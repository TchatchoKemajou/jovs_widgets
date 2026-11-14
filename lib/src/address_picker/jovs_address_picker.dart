import 'dart:async';
import 'dart:convert';

import 'package:custom_country_state_city/custom_country_state_city.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'jovs_address.dart';
import 'nominatim_client.dart';

/// Universal address picker for Jov's apps.
///
/// Refactor 2026-11-14 (Franck) : carte retirée, remplacée par dropdowns
/// stricts Pays / Région / Ville via le package `custom_country_state_city`.
/// Nominatim reste pour l'autocomplete et le reverse geocode. GPS en bouton
/// visible dès l'ouverture. Flow :
///
/// 1. Au mount, le pays est préremplis via [initialCountryCode] (déduit par
///    l'app depuis l'indicatif +XXX du phone du user — le pays est toujours
///    connu puisqu'on exige phone à l'inscription).
/// 2. Bouton « Détecter ma position » déclenche GPS → reverse Nominatim →
///    pré-remplit les 3 dropdowns + rue + lat/lng.
/// 3. Recherche libre (Nominatim) → sélection → même traitement.
/// 4. Saisie 100 % manuelle via les 3 dropdowns est toujours possible.
///
/// Translation keys used (fallback hard-codés si non fournis) :
///   address_picker.search_hint
///   address_picker.use_my_location
///   address_picker.country / state / city
///   address_picker.street / street_hint (+ variantes _ca/_fr/_cm)
///   address_picker.landmark / landmark_hint
///   address_picker.confirm
///   address_picker.permission_denied
///   address_picker.no_results
///   address_picker.manual_hint
class JovsAddressPicker extends StatefulWidget {
  const JovsAddressPicker({
    super.key,
    this.initial,
    this.onChanged,
    this.onConfirm,
    this.locale,
    this.initialCountryCode,
    this.showConfirmButton = true,
    @Deprecated('Carte retirée 2026-11-14 — paramètre no-op, à supprimer')
    this.initialCenter,
    @Deprecated('Remplacé par initialCountryCode — même sémantique')
    String? biasCountry,
    @Deprecated('Carte retirée 2026-11-14 — paramètre no-op, à supprimer')
    double? height,
  }) : _legacyBiasCountry = biasCountry;

  /// If the caller already has an address (edit mode), start the form there.
  final JovsAddress? initial;

  /// Called whenever a field changes.
  final ValueChanged<JovsAddress>? onChanged;

  /// Optional confirmation button handler (hide it with [showConfirmButton]).
  final ValueChanged<JovsAddress>? onConfirm;

  /// Locale passed to Nominatim via Accept-Language.
  final String? locale;

  /// ISO-3166 alpha-2 (`CA`, `FR`, `CM`). Pré-remplit le dropdown pays au
  /// mount (host app passe le pays déduit de l'indicatif phone). Biaise
  /// aussi la recherche Nominatim.
  final String? initialCountryCode;

  final bool showConfirmButton;

  /// @deprecated no-op depuis le retrait de la carte (2026-11-14).
  final dynamic initialCenter;

  final String? _legacyBiasCountry;

  /// Lit `initialCountryCode` et fallback sur l'ancien `biasCountry`.
  String? get _effectiveCountryCode =>
      initialCountryCode ?? _legacyBiasCountry;

  @override
  State<JovsAddressPicker> createState() => _JovsAddressPickerState();
}

class _JovsAddressPickerState extends State<JovsAddressPicker> {
  final NominatimClient _nominatim = NominatimClient();

  late TextEditingController _searchCtrl;
  late TextEditingController _streetCtrl;
  late TextEditingController _landmarkCtrl;
  // Controllers pour le picker du package (textes affichés à l'écran).
  late TextEditingController _countryCtrl;
  late TextEditingController _stateCtrl;
  late TextEditingController _cityCtrl;

  JovsAddress? _current;
  bool _loadingGps = false;
  Timer? _searchDebounce;
  List<NominatimPlace> _suggestions = const [];
  bool _searchReturnedEmpty = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _searchCtrl = TextEditingController();
    _streetCtrl = TextEditingController(text: init?.street ?? '');
    _landmarkCtrl = TextEditingController(text: init?.landmark ?? '');
    _countryCtrl = TextEditingController(text: init?.country ?? '');
    _stateCtrl = TextEditingController(text: init?.province ?? '');
    _cityCtrl = TextEditingController(text: init?.city ?? '');
    _current = init ??
        JovsAddress(countryCode: widget._effectiveCountryCode?.toUpperCase());
    // Préremplit le nom du pays dans le dropdown si on a juste un code ISO
    // (host app passe +237 → "CM"). On lit le JSON de pays du package pour
    // retrouver "Cameroun" / "Cameroon" selon la locale.
    if (init?.country == null && widget._effectiveCountryCode != null) {
      _prefillCountryName(widget._effectiveCountryCode!);
    }
  }

  Future<void> _prefillCountryName(String isoCode) async {
    try {
      final locale = (widget.locale ?? 'en').toLowerCase();
      final lang = locale.startsWith('fr') ? 'fr' : 'en';
      final json = await rootBundle.loadString(
        'packages/custom_country_state_city/assets/$lang/country.json',
      );
      final list = jsonDecode(json) as List;
      final match = list.cast<Map<String, dynamic>>().firstWhere(
            (c) =>
                (c['sortname'] as String?)?.toUpperCase() ==
                isoCode.toUpperCase(),
            orElse: () => const {},
          );
      final name = match['name'] as String?;
      if (name != null && name.isNotEmpty && mounted) {
        setState(() {
          _countryCtrl.text = name;
          _current = (_current ?? const JovsAddress()).copyWith(
            countryCode: isoCode.toUpperCase(),
            country: name,
          );
        });
      }
    } catch (_) {
      // Pas grave si on n'arrive pas à préremplir — user choisira.
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _streetCtrl.dispose();
    _landmarkCtrl.dispose();
    _countryCtrl.dispose();
    _stateCtrl.dispose();
    _cityCtrl.dispose();
    _nominatim.dispose();
    super.dispose();
  }

  String get _acceptLanguage {
    return widget.locale ?? context.locale.toString();
  }

  String? get _activeCountryCode {
    return (_current?.countryCode ?? widget._effectiveCountryCode)
        ?.toUpperCase();
  }

  /// Un champ rue adaptatif au pays (CA/FR/CM ont des conventions très
  /// différentes — rue+numéro vs carrefour vs quartier). Si le pays n'est
  /// pas encore sélectionné, libellé générique.
  String get _streetLabel {
    switch (_activeCountryCode) {
      case 'CA':
        return 'address_picker.street_ca'.tr();
      case 'FR':
        return 'address_picker.street_fr'.tr();
      case 'CM':
        return 'address_picker.street_cm'.tr();
      default:
        return 'address_picker.street'.tr();
    }
  }

  String get _streetHint {
    switch (_activeCountryCode) {
      case 'CA':
        return 'address_picker.street_hint_ca'.tr();
      case 'FR':
        return 'address_picker.street_hint_fr'.tr();
      case 'CM':
        return 'address_picker.street_hint_cm'.tr();
      default:
        return 'address_picker.street_hint'.tr();
    }
  }

  void _emit() {
    if (_current == null) return;
    widget.onChanged?.call(_current!);
  }

  void _syncFromFields() {
    _current = (_current ?? const JovsAddress()).copyWith(
      street: _streetCtrl.text.trim().isEmpty ? null : _streetCtrl.text.trim(),
      landmark: _landmarkCtrl.text.trim().isEmpty
          ? null
          : _landmarkCtrl.text.trim(),
      country: _countryCtrl.text.trim().isEmpty ? null : _countryCtrl.text.trim(),
      province: _stateCtrl.text.trim().isEmpty ? null : _stateCtrl.text.trim(),
      city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
    );
    _emit();
  }

  Future<void> _applyReverse(JovsAddress reverse) async {
    // Fallback intelligent pour le champ "Adresse" dans les pays sans
    // adressage formel (Cameroun, parts d'Afrique) : Nominatim retourne
    // rarement un `road` mais presque toujours un `suburb`/`neighbourhood`.
    final streetLike = reverse.street ?? reverse.neighborhood ?? '';
    setState(() {
      _streetCtrl.text = streetLike;
      _countryCtrl.text = reverse.country ?? _countryCtrl.text;
      _stateCtrl.text = reverse.province ?? _stateCtrl.text;
      _cityCtrl.text = reverse.city ?? _cityCtrl.text;
      // Préserve landmark édité par l'utilisateur.
      final preservedLandmark = _landmarkCtrl.text.trim().isEmpty
          ? null
          : _landmarkCtrl.text.trim();
      _current = reverse.copyWith(landmark: preservedLandmark);
    });
    _emit();
  }

  Future<void> _tryUseCurrentLocation({bool silent = false}) async {
    setState(() => _loadingGps = true);
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
      final reverse = await _nominatim.reverse(
        LatLng(pos.latitude, pos.longitude),
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) return;
      if (reverse != null) {
        await _applyReverse(reverse);
      } else {
        // Reverse a échoué mais on garde quand même le lat/lng.
        setState(() {
          _current = (_current ?? const JovsAddress()).copyWith(
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
        });
        _emit();
      }
    } catch (_) {
      if (!silent) _snack('address_picker.permission_denied'.tr());
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    if (text.trim().length < 3) {
      setState(() {
        _suggestions = const [];
        _searchReturnedEmpty = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await _nominatim.search(
        text,
        acceptLanguage: _acceptLanguage,
        countryCode: _activeCountryCode,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _searchReturnedEmpty = results.isEmpty;
      });
    });
  }

  Future<void> _pickSuggestion(NominatimPlace p) async {
    _searchCtrl.text = p.displayName;
    setState(() {
      _suggestions = const [];
      _searchReturnedEmpty = false;
    });
    final reverse = await _nominatim.reverse(
      p.latLng,
      acceptLanguage: _acceptLanguage,
    );
    if (!mounted) return;
    if (reverse != null) {
      await _applyReverse(reverse);
    } else {
      setState(() {
        _current = (_current ?? const JovsAddress()).copyWith(
          latitude: p.latLng.latitude,
          longitude: p.latLng.longitude,
        );
      });
      _emit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchBar(theme),
        const SizedBox(height: 8),
        _buildGpsButton(theme),
        const SizedBox(height: 16),
        _buildCountryCityCard(theme),
        const SizedBox(height: 14),
        _buildStreetField(theme),
        const SizedBox(height: 14),
        _buildLandmarkField(theme),
        if (widget.showConfirmButton) ...[
          const SizedBox(height: 20),
          _buildConfirmButton(theme),
        ],
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Material(
              elevation: 2,
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
          )
        else if (_searchReturnedEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'address_picker.no_results'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGpsButton(ThemeData theme) {
    return OutlinedButton.icon(
      onPressed: _loadingGps ? null : () => _tryUseCurrentLocation(),
      icon: _loadingGps
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.my_location, size: 18),
      label: Text('address_picker.use_my_location'.tr()),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildCountryCityCard(ThemeData theme) {
    // Le picker du package gère lui-même son dialog de sélection avec
    // search intégrée. On lui donne les 3 TextEditingController ; ses
    // onCountryChanged/onStateChanged/onCityChanged nous rendent les
    // sélections et on les pousse dans _current via _syncFromFields.
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: CustomCountryStateCityPicker(
        country: _countryCtrl,
        state: _stateCtrl,
        city: _cityCtrl,
        locale: _acceptLanguage.startsWith('fr') ? 'fr' : 'en',
        spacing: 8,
        textFieldDecoration: InputDecoration(
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        fieldHintText: FieldHintText(
          countryHintText: 'address_picker.country'.tr(),
          stateHintText: 'address_picker.state'.tr(),
          cityHintText: 'address_picker.city'.tr(),
        ),
        dialogTitle: DialogTitle(
          countryDialogTitle: 'address_picker.country'.tr(),
          stateDialogTitle: 'address_picker.state'.tr(),
          cityDialogTitle: 'address_picker.city'.tr(),
        ),
        onCountryChanged: (c) {
          _current = (_current ?? const JovsAddress()).copyWith(
            countryCode: c.sortName,
            country: c.name,
          );
          _syncFromFields();
        },
        onStateChanged: (_) => _syncFromFields(),
        onCityChanged: (_) => _syncFromFields(),
      ),
    );
  }

  Widget _buildStreetField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _streetCtrl,
          onChanged: (_) => _syncFromFields(),
          decoration: InputDecoration(
            labelText: _streetLabel,
            hintText: _streetHint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(
            'address_picker.manual_hint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.55),
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandmarkField(ThemeData theme) {
    return TextField(
      controller: _landmarkCtrl,
      onChanged: (_) => _syncFromFields(),
      maxLines: 2,
      decoration: InputDecoration(
        labelText: 'address_picker.landmark'.tr(),
        hintText: 'address_picker.landmark_hint'.tr(),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildConfirmButton(ThemeData theme) {
    final canConfirm = (_cityCtrl.text.trim().isNotEmpty) &&
        (_countryCtrl.text.trim().isNotEmpty);
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFC9501),
          foregroundColor: Colors.white,
        ),
        onPressed: canConfirm && _current != null
            ? () => widget.onConfirm?.call(_current!)
            : null,
        child: Text('address_picker.confirm'.tr()),
      ),
    );
  }
}
