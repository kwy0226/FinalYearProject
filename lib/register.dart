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
  // Global form key for validation
  final _formKey = GlobalKey<FormState>();

  // Text controllers
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  // Validation flags
  bool _emailValid = false;
  bool _pwdValid = false;
  bool _confirmValid = false;

  // Password visibility toggles
  bool _passwordObscure = true;
  bool _confirmObscure = true;

  // Dirty flags
  bool _emailDirty = false;
  bool _pwdDirty = false;
  bool _confirmDirty = false;

  // Email existence check
  bool _checkingEmail = false;
  bool _emailExists = false;
  Timer? _emailDebounce;

  // Other UI flags
  bool _agree = false;
  bool _loading = false;
  String? _error;

  int? _month;
  int? _day;
  int? _year;

  @override
  void dispose() {
    _emailDebounce?.cancel();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // Email regex
  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  // Password rule: 8–14 characters + must contain letters
  bool _validatePasswordRules(String v) {
    if (v.length < 8 || v.length > 14) return false;
    if (!RegExp(r'[A-Za-z]').hasMatch(v)) return false;
    return true;
  }

  // Days in month helper
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
    return List<int>.generate(_daysInMonth(y, m), (i) => i + 1);
  }

  /// Check if email already exists (REST fallback)
  Future<bool> _emailAlreadyRegistered(String email) async {
    try {
      final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
      final url =
          'https://identitytoolkit.googleapis.com/v1/accounts:createAuthUri?key=$apiKey';

      final resp = await Dio().post(url, data: {
        'identifier': email,
        'continueUri': 'https://example.com',
      });

      return resp.data is Map && resp.data['registered'] == true;
    } catch (_) {
      return false; // fallback — allow validation on submit
    }
  }

  // Terms & Policy dialog
  Future<void> _openTermsDialog() async {
    final controller = ScrollController();
    bool reachedBottom = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            if (!controller.hasListeners) {
              controller.addListener(() {
                final isAtBottom = controller.offset >=
                    controller.position.maxScrollExtent - 10;

                if (isAtBottom != reachedBottom) {
                  reachedBottom = isAtBottom;
                  setD(() {}); // update Agree button state
                }
              });
            }

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
                    child: const Text(
                      "This application collects certain user information for the purpose of system functionality, "
                          "research, and continuous improvement of the AI assistant. By creating an account and using "
                          "this application, you acknowledge and agree to the following terms:\n\n"

                          "1. Data Collected\n"
                          "- Basic profile information such as username, email address, and date of birth.\n"
                          "- User interaction data including chat messages, emotional feedback results, and AI response logs.\n"
                          "- Technical information, such as device type, usage time, and app performance statistics.\n\n"

                          "2. Purpose of Data Usage\n"
                          "- To enable key features of the system, including personalized responses, emotional analysis, and user history tracking.\n"
                          "- To support academic research related to emotion recognition, human–AI interaction, and system performance analysis.\n"
                          "- To improve model accuracy, user experience, and overall system quality.\n\n"

                          "3. Data Protection & Privacy\n"
                          "- All collected data is stored securely using encrypted and authenticated cloud services.\n"
                          "- Your personal data will not be sold, shared, or disclosed to unauthorized third parties.\n"
                          "- Data access is restricted to project developers and academic supervisors for research purposes only.\n"
                          "- Your data will never be used for illegal activities, harmful profiling, or targeted advertising.\n\n"

                          "4. Research & Analytics\n"
                          "- Aggregated and anonymized data may be analyzed to identify patterns such as emotion trends, "
                          "user behavior groups, and system performance metrics.\n"
                          "- No individual user identity will be revealed in any research output or academic reporting.\n"
                          "- The system may process historical chat logs to compute monthly emotion summaries, usage statistics, "
                          "or performance evaluations.\n\n"

                          "5. User Rights\n"
                          "- You may request deletion of your account and data at any time by contacting the system administrator.\n"
                          "- You may update your profile information within the app settings.\n"
                          "- If you choose not to agree with these terms, you may decline and exit registration.\n\n"

                          "6. Agreement\n"
                          "By scrolling to the bottom and pressing the 'Agree' button, you confirm that you have read, "
                          "understood, and accepted all the terms stated in this policy. If you disagree with any part of "
                          "this policy, please select 'Decline'.\n\n"

                          "Thank you for supporting this academic project. Your privacy and security are always our priority.",
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Decline"),
                ),
                FilledButton(
                  onPressed: reachedBottom
                      ? () {
                    setState(() => _agree = true);
                    Navigator.pop(ctx);
                  }
                      : null,
                  child: const Text("Agree"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Register user + write to Firebase
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
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      await cred.user?.updateDisplayName(_usernameCtrl.text.trim());

      final uid = cred.user!.uid;
      await FirebaseDatabase.instance.ref("users/$uid").set({
        "username": _usernameCtrl.text.trim(),
        "email": _emailCtrl.text.trim(),
        "birthday": {
          "year": _year,
          "month": _month,
          "day": _day,
        },
        "createdAt": DateTime.now().toIso8601String(),
        "status": {"disabled": false},
      });

      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Registration successful. Please log in.")),
      );

      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = switch (e.code) {
          "email-already-in-use" => "Email is already in use.",
          "invalid-email" => "Invalid email.",
          "weak-password" => "Password is too weak.",
          _ => e.message ?? "Registration failed."
        };
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Email suffix: loading / ✓ / X
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


  // UI
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
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),

                          const SizedBox(height: 10),

                          Text(
                            "Create Account",
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF5E4631),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // USERNAME
                          TextFormField(
                            controller: _usernameCtrl,
                            decoration: const InputDecoration(
                              labelText: "Username",
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if ((v ?? "").trim().isEmpty) {
                                return "Please enter a username";
                              }
                              if ((v ?? "").trim().length < 2) {
                                return "At least 2 characters";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // EMAIL
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: "Email",
                              prefixIcon: const Icon(Icons.email_outlined),
                              border: const OutlineInputBorder(),
                              suffixIcon: _buildEmailSuffix(),
                            ),
                            onChanged: (v) {
                              final value = v.trim();
                              setState(() {
                                _emailDirty = true;
                                _emailValid = _emailRe.hasMatch(value);
                                _emailExists = false;
                              });

                              _emailDebounce?.cancel();
                              _emailDebounce =
                                  Timer(const Duration(milliseconds: 500),
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
                                      });
                            },
                            validator: (v) {
                              final value = v?.trim() ?? "";
                              if (value.isEmpty) return "Enter email";
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

                          // BIRTHDAY ROW
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  isDense: true,
                                  value: _year,
                                  decoration: const InputDecoration(
                                    labelText: "Year",
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _years
                                      .map((y) => DropdownMenuItem(
                                    value: y,
                                    child: Text("$y"),
                                  ))
                                      .toList(),
                                  onChanged: (v) {
                                    setState(() {
                                      _year = v;
                                      if (_day != null &&
                                          _month != null &&
                                          _year != null) {
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
                                  decoration: const InputDecoration(
                                    labelText: "Month",
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _months
                                      .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Text("$m"),
                                  ))
                                      .toList(),
                                  onChanged: (v) {
                                    setState(() {
                                      _month = v;
                                      if (_day != null &&
                                          _month != null &&
                                          _year != null) {
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
                                  decoration: const InputDecoration(
                                    labelText: "Day",
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _daysFor(_year, _month)
                                      .map((d) => DropdownMenuItem(
                                    value: d,
                                    child: Text("$d"),
                                  ))
                                      .toList(),
                                  onChanged: (v) => setState(() => _day = v),
                                  validator: (v) =>
                                  v == null ? "Select day" : null,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // PASSWORD
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _passwordObscure,
                            onChanged: (v) {
                              setState(() {
                                _pwdDirty = true;
                                _pwdValid = _validatePasswordRules(v);
                                _confirmValid = v == _confirmCtrl.text;
                              });
                            },
                            decoration: InputDecoration(
                              labelText: "Password (8–14, must contain letters)",
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
                                    onPressed: () {
                                      setState(() {
                                        _passwordObscure = !_passwordObscure;
                                      });
                                    },
                                    icon: Icon(_passwordObscure
                                        ? Icons.visibility
                                        : Icons.visibility_off),
                                  ),
                                ],
                              ),
                            ),
                            validator: (v) {
                              if ((v ?? "").isEmpty) {
                                return "Please enter your password";
                              }
                              if (!_validatePasswordRules(v!)) {
                                return "8–14 chars, must contain letters";
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 12),

                          // CONFIRM PASSWORD
                          TextFormField(
                            controller: _confirmCtrl,
                            obscureText: _confirmObscure,
                            onChanged: (v) {
                              setState(() {
                                _confirmDirty = true;
                                _confirmValid = v == _passwordCtrl.text;
                              });
                            },
                            decoration: InputDecoration(
                              labelText: "Confirm Password",
                              prefixIcon: const Icon(Icons.lock_reset),
                              border: const OutlineInputBorder(),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_confirmDirty)
                                    Icon(
                                      _confirmValid
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      color: _confirmValid
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _confirmObscure = !_confirmObscure;
                                      });
                                    },
                                    icon: Icon(_confirmObscure
                                        ? Icons.visibility
                                        : Icons.visibility_off),
                                  ),
                                ],
                              ),
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

                          // TERMS CHECKBOX
                          InkWell(
                            onTap: _openTermsDialog,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
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

                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),

                          const SizedBox(height: 10),
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFB08968),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _loading ? null : _handleRegister,
                              child: _loading
                                  ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                                  : const Text("Register"),
                            ),
                          ),
                        ],
                      ),
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
