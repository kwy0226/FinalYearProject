import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'background_widget.dart';

/// ✅ 填自己的 Key
const String openAIApiKey = "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";

class ChartPage extends StatefulWidget {
  const ChartPage({Key? key}) : super(key: key);

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance.ref();

  /// Daily Statistics (for PieChart)
  final Map<String, Map<String, int>> dailyEmotionCounts = {};
  final Map<String, int> totalEmotionCounts = {
    "happy": 0,
    "sad": 0,
    "angry": 0,
    "neutral": 0,
  };

  /// Time series for line charts
  final List<Map<String, dynamic>> messageTimeline = [];

  int _tabIndex = 2;
  int selectedMonth = DateTime
      .now()
      .month;
  int selectedYear = DateTime
      .now()
      .year;

  String gptSuggestion = "";
  bool isLoadingSuggestion = true;

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

  /// Read Firebase Sentiment Data + Timeline
  Future<void> fetchEmotionData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    dailyEmotionCounts.clear();
    messageTimeline.clear();
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
              final msg = msgEntry.value;

              if (msg is Map && msg['emotion'] != null) {
                final createdAt = msg['createdAt'];
                if (createdAt == null) continue;

                final createdDate =
                DateTime.fromMillisecondsSinceEpoch(createdAt);

                if (createdDate.isAfter(DateTime.now())) continue;
                if (createdDate.month != selectedMonth ||
                    createdDate.year != selectedYear) continue;

                final rawLabel =
                (msg['emotion']['label'] ?? "").toString().toLowerCase();

                String? label;
                if (rawLabel == "joy")
                  label = "happy";
                else if (["sad", "angry", "neutral"].contains(rawLabel))
                  label = rawLabel;
                if (label == null) continue;

                /// PieChart
                final dateStr = createdDate.toString().substring(0, 10);
                dailyEmotionCounts.putIfAbsent(dateStr, () =>
                {
                  "happy": 0,
                  "sad": 0,
                  "angry": 0,
                  "neutral": 0,
                });
                dailyEmotionCounts[dateStr]![label] =
                    dailyEmotionCounts[dateStr]![label]! + 1;

                totalEmotionCounts[label] = totalEmotionCounts[label]! + 1;

                /// Line Chart
                messageTimeline.add({
                  "time": createdDate,
                  "text": msg["content"] ?? "",
                  "emotion": label,
                });
              }
            }
          }
        }
      }

      /// Time Sorting (required for line charts)
      messageTimeline.sort((a, b) =>
          a["time"].compareTo(b["time"]));
    } catch (_) {}

    await _generateGptSuggestion();
  }

  /// PieChart Ratio
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

  /// emotion converted to height (line chart Y-axis)
  double emotionScore(String e) {
    switch (e) {
      case "happy":
        return 3;
      case "neutral":
        return 2;
      case "sad":
        return 1;
      case "angry":
        return 0;
    }
    return 0;
  }

  /// Line Chart Point
  List<FlSpot> _buildLineSpots() {
    List<FlSpot> spots = [];
    for (int i = 0; i < messageTimeline.length; i++) {
      spots.add(
        FlSpot(i.toDouble(), emotionScore(messageTimeline[i]["emotion"])),
      );
    }
    return spots;
  }

  /// LineChart with popup dialog
  Widget _buildEmotionLineChart() {
    if (messageTimeline.isEmpty) return const SizedBox();

    final spots = _buildLineSpots();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            "Daily Emotion Fluctuation",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 3,
                gridData: FlGridData(show: true),

                /// Click here → Pop-up window displays full content
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchCallback: (event, response) {
                    if (event is FlTapUpEvent &&
                        response?.lineBarSpots != null) {
                      final idx = response!.lineBarSpots![0].x.toInt();
                      final node = messageTimeline[idx];

                      showDialog(
                        context: context,
                        builder: (_) =>
                            AlertDialog(
                              title: Text("Emotion: ${node["emotion"]}"),
                              content: Text(
                                "Time: ${node["time"]}\n\nMessage:\n${node["text"]}",
                                style: const TextStyle(fontSize: 14),
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
                  },
                ),

                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          switch (v.toInt()) {
                            case 3:
                              return const Text(
                                  "Happy", style: TextStyle(fontSize: 10));
                            case 2:
                              return const Text(
                                  "Neutral", style: TextStyle(fontSize: 10));
                            case 1:
                              return const Text(
                                  "Sad", style: TextStyle(fontSize: 10));
                            case 0:
                              return const Text(
                                  "Angry", style: TextStyle(fontSize: 10));
                          }
                          return const SizedBox();
                        }),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),

                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    color: const Color(0xFF8B6B4A),
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    spots: spots,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// GPT Summary
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
        "Analyze user's monthly emotions. Most frequent: '${mostFrequent
        .key}'. "
        "Give short, practical mental-health advice in max 2 sentences.";

    try {
      final resp = await http.post(
        Uri.parse("https://api.openai.com/v1/chat/completions"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $openAIApiKey",
        },
        body: jsonEncode({
          "model": "gpt-4o-mini",
          "messages": [
            {"role": "system", "content": "You are a friendly assistant."},
            {"role": "user", "content": prompt},
          ],
          "max_tokens": 100,
        }),
      ).timeout(const Duration(seconds: 15));

      print(resp.body);

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        String? result;

        if (json["choices"] != null) {
          // Supports standard formatting
          if (json["choices"][0]["message"]?["content"] != null) {
            result = json["choices"][0]["message"]["content"];
          }
          // Supports delta format (avoids “No suggestion”)
          else if (json["choices"][0]["delta"]?["content"] != null) {
            result = json["choices"][0]["delta"]["content"];
          }
        }

        setState(() =>
        gptSuggestion = result?.trim() ?? "No suggestion generated.");
      } else {
        setState(() => gptSuggestion = "Failed (${resp.statusCode}).");
      }
    } catch (e) {
      setState(() => gptSuggestion = "GPT suggestion unavailable.");
    } finally {
      if (mounted) setState(() => isLoadingSuggestion = false);
    }
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
            child: FutureBuilder(
              future: _loadFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                return Column(
                  children: [
                    const SizedBox(height: 16),
                    const Text(
                      "Emotion Trend Chart",
                      style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const Divider(
                        color: Color(0xFFB08968), indent: 20, endIndent: 20),

                    /// Month Selection
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        DropdownButton<int>(
                          value: selectedMonth,
                          items: List.generate(
                              12,
                                  (i) =>
                                  DropdownMenuItem(
                                      value: i + 1,
                                      child: Text(monthNames[i]))),
                          onChanged: (v) {
                            selectedMonth = v!;
                            _loadFuture = fetchEmotionData();
                            setState(() {});
                          },
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: selectedYear,
                          items: List.generate(5, (i) {
                            final y = DateTime
                                .now()
                                .year - 2 + i;
                            return DropdownMenuItem(
                                value: y, child: Text("$y"));
                          }),
                          onChanged: (v) {
                            selectedYear = v!;
                            _loadFuture = fetchEmotionData();
                            setState(() {});
                          },
                        ),
                      ],
                    ),

                    /// No Data
                    if (total == 0)
                      const Expanded(
                        child:
                        Center(child: Text("No data for this month.")),
                      )

                    /// Data available → Pie + Line + Stats + GPT
                    else
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              SizedBox(
                                height: 250,
                                child: PieChart(
                                  PieChartData(
                                    sections: [
                                      _pieSection("happy", ratios["happy"]!,
                                          const Color(0xFF9FE2BF)),
                                      _pieSection("sad", ratios["sad"]!,
                                          const Color(0xFFAEC6CF)),
                                      _pieSection("angry", ratios["angry"]!,
                                          const Color(0xFFF4C2C2)),
                                      _pieSection("neutral", ratios["neutral"]!,
                                          const Color(0xFFDCDCDC)),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              /// Curve & Click Popup (Version B)
                              _buildEmotionLineChart(),

                              const SizedBox(height: 10),
                              _buildSummaryCards(),
                              const SizedBox(height: 10),
                              _emotionStatList(ratios),

                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: isLoadingSuggestion
                                    ? const CircularProgressIndicator()
                                    : Text(
                                  gptSuggestion,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      fontSize: 13),
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

      /// Bottom Nav
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) {
          if (i == _tabIndex) return;
          setState(() => _tabIndex = i);
          switch (i) {
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
        unselectedItemColor: const Color(0xFF5E4631),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded), label: 'Homepage'),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_rounded), label: 'Chats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.insights_rounded), label: 'Chart'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }

  /// PieChart Section builder
  PieChartSectionData _pieSection(String emotion, double ratio, Color color) {
    if (ratio == 0) return PieChartSectionData(value: 0);
    return PieChartSectionData(
      color: color,
      value: ratio * 100,
      title: emotion[0].toUpperCase() + emotion.substring(1),
      radius: 120,
      titleStyle:
      const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
    );
  }

  /// Summary Cards
  Widget _buildSummaryCards() {
    final totalChats = totalEmotionCounts.values.fold(0, (a, b) => a + b);
    final mostFrequent = totalEmotionCounts.entries
        .reduce((a, b) => a.value >= b.value ? a : b);
    final activeDays = dailyEmotionCounts.length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _summaryCard("Total Chats", "$totalChats"),
        _summaryCard("Top Emotion", mostFrequent.key),
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
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              Text(title, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  /// Small List Statistics
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

  Widget _emotionRow(String type, String imagePath,
      Map<String, double> ratios) {
    return InkWell(
      onTap: () => _showDetailDialog(type),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Image.asset(imagePath, width: 26, height: 26),
            const SizedBox(width: 8),
            Text(
              "${type[0].toUpperCase()}${type.substring(1)} "
                  "${(ratios[type]! * 100).toStringAsFixed(1)}% "
                  "(${totalEmotionCounts[type]} times)",
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetailDialog(String emotion) {
    final details = dailyEmotionCounts.entries
        .where((e) => e.value[emotion]! > 0)
        .map((e) => "${e.key}: ${e.value[emotion]} times")
        .toList();

    showDialog(
      context: context,
      builder: (_) =>
          AlertDialog(
            title: Text("${emotion[0].toUpperCase()}${emotion.substring(
                1)} Details"),
            content: details.isEmpty
                ? const Text("No records for this emotion in this month.")
                : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: details.map((e) => Text(e)).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          ),
    );
  }
}