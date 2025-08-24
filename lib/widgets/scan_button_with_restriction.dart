import 'package:flutter/material.dart';
import '../services/premium_service.dart';
import '../services/auth_service.dart';

class ScanButtonWithRestriction extends StatelessWidget {
  final VoidCallback onScanAllowed;
  final Widget child;

  const ScanButtonWithRestriction({
    Key? key,
    required this.onScanAllowed,
    required this.child,
  }) : super(key: key);

  Future<void> _handleScanTap(BuildContext context) async {
    if (!AuthService.isLoggedIn) {
      _showLoginDialog(context);
      return;
    }

    final canScan = await PremiumService.useScan();
    if (!canScan) {
      _showScanLimitDialog(context);
      return;
    }

    onScanAllowed();
  }

  void _showLoginDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Login Required'),
        content: Text('Please sign in to scan products.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/login');
            },
            child: Text('Sign In'),
          ),
        ],
      ),
    );
  }

  void _showScanLimitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.star, color: Colors.amber),
            SizedBox(width: 8),
            Text('Daily Limit Reached'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('You\'ve reached your daily scan limit.'),
            SizedBox(height: 12),
            Text('Upgrade to Premium for:'),
            Text('• Unlimited daily scans'),
            Text('• Full recipe access'),
            Text('• Personal grocery list'),
            Text('• Priority support'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/premium');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.white,
            ),
            child: Text('Upgrade Now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _handleScanTap(context),
      child: child,
    );
  }
}