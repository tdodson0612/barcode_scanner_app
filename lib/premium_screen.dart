import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/database_service.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _isPremium = false;
  bool _isLoading = true;
  bool _isPurchasing = false;

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    try {
      DatabaseService.ensureUserAuthenticated();
      await _checkPremiumStatus();
    } catch (e) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _checkPremiumStatus() async {
    final userId = DatabaseService.currentUserId;
    if (userId == null) return;

    try {
      // Check local cache first
      final prefs = await SharedPreferences.getInstance();
      final localPremium = prefs.getBool('isPremiumUser') ?? false;

      if (localPremium) {
        setState(() {
          _isPremium = true;
          _isLoading = false;
        });
        return;
      }

      // Fetch premium status from Supabase
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('users') // assuming you have a 'users' table with 'is_premium' column
          .select('is_premium')
          .eq('id', userId)
          .single();

      final premiumStatus = response['is_premium'] as bool? ?? false;

      // Update local cache
      await prefs.setBool('isPremiumUser', premiumStatus);

      setState(() {
        _isPremium = premiumStatus;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking premium status: $e')),
      );
    }
  }

  Future<void> _purchasePremium() async {
    setState(() => _isPurchasing = true);

    try {
      // Simulate purchase process (replace with real payment logic)
      await Future.delayed(const Duration(seconds: 2));

      final userId = DatabaseService.currentUserId;
      if (userId == null) throw Exception('User not authenticated');

      final supabase = Supabase.instance.client;

      // Update premium status in Supabase
      await supabase.from('users').update({'is_premium': true}).eq('id', userId);

      // Update local cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isPremiumUser', true);

      setState(() {
        _isPremium = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Premium activated! Enjoy unlimited features.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error activating premium: $e')),
      );
    } finally {
      setState(() => _isPurchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium Features'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha((0.9 * 255).toInt()),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(Icons.star, size: 64, color: Colors.amber),
                  const SizedBox(height: 16),
                  Text(
                    _isPremium ? 'You are a Premium User!' : 'Go Premium',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isPremium
                        ? 'Enjoy unlimited features and full access.'
                        : 'Unlock unlimited daily scans and premium features.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isPremium || _isPurchasing ? null : _purchasePremium,
                      icon: _isPurchasing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.payment, size: 20),
                      label: Text(
                        _isPremium
                            ? 'Premium Active'
                            : _isPurchasing
                                ? 'Processing...'
                                : 'Purchase Premium',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
