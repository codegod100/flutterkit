import 'dart:io';

import 'package:flatkit/flatkit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Trimmed from Plasma 6's Breeze Dark.
const breezeDark = '''
[ColorEffects:Disabled]
Color=56,56,56

[Colors:Button]
BackgroundNormal=41,44,48
ForegroundNormal=252,252,252

[Colors:Selection]
BackgroundNormal=61,174,233
ForegroundNormal=252,252,252

[Colors:View]
BackgroundNormal=20,22,24
DecorationFocus=61,174,233
ForegroundNegative=218,68,83
ForegroundPositive=39,174,96

[Colors:Window]
BackgroundNormal=32,35,38
ForegroundInactive=161,169,177
ForegroundNormal=252,252,252

[General]
ColorScheme=BreezeDark
''';

const breezeLight = '''
[Colors:Window]
BackgroundNormal=239,240,241
ForegroundNormal=35,38,41
''';

void main() {
  test('maps Breeze Dark onto kit colours', () {
    final c = KdeColors.parse(breezeDark)!;
    expect(c.brightness, Brightness.dark);
    expect(c.background, const Color(0xFF202326));
    expect(c.surface, const Color(0xFF292C30));
    expect(c.text, const Color(0xFFFCFCFC));
    expect(c.textDim, const Color(0xFFA1A9B1));
    expect(c.accent, const Color(0xFF3DAEE9));
    expect(c.danger, const Color(0xFFDA4453));
    expect(c.success, const Color(0xFF27AE60));
  });

  test('a light scheme fills gaps from the light defaults', () {
    final c = KdeColors.parse(breezeLight)!;
    expect(c.brightness, Brightness.light);
    expect(c.background, const Color(0xFFEFF0F1));
    expect(c.accent, KitColors.light.accent);
    expect(c.surface, KitColors.light.surface);
  });

  test('the accent colour setting wins over the selection colour', () {
    final c = KdeColors.parse('$breezeDark\n[General]\nAccentColor=#ff8800\n')!;
    expect(c.accent, const Color(0xFFFF8800));
  });

  test('no colour scheme, no colours', () {
    expect(KdeColors.parse('[General]\nfont=Noto Sans,10\n'), isNull);
    expect(KdeColors.parse(''), isNull);
  });

  test('only Plasma sessions read kdeglobals', () {
    final dir = Directory.systemTemp.createTempSync('flatkit');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/kdeglobals').writeAsStringSync(breezeDark);
    expect(KdeColors.read({'XDG_CONFIG_HOME': dir.path, 'XDG_CURRENT_DESKTOP': 'GNOME'}), isNull);
    expect(KdeColors.read({'XDG_CONFIG_HOME': dir.path, 'XDG_CURRENT_DESKTOP': 'KDE'})?.brightness,
        Brightness.dark);
    expect(KdeColors.read({'HOME': '/nonexistent', 'KDE_FULL_SESSION': 'true'}), isNull);
  });

  testWidgets('KitSystemTheme follows kdeglobals as it changes', (tester) async {
    final dir = Directory.systemTemp.createTempSync('flatkit');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/kdeglobals')..writeAsStringSync(breezeDark);
    KitColors? seen;
    await tester.pumpWidget(KitSystemTheme(
      environment: {'XDG_CONFIG_HOME': dir.path, 'XDG_CURRENT_DESKTOP': 'KDE'},
      builder: (context, colors) {
        seen = KitTheme.of(context);
        return const SizedBox();
      },
    ));
    expect(seen?.brightness, Brightness.dark);

    // Save the way KConfig does: write elsewhere, rename over.
    await tester.runAsync(() async {
      File('${dir.path}/kdeglobals.tmp')
        ..writeAsStringSync(breezeLight)
        ..renameSync(file.path);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    // The reload is debounced on a timer in the test's fake clock.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(seen?.brightness, Brightness.light);
    expect(seen?.background, const Color(0xFFEFF0F1));
  });

  testWidgets('KitSystemTheme uses the plain light/dark colours off Plasma', (tester) async {
    KitColors? seen;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(KitSystemTheme(
      environment: const {'XDG_CURRENT_DESKTOP': 'GNOME'},
      builder: (context, colors) {
        seen = colors;
        return const SizedBox();
      },
    ));
    expect(seen, same(KitColors.dark));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    expect(seen, same(KitColors.light));
  });
}
