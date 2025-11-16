// lib/login.dart - Group B Changes: Remember Me + Autofill + FIXED: No Supabase Egress
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'services/auth_service.dart';
import 'services/error_handling_service.dart';
import 'config/app_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late final StreamSubscription _authSub;

  String _email = '';
  String _password = '';
  String _confirmPassword = '';
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
    _loadSavedCredentials();
    
    _emailController.text = _email;
    _passwordController.text = _password;
    _confirmPasswordController.text = _confirmPassword;
  }

  @override
  void dispose() {
    _authSub.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('remember_me') ?? true;
      final savedEmail = prefs.getString('saved_email') ?? '';
      
      setState(() {
        _rememberMe = rememberMe;
        if (rememberMe && savedEmail.isNotEmpty) {
          _email = savedEmail;
          _emailController.text = savedEmail;
        }
      });
    } catch (e) {
      AppConfig.debugPrint('Error loading saved credentials: $e');
    }
  }

  Future<void> _saveCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', _rememberMe);
      
      if (_rememberMe) {
        await prefs.setString('saved_email', _email.trim());
      } else {
        await prefs.remove('saved_email');
      }
    } catch (e) {
      AppConfig.debugPrint('Error saving credentials: $e');
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    _formKey.currentState!.save();

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await _handleLogin();
      } else {
        await _handleSignUp();
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        AppConfig.debugPrint('Auth error details: $errorMessage');
        
        if (errorMessage.contains('Invalid login credentials')) {
          errorMessage = 'Invalid email or password. Please check your credentials and try again.';
        } else if (errorMessage.contains('Email not confirmed')) {
          errorMessage = 'Please verify your email address before signing in. Check your inbox for the confirmation link.';
        }
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.authError,
          showSnackBar: true,
          customMessage: errorMessage,
          onRetry: _submitForm,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleLogin() async {
    try {
      final trimmedEmail = _email.trim();
      final trimmedPassword = _password;
      
      AppConfig.debugPrint('Attempting login for: $trimmedEmail');
      
      await _saveCredentials();
      
      final response = await AuthService.signIn(
        email: trimmedEmail,
        password: trimmedPassword,
      );

      if (response.user != null) {
        AppConfig.debugPrint('Login successful: ${response.user?.email}');
        
        if (mounted) {
          ErrorHandlingService.showSuccess(context, 'Welcome back!');
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        throw Exception('Login failed - no user returned');
      }
    } catch (e) {
      AppConfig.debugPrint('Login error: $e');
      rethrow;
    }
  }

  Future<void> _handleSignUp() async {
    if (_password != _confirmPassword) {
      throw Exception('Passwords do not match!');
    }

    if (_password.length < 6) {
      throw Exception('Password must be at least 6 characters long');
    }

    try {
      final trimmedEmail = _email.trim();
      
      final response = await AuthService.signUp(
        email: trimmedEmail,
        password: _password,
      );

      if (response.user != null) {
        AppConfig.debugPrint('Sign up successful: ${response.user?.email}');

        await Future.delayed(const Duration(milliseconds: 1000));
        
        // FIXED: Route user profile creation through Cloudflare Worker instead of direct Supabase
        await _createUserProfileViaWorker(response.user!);

        await _saveCredentials();

        if (mounted) {
          if (response.session == null) {
            ErrorHandlingService.showSuccess(
              context,
              'Account created! Please check your email to confirm your account.'
            );
          } else {
            ErrorHandlingService.showSuccess(context, 'Account created successfully!');
            Navigator.pushReplacementNamed(context, '/home');
          }
        }
      } else {
        throw Exception('Sign up failed - no user returned');
      }
    } catch (e) {
      AppConfig.debugPrint('Sign up error: $e');
      rethrow;
    }
  }

  // FIXED: Create user profile via Cloudflare Worker (no Supabase egress)
  Future<void> _createUserProfileViaWorker(User user) async {
    try {
      final response = await http.post(
        Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'insert',
          'table': 'user_profiles',
          'data': {
            'id': user.id,
            'email': user.email,
            'daily_scans_used': 0,
            'last_scan_date': DateTime.now().toIso8601String().split('T')[0],
            'username': user.email?.split('@')[0] ?? 'user',
            'created_at': DateTime.now().toIso8601String(),
            'friends_list_visible': true,
          },
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Worker profile creation failed: ${response.body}');
      }
      
      AppConfig.debugPrint('User profile created for ${user.email} via Worker');
    } catch (e) {
      AppConfig.debugPrint('Error creating user profile via Worker: $e');
      
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          showSnackBar: true,
          customMessage: 'Account created but profile setup failed. You can complete this in settings.',
        );
      }
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    String resetEmail = _emailController.text.trim();
    
    if (resetEmail.isEmpty) {
      resetEmail = await _showEmailInputDialog() ?? '';
    }
    
    if (resetEmail.isEmpty) {
      ErrorHandlingService.showSimpleError(context, 'Please enter your email address');
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(resetEmail)) {
      ErrorHandlingService.showSimpleError(context, 'Please enter a valid email address');
      return;
    }

    try {
      await AuthService.resetPassword(resetEmail);
      
      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          'Password reset email sent to $resetEmail. Check your inbox and spam folder.'
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.authError,
          customMessage: 'Failed to send password reset email',
          onRetry: _sendPasswordResetEmail,
        );
      }
    }
  }

  Future<String?> _showEmailInputDialog() async {
    final controller = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter your email address to receive a password reset link:'),
            SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('Send Reset Email'),
          ),
        ],
      ),
    );
  }

  void _setupAuthListener() {
    _authSub = AuthService.authStateChanges.listen((data) {
      final event = data.event;
      final session = data.session;

      switch (event) {
        case AuthChangeEvent.signedIn:
          AppConfig.debugPrint('User signed in: ${session?.user.email}');
          break;
        case AuthChangeEvent.signedOut:
          AppConfig.debugPrint('User signed out');
          break;
        case AuthChangeEvent.passwordRecovery:
          AppConfig.debugPrint('Password recovery initiated');
          break;
        default:
          break;
      }
    });
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _formKey.currentState?.reset();
      _emailController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _email = '';
      _password = '';
      _confirmPassword = '';
    });
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    
    if (!_isLogin) {
      if (value.length < 6) {
        return 'Password must be at least 6 characters';
      }
    }
    
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (!_isLogin) {
      if (value == null || value.isEmpty) {
        return 'Please confirm your password';
      }
      
      if (value != _passwordController.text) {
        return 'Passwords do not match';
      }
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Sign In' : 'Create Account'),
        centerTitle: true,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // App Logo/Icon
                          Icon(
                            Icons.restaurant_menu,
                            size: 64,
                            color: Colors.blue.shade600,
                          ),
                          SizedBox(height: 16),
                          
                          // Title
                          Text(
                            _isLogin ? 'Welcome Back!' : 'Create Your Account',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          
                          SizedBox(height: 8),
                          
                          Text(
                            _isLogin 
                                ? 'Sign in to access your recipes and scan history'
                                : 'Join Liver Food Scanner to unlock premium features',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          
                          SizedBox(height: 32),

                          // Email Field with Autofill
                          TextFormField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: "Email Address",
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: _validateEmail,
                            onSaved: (val) => _email = val?.trim() ?? '',
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: [AutofillHints.email],
                          ),
                          
                          SizedBox(height: 16),

                          // Password Field with Autofill
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: "Password",
                              prefixIcon: Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            obscureText: _obscurePassword,
                            textInputAction: _isLogin ? TextInputAction.done : TextInputAction.next,
                            validator: _validatePassword,
                            onSaved: (val) => _password = val ?? '',
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: _isLogin 
                                ? [AutofillHints.password]
                                : [AutofillHints.newPassword],
                          ),

                          // Confirm Password Field (Sign Up only)
                          if (!_isLogin) ...[
                            SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPasswordController,
                              decoration: InputDecoration(
                                labelText: "Confirm Password",
                                prefixIcon: Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              obscureText: _obscureConfirmPassword,
                              textInputAction: TextInputAction.done,
                              validator: _validateConfirmPassword,
                              onSaved: (val) => _confirmPassword = val ?? '',
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: [AutofillHints.newPassword],
                            ),
                          ],

                          // Remember Me Checkbox (Login only)
                          if (_isLogin) ...[
                            SizedBox(height: 16),
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  onChanged: (value) {
                                    setState(() {
                                      _rememberMe = value ?? true;
                                    });
                                  },
                                  activeColor: Colors.blue.shade600,
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _rememberMe = !_rememberMe;
                                      });
                                    },
                                    child: Text(
                                      'Remember me on this device',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          SizedBox(height: 24),

                          // Submit Button
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _submitForm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade600,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              child: _isLoading 
                                  ? Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Text(
                                          _isLogin ? 'Signing In...' : 'Creating Account...',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      _isLogin ? 'Sign In' : 'Create Account',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),

                          // Forgot Password (Login only)
                          if (_isLogin) ...[
                            SizedBox(height: 16),
                            TextButton(
                              onPressed: _sendPasswordResetEmail,
                              child: Text(
                                "Forgot your password?",
                                style: TextStyle(color: Colors.blue.shade600),
                              ),
                            ),
                          ],

                          SizedBox(height: 24),

                          // Divider
                          Row(
                            children: [
                              Expanded(child: Divider()),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'OR',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(child: Divider()),
                            ],
                          ),

                          SizedBox(height: 24),

                          // Toggle Mode Button
                          TextButton(
                            onPressed: _toggleMode,
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                                children: [
                                  TextSpan(
                                    text: _isLogin 
                                        ? "Don't have an account? "
                                        : "Already have an account? ",
                                  ),
                                  TextSpan(
                                    text: _isLogin ? 'Create one' : 'Sign in',
                                    style: TextStyle(
                                      color: Colors.blue.shade600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
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
        ),
      ),
    );
  }
}