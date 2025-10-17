import 'package:flutter/material.dart';

/// Reusable app background with a soft beige gradient and decorative bubbles.
/// Use as the bottom layer of a Stack.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFAF3E0), // light beige
            Color(0xFFF5E6C8), // warm beige
          ],
        ),
      ),
      child: CustomPaint(
        painter: _BubblesPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BubblesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;

    // Soft circles for a cozy atmosphere
    paint.color = const Color(0x26A67C52); // subtle brown (15% opacity)
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.2), 90, paint);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), 60, paint);

    paint.color = const Color(0x1FA67C52); // even lighter
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.75), 120, paint);
    canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.8), 70, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
