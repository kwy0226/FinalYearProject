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
  int _tabIndex = 3; // 默认在 Settings tab

  // ---- 删除账号逻辑 ----
  Future<void> _deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Account"),
        content: const Text(
          "Are you sure you want to permanently delete your account? This action cannot be undone.",
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

    try {
      // Delete from Realtime Database
      await FirebaseDatabase.instance.ref("users/${user.uid}").remove();

      // Delete Firebase Auth account
      await user.delete();

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete account: $e")),
      );
    }
  }

  // ---- 登出逻辑 ----
  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

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
        break; // already here
    }
  }

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
                // ===== Title =====
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

                // ===== List of options =====
                Expanded(
                  child: ListView(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person, color: Color(0xFF8B6B4A)),
                        title: const Text("Edit Profile"),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => Navigator.pushNamed(context, '/editProfile'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.info, color: Color(0xFF8B6B4A)),
                        title: const Text("About Us"),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => Navigator.pushNamed(context, '/aboutus'),
                      ),
                      const Divider(),

                      // Delete account
                      ListTile(
                        leading: const Icon(Icons.delete_forever,
                            color: Colors.redAccent),
                        title: const Text("Delete Account",
                            style: TextStyle(color: Colors.redAccent)),
                        onTap: _deleteAccount,
                      ),

                      // Logout
                      ListTile(
                        leading:
                        const Icon(Icons.logout, color: Color(0xFF8B6B4A)),
                        title: const Text("Logout"),
                        onTap: _logout,
                      ),
                    ],
                  ),
                ),

                // ===== Bottom navigation =====
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
