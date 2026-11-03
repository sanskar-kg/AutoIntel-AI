import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/analytics.dart';
import '../../core/theme.dart';
import '../../l10n/strings.g.dart';

const _nativeNames = <String, String>{
  'en': 'English',
  'bn': 'বাংলা',
  'gu': 'ગુજરાતી',
  'hi': 'हिन्दी',
  'kn': 'ಕನ್ನಡ',
  'ml': 'മലയാളം',
  'mr': 'मराठी',
  'pa': 'ਪੰਜਾਬੀ',
  'ta': 'தமிழ்',
  'te': 'తెలుగు',
};

const _indianLanguageCodes = {
  'en',
  'bn',
  'gu',
  'hi',
  'kn',
  'ml',
  'mr',
  'pa',
  'ta',
  'te',
};

List<String> get supportedIndianLanguageTags {
  // Play Console supplies translated values-xx resources after processing the
  // uploaded bundle. Keep the picker stable even before those resources arrive;
  // Android falls back to English for a missing translation.
  supportedLanguageTags
    ..clear()
    ..addAll(_indianLanguageCodes);
  return _indianLanguageCodes.toList(growable: false);
}

bool get hasMultipleLanguages => true;

String nativeLanguageName(String tag) =>
    _nativeNames[tag.split('_').first] ?? 'English';

Future<void> showLanguageSheet(BuildContext context) async {
  await AppAnalytics.log('language_picker_viewed');
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => const _LanguageSheet(),
  );
}

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final selected = ref.watch(languageProvider);
    final selectedTag = selected?.languageCode;

    Widget option({
      required String label,
      required bool isSelected,
      required VoidCallback onTap,
    }) => ListTile(
      title: Text(
        label,
        style: sora(15, weight: FontWeight.w600, color: AppColors.navy),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.blue)
          : const Icon(Icons.circle_outlined, color: AppColors.border),
      onTap: () {
        unawaited(
          AppAnalytics.log(
            'language_option_tapped',
            parameters: {'language': label},
          ),
        );
        onTap();
        Navigator.pop(context);
      },
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                s.languageTitle,
                style: sora(20, weight: FontWeight.w700, color: AppColors.navy),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  option(
                    label: s.languageSystemDefault,
                    isSelected: selected == null,
                    onTap: () => ref.read(languageProvider.notifier).set(null),
                  ),
                  for (final tag in supportedIndianLanguageTags)
                    option(
                      label: nativeLanguageName(tag),
                      isSelected: selectedTag == tag.split('_').first,
                      onTap: () => ref
                          .read(languageProvider.notifier)
                          .set(Locale(tag.split('_').first)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LanguageButton extends ConsumerWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(languageProvider);
    final language = Localizations.localeOf(context).languageCode;
    return Tooltip(
      message: S.of(context).a11yLanguageButton,
      child: TextButton.icon(
        onPressed: () => showLanguageSheet(context),
        icon: const Icon(Icons.language, size: 22, color: AppColors.navy),
        label: Text(
          nativeLanguageName(language),
          style: sora(11, weight: FontWeight.w700, color: AppColors.navy),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(88, 48),
        ),
      ),
    );
  }
}
