/// Address value produced by [JovsAddressPicker].
///
/// Mirrors the backend Salon address model (horusApi):
/// * `latitude` + `longitude` are the pin coordinates (required — the whole
///   point of the picker is to produce a usable GPS pin, including in places
///   without a precise postal address).
/// * `countryCode` is the ISO-3166-1 alpha-2 code (`CA`, `FR`, `CM`...).
/// * `country`, `city`, `neighborhood`, `street`, `postalCode` are the
///   human-readable fields returned by reverse geocoding and editable by the
///   user. All nullable except `city` (the minimum structured info).
/// * `landmark` is free-form user text ("in front of the pharmacy on the
///   corner") for places where even reverse geocoding fails to disambiguate.
/// * `raw` is the untouched Nominatim payload — kept for debugging and for
///   features that may later want extra fields (county, state, …).
class JovsAddress {
  const JovsAddress({
    required this.latitude,
    required this.longitude,
    this.countryCode,
    this.country,
    this.city,
    this.neighborhood,
    this.street,
    this.postalCode,
    this.landmark,
    this.raw,
  });

  final double latitude;
  final double longitude;
  final String? countryCode;
  final String? country;
  final String? city;
  final String? neighborhood;
  final String? street;
  final String? postalCode;
  final String? landmark;
  final Map<String, dynamic>? raw;

  JovsAddress copyWith({
    double? latitude,
    double? longitude,
    String? countryCode,
    String? country,
    String? city,
    String? neighborhood,
    String? street,
    String? postalCode,
    String? landmark,
    Map<String, dynamic>? raw,
  }) {
    return JovsAddress(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      countryCode: countryCode ?? this.countryCode,
      country: country ?? this.country,
      city: city ?? this.city,
      neighborhood: neighborhood ?? this.neighborhood,
      street: street ?? this.street,
      postalCode: postalCode ?? this.postalCode,
      landmark: landmark ?? this.landmark,
      raw: raw ?? this.raw,
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'countryCode': countryCode,
        'country': country,
        'city': city,
        'neighborhood': neighborhood,
        'address': street,
        'postalCode': postalCode,
        'landmark': landmark,
      };
}
