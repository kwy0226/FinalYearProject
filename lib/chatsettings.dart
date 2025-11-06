import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class ChatSettingsPage extends StatefulWidget {
  final String chatId;
  const ChatSettingsPage({super.key, required this.chatId});

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  final _nameCtrl = TextEditingController();
  final _backgroundCtrl = TextEditingController();
  final picker = ImagePicker();

  late DatabaseReference _charRef;
  late String _uid;
  String? _selectedAvatar;
  String _gender = "unspecified";

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError("No user signed in.");
    _uid = user.uid;

    _charRef = FirebaseDatabase.instance
        .ref("character/$_uid/${widget.chatId}");

    _loadData();
  }

  Future<void> _loadData() async {
    final snap = await _charRef.get();
    if (!snap.exists) return;

    setState(() {
      _nameCtrl.text = (snap.child("aiName").value ?? "").toString();
      _gender = (snap.child("aiGender").value ?? "unspecified").toString();

      final bg = (snap.child("aiBackground").value ?? "").toString();
      String pure = bg;

            if (bg.contains("[补全资料]")) {
               pure = bg.split("[补全资料]").first.trim();
             }

      _backgroundCtrl.text = pure;

      _selectedAvatar = snap.child("selectedAvatar").value?.toString();
    });
  }


  /// ✅ Pick avatar from assets
  Future<void> _pickAvatar() async {
    final avatars = [
      "assets/images/Man 1.png",
      "assets/images/Man 2.png",
      "assets/images/Man 3.png",
      "assets/images/Man 4.png",
      "assets/images/Man 5.png",
      "assets/images/Women 1.png",
      "assets/images/Women 2.png",
      "assets/images/Women 3.png",
      "assets/images/Women 4.png",
      "assets/images/Women 5.png",
    ];

    showModalBottomSheet(
      context: context,
      builder: (c) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: avatars.length,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () async {
            Navigator.pop(context);
            setState(() => _selectedAvatar = avatars[i]);
            await _charRef.update({"selectedAvatar": avatars[i]});
          },
          child: CircleAvatar(
            radius: 40,
            backgroundImage: AssetImage(avatars[i]),
          ),
        ),
      ),
    );
  }

  /// ✅ Save name, gender, background text
  Future<void> _saveInfo() async {
    final snap = await _charRef.get();
    String original = (snap.child("aiBackground").value ?? "").toString();

    String extra = "";
    if (original.contains("[补全资料]")) {
      extra = original.substring(original.indexOf("[补全资料]")).trim();
    }

    String merged = "${_backgroundCtrl.text.trim()} $extra".trim();

    await _charRef.child("aiBackground").set(merged);

    await _charRef.update({
      "aiName": _nameCtrl.text.trim(),
      "aiGender": _gender,
      "updatedAt": ServerValue.timestamp,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Saved successfully")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 1,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Chat Settings",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 10),

          /// Avatar
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: CircleAvatar(
                radius: 55,
                backgroundColor: Colors.grey[200],
                backgroundImage: _selectedAvatar != null
                    ? AssetImage(_selectedAvatar!)
                    : const AssetImage("assets/images/default.jpeg"),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Center(child: Text("Tap image to change avatar")),

          const SizedBox(height: 25),

          /// Name
          const Text("Name:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: "Enter AI name",
            ),
          ),

          const SizedBox(height: 25),

          /// Gender
          const Text("Gender:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Row(
            children: [
              Radio<String>(
                value: "male",
                groupValue: _gender,
                onChanged: (v) => setState(() => _gender = v!),
              ),
              const Text("Male"),

              Radio<String>(
                value: "female",
                groupValue: _gender,
                onChanged: (v) => setState(() => _gender = v!),
              ),
              const Text("Female"),
            ],
          ),

          const SizedBox(height: 25),

          /// Background text
          const Text("Background:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          TextField(
            controller: _backgroundCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: "Enter AI background",
            ),
          ),

          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: _saveInfo,
            child: const Text("Save Info"),
          ),
        ],
      ),
    );
  }
}
