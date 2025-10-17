// lib/chats_page.dart
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
  int _tabIndex = 1; // 首页=0，Chats=1

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('User not signed in.');
    }
    _uid = user.uid;

    // ✅ 监听 chathistory/<uid>
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
    });

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatBoxPage(chatId: newChat.key!),
      ),
    );
  }

  // 📌 长按弹出菜单
  void _showChatOptionsDialog(String chatId, bool pinned) {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text("Chat Options"),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context);
                if (pinned) {
                  _unpinChat(chatId);
                } else {
                  _pinChat(chatId);
                }
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
        );
      },
    );
  }

  // 🗑 删除聊天
  Future<void> _deleteChat(String chatId) async {
    await _chatsRef.child(chatId).remove();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Chat deleted")),
    );
  }

  // 📌 置顶聊天
  Future<void> _pinChat(String chatId) async {
    await _chatsRef.child(chatId).child('meta').update({'pinned': true});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Chat pinned")),
    );
  }

  // 📌 取消置顶
  Future<void> _unpinChat(String chatId) async {
    await _chatsRef.child(chatId).child('meta').update({'pinned': false});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Chat unpinned")),
    );
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(),
                const Divider(
                  thickness: 1,
                  height: 1,
                  color: Color(0xFFD3C5B2),
                ),
                Expanded(
                  child: StreamBuilder<DatabaseEvent>(
                    stream: _chatsStream,
                    builder: (context, snapshot) {
                      final items = <_ChatListItem>[];

                      if (snapshot.hasData) {
                        final snap = snapshot.data!.snapshot;

                        for (final chat in snap.children) {
                          final id = chat.key ?? '';
                          final meta = chat.child('meta');

                          final aiName =
                          (meta.child('aiName').value ?? 'Companion')
                              .toString();
                          final lastMsg =
                          (meta.child('lastMessage').value ?? '')
                              .toString();
                          final updatedAt =
                          (meta.child('updatedAt').value ?? 0) as int;
                          final pinned =
                              (meta.child('pinned').value ?? false) == true;

                          items.add(_ChatListItem(
                            chatId: id,
                            aiName: aiName,
                            lastMessage: lastMsg,
                            updatedAtMs: updatedAt,
                            pinned: pinned,
                          ));
                        }

                        // ✅ pinned 优先，其次按时间排序
                        items.sort((a, b) {
                          if (a.pinned && !b.pinned) return -1;
                          if (!a.pinned && b.pinned) return 1;
                          return b.updatedAtMs.compareTo(a.updatedAtMs);
                        });
                      }

                      if (items.isEmpty) {
                        return const Center(
                          child: Text(
                            "No conversations yet.\nTap the + button to start one!",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF5E4631),
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return GestureDetector(
                            onLongPress: () =>
                                _showChatOptionsDialog(item.chatId, item.pinned),
                            child: Container(
                              decoration: BoxDecoration(
                                color: item.pinned
                                    ? const Color(0xFFF1EDE5)
                                    : Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ],
                              ),
                              child: ListTile(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ChatBoxPage(chatId: item.chatId),
                                  ),
                                ),
                                leading: _avatarFromName(item.aiName),
                                title: Text(
                                  item.aiName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF5E4631),
                                  ),
                                ),
                                subtitle: Text(
                                  item.lastMessage.isEmpty
                                      ? "New conversation"
                                      : item.lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF5E4631),
                                  ),
                                ),
                                trailing: Text(
                                  _friendlyTime(item.updatedAtMs),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF5E4631),
                                  ),
                                ),
                              ),
                            ),
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
      bottomNavigationBar: Container(
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
          unselectedItemColor: const Color(0xFF5E4631).withOpacity(0.6),
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
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          'Chats',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF5E4631),
          ),
        ),
      ),
    );
  }

  Widget _avatarFromName(String name) {
    final initials =
    name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'C';
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFFDECDBE),
      child: Text(
        initials,
        style: const TextStyle(
          color: Color(0xFF5E4631),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _friendlyTime(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();

    String two(int n) => n.toString().padLeft(2, '0');

    final isSameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isSameDay) {
      return '${two(dt.hour)}:${two(dt.minute)}';
    }

    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day;
    if (isYesterday) return 'Yesterday';

    return '${dt.month}/${dt.day}';
  }
}

class _ChatListItem {
  _ChatListItem({
    required this.chatId,
    required this.aiName,
    required this.lastMessage,
    required this.updatedAtMs,
    this.pinned = false,
  });

  final String chatId;
  final String aiName;
  final String lastMessage;
  final int updatedAtMs;
  final bool pinned;
}
