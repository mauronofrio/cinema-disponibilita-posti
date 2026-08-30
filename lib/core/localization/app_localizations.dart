import 'package:flutter/material.dart';

/// Hand-written localization (no ARB/codegen - the string set is small
/// enough that a plain lookup table is simpler to read and maintain).
/// English is the default; Italian is offered because the app's whole
/// subject (The Space Cinema) is Italian.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('it')];

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  /// Sessions off the widget tree (e.g. exceptions thrown from the API
  /// client, which has no `BuildContext`) can't call [of]. The delegate
  /// updates this every time the effective locale changes, so those call
  /// sites have a best-effort fallback instead of being stuck in one
  /// language forever.
  static AppLocalizations current = AppLocalizations(const Locale('en'));

  static const _strings = <String, Map<String, String>>{
    'pickCinemaTitle': {
      'en': 'Choose your cinema',
      'it': 'Scegli il tuo cinema',
    },
    'searchHint': {
      'en': 'Search city or cinema…',
      'it': 'Cerca città o cinema…',
    },
    'noCinemaFound': {'en': 'No cinema found', 'it': 'Nessun cinema trovato'},
    'cinemaListLoadError': {
      'en': 'Couldn\'t load the cinema list.',
      'it': 'Impossibile caricare la lista cinema.',
    },
    'daysLoadError': {'en': 'Days error:', 'it': 'Errore giorni:'},
    'filmsLoadError': {'en': 'Films error:', 'it': 'Errore film:'},
    'genericError': {'en': 'Error:', 'it': 'Errore:'},
    'noShowingsAvailable': {
      'en': 'No showings available.',
      'it': 'Nessuno spettacolo disponibile.',
    },
    'noFilmsForDay': {
      'en': 'No films scheduled for this day.',
      'it': 'Nessun film in programmazione per questo giorno.',
    },
    'today': {'en': 'Today', 'it': 'Oggi'},
    'tomorrow': {'en': 'Tomorrow', 'it': 'Domani'},
    'soldOut': {'en': 'sold out', 'it': 'esaurito'},
    'seatsLoadError': {
      'en': 'Couldn\'t load the seats.',
      'it': 'Impossibile caricare i posti.',
    },
    'noShowingsForFilmThatDay': {
      'en': 'This film has no showings that day.',
      'it': 'Nessuno spettacolo di questo film in quel giorno.',
    },
    'seatStatusAvailable': {'en': 'Available', 'it': 'Disponibile'},
    'seatStatusOccupied': {'en': 'Occupied', 'it': 'Occupato'},
    'seatStatusReserved': {'en': 'Reserved', 'it': 'Riservato'},
    'seatStatusSpecial': {'en': 'Special', 'it': 'Speciale'},
    'seatStatusAccessibility': {'en': 'Accessibility', 'it': 'Accessibilità'},
    'seatStatusUnavailable': {'en': 'Not available', 'it': 'Non disponibile'},
    'occupiedSummary': {'en': 'Occupied', 'it': 'Occupati'},
    'screenIndicator': {'en': 'SCREEN', 'it': 'SCHERMO'},
    'buyTickets': {
      'en': 'Buy tickets on the official site',
      'it': 'Compra i biglietti sul sito ufficiale',
    },
    'getDirections': {'en': 'Get directions', 'it': 'Indicazioni stradali'},
    'openMapsTitle': {'en': 'Open Maps?', 'it': 'Aprire Maps?'},
    'cancel': {'en': 'Cancel', 'it': 'Annulla'},
    'retry': {'en': 'Retry', 'it': 'Riprova'},
    'open': {'en': 'Open', 'it': 'Apri'},
    'settingsTitle': {'en': 'Settings', 'it': 'Impostazioni'},
    'yourCinemas': {'en': 'Your cinemas', 'it': 'I tuoi cinema'},
    'noCinemaSelected': {
      'en': 'No cinema selected',
      'it': 'Nessun cinema selezionato',
    },
    'addCinema': {'en': 'Add a cinema', 'it': 'Aggiungi un cinema'},
    'removeCinema': {'en': 'Remove', 'it': 'Rimuovi'},
    'removeCinemaTitle': {
      'en': 'Remove this cinema?',
      'it': 'Rimuovere questo cinema?',
    },
    'active': {'en': 'Active', 'it': 'Attivo'},
    'language': {'en': 'Language', 'it': 'Lingua'},
    'languageAuto': {'en': 'Auto', 'it': 'Auto'},
    'linkOpenError': {
      'en': 'Couldn\'t open the link on this device.',
      'it': 'Impossibile aprire il link su questo dispositivo.',
    },
    // Kept deliberately chain-neutral: this app covers 226 cinemas across
    // four different operators/platforms, so naming any one of them (as an
    // earlier version did, when The Space was the only supported chain)
    // would be wrong for the large majority of them. Mirrors the README's
    // own disclaimer.
    'disclaimer': {
      'en':
          'Unofficial app, with no affiliation to any of the cinemas or chains it lists. '
          'It doesn\'t handle accounts, payments, tickets or bookings: it only shows the programme '
          'and seat availability, data that is already publicly visible on each cinema\'s own '
          'official site.',
      'it':
          'App non ufficiale, senza alcun legame con i cinema o le catene elencate. '
          'Non gestisce account, pagamenti, biglietti o prenotazioni: mostra soltanto '
          'programmazione e disponibilità posti, dati già pubblicamente visibili sui siti '
          'ufficiali di ciascun cinema.',
    },
    'connectionError': {
      'en':
          'No internet connection available. Check your network and try again.',
      'it':
          'Connessione a Internet non disponibile. Controlla la rete e riprova.',
    },
    'requestFailedError': {
      'en': 'Couldn\'t complete the request. Please try again later.',
      'it': 'Impossibile completare la richiesta. Riprova più tardi.',
    },
    'updateAvailableTitle': {
      'en': 'Update available',
      'it': 'Aggiornamento disponibile',
    },
    'updateLater': {'en': 'Later', 'it': 'Più tardi'},
    'updateDownload': {'en': 'Download', 'it': 'Scarica'},
    'sourceCode': {'en': 'Source code on GitHub', 'it': 'Codice sorgente su GitHub'},
    'filmInfoTooltip': {
      'en': 'Description and trailer',
      'it': 'Descrizione e trailer',
    },
    'filmInfoUnavailable': {
      'en': 'Description not available.',
      'it': 'Descrizione non disponibile.',
    },
    'watchTrailer': {'en': 'Watch trailer', 'it': 'Guarda il trailer'},
  };

  String _t(String key) =>
      _strings[key]?[locale.languageCode] ?? _strings[key]!['en']!;

  String get pickCinemaTitle => _t('pickCinemaTitle');
  String get searchHint => _t('searchHint');
  String get noCinemaFound => _t('noCinemaFound');
  String get cinemaListLoadError => _t('cinemaListLoadError');
  String get daysLoadError => _t('daysLoadError');
  String get filmsLoadError => _t('filmsLoadError');
  String get genericError => _t('genericError');
  String get noShowingsAvailable => _t('noShowingsAvailable');
  String get noFilmsForDay => _t('noFilmsForDay');
  String get today => _t('today');
  String get tomorrow => _t('tomorrow');
  String get soldOut => _t('soldOut');
  String get seatsLoadError => _t('seatsLoadError');
  String get noShowingsForFilmThatDay => _t('noShowingsForFilmThatDay');
  String get seatStatusAvailable => _t('seatStatusAvailable');
  String get seatStatusOccupied => _t('seatStatusOccupied');
  String get seatStatusReserved => _t('seatStatusReserved');
  String get seatStatusSpecial => _t('seatStatusSpecial');
  String get seatStatusAccessibility => _t('seatStatusAccessibility');
  String get seatStatusUnavailable => _t('seatStatusUnavailable');
  String get occupiedSummary => _t('occupiedSummary');
  String get screenIndicator => _t('screenIndicator');
  String get buyTickets => _t('buyTickets');
  String get getDirections => _t('getDirections');
  String get openMapsTitle => _t('openMapsTitle');
  String get cancel => _t('cancel');
  String get retry => _t('retry');
  String get open => _t('open');

  /// "Get directions to the {cinemaName} cinema?" - kept as a method rather
  /// than a plain getter since it needs to interpolate the name. Leads with
  /// "cinema"/"cinema" explicitly: every cinema is just named after its own
  /// town (e.g. "Casamassima Bari"), so the bare name alone reads as a place
  /// name rather than clearly "the cinema in that town".
  String openMapsMessage(String cinemaName) {
    return locale.languageCode == 'it'
        ? 'Vuoi aprire Google Maps per le indicazioni verso il cinema $cinemaName?'
        : 'Open Google Maps for directions to the $cinemaName cinema?';
  }

  String get settingsTitle => _t('settingsTitle');
  String get yourCinemas => _t('yourCinemas');
  String get noCinemaSelected => _t('noCinemaSelected');
  String get addCinema => _t('addCinema');
  String get removeCinema => _t('removeCinema');
  String get removeCinemaTitle => _t('removeCinemaTitle');

  /// "Remove {name} from your cinemas?" - a method rather than a getter
  /// since it interpolates the name, same as [openMapsMessage].
  String removeCinemaMessage(String cinemaName) {
    return locale.languageCode == 'it'
        ? 'Vuoi rimuovere $cinemaName dai tuoi cinema?'
        : 'Remove $cinemaName from your cinemas?';
  }
  String get active => _t('active');
  String get language => _t('language');
  String get languageAuto => _t('languageAuto');
  String get linkOpenError => _t('linkOpenError');
  String get disclaimer => _t('disclaimer');
  String get connectionError => _t('connectionError');
  String get requestFailedError => _t('requestFailedError');
  String get updateAvailableTitle => _t('updateAvailableTitle');
  String get updateLater => _t('updateLater');
  String get updateDownload => _t('updateDownload');
  String get sourceCode => _t('sourceCode');
  String get filmInfoTooltip => _t('filmInfoTooltip');
  String get filmInfoUnavailable => _t('filmInfoUnavailable');
  String get watchTrailer => _t('watchTrailer');

  /// "Version {latest} is available (installed: {current})." - method rather
  /// than getter since it interpolates both versions.
  String updateAvailableMessage(String latest, String current) {
    return locale.languageCode == 'it'
        ? 'È disponibile la versione $latest (installata: $current). '
              'Il download si apre nel browser.'
        : 'Version $latest is available (installed: $current). '
              'The download opens in your browser.';
  }

  /// `DateFormat` locale identifier matching this app's locale (e.g. for day
  /// labels like "Wed 9 Jul" / "mer 9 lug").
  String get dateFormatLocale =>
      locale.languageCode == 'it' ? 'it_IT' : 'en_US';
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (l) => l.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final resolved = AppLocalizations(locale);
    AppLocalizations.current = resolved;
    return resolved;
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
