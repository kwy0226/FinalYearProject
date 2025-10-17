import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'background_widget.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  static const int maxAttempts = 3;
  static const Duration lockDuration = Duration(minutes: 30);

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ---- Lock helpers ----
  Future<Map<String, dynamic>> _getLockInfo(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('lock_$email');
    if (raw == null) return {};
    return jsonDecode(raw);
  }

  Future<void> _setLockInfo(String email, Map<String, dynamic> info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lock_$email', jsonEncode(info));
  }

  Future<void> _clearLockInfo(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lock_$email');
  }

  // ---- Login flow ----
  Future<void> _handleLogin() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    setState(() {
      _loading = true;
      _error = null;
    });

    // lock check
    final lockInfo = await _getLockInfo(email);
    if (lockInfo.isNotEmpty && lockInfo['until'] != null) {
      final unlockTime = DateTime.parse(lockInfo['until']);
      if (DateTime.now().isBefore(unlockTime)) {
        setState(() {
          _error = "You’ve tried too many times. Please try again later.";
          _loading = false;
        });
        return;
      } else {
        await _clearLockInfo(email);
      }
    }

    try {
      // 直接尝试登录（用异常判断 email 是否存在/密码是否正确）
      final userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = userCred.user?.uid;
      if (uid == null) {
        setState(() {
          _error = "Authentication failed. Please try again.";
          _loading = false;
        });
        return;
      }

      // 登录成功：清掉失败记录
      await _clearLockInfo(email);

      // ✅ 检查是否被禁用
      final disabledSnap = await FirebaseDatabase.instance
          .ref('users/$uid/status/disabled')
          .get();
      final isDisabled = disabledSnap.value == true;
      if (isDisabled) {
        await FirebaseAuth.instance.signOut();
        setState(() {
          _error = "This account has been disabled by the administrator.";
        });
        _loading = false;
        return;
      }

      // 读取角色（吞掉数据库的 permission-denied，不再抛到外层）
      final db = FirebaseDatabase.instance.ref();
      bool isAdmin = false;
      bool isUser = false;

      try {
        final adminSnap = await db.child('admin/$uid').get();
        isAdmin = adminSnap.exists && (adminSnap.value == true || adminSnap.value == 'true');
      } catch (_) {
        // ignore permission-denied or other db errors
        isAdmin = false;
      }

      try {
        final userSnap = await db.child('users/$uid').get();
        isUser = userSnap.exists;
      } catch (_) {
        isUser = false;
      }

      if (!mounted) return;

      if (isAdmin) {
        Navigator.pushReplacementNamed(context, "/adminhome");
      } else if (isUser) {
        Navigator.pushReplacementNamed(context, "/home");
      } else {
        // 没有角色节点
        setState(() {
          _error = "No role assigned for this account.";
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Login successful")),
      );

    } on FirebaseAuthException catch (e) {
      // 邮箱不存在
      if (e.code == 'user-not-found') {
        setState(() {
          _error = "Invalid Email. Please try again.";
        });
      }
      // 密码错误（或凭证失效统一当作密码错）
      else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        final info = await _getLockInfo(email);
        int fails = (info['fails'] ?? 0) + 1;

        if (fails >= maxAttempts) {
          final until = DateTime.now().add(lockDuration);
          await _setLockInfo(email, {'fails': fails, 'until': until.toIso8601String()});
          setState(() {
            _error = "You’ve tried too many times. Please try again later.";
          });
        } else {
          await _setLockInfo(email, {'fails': fails});
          final remain = maxAttempts - fails;
          setState(() {
            _error = "Invalid Password. You still have $remain chance${remain > 1 ? 's' : ''}.";
          });
        }
      }
      // 其他常见错误
      else if (e.code == 'too-many-requests') {
        setState(() {
          _error = "You’ve tried too many times. Please try again later.";
        });
      } else if (e.code == 'network-request-failed') {
        setState(() {
          _error = "Network error. Please check your connection.";
        });
      } else if (e.code == 'user-disabled') {
        setState(() {
          _error = "This account has been disabled.";
        });
      } else {
        setState(() {
          _error = "Login failed. Please try again.";
        });
      }
    } catch (_) {
      // 兜底（不再把数据库的异常落到这里）
      setState(() {
        _error = "Login failed. Please try again.";
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
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
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          "Emotion Mate",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF5E4631),
                          ),
                        ),
                        const SizedBox(height: 18),

                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Email",
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final value = v?.trim() ?? "";
                            if (value.isEmpty) return "Please enter your email";
                            final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                            if (!re.hasMatch(value)) return "Invalid email";
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleLogin(),
                          decoration: InputDecoration(
                            labelText: "Password",
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: _obscure ? "Show password" : "Hide password",
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                            ),
                          ),
                          validator: (v) {
                            if ((v ?? "").isEmpty) return "Please enter your password";
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        if (_error != null) ...[
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 8),
                        ],

                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFB08968),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _loading ? null : _handleLogin,
                            child: _loading
                                ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : const Text("Login"),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Center(
                          child: RichText(
                            text: TextSpan(
                              text: "If don't have an account, ",
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: const Color(0xFF5E4631)),
                              children: [
                                TextSpan(
                                  text: "Sign Up Now!",
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                    decoration: TextDecoration.underline,
                                    color: const Color(0xFF8B6B4A),
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      Navigator.pushNamed(context, "/register");
                                    },
                                ),
                              ],
                            ),
                          ),
                        ),

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.pushNamed(context, "/forgotpw");
                            },
                            child: const Text("Forgot Password?"),
                          ),
                        ),

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.pushNamed(context, "/feedback");
                            },
                            child: const Text("Give a Feedback"),
                          ),
                        ),
                      ],
                    ),
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
