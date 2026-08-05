import 'package:flutter_test/flutter_test.dart';
import 'package:semflix/main.dart';

void main() {
  testWidgets('App renders the SemFlix header', (tester) async {
    await tester.pumpWidget(const SemFlixApp());
    await tester.pump();
    expect(find.text('SemFlix TV'), findsOneWidget);
  });
}
