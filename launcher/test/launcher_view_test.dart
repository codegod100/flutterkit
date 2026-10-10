import 'package:flatkit/flatkit.dart';
import 'package:flatkit_launcher/src/apps.dart';
import 'package:flatkit_launcher/src/desktop_entry.dart';
import 'package:flatkit_launcher/src/icons.dart';
import 'package:flatkit_launcher/src/launcher_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final apps = [
  const DesktopEntry(
    id: 'firefox.desktop',
    path: '',
    name: 'Firefox',
    genericName: 'Web Browser',
    exec: 'firefox %u',
    actions: [DesktopAction(id: 'private', name: 'New Private Window', exec: 'firefox --private-window')],
  ),
  const DesktopEntry(id: 'kate.desktop', path: '', name: 'Kate', exec: 'kate'),
  const DesktopEntry(id: 'konsole.desktop', path: '', name: 'Konsole', exec: 'konsole'),
];

void main() {
  late List<String> launched;
  late int hides;

  Future<void> pump(WidgetTester tester) async {
    launched = [];
    hides = 0;
    tester.view.physicalSize = const Size(680, 460);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: KitTheme.material(KitColors.dark),
      builder: (context, child) => KitTheme(
        colors: KitColors.dark,
        child: Material(child: DefaultTextStyle(style: kitTextStyle, child: child!)),
      ),
      home: LauncherView(
        apps: apps,
        icons: IconIndex.empty(),
        history: LaunchHistory.memory(),
        services: LauncherServices(
          launchApp: (e, a) async => launched.add(a == null ? e.id : '${e.id}#${a.id}'),
          runCommand: (c, t) async => launched.add('${t ? 'term' : 'sh'}:$c'),
          hide: () async => hides++,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('typing filters and Enter launches the top match', (tester) async {
    await pump(tester);
    expect(find.text('Firefox'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'kon');
    await tester.pump();
    expect(find.text('Kate'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(launched, ['konsole.desktop']);
    expect(hides, 1);
  });

  testWidgets('arrows move the selection', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(launched, ['kate.desktop']);
  });

  testWidgets('Tab lists an app\'s actions', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(EditableText), 'fire');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.text('New Private Window'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('New Private Window'), findsNothing);
    expect(hides, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(launched, ['firefox.desktop#private']);
  });

  testWidgets('unmatched text runs as a command; sums show an answer', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(EditableText), 'echo hi');
    await tester.pump();
    expect(find.text('Run “echo hi”'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(launched, ['sh:echo hi']);

    await tester.enterText(find.byType(EditableText), '6*7');
    await tester.pump();
    expect(find.text('= 42'), findsOneWidget);
  });

  testWidgets('Escape hides the window', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(hides, 1);
    expect(launched, isEmpty);
  });
}
