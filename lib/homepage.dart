import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'background_widget.dart';
import 'chatbox.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _auth = FirebaseAuth.instance; // Firebase auth instance
  // Subscriptions to Firebase listeners (profile + chat history)
  StreamSubscription<DatabaseEvent>? _profileSub;
  StreamSubscription<DatabaseEvent>? _chatHistorySub;

  String? _username; // Loaded from Firebase
  String? _photoBase64; // Base64 encoded profile picture
  int _tabIndex = 0; // For bottom navigation bar
  List<Map<String, dynamic>> recentChats = []; // Stores chat history summary

  @override
  void initState() {
    super.initState();
    _loadProfile(); // Start listening to user profile changes
    _loadChatHistory(); // Start listening to chat history updates
  }

  // LOAD & LISTEN TO USER PROFILE
  void _loadProfile() {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    // Listen to the user's node in Firebase DB
    _profileSub = FirebaseDatabase.instance.ref('users/$uid').onValue.listen(
          (event) {
        // Convert snapshot to Map
        final data = (event.snapshot.value as Map?) ?? {};
        setState(() {
          _username = data['username'] as String? ?? 'User';
          _photoBase64 = data['photoBase64'] as String?;
        });
      },
    );
  }

  // LOAD CHAT HISTORY WITH aiName
  void _loadChatHistory() {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;

    // Listen to chat list under chathistory/uid
    _chatHistorySub =
        FirebaseDatabase.instance.ref('chathistory/$uid').onValue.listen(
              (event) {
            final data = (event.snapshot.value as Map?) ?? {};
            List<Map<String, dynamic>> chats = [];

            // Every child = one chat room
            data.forEach((chatId, value) {
              final chat = value as Map;
              final meta = chat['meta'] as Map?;

              // --- Added: skip archived chats (no meta = archived) ---
              if (meta == null) {
                return; // Do NOT show archived chats
              }
              // ---------------------------------------------------------

              // Store only metadata needed for chat list
              chats.add({
                'chatId': chatId,
                'aiName': meta['aiName'] ?? 'Companion', // default AI name
                'lastMessage': meta['lastMessage'] ?? '',
                'updatedAt': meta['updatedAt'] ?? 0, // used for sorting
              });
            });

            // Sort most recent chats to the top
            chats.sort((a, b) => b['updatedAt'].compareTo(a['updatedAt']));

            setState(() {
              recentChats = chats;
            });
          },
        );
  }

  // BREATHING MODAL
  // A 1-minute breathing exercise with countdown timer
  void _openBreathingModal() {
    showDialog(
      context: context,
      barrierDismissible: false, // User must click Close
      builder: (ctx) {
        int seconds = 60;
        Timer? timer;

        return StatefulBuilder(
          builder: (context, setModalState) {
            // Start 60s countdown timer
            void startTimer() {
              timer = Timer.periodic(const Duration(seconds: 1), (t) {
                if (seconds == 0) {
                  t.cancel();
                  setModalState(() {});
                } else {
                  setModalState(() => seconds--);
                }
              });
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text("1-Minute Breathing"),
              // Modal content with instructions + timer
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Breathe in through your nose for 4 seconds,\n"
                        "hold for 4 seconds,\n"
                        "and slowly exhale through your mouth for 6 seconds.\n\n"
                        "Relax your shoulders and focus only on your breath.",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  // Timer display after clicking Start
                  if (seconds < 60)
                    Text(
                      seconds > 0
                          ? "⏳ Time remaining: $seconds s"
                          : "🎉 Great job! You've completed the session.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              actions: [
                // Start button appears only before timer starts
                if (seconds == 60)
                  TextButton(
                    onPressed: startTimer,
                    child: const Text("Start"),
                  ),
                // Close button always visible
                TextButton(
                  onPressed: () {
                    timer?.cancel(); // Stop timer if running
                    Navigator.pop(ctx); // Close dialog
                  },
                  child: const Text("Close"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // CREATE NEW CHAT + NAVIGATE TO CHATBOX PAGE
  Future<void> _createNewChatAndOpen() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    // Create a new chat node using push()
    final ref = FirebaseDatabase.instance.ref('chathistory/$uid').push();
    final chatId = ref.key;
    if (chatId == null) return;

    // Initial metadata for the new chat
    await ref.child('meta').set({
      'createdAt': now,
      'updatedAt': now,
      'lastMessage': '',
      'aiName': 'Companion', // default AI persona name
    });

    // Navigate to chatbox page
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatBoxPage(chatId: chatId)),
    );
  }

  // BOTTOM NAVIGATION
  void _onBottomTap(int index) {
    if (index == _tabIndex) return;
    setState(() => _tabIndex = index);

    switch (index) {
      case 0:
        break;
      case 1:
        Navigator.pushNamed(context, '/chats');
        break;
      case 2:
        Navigator.pushNamed(context, '/chart');
        break;
      case 3:
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }

  // AVATAR BUILDER
  Widget _buildAvatar() {
    // If profile photo exists → decode from Base64
    if (_photoBase64 != null && _photoBase64!.isNotEmpty) {
      return CircleAvatar(
        radius: 26,
        backgroundImage: MemoryImage(base64Decode(_photoBase64!)),
      );
    } else {
      // Otherwise show initials from username
      final initials =
      _username?.isNotEmpty == true ? _username![0].toUpperCase() : 'U';
      return CircleAvatar(
        radius: 26,
        backgroundColor: const Color(0xFFDECDBE),
        child: Text(
          initials,
          style: const TextStyle(
              color: Color(0xFF5E4631), fontWeight: FontWeight.bold),
        ),
      );
    }
  }

  // Format timestamp for display in chat list
  String _formatTime(int timestamp) {
    if (timestamp == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    // If message is from today → show HH:mm
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }
    // Otherwise show MM/DD
    return "${dt.month}/${dt.day}";
  }

  @override
  void dispose() {
    _profileSub?.cancel(); // Stop listening to profile changes
    _chatHistorySub?.cancel(); // Stop listening to chat history
    super.dispose();
  }

  // BUILD UI
  @override
  Widget build(BuildContext context) {
    final name = _username ?? 'User';
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          const AppBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== Header =====
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _buildAvatar(),
                          const SizedBox(width: 12),
                          Text(
                            "Welcome back, $name 👋",
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF5E4631),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded,
                            color: Color(0xFF8B6B4A)),
                        onPressed: () async {
                          await _auth.signOut();
                          if (!mounted) return;
                          Navigator.of(context).pushNamedAndRemoveUntil(
                              '/login', (route) => false);
                        },
                      )
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ===== Daily Emotional Mini-Practice =====
                  Card(
                    color: const Color(0xFFFFF7E9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Daily Emotional Mini-Practice",
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF5E4631)),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "💛 You deserve kindness — from yourself too.",
                            style: TextStyle(color: Color(0xFF5E4631)),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB08968),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _openBreathingModal,
                              child: const Text("Start 1-min Breathing"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ===== Recent Chats =====
                  const Text(
                    "Recent Chats",
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: Color(0xFF5E4631)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: recentChats.isEmpty
                        ? const Text("No chat history yet.")
                        : ListView.builder(
                      itemCount: recentChats.length,
                      itemBuilder: (context, index) {
                        final chat = recentChats[index];
                        return ListTile(
                          leading: const Icon(Icons.chat_bubble_outline),
                          title: Text(
                            chat['aiName'] ?? 'Companion',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            chat['lastMessage'].isEmpty
                                ? "(No message yet)"
                                : chat['lastMessage'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _formatTime(chat['updatedAt']),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          onTap: () async {
                            final uid = _auth.currentUser!.uid;

                            // --- Added: Check if chat still has meta (not archived) ---
                            final metaRef = FirebaseDatabase.instance
                                .ref('chathistory/$uid/${chat['chatId']}/meta');

                            final metaSnap = await metaRef.get();

                            if (!metaSnap.exists) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("This chat has been archived.")),
                              );
                              return; // Do NOT open archived chat
                            }
                            // -----------------------------------------------------------

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatBoxPage(chatId: chat['chatId']),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ===== Let’s Chat Button =====
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _createNewChatAndOpen,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB08968),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text("Let's Chat!"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // Bottom Navigation Bar
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
}
