// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:truckrader/providers/tracking_provider.dart';
import 'package:truckrader/main.dart';

void main() {
  testWidgets('Vehicle tracker app smoke test', (WidgetTester tester) async {
    // Create a mock provider for testing
    final provider = TrackingProvider();

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      VehicleTrackerApp(provider: provider),
    );

    // Verify that the app loads
    expect(find.byType(VehicleTrackerApp), findsOneWidget);
  });
}
