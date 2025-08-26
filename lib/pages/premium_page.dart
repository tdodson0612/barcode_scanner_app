// lib/pages/premium_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:io';
import '../services/database_service.dart';
import '../controllers/premium_gate_controller.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> with TickerProviderStateMixin {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _isPremium = false;
  bool _isTester = false;
  bool _isAvailable = false;
  int _dailyScans = 0;
  int _remainingScans = 0;
  String? _selectedPlan;
  List<ProductDetails> _products = <ProductDetails>[];
  
  // Tester key functionality
  final TextEditingController _testerKeyController = TextEditingController();
  bool _showTesterKeyInput = false;
  bool _isValidTesterKey = false;
  static const String testerKey = '82125';

  // Product IDs
  static const String premiumProductId = 'premium_upgrade';
  static const String testerProductId = 'tester_upgrade';
  static const Set<String> _productIds = {premiumProductId, testerProductId};

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _initializePremiumPage();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _animationController.dispose();
    _testerKeyController.dispose();
    super.dispose();
  }

  Future<void> _initializePremiumPage() async {
    try {
      DatabaseService.ensureUserAuthenticated();
      await _checkPremiumStatus();
      await _initializeInAppPurchase();
      _animationController.forward();
    } catch (e) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _checkPremiumStatus() async {
    try {
      final userId = DatabaseService.currentUserId;
      if (userId == null) return;

      // Check local cache first
      final prefs = await SharedPreferences.getInstance();
      final localPremium = prefs.getBool('isPremiumUser') ?? false;
      final localTester = prefs.getBool('isTesterUser') ?? false;

      if (localPremium || localTester) {
        setState(() {
          _isPremium = localPremium;
          _isTester = localTester;
        });
      }

      // Fetch from Supabase to ensure sync
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('users')
          .select('is_premium')
          .eq('id', userId)
          .single();

      final premiumStatus = response['is_premium'] as bool? ?? false;
      
      // Update local cache
      await prefs.setBool('isPremiumUser', premiumStatus);

      final dailyScans = await DatabaseService.getDailyScanCount();
      final remainingScans = (premiumStatus || localTester) ? -1 : (3 - dailyScans);

      setState(() {
        _isPremium = premiumStatus;
        _isTester = localTester && !premiumStatus; // Tester only if not premium
        _dailyScans = dailyScans;
        _remainingScans = remainingScans;
      });
    } catch (e) {
      debugPrint('Error checking premium status: $e');
    }
  }

  Future<void> _initializeInAppPurchase() async {
    final bool isAvailable = await _inAppPurchase.isAvailable();
    setState(() {
      _isAvailable = isAvailable;
      _isLoading = false;
    });

    if (!isAvailable) return;

    // Listen to purchase updates
    final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription.cancel(),
      onError: (Object error) {
        _showErrorSnackBar('Purchase error: $error');
      },
    );

    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    if (!_isAvailable) return;

    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(_productIds);
    setState(() {
      _products = response.productDetails;
    });
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          setState(() => _isPurchasing = true);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _handleSuccessfulPurchase(purchaseDetails);
          break;
        case PurchaseStatus.error:
          setState(() => _isPurchasing = false);
          _showErrorSnackBar('Purchase failed: ${purchaseDetails.error?.message}');
          break;
        case PurchaseStatus.canceled:
          setState(() => _isPurchasing = false);
          break;
      }

      if (purchaseDetails.pendingCompletePurchase) {
        _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }

  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchaseDetails) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = DatabaseService.currentUserId;
      
      if (userId == null) throw Exception('User not authenticated');

      String planName;
      final supabase = Supabase.instance.client;

      if (purchaseDetails.productID == premiumProductId) {
        // Update Supabase database
        await supabase.from('users').update({'is_premium': true}).eq('id', userId);
        
        // Update DatabaseService
        await DatabaseService.setPremiumStatus(true);
        
        // Update local cache
        await prefs.setBool('isPremiumUser', true);
        await prefs.setBool('isTesterUser', false);
        
        planName = 'Premium';
        setState(() {
          _isPremium = true;
          _isTester = false;
        });
      } else if (purchaseDetails.productID == testerProductId) {
        // Testers don't get database premium status, just local
        await prefs.setBool('isTesterUser', true);
        await prefs.setBool('isPremiumUser', false);
        
        planName = 'Tester';
        setState(() {
          _isTester = true;
          _isPremium = false;
        });
      } else {
        throw Exception('Unknown product ID: ${purchaseDetails.productID}');
      }

      // Store detailed purchase information
      await prefs.setString('purchaseDate', DateTime.now().toIso8601String());
      await prefs.setString('planType', _selectedPlan!);
      await prefs.setString('productId', purchaseDetails.productID);
      await prefs.setString('transactionId', purchaseDetails.transactionDate ?? DateTime.now().millisecondsSinceEpoch.toString());

      // Refresh premium controller
      await PremiumGateController().refresh();

      setState(() {
        _remainingScans = -1;
        _isPurchasing = false;
      });

      if (mounted) {
        _showSuccessSnackBar('Welcome to $planName! Purchase successful.');
        
        // Navigate back and reload the app to ensure all features are available
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ReloadApp()),
              (route) => false,
            );
          }
        });
      }
    } catch (e) {
      setState(() => _isPurchasing = false);
      
      // Show specific error for purchase success but account update failure
      _showErrorSnackBar('Purchase successful, but failed to update account: $e. Please contact support.');
    }
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
      _showErrorSnackBar('Invalid tester key. Please try again or choose Premium.');
    }
  }

  Future<void> _purchasePlan() async {
    if (_selectedPlan == null) {
      _showErrorSnackBar('Please select a plan first');
      return;
    }

    if (_selectedPlan == 'tester' && !_isValidTesterKey) {
      _showErrorSnackBar('Please enter a valid tester key');
      return;
    }

    if (!_isAvailable) {
      _showErrorSnackBar('In-app purchases are not available');
      return;
    }

    setState(() => _isPurchasing = true);

    try {
      final String productId = _selectedPlan == 'premium' ? premiumProductId : testerProductId;
      final ProductDetails? productDetails = _products.cast<ProductDetails?>().firstWhere(
        (product) => product?.id == productId,
        orElse: () => null,
      );

      if (productDetails == null) {
        throw Exception('Product not found');
      }

      final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
      await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      setState(() => _isPurchasing = false);
      _showErrorSnackBar('Failed to start purchase: $e');
    }
  }

  Future<void> _restorePurchases() async {
    if (!_isAvailable) return;

    setState(() => _isPurchasing = true);
    try {
      await _inAppPurchase.restorePurchases();
    } catch (e) {
      setState(() => _isPurchasing = false);
      _showErrorSnackBar('Failed to restore purchases: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _getProductPrice(String productId) {
    try {
      final product = _products.firstWhere((p) => p.id == productId);
      return product.price;
    } catch (e) {
      // Fallback prices if products aren't loaded
      return productId == premiumProductId ? '\$9.99' : '\$4.99';
    }
  }

  Widget _buildStatusCard() {
    String title;
    String subtitle;
    IconData icon;
    Color iconColor;
    Color backgroundColor;

    if (_isPremium) {
      title = 'Premium Active!';
      subtitle = 'You have access to all premium features!';
      icon = Icons.star;
      iconColor = Colors.amber.shade600;
      backgroundColor = Colors.amber.shade50;
    } else if (_isTester) {
      title = 'Tester Active!';
      subtitle = 'Thank you for helping us improve LiverWise!';
      icon = Icons.science;
      iconColor = Colors.blue.shade600;
      backgroundColor = Colors.blue.shade50;
    } else {
      title = 'Choose Your Plan';
      subtitle = 'Unlock the full potential of LiverWise';
      icon = Icons.star_outline;
      iconColor = Colors.grey.shade600;
      backgroundColor = Colors.grey.shade50;
    }

    return Container(
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 64, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
          
          if (!_isPremium && !_isTester) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _remainingScans <= 0 ? Colors.red.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _remainingScans <= 0 ? Colors.red.shade200 : Colors.blue.shade200,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Free Account Limits',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _remainingScans <= 0 ? Colors.red.shade700 : Colors.blue.shade700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Daily scans used: $_dailyScans/3',
                    style: TextStyle(
                      color: _remainingScans <= 0 ? Colors.red.shade600 : Colors.blue.shade600,
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
    );
  }

  Widget _buildFeaturesCard() {
    final premiumFeatures = [
      {'icon': Icons.all_inclusive, 'title': 'Unlimited daily scans'},
      {'icon': Icons.shopping_cart, 'title': 'Personal grocery list'},
      {'icon': Icons.favorite, 'title': 'Save favorite recipes'},
      {'icon': Icons.restaurant_menu, 'title': 'Submit your own recipes'},
      {'icon': Icons.menu_book, 'title': 'Full recipe details & directions'},
      {'icon': Icons.add_shopping_cart, 'title': 'Add recipes to shopping list'},
      {'icon': Icons.support_agent, 'title': 'Priority customer support'},
      {'icon': Icons.sync, 'title': 'Sync across all devices'},
    ];

    return Container(
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
          
          ...premiumFeatures.map((feature) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(
                  (_isPremium || _isTester) ? Icons.check_circle : Icons.check_circle_outline,
                  color: (_isPremium || _isTester) ? Colors.green : Colors.amber,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    feature['title'] as String,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }

  Widget _buildPlanSelection() {
    if (_isPremium || _isTester) return const SizedBox.shrink();

    return Container(
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
            'Choose your subscription plan:',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          
          // Premium Plan Card
          Card(
            elevation: _selectedPlan == 'premium' ? 8 : 2,
            color: _selectedPlan == 'premium' ? Colors.amber.shade50 : null,
            child: InkWell(
              onTap: () => _selectPlan('premium'),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Radio<String>(
                      value: 'premium',
                      groupValue: _selectedPlan,
                      onChanged: (value) => _selectPlan(value!),
                      activeColor: Colors.amber.shade600,
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
                    Text(
                      _getProductPrice(premiumProductId),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Tester Plan Card
          Card(
            elevation: _selectedPlan == 'tester' ? 8 : 2,
            color: _selectedPlan == 'tester' ? Colors.orange.shade50 : null,
            child: InkWell(
              onTap: () => _selectPlan('tester'),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Radio<String>(
                      value: 'tester',
                      groupValue: _selectedPlan,
                      onChanged: (value) => _selectPlan(value!),
                      activeColor: Colors.orange.shade600,
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
                    Text(
                      _getProductPrice(testerProductId),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
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
          
          const SizedBox(height: 24),
          
          // Purchase Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isPurchasing ? null : _purchasePlan,
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedPlan == 'premium' ? Colors.amber : Colors.orange,
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
                              ? 'Purchase Premium - ${_getProductPrice(premiumProductId)}'
                              : _isValidTesterKey
                                  ? 'Purchase Tester Access - ${_getProductPrice(testerProductId)}'
                                  : 'Enter Valid Tester Key',
                      style: const TextStyle(fontSize: 16),
                    ),
            ),
          ),
          
          const SizedBox(height: 16),
          Text(
            'Purchases are processed through ${Platform.isIOS ? 'App Store' : 'Google Play'}. By purchasing, you agree to our Terms of Service and Privacy Policy.',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAlreadyPurchasedCard() {
    if (!_isPremium && !_isTester) return const SizedBox.shrink();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _isPremium ? Colors.green.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _isPremium ? Colors.green.shade200 : Colors.blue.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.verified,
            size: 48,
            color: _isPremium ? Colors.green.shade600 : Colors.blue.shade600,
          ),
          const SizedBox(height: 16),
          Text(
            _isPremium ? 'You\'re all set!' : 'You\'re a Tester!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _isPremium ? Colors.green.shade700 : Colors.blue.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isPremium 
                ? 'Enjoy unlimited access to all premium features. Thank you for supporting LiverWise!'
                : 'Thank you for helping us improve the app! Your feedback is invaluable.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: _isPremium ? Colors.green.shade600 : Colors.blue.shade600,
            ),
          ),
        ],
      ),
    );
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
        actions: [
          if (!_isPremium && !_isTester && _isAvailable)
            TextButton(
              onPressed: _restorePurchases,
              child: const Text(
                'Restore',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
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
          FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 30),
                  _buildFeaturesCard(),
                  const SizedBox(height: 30),
                  _buildPlanSelection(),
                  _buildAlreadyPurchasedCard(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ReloadApp widget to restart the entire app after purchase
class ReloadApp extends StatelessWidget {
  const ReloadApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Import your main app widget here
    // This assumes your main app widget is called MyApp
    // Replace with your actual main app widget
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('Activating your features...'),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  // Navigate to home or restart app logic here
                  Navigator.of(context).pushReplacementNamed('/');
                },
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}