import 'dart:io';

import 'package:flatkit_launcher/src/apps.dart';
import 'package:flatkit_launcher/src/calc.dart';
import 'package:flatkit_launcher/src/desktop_entry.dart';
import 'package:flatkit_launcher/src/fuzzy.dart';
import 'package:flatkit_launcher/src/icons.dart';
import 'package:flutter_test/flutter_test.dart';

DesktopEntry app(String name, {String? generic, List<String> keywords = const [], String? exec}) =>
    DesktopEntry(
      id: '${name.toLowerCase().replaceAll(' ', '-')}.desktop',
      path: '',
      name: name,
      genericName: generic,
      keywords: keywords,
      exec: exec ?? name.toLowerCase().replaceAll(' ', ''),
    );

List<String> names(List<AppResult> r) => [for (final a in r) a.entry.name];

void main() {
  group('fuzzy', () {
    test('matches subsequences, case-insensitively', () {
      expect(fuzzyMatch('ffx', 'Firefox'), isNotNull);
      expect(fuzzyMatch('xff', 'Firefox'), isNull);
      expect(fuzzyMatch('FIRE', 'firefox')!.positions, [0, 1, 2, 3]);
    });

    test('prefers word starts', () {
      expect(fuzzyMatch('sm', 'System Monitor')!.positions, [0, 7]);
      expect(fuzzyMatch('vsc', 'Visual Studio Code')!.positions, [0, 7, 14]);
      expect(fuzzyMatch('ks', 'KSysGuard')!.positions, [0, 1]);
    });

    test('ranks prefixes and runs above scattered hits', () {
      double s(String p, String t) => fuzzyMatch(p, t)!.score;
      expect(s('kat', 'Kate'), greaterThan(s('kat', 'Krita Animation Tool')));
      expect(s('term', 'Terminal'), greaterThan(s('term', 'The Error Messenger')));
      expect(s('dol', 'Dolphin'), greaterThan(s('dol', 'KDE Dolphin Settings')));
    });
  });

  group('ranking', () {
    final apps = [
      app('Dolphin', generic: 'File Manager', keywords: ['files', 'explorer']),
      app('Files'),
      app('Konsole', generic: 'Terminal'),
      app('Kate', generic: 'Text Editor'),
      app('Krita', generic: 'Digital Painting'),
      app('Firefox', generic: 'Web Browser', exec: 'firefox %u'),
      app('Spotify', exec: 'flatpak run com.spotify.Client'),
    ];

    test('finds apps by name, generic name, keywords and command', () {
      final h = LaunchHistory.memory();
      expect(names(rank(apps, 'kon', h)).first, 'Konsole');
      expect(names(rank(apps, 'terminal', h)).first, 'Konsole');
      expect(names(rank(apps, 'files', h)), ['Files', 'Dolphin']);
      expect(names(rank(apps, 'client', h)), contains('Spotify'));
    });

    test('lifts often and recently used apps', () {
      final h = LaunchHistory.memory();
      expect(names(rank(apps, 'k', h)).first, 'Kate');
      h.record('krita.desktop');
      h.record('krita.desktop');
      expect(names(rank(apps, 'k', h)).first, 'Krita');
      expect(names(rank(apps, '', h)).first, 'Krita');
      // Everything else stays alphabetical.
      expect(names(rank(apps, '', h)).skip(1).take(2), ['Dolphin', 'Files']);
    });

    test('history survives a reload', () {
      final dir = Directory.systemTemp.createTempSync('launcher-history');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/state/history.json';
      LaunchHistory.load(path).record('kate.desktop');
      expect(LaunchHistory.load(path)['kate.desktop']!.count, 1);
    });
  });

  test('scans application dirs with shadowing and TryExec', () {
    final dir = Directory.systemTemp.createTempSync('launcher-apps');
    addTearDown(() => dir.deleteSync(recursive: true));
    final user = Directory('${dir.path}/user/applications')..createSync(recursive: true);
    final system = Directory('${dir.path}/system/applications')..createSync(recursive: true);
    Directory('${system.path}/kde').createSync();
    File('${system.path}/a.desktop').writeAsStringSync('[Desktop Entry]\nType=Application\nName=A\nExec=a\n');
    File('${system.path}/b.desktop').writeAsStringSync('[Desktop Entry]\nType=Application\nName=B\nExec=b\n');
    File('${user.path}/b.desktop').writeAsStringSync('[Desktop Entry]\nType=Application\nName=B\nExec=b\nHidden=true\n');
    File('${system.path}/kde/c.desktop').writeAsStringSync('[Desktop Entry]\nType=Application\nName=C\nExec=c\n');
    File('${system.path}/d.desktop')
        .writeAsStringSync('[Desktop Entry]\nType=Application\nName=D\nExec=d\nTryExec=no-such-program-xyz\n');

    final found = scanApplications(
      dirs: [user.path, system.path],
      environment: {'PATH': '/usr/bin', 'XDG_CURRENT_DESKTOP': 'KDE'},
    );
    expect({for (final e in found) e.id}, {'a.desktop', 'kde-c.desktop'});
  });

  test('finds icons in the theme closest to the wanted size', () {
    final dir = Directory.systemTemp.createTempSync('launcher-icons');
    addTearDown(() => dir.deleteSync(recursive: true));
    final icons = '${dir.path}/share/icons';
    void file(String path, [String contents = '']) =>
        File('$icons/$path')..createSync(recursive: true)..writeAsStringSync(contents);
    file('mytheme/index.theme', '''
[Icon Theme]
Name=Mine
Inherits=hicolor
Directories=apps/16,apps/48

[apps/16]
Size=16
Context=Applications
Type=Fixed

[apps/48]
Size=48
Context=Applications
Type=Fixed
''');
    file('mytheme/apps/16/kate.svg');
    file('mytheme/apps/48/kate.svg');
    file('hicolor/index.theme', '''
[Icon Theme]
Name=Hicolor
Directories=48x48/apps,scalable/apps

[48x48/apps]
Size=48
Context=Applications
Type=Threshold

[scalable/apps]
Size=128
MinSize=8
MaxSize=512
Context=Applications
Type=Scalable
''');
    file('hicolor/48x48/apps/krita.png');
    file('hicolor/scalable/apps/krita.svg');
    file('hicolor/48x48/apps/kate.png');
    Directory('${dir.path}/config').createSync();
    File('${dir.path}/config/kdeglobals').writeAsStringSync('[Icons]\nTheme=mytheme\n');

    final index = IconIndex(IconIndex.buildSync(environment: {
      'HOME': dir.path,
      'XDG_DATA_DIRS': '${dir.path}/share',
      'XDG_CONFIG_HOME': '${dir.path}/config',
    }));
    expect(index.lookup('kate'), '$icons/mytheme/apps/48/kate.svg');
    expect(index.lookup('krita'), '$icons/hicolor/48x48/apps/krita.png');
    expect(index.lookup('krita.png'), '$icons/hicolor/48x48/apps/krita.png');
    expect(index.lookup('nothing'), isNull);
  });

  group('calculator', () {
    test('evaluates arithmetic', () {
      expect(evaluate('1+2*3'), 7);
      expect(evaluate('(1+2)*3'), 9);
      expect(evaluate('2^10'), 1024);
      expect(evaluate('-2^2'), -4);
      expect(evaluate('sqrt(16) + 1'), 5);
      expect(formatNumber(evaluate('1/3')!), '0.333333333333');
      expect(formatNumber(evaluate('0.1+0.2')!), '0.3');
    });

    test('ignores things that are not sums', () {
      expect(evaluate('firefox'), isNull);
      expect(evaluate('42'), isNull);
      expect(evaluate('2+'), isNull);
      expect(evaluate('kate 2'), isNull);
    });
  });
}
