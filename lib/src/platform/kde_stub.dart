/// Stand-ins for platforms without dart:io (the web): no environment, no
/// files, so the KDE scheme is never found.
library;

Map<String, String> platformEnvironment() => const {};

bool get platformIsLinux => false;

String? readFile(String path) => null;

Stream<void>? watchFile(String path) => null;
