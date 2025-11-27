import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  // BASIC CONFIGURATION
  // Using Dio to handle network calls to my Cloud Run backend.
  static const String kApiBase =
      "https://fyp-project-758812934986.asia-southeast1.run.app";

  final Dio _dio = Dio(BaseOptions(
    baseUrl: kApiBase,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {"Content-Type": "application/json"},
  ));

  // Text input controller for user messages
  final TextEditingController _textCtrl = TextEditingController();

  // Scroll controller to auto-scroll to latest chat messages
  final ScrollController _scrollCtrl = ScrollController();

  // Firebase references
  late final String _uid;
  late final DatabaseReference _characterRef;
  late final DatabaseReference _chatRef;
  late final DatabaseReference _messagesRef;
  late final DatabaseReference _metaRef;

  // AI Character (customizable)
  String _aiName = "Companion";
  String _aiGender = "unspecified";
  String _aiBackground = "";
  // _aiAvatar can be an asset path (e.g. "assets/images/.."), an http(s) URL, or a data:base64 URI
  String _aiAvatar = "assets/images/default_avatar.png";

  // User photo (Base64)
  String? _userPhotoB64;

  // Audio recorder and player
  final rec.AudioRecorder _recorder = rec.AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  // Recording state
  bool _recording = false;
  Timer? _timer;
  int _recordDuration = 0;

  // Stream for Firebase messages (used by StreamBuilder)
  Stream<DatabaseEvent>? _msgStream;

  // Additional subscriptions to detect aiReply and character changes
  StreamSubscription<DatabaseEvent>? _msgAddedSub;
  StreamSubscription<DatabaseEvent>? _msgChangedSub;
  StreamSubscription<DatabaseEvent>? _characterSub;

  @override
  void initState() {
    super.initState();
    // Get current logged-in user UID
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError("User not signed in.");
    _uid = user.uid;

    // Initialize Firebase paths for character and chat history
    _characterRef =
        FirebaseDatabase.instance.ref("character/$_uid/${widget.chatId}");
    _chatRef =
        FirebaseDatabase.instance.ref("chathistory/$_uid/${widget.chatId}");
    _messagesRef = _chatRef.child("messages");
    _metaRef = _chatRef.child("meta");

    // Load essential data when chat opens:
    _subscribeCharacterChanges(); // - keep meta.aiName in sync
    _subscribeMessageEvents(); // - listen for aiReply additions/changes
    _ensureCharacter(); // - ensure AI profile exists (but do NOT restore archived meta)
    _loadAvatar(); // - load AI avatar (meta -> character)
    _loadUserPhoto(); // - load user profile photo

    // Prepare stream for messages listing
    _subscribeMessages(); // sets _msgStream which StreamBuilder uses
  }

  @override
  void dispose() {
    // Clean up all controllers, timers and subscriptions
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _recorder.dispose();
    _player.dispose();
    _timer?.cancel();

    _msgAddedSub?.cancel();
    _msgChangedSub?.cancel();
    _characterSub?.cancel();

    super.dispose();
  }

  // FIREBASE INITIALIZATION
  // INITIALIZING AI CHARACTER (FIRST-TIME SETUP)
  //
  // NOTE: Do NOT recreate meta if the chat has been archived (meta removed).
  // This prevents archived chat nodes from being resurrected when user opens ChatBox.
  Future<void> _ensureCharacter() async {
    final charSnap = await _characterRef.get();
    final metaSnap = await _metaRef.get();

    // If meta is missing, this chat is considered archived. DO NOT re-create meta.
    if (!metaSnap.exists) {
      // We avoid creating meta or writing to meta — prevents accidental "revival".
      // If we still want to allow a user to unarchive from UI, do that explicitly elsewhere.
      return;
    }

    // If character is missing but meta exists, we create character using meta.aiName if available.
    if (!charSnap.exists) {
      // Use aiName from meta if present
      final aiNameFromMeta = metaSnap.child('aiName').value?.toString();
      final initialAiName = aiNameFromMeta?.isNotEmpty == true ? aiNameFromMeta! : _aiName;

      // Create character node but do NOT change meta's timestamps here beyond what's already present.
      await _characterRef.set({
        "aiName": initialAiName,
        "aiGender": _aiGender,
        "aiBackground": _aiBackground,
        "createdAt": ServerValue.timestamp,
        "updatedAt": ServerValue.timestamp,
      });

      // Update local state
      if (!mounted) return;
      setState(() {
        _aiName = initialAiName;
      });
    } else {
      // Load existing character settings
      final snap = charSnap;
      if (snap.exists) {
        if (!mounted) return;
        setState(() {
          _aiName = (snap.child("aiName").value ?? "Companion").toString();
          _aiGender = (snap.child("aiGender").value ?? "unspecified").toString();
          _aiBackground = (snap.child("aiBackground").value ?? "").toString();
        });
      }
    }
  }

  // LOAD AI AVATAR
  //
  // Priority:
  // 1) meta.selectedAvatar (if exists)
  // 2) character.selectedAvatar (if exists) — and write it to meta for future sync
  Future<void> _loadAvatar() async {
    final metaSnap = await _metaRef.get();
    if (metaSnap.exists && metaSnap.child("selectedAvatar").exists) {
      final avatarVal = metaSnap.child("selectedAvatar").value.toString();
      if (avatarVal.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _aiAvatar = avatarVal;
        });
        return;
      }
    }

    // If meta doesn't have it, check character node
    final charSnap = await _characterRef.get();
    if (charSnap.exists && charSnap.child("selectedAvatar").exists) {
      final avatarVal = charSnap.child("selectedAvatar").value.toString();
      if (avatarVal.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _aiAvatar = avatarVal;
        });

        // Also write to meta for sync next time (but only if meta exists; we want to avoid resurrecting archived chats)
        final metaSnap2 = await _metaRef.get();
        if (metaSnap2.exists) {
          await _metaRef.update({"selectedAvatar": _aiAvatar});
        }
      }
    }
  }

  // LOAD USER PHOTO
  Future<void> _loadUserPhoto() async {
    final snap = await FirebaseDatabase.instance.ref("users/$_uid").get();
    if (snap.child("photoBase64").exists) {
      setState(() {
        _userPhotoB64 = snap.child("photoBase64").value.toString();
      });
    }
  }

  // SUBSCRIBE TO CHAT MESSAGES IN REALTIME (used by StreamBuilder)
  void _subscribeMessages() {
    _msgStream = _messagesRef.orderByChild("createdAt").onValue;
  }

  // SUBSCRIBE TO NEW MESSAGE EVENTS (child_added and child_changed)
  // We use these listeners to detect when the backend writes an aiReply
  // (either as a new child or via update). When aiReply appears, we update meta.lastMessage & meta.updatedAt.
  void _subscribeMessageEvents() {
    // child added event: a new user message was pushed
    _msgAddedSub = _messagesRef.onChildAdded.listen((event) async {
      final snap = event.snapshot;
      if (snap.exists) {
        // If the newly added node already contains aiReply (rare), update meta
        if (snap.child('aiReply').exists) {
          final aiContent = snap.child('aiReply/content').value?.toString() ?? '';
          if (aiContent.isNotEmpty) {
            await _metaRef.update({
              "lastMessage": aiContent,
              "updatedAt": ServerValue.timestamp,
            });
          }
        }
      }
    });

    // child changed event: backend may set aiReply on an existing message node
    _msgChangedSub = _messagesRef.onChildChanged.listen((event) async {
      final snap = event.snapshot;
      if (snap.exists && snap.child('aiReply').exists) {
        final aiContent = snap.child('aiReply/content').value?.toString() ?? '';
        if (aiContent.isNotEmpty) {
          await _metaRef.update({
            "lastMessage": aiContent,
            "updatedAt": ServerValue.timestamp,
          });
        }
      }
    });
  }

  // SUBSCRIBE TO CHARACTER CHANGES
  // Keep meta.aiName in sync when user edits AI name in ChatSettings.
  void _subscribeCharacterChanges() {
    _characterSub = _characterRef.onValue.listen((event) async {
      final snap = event.snapshot;
      if (!snap.exists) return;

      final newName = snap.child('aiName').value?.toString();
      if (newName != null && newName.isNotEmpty) {
        // Update local state so AppBar shows latest name
        if (!mounted) return;
        setState(() {
          _aiName = newName;
        });

        // Update meta.aiName if meta exists (do not create meta if it's missing)
        final metaSnap = await _metaRef.get();
        if (metaSnap.exists) {
          await _metaRef.update({
            "aiName": newName,
            "updatedAt": ServerValue.timestamp,
          });
        }
      }

      // Also check selectedAvatar in character and sync to meta if meta exists
      final charAvatar = snap.child('selectedAvatar').value?.toString();
      if (charAvatar != null && charAvatar.isNotEmpty) {
        final metaSnap = await _metaRef.get();
        if (metaSnap.exists) {
          await _metaRef.update({"selectedAvatar": charAvatar});
          if (!mounted) return;
          setState(() {
            _aiAvatar = charAvatar;
          });
        }
      }
    });
  }

  // SEND TEXT
  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();

    // Create new message node
    final msgRef = _messagesRef.push(); // Add one more message
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    await msgRef.set({
      "role": "user",
      "type": "text",
      "content": text, // Store message content in the database
      "createdAt": timestamp, // Timestamps facilitate sorting
    });

    // Update chat meta (last message preview) to user's message right away
    // The message will be replaced/updated by the AI reply when backend responds (listener will update meta again)
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
      // If backend fails, show placeholder AI reply and update meta
      final placeholder = "(...)";
      await msgRef.update({
        "aiReply": {
          "role": "assistant",
          "type": "text",
          "content": placeholder,
          "createdAt": ServerValue.timestamp,
        }
      });
      await _metaRef.update({
        "lastMessage": placeholder,
        "updatedAt": ServerValue.timestamp,
      });
    }
  }

  // SEND AUDIO (voice)
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
      final placeholder = "(...)";
      await msgRef.update({
        "aiReply": {
          "role": "assistant",
          "type": "text",
          "content": placeholder,
          "createdAt": ServerValue.timestamp,
        }
      });
      await _metaRef.update({
        "lastMessage": placeholder,
        "updatedAt": ServerValue.timestamp,
      });
    }
  }

  // MAIN UI BUILD
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder(
          stream: _characterRef.onValue,
          builder: (context, snapshot) {
            String name = _aiName;
            if (snapshot.hasData && snapshot.data!.snapshot.exists) {
              name = (snapshot.data!.snapshot.child("aiName").value ?? "Companion")
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

  // BUILD CHAT MESSAGE LIST
  Widget _buildMessages() {
    return StreamBuilder(
      stream: _msgStream, // Listen from Firebase Realtime Database
      builder: (c, snap) {
        final messages = <Map<String, dynamic>>[];

        if (snap.hasData) {
          final data = snap.data!.snapshot;

          for (final m in data.children) {
            // Each push key usually represents a user message node.
            final userMsgMap = <String, dynamic>{
              "role": m.child("role").value,
              "type": m.child("type").value,
              "content": m.child("content").value,
              "localPath": m.child("localPath").value,
              "createdAt": m.child("createdAt").value,
            };

            // Convert createdAt to int if possible
            final createdAtUser = (userMsgMap["createdAt"] is int)
                ? userMsgMap["createdAt"] as int
                : int.tryParse(userMsgMap["createdAt"]?.toString() ?? "0") ?? 0;

            userMsgMap["createdAt"] = createdAtUser;
            messages.add(userMsgMap);

            // If aiReply exists inside this message node, treat it as a separate message item
            if (m.child("aiReply").exists) {
              final aiCreatedAtRaw = m.child("aiReply/createdAt").value;
              final aiCreatedAt = (aiCreatedAtRaw is int)
                  ? aiCreatedAtRaw
                  : int.tryParse(aiCreatedAtRaw?.toString() ?? "0") ?? 0;

              messages.add({
                "role": m.child("aiReply/role").value,
                "type": m.child("aiReply/type").value,
                "content": m.child("aiReply/content").value,
                "createdAt": aiCreatedAt,
              });
            }
          }

          // IMPORTANT: Sort messages by createdAt ascending so order is correct
          messages.sort((a, b) {
            final aTs = (a["createdAt"] is int) ? a["createdAt"] as int : 0;
            final bTs = (b["createdAt"] is int) ? b["createdAt"] as int : 0;
            return aTs.compareTo(bTs);
          });
        }

        // Auto-scroll to newest message after widget build
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

            // Voice message bubble
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
              // Text message bubble
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

  // MESSAGE ROW WITH AVATAR + BUBBLE
  Widget _chatRow({required bool isMe, required Widget child}) {
    final avatar = isMe
        ? (_userPhotoB64 == null
        ? const CircleAvatar(radius: 16, child: Icon(Icons.person))
        : CircleAvatar(
      radius: 16,
      backgroundImage: MemoryImage(
        // The stored Base64 might include "data:...;base64," prefix; handle it.
        base64Decode(_userPhotoB64!.split(',').last),
      ),
    ))
        : _buildAiAvatarCircle();

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

  // Helper to produce AI avatar CircleAvatar supporting assets, network and data: URIs
  Widget _buildAiAvatarCircle() {
    final provider = _imageProviderFromString(_aiAvatar);
    if (provider != null) {
      return CircleAvatar(radius: 16, backgroundImage: provider);
    } else {
      // Fallback: initial letter avatar using _aiName
      final initial = _aiName.isNotEmpty ? _aiName[0].toUpperCase() : 'C';
      return CircleAvatar(
        radius: 16,
        backgroundColor: const Color(0xFFDECDBE),
        child: Text(
          initial,
          style: const TextStyle(
            color: Color(0xFF5E4631),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
  }

  // Convert a string to an ImageProvider:
  // - if starts with http(s) -> NetworkImage
  // - if starts with 'data:' -> decode base64 to MemoryImage
  // - otherwise assume it's an asset path -> AssetImage
  ImageProvider? _imageProviderFromString(String path) {
    try {
      if (path.isEmpty) return null;
      final trimmed = path.trim();
      if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
        return NetworkImage(trimmed);
      }
      if (trimmed.startsWith("data:")) {
        // data URI like: data:image/png;base64,AAAABBBB...
        final parts = trimmed.split(',');
        if (parts.length == 2) {
          final b64 = parts[1];
          final bytes = base64.decode(b64);
          return MemoryImage(bytes);
        }
        return null;
      }
      // Default: treat as local asset path
      return AssetImage(trimmed);
    } catch (_) {
      return null;
    }
  }

  // CHAT BUBBLE (GREEN FOR USER, WHITE FOR AI)
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

  // TEXT INPUT BAR + SEND ICON
  Widget _buildInputBar() {
    return SafeArea(
      child: Row(children: [
        IconButton(icon: const Icon(Icons.mic, color: Colors.brown), onPressed: _startRecording),
        Expanded(
            child: TextField(
              controller: _textCtrl,
              decoration: const InputDecoration(hintText: "Type a message...", border: OutlineInputBorder()),
              onSubmitted: (_) => _sendText(),
            )),
        IconButton(icon: const Icon(Icons.send, color: Colors.brown), onPressed: _sendText),
      ]),
    );
  }

  // RECORDING BAR UI
  Widget _buildRecordingBar() {
    return Container(
      color: Colors.red[50],
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Text("Recording: $_recordDuration s"),
        const Spacer(),
        IconButton(icon: const Icon(Icons.stop, color: Colors.red), onPressed: () => _stopRecording()),
        IconButton(icon: const Icon(Icons.delete, color: Colors.grey), onPressed: () => _stopRecording(cancel: true)),
      ]),
    );
  }

  // START AUDIO RECORDING
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

  // ===================== AI SETTINGS POPUP =====================
  Future<Map<String, String>?> _askForAiSettings(BuildContext context) async {
    final TextEditingController nameCtrl = TextEditingController(text: _aiName);
    final TextEditingController bgCtrl = TextEditingController(text: _aiBackground);
    String gender = _aiGender;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Set your AI character"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "AI Name")),
          DropdownButtonFormField<String>(
            value: gender,
            items: const [
              DropdownMenuItem(value: "unspecified", child: Text("Unspecified")),
              DropdownMenuItem(value: "male", child: Text("Male")),
              DropdownMenuItem(value: "female", child: Text("Female")),
            ],
            onChanged: (v) => gender = v ?? "unspecified",
          ),
          TextField(controller: bgCtrl, maxLines: 3, decoration: const InputDecoration(labelText: "AI Background")),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
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
