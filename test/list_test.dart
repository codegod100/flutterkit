import 'package:flatkit/flatkit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'flatkit_test.dart' show host;

Color? rowColor(WidgetTester tester, String text) {
  final container = tester.widget<Container>(
      find.ancestor(of: find.text(text), matching: find.byType(Container)).first);
  return container.color;
}

void main() {
  testWidgets('list rows show selection by whether the list is active', (tester) async {
    var taps = 0;
    Widget rows(bool active) => host(SizedBox(
          width: 200,
          child: Column(children: [
            KitListRow(selected: true, active: active, onTap: () => taps++, child: const Text('a')),
            KitListRow(onTap: () => taps++, child: const Text('b')),
          ]),
        ));
    await tester.pumpWidget(rows(true));
    expect(rowColor(tester, 'a'), KitColors.light.accent);
    await tester.pumpWidget(rows(false));
    expect(rowColor(tester, 'a'), KitColors.light.pressed);
    await tester.tap(find.text('b'));
    expect(taps, 1);
  });

  testWidgets('selection list jumps to keep the selection in view', (tester) async {
    Widget list(int selected) => host(SizedBox(
          width: 200,
          height: 280,
          child: KitSelectionList(
            itemCount: 100,
            selectedIndex: selected,
            itemBuilder: (context, i, sel) => KitListRow(selected: sel, child: Text('row $i')),
          ),
        ));
    await tester.pumpWidget(list(0));
    expect(find.text('row 0'), findsOneWidget);
    await tester.pumpWidget(list(50));
    await tester.pump();
    expect(find.text('row 50'), findsOneWidget);
    expect(find.text('row 0'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('tabs switch on tap', (tester) async {
    var tab = 0;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (context, setState) => KitTabs<int>(
        tabs: const [(0, 'Metadata'), (1, 'Files')],
        selected: tab,
        onChanged: (v) => setState(() => tab = v),
      ),
    )));
    await tester.tap(find.text('Files'));
    await tester.pump();
    expect(tab, 1);
  });

  testWidgets('checkbox flips, and not when disabled', (tester) async {
    var on = false;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (context, setState) => Column(children: [
        KitCheckbox(value: on, label: 'linux-64', onChanged: (v) => setState(() => on = v)),
        const KitCheckbox(value: false, label: 'off', onChanged: null),
      ]),
    )));
    await tester.tap(find.text('linux-64'));
    await tester.pump();
    expect(on, true);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('off'));
    await tester.pump();
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('toast shows instantly and goes away after its duration', (tester) async {
    await tester.pumpWidget(host(Builder(
      builder: (context) => KitButton('Copy', onPressed: () => showKitToast(context, 'Copied')),
    )));
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('text field takes a focus node, style and trailing widget', (tester) async {
    final controller = TextEditingController(text: 'numpy');
    final focus = FocusNode();
    await tester.pumpWidget(host(SizedBox(
      width: 300,
      child: KitTextField(
        controller: controller,
        focusNode: focus,
        style: const TextStyle(fontFamily: 'monospace'),
        trailing: KitIconButton.compact(Icons.clear, onPressed: controller.clear),
      ),
    )));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, true);
    expect(tester.widget<TextField>(find.byType(TextField)).style?.fontFamily, 'monospace');
    expect(
        tester.getSize(
            find.ancestor(of: find.byIcon(Icons.clear), matching: find.byType(Container)).first),
        const Size(24, 24));
    await tester.tap(find.byIcon(Icons.clear));
    expect(controller.text, '');
    focus.dispose();
  });
}
