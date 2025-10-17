// lib/adminhome.dart
//
// ==========================
// Admin Home 页面（保留原有 UI 和配色）
// 本文件包含：
// 1) 全局统计的计算与展示
// 2) Top Users 列表（支持点击弹窗查看该用户的汇总统计）
// 3) Manage Users 底部弹窗（支持搜索/禁用/删除数据；subtitle 统一显示为 Email 或 UID）
// 4) Add Admin（二级 App 创建，不影响当前登录态）
// ==========================

import 'dart:async';
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

  // ---------- 从这里开始：全局统计指标 ----------
  int totalUsers = 0;
  int activeUsersLast30d = 0;

  int totalMessages = 0;
  int totalChats = 0;

  int totalDurationMin = 0;
  double avgDurationMin = 0;

  int audioCount = 0;
  int textCount = 0;

  Map<String, int> emotionCount = {
    "happy": 0,
    "sad": 0,
    "angry": 0,
    "neutral": 0
  };

  // 最近 7 天每日消息数 + 活跃用户对比
  List<int> msgsLast7d = List.filled(7, 0);
  int activeUsersLast7d = 0;
  int activeUsersPrev7d = 0;

  // Top 用户（最近 30 天）
  List<_TopUser> topUsers = [];
  // ---------- 到这里结束：全局统计指标 ----------

  @override
  void initState() {
    super.initState();
    _loadAllStats();
  }

  // ==========================
  // 从这里开始：加载全量统计（扫描 chathistory）
  // ==========================
  Future<void> _loadAllStats() async {
    setState(() => _loadingStats = true);

    try {
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final last7dStart = now.subtract(const Duration(days: 6));
      final last7dStartMs = DateTime(last7dStart.year, last7dStart.month, last7dStart.day).millisecondsSinceEpoch; // 当天 00:00
      final prev7dStartMs = last7dStartMs - const Duration(days: 7).inMilliseconds;
      final last30dStartMs = nowMs - const Duration(days: 30).inMilliseconds;

      // 1) 用户总数
      final usersSnap = await db.child('users').get();
      totalUsers = usersSnap.exists ? usersSnap.children.length : 0;

      // 2) 清零并准备统计容器
      totalMessages = 0;
      totalChats = 0;
      totalDurationMin = 0;
      avgDurationMin = 0;
      audioCount = 0;
      textCount = 0;
      msgsLast7d = List.filled(7, 0);
      activeUsersLast7d = 0;
      activeUsersPrev7d = 0;
      emotionCount.updateAll((key, value) => 0);
      topUsers.clear();

      final Map<String, int> perUserCount30d = {};
      final Map<String, bool> activeMarkLast30d = {};
      final Map<String, bool> activeMarkLast7d = {};
      final Map<String, bool> activeMarkPrev7d = {};

      // 3) 统计 chathistory
      final allChats = await db.child('chathistory').get();
      if (allChats.exists) {
        for (final userNode in allChats.children) {
          final uid = userNode.key ?? '';
          int userCount30d = 0;
          bool userActive30d = false;
          bool userActive7d = false;
          bool userActivePrev7 = false;

          for (final chatNode in userNode.children) {
            final messages = chatNode.child('messages');
            if (!messages.exists) continue;

            int? firstTime;
            int? lastTime;

            for (final m in messages.children) {
              // createdAt 时间戳
              final createdStr = (m.child('createdAt').value ?? '0').toString();
              final createdAt = int.tryParse(createdStr) ?? 0;

              if (createdAt > 0) {
                firstTime = (firstTime == null) ? createdAt : math.min(firstTime!, createdAt);
                lastTime  = (lastTime  == null) ? createdAt : math.max(lastTime!,  createdAt);
              }

              // 总消息数
              totalMessages++;

              // 最近 7 天消息分桶（今天 index=6）
              if (createdAt >= last7dStartMs) {
                final daysDiff = DateTime.fromMillisecondsSinceEpoch(createdAt)
                    .difference(DateTime(now.year, now.month, now.day)).inDays;
                final idx = 6 + daysDiff;
                if (idx >= 0 && idx < 7) msgsLast7d[idx] += 1;
              }

              // 活跃标记
              if (createdAt >= last30dStartMs) userActive30d = true;
              if (createdAt >= last7dStartMs) userActive7d = true;
              if (createdAt < last7dStartMs && createdAt >= prev7dStartMs) userActivePrev7 = true;

              // Audio / Text 统计（以 type 优先，兜底看 aiReply 文本）
              final type = (m.child('type').value ?? '').toString().toLowerCase();
              if (type == 'audio') audioCount++;
              if (type == 'text')  textCount++;
              if (type.isEmpty) {
                final content = (m.child('aiReply').child('aiReplyParts').child('content').value ?? '')
                    .toString().toLowerCase();
                if (content.contains('(audio')) {
                  audioCount++;
                } else {
                  textCount++;
                }
              }

              // Emotion 统计
              final label = (m.child('emotion').child('label').value ?? '').toString().toLowerCase();
              if (emotionCount.containsKey(label)) {
                emotionCount[label] = (emotionCount[label] ?? 0) + 1;
              }

              // Top 用户统计（30 天内消息数）
              if (createdAt >= last30dStartMs) userCount30d++;
            }

            // 会话总数与时长
            totalChats++;
            if (firstTime != null && lastTime != null && lastTime! >= firstTime!) {
              totalDurationMin += ((lastTime! - firstTime!) / 60000).round();
            }
          }

          if (userCount30d > 0) perUserCount30d[uid] = userCount30d;
          if (userActive30d)   activeMarkLast30d[uid] = true;
          if (userActive7d)    activeMarkLast7d[uid]  = true;
          if (userActivePrev7) activeMarkPrev7d[uid]  = true;
        }
      }

      activeUsersLast30d = activeMarkLast30d.length;
      activeUsersLast7d  = activeMarkLast7d.length;
      activeUsersPrev7d  = activeMarkPrev7d.length;
      avgDurationMin     = totalChats == 0 ? 0 : totalDurationMin / totalChats;

      // Top 5 用户：取最近 30 天消息数最多的用户
      final sorted = perUserCount30d.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top5 = sorted.take(5);
      for (final e in top5) {
        final userSnap = await db.child('users/${e.key}').get();
        final name = (userSnap.child('username').value ?? '').toString();
        final mail = (userSnap.child('email').value ?? '').toString();
        topUsers.add(_TopUser(uid: e.key, name: name, email: mail, count: e.value));
      }
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }
  // ==========================
  // 到这里结束：加载全量统计
  // ==========================

  // ==========================
  // 从这里开始：Top Users 点击弹窗（不展示 Email）
  // ==========================
  Future<void> _showUserStatsDialog(_TopUser user) async {
    int msgCount = 0, chatCount = 0, audio = 0, text = 0, durationMin = 0;
    final snap = await db.child('chathistory/${user.uid}').get();
    if (snap.exists) {
      for (final chat in snap.children) {
        final msgs = chat.child('messages');
        if (!msgs.exists) continue;
        int? first, last;
        for (final m in msgs.children) {
          msgCount++;
          final created = int.tryParse((m.child('createdAt').value ?? '0').toString()) ?? 0;
          if (created > 0) {
            first = (first == null) ? created : math.min(first!, created);
            last  = (last  == null) ? created : math.max(last!,  created);
          }
          final type = (m.child('type').value ?? '').toString().toLowerCase();
          if (type == 'audio') audio++; else text++;
        }
        chatCount++;
        if (first != null && last != null && last! >= first!) {
          durationMin += ((last! - first!) / 60000).round();
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
            Text('Audio: $audio  ·  Text: $text'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
  // ==========================
  // 到这里结束：Top Users 点击弹窗
  // ==========================

  // ==========================
  // 从这里开始：Manage Users 弹窗
  // ==========================
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
  // ==========================
  // 到这里结束：Manage Users 弹窗
  // ==========================

  // ==========================
  // 从这里开始：Add Admin（二级 App，避免影响当前登录）
  // ==========================
  Future<void> _openAddAdminDialog() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool working = false;
    String? error;

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(builder: (_, setD) {
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Admin created successfully')),
                );
              }
            } on FirebaseAuthException catch (e) {
              error = e.message;
            } finally {
              if (secondary != null) {
                try { await secondary.delete(); } catch (_) {}
              }
              setD(() => working = false);
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFFFFF7E9),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Add Admin'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v!.trim().isEmpty ? 'Enter email' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: passCtrl,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    validator: (v) => (v ?? '').isEmpty ? 'Enter password' : null,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: working ? null : () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(onPressed: working ? null : submit, child: working
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add')),
            ],
          );
        });
      },
    );
  }
  // ==========================
  // 到这里结束：Add Admin
  // ==========================

  // ==========================
  // 从这里开始：主 UI 构建（保留原有风格）
  // ==========================
  @override
  Widget build(BuildContext context) {
    final accent  = const Color(0xFF8B6B4A);
    final primary = const Color(0xFF5E4631);

    double audioRatio() {
      final total = audioCount + textCount;
      return total == 0 ? 0 : audioCount / total;
    }

    double textRatio() {
      final total = audioCount + textCount;
      return total == 0 ? 0 : textCount / total;
    }

    int emotionsTotal() => emotionCount.values.fold<int>(0, (p, e) => p + e);

    double growthPct(int current, int prev) {
      if (prev <= 0) return current > 0 ? 100 : 0;
      return (current - prev) * 100 / prev;
    }

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
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800, color: primary)),
                  const SizedBox(height: 6),
                  Text('Manage users and monitor activity',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: primary)),
                  const SizedBox(height: 14),
                  const Divider(thickness: 1, color: Color(0x22000000)),

                  // 顶部两个操作卡片（不改）
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _bigAction(
                        icon: Icons.group,
                        label: 'Manage Users',
                        onTap: _openManageUsers,
                      ),
                      const SizedBox(width: 12),
                      _bigAction(
                        icon: Icons.person_add_alt_1,
                        label: 'Add Admin',
                        onTap: _openAddAdminDialog,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 概览 KPI
                  _statsCard(
                    title: 'At a glance',
                    subtitle: 'System-wide overview (last 30 days for activity)',
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          _kpiBlock('Users', '$totalUsers'),
                          _kpiBlock('Active (30d)', '$activeUsersLast30d'),
                          _kpiBlock('Messages', '$totalMessages'),
                          _kpiBlock('Chats', '$totalChats'),
                        ],
                      ),
                    ),
                  ),

                  // Chat Duration
                  _statsCard(
                    title: 'Chat Duration',
                    subtitle: 'Total ${_fmtMin(totalDurationMin)} · Avg ${avgDurationMin.toStringAsFixed(1)}m/chat',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Kpi(label: _fmtMin(totalDurationMin)), // 显示总时长
                        _Kpi(label: '${avgDurationMin.toStringAsFixed(1)}m/chat'), // 显示平均时长
                      ],
                    ),
                  ),

                  // Audio/Text 比例条
                  _statsCard(
                    title: 'Audio/Text Ratio',
                    subtitle: 'Share of message types',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _stackedBar(audioRatio(), textRatio()),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _legendDot('Audio', audioCount),
                              _legendDot('Text',  textCount),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Top Emotions 百分比
                  _statsCard(
                    title: 'Top Emotions',
                    subtitle: 'Across all messages',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _emotionChip('Happy',   emotionCount['happy']   ?? 0, emotionsTotal()),
                          _emotionChip('Sad',     emotionCount['sad']     ?? 0, emotionsTotal()),
                          _emotionChip('Angry',   emotionCount['angry']   ?? 0, emotionsTotal()),
                          _emotionChip('Neutral', emotionCount['neutral'] ?? 0, emotionsTotal()),
                        ],
                      ),
                    ),
                  ),

                  // 最近 7 天活动
                  _statsCard(
                    title: 'Last 7 Days Activity',
                    subtitle: 'Messages per day · Active users: $activeUsersLast7d  (Δ ${growthPct(activeUsersLast7d, activeUsersPrev7d).toStringAsFixed(0)}%)',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: _sparkBars(msgsLast7d),
                    ),
                  ),

                  // Top Users（点击弹窗）
                  _statsCard(
                    title: 'Top Users',
                    subtitle: 'Most messages in last 30 days',
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        for (final u in topUsers)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              u.name.isEmpty ? '(No name)' : u.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF5E4631)),
                            ),
                            subtitle: Text(
                              // 保留原显示：有 email 显示 email，否则显示 uid
                              u.email.isEmpty ? u.uid : u.email,
                              style: const TextStyle(color: Color(0xFF5E4631)),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFE3D3),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Text('${u.count} msgs', style: const TextStyle(color: Color(0xFF5E4631))),
                            ),
                            onTap: () => _showUserStatsDialog(u), // 👉 新增：点击查看该用户汇总统计
                          ),
                        if (topUsers.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('— No data in last 30 days —', style: TextStyle(color: Color(0xFF5E4631))),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(thickness: 1, color: Color(0x22000000)),
                  const SizedBox(height: 8),

                  // Logout（不改）
                  Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (mounted) {
                          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
                        }
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Logout'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF8B6B4A),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_loadingStats)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
  // ==========================
  // 到这里结束：主 UI
  // ==========================

  // ---------- 从这里开始：UI 辅助小组件（保持你的风格） ----------
  static String _fmtMin(int totalMin) {
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h <= 0) return '${m}m';
    return '${h}h ${m}m';
  }

  static Widget _legendDot(String label, int value) {
    return Row(
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: const Color(0xFF5E4631), borderRadius: BorderRadius.circular(99)),
        ),
        const SizedBox(width: 6),
        Text('$label  ·  $value', style: const TextStyle(color: Color(0xFF5E4631))),
      ],
    );
  }

  Widget _bigAction({required IconData icon, required String label, required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E9),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: const Color(0xFF5E4631)),
              const SizedBox(height: 12),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF5E4631))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsCard({required String title, required String subtitle, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E9),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF5E4631))),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: Color(0xFF5E4631))),
        const SizedBox(height: 8),
        child,
      ]),
    );
  }

  static Widget _kpiBlock(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFEFE3D3), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF5E4631))),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Color(0xFF5E4631))),
        ],
      ),
    );
  }

  static Widget _stackedBar(double left, double right) {
    return LayoutBuilder(builder: (context, c) {
      final totalW = c.maxWidth;
      final leftW  = totalW * left;
      final rightW = totalW * right;
      return Row(
        children: [
          Container(
            height: 10, width: leftW,
            decoration: const BoxDecoration(
              color: Color(0xFF5E4631),
              borderRadius: BorderRadius.horizontal(left: Radius.circular(6)),
            ),
          ),
          Container(
            height: 10, width: rightW,
            decoration: const BoxDecoration(
              color: Color(0xFFC9B29B),
              borderRadius: BorderRadius.horizontal(right: Radius.circular(6)),
            ),
          ),
        ],
      );
    });
  }

  static Widget _emotionChip(String label, int value, int total) {
    final pct = total == 0 ? 0 : (value * 100 / total);
    return Chip(
      label: Text('$label · ${pct.toStringAsFixed(1)}% ($value)'),
      backgroundColor: const Color(0xFFEFE3D3),
      labelStyle: const TextStyle(color: Color(0xFF5E4631)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }

  static Widget _sparkBars(List<int> data) {
    if (data.isEmpty) return const SizedBox.shrink();
    final maxV = data.reduce((a, b) => math.max(a, b));
    return SizedBox(
      height: 60,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < data.length; i++) ...[
            Expanded(
              child: Container(
                height: maxV == 0 ? 2 : (50.0 * data[i] / maxV + 2),
                decoration: BoxDecoration(color: const Color(0xFFC9B29B), borderRadius: BorderRadius.circular(6)),
              ),
            ),
            if (i != data.length - 1) const SizedBox(width: 6),
          ]
        ],
      ),
    );
  }
// ---------- 到这里结束：UI 辅助小组件 ----------
}

// Top 用户数据结构
class _TopUser {
  final String uid;
  final String name;
  final String email;
  final int count;
  _TopUser({required this.uid, required this.name, required this.email, required this.count});
}

// ==========================
// 从这里开始：底部弹窗 - Manage Users（支持搜索/禁用/删除数据）
// 注：subtitle 统一显示 Email 或 UID
// ==========================
class _ManageUsersSheet extends StatefulWidget {
  const _ManageUsersSheet();

  @override
  State<_ManageUsersSheet> createState() => _ManageUsersSheetState();
}

class _ManageUsersSheetState extends State<_ManageUsersSheet> {
  final db = FirebaseDatabase.instance.ref();
  bool loading = true;
  String? error;
  List<_UserRow> rows = [];
  List<_UserRow> filtered = [];
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; rows = []; filtered = []; });

    try {
      final usersSnap = await db.child('users').get();
      if (usersSnap.exists) {
        for (final u in usersSnap.children) {
          final uid = u.key!;
          final username = (u.child('username').value ?? '').toString();
          final email = (u.child('email').value ?? '').toString();
          final disabled = (u.child('status').child('disabled').value ?? false).toString() == 'true';
          rows.add(_UserRow(
            uid: uid,
            username: username.isEmpty ? '(No name)' : username,
            email: email,
            disabled: disabled,
          ));
        }
      }
      filtered = List.from(rows);
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      filtered = q.isEmpty
          ? List.from(rows)
          : rows.where((e) =>
      e.username.toLowerCase().contains(q) ||
          e.email.toLowerCase().contains(q) ||
          e.uid.toLowerCase().contains(q))
          .toList();
    });
  }

  Future<void> _toggleDisable(_UserRow row) async {
    try {
      final newVal = !row.disabled;
      await db.child('users/${row.uid}/status/disabled').set(newVal);
      setState(() => row.disabled = newVal);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(newVal ? 'User disabled' : 'User enabled')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update status')));
    }
  }

  Future<void> _deleteUserData(_UserRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFFFF7E9),
        title: const Text('Delete user data?'),
        content: Text(
          'This will remove the user profile and all chathistory of\n${row.email.isEmpty ? row.uid : row.email}.\n\nIt will NOT delete the authentication account.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await FirebaseDatabase.instance.ref('users/${row.uid}').remove();
      await FirebaseDatabase.instance.ref('chathistory/${row.uid}').remove();
      setState(() {
        rows.removeWhere((e) => e.uid == row.uid);
        filtered.removeWhere((e) => e.uid == row.uid);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User data deleted')));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16, right: 16, top: 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 14),
            Row(
              children: const [
                Icon(Icons.group, color: Color(0xFF5E4631)),
                SizedBox(width: 8),
                Text('Manage Users', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF5E4631))),
              ],
            ),
            const SizedBox(height: 10),

            // 搜索
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name / email / uid',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            if (loading) const LinearProgressIndicator(minHeight: 2),
            if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: Colors.red))),

            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('No users', style: TextStyle(color: Color(0xFF5E4631))),
              )
                  : ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  return ListTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.username,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (r.disabled)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFFECCFCF), borderRadius: BorderRadius.circular(6)),
                            child: const Text('Disabled', style: TextStyle(color: Color(0xFF5E4631))),
                          ),
                      ],
                    ),
                    // 👉 统一：subtitle 优先显示 email；没有则显示 uid
                    subtitle: Text(r.email.isEmpty ? r.uid : r.email),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => _toggleDisable(r),
                          child: Text(r.disabled ? 'Enable' : 'Disable'),
                        ),
                        TextButton(
                          onPressed: () => _deleteUserData(r),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// Manage Users 列表中的数据结构
class _UserRow {
  final String uid;
  final String username;
  final String email;
  bool disabled;
  _UserRow({required this.uid, required this.username, required this.email, required this.disabled});
}

// 小 KPI 文本（你原本用在 Chat Duration 卡片里）
class _Kpi extends StatelessWidget {
  final String label;
  const _Kpi({required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Color(0xFF5E4631))),
      ],
    );
  }
}