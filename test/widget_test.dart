import 'package:flutter_test/flutter_test.dart';

import 'package:notifyy/main.dart';

void main() {
  testWidgets('Home page renders', (WidgetTester tester) async {
    await tester.pumpWidget(const NotesApp());

    expect(find.text('AI Notes Generator'), findsOneWidget);
    expect(find.text('Generate PDF'), findsOneWidget);
  });
}
