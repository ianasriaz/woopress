import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:woo_press/features/orders/presentation/widgets/status_filter_bar.dart';

const _labels = ['ALL', 'PROCESSING', 'ON HOLD', 'COMPLETED', 'CANCELLED'];

Widget _harness({required double width, required String currentStatus, required ValueChanged<String> onSelected}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: StatusFilterBar(currentStatus: currentStatus, onSelected: onSelected),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('every label stays on a single row on a very narrow phone', (tester) async {
    // 280px of usable width — narrower than any real device — must not overflow
    // the row or force a label onto a second line.
    await tester.pumpWidget(_harness(width: 280, currentStatus: 'all', onSelected: (_) {}));
    for (final label in _labels) {
      expect(find.text(label), findsOneWidget, reason: '"$label" should be rendered exactly once');
      expect(tester.takeException(), isNull, reason: '"$label" should not overflow its chip');
    }
    expect(find.byType(FittedBox), findsNWidgets(_labels.length));
  });

  testWidgets('the selected filter chip is highlighted', (tester) async {
    await tester.pumpWidget(_harness(width: 400, currentStatus: 'completed', onSelected: (_) {}));

    final selectedChip = find.ancestor(of: find.text('COMPLETED'), matching: find.byType(Container)).first;
    final BoxDecoration decoration = tester.widget<Container>(selectedChip).decoration as BoxDecoration;

    expect(decoration.color, isNotNull);
  });

  testWidgets('tapping a chip reports its status id', (tester) async {
    String? selected;
    await tester.pumpWidget(_harness(width: 400, currentStatus: 'all', onSelected: (id) => selected = id));

    await tester.tap(find.text('PROCESSING'));
    await tester.pumpAndSettle();

    expect(selected, 'processing');
  });
}
