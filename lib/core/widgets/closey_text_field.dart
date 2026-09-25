import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/closey_colors.dart';
import '../theme/closey_motion.dart';
import '../theme/closey_spacing.dart';
import '../theme/closey_typography.dart';

/// Labelled text field with focus-aware chrome.
///
/// The Expo `Input` had *no* focus state — the border never changed, so there
/// was no way to tell which field was active. This one:
/// * animates the label + border to the brand colour on focus,
/// * shows an optional character counter that turns danger near the limit,
/// * reports errors inline instead of via `Alert.alert`,
/// * and exposes a `TextInputAction` chain for proper keyboard navigation.
class CloseyTextField extends StatefulWidget {
  const CloseyTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.sentences,
    this.autofillHints,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool enabled;
  final TextCapitalization textCapitalization;
  final List<String>? autofillHints;

  @override
  State<CloseyTextField> createState() => _CloseyTextFieldState();
}

class _CloseyTextFieldState extends State<CloseyTextField> {
  late final FocusNode _focus = FocusNode();
  bool _showSecret = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final focused = _focus.hasFocus;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    final borderColor = hasError
        ? c.danger
        : focused
        ? c.brand
        : c.border;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Gap.xs, bottom: Gap.sm),
          child: AnimatedDefaultTextStyle(
            duration: context.motion(Motion.quick),
            style: CloseyTypography.eyebrow.copyWith(
              color: hasError
                  ? c.danger
                  : focused
                  ? c.brandText
                  : c.textTertiary,
            ),
            child: Text(widget.label.toUpperCase()),
          ),
        ),
        AnimatedContainer(
          duration: context.motion(Motion.quick),
          curve: Motion.standard,
          decoration: BoxDecoration(
            borderRadius: Radii.allMd,
            boxShadow: focused && !hasError
                ? [
                    BoxShadow(
                      color: c.brand.withValues(alpha: 0.14),
                      blurRadius: 0,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            obscureText: widget.obscureText && !_showSecret,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            minLines: widget.minLines,
            maxLength: widget.maxLength,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            textCapitalization: widget.textCapitalization,
            autofillHints: widget.autofillHints,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: context.text.bodyLarge,
            cursorColor: c.brand,
            cursorRadius: const Radius.circular(Radii.full),
            buildCounter:
                (_, {required currentLength, required isFocused, maxLength}) =>
                    null,
            decoration: InputDecoration(
              hintText: widget.hint,
              isDense: false,
              filled: true,
              fillColor: widget.enabled ? c.surface : c.surfaceSunken,
              counterText: '',
              prefixIcon: widget.prefixIcon != null
                  ? Icon(widget.prefixIcon, size: 19, color: c.textTertiary)
                  : null,
              suffixIcon: widget.obscureText
                  ? IconButton(
                      onPressed: () =>
                          setState(() => _showSecret = !_showSecret),
                      icon: Icon(
                        _showSecret
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 19,
                        color: c.textTertiary,
                      ),
                      tooltip: _showSecret ? 'Hide password' : 'Show password',
                    )
                  : widget.suffix,
              enabledBorder: OutlineInputBorder(
                borderRadius: Radii.allMd,
                borderSide: BorderSide(color: borderColor, width: Strokes.thin),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: Radii.allMd,
                borderSide: BorderSide(
                  color: hasError ? c.danger : c.brand,
                  width: Strokes.thick,
                ),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: Radii.allMd,
                borderSide: BorderSide(color: c.border),
              ),
            ),
          ),
        ),
        if (hasError || widget.helper != null)
          Padding(
            padding: const EdgeInsets.only(left: Gap.xs, top: Gap.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasError)
                  Padding(
                    padding: const EdgeInsets.only(right: Gap.xs + 2, top: 1),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 14,
                      color: c.danger,
                    ),
                  ),
                Expanded(
                  child: Text(
                    hasError ? widget.errorText! : widget.helper!,
                    style: context.text.bodySmall?.copyWith(
                      color: hasError ? c.danger : c.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A single-line OTP / code entry field set.
class CloseyCodeField extends StatelessWidget {
  const CloseyCodeField({
    super.key,
    required this.controller,
    this.length = 6,
    this.onCompleted,
    this.errorText,
  });

  final TextEditingController controller;
  final int length;
  final ValueChanged<String>? onCompleted;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: length,
          autofocus: true,
          onChanged: (v) {
            if (v.length == length) onCompleted?.call(v);
          },
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: CloseyTypography.numeric.copyWith(
            fontSize: 30,
            letterSpacing: 14,
            color: c.textPrimary,
          ),
          cursorColor: c.brand,
          decoration: InputDecoration(
            counterText: '',
            hintText: '•' * length,
            hintStyle: TextStyle(
              fontSize: 30,
              letterSpacing: 14,
              color: c.textTertiary,
            ),
            filled: true,
            fillColor: c.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: Radii.allMd,
              borderSide: BorderSide(
                color: errorText != null ? c.danger : c.border,
                width: Strokes.thin,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: Radii.allMd,
              borderSide: BorderSide(color: c.brand, width: Strokes.thick),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm, left: Gap.xs),
            child: Text(
              errorText!,
              style: context.text.bodySmall?.copyWith(color: c.danger),
            ),
          ),
      ],
    );
  }
}
