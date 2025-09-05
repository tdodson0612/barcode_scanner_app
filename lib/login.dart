import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'services/auth_service.dart'; // Updated import

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final logger = Logger();

  late final StreamSubscription _authSub;

  String _email = '';
  String _password = '';
  String _confirmPassword = '';
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  Future<void> _submitForm() async {
  if (_formKey.currentState!.validate()) {
    _formKey.currentState!.save();

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        final response = await AuthService.signIn(
          email: _email,
          password: _password,
        );

        if (response.user != null) {
          logger.i('Login successful: ${response.user?.email}');
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        if (_password != _confirmPassword) {
          throw Exception('Passwords do not match!');
        }

        final response = await AuthService.signUp(
          email: _email,
          password: _password,
        );

        if (response.user != null) {
          logger.i('Sign up successful: ${response.user?.email}');

          // Add delay to ensure auth context is ready
          await Future.delayed(const Duration(milliseconds: 1000));

          try {
            await Supabase.instance.client.from('user_profiles').insert({
              'id': response.user!.id,
              'email': response.user!.email,
              'daily_scans_used': 0,
              'last_scan_date': DateTime.now().toIso8601String().split('T').first,
            });
            logger.i('User profile created for ${response.user?.email}');
          } catch (e) {
            logger.e('Error creating user profile: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error creating profile: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }

          if (response.session == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please check your email to confirm your account!'),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            Navigator.pushReplacementNamed(context, '/home');
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }
}

  Future<void> _sendPasswordResetEmail() async {
    if (_email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await AuthService.resetPassword(_email);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent! Check your inbox.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _setupAuthListener() {
    _authSub = AuthService.authStateChanges.listen((data) {
      final event = data.event;
      final session = data.session;

      switch (event) {
        case AuthChangeEvent.signedIn:
          logger.i('User signed in: ${session?.user.email}');
          break;
        case AuthChangeEvent.signedOut:
          logger.w('User signed out');
          break;
        default:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Login' : 'Sign Up'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: "Email",
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (val) => val!.isEmpty ? "Enter an email" : null,
                  onSaved: (val) => _email = val!,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: "Password",
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: (val) => val!.isEmpty ? "Enter a password" : null,
                  onSaved: (val) => _password = val!,
                ),
                if (!_isLogin) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: "Confirm Password",
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    obscureText: true,
                    onSaved: (val) => _confirmPassword = val!,
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitForm,
                    child: _isLoading 
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text(_isLogin ? 'Login' : 'Sign Up'),
                  ),
                ),
                if (_isLogin)
                  TextButton(
                    onPressed: _sendPasswordResetEmail,
                    child: const Text("Forgot Password?"),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin
                        ? "Don't have an account? Sign up"
                        : "Already have an account? Login",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}