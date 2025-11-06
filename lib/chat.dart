import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'background_widget.dart';
import 'chatbox.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final _auth = FirebaseAuth.instance;

  late final String _uid;
  late final DatabaseReference _chatsRef;

  Stream<DatabaseEvent>? _chatsStream;
  int _tabIndex = 1;

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user == null) throw StateError('User not signed in.');
    _uid = user.uid;

    _chatsRef = FirebaseDatabase.instance.ref('chathistory/$_uid');
    _chatsStream = _chatsRef.orderByChild('meta/updatedAt').onValue;
  }

  Future<void> _createNewChat() async {
    final newChat = _chatsRef.push();
    await newChat.child('meta').set({
      'aiName': 'Companion',
      'lastMessage': '',
      'createdAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
      'pinned': false,
    });

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatBoxPage(chatId: newChat.key!),
      ),
    );
  }

  void _showChatOptionsDialog(String chatId, bool pinned) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("Chat Options"),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              pinned ? _unpinChat(chatId) : _pinChat(chatId);
            },
            child: Text(pinned ? "📌 Unpin Chat" : "📌 Pin Chat"),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _deleteChat(chatId);
            },
            child: const Text(
              "🗑 Delete Chat",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteChat(String chatId) async {
    await _chatsRef.child(chatId).remove();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Chat deleted")));
  }

  Future<void> _pinChat(String chatId) async {
    await _chatsRef.child(chatId).child('meta').update({'pinned': true});
  }

  Future<void> _unpinChat(String chatId) async {
    await _chatsRef.child(chatId).child('meta').update({'pinned': false});
  }

  void _onBottomTap(int index) {
    if (index == _tabIndex) return;
    setState(() => _tabIndex = index);

    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/chart');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AppBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const Divider(
                  thickness: 1,
                  color: Color(0xFFD3C5B2),
                ),
                Expanded(
                  child: StreamBuilder(
                    stream: _chatsStream,
                    builder: (context, snapshot) {
                      final items = <_ChatListItem>[];

                      if (snapshot.hasData) {
                        final snap = snapshot.data!.snapshot;
                        for (final chat in snap.children) {
                          final id = chat.key!;
                          final meta = chat.child("meta");

                          items.add(_ChatListItem(
                            chatId: id,
                            aiName: (meta.child("aiName").value ?? "Companion").toString(),
                            lastMessage: (meta.child("lastMessage").value ?? "").toString(),
                            updatedAt: (meta.child("updatedAt").value ?? 0) as int,
                            pinned: (meta.child("pinned").value ?? false) == true,
                          ));
                        }

                        items.sort((a, b) {
                          if (a.pinned && !b.pinned) return -1;
                          if (!a.pinned && b.pinned) return 1;
                          return b.updatedAt.compareTo(a.updatedAt);
                        });
                      }

                      if (items.isEmpty) {
                        return const Center(
                          child: Text(
                            "No conversations yet.\nTap the + button to start one!",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Color(0xFF5E4631)),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return GestureDetector(
                            onLongPress: () => _showChatOptionsDialog(item.chatId, item.pinned),
                            child: _buildChatTile(item),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFB08968),
        foregroundColor: Colors.white,
        onPressed: _createNewChat,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: _buildNavBar(),
    );
  }

  Widget _buildChatTile(_ChatListItem item) {
    return Container(
      decoration: BoxDecoration(
        color: item.pinned ? const Color(0xFFF1EDE5) : Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatBoxPage(chatId: item.chatId),
          ),
        ),
        leading: _avatarFromName(item.aiName),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.aiName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5E4631),
                ),
              ),
            ),
            if (item.pinned)
              const Icon(Icons.push_pin, size: 18, color: Colors.brown),
          ],
        ),
        subtitle: Text(
          item.lastMessage.isEmpty ? "New conversation" : item.lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF5E4631)),
        ),
        trailing: Text(
          _friendlyTime(item.updatedAt),
          style: const TextStyle(fontSize: 12, color: Color(0xFF5E4631)),
        ),
      ),
    );
  }

  Widget _avatarFromName(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    return CircleAvatar(
      radius: 22,
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

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          "Chats",
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF5E4631),
          ),
        ),
      ),
    );
  }

  Widget _buildNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -1),
          )
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: _onBottomTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFFFFF7E9),
        selectedItemColor: const Color(0xFF8B6B4A),
        unselectedItemColor: const Color(0xFF5E4631).withOpacity(0.6),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: "Homepage"),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: "Chats"),
          BottomNavigationBarItem(icon: Icon(Icons.insights_rounded), label: "Chart"),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: "Settings"),
        ],
      ),
    );
  }

  String _friendlyTime(int ms) {
    if (ms <= 0) return "";
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();

    String two(int n) => n.toString().padLeft(2, '0');

    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return "${two(dt.hour)}:${two(dt.minute)}";
    }

    final y = now.subtract(const Duration(days: 1));
    if (dt.year == y.year && dt.month == y.month && dt.day == y.day) {
      return "Yesterday";
    }

    return "${dt.month}/${dt.day}";
  }
}

class _ChatListItem {
  final String chatId;
  final String aiName;
  final String lastMessage;
  final int updatedAt;
  final bool pinned;

  _ChatListItem({
    required this.chatId,
    required this.aiName,
    required this.lastMessage,
    required this.updatedAt,
    required this.pinned,
  });
}
