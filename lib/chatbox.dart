// lib/chatbox.dart
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

class ChatBoxPage extends StatefulWidget {
  const ChatBoxPage({super.key, required this.chatId});
  final String chatId;

  @override
  State<ChatBoxPage> createState() => _ChatBoxPageState();
}

class _ChatBoxPageState extends State<ChatBoxPage> {
  static const String kApiBase =
      "https://fyp-project-758812934986.asia-southeast1.run.app";

  final _dio = Dio(BaseOptions(
    baseUrl: kApiBase,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {"Content-Type": "application/json"},
  ));

  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  late final String _uid;
  late final DatabaseReference _characterRef;
  late final DatabaseReference _chatRef;
  late final DatabaseReference _messagesRef;
  late final DatabaseReference _metaRef;

  String _aiName = "Companion";
  String _aiGender = "unspecified";
  String _aiBackground = "";

  final rec.AudioRecorder _recorder = rec.AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _recording = false;
  Timer? _timer;
  int _recordDuration = 0;
  String? _recordFilePath;

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

  /// 确保角色信息
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

  Future<Map<String, String>?> _askForAiSettings(BuildContext ctx) async {
    final nameCtrl = TextEditingController(text: _aiName);
    final bgCtrl = TextEditingController(text: _aiBackground);
    String gender = _aiGender;

    return showDialog<Map<String, String>>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Set your AI character"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: "AI Name"),
          ),
          DropdownButtonFormField<String>(
            value: gender,
            items: const [
              DropdownMenuItem(value: "unspecified", child: Text("Unspecified")),
              DropdownMenuItem(value: "male", child: Text("Male")),
              DropdownMenuItem(value: "female", child: Text("Female")),
            ],
            onChanged: (v) => gender = v ?? "unspecified",
          ),
          TextField(
            controller: bgCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: "AI Background"),
          ),
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

  void _subscribeMessages() {
    _msgStream = _messagesRef.orderByChild("createdAt").onValue;
  }

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();

    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final msgRef = _messagesRef.push();
    await msgRef.set({
      "role": "user",
      'createdAt': timestamp,  // ✅ 加这一行
      "type": "text",
      "content": text,
      "createdAt": ServerValue.timestamp,
    });

    await _metaRef.update({
      "lastMessage": text,
      "updatedAt": ServerValue.timestamp,
    });

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
          "content": "(.......)",
          "role": "assistant",
          "type": "text",
          "createdAt": ServerValue.timestamp,
        }
      });
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DatabaseEvent>(
          stream: _characterRef.onValue,
          builder: (context, snapshot) {
            String name = _aiName;
            if (snapshot.hasData && snapshot.data!.snapshot.exists) {
              name = (snapshot.data!.snapshot.child("aiName").value ?? "Companion").toString();
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

  Widget _buildMessages() {
    return StreamBuilder<DatabaseEvent>(
      stream: _msgStream,
      builder: (c, snap) {
        final messages = <Map<String, dynamic>>[];
        if (snap.hasData) {
          final data = snap.data!.snapshot;
          for (final m in data.children) {
            messages.add({
              "key": m.key,
              "role": m.child("role").value,
              "content": m.child("content").value,
              "type": m.child("type").value,
              "createdAt": m.child("createdAt").value,
              "localPath": m.child("localPath").value,
            });
            if (m.child("aiReply").exists) {
              messages.add({
                "key": "${m.key}_ai",
                "role": m.child("aiReply/role").value,
                "content": m.child("aiReply/content").value,
                "type": m.child("aiReply/type").value,
                "createdAt": m.child("aiReply/createdAt").value,
              });
            }
          }
        }
        return ListView.builder(
          controller: _scrollCtrl,
          itemCount: messages.length,
          itemBuilder: (c, i) {
            final m = messages[i];
            final isMe = m["role"] == "user";
            final type = m["type"];
            Widget child;
            if (type == "audio") {
              final localPath = m["localPath"]?.toString();
              child = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    onPressed: () async {
                      if (localPath != null &&
                          File(localPath).existsSync()) {
                        await _player.play(DeviceFileSource(localPath));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("音频文件不存在")),
                        );
                      }
                    },
                  ),
                  Text((m["content"] ?? "").toString(),
                      style: const TextStyle(color: Colors.white)),
                ],
              );
            } else {
              child = Text(
                (m["content"] ?? "").toString(),
                style: const TextStyle(color: Colors.white),
              );
            }
            return GestureDetector(
              onLongPress: () => _messagesRef.child(m["key"]).remove(),
              child: _bubble(isMe: isMe, child: child),
            );
          },
        );
      },
    );
  }

  Widget _bubble({required bool isMe, required Widget child}) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? Colors.green : Colors.blueGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.mic, color: Colors.brown),
          onPressed: _startRecording,
        ),
        Expanded(
          child: TextField(
            controller: _textCtrl,
            decoration: const InputDecoration(
                hintText: "Type a message...",
                border: OutlineInputBorder()),
            onSubmitted: (_) => _sendText(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.send, color: Colors.brown),
          onPressed: _sendText,
        ),
      ]),
    );
  }

  Widget _buildRecordingBar() {
    return Container(
      color: Colors.red[50],
      padding: const EdgeInsets.all(12),
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

  // ----------------- AUDIO -----------------
  Future<void> _startRecording() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required')),
        );
      }
      return;
    }

    // 自定义目录: Download/ChatVoices/{uid}
    Directory? baseDir = await getDownloadsDirectory();
    baseDir ??= await getApplicationDocumentsDirectory(); // fallback iOS
    final userDir = Directory("${baseDir.path}/ChatVoices/$_uid");
    if (!(await userDir.exists())) {
      await userDir.create(recursive: true);
    }

    final path =
        "${userDir.path}/chat_${DateTime.now().millisecondsSinceEpoch}.wav";

    await _recorder.start(
      rec.RecordConfig(
        encoder: rec.AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    setState(() {
      _recording = true;
      _recordDuration = 0;
      _recordFilePath = path;
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

    setState(() {
      _recording = false;
      _recordFilePath = path;
    });
    await _sendVoice(path, _recordDuration);
  }

  Future<void> _sendVoice(String filePath, int duration) async {
    final msgRef = _messagesRef.push();
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    await msgRef.set({
      "role": "user",
      "type": "audio",
      "createdAt": timestamp,  // ✅ 加这一行
      "content": "(voice $duration s)",
      "localPath": filePath, // ✅ 存储本地路径
    });

    await _metaRef.update({
      "lastMessage": "(voice)",
      "updatedAt": ServerValue.timestamp,
    });

    try {
      final bytes = await File(filePath).readAsBytes();
      final b64 = base64.encode(bytes);

      await _dio.post("/audio/process", data: {
        "wav_base64": "data:audio/wav;base64,$b64",
        "uid": _uid,
        "chatId": widget.chatId,
        "msgId": msgRef.key,
      });
    } catch (e) {
      await msgRef.update({
        "aiReply": {
          "content": "(.......)",
          "role": "assistant",
          "type": "text",
          "createdAt": ServerValue.timestamp,
        }
      });
    }
  }
}
