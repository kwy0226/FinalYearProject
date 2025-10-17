import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'background_widget.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  // ---- Firebase 官方发送 Reset Link ----
  Future<void> _sendResetLink() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty) {
      setState(() => _error = "Please enter your email.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Password reset link sent to $email")),
      );
      Navigator.pop(context); // 返回登录页
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? "Password reset failed.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF5E4631)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          const AppBackground(),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 8,
                color: const Color(0xFFFFF7E9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title
                      Text(
                        "Forgot Password",
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF5E4631),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Email input
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Error message
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Send Reset Link Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _sendResetLink,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB08968),
                            foregroundColor: Colors.white,
                          ),
                          child: _loading
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Text("Send Reset Link"),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Info text
                      const Text(
                        "Enter your registered email. "
                            "You will receive a reset link in your inbox.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF5E4631),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
