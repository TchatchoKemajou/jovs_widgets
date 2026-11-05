# jovs_widgets

Shared Flutter widgets for the Jov's apps (`jovsPro`, `jovsClient`, `jovsAdmin`, future ones).

Consumed via path dependency from each app's `pubspec.yaml`:

```yaml
dependencies:
  jovs_widgets:
    path: ../jovs_widgets
```

This repo must sit as a sibling of the Flutter apps on disk — both on your
machine and in CI. If you clone a Flutter app alone, run
`git clone <jovs_widgets url> ../jovs_widgets` next to it before
`flutter pub get`.

## Widgets

### `JovsAddressPicker`

Introduced for the international pilot (T4, nov 2026). Produces a `JovsAddress`
from a Leaflet/OpenStreetMap map with GPS, Nominatim search and four editable
fields (country, city, neighborhood, landmark). Works anywhere — Montréal,
Paris, Yaoundé — without needing a postal address.

Minimum usage:

```dart
JovsAddressPicker(
  onChanged: (addr) => setState(() => _address = addr),
)
```

See `lib/src/address_picker/` for the model and the Nominatim client.

## Translation keys

The widget calls `.tr()` on these keys — the host app must provide them in
its `assets/translations/{fr,en}.json`:

- `address_picker.search_hint`
- `address_picker.use_my_location`
- `address_picker.country`
- `address_picker.city`
- `address_picker.neighborhood`
- `address_picker.landmark`
- `address_picker.landmark_hint`
- `address_picker.confirm`
- `address_picker.permission_denied`
- `address_picker.osm_attribution`

## Host app requirements

Location permissions must be declared by each consuming app:

- **Android** (`android/app/src/main/AndroidManifest.xml`):
  `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>`
- **iOS** (`ios/Runner/Info.plist`): `NSLocationWhenInUseUsageDescription`
  with a human-readable reason.
