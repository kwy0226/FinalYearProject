import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as rec;
import 'package:audioplayers/audioplayers.dart';

import 'background_widget.dart';
import 'chatsettings.dart';

class ChatBoxPage extends StatefulWidget {
  const ChatBoxPage({super.key, required this.chatId});
  final String chatId;

  @override
  State<ChatBoxPage> createState() => _ChatBoxPageState();
}

class _ChatBoxPageState extends State<ChatBoxPage> {
  // ===================== BASIC CONFIG =====================
  static const String kApiBase =
      "https://fyp-project-758812934986.asia-southeast1.run.app";

  final Dio _dio = Dio(BaseOptions(
    baseUrl: kApiBase,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {"Content-Type": "application/json"},
  ));

  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  late final String _uid;
  late final DatabaseReference _characterRef;
  late final DatabaseReference _chatRef;
  late final DatabaseReference _messagesRef;
  late final DatabaseReference _metaRef;

  String _aiName = "Companion";
  String _aiGender = "unspecified";
  String _aiBackground = "";
  String _aiAvatar = "assets/images/default_avatar.png";
  String? _userPhotoB64;

  final rec.AudioRecorder _recorder = rec.AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _recording = false;
  Timer? _timer;
  int _recordDuration = 0;
  Stream<DatabaseEvent>? _msgStream;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError("User not signed in.");
    _uid = user.uid;

    _characterRef =
        FirebaseDatabase.instance.ref("character/$_uid/${widget.chatId}");
    _chatRef =
        FirebaseDatabase.instance.ref("chathistory/$_uid/${widget.chatId}");
    _messagesRef = _chatRef.child("messages");
    _metaRef = _chatRef.child("meta");

    _ensureCharacter();
    _loadAvatar();
    _loadUserPhoto();
    _subscribeMessages();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _recorder.dispose();
    _player.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // ===================== FIREBASE INITIALIZATION =====================

  /// Create default AI character info if not exists
  Future<void> _ensureCharacter() async {
    final snap = await _characterRef.get();
    if (!mounted) return;

    if (!snap.exists) {
      final settings = await _askForAiSettings(context);
      if (settings != null) {
        setState(() {
          _aiName = settings["name"]!;
          _aiGender = settings["gender"]!;
          _aiBackground = settings["background"]!;
        });

        await _characterRef.set({
          "aiName": _aiName,
          "aiGender": _aiGender,
          "aiBackground": _aiBackground,
          "createdAt": ServerValue.timestamp,
          "updatedAt": ServerValue.timestamp,
        });

        await _metaRef.update({
          "aiName": _aiName,
          "updatedAt": ServerValue.timestamp,
        });
      }
    } else {
      setState(() {
        _aiName = (snap.child("aiName").value ?? "Companion").toString();
        _aiGender = (snap.child("aiGender").value ?? "unspecified").toString();
        _aiBackground = (snap.child("aiBackground").value ?? "").toString();
      });
    }
  }

  /// Load AI avatar from Firebase meta
  Future<void> _loadAvatar() async {
    // First check meta
    final metaSnap = await _metaRef.get();
    if (metaSnap.child("selectedAvatar").exists) {
      setState(() {
        _aiAvatar = metaSnap.child("selectedAvatar").value.toString();
      });
      return;
    }

    // If meta doesn't have it, check character node
    final charSnap = await _characterRef.get();
    if (charSnap.child("selectedAvatar").exists) {
      setState(() {
        _aiAvatar = charSnap.child("selectedAvatar").value.toString();
      });

      // Also write to meta for sync next time
      await _metaRef.update({"selectedAvatar": _aiAvatar});
    }
  }

  /// Load user's own avatar (photoBase64)
  Future<void> _loadUserPhoto() async {
    final snap = await FirebaseDatabase.instance.ref("users/$_uid").get();
    if (snap.child("photoBase64").exists) {
      setState(() {
        _userPhotoB64 = snap.child("photoBase64").value.toString();
      });
    }
  }

  /// Subscribe Firebase messages
  void _subscribeMessages() {
    _msgStream = _messagesRef.orderByChild("createdAt").onValue;
  }

  // ===================== SEND TEXT =====================
  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();

    final msgRef = _messagesRef.push(); // Add one more message
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    await msgRef.set({
      "role": "user",
      "type": "text",
      "content": text, // Store message content in the database
      "createdAt": timestamp, // Timestamps facilitate sorting
    });

    await _metaRef.update({
      "lastMessage": text,
      "updatedAt": ServerValue.timestamp,
    });

    // Send to backend to generate AI reply
    try {
      await _dio.post("/chat/reply", data: {
        "message": text,
        "aiName": _aiName,
        "aiGender": _aiGender,
        "aiBackground": _aiBackground,
        "uid": _uid,
        "chatId": widget.chatId,
        "msgId": msgRef.key,
      });
    } catch (_) {
      await msgRef.update({
        "aiReply": {
          "role": "assistant",
          "type": "text",
          "content": "(...)",
          "createdAt": ServerValue.timestamp,
        }
      });
    }
  }

  // ===================== UI =====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder(
          stream: _characterRef.onValue,
          builder: (context, snapshot) {
            String name = _aiName;
            if (snapshot.hasData && snapshot.data!.snapshot.exists) {
              name =
                  (snapshot.data!.snapshot.child("aiName").value ?? "Companion")
                      .toString();
            }
            return Text(name,
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold));
          },
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ChatSettingsPage(chatId: widget.chatId)),
              ).then((_) => _loadAvatar());
            },
          ),
        ],
      ),

      body: Stack(children: [
        const AppBackground(),

        Column(children: [
          Expanded(child: _buildMessages()),
          _recording ? _buildRecordingBar() : _buildInputBar(),
        ])
      ]),
    );
  }

  // ===================== CHAT LIST + AVATARS =====================
  Widget _buildMessages() {
    return StreamBuilder(
      stream: _msgStream, // Listen from Firebase Realtime Database
      builder: (c, snap) {
        final messages = <Map<String, dynamic>>[];

        if (snap.hasData) {
          final data = snap.data!.snapshot;

          for (final m in data.children) {
            // Read messages sent by the user
            messages.add({
              "role": m.child("role").value,
              "type": m.child("type").value,
              "content": m.child("content").value,
              "localPath": m.child("localPath").value,
              "createdAt": m.child("createdAt").value,
            });

            // ai reply
            if (m.child("aiReply").exists) {
              messages.add({
                "role": m.child("aiReply/role").value,
                "type": m.child("aiReply/type").value,
                "content": m.child("aiReply/content").value,
                "createdAt": m.child("aiReply/createdAt").value,
              });
            }
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(
              _scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });

        return ListView.builder(
          controller: _scrollCtrl,
          itemCount: messages.length,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemBuilder: (c, i) {
            final msg = messages[i];
            final isMe = msg["role"] == "user";
            final type = msg["type"];
            Widget contentWidget;

            // Voice message
            if (type == "audio") {
              final path = msg["localPath"]?.toString();
              contentWidget = Row(children: [
                IconButton(
                    icon: const Icon(Icons.play_arrow, color: Colors.black),
                    onPressed: () async {
                      if (path != null && File(path).existsSync()) {
                        await _player.play(DeviceFileSource(path));
                      }
                    }),
                Text((msg["content"] ?? "").toString(),
                    style: const TextStyle(color: Colors.black)),
              ]);
            } else {
              contentWidget = Text(
                (msg["content"] ?? '').toString(),
                style: TextStyle(
                    color: isMe ? Colors.white : Colors.black, fontSize: 15),
              );
            }

            return _chatRow(isMe: isMe, child: contentWidget);
          },
        );
      },
    );
  }

  /// Single message row with avatar
  Widget _chatRow({required bool isMe, required Widget child}) {
    final avatar = isMe
        ? (_userPhotoB64 == null
        ? const CircleAvatar(radius: 16, child: Icon(Icons.person))
        : CircleAvatar(
        radius: 16,
        backgroundImage: MemoryImage(
          base64Decode(_userPhotoB64!.split(',').last),
        )))
        : CircleAvatar(radius: 16, backgroundImage: AssetImage(_aiAvatar));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) avatar,
          if (!isMe) const SizedBox(width: 8),
          Flexible(child: _bubble(isMe: isMe, child: child)),
          if (isMe) const SizedBox(width: 8),
          if (isMe) avatar,
        ],
      ),
    );
  }

  /// Chat bubble UI
  Widget _bubble({required bool isMe, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? Colors.green[400] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 3,
              offset: const Offset(0, 1))
        ],
      ),
      child: child,
    );
  }

  // ===================== INPUT BAR =====================
  Widget _buildInputBar() {
    return SafeArea(
      child: Row(children: [
        IconButton(
            icon: const Icon(Icons.mic, color: Colors.brown),
            onPressed: _startRecording),
        Expanded(
            child: TextField(
              controller: _textCtrl,
              decoration: const InputDecoration(
                  hintText: "Type a message...", border: OutlineInputBorder()),
              onSubmitted: (_) => _sendText(),
            )),
        IconButton(
            icon: const Icon(Icons.send, color: Colors.brown),
            onPressed: _sendText),
      ]),
    );
  }

  // ===================== RECORDING BAR =====================
  Widget _buildRecordingBar() {
    return Container(
      color: Colors.red[50],
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Text("Recording: $_recordDuration s"),
        const Spacer(),
        IconButton(
            icon: const Icon(Icons.stop, color: Colors.red),
            onPressed: () => _stopRecording()),
        IconButton(
            icon: const Icon(Icons.delete, color: Colors.grey),
            onPressed: () => _stopRecording(cancel: true)),
      ]),
    );
  }

  // ===================== AUDIO FUNCTIONS =====================
  Future<void> _startRecording() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Microphone permission required")),
      );
      return;
    }

    Directory? baseDir = await getDownloadsDirectory();
    baseDir ??= await getApplicationDocumentsDirectory();
    final dir = Directory("${baseDir.path}/ChatVoices/$_uid");
    if (!(await dir.exists())) await dir.create(recursive: true);

    final path = "${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav";

    await _recorder.start(
      rec.RecordConfig(
          encoder: rec.AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );

    setState(() {
      _recording = true;
      _recordDuration = 0;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordDuration++);
    });
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    _timer?.cancel();
    final path = await _recorder.stop();
    if (!mounted) return;

    if (cancel || path == null) {
      setState(() => _recording = false);
      return;
    }

    setState(() => _recording = false);
    await _sendVoice(path, _recordDuration);
  }

  Future<void> _sendVoice(String filePath, int duration) async {
    final msgRef = _messagesRef.push();

    await msgRef.set({
      "role": "user",
      "type": "audio",
      "content": "(voice $duration s)",
      "localPath": filePath,
      "createdAt": DateTime.now().millisecondsSinceEpoch,
    });

    await _metaRef.update({
      "lastMessage": "(voice)",
      "updatedAt": ServerValue.timestamp,
    });

    try {
      final bytes = await File(filePath).readAsBytes();
      final String b64 = base64.encode(bytes);

      await _dio.post("/audio/process", data: {
        "wav_base64": "data:audio/wav;base64,$b64",
        "uid": _uid,
        "chatId": widget.chatId,
        "msgId": msgRef.key,
      });
    } catch (_) {
      await msgRef.update({
        "aiReply": {
          "role": "assistant",
          "type": "text",
          "content": "(...)",
          "createdAt": ServerValue.timestamp,
        }
      });
    }
  }

  // ===================== AI SETTINGS POPUP =====================
  Future<Map<String, String>?> _askForAiSettings(BuildContext context) async {
    final TextEditingController nameCtrl =
    TextEditingController(text: _aiName);
    final TextEditingController bgCtrl =
    TextEditingController(text: _aiBackground);
    String gender = _aiGender;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Set your AI character"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "AI Name")),
          DropdownButtonFormField<String>(
            value: gender,
            items: const [
              DropdownMenuItem(
                  value: "unspecified", child: Text("Unspecified")),
              DropdownMenuItem(value: "male", child: Text("Male")),
              DropdownMenuItem(value: "female", child: Text("Female")),
            ],
            onChanged: (v) => gender = v ?? "unspecified",
          ),
          TextField(
              controller: bgCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: "AI Background")),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () {
                Navigator.pop(c, {
                  "name": nameCtrl.text.trim(),
                  "gender": gender,
                  "background": bgCtrl.text.trim(),
                });
              },
              child: const Text("Confirm")),
        ],
      ),
    );
  }
}
