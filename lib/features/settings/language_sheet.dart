import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme.dart';
import '../../l10n/strings.g.dart';

/// Language names in their own script. These are data, not UI copy, so they are
/// intentionally not in strings.xml (a language is always named in itself).
const _nativeNames = <String, String>{
  'en': 'English',
  'hi': 'हिन्दी',
  'mr': 'मराठी',
  'gu': 'ગુજરાતી',
  'bn': 'বাংলা',
  'ta': 'தமிழ்',
  'te': 'తెలుగు',
  'kn': 'ಕನ್ನಡ',
};

/// Only offer language switching once at least one translation has been added.
bool get hasMultipleLanguages => supportedLanguageTags.length > 1;

String nativeLanguageName(String tag) =>
    _nativeNames[tag.split('_').first] ?? tag;

Future<void> showLanguageSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => const _LanguageSheet(),
    );

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
                  for (final tag in supportedLanguageTags)
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

/// Globe + language code, as in MIC's dashboard header.
class LanguageButton extends ConsumerWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasMultipleLanguages) return const SizedBox.shrink();
    ref.watch(languageProvider);
    final code = Localizations.localeOf(context).languageCode.toUpperCase();
    return Tooltip(
      message: S.of(context).a11yLanguageButton,
      child: TextButton.icon(
        onPressed: () => showLanguageSheet(context),
        icon: const Icon(Icons.language, size: 22, color: AppColors.navy),
        label: Text(
          code,
          style: sora(12, weight: FontWeight.w700, color: AppColors.navy),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(48, 48),
        ),
      ),
    );
  }
}
