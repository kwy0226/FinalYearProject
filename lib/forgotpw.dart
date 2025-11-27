import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'background_widget.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

// Controller for email input
class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  bool _loading = false; // Prevent double-click while sending reset email
  String? _error; // Display error message to user

  @override
  void dispose() {
    _emailCtrl.dispose(); // Prevent memory leak
    super.dispose();
  }

  // SEND PASSWORD RESET LINK THROUGH FIREBASE
  Future<void> _sendResetLink() async {
    final email = _emailCtrl.text.trim();

    // Basic validation before sending request
    if (email.isEmpty) {
      setState(() => _error = "Please enter your email.");
      return;
    }

    setState(() {
      _loading = true; // Show loading spinner
      _error = null; // Clear previous error
    });

    try {
      // Firebase Auth built-in API to send reset link
      // Firebase will send an email to the user immediately
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      // Show success message to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Password reset link sent to $email")),
      );
      Navigator.pop(context); // Back to Login Page
    } on FirebaseAuthException catch (e) {
      // Firebase returns detailed error message
      setState(() => _error = e.message ?? "Password reset failed.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // BUILD UI
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
