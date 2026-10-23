// Generates lib/l10n/strings.g.dart from Android string resources.
//
//   dart run tool/gen_strings.dart            # regenerate
//   dart run tool/gen_strings.dart --check    # CI: fail if the generated file is stale
//   dart run tool/gen_strings.dart --strict   # CI: also fail on untranslated keys
//
// Source of truth: android/app/src/main/res/values*/strings.xml
// (values/ is English; values-xx/ come from Play Console's translation service).
import 'dart:io';

import 'package:xml/xml.dart';

const _resDir = 'android/app/src/main/res';
const _outFile = 'lib/l10n/strings.g.dart';
const _placeholder = r'%(\d+)\$([sd])';

class _Entry {
  _Entry(this.name, this.value, {this.plurals});
  final String name;
  final String value; // empty for plurals
  final Map<String, String>? plurals;
  bool get isPlural => plurals != null;
}

void main(List<String> args) {
  final check = args.contains('--check');
  final strict = args.contains('--strict');
  final res = Directory(_resDir);
  if (!res.existsSync()) _fail('Missing $_resDir (run from the project root).');

  final tables = <String, Map<String, _Entry>>{};
  final nonTranslatable = <String>{};
  for (final dir in res.listSync().whereType<Directory>()) {
    final base = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final tag = _tagForFolder(base);
    if (tag == null) continue;
    final file = File('${dir.path}/strings.xml');
    if (!file.existsSync()) continue;
    tables[tag] = _parse(file, tag, nonTranslatable);
  }
  final en = tables['en'];
  if (en == null) _fail('values/strings.xml (English) is required.');

  final errors = <String>[];
  var missing = 0;
  for (final tag in tables.keys.where((t) => t != 'en')) {
    final table = tables[tag]!;
    table.removeWhere((k, _) => nonTranslatable.contains(k));
    for (final key in table.keys.toList()) {
      if (!en.containsKey(key)) {
        errors.add('[$tag] "$key" does not exist in English; remove it.');
        continue;
      }
      if (_signature(en[key]!) != _signature(table[key]!)) {
        errors.add(
          '[$tag] "$key" placeholders ${_signature(table[key]!)} do not match '
          'English ${_signature(en[key]!)}.',
        );
      }
    }
    for (final key in en.keys) {
      if (!nonTranslatable.contains(key) && !table.containsKey(key)) missing++;
    }
  }
  if (errors.isNotEmpty) _fail(errors.join('\n'));
  if (missing > 0) {
    stdout.writeln('Note: $missing untranslated entries fall back to English.');
    if (strict) exit(1);
  }

  final generated = _render(tables, en);
  final out = File(_outFile);
  if (check) {
    if (!out.existsSync() || out.readAsStringSync() != generated) {
      _fail('$_outFile is stale. Run: dart run tool/gen_strings.dart');
    }
    stdout.writeln('$_outFile is up to date.');
    return;
  }
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(generated);
  stdout.writeln(
    'Wrote $_outFile (${en.length} keys, ${tables.length} locales).',
  );
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}

String? _tagForFolder(String folder) {
  if (folder == 'values') return 'en';
  final m = RegExp(
    r'^values-([a-z]{2,3})(?:-r([A-Z]{2}))?$',
  ).firstMatch(folder);
  if (m == null) return null; // night, v21, sw600dp, ... are not locales
  return m.group(2) == null ? m.group(1)! : '${m.group(1)}_${m.group(2)}';
}

Map<String, _Entry> _parse(File file, String tag, Set<String> nonTranslatable) {
  final doc = XmlDocument.parse(file.readAsStringSync());
  final result = <String, _Entry>{};
  for (final el in doc.rootElement.childElements) {
    final name = el.getAttribute('name');
    if (name == null) continue;
    if (el.getAttribute('translatable') == 'false') {
      nonTranslatable.add(name);
    }
    if (el.name.local == 'string') {
      result[name] = _Entry(name, _unescape(el.innerText));
    } else if (el.name.local == 'plurals') {
      final items = <String, String>{};
      for (final item in el.findElements('item')) {
        items[item.getAttribute('quantity')!] = _unescape(item.innerText);
      }
      if (!items.containsKey('other')) {
        _fail('[$tag] plurals "$name" needs an "other" item.');
      }
      result[name] = _Entry(name, '', plurals: items);
    }
  }
  return result;
}

/// Android resource escaping: \' \" \n \t \\ \@ \? \uXXXX
String _unescape(String raw) {
  final text = raw.trim();
  final buf = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c != r'\' || i + 1 >= text.length) {
      buf.write(c);
      continue;
    }
    final n = text[++i];
    switch (n) {
      case 'n':
        buf.write('\n');
      case 't':
        buf.write('\t');
      case 'u':
        buf.writeCharCode(int.parse(text.substring(i + 1, i + 5), radix: 16));
        i += 4;
      default:
        buf.write(n);
    }
  }
  return buf.toString();
}

/// "1:s,2:d" — placeholder index/type signature used for validation and typing.
String _signature(_Entry e) {
  final texts = e.isPlural ? e.plurals!.values : [e.value];
  final types = <int, String>{};
  for (final t in texts) {
    for (final m in RegExp(_placeholder).allMatches(t)) {
      types[int.parse(m.group(1)!)] = m.group(2)!;
    }
  }
  final keys = types.keys.toList()..sort();
  return keys.map((k) => '$k:${types[k]}').join(',');
}

String _camel(String snake) {
  final parts = snake.split('_');
  return parts.first +
      parts
          .skip(1)
          .map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1))
          .join();
}

String _lit(String s) {
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t');
  return "'$escaped'";
}

String _render(
  Map<String, Map<String, _Entry>> tables,
  Map<String, _Entry> en,
) {
  final b = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('// Source: android/app/src/main/res/values*/strings.xml')
    ..writeln('// Regenerate with: dart run tool/gen_strings.dart')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln('// dart format off')
    ..writeln()
    ..writeln("import 'package:flutter/widgets.dart';")
    ..writeln()
    ..writeln("import 'strings_runtime.dart';")
    ..writeln();

  final tags = tables.keys.toList()
    ..sort(
      (a, b) => a == 'en'
          ? -1
          : b == 'en'
          ? 1
          : a.compareTo(b),
    );
  b.writeln(
    '/// Language tags that have a values-xx/strings.xml (English first).',
  );
  b.writeln(
    'const supportedLanguageTags = <String>[${tags.map(_lit).join(', ')}];',
  );
  b.writeln();
  b.writeln('const _strings = <String, Map<String, String>>{');
  for (final tag in tags) {
    b.writeln('  ${_lit(tag)}: {');
    for (final e in tables[tag]!.values.where((e) => !e.isPlural)) {
      b.writeln('    ${_lit(e.name)}: ${_lit(e.value)},');
    }
    b.writeln('  },');
  }
  b.writeln('};');
  b.writeln();
  b.writeln('const _plurals = <String, Map<String, Map<String, String>>>{');
  for (final tag in tags) {
    b.writeln('  ${_lit(tag)}: {');
    for (final e in tables[tag]!.values.where((e) => e.isPlural)) {
      b.writeln('    ${_lit(e.name)}: {');
      for (final q in e.plurals!.entries) {
        b.writeln('      ${_lit(q.key)}: ${_lit(q.value)},');
      }
      b.writeln('    },');
    }
    b.writeln('  },');
  }
  b.writeln('};');
  b.writeln();
  b.writeln(
    '/// Typed accessors for every string. Use `S.of(context).someKey`.',
  );
  b.writeln('class S extends StringsBase {');
  b.writeln('  S(Locale locale) : super(locale, _strings, _plurals);');
  b.writeln();
  b.writeln(
    '  static const LocalizationsDelegate<S> delegate = StringsDelegate<S>(',
  );
  b.writeln('    supportedLanguageTags,');
  b.writeln('    S.new,');
  b.writeln('  );');
  b.writeln();
  b.writeln(
    '  static S of(BuildContext context) => Localizations.of<S>(context, S)!;',
  );
  for (final e in en.values) {
    final name = _camel(e.name);
    final sig = _signature(e);
    final params = sig.isEmpty
        ? <MapEntry<int, String>>[]
        : sig.split(',').map((p) {
            final kv = p.split(':');
            return MapEntry(int.parse(kv[0]), kv[1]);
          }).toList();
    b.writeln();
    if (e.isPlural) {
      final extra = params.where((p) => p.key != 1).toList();
      final decl = [
        'int count',
        ...extra.map((p) => '${p.value == 'd' ? 'int' : 'String'} p${p.key}'),
      ];
      final args = ['count', ...extra.map((p) => 'p${p.key}')];
      b.writeln('  String $name(${decl.join(', ')}) =>');
      b.writeln('      plural(${_lit(e.name)}, count, [${args.join(', ')}]);');
    } else if (params.isEmpty) {
      b.writeln('  String get $name => text(${_lit(e.name)});');
    } else {
      final decl = params.map(
        (p) => '${p.value == 'd' ? 'int' : 'String'} p${p.key}',
      );
      final args = params.map((p) => 'p${p.key}');
      b.writeln('  String $name(${decl.join(', ')}) =>');
      b.writeln('      format(${_lit(e.name)}, [${args.join(', ')}]);');
    }
  }
  b.writeln('}');
  return b.toString();
}
