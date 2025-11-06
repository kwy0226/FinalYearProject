import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'background_widget.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _auth = FirebaseAuth.instance;

  // 强制使用你项目的 Realtime DB URL（若 firebase_options 已配置可改回 FirebaseDatabase.instance）
  final FirebaseDatabase _db = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
    'https://finalyearproject-b2776-default-rtdb.asia-southeast1.firebasedatabase.app',
  );

  final _usernameCtrl = TextEditingController();
  String? _gender;             // "Male" | "Female"
  String? _photoBase64;        // 头像以 Base64 存在 DB
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile(); // Enter the page to fetch username/gender/photoBase64
  }

  // Read /users/<uid> and safely unpack the Map
  Future<void> _loadProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snap = await _db.ref('users/${user.uid}').get();
      if (!snap.exists || snap.value == null) return;

      final map = Map<String, dynamic>.from(snap.value as Map);

      setState(() {
        _usernameCtrl.text = (map['username'] as String?) ?? '';
        _gender = map['gender'] as String?;
        _photoBase64 = map['photoBase64'] as String?;
      });
    } catch (e) {
      // If permissions prevent reading here, it will also cause the username to not display.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load profile: $e')),
      );
    }
  }

  // Select image -> Convert to Base64 -> Save to /users/<uid>/photoBase64
  Future<void> _pickAndSavePhoto() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() => _loading = true);

      // Read as bytes and convert to Base64 (Avatar size should be < 400KB to prevent excessive DB node size)
      final bytes = await File(picked.path).readAsBytes();
      final base64Str = base64Encode(bytes);

      await _db.ref('users/${user.uid}/photoBase64').set(base64Str);

      setState(() {
        _photoBase64 = base64Str;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated.')),
      );
    } catch (e) {
      // permission denied (requires the DB rules above)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save photo: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  // Save username + gender to the same-level node
  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    try {
      await _db.ref('users/${user.uid}').update({
        'username': _usernameCtrl.text.trim(),
        'gender': _gender ?? 'Male',
        // photoBase64 has already been written during separate uploads and does not need to be uploaded again.
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
      Navigator.pop(context); // Back to Settings
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 将 Base64 头像（若存在）解码为 MemoryImage
    ImageProvider? avatarProvider;
    if (_photoBase64 != null && _photoBase64!.isNotEmpty) {
      try {
        avatarProvider = MemoryImage(base64Decode(_photoBase64!));
      } catch (_) {
        avatarProvider = null;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF5E4631)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          const AppBackground(),
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // ---- 头像（点击上传）----
                GestureDetector(
                  onTap: _loading ? null : _pickAndSavePhoto,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 55,
                        backgroundColor: const Color(0xFFDECDBE),
                        backgroundImage: avatarProvider,
                        child: avatarProvider == null
                            ? const Icon(Icons.camera_alt,
                            size: 40, color: Color(0xFF5E4631))
                            : null,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Upload Photo',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5E4631),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // ---- Username ----
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 20),

                // ---- Gender ----
                Row(
                  children: [
                    const Icon(Icons.wc, color: Color(0xFF8B6B4A)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _gender,
                        decoration: const InputDecoration(
                          labelText: 'Gender',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(value: 'Female', child: Text('Female')),
                        ],
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                // ---- Save ----
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB08968),
                      foregroundColor: Colors.white,
                    ),
                    child: _loading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
