import 'package:flutter_test/flutter_test.dart';
import 'package:adlesstube/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const AdlessTubeApp());
    expect(find.text('AdlessTube'), findsOneWidget);
  });
}
