import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  bool _isLoading = false;
  String? _selectedPlan;
  final TextEditingController _testerKeyController = TextEditingController();
  bool _showTesterKeyInput = false;
  bool _isValidTesterKey = false;

  // Your Stripe configuration
  static const String publishableKey = 'pk_live_YOUR_STRIPE_PUBLISHABLE_KEY'; // Replace with your key
  static const String backendUrl = 'https://your-backend.com'; // Replace with your backend URL
  static const String testerKey = '82125';

  @override
  void initState() {
    super.initState();
    // Initialize Stripe
    Stripe.publishableKey = publishableKey;
  }

  @override
  void dispose() {
    _testerKeyController.dispose();
    super.dispose();
  }

  void _selectPlan(String plan) {
    setState(() {
      _selectedPlan = plan;
      if (plan == 'tester') {
        _showTesterKeyInput = true;
        _isValidTesterKey = false;
      } else {
        _showTesterKeyInput = false;
        _isValidTesterKey = false;
      }
    });
  }

  void _validateTesterKey() {
    final enteredKey = _testerKeyController.text.trim();
    setState(() {
      _isValidTesterKey = enteredKey == testerKey;
    });

    if (!_isValidTesterKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid tester key. Please try again or choose Premium.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _createPaymentIntent(String amount, String currency) async {
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/create-payment-intent'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'amount': amount,
          'currency': currency,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to create payment intent');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  Future<void> _processPayment() async {
    if (_selectedPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a plan first')),
      );
      return;
    }

    if (_selectedPlan == 'tester' && !_isValidTesterKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid tester key')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Determine amount based on selected plan
      final amount = _selectedPlan == 'premium' ? '999' : '499'; // Amount in cents
      final planName = _selectedPlan == 'premium' ? 'Premium' : 'Tester';

      // Create payment intent
      final paymentIntentData = await _createPaymentIntent(amount, 'usd');
      
      // Initialize payment sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntentData['client_secret'],
          merchantDisplayName: 'Your App Name',
          style: ThemeMode.system,
          appearance: const PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: Colors.blue,
            ),
          ),
        ),
      );

      // Present payment sheet
      await Stripe.instance.presentPaymentSheet();

      // Payment successful
      await _handleSuccessfulPayment(planName);

    } on StripeException catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (e.error.code != FailureCode.Canceled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: ${e.error.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleSuccessfulPayment(String planName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (_selectedPlan == 'premium') {
        await prefs.setBool('isPremiumUser', true);
        await prefs.setBool('isTesterUser', false);
      } else {
        await prefs.setBool('isTesterUser', true);
        await prefs.setBool('isPremiumUser', false);
      }

      // Store purchase date
      await prefs.setString('purchaseDate', DateTime.now().toIso8601String());
      await prefs.setString('planType', _selectedPlan!);

      setState(() {
        _isLoading = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome to $planName! Payment successful.'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate back to main app
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ReloadApp()),
        (route) => false,
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment successful, but failed to update account: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Plan'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Choose your subscription plan:',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            
            // Premium Plan Card
            Card(
              elevation: _selectedPlan == 'premium' ? 8 : 2,
              color: _selectedPlan == 'premium' ? Colors.blue.shade50 : null,
              child: InkWell(
                onTap: () => _selectPlan('premium'),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Radio<String>(
                            value: 'premium',
                            groupValue: _selectedPlan,
                            onChanged: (value) => _selectPlan(value!),
                          ),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Premium Plan',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 5),
                                Text(
                                  '• Remove all ads\n• Unlock all premium features\n• Priority support\n• Full access to all content',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            '\$9.99',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Tester Plan Card
            Card(
              elevation: _selectedPlan == 'tester' ? 8 : 2,
              color: _selectedPlan == 'tester' ? Colors.orange.shade50 : null,
              child: InkWell(
                onTap: () => _selectPlan('tester'),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Radio<String>(
                            value: 'tester',
                            groupValue: _selectedPlan,
                            onChanged: (value) => _selectPlan(value!),
                          ),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tester Plan',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 5),
                                Text(
                                  '• Early access to features\n• Help shape the app\n• Provide feedback\n• Special tester key required',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            '\$4.99',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Tester Key Input
            if (_showTesterKeyInput) ...[
              const SizedBox(height: 20),
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter Tester Key:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _testerKeyController,
                              decoration: const InputDecoration(
                                hintText: 'Enter your tester key',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                if (value.trim() == testerKey) {
                                  _validateTesterKey();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _validateTesterKey,
                            child: const Text('Verify'),
                          ),
                        ],
                      ),
                      if (_isValidTesterKey)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green),
                              SizedBox(width: 5),
                              Text(
                                'Valid tester key!',
                                style: TextStyle(color: Colors.green),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            
            const Spacer(),
            
            // Purchase Button
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedPlan == 'premium' ? Colors.blue : Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const Row(
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
                          SizedBox(width: 10),
                          Text('Processing...'),
                        ],
                      )
                    : Text(
                        _selectedPlan == null
                            ? 'Select a Plan'
                            : _selectedPlan == 'premium'
                                ? 'Purchase Premium - \$9.99'
                                : _isValidTesterKey
                                    ? 'Purchase Tester Access - \$4.99'
                                    : 'Enter Valid Tester Key',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Terms and conditions
            const Text(
              'By purchasing, you agree to our Terms of Service and Privacy Policy. Payments are processed securely through Stripe.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// This widget simply reloads the app
class ReloadApp extends StatelessWidget {
  const ReloadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MyApp();
  }
}