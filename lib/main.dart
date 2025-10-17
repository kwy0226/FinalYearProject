import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fyp_project/aboutus.dart';
import 'firebase_options.dart';
import 'login.dart';
import 'register.dart';
import 'homepage.dart';
import 'chatbox.dart';
import 'chat.dart';
import 'forgotpw.dart';
import 'settings.dart';
import 'edit_profile.dart';
import 'feedback.dart';
import 'aboutus.dart';
import 'chart.dart';
import 'adminhome.dart';

// 覆盖 HttpClient，忽略证书错误（仅测试用）
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 设置 HttpOverrides
  HttpOverrides.global = MyHttpOverrides();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Emotion Mate',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB08968)),
        useMaterial3: true,
      ),
      home: const LoginPage(),
      routes: {
        '/login': (_) => const LoginPage(),
        '/register': (_) => const RegisterPage(),
        '/forgotpw': (_) => const ForgotPasswordPage(),
        '/home': (_) => const HomePage(),
        '/chats': (_) => const ChatsPage(),
        '/chatbox': (context) => ChatBoxPage(chatId: "default_chat"),
        '/settings': (_) => const SettingsPage(),
        '/editProfile': (_) => const EditProfilePage(),
        '/feedback': (_) => const FeedbackPage(),
        '/aboutus': (_) => const AboutUsPage(),
        '/chart': (_) => ChartPage(),
        '/adminhome': (_) => AdminHomePage(),
      },
    );
  }
}
