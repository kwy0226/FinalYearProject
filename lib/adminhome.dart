// lib/adminhome.dart
// ==========================
// Admin Home 页面（移除情绪和消息比例模块）
// ==========================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'background_widget.dart';
import 'firebase_options.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({Key? key}) : super(key: key);
  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  final db = FirebaseDatabase.instance.ref();
  bool _loadingStats = true;

  int totalUsers = 0;
  int activeUsersLast30d = 0;
  int totalMessages = 0;
  int totalChats = 0;
  int totalDurationMin = 0;
  double avgDurationMin = 0;
  List<_TopUser> topUsers = [];

  @override
  void initState() {
    super.initState();
    _loadAllStats();
  }

  Future<void> _loadAllStats() async {
    setState(() => _loadingStats = true);
    try {
      final now = DateTime.now();
      final last30dStartMs =
          now.millisecondsSinceEpoch - const Duration(days: 30).inMilliseconds;

      final usersSnap = await db.child('users').get();
      totalUsers = usersSnap.exists ? usersSnap.children.length : 0;

      totalMessages = 0;
      totalChats = 0;
      totalDurationMin = 0;
      avgDurationMin = 0;
      topUsers.clear();

      final Map<String, int> perUserCount30d = {};
      final Map<String, bool> activeMark30d = {};

      final allChats = await db.child('chathistory').get();
      if (allChats.exists) {
        for (final userNode in allChats.children) {
          final uid = userNode.key ?? '';
          int userCount30d = 0;
          bool userActive30d = false;

          for (final chatNode in userNode.children) {
            final messages = chatNode.child('messages');
            if (!messages.exists) continue;
            int? first, last;
            for (final m in messages.children) {
              final createdAt =
                  int.tryParse((m.child('createdAt').value ?? '0').toString()) ??
                      0;
              if (createdAt > 0) {
                first =
                (first == null) ? createdAt : math.min(first!, createdAt);
                last = (last == null) ? createdAt : math.max(last!, createdAt);
              }
              totalMessages++;
              if (createdAt >= last30dStartMs) {
                userActive30d = true;
                userCount30d++;
              }
            }
            totalChats++;
            if (first != null && last != null && last >= first) {
              totalDurationMin += ((last - first) / 60000).round();
            }
          }
          if (userCount30d > 0) perUserCount30d[uid] = userCount30d;
          if (userActive30d) activeMark30d[uid] = true;
        }
      }

      activeUsersLast30d = activeMark30d.length;
      avgDurationMin = totalChats == 0 ? 0 : totalDurationMin / totalChats;

      final sorted = perUserCount30d.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted.take(5)) {
        final userSnap = await db.child('users/${e.key}').get();
        final name = (userSnap.child('username').value ?? '').toString();
        final mail = (userSnap.child('email').value ?? '').toString();
        topUsers.add(
            _TopUser(uid: e.key, name: name, email: mail, count: e.value));
      }
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _showUserStatsDialog(_TopUser user) async {
    int msgCount = 0, chatCount = 0, durationMin = 0;
    final snap = await db.child('chathistory/${user.uid}').get();
    if (snap.exists) {
      for (final chat in snap.children) {
        final msgs = chat.child('messages');
        if (!msgs.exists) continue;
        int? first, last;
        for (final m in msgs.children) {
          msgCount++;
          final created =
              int.tryParse((m.child('createdAt').value ?? '0').toString()) ?? 0;
          if (created > 0) {
            first = (first == null) ? created : math.min(first!, created);
            last = (last == null) ? created : math.max(last!, created);
          }
        }
        chatCount++;
        if (first != null && last != null && last >= first) {
          durationMin += ((last - first) / 60000).round();
        }
      }
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFFFF7E9),
        title: Text(user.name.isEmpty ? user.uid : user.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Messages: $msgCount'),
            Text('Chats: $chatCount'),
            Text('Duration: ${_fmtMin(durationMin)}'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _openManageUsers() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFF7E9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ManageUsersSheet(),
    );
  }

  Future<void> _openAddAdminDialog() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool working = false;
    String? error;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (_, setD) {
        Future<void> submit() async {
          if (!(formKey.currentState?.validate() ?? false)) return;
          setD(() => working = true);
          FirebaseApp? secondary;
          try {
            secondary = await Firebase.initializeApp(
              name: 'admin_secondary',
              options: DefaultFirebaseOptions.currentPlatform,
            );
            final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
            final cred = await secondaryAuth.createUserWithEmailAndPassword(
              email: emailCtrl.text.trim(),
              password: passCtrl.text,
            );
            final newUid = cred.user?.uid;
            if (newUid != null) {
              await db.child('admin/$newUid').set(true);
              await db.child('users/$newUid/email').set(emailCtrl.text.trim());
              await db.child('users/$newUid/status/disabled').set(false);
            }
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Admin created successfully')));
            }
          } on FirebaseAuthException catch (e) {
            error = e.message;
          } finally {
            if (secondary != null) {
              try {
                await secondary.delete();
              } catch (_) {}
            }
            setD(() => working = false);
          }
        }

        return AlertDialog(
          backgroundColor: const Color(0xFFFFF7E9),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Admin'),
          content: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => v!.isEmpty ? 'Enter email' : null,
              ),
              TextFormField(
                controller: passCtrl,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) => v!.isEmpty ? 'Enter password' : null,
              ),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child:
                    Text(error!, style: const TextStyle(color: Colors.red))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: working ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: working ? null : submit,
              child: working
                  ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add'),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF5E4631);

    return Scaffold(
      body: Stack(
        children: [
          const AppBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome, Admin',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                          fontWeight: FontWeight.w800, color: primary)),
                  const SizedBox(height: 6),
                  Text('Manage users and monitor activity',
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: primary)),
                  const SizedBox(height: 14),
                  const Divider(thickness: 1, color: Color(0x22000000)),
                  Row(children: [
                    _bigAction(
                        icon: Icons.group,
                        label: 'Manage Users',
                        onTap: _openManageUsers),
                    const SizedBox(width: 12),
                    _bigAction(
                        icon: Icons.person_add_alt_1,
                        label: 'Add Admin',
                        onTap: _openAddAdminDialog),
                  ]),
                  const SizedBox(height: 16),
                  _statsCard(
                    title: 'At a glance',
                    subtitle: 'System overview (last 30 days)',
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child:
                      Wrap(spacing: 16, runSpacing: 12, children: [
                        _kpiBlock('Users', '$totalUsers'),
                        _kpiBlock('Active (30d)', '$activeUsersLast30d'),
                        _kpiBlock('Messages', '$totalMessages'),
                        _kpiBlock('Chats', '$totalChats'),
                      ]),
                    ),
                  ),
                  _statsCard(
                    title: 'Chat Duration',
                    subtitle:
                    'Total ${_fmtMin(totalDurationMin)} · Avg ${avgDurationMin.toStringAsFixed(1)}m/chat',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Kpi(label: _fmtMin(totalDurationMin)),
                        _Kpi(label: '${avgDurationMin.toStringAsFixed(1)}m/chat'),
                      ],
                    ),
                  ),
                  _statsCard(
                    title: 'Top Users',
                    subtitle: 'Most messages in last 30 days',
                    child: Column(children: [
                      for (final u in topUsers)
                        ListTile(
                          title: Text(u.name.isEmpty ? '(No name)' : u.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF5E4631))),
                          subtitle: Text(u.email.isEmpty ? u.uid : u.email),
                          trailing: Text('${u.count} msgs'),
                          onTap: () => _showUserStatsDialog(u),
                        ),
                      if (topUsers.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('— No data —',
                                style:
                                TextStyle(color: Color(0xFF5E4631)))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/emotionoverview'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB08968),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.pie_chart_rounded),
                      label: const Text('View Emotion Insights'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(thickness: 1, color: Color(0x22000000)),
                  Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (mounted)
                          Navigator.pushNamedAndRemoveUntil(
                              context, '/login', (_) => false);
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Logout'),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF8B6B4A),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loadingStats)
            const Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(minHeight: 2)),
        ],
      ),
    );
  }

  static String _fmtMin(int totalMin) {
    final h = totalMin ~/ 60, m = totalMin % 60;
    return h <= 0 ? '${m}m' : '${h}h ${m}m';
  }

  Widget _bigAction(
      {required IconData icon,
        required String label,
        required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
              color: const Color(0xFFFFF7E9),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)]),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 36, color: const Color(0xFF5E4631)),
                const SizedBox(height: 12),
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF5E4631))),
              ]),
        ),
      ),
    );
  }

  Widget _statsCard(
      {required String title,
        required String subtitle,
        required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E9),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5E4631))),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Color(0xFF5E4631))),
        const SizedBox(height: 8),
        child,
      ]),
    );
  }

  static Widget _kpiBlock(String title, String value) {
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: const Color(0xFFEFE3D3),
          borderRadius: BorderRadius.circular(14)),
      child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5E4631))),
        Text(title, style: const TextStyle(color: Color(0xFF5E4631))),
      ]),
    );
  }
}

class _TopUser {
  final String uid, name, email;
  final int count;
  _TopUser(
      {required this.uid,
        required this.name,
        required this.email,
        required this.count});
}

// ✅ 改进后的 Manage Users sheet
class _ManageUsersSheet extends StatefulWidget {
  const _ManageUsersSheet();
  @override
  State<_ManageUsersSheet> createState() => _ManageUsersSheetState();
}

class _ManageUsersSheetState extends State<_ManageUsersSheet> {
  final db = FirebaseDatabase.instance.ref();
  bool loading = true;
  List<_UserRow> rows = [], filtered = [];
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  Future<void> _load() async {
    final usersSnap = await db.child('users').get();
    rows.clear();
    if (usersSnap.exists) {
      for (final u in usersSnap.children) {
        final uid = u.key ?? '';
        rows.add(_UserRow(
          uid: uid,
          username: (u.child('username').value ?? '').toString(),
          email: (u.child('email').value ?? '').toString(),
          gender: (u.child('gender').value ?? '').toString(),
          birthday: _parseBirthday(u.child('birthday').value),
          photoBase64: (u.child('photoBase64').value ?? '').toString(),
          disabled: (u.child('status').child('disabled').value ?? false)
              .toString() ==
              'true',
        ));
      }
    }
    filtered = List.from(rows);
    setState(() => loading = false);
  }

  String _parseBirthday(dynamic value) {
    if (value == null) return 'Not set';
    try {
      if (value is Map) {
        final y = value['year'], m = value['month'], d = value['day'];
        return "$d/$m/$y";
      }
      if (value is String) {
        final cleaned = value.replaceAll(RegExp(r'[{}]'), '');
        final parts = {
          for (var s in cleaned.split(',')) s.split(':')[0].trim(): s.split(':')[1].trim()
        };
        return "${parts['day']}/${parts['month']}/${parts['year']}";
      }
    } catch (_) {}
    return value.toString();
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      filtered = q.isEmpty
          ? List.from(rows)
          : rows
          .where((e) =>
      e.username.toLowerCase().contains(q) ||
          e.email.toLowerCase().contains(q) ||
          e.uid.toLowerCase().contains(q))
          .toList();
    });
  }

  Future<void> _showUserDialog(_UserRow user) async {
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setD) {
        return AlertDialog(
          backgroundColor: const Color(0xFFFFF7E9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundImage: user.photoBase64.isNotEmpty
                    ? MemoryImage(base64Decode(user.photoBase64))
                    : null,
                child: user.photoBase64.isEmpty
                    ? const Icon(Icons.person, color: Color(0xFF5E4631))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  user.username,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFF5E4631),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Gender: ${user.gender}", style: const TextStyle(color: Color(0xFF5E4631))),
              Text("Birthday: ${user.birthday}", style: const TextStyle(color: Color(0xFF5E4631))),
              const SizedBox(height: 10),
              Text(
                "Status: ${user.disabled ? '❌ Disabled' : '✅ Active'}",
                style: TextStyle(
                  color: user.disabled ? Colors.red : Colors.green[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final newState = !user.disabled;
                await db.child("users/${user.uid}/status/disabled").set(newState);
                setD(() => user.disabled = newState);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(newState ? "User disabled" : "User enabled"),
                  backgroundColor: const Color(0xFFB08968),
                ));
              },
              child: Text(user.disabled ? "Enable" : "Disable",
                  style: const TextStyle(color: Color(0xFF5E4631))),
            ),
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFFFFF7E9),
                    title: const Text("Confirm Deletion"),
                    content: Text("Delete ${user.username}? This cannot be undone."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text("Delete"),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await db.child("users/${user.uid}").remove();
                  Navigator.pop(context);
                  setState(() {
                    rows.removeWhere((e) => e.uid == user.uid);
                    filtered.removeWhere((e) => e.uid == user.uid);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("User deleted"),
                    backgroundColor: Colors.redAccent,
                  ));
                }
              },
              child: const Text("Delete", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Color(0xFF5E4631))),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Manage Users',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          TextField(controller: _searchCtrl, decoration: const InputDecoration(hintText: 'Search user')),
          const SizedBox(height: 10),
          if (loading)
            const LinearProgressIndicator()
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final u = filtered[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: u.photoBase64.isNotEmpty
                          ? MemoryImage(base64Decode(u.photoBase64))
                          : null,
                      child: u.photoBase64.isEmpty
                          ? const Icon(Icons.person, color: Color(0xFF5E4631))
                          : null,
                    ),
                    title: Text(u.username),
                    subtitle: Text(u.email.isEmpty ? u.uid : u.email),
                    trailing: Icon(
                      u.disabled ? Icons.block : Icons.check_circle,
                      color: u.disabled ? Colors.red : Colors.green,
                    ),
                    onTap: () => _showUserDialog(u),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}

class _UserRow {
  final String uid, username, email, gender, birthday, photoBase64;
  bool disabled;
  _UserRow({
    required this.uid,
    required this.username,
    required this.email,
    required this.gender,
    required this.birthday,
    required this.photoBase64,
    required this.disabled,
  });
}

class _Kpi extends StatelessWidget {
  final String label;
  const _Kpi({required this.label});
  @override
  Widget build(BuildContext context) =>
      Text(label, style: const TextStyle(color: Color(0xFF5E4631)));
}

