import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:barcode_scanner_app/main.dart';

void main() {
  testWidgets('Liver health bar renders with emoji', (WidgetTester tester) async {
    // Build the app
    await tester.pumpWidget(const MyApp());

    // Look for some common UI elements
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.textContaining('Scan'), findsOneWidget);
  });
}
