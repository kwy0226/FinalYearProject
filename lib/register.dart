import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:dio/dio.dart';
import 'firebase_options.dart';
import 'background_widget.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  // live validation flags
  bool _emailValid = false;
  bool _pwdValid = false;
  bool _confirmValid = false;

  // show check/cross only after typing
  bool _emailDirty = false;
  bool _pwdDirty = false;
  bool _confirmDirty = false;

  // email existence check
  bool _checkingEmail = false;
  bool _emailExists = false;
  Timer? _emailDebounce;

  bool _agree = false;
  bool _loading = false;
  String? _error;

  int? _month; // 1..12
  int? _day;   // 1..(28..31)
  int? _year;  // 1950..2025

  @override
  void dispose() {
    _emailDebounce?.cancel();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ---------- helpers ----------
  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool _validatePasswordRules(String v) {
    if (v.length < 8 || v.length > 14) return false;
    if (!RegExp(r'[A-Za-z]').hasMatch(v)) return false; // must contain letters
    return true;
  }

  int _daysInMonth(int year, int month) {
    if (month == 2) {
      final leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
      return leap ? 29 : 28;
    }
    const months31 = {1, 3, 5, 7, 8, 10, 12};
    return months31.contains(month) ? 31 : 30;
  }

  List<int> get _years => List<int>.generate(2025 - 1950 + 1, (i) => 1950 + i);
  List<int> get _months => List<int>.generate(12, (i) => i + 1);
  List<int> _daysFor(int? y, int? m) {
    if (y == null || m == null) return const [];
    final n = _daysInMonth(y, m);
    return List<int>.generate(n, (i) => i + 1);
  }

  /// REST fallback: check if an email is already registered using Google Identity Toolkit.
  Future<bool> _emailAlreadyRegistered(String email) async {
    try {
      final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
      final url =
          'https://identitytoolkit.googleapis.com/v1/accounts:createAuthUri?key=$apiKey';

      final resp = await Dio().post(url, data: {
        'identifier': email,
        'continueUri': 'https://example.com',
      });

      final registered = resp.data is Map && resp.data['registered'] == true;
      return registered; // true = already in use
    } catch (e) {
      debugPrint('Email check (REST) error: $e');
      // On error, treat as not registered and rely on server-side validation during submit.
      return false;
    }
  }

  Future<void> _openTermsDialog() async {
    final controller = ScrollController();
    bool reachedBottom = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDState) {
          controller.addListener(() {
            final atBottom =
                controller.offset >= controller.position.maxScrollExtent - 8.0;
            if (atBottom != reachedBottom) {
              reachedBottom = atBottom;
              setDState(() {});
            }
          });

          return AlertDialog(
            backgroundColor: const Color(0xFFFFF7E9),
            title: const Text("Terms & Data Policy"),
            content: SizedBox(
              width: 460,
              height: 260,
              child: Scrollbar(
                thumbVisibility: true,
                controller: controller,
                child: SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.only(right: 8),
                  child: const Text(
                    "This app will collect user profile data and chat messages "
                        "for research purposes. We commit not to use this data for "
                        "any illegal activities. By continuing, you acknowledge "
                        "and accept that your data may be analyzed to improve the "
                        "service quality and research outcomes. Your data will be "
                        "handled with care and protected with appropriate security "
                        "measures.\n\n"
                        "Please read the entire statement. The Agree button will "
                        "only be enabled once you reach the bottom of this dialog.",
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text("Decline"),
              ),
              FilledButton(
                onPressed: reachedBottom
                    ? () {
                  setState(() => _agree = true);
                  Navigator.of(ctx).pop();
                }
                    : null,
                child: const Text("Agree"),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _handleRegister() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    if (!_agree) {
      setState(() => _error = "Please read and agree to the terms.");
      return;
    }
    if (_year == null || _month == null || _day == null) {
      setState(() => _error = "Please select your birthday.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1) Create auth user (server-side will still reject if email was taken).
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      // 2) Update displayName
      await cred.user?.updateDisplayName(_usernameCtrl.text.trim());

// 3) Write profile to RTDB (add status.disabled = false)
      final uid = cred.user!.uid;
      final ref = FirebaseDatabase.instance.ref("users/$uid");
      await ref.set({
        "username": _usernameCtrl.text.trim(),
        "email": _emailCtrl.text.trim(), // 建议也一起存，方便 admin 页面统一显示
        "birthday": {"year": _year, "month": _month, "day": _day},
        "createdAt": DateTime.now().toUtc().toIso8601String(),
        "status": {
          "disabled": false, // ✅ 新增这一行
        },
      });

      // 4) Sign out -> back to login
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Registration successful. Please log in.")),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case "email-already-in-use":
          msg = "Email is already in use.";
          break;
        case "invalid-email":
          msg = "Invalid email address.";
          break;
        case "weak-password":
          msg = "Password is too weak.";
          break;
        default:
          msg = e.message ?? "Registration failed.";
      }
      setState(() => _error = msg);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget? _buildEmailSuffix() {
    if (!_emailDirty) return null;
    if (_checkingEmail) {
      return const Padding(
        padding: EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final ok = _emailValid && !_emailExists;
    return Icon(ok ? Icons.check_circle : Icons.cancel,
        color: ok ? Colors.green : Colors.red);
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
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 8,
                color: const Color(0xFFFFF7E9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        const SizedBox(height: 4),

                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                "Create Account",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF5E4631),
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Username
                              TextFormField(
                                controller: _usernameCtrl,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: "Username",
                                  prefixIcon: Icon(Icons.person_outline),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) {
                                  final value = v?.trim() ?? "";
                                  if (value.isEmpty) {
                                    return "Please enter a username";
                                  }
                                  if (value.length < 2) {
                                    return "At least 2 characters";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),

                              // Email: format + uniqueness (async with debounce)
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                onChanged: (v) {
                                  final value = v.trim();
                                  setState(() {
                                    _emailDirty = true;
                                    _emailValid = _emailRe.hasMatch(value);
                                    _emailExists = false;
                                  });

                                  _emailDebounce?.cancel();
                                  _emailDebounce = Timer(
                                    const Duration(milliseconds: 500),
                                        () async {
                                      if (!_emailValid) return;
                                      setState(() => _checkingEmail = true);
                                      final exists =
                                      await _emailAlreadyRegistered(value);
                                      if (!mounted) return;
                                      setState(() {
                                        _emailExists = exists;
                                        _checkingEmail = false;
                                      });
                                    },
                                  );
                                },
                                decoration: InputDecoration(
                                  labelText: "Email",
                                  prefixIcon:
                                  const Icon(Icons.email_outlined),
                                  border: const OutlineInputBorder(),
                                  suffixIcon: _buildEmailSuffix(),
                                ),
                                validator: (v) {
                                  final value = v?.trim() ?? "";
                                  if (value.isEmpty) {
                                    return "Please enter your email";
                                  }
                                  if (!_emailRe.hasMatch(value)) {
                                    return "Invalid email";
                                  }
                                  if (_emailExists) {
                                    return "Email already in use";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),

                              // Birthday: Year / Month / Day
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      isDense: true,
                                      value: _year,
                                      items: _years
                                          .map((y) => DropdownMenuItem(
                                        value: y,
                                        child: Text(y.toString()),
                                      ))
                                          .toList(),
                                      decoration: const InputDecoration(
                                        labelText: "Year",
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding:
                                        EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                      ),
                                      onChanged: (v) {
                                        setState(() {
                                          _year = v;
                                          if (_day != null &&
                                              _year != null &&
                                              _month != null) {
                                            final max = _daysInMonth(
                                                _year!, _month!);
                                            if (_day! > max) _day = null;
                                          }
                                        });
                                      },
                                      validator: (v) =>
                                      v == null ? "Select year" : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      isDense: true,
                                      value: _month,
                                      items: _months
                                          .map((m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(m.toString()),
                                      ))
                                          .toList(),
                                      decoration: const InputDecoration(
                                        labelText: "Month",
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding:
                                        EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                      ),
                                      onChanged: (v) {
                                        setState(() {
                                          _month = v;
                                          if (_day != null &&
                                              _year != null &&
                                              _month != null) {
                                            final max = _daysInMonth(
                                                _year!, _month!);
                                            if (_day! > max) _day = null;
                                          }
                                        });
                                      },
                                      validator: (v) =>
                                      v == null ? "Select month" : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      isDense: true,
                                      value: _day,
                                      items: _daysFor(_year, _month)
                                          .map((d) => DropdownMenuItem(
                                        value: d,
                                        child: Text(d.toString()),
                                      ))
                                          .toList(),
                                      decoration: const InputDecoration(
                                        labelText: "Day",
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding:
                                        EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                      ),
                                      onChanged: (v) =>
                                          setState(() => _day = v),
                                      validator: (v) =>
                                      v == null ? "Select day" : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Password (+ eye) with live check
                              StatefulBuilder(
                                builder: (ctx, setLocal) {
                                  bool obscure = true;
                                  return TextFormField(
                                    controller: _passwordCtrl,
                                    obscureText: obscure,
                                    onChanged: (v) => setState(() {
                                      _pwdDirty = true;
                                      _pwdValid = _validatePasswordRules(v);
                                      _confirmValid =
                                          _confirmCtrl.text == v;
                                    }),
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      labelText:
                                      "Password (8–14, must contain letters)",
                                      prefixIcon: const Icon(Icons.lock_outline),
                                      border: const OutlineInputBorder(),
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_pwdDirty)
                                            Icon(
                                              _pwdValid
                                                  ? Icons.check_circle
                                                  : Icons.cancel,
                                              color: _pwdValid
                                                  ? Colors.green
                                                  : Colors.red,
                                            ),
                                          IconButton(
                                            tooltip: "Toggle visibility",
                                            onPressed: () {
                                              obscure = !obscure;
                                              setLocal(() {});
                                            },
                                            icon: Icon(
                                              obscure
                                                  ? Icons.visibility
                                                  : Icons.visibility_off,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    validator: (v) {
                                      final value = v ?? "";
                                      if (value.isEmpty) {
                                        return "Please enter your password";
                                      }
                                      if (!_validatePasswordRules(value)) {
                                        return "8–14 characters and must contain letters";
                                      }
                                      return null;
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 12),

                              // Confirm password
                              TextFormField(
                                controller: _confirmCtrl,
                                obscureText: true,
                                onChanged: (v) => setState(() {
                                  _confirmDirty = true;
                                  _confirmValid =
                                      v == _passwordCtrl.text;
                                }),
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  labelText: "Confirm Password",
                                  prefixIcon:
                                  const Icon(Icons.lock_reset),
                                  border: const OutlineInputBorder(),
                                  suffixIcon: _confirmDirty
                                      ? Icon(
                                    _confirmValid
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    color: _confirmValid
                                        ? Colors.green
                                        : Colors.red,
                                  )
                                      : null,
                                ),
                                validator: (v) {
                                  if ((v ?? "").isEmpty) {
                                    return "Please confirm your password";
                                  }
                                  if (v != _passwordCtrl.text) {
                                    return "Passwords do not match";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),

                              // Terms
                              InkWell(
                                onTap: _openTermsDialog,
                                child: Row(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Checkbox(
                                      value: _agree,
                                      onChanged: (_) => _openTermsDialog(),
                                    ),
                                    const Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(top: 12),
                                        child: Text(
                                          "I have read and agree to the Terms & Data Policy.",
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              if (_error != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _error!,
                                  style:
                                  const TextStyle(color: Colors.red),
                                ),
                              ],

                              const SizedBox(height: 10),
                              SizedBox(
                                height: 48,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                    const Color(0xFFB08968),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed:
                                  _loading ? null : _handleRegister,
                                  child: _loading
                                      ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child:
                                    CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                      : const Text("Register"),
                                ),
                              ),
                            ],
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
