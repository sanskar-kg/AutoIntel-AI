import 'package:autointel_ai/core/money.dart';
import 'package:autointel_ai/core/reg_no.dart';
import 'package:autointel_ai/l10n/strings.g.dart';
import 'package:autointel_ai/l10n/strings_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('registration numbers', () {
    test('normalizes case, spaces and hyphens', () {
      expect(normalizeRegNo('mh 12-ab 1234'), 'MH12AB1234');
    });

    test('accepts common plate formats', () {
      for (final ok in [
        'MH12AB1234',
        'DL1CAB1234',
        'KA03M1234',
        'MH 12 AB 1234',
        '22BH1234AA',
        'GJ05CD0001',
      ]) {
        expect(isValidRegNo(ok), isTrue, reason: ok);
      }
    });

    test('rejects malformed input', () {
      for (final bad in [
        '',
        'ABC',
        '1234',
        'MH12AB',
        'MH12AB12345',
        '12MH1234AB',
        'MH-AB-1234',
      ]) {
        expect(isValidRegNo(bad), isFalse, reason: bad);
      }
    });

    test('masks the middle', () {
      expect(maskRegNo('MH12AB1234'), 'MH12****34');
    });
  });

  group('money', () {
    test('formats whole rupees without decimals and keeps paise otherwise', () {
      expect(formatPaise(200), '₹2');
      expect(formatPaise(10000), '₹100');
      expect(formatPaise(250), '₹2.50');
      expect(formatPaise(125000), '₹1,250');
    });
  });

  group('strings runtime', () {
    test('substitutes positional placeholders in any order', () {
      expect(formatTemplate('%2\$s then %1\$s', ['a', 'b']), 'b then a');
      expect(formatTemplate('100%% of %1\$d', [3]), '100% of 3');
    });

    test('plural categories', () {
      expect(pluralCategory('en', 1), 'one');
      expect(pluralCategory('en', 2), 'other');
      expect(pluralCategory('hi', 0), 'one');
    });

    test('generated accessors resolve and fall back to English', () {
      final s = S(
        const Locale('xx'),
      ); // unsupported locale falls back to English
      expect(s.navHome, 'Home');
      expect(s.lookupButtonSearch('₹2'), 'Search for ₹2');
      expect(s.historyCount(1), '1 search');
      expect(s.historyCount(5), '5 searches');
      expect(s.homeTileRcTitle, 'Vehicle Details');
      expect(s.homeTilePhoneSubtitle, contains("owner's"));
    });
  });
}
