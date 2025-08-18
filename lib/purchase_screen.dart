import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; 

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  Future<void> _goPremium() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isPremiumUser', true);

    if (!mounted) return; // <-- check if widget is still in the widget tree

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You are now a Premium user!')),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ReloadApp()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade to Premium')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Upgrade to remove ads and unlock premium features!',
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _goPremium,
              child: const Text('Upgrade for \$9.99'),
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
