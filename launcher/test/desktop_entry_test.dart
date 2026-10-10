import 'package:flatkit_launcher/src/desktop_entry.dart';
import 'package:flutter_test/flutter_test.dart';

const firefox = r'''
[Desktop Entry]
Version=1.0
Name=Firefox
Name[de]=Firefox-Browser
GenericName=Web Browser
GenericName[de]=Webbrowser
Comment=Browse the World Wide Web
Keywords=Internet;WWW;Browser;Web\;Explorer;
Exec=firefox %u
Icon=firefox
Terminal=false
Type=Application
Categories=Network;WebBrowser;
Actions=new-window;new-private-window;missing;

[Desktop Action new-window]
Name=Open a New Window
Exec=firefox --new-window %u

[Desktop Action new-private-window]
Name=Open a New Private Window
Name[de]=Neues privates Fenster
Exec=firefox --private-window %u
''';

void main() {
  test('parses names, lists and actions', () {
    final e = DesktopEntry.parse(firefox, id: 'firefox.desktop')!;
    expect(e.name, 'Firefox');
    expect(e.genericName, 'Web Browser');
    expect(e.keywords, ['Internet', 'WWW', 'Browser', 'Web;Explorer']);
    expect(e.categories, ['Network', 'WebBrowser']);
    expect(e.actions.map((a) => a.id), ['new-window', 'new-private-window']);
    expect(e.hidden, isFalse);
  });

  test('picks translations by locale', () {
    final e = DesktopEntry.parse(firefox, id: 'firefox.desktop', locale: 'de_DE.UTF-8')!;
    expect(e.name, 'Firefox-Browser');
    expect(e.genericName, 'Webbrowser');
    expect(e.actions[1].name, 'Neues privates Fenster');
    expect(DesktopEntry.localeKeys('sr_RS.UTF-8@latin'), ['sr_RS@latin', 'sr_RS', 'sr@latin', 'sr']);
  });

  test('marks entries hidden from this desktop', () {
    String entry(String extra) => '[Desktop Entry]\nType=Application\nName=X\nExec=x\n$extra\n';
    expect(DesktopEntry.parse(entry('NoDisplay=true'), id: 'x')!.hidden, isTrue);
    expect(DesktopEntry.parse(entry('Hidden=true'), id: 'x')!.hidden, isTrue);
    expect(DesktopEntry.parse(entry('OnlyShowIn=GNOME;'), id: 'x')!.hidden, isTrue);
    expect(DesktopEntry.parse(entry('OnlyShowIn=GNOME;KDE;'), id: 'x')!.hidden, isFalse);
    expect(DesktopEntry.parse(entry('NotShowIn=KDE;'), id: 'x')!.hidden, isTrue);
    expect(DesktopEntry.parse(entry('NotShowIn=KDE;'), id: 'x', desktops: ['GNOME'])!.hidden,
        isFalse);
  });

  test('skips links and entries without a command', () {
    expect(DesktopEntry.parse('[Desktop Entry]\nType=Link\nName=X\nURL=http://x\n', id: 'x'), isNull);
    expect(DesktopEntry.parse('[Desktop Entry]\nType=Application\nName=X\n', id: 'x'), isNull);
    expect(DesktopEntry.parse('Name=X\nExec=x\n', id: 'x'), isNull);
  });

  group('Exec', () {
    test('drops file and URL codes', () {
      expect(parseExec('firefox %u'), ['firefox']);
      expect(parseExec('gimp-2.10 %U --foo'), ['gimp-2.10', '--foo']);
      expect(parseExec('app --file=%f'), ['app', '--file=']);
    });

    test('expands %i, %c, %k and %%', () {
      expect(parseExec('app %i', icon: 'app-icon'), ['app', '--icon', 'app-icon']);
      expect(parseExec('app %i'), ['app']);
      expect(parseExec('app --name %c', name: 'My App'), ['app', '--name', 'My App']);
      expect(parseExec('app %k', path: '/a/b.desktop'), ['app', '/a/b.desktop']);
      expect(parseExec('printf 100%%'), ['printf', '100%']);
    });

    test('honours quoting', () {
      expect(parseExec(r'"/opt/My App/run" --x "a \"b\" c"'), ['/opt/My App/run', '--x', 'a "b" c']);
      expect(parseExec(r'sh -c "echo \$HOME"'), ['sh', '-c', r'echo $HOME']);
      expect(parseExec('"unterminated'), isNull);
    });

    test('reads string escapes from the file first', () {
      final e = DesktopEntry.parse(
          '[Desktop Entry]\nType=Application\nName=X\nExec=sh -c "echo a\\\\\\\\b"\n',
          id: 'x')!;
      // File value `echo a\\\\b` unescapes to `echo a\\b`, which quoting
      // turns into `echo a\b`.
      expect(parseExec(e.exec), ['sh', '-c', r'echo a\b']);
    });
  });
}
