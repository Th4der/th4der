import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/chat_api.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('Th4der home renders', (WidgetTester tester) async {
    await tester.pumpWidget(Th4derApp(api: DemoChatApi()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Th4der'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
  });
}
