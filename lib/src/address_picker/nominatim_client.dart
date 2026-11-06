import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'jovs_address.dart';

/// Thin client for the public Nominatim (OpenStreetMap) endpoints.
///
/// Nominatim has a 1 req/s per IP rate limit and requires a descriptive
/// User-Agent — the callers debounce typing to ~500ms so a human fills a form
/// well under that budget. If the server is slow or down, methods return
/// `null`/empty: the UI must stay usable with manual field editing.
class NominatimClient {
  NominatimClient({
    http.Client? httpClient,
    String userAgent = 'jovs-app/1.0 (contact@jovs.ca)',
  })  : _http = httpClient ?? http.Client(),
        _userAgent = userAgent;

  static const String _base = 'https://nominatim.openstreetmap.org';

  final http.Client _http;
  final String _userAgent;

  Map<String, String> _headers(String? acceptLanguage) => {
        'User-Agent': _userAgent,
        if (acceptLanguage != null) 'Accept-Language': acceptLanguage,
      };

  /// Full-text search. Returns up to [limit] candidates.
  ///
  /// [countryCode] (ISO-3166 alpha-2) biaise fortement les résultats vers
  /// ce pays. Sans ça, Nominatim peut rendre des adresses en Belgique quand
  /// on cherche un quartier québécois homonyme. Le picker passe le pays
  /// détecté par geo-IP pour que la recherche reste précise localement.
  Future<List<NominatimPlace>> search(
    String query, {
    String? acceptLanguage,
    String? countryCode,
    int limit = 5,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (query.trim().length < 3) return const [];
    final params = <String, String>{
      'q': query,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '$limit',
    };
    final cc = countryCode?.trim().toLowerCase();
    if (cc != null && cc.length == 2) {
      params['countrycodes'] = cc;
    }
    final uri = Uri.parse(_base).replace(
      path: '/search',
      queryParameters: params,
    );
    try {
      final res = await _http.get(uri, headers: _headers(acceptLanguage)).timeout(timeout);
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body);
      if (body is! List) return const [];
      return body.whereType<Map<String, dynamic>>().map(NominatimPlace.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Reverse geocoding: pin → structured address.
  Future<JovsAddress?> reverse(
    LatLng point, {
    String? acceptLanguage,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final uri = Uri.parse(_base).replace(
      path: '/reverse',
      queryParameters: {
        'lat': '${point.latitude}',
        'lon': '${point.longitude}',
        'format': 'jsonv2',
        'addressdetails': '1',
        // zoom 18 = niveau bâtiment. En 16 Nominatim retourne la rue mais
        // rarement le house_number ; l'utilisateur voit "Rue Létourneau"
        // au lieu de "36B rue Létourneau" et pense que le reverse rate.
        'zoom': '18',
      },
    );
    try {
      final res = await _http.get(uri, headers: _headers(acceptLanguage)).timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) return null;
      return _mapAddress(point, body);
    } catch (_) {
      return null;
    }
  }

  static JovsAddress _mapAddress(LatLng point, Map<String, dynamic> body) {
    final addr = body['address'] is Map<String, dynamic>
        ? body['address'] as Map<String, dynamic>
        : const <String, dynamic>{};
    // Nominatim returns different keys per place type — we try the common ones.
    final city = _firstNonEmpty([
      addr['city'],
      addr['town'],
      addr['village'],
      addr['hamlet'],
      addr['municipality'],
      addr['county'],
    ]);
    final neighborhood = _firstNonEmpty([
      addr['neighbourhood'],
      addr['suburb'],
      addr['quarter'],
      addr['district'],
      addr['city_district'],
    ]);
    final street = () {
      final road = addr['road'] as String?;
      final houseNumber = addr['house_number'] as String?;
      if (road == null || road.isEmpty) return null;
      return houseNumber != null && houseNumber.isNotEmpty
          ? '$houseNumber $road'
          : road;
    }();
    return JovsAddress(
      latitude: point.latitude,
      longitude: point.longitude,
      countryCode: (addr['country_code'] as String?)?.toUpperCase(),
      country: addr['country'] as String?,
      city: city,
      neighborhood: neighborhood,
      street: street,
      postalCode: addr['postcode'] as String?,
      raw: body,
    );
  }

  static String? _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  void dispose() => _http.close();
}

/// A single Nominatim search hit, used by the autocomplete list.
class NominatimPlace {
  const NominatimPlace({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  factory NominatimPlace.fromJson(Map<String, dynamic> j) {
    return NominatimPlace(
      displayName: (j['display_name'] as String?) ?? '',
      latitude: double.tryParse('${j['lat']}') ?? 0,
      longitude: double.tryParse('${j['lon']}') ?? 0,
    );
  }

  final String displayName;
  final double latitude;
  final double longitude;

  LatLng get latLng => LatLng(latitude, longitude);
}
