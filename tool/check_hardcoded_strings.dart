// CI guard: user-facing text must come from strings.xml (via S.of(context)).
//
//   dart run tool/check_hardcoded_strings.dart
//
// Flags string literals passed directly to Text(...) or to common UI text parameters.
// Literals without any letters (symbols like '₹', '·') are ignored. Append
// `// l10n-ignore` to a line to exempt it (use sparingly, with a reason).
import 'dart:io';

final _patterns = <RegExp>[
  // Text('...') / Text("...") / const Text('...')
  RegExp(r'''\bText\(\s*(?:const\s+)?(['"])((?:\\.|(?!\1).)*)\1'''),
  // hintText: '...', labelText: '...', tooltip: '...', etc.
  RegExp(
    r'''\b(?:hintText|labelText|helperText|errorText|counterText|prefixText|suffixText|tooltip|semanticsLabel|semanticLabel|label|message|title|subtitle)\s*:\s*(?:const\s+)?(['"])((?:\\.|(?!\1).)*)\1''',
  ),
  RegExp(r'''SnackBar\(\s*content:\s*Text\(\s*(['"])((?:\\.|(?!\1).)*)\1'''),
];

void main() {
  final violations = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (path.startsWith('lib/l10n/')) continue; // generated + runtime
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('l10n-ignore')) continue;
      for (final p in _patterns) {
        for (final m in p.allMatches(line)) {
          final literal = m.group(2) ?? '';
          if (!RegExp(r'[A-Za-zऀ-෿]').hasMatch(literal)) continue;
          // Pure interpolation like '$x' has no words of its own.
          if (RegExp(r'^\$\w+$').hasMatch(literal)) continue;
          violations.add('$path:${i + 1}: hard-coded string "$literal"');
        }
      }
    }
  }
  if (violations.isEmpty) {
    stdout.writeln('No hard-coded UI strings found.');
    return;
  }
  stderr.writeln('Hard-coded UI strings found (move them to strings.xml):');
  violations.forEach(stderr.writeln);
  exit(1);
}
