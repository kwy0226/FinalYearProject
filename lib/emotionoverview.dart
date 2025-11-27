import 'dart:async';
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'background_widget.dart';

//  GPT Summary config
const bool USE_GPT_SUMMARY = true;
const String OPENAI_API_KEY =
    "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";
const String OPENAI_ENDPOINT = "https://api.openai.com/v1/chat/completions";
const String OPENAI_MODEL = "gpt-4o-mini";

class EmotionOverviewPage extends StatefulWidget {
  const EmotionOverviewPage({Key? key}) : super(key: key);

  @override
  State<EmotionOverviewPage> createState() => _EmotionOverviewPageState();
}

class _EmotionOverviewPageState extends State<EmotionOverviewPage> {
  final db = FirebaseDatabase.instance.ref();

  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;
  bool loading = true;
  String? error;

  Map<String, int> emotionTotal = {"happy": 0, "sad": 0, "angry": 0, "neutral": 0};
  Map<String, Map<String, int>> byType = {
    "audio": {"happy": 0, "sad": 0, "angry": 0, "neutral": 0},
    "text": {"happy": 0, "sad": 0, "angry": 0, "neutral": 0},
  };

  List<double?> dailyAvg = [];
  int improvedUsers = 0, sameUsers = 0, worsenedUsers = 0;
  String? aiSummary;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final start = DateTime(selectedYear, selectedMonth, 1);
      final end = DateTime(selectedYear, selectedMonth + 1, 1);
      final startMs = start.millisecondsSinceEpoch;
      final endMs = end.millisecondsSinceEpoch;
      emotionTotal.updateAll((k, v) => 0);
      byType["audio"]!.updateAll((k, v) => 0);
      byType["text"]!.updateAll((k, v) => 0);

      final daysInMonth = DateTime(selectedYear, selectedMonth + 1, 0).day;
      dailyAvg = List<double?>.filled(daysInMonth, null);
      final dailyScores = List.generate(daysInMonth, (_) => <int>[]);
      final Map<String, _EdgeMsg> first = {};
      final Map<String, _EdgeMsg> last = {};

      final all = await db.child('chathistory').get();
      if (all.exists) {
        for (final user in all.children) {
          final uid = user.key ?? '';
          for (final chat in user.children) {
            final msgs = chat.child('messages');
            if (!msgs.exists) continue;
            for (final m in msgs.children) {
              final t = int.tryParse('${m.child('createdAt').value}') ?? 0;
              if (t < startMs || t >= endMs) continue;
              final label = (m.child('emotion/label').value ?? '').toString().toLowerCase();
              if (!emotionTotal.containsKey(label)) continue;

              emotionTotal[label] = (emotionTotal[label]! + 1);
              String type = (m.child('type').value ?? '').toString().toLowerCase();
              if (type != 'audio' && type != 'text') type = 'text';
              byType[type]![label] = (byType[type]![label]! + 1);

              final day = DateTime.fromMillisecondsSinceEpoch(t).day - 1;
              dailyScores[day].add(_score(label));

              final score = _score(label);
              final e = _EdgeMsg(createdAt: t, score: score);
              if (!first.containsKey(uid) || t < first[uid]!.createdAt) first[uid] = e;
              if (!last.containsKey(uid) || t > last[uid]!.createdAt) last[uid] = e;
            }
          }
        }
      }

      for (int i = 0; i < daysInMonth; i++) {
        if (dailyScores[i].isNotEmpty) {
          final avg = dailyScores[i].reduce((a, b) => a + b) / dailyScores[i].length;
          dailyAvg[i] = avg;
        }
      }

      int imp = 0, same = 0, worse = 0;
      for (final uid in first.keys) {
        final f = first[uid]!, l = last[uid]!;
        if (l.score > f.score) imp++;
        else if (l.score == f.score) same++;
        else worse++;
      }
      improvedUsers = imp;
      sameUsers = same;
      worsenedUsers = worse;

      aiSummary = await _buildSummary(start);
      setState(() => loading = false);
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  int _score(String e) => e == 'happy' ? 3 : e == 'neutral' ? 2 : e == 'sad' ? 1 : 0;

  Future<String> _buildSummary(DateTime monthStart) async {
    final total = emotionTotal.values.fold(0, (a, b) => a + b);
    String pct(String k) =>
        total == 0 ? "0%" : "${(emotionTotal[k]! * 100 / total).toStringAsFixed(1)}%";
    String typeBreak(String t) {
      final map = byType[t]!;
      final totalT = map.values.fold(0, (a, b) => a + b);
      if (totalT == 0) return "$t: no data";
      pct2(String e) => "${(map[e]! * 100 / totalT).toStringAsFixed(0)}%";
      return "$t → Happy ${pct2('happy')}, Neutral ${pct2('neutral')}, Sad ${pct2('sad')}, Angry ${pct2('angry')}";
    }

    final monthName = _monthStr(selectedMonth);
    final local =
        "For $monthName $selectedYear, overall emotions were Happy ${pct('happy')}, Neutral ${pct('neutral')}, Sad ${pct('sad')}, Angry ${pct('angry')}. "
        "By type: ${typeBreak('audio')}; ${typeBreak('text')}. "
        "Improvement: $improvedUsers improved, $sameUsers unchanged, $worsenedUsers worsened.";

    if (!USE_GPT_SUMMARY || OPENAI_API_KEY.isEmpty) return local;

    final prompt = """
You are an emotion analytics assistant. Summarize user emotions for $monthName $selectedYear.
Include: (1) dominant and least common emotion, (2) difference between text and audio, (3) improvement rate, and (4) general trend. 
Keep it concise (4–6 sentences) and factual.
""";

    try {
      final r = await http.post(Uri.parse(OPENAI_ENDPOINT),
          headers: {
            "Authorization": "Bearer $OPENAI_API_KEY",
            "Content-Type": "application/json"
          },
          body: jsonEncode({
            "model": OPENAI_MODEL,
            "messages": [
              {"role": "system", "content": "You are a data analyst."},
              {"role": "user", "content": prompt}
            ]
          }));
      final j = jsonDecode(r.body);
      return j["choices"]?[0]?["message"]?["content"] ?? local;
    } catch (_) {
      return local;
    }
  }

  // ========== UI ==========
  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF5E4631);
    return Scaffold(
      body: Stack(
        children: [
          const AppBackground(),
          SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 90),
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                    ? Center(child: Text(error!, style: const TextStyle(color: Colors.red)))
                    : SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Emotion Overview",
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: primary)),
                          const SizedBox(height: 8),
                          _monthPicker(),
                          const SizedBox(height: 12),
                          _card("Overall Emotion Distribution", _pie()),
                          _card("Emotion by Message Type (Text vs Audio)", _bar()),
                          _card("Daily Average Mood (This Month)", _trend()),
                          _card("Improvement Rate", _improve()),
                          _card(
                              "Summary",
                              Text(aiSummary ?? "",
                                  style: const TextStyle(
                                      color: Color(0xFF5E4631), height: 1.4)))
                        ]))),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: const Color(0xFFFFF7E9),
              padding: const EdgeInsets.all(10),
              child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text("Back to Admin Home"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB08968),
                      foregroundColor: Colors.white)),
            ),
          )
        ],
      ),
    );
  }

  Widget _monthPicker() {
    final months = List.generate(12, (i) => i + 1);
    final years = List.generate(5, (i) => DateTime.now().year - i);
    return Row(children: [
      Expanded(
          child: DropdownButton<int>(
              isExpanded: true,
              value: selectedMonth,
              items: months
                  .map((m) => DropdownMenuItem(value: m, child: Text(_monthStr(m))))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => selectedMonth = v);
                  _loadAll();
                }
              })),
      const SizedBox(width: 12),
      Expanded(
          child: DropdownButton<int>(
              isExpanded: true,
              value: selectedYear,
              items: years
                  .map((y) => DropdownMenuItem(value: y, child: Text("$y")))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => selectedYear = v);
                  _loadAll();
                }
              }))
    ]);
  }

  String _monthStr(int m) =>
      ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][m - 1];

  Widget _card(String title, Widget child) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFFFFF7E9),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5E4631))),
        const SizedBox(height: 6),
        child
      ]));

  Widget _bar() {
    double safeY(double y) => y <= 0 ? 0.5 : y;
    const colors = {
      "happy": Colors.amber,
      "sad": Colors.blue,
      "angry": Colors.red,
      "neutral": Colors.grey
    };

    BarChartGroupData g(String t, int x) {
      final total = byType[t]!.values.fold(0, (a, b) => a + b);
      double pct(String e) => total == 0 ? 0 : byType[t]![e]! * 100 / total;
      return BarChartGroupData(x: x, barRods: [
        BarChartRodData(toY: safeY(pct('happy')), width: 12, color: colors['happy']),
        BarChartRodData(toY: safeY(pct('neutral')), width: 12, color: colors['neutral']),
        BarChartRodData(toY: safeY(pct('sad')), width: 12, color: colors['sad']),
        BarChartRodData(toY: safeY(pct('angry')), width: 12, color: colors['angry']),
      ]);
    }

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text("(%)",
              style: TextStyle(
                  color: Color(0xFF5E4631),
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ),
        SizedBox(
          height: 220,
          child: BarChart(BarChartData(
            maxY: 100,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(show: true, horizontalInterval: 25),
            borderData: FlBorderData(show: false),
            barGroups: [g('audio', 0), g('text', 1)],
            titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) => Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(v == 0 ? "Audio" : "Text",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF5E4631))))))),
          )),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          children: [
            _legendDot("Happy", colors['happy']!),
            _legendDot("Neutral", colors['neutral']!),
            _legendDot("Sad", colors['sad']!),
            _legendDot("Angry", colors['angry']!),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: Color(0xFF5E4631), fontSize: 12))
    ],
  );

// ---------- 改进版：更美观的折线图 ----------
  Widget _trend() {
    final spots = <FlSpot>[];
    for (int i = 0; i < dailyAvg.length; i++) {
      final v = dailyAvg[i];
      if (v != null) spots.add(FlSpot(i + 1, v));
    }

    if (spots.isEmpty) return const Text("No data this month");

    final sparse = spots.length < 2;

    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 3,
          gridData: FlGridData(show: true, horizontalInterval: 0.5),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(0),
                  style: const TextStyle(color: Color(0xFF5E4631), fontSize: 11),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: (dailyAvg.length / 6).clamp(1, 5).toDouble(),
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(color: Color(0xFF5E4631), fontSize: 10),
                ),
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              isCurved: true,
              spots: spots,
              barWidth: 3,
              color: const Color(0xFF8B6B4A),
              isStrokeCapRound: true,
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF8B6B4A).withOpacity(0.4),
                    const Color(0xFF8B6B4A).withOpacity(0.05),
                  ],
                ),
              ),
              dotData: FlDotData(show: true),
              dashArray: sparse ? [8, 6] : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pie() {
    final total = emotionTotal.values.fold(0, (a, b) => a + b);
    if (total == 0) return const Text("No data this month");
    final colors = {
      "happy": Colors.amber,
      "sad": Colors.blue,
      "angry": Colors.red,
      "neutral": Colors.grey
    };
    return SizedBox(
        height: 230,
        child: PieChart(PieChartData(
            sections: emotionTotal.entries
                .map((e) => PieChartSectionData(
                color: colors[e.key],
                value: e.value.toDouble(),
                title:
                "${e.key[0].toUpperCase()}${e.key.substring(1)}\n${(e.value * 100 / total).toStringAsFixed(1)}%",
                titleStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)))
                .toList())));
  }

  Widget _improve() {
    final total = improvedUsers + sameUsers + worsenedUsers;
    String pct(int n) =>
        total == 0 ? "0%" : "${(n * 100 / total).toStringAsFixed(0)}%";
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pill("Improved", pct(improvedUsers), improvedUsers, Colors.green[200]!),
          _pill("Unchanged", pct(sameUsers), sameUsers, Colors.grey[300]!),
          _pill("Worsened", pct(worsenedUsers), worsenedUsers, Colors.red[200]!),
          const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                  "Definition: Compare each user's first vs last message within the month.",
                  style: TextStyle(fontSize: 12, color: Color(0xFF5E4631))))
        ]);
  }

  Widget _pill(String t, String pct, int n, Color bg) => Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2))
          ]),
      child: Text(
        "$t • $pct ($n)",
        style: const TextStyle(color: Colors.black, fontSize: 14),
      ));
}

class _EdgeMsg {
  final int createdAt;
  final int score;
  _EdgeMsg({required this.createdAt, required this.score});
}

