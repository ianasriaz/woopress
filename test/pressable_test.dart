import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:woo_press/core/widgets/pressable.dart';

void main() {
  testWidgets('tapping fires the callback exactly once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: Pressable(onTap: () => taps++, child: const Icon(Icons.phone))))),
    );

    await tester.tap(find.byType(Pressable));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('finger down visibly presses the content, release springs back', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: Pressable(onTap: () => taps++, child: const Icon(Icons.phone))))),
    );

    AnimatedScale whilePressed = tester.widget(find.byType(AnimatedScale));
    expect(whilePressed.scale, 1.0, reason: 'idle state should be unscaled');

    final gesture = await tester.startGesture(tester.getCenter(find.byIcon(Icons.phone)));
    await tester.pumpAndSettle();

    whilePressed = tester.widget(find.byType(AnimatedScale));
    expect(whilePressed.scale, lessThan(1.0), reason: 'finger down should shrink the button for tactile feedback');

    await gesture.up();
    await tester.pumpAndSettle();

    whilePressed = tester.widget(find.byType(AnimatedScale));
    expect(whilePressed.scale, 1.0, reason: 'release should spring back');
    expect(taps, 1);
  });

  testWidgets('no callback fires when only pressing down and cancelling', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: Pressable(onTap: () => taps++, child: const Icon(Icons.phone))))),
    );

    final gesture = await tester.startGesture(tester.getCenter(find.byIcon(Icons.phone)));
    await tester.pumpAndSettle();
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(taps, 0);
  });
}
