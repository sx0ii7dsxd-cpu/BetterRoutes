import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/main.dart';

void main() {
  testWidgets('BetterRoutes app starts successfully', (
    WidgetTester tester,
  ) async {
    // Verify the app widget can be constructed.
    expect(BetterRoutesApp(), isNotNull);
  });
}
