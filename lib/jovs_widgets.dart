/// Shared Jov's widgets.
///
/// Exports the [JovsAddressPicker] used across jovsPro, jovsClient and
/// jovsAdmin for l'ouverture internationale. Depuis le refactor 2026-11-14 :
/// carte retirée, dropdowns stricts Pays / Région / Ville via
/// `custom_country_state_city` (package maison de Franck), autocomplete
/// Nominatim conservé pour pré-remplir, GPS en bouton visible.
library jovs_widgets;

export 'src/address_picker/jovs_address.dart';
export 'src/address_picker/jovs_address_picker.dart';
export 'src/geo/geo_client.dart';
export 'src/money/money.dart';
export 'src/phone/jovs_phone_field.dart';
