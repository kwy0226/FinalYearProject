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
  // Text controllers for AI name and background description
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _backgroundCtrl = TextEditingController();

  final picker = ImagePicker();

  late DatabaseReference _charRef;
  late DatabaseReference _metaRef;
  late String _uid;

  String? _selectedAvatar;
  String _gender = "unspecified";

  @override
  void initState() {
    super.initState();

    // Get authenticated user UID
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError("No user signed in.");
    _uid = user.uid;

    // Character settings path: character/<uid>/<chatId>
    _charRef =
        FirebaseDatabase.instance.ref("character/$_uid/${widget.chatId}");

    // Meta section used by chat list UI
    _metaRef = FirebaseDatabase.instance
        .ref("chathistory/$_uid/${widget.chatId}/meta");

    // Load existing character settings
    _loadData();
  }

  // Loads character name, gender, avatar, and background text from Firebase
  Future<void> _loadData() async {
    final snap = await _charRef.get();
    if (!snap.exists) return;

    setState(() {
      _nameCtrl.text = (snap.child("aiName").value ?? "").toString();
      _gender = (snap.child("aiGender").value ?? "unspecified").toString();

      // Background is fully user-written, no auto-extension
      _backgroundCtrl.text =
          (snap.child("aiBackground").value ?? "").toString();

      _selectedAvatar = snap.child("selectedAvatar").value?.toString();
    });
  }

  // Allows user to pick an avatar from predefined assets
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

            // Store avatar in character settings
            await _charRef.update({"selectedAvatar": avatars[i]});

            // Sync to meta (chat list uses meta)
            await _metaRef.update({"selectedAvatar": avatars[i]});
          },
          child: CircleAvatar(
            radius: 40,
            backgroundImage: AssetImage(avatars[i]),
          ),
        ),
      ),
    );
  }

  // Saves AI settings (name, gender, background text)
  Future<void> _saveInfo() async {
    // Save to character node
    await _charRef.update({
      "aiName": _nameCtrl.text.trim(),
      "aiGender": _gender,
      "aiBackground": _backgroundCtrl.text.trim(), // fully user-defined
      "updatedAt": ServerValue.timestamp,
    });

    // Sync display name to meta (used by chat list & homepage)
    await _metaRef.update({
      "aiName": _nameCtrl.text.trim(),
      "updatedAt": ServerValue.timestamp,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Saved successfully")),
    );
  }

  // Shows a dialog explaining how to write a good background description
  void _showBackgroundGuide() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          "How to Write a Good AI Background",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const SingleChildScrollView(
          child: Text(
            """
A detailed background helps the AI behave consistently and match the personality you want.

Here are recommended elements to include:

1. **Personality Traits**
   - e.g., gentle, confident, shy, humorous, protective, caring.

2. **Speaking Style**
   - e.g., formal, casual, cute, mature, energetic, soft-spoken.

3. **Character Background**
   - Where they come from, their past experiences, hobbies, or life goals.
   - Example: “A warm-hearted barista who enjoys rainy days and quiet music.”

4. **Relationship Dynamics**
   - How the AI should treat you: friend, supportive partner, mentor, listener, etc.

5. **Boundaries & Rules**
   - What topics to avoid or how serious the AI should be.

The more details you provide, the stronger the emotional immersion and role consistency will be.
""",
            textAlign: TextAlign.left,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          )
        ],
      ),
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

          // Avatar preview
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

          // Name Field
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

          // Gender Selection
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

          // Background Field
          const Text("Background:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          TextField(
            controller: _backgroundCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: "Describe your AI's personality and background",
            ),
          ),

          const SizedBox(height: 8),

          // Background guide button
          TextButton(
            onPressed: _showBackgroundGuide,
            child: const Text(
              "How to write a good AI background? (Tap to learn more)",
              style: TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
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
