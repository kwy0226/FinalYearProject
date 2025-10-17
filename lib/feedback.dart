import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'background_widget.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  // ---- 提交反馈 ----
  Future<void> _submitFeedback() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _error = "Please log in to submit feedback.");
      return;
    }

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final message = _messageCtrl.text.trim();

    if (name.isEmpty || email.isEmpty || message.isEmpty) {
      setState(() => _error = "Please fill in all fields.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ref = _db.ref("feedback").push();
      await ref.set({
        "uid": user.uid,
        "name": name,
        "email": email,
        "message": message,
        "createdAt": DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Feedback submitted successfully.")),
      );

      Navigator.pop(context); // 返回 Settings 页面
    } catch (e) {
      setState(() => _error = "Failed to submit feedback: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Feedback"),
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
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 8,
                color: const Color(0xFFFFF7E9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ListView(
                    children: [
                      Text(
                        "We value your feedback!",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF5E4631),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Name
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: "Name",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Email
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Message
                      TextField(
                        controller: _messageCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: "Question / Suggestion",
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                          prefixIcon: Icon(Icons.feedback_outlined),
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (_error != null)
                        Text(_error!,
                            style: const TextStyle(color: Colors.red)),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submitFeedback,
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
                              : const Text("Submit"),
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
