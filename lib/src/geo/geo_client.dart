import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Lightweight client for horusApi's `GET /api/v1/geo/country`. Lets a host
/// app pre-seed the [JovsAddressPicker] on the user's own country instead of
/// defaulting to Montreal — a Cameroonian pro signing up no longer has to
/// pan the map across the Atlantic to start pinning.
///
/// Call once at boot of a flow that needs it; the backend caches by IP for
/// 24h so a repeat call is cheap.
class JovsGeoClient {
  JovsGeoClient({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// horusApi origin, e.g. 'https://dev-api.jovs.ca'.
  final String baseUrl;
  final http.Client _http;

  /// Hits `/api/v1/geo/country`. Returns the ISO-3166 code + suggested
  /// language, or `null` on any error so the caller can fall back to its
  /// own default (CA / Montreal) without surfacing an error to the user.
  Future<JovsGeoResult?> detect({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final res = await _http
          .get(Uri.parse('$baseUrl/api/v1/geo/country'))
          .timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      final country = (body['country'] as String?)?.toUpperCase();
      final language = (body['language'] as String?)?.toLowerCase();
      if (country == null || country.length != 2) return null;
      return JovsGeoResult(country: country, language: language ?? 'en');
    } catch (_) {
      return null;
    }
  }

  void dispose() => _http.close();

  /// Capital (or largest city) of a country as a map-friendly seed. Covers
  /// the pilot's expected markets. Unknown codes fall back to Montreal, which
  /// matches [JovsAddressPicker]'s own historical default.
  ///
  /// We don't need a 250-country table — the picker's search bar handles
  /// anywhere not pre-seeded. The list exists to pre-center on the top
  /// markets the pilot is actually targeting.
  static LatLng cityCenterFor(String? countryCode) {
    final c = (countryCode ?? '').toUpperCase();
    final seed = _capitals[c];
    return seed ?? const LatLng(45.5017, -73.5673); // Montreal default
  }

  static const Map<String, LatLng> _capitals = {
    'CA': LatLng(45.5017, -73.5673),   // Montréal (biggest JOV's market)
    'US': LatLng(40.7128, -74.0060),   // New York
    'FR': LatLng(48.8566, 2.3522),     // Paris
    'BE': LatLng(50.8503, 4.3517),     // Brussels
    'CH': LatLng(46.9480, 7.4474),     // Bern
    'LU': LatLng(49.6116, 6.1319),     // Luxembourg
    'GB': LatLng(51.5074, -0.1278),    // London
    'DE': LatLng(52.5200, 13.4050),    // Berlin
    'ES': LatLng(40.4168, -3.7038),    // Madrid
    'IT': LatLng(41.9028, 12.4964),    // Rome
    'NL': LatLng(52.3676, 4.9041),     // Amsterdam
    'PT': LatLng(38.7169, -9.1399),    // Lisbon
    'CM': LatLng(3.8480, 11.5021),     // Yaoundé
    'CI': LatLng(5.3600, -4.0083),     // Abidjan
    'SN': LatLng(14.6928, -17.4467),   // Dakar
    'MA': LatLng(33.9716, -6.8498),    // Rabat
    'DZ': LatLng(36.7538, 3.0588),     // Algiers
    'TN': LatLng(36.8065, 10.1815),    // Tunis
    'BF': LatLng(12.3714, -1.5197),    // Ouagadougou
    'ML': LatLng(12.6392, -8.0029),    // Bamako
    'NG': LatLng(9.0820, 8.6753),      // Abuja
    'GH': LatLng(5.6037, -0.1870),     // Accra
    'KE': LatLng(-1.2921, 36.8219),    // Nairobi
    'ZA': LatLng(-26.2041, 28.0473),   // Johannesburg
    'EG': LatLng(30.0444, 31.2357),    // Cairo
    'MX': LatLng(19.4326, -99.1332),   // Mexico City
    'BR': LatLng(-15.7939, -47.8828),  // Brasília
    'AR': LatLng(-34.6037, -58.3816),  // Buenos Aires
    'CN': LatLng(39.9042, 116.4074),   // Beijing
    'JP': LatLng(35.6762, 139.6503),   // Tokyo
    'IN': LatLng(28.6139, 77.2090),    // New Delhi
    'ID': LatLng(-6.2088, 106.8456),   // Jakarta
    'AU': LatLng(-33.8688, 151.2093),  // Sydney
    'AE': LatLng(25.2048, 55.2708),    // Dubai
    'SA': LatLng(24.7136, 46.6753),    // Riyadh
  };
}

class JovsGeoResult {
  const JovsGeoResult({required this.country, required this.language});

  /// ISO-3166 alpha-2 country code.
  final String country;

  /// 'fr' or 'en' — host app's suggested UI language.
  final String language;
}
