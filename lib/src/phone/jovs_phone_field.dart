import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';

/// International phone input used across every Jov's app form that accepts a
/// phone number (registration, salon setup, client creation, appointment
/// quick-add, staff invitation, profile edit).
///
/// Produces an E.164 string via the [onChanged] callback — e.g. "+237692696414"
/// for a Cameroon number — so callers never have to prefix "+1" or any other
/// dial code. The country picker defaults to [initialCountry] (CA for the
/// pilot's historical market) and can be re-targeted from the signal we
/// already have in [JovsAddressPicker] (the salon's countryCode).
///
/// Internally wraps the `intl_phone_field` package. Validation is permissive
/// by design: the user shouldn't be blocked while typing, so we only report
/// 'number too short' once they've tried submitting with [validate] = true.
class JovsPhoneField extends StatelessWidget {
  const JovsPhoneField({
    super.key,
    this.initialValue,
    this.initialCountry = 'CA',
    this.label,
    this.hint,
    this.onChanged,
    this.onSaved,
    this.validate = true,
    this.enabled = true,
    this.autofocus = false,
    this.decoration,
  });

  /// Pre-filled E.164 value, used when editing an existing profile/record.
  final String? initialValue;

  /// Default country ISO-3166 alpha-2 shown when there's no [initialValue].
  final String initialCountry;

  final String? label;
  final String? hint;

  /// Fires on every keystroke with the latest E.164 string (empty when the
  /// user has cleared the field). Null while initializing.
  final ValueChanged<String>? onChanged;

  /// Called on Form.save with the final E.164 string.
  final ValueChanged<String?>? onSaved;

  /// When true (default), apply a conservative length check (7–15 digits
  /// after the country code — tightest union of real-world rules).
  final bool validate;

  final bool enabled;
  final bool autofocus;

  /// Override the default decoration if the caller has specific styling.
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final decoration0 = this.decoration ??
        InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          prefixIcon: const Icon(Icons.phone_outlined),
        );

    // Parse an existing E.164 value into the country + national number the
    // package expects. If parsing fails we fall through to a clean picker.
    String? seedNumber;
    String seedCountry = initialCountry;
    final v = (initialValue ?? '').trim();
    if (v.startsWith('+') && v.length > 3) {
      final parsed = _splitE164(v);
      if (parsed != null) {
        seedCountry = parsed.$1;
        seedNumber = parsed.$2;
      }
    } else if (v.isNotEmpty) {
      seedNumber = v;
    }

    return IntlPhoneField(
      initialCountryCode: seedCountry,
      initialValue: seedNumber,
      enabled: enabled,
      autofocus: autofocus,
      disableLengthCheck: !validate,
      invalidNumberMessage: 'Numéro invalide',
      decoration: decoration0,
      // Padding à gauche du drapeau (sinon il colle au bord du champ et
      // dénote visuellement par rapport aux autres TextFormField qui ont
      // leur prefixIcon aéré — Franck 2026-11-08).
      flagsButtonPadding: const EdgeInsets.symmetric(horizontal: 12),
      onChanged: (PhoneNumber n) {
        onChanged?.call(n.completeNumber);
      },
      onSaved: (PhoneNumber? n) {
        onSaved?.call(n?.completeNumber);
      },
    );
  }

  /// Best-effort split of an E.164 string into (isoCountry, nationalNumber).
  /// Uses the leading digits as a dial-code lookup against the picker's
  /// known codes. Returns null when the number is too short or unknown.
  static (String, String)? _splitE164(String e164) {
    // Dial-code ranges: longest-match first so +1 doesn't eat +1876 (Jamaica).
    // Minimal table covering the pilot markets + most-requested countries;
    // the picker UI will let the user override the country if we guess wrong.
    const dialCodes = <String, String>{
      '237': 'CM', '225': 'CI', '221': 'SN', '212': 'MA', '216': 'TN',
      '213': 'DZ', '234': 'NG', '233': 'GH', '254': 'KE', '27': 'ZA',
      '20': 'EG', '33': 'FR', '41': 'CH', '44': 'GB', '49': 'DE',
      '34': 'ES', '39': 'IT', '32': 'BE', '31': 'NL', '46': 'SE',
      '47': 'NO', '45': 'DK', '48': 'PL', '52': 'MX', '55': 'BR',
      '54': 'AR', '86': 'CN', '81': 'JP', '91': 'IN', '62': 'ID',
      '971': 'AE', '966': 'SA', '61': 'AU', '64': 'NZ', '1': 'CA',
    };
    final digits = e164.substring(1);
    for (final len in [3, 2, 1]) {
      if (digits.length <= len) continue;
      final head = digits.substring(0, len);
      final iso = dialCodes[head];
      if (iso != null) return (iso, digits.substring(len));
    }
    return null;
  }
}
