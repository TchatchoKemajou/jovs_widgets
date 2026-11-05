import 'dart:ui' show Locale;

import 'package:intl/intl.dart';

/// Price/money formatting across the Jov's Flutter apps.
///
/// One entry point, [Money.format]: pass the amount, the salon's [currencyCode]
/// (ISO-4217 — `CAD`, `EUR`, `XAF`, …) and optionally the user's locale, and
/// the result reads naturally for any pilot market:
///
/// ```dart
/// Money.format(25.00, currencyCode: 'CAD', locale: Locale('fr', 'CA'));
/// // => '25,00 $'
///
/// Money.format(25.00, currencyCode: 'EUR', locale: Locale('fr'));
/// // => '25,00 €'
///
/// Money.format(1500, currencyCode: 'XAF', locale: Locale('fr'));
/// // => '1 500 FCFA'
/// ```
///
/// Pricing is **display-only** — no FX conversion is ever performed. The salon
/// stores raw prices in its own currency; the client sees them in the same
/// currency formatted for their language. A Quebec client browsing a Paris
/// salon sees euros with French-Quebec spacing; that is intentional.
class Money {
  Money._();

  /// Format [amount] in [currencyCode].
  ///
  /// [locale] defaults to the Dart default locale (set by EasyLocalization or
  /// whichever i18n package the host app uses). [decimals] defaults to the
  /// currency's conventional digits (2 for USD/CAD/EUR, 0 for XAF/XOF/JPY).
  /// Pass [decimals] explicitly to force a count (e.g. rounded totals).
  static String format(
    num amount, {
    required String currencyCode,
    Locale? locale,
    int? decimals,
  }) {
    final code = (currencyCode.isEmpty ? 'CAD' : currencyCode).toUpperCase();
    final tag = locale != null ? _localeTag(locale) : null;
    final digits = decimals ?? _defaultDigits(code);
    final fmt = NumberFormat.currency(
      locale: tag,
      name: code,
      decimalDigits: digits,
    );
    return fmt.format(amount).trim();
  }

  /// Just the currency symbol ("$", "€", "FCFA") without an amount —
  /// used for standalone chips/labels. Falls back to [currencyCode] when
  /// the symbol is unknown to `intl`.
  static String symbol(String currencyCode, {Locale? locale}) {
    final code = (currencyCode.isEmpty ? 'CAD' : currencyCode).toUpperCase();
    final tag = locale != null ? _localeTag(locale) : null;
    final fmt = NumberFormat.simpleCurrency(locale: tag, name: code);
    return fmt.currencySymbol;
  }

  static String _localeTag(Locale l) {
    final country = l.countryCode;
    return country == null || country.isEmpty ? l.languageCode : '${l.languageCode}_$country';
  }

  /// ISO-4217 convention — most currencies have 2 fractional digits, a few
  /// major ones have 0 (CFA franc, Japanese yen, …) or 3 (dinars).
  static int _defaultDigits(String code) {
    switch (code) {
      case 'XAF':
      case 'XOF':
      case 'JPY':
      case 'KRW':
      case 'CLP':
      case 'VND':
        return 0;
      case 'BHD':
      case 'JOD':
      case 'KWD':
      case 'OMR':
      case 'TND':
        return 3;
      default:
        return 2;
    }
  }
}
