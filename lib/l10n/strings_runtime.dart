import 'package:flutter/widgets.dart';

/// Looks strings up for one locale with fallback: full tag (pt_BR) → language (pt) → English.
/// The typed accessors live in the generated `strings.g.dart`.
class StringsBase {
  StringsBase(this.locale, this._strings, this._plurals);

  final Locale locale;
  final Map<String, Map<String, String>> _strings;
  final Map<String, Map<String, Map<String, String>>> _plurals;

  List<String> get _chain => [
    if (locale.countryCode != null)
      '${locale.languageCode}_${locale.countryCode}',
    locale.languageCode,
    'en',
  ];

  @protected
  String text(String key) {
    for (final tag in _chain) {
      final value = _strings[tag]?[key];
      if (value != null) return value;
    }
    return key; // never reached for generated keys; makes a bug visible
  }

  @protected
  String format(String key, List<Object> args) =>
      formatTemplate(text(key), args);

  @protected
  String plural(String key, int count, List<Object> args) {
    final category = pluralCategory(locale.languageCode, count);
    for (final tag in _chain) {
      final forms = _plurals[tag]?[key];
      if (forms != null) {
        return formatTemplate(forms[category] ?? forms['other']!, args);
      }
    }
    return key;
  }
}

/// Replaces positional `%1$s` / `%2$d` placeholders and `%%`.
String formatTemplate(String template, List<Object> args) {
  return template.replaceAllMapped(RegExp(r'%(\d+)\$[sd]|%%'), (m) {
    if (m.group(0) == '%%') return '%';
    final i = int.parse(m.group(1)!) - 1;
    return i >= 0 && i < args.length ? args[i].toString() : '';
  });
}

/// Minimal CLDR plural rules for the launch languages. Extend when adding a language
/// that needs more categories (e.g. ar, ru).
String pluralCategory(String language, int n) {
  switch (language) {
    case 'hi':
    case 'bn':
    case 'gu':
    case 'kn':
      return n == 0 || n == 1 ? 'one' : 'other';
    case 'ta':
    case 'te':
    case 'mr':
    case 'en':
    default:
      return n == 1 ? 'one' : 'other';
  }
}

class StringsDelegate<T> extends LocalizationsDelegate<T> {
  const StringsDelegate(this._languageTags, this._create);

  final List<String> _languageTags;
  final T Function(Locale) _create;

  @override
  bool isSupported(Locale locale) =>
      _languageTags.any((t) => t.split('_').first == locale.languageCode);

  @override
  Future<T> load(Locale locale) async => _create(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<T> old) => false;
}
