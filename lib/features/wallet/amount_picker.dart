import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.g.dart';

/// Preset chips + custom amount. Reports a valid amount in paise, or null when invalid/empty.
class AmountPicker extends StatefulWidget {
  const AmountPicker({
    super.key,
    required this.config,
    required this.onChanged,
    this.initialPaise,
  });

  final AppConfig config;
  final ValueChanged<int?> onChanged;
  final int? initialPaise;

  @override
  State<AmountPicker> createState() => _AmountPickerState();
}

class _AmountPickerState extends State<AmountPicker> {
  final _controller = TextEditingController();
  int? _presetPaise;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPaise ?? _defaultPreset();
    if (widget.config.presetsPaise.contains(initial)) {
      _presetPaise = initial;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onChanged(_presetPaise),
    );
  }

  int? _defaultPreset() {
    final presets = widget.config.presetsPaise;
    return presets.isEmpty ? null : presets[presets.length > 1 ? 1 : 0];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectPreset(int paise) {
    _controller.clear();
    setState(() {
      _presetPaise = paise;
      _error = null;
    });
    widget.onChanged(paise);
  }

  void _onCustomChanged(String text) {
    final s = S.of(context);
    final rupees = int.tryParse(text);
    int? valid;
    String? error;
    if (rupees != null) {
      final paise = rupeesToPaise(rupees);
      if (paise < widget.config.minRechargePaise) {
        error = s.amountErrorMin(formatPaise(widget.config.minRechargePaise));
      } else if (paise > widget.config.maxRechargePaise) {
        error = s.amountErrorMax(formatPaise(widget.config.maxRechargePaise));
      } else {
        valid = paise;
      }
    }
    setState(() {
      _presetPaise = null;
      _error = error;
    });
    widget.onChanged(valid);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < widget.config.presetsPaise.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _AmountChip(
                  label: formatPaise(widget.config.presetsPaise[i]),
                  selected: _presetPaise == widget.config.presetsPaise[i],
                  onTap: () => _selectPreset(widget.config.presetsPaise[i]),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onChanged: _onCustomChanged,
          style: sora(15, weight: FontWeight.w600, color: AppColors.navy),
          decoration: InputDecoration(
            labelText: s.amountCustomLabel,
            hintText: s.amountCustomHint(
              formatPaise(widget.config.minRechargePaise),
            ),
            prefixText: '₹ ',
            errorText: _error,
          ),
        ),
      ],
    );
  }
}

/// Equal-width preset button (four fit one row even inside a padded card).
class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? AppColors.blue : AppColors.chipBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: sora(
                  14,
                  weight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.navy,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
