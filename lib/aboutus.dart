import 'package:flutter/material.dart';
import 'background_widget.dart';

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("About Us"),
        backgroundColor: const Color(0xFFB08968),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context), // 返回 Setting 页面
        ),
      ),
      body: Stack(
        children: [
          const AppBackground(), // ✅ 复用背景
          Center(
            child: Card(
              color: const Color(0xFFFFF7E9),
              elevation: 6,
              margin: const EdgeInsets.all(24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Emotion Mate",
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF5E4631),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Version: Test Generation 1.0",
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF5E4631),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Developer: Yeoh Wen Kai",
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF5E4631),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    Text(
                      "This application is designed to detect user emotions "
                          "and respond empathetically. It is still in testing "
                          "phase and may be improved in future versions.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5E4631),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
