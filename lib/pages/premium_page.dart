// lib/pages/premium_page.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../controllers/premium_gate_controller.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _isPremium = false;
  int _dailyScans = 0;
  int _remainingScans = 0;

  @override
  void initState() {
    super.initState();
    _initializePremiumStatus();
  }

  Future<void> _initializePremiumStatus() async {
    try {
      DatabaseService.ensureUserAuthenticated();
      
      final isPremium = await DatabaseService.isPremiumUser();
      final dailyScans = await DatabaseService.getDailyScanCount();
      final remainingScans = isPremium ? -1 : (3 - dailyScans);

      setState(() {
        _isPremium = isPremium;
        _dailyScans = dailyScans;
        _remainingScans = remainingScans;
        _isLoading = false;
      });
    } catch (e) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _purchasePremium() async {
    setState(() => _isPurchasing = true);

    try {
      // Simulate purchase process (replace with real payment integration)
      await Future.delayed(const Duration(seconds: 2));

      // Update premium status in database
      await DatabaseService.setPremiumStatus(true);

      // Refresh premium controller
      await PremiumGateController().refresh();

      setState(() {
        _isPremium = true;
        _remainingScans = -1; // Unlimited
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Welcome to Premium! Enjoy unlimited features!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // Navigate back to home
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to activate premium: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        title: const Text('Premium Subscription'),
        backgroundColor: Colors.amber,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.amber, Colors.orange],
              ),
            ),
          ),
          
          // Content
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Premium Status Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _isPremium ? Icons.star : Icons.star_outline,
                        size: 80,
                        color: Colors.amber,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isPremium ? 'Premium Active!' : 'Go Premium',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isPremium 
                            ? 'You have access to all premium features!'
                            : 'Unlock the full potential of LiverWise',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      
                      if (!_isPremium) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Free Account Limits',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Daily scans used: $_dailyScans/3',
                                style: TextStyle(
                                  color: Colors.red.shade600,
                                  fontSize: 14,
                                ),
                              ),
                              if (_remainingScans <= 0)
                                Text(
                                  'No scans remaining today',
                                  style: TextStyle(
                                    color: Colors.red.shade600,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // Features List
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Premium Features',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      ...[
                        '🚀 Unlimited daily scans',
                        '📋 Personal grocery list',
                        '⭐ Save favorite recipes',
                        '📝 Submit your own recipes',
                        '🍽️ Full recipe details & directions',
                        '🛒 Add recipes to shopping list',
                        '⚡ Priority customer support',
                        '🔄 Sync across all devices',
                      ].map((feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Icon(
                              _isPremium ? Icons.check_circle : Icons.check_circle_outline,
                              color: _isPremium ? Colors.green : Colors.amber,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                feature,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // Pricing Card
                if (!_isPremium)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Special Launch Price',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '\$9.99',
                              style: TextStyle(
                                fontSize: 20,
                                color: Colors.grey.shade500,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              '\$4.99',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                              ),
                            ),
                            const Text(
                              '/month',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '50% OFF - Limited Time!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.red.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isPurchasing ? null : _purchasePremium,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 8,
                            ),
                            child: _isPurchasing
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Processing...',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Text(
                                    'Upgrade to Premium Now',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Cancel anytime • No hidden fees',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Already Premium Message
                if (_isPremium)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.verified,
                          size: 48,
                          color: Colors.green.shade600,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'You\'re all set!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enjoy unlimited access to all premium features. Thank you for supporting LiverWise!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}