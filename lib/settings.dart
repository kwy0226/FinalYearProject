import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'background_widget.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _auth = FirebaseAuth.instance;
  int _tabIndex = 3;

  // ===============================================================
  // Delete Account (FULL DELETION: Auth + all database user data)
  // ===============================================================
  Future<void> _deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Step 1 — Ask user for confirmation
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Account"),
        content: const Text(
          "Are you sure you want to permanently delete your account?\n"
              "All your chats, history and profile will be erased.\n"
              "This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Step 2 — Firebase requires re-authentication before deleting user
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text("Confirm Password"),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: "Enter your password",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );

    if (password == null || password.isEmpty) return;

    try {
      // Step 3 — Re-authenticate user with password
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);

      final uid = user.uid;
      final db = FirebaseDatabase.instance.ref();

      // Step 4 — Delete ALL database data related to this user
      // (Add/remove paths based on your app structure)
      await Future.wait([
        db.child("users/$uid").remove(),
        db.child("chathistory/$uid").remove(),
        db.child("character/$uid").remove(),
        db.child("chats/$uid").remove(),
        db.child("audio/$uid").remove(),
        db.child("stats/$uid").remove(),
        // Add any other paths if used in your app
      ]);

      // Step 5 — Delete Firebase Auth account
      await user.delete();

      if (!mounted) return;

      // Step 6 — Redirect to Login Page
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);

    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to delete account: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ===============================================================
  // Logout (Simple Sign Out)
  // ===============================================================
  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  // Bottom navigation handling
  void _onBottomTap(int index) {
    if (index == _tabIndex) return;
    setState(() => _tabIndex = index);

    switch (index) {
      case 0:
        Navigator.pushNamed(context, '/home');
        break;
      case 1:
        Navigator.pushNamed(context, '/chats');
        break;
      case 2:
        Navigator.pushNamed(context, '/chart');
        break;
      case 3:
        break;
    }
  }

  // ===============================================================
  // UI
  // ===============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          const AppBackground(),
          SafeArea(
            child: Column(
              children: [
                // ----- Page Title -----
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    "Settings",
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF5E4631),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                Expanded(
                  child: ListView(
                    children: [
                      // ----- Edit Profile -----
                      ListTile(
                        leading: const Icon(Icons.person, color: Color(0xFF8B6B4A)),
                        title: const Text("Edit Profile"),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => Navigator.pushNamed(context, '/editProfile'),
                      ),

                      // ----- About Us -----
                      ListTile(
                        leading: const Icon(Icons.info, color: Color(0xFF8B6B4A)),
                        title: const Text("About Us"),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => Navigator.pushNamed(context, '/aboutus'),
                      ),

                      const Divider(),

                      // ----- Delete Account -----
                      ListTile(
                        leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        title: const Text(
                          "Delete Account",
                          style: TextStyle(color: Colors.redAccent),
                        ),
                        onTap: _deleteAccount,
                      ),

                      // ----- Logout -----
                      ListTile(
                        leading: const Icon(Icons.logout, color: Color(0xFF8B6B4A)),
                        title: const Text("Logout"),
                        onTap: _logout,
                      ),
                    ],
                  ),
                ),

                // Bottom navigation bar
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E9),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: BottomNavigationBar(
                    currentIndex: _tabIndex,
                    onTap: _onBottomTap,
                    type: BottomNavigationBarType.fixed,
                    backgroundColor: const Color(0xFFFFF7E9),
                    selectedItemColor: const Color(0xFF8B6B4A),
                    unselectedItemColor:
                    const Color(0xFF5E4631).withOpacity(0.6),
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.home_rounded),
                        label: 'Homepage',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.chat_bubble_rounded),
                        label: 'Chats',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.insights_rounded),
                        label: 'Chart',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.settings_rounded),
                        label: 'Settings',
                      ),
                    ],
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
