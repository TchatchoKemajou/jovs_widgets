import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'jovs_address.dart';
import 'nominatim_client.dart';

/// Universal address picker for Jov's apps.
///
/// Combines three complementary inputs so the same screen works in Montreal,
/// Paris, Yaoundé or on a remote village with no mailbox address:
///
/// 1. A search box at the top (Nominatim/OSM autocomplete, debounced).
/// 2. A full-screen embeddable Leaflet/OSM map with a pin at the current
///    guess. Tapping the map moves the pin.
/// 3. Four editable fields below the map: country (read-only once chosen),
///    city, neighborhood and a free-form landmark. The city is mandatory, the
///    rest is nullable — enough structure for every pilot country.
///
/// The widget never blocks on network: if Nominatim is slow or down the user
/// can still type everything manually.
///
/// Translation keys used (all fall back to English hard-coded strings if the
/// host app doesn't provide them):
///   address_picker.search_hint
///   address_picker.use_my_location
///   address_picker.country
///   address_picker.city
///   address_picker.neighborhood
///   address_picker.landmark
///   address_picker.landmark_hint
///   address_picker.confirm
///   address_picker.permission_denied
///   address_picker.osm_attribution
class JovsAddressPicker extends StatefulWidget {
  const JovsAddressPicker({
    super.key,
    this.initial,
    this.initialCenter,
    this.onChanged,
    this.onConfirm,
    this.locale,
    this.showConfirmButton = true,
    this.height = 420,
  });

  /// If the caller already has an address (edit mode), start the pin there.
  final JovsAddress? initial;

  /// Fallback center when no GPS permission and no [initial]. Montréal.
  final LatLng? initialCenter;

  /// Called whenever the pin moves or a field is edited.
  final ValueChanged<JovsAddress>? onChanged;

  /// Optional confirmation button handler (fired by the built-in Confirm
  /// button — hide it by setting [showConfirmButton] to false).
  final ValueChanged<JovsAddress>? onConfirm;

  /// Locale passed to Nominatim via Accept-Language so results come back in
  /// the right language where OSM has translations. Defaults to the host
  /// app's EasyLocalization locale.
  final String? locale;

  final bool showConfirmButton;

  final double height;

  @override
  State<JovsAddressPicker> createState() => _JovsAddressPickerState();
}

class _JovsAddressPickerState extends State<JovsAddressPicker> {
  static const LatLng _montreal = LatLng(45.5017, -73.5673);

  final MapController _mapController = MapController();
  final NominatimClient _nominatim = NominatimClient();

  late TextEditingController _searchCtrl;
  late TextEditingController _cityCtrl;
  late TextEditingController _neighborhoodCtrl;
  late TextEditingController _landmarkCtrl;

  LatLng _pin = _montreal;
  JovsAddress? _current;
  bool _loadingReverse = false;
  Timer? _searchDebounce;
  List<NominatimPlace> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    final init = widget.initial;
    _cityCtrl = TextEditingController(text: init?.city ?? '');
    _neighborhoodCtrl = TextEditingController(text: init?.neighborhood ?? '');
    _landmarkCtrl = TextEditingController(text: init?.landmark ?? '');
    _pin = init != null
        ? LatLng(init.latitude, init.longitude)
        : (widget.initialCenter ?? _montreal);
    _current = init;
    // Center the map on first frame once the widget is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _mapController.move(_pin, 13));
    if (init == null) {
      _tryUseCurrentLocation(silent: true);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _cityCtrl.dispose();
    _neighborhoodCtrl.dispose();
    _landmarkCtrl.dispose();
    _nominatim.dispose();
    super.dispose();
  }

  String get _acceptLanguage {
    final l = widget.locale ?? context.locale.toString();
    return l;
  }

  void _emit() {
    if (_current == null) return;
    widget.onChanged?.call(_current!);
  }

  void _onFieldChanged() {
    final c = _current;
    if (c == null) return;
    _current = c.copyWith(
      city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      neighborhood: _neighborhoodCtrl.text.trim().isEmpty ? null : _neighborhoodCtrl.text.trim(),
      landmark: _landmarkCtrl.text.trim().isEmpty ? null : _landmarkCtrl.text.trim(),
    );
    _emit();
  }

  Future<void> _movePinAndReverse(LatLng p) async {
    setState(() {
      _pin = p;
      _loadingReverse = true;
    });
    _mapController.move(p, _mapController.camera.zoom);
    final result = await _nominatim.reverse(p, acceptLanguage: _acceptLanguage);
    if (!mounted) return;
    setState(() {
      _loadingReverse = false;
      if (result != null) {
        // Preserve user-edited landmark across reverse lookups.
        final preservedLandmark = _landmarkCtrl.text.trim().isEmpty
            ? null
            : _landmarkCtrl.text.trim();
        _current = result.copyWith(landmark: preservedLandmark);
        _cityCtrl.text = result.city ?? '';
        _neighborhoodCtrl.text = result.neighborhood ?? '';
      } else {
        // Keep the pin but let the user fill the form manually.
        _current = (_current ??
                JovsAddress(latitude: p.latitude, longitude: p.longitude))
            .copyWith(latitude: p.latitude, longitude: p.longitude);
      }
    });
    _emit();
  }

  Future<void> _tryUseCurrentLocation({bool silent = false}) async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        if (!silent) _snack('address_picker.permission_denied'.tr());
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!silent) _snack('address_picker.permission_denied'.tr());
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _movePinAndReverse(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      if (!silent) _snack('address_picker.permission_denied'.tr());
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await _nominatim.search(text, acceptLanguage: _acceptLanguage);
      if (!mounted) return;
      setState(() => _suggestions = results);
    });
  }

  Future<void> _pickSuggestion(NominatimPlace p) async {
    _searchCtrl.text = p.displayName;
    setState(() => _suggestions = const []);
    await _movePinAndReverse(p.latLng);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchBar(theme),
        const SizedBox(height: 8),
        SizedBox(height: widget.height, child: _buildMap(theme)),
        const SizedBox(height: 12),
        _buildFieldsCard(theme),
        if (widget.showConfirmButton) ...[
          const SizedBox(height: 12),
          _buildConfirmButton(theme),
        ],
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Stack(
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'address_picker.search_hint'.tr(),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Positioned(
            top: 56,
            left: 0,
            right: 0,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _suggestions
                    .map((s) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined, size: 20),
                          title: Text(s.displayName,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => _pickSuggestion(s),
                        ))
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMap(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pin,
              initialZoom: 13,
              onTap: (_, point) => _movePinAndReverse(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'ca.jovs.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pin,
                    width: 42,
                    height: 42,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_pin,
                        size: 42, color: Color(0xFFFC9501)),
                  ),
                ],
              ),
            ],
          ),
          if (_loadingReverse)
            const Positioned(
              top: 12,
              right: 12,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Positioned(
            bottom: 12,
            left: 12,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
              onPressed: () => _tryUseCurrentLocation(),
              icon: const Icon(Icons.my_location, size: 18),
              label: Text('address_picker.use_my_location'.tr()),
            ),
          ),
          Positioned(
            bottom: 4,
            right: 8,
            child: Text(
              'address_picker.osm_attribution'.tr(),
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldsCard(ThemeData theme) {
    final country = _current?.country;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, size: 18, color: Colors.black45),
              const SizedBox(width: 8),
              Text(
                '${'address_picker.country'.tr()}: ${country ?? "—"}',
                style: const TextStyle(color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cityCtrl,
            onChanged: (_) => _onFieldChanged(),
            decoration: InputDecoration(
              labelText: 'address_picker.city'.tr(),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _neighborhoodCtrl,
            onChanged: (_) => _onFieldChanged(),
            decoration: InputDecoration(
              labelText: 'address_picker.neighborhood'.tr(),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _landmarkCtrl,
            onChanged: (_) => _onFieldChanged(),
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'address_picker.landmark'.tr(),
              hintText: 'address_picker.landmark_hint'.tr(),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFC9501),
          foregroundColor: Colors.white,
        ),
        onPressed: _current == null
            ? null
            : () => widget.onConfirm?.call(_current!),
        child: Text('address_picker.confirm'.tr()),
      ),
    );
  }
}
