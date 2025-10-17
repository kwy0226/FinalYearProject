import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'background_widget.dart';

// TODO: 把你的 OpenAI Key 放这里
const String openAIApiKey = "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";

class ChartPage extends StatefulWidget {
  const ChartPage({Key? key}) : super(key: key);

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance.ref();

  // 每日情绪计数与总计
  final Map<String, Map<String, int>> dailyEmotionCounts = {};
  final Map<String, int> totalEmotionCounts = {
    "happy": 0,
    "sad": 0,
    "angry": 0,
    "neutral": 0,
  };

  // 底部导航
  int _tabIndex = 2;

  // 月份/年份
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;

  // GPT 建议
  String gptSuggestion = "";
  bool isLoadingSuggestion = false;

  // 关键点：持久化 Future，避免重建时不断新建 Future
  late Future<void> _loadFuture;

  final List<String> monthNames = const [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
  ];

  @override
  void initState() {
    super.initState();
    _loadFuture = fetchEmotionData();
  }

  // 从 Firebase 拉取并聚合当月情绪
  Future<void> fetchEmotionData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    dailyEmotionCounts.clear();
    totalEmotionCounts.updateAll((key, value) => 0);

    try {
      final uid = user.uid;
      final snapshot = await _db.child("chathistory/$uid").get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        for (final chatEntry in data.entries) {
          final messages = chatEntry.value['messages'];
          if (messages is Map) {
            for (final msgEntry in messages.entries) {
              final msgData = msgEntry.value;
              if (msgData is Map && msgData['emotion'] != null) {
                final createdAt = msgData['createdAt'];
                if (createdAt == null) continue;

                final createdDate =
                DateTime.fromMillisecondsSinceEpoch(createdAt);
                if (createdDate.isAfter(DateTime.now())) continue;
                if (createdDate.month != selectedMonth ||
                    createdDate.year != selectedYear) continue;

                final labelRaw =
                (msgData['emotion']['label'] ?? '').toString().toLowerCase();

                String? label;
                if (labelRaw == 'joy') {
                  label = 'happy';
                } else if (['sad', 'angry', 'neutral'].contains(labelRaw)) {
                  label = labelRaw;
                }
                if (label == null) continue;

                final dateStr =
                createdDate.toLocal().toString().substring(0, 10);

                dailyEmotionCounts.putIfAbsent(dateStr, () => {
                  "happy": 0,
                  "sad": 0,
                  "angry": 0,
                  "neutral": 0,
                });

                dailyEmotionCounts[dateStr]![label] =
                    dailyEmotionCounts[dateStr]![label]! + 1;
                totalEmotionCounts[label] = totalEmotionCounts[label]! + 1;
              }
            }
          }
        }
      }
    } catch (_) {
      // 忽略，保持空数据状态即可
    }

    await _generateGptSuggestion();
  }

  Map<String, double> calculateRatios() {
    final total = totalEmotionCounts.values.fold(0, (a, b) => a + b);
    if (total == 0) {
      return {"happy": 0, "sad": 0, "angry": 0, "neutral": 0};
    }
    return {
      "happy": totalEmotionCounts["happy"]! / total,
      "sad": totalEmotionCounts["sad"]! / total,
      "angry": totalEmotionCounts["angry"]! / total,
      "neutral": totalEmotionCounts["neutral"]! / total,
    };
  }

  // GPT：生成简洁建议（2 句以内），并加超时，失败不阻塞 UI
  Future<void> _generateGptSuggestion() async {
    final mostFrequent =
    totalEmotionCounts.entries.reduce((a, b) => a.value >= b.value ? a : b);

    if (mostFrequent.value == 0) {
      setState(() => gptSuggestion = "No data for this month.");
      return;
    }
    if (openAIApiKey.isEmpty) {
      setState(() => gptSuggestion = "No GPT API key provided.");
      return;
    }

    setState(() => isLoadingSuggestion = true);

    final prompt =
        "Analyze user's monthly emotions. Most frequent: '${mostFrequent.key}'. "
        "Give short, practical mental-health advice in max 2 sentences, "
        "without any preface.";

    try {
      final resp = await http
          .post(
        Uri.parse("https://api.openai.com/v1/chat/completions"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $openAIApiKey",
        },
        body: jsonEncode({
          "model": "gpt-3.5-turbo",
          "messages": [
            {
              "role": "system",
              "content": "You are a helpful mental health assistant."
            },
            {"role": "user", "content": prompt},
          ],
          "max_tokens": 120,
        }),
      )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final content =
        jsonDecode(resp.body)["choices"][0]["message"]["content"];
        setState(() => gptSuggestion = (content ?? "").toString().trim());
      } else {
        setState(() =>
        gptSuggestion = "Failed to get suggestion (Error ${resp.statusCode}).");
      }
    } catch (_) {
      setState(() => gptSuggestion = "GPT suggestion unavailable right now.");
    } finally {
      if (mounted) setState(() => isLoadingSuggestion = false);
    }
  }

  // 详情弹窗
  void _showDetailDialog(String emotion) {
    final details = dailyEmotionCounts.entries
        .where((e) => e.value[emotion]! > 0)
        .map((e) => "${e.key}: ${e.value[emotion]} times")
        .toList();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("${emotion[0].toUpperCase()}${emotion.substring(1)} Details"),
        content: details.isEmpty
            ? const Text("No records for this emotion this month.")
            : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: details.map((e) => Text(e)).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }

  // 顶部三个统计小卡片
  Widget _buildSummaryCards() {
    final totalChats = totalEmotionCounts.values.fold(0, (a, b) => a + b);
    final mostFrequent =
    totalEmotionCounts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final activeDays = dailyEmotionCounts.length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _summaryCard("Total Chats", "$totalChats"),
        _summaryCard("Top Emotion", mostFrequent.value == 0 ? "-" : mostFrequent.key),
        _summaryCard("Active Days", "$activeDays"),
      ],
    );
  }

  Widget _summaryCard(String title, String value) {
    return Expanded(
      child: Card(
        color: const Color(0xFFFFF7E9),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(title, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ratios = calculateRatios();
    final total = totalEmotionCounts.values.fold(0, (a, b) => a + b);

    return Scaffold(
      body: Stack(
        children: [
          const AppBackground(),
          SafeArea(
            child: FutureBuilder<void>(
              future: _loadFuture, // ✅ 使用持久化的 future
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        "Emotion Trend Chart",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Divider(
                      color: Color(0xFFB08968), // 你可以换成你喜欢的颜色
                      thickness: 1.2,           // 线条粗细
                      indent: 20,              // 左边缩进
                      endIndent: 20,           // 右边缩进
                    ),
                    // 月份/年份选择
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        DropdownButton<int>(
                          value: selectedMonth,
                          items: List.generate(
                            12,
                                (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text(monthNames[i]),
                            ),
                          ),
                          onChanged: (v) {
                            if (v == null) return;
                            selectedMonth = v;
                            _loadFuture = fetchEmotionData(); // 触发重拉
                            setState(() {});
                          },
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: selectedYear,
                          items: List.generate(
                            5,
                                (i) {
                              final y = DateTime.now().year - 2 + i;
                              return DropdownMenuItem(value: y, child: Text("$y"));
                            },
                          ),
                          onChanged: (v) {
                            if (v == null) return;
                            selectedYear = v;
                            _loadFuture = fetchEmotionData(); // 触发重拉
                            setState(() {});
                          },
                        ),
                      ],
                    ),

                    if (total == 0)
                      const Expanded(
                        child: Center(child: Text("No data for this month.")),
                      )
                    else
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              SizedBox(
                                height: 260,
                                child: PieChart(
                                  PieChartData(
                                    sectionsSpace: 2,
                                    centerSpaceRadius: 0,
                                    sections: [
                                      _pieSection("happy", ratios["happy"]!, const Color(0xFF9FE2BF)),
                                      _pieSection("sad", ratios["sad"]!, const Color(0xFFAEC6CF)),
                                      _pieSection("angry", ratios["angry"]!, const Color(0xFFF4C2C2)),
                                      _pieSection("neutral", ratios["neutral"]!, const Color(0xFFDCDCDC)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildSummaryCards(),
                              const SizedBox(height: 8),
                              _emotionStatList(ratios),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: isLoadingSuggestion
                                    ? const Center(child: CircularProgressIndicator())
                                    : Text(
                                  gptSuggestion,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),

      // 底部导航（与首页一致）
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
          onTap: (index) {
            if (index == _tabIndex) return;
            setState(() => _tabIndex = index);
            switch (index) {
              case 0:
                Navigator.pushReplacementNamed(context, '/home');
                break;
              case 1:
                Navigator.pushReplacementNamed(context, '/chats');
                break;
              case 2:
                break;
              case 3:
                Navigator.pushReplacementNamed(context, '/settings');
                break;
            }
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFFFFF7E9),
          selectedItemColor: const Color(0xFF8B6B4A),
          unselectedItemColor: const Color(0xFF5E4631).withOpacity(0.6),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Homepage'),
            BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: 'Chats'),
            BottomNavigationBarItem(icon: Icon(Icons.insights_rounded), label: 'Chart'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
          ],
        ),
      ),
    );
  }

  PieChartSectionData _pieSection(String emotion, double ratio, Color color) {
    if (ratio == 0) return PieChartSectionData(value: 0);
    return PieChartSectionData(
      color: color,
      value: ratio * 100,
      title: emotion[0].toUpperCase() + emotion.substring(1),
      radius: 120, // 放大
      titleStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
    );
  }

  Widget _emotionStatList(Map<String, double> ratios) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFFFFF7E9),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            _emotionRow("happy", "assets/images/happy_cat.png", ratios),
            _emotionRow("sad", "assets/images/sad_cat.png", ratios),
            _emotionRow("angry", "assets/images/angry_cat.png", ratios),
            _emotionRow("neutral", "assets/images/neutral_cat.png", ratios),
          ],
        ),
      ),
    );
  }

  Widget _emotionRow(String type, String imagePath, Map<String, double> ratios) {
    return InkWell(
      onTap: () => _showDetailDialog(type),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Image.asset(imagePath, width: 24, height: 24),
            const SizedBox(width: 6),
            Text(
              "${type[0].toUpperCase()}${type.substring(1)} ${(ratios[type]! * 100).toStringAsFixed(1)}% (${totalEmotionCounts[type]} times)",
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
