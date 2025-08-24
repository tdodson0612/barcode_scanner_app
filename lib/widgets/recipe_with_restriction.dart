import 'package:flutter/material.dart';
import '../services/premium_service.dart';

class RecipeWithRestriction extends StatelessWidget {
  final String recipeName;
  final String ingredients;
  final String directions;

  const RecipeWithRestriction({
    Key? key,
    required this.recipeName,
    required this.ingredients,
    required this.directions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: PremiumService.canAccessPremiumFeature(),
      builder: (context, snapshot) {
        final isPremium = snapshot.data ?? false;
        
        return Card(
          margin: EdgeInsets.all(16),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.restaurant, color: Colors.green),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        recipeName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!isPremium) ...[
                      Icon(Icons.star, color: Colors.amber, size: 20),
                    ],
                  ],
                ),
                SizedBox(height: 16),
                
                if (isPremium) ...[
                  // Show full recipe for premium users
                  Text(
                    'Ingredients:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(ingredients),
                  SizedBox(height: 16),
                  Text(
                    'Directions:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(directions),
                ] else ...[
                  // Show limited preview for free users
                  Text(
                    'Ingredients:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '${ingredients.length > 50 ? ingredients.substring(0, 50) + '...' : ingredients}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  SizedBox(height: 16),
                  
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.star, color: Colors.amber),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Upgrade to Premium to see the full recipe!',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pushNamed(context, '/premium');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.white,
                            ),
                            child: Text('Upgrade Now'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}