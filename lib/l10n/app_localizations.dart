import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appName.
  ///
  /// In es, this message translates to:
  /// **'Sonara'**
  String get appName;

  /// No description provided for @appearance.
  ///
  /// In es, this message translates to:
  /// **'Apariencia'**
  String get appearance;

  /// No description provided for @appearanceMode.
  ///
  /// In es, this message translates to:
  /// **'Modo de apariencia'**
  String get appearanceMode;

  /// No description provided for @system.
  ///
  /// In es, this message translates to:
  /// **'Sistema'**
  String get system;

  /// No description provided for @light.
  ///
  /// In es, this message translates to:
  /// **'Claro'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In es, this message translates to:
  /// **'Oscuro'**
  String get dark;

  /// No description provided for @accentColor.
  ///
  /// In es, this message translates to:
  /// **'Color de acento'**
  String get accentColor;

  /// No description provided for @colorSonara.
  ///
  /// In es, this message translates to:
  /// **'Sonara'**
  String get colorSonara;

  /// No description provided for @colorVioleta.
  ///
  /// In es, this message translates to:
  /// **'Violeta'**
  String get colorVioleta;

  /// No description provided for @colorEsmeralda.
  ///
  /// In es, this message translates to:
  /// **'Esmeralda'**
  String get colorEsmeralda;

  /// No description provided for @colorNaranja.
  ///
  /// In es, this message translates to:
  /// **'Naranja'**
  String get colorNaranja;

  /// No description provided for @colorRojo.
  ///
  /// In es, this message translates to:
  /// **'Rojo'**
  String get colorRojo;

  /// No description provided for @colorRosa.
  ///
  /// In es, this message translates to:
  /// **'Rosa'**
  String get colorRosa;

  /// No description provided for @colorCian.
  ///
  /// In es, this message translates to:
  /// **'Cian'**
  String get colorCian;

  /// No description provided for @playback.
  ///
  /// In es, this message translates to:
  /// **'Reproducción'**
  String get playback;

  /// No description provided for @crossfade.
  ///
  /// In es, this message translates to:
  /// **'Crossfade'**
  String get crossfade;

  /// No description provided for @disabled.
  ///
  /// In es, this message translates to:
  /// **'Desactivado'**
  String get disabled;

  /// No description provided for @seconds.
  ///
  /// In es, this message translates to:
  /// **'{count} segundos'**
  String seconds(Object count);

  /// No description provided for @secondsShort.
  ///
  /// In es, this message translates to:
  /// **'{count} s'**
  String secondsShort(Object count);

  /// No description provided for @application.
  ///
  /// In es, this message translates to:
  /// **'Aplicación'**
  String get application;

  /// No description provided for @language.
  ///
  /// In es, this message translates to:
  /// **'Idioma'**
  String get language;

  /// No description provided for @about.
  ///
  /// In es, this message translates to:
  /// **'Acerca de'**
  String get about;

  /// No description provided for @aboutSonara.
  ///
  /// In es, this message translates to:
  /// **'Información sobre Sonara'**
  String get aboutSonara;

  /// No description provided for @sourceCode.
  ///
  /// In es, this message translates to:
  /// **'Código fuente'**
  String get sourceCode;

  /// No description provided for @viewSonaraSource.
  ///
  /// In es, this message translates to:
  /// **'Ver el código de Sonara'**
  String get viewSonaraSource;

  /// No description provided for @close.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get close;

  /// No description provided for @aboutSonaraTitle.
  ///
  /// In es, this message translates to:
  /// **'Acerca de Sonara'**
  String get aboutSonaraTitle;

  /// No description provided for @aboutSonaraDescription.
  ///
  /// In es, this message translates to:
  /// **'Un reproductor de música rápido, potente y diseñado para tu día a día.'**
  String get aboutSonaraDescription;

  /// No description provided for @developer.
  ///
  /// In es, this message translates to:
  /// **'Desarrollador'**
  String get developer;

  /// No description provided for @helper.
  ///
  /// In es, this message translates to:
  /// **'Ayudante'**
  String get helper;

  /// No description provided for @openSourceLicenses.
  ///
  /// In es, this message translates to:
  /// **'Licencias de código abierto'**
  String get openSourceLicenses;

  /// No description provided for @privacyPolicy.
  ///
  /// In es, this message translates to:
  /// **'Política de privacidad'**
  String get privacyPolicy;

  /// No description provided for @support.
  ///
  /// In es, this message translates to:
  /// **'Soporte'**
  String get support;

  /// No description provided for @allRightsReserved.
  ///
  /// In es, this message translates to:
  /// **'Todos los derechos reservados.'**
  String get allRightsReserved;

  /// No description provided for @version.
  ///
  /// In es, this message translates to:
  /// **'Versión {version}'**
  String version(Object version);

  /// No description provided for @home.
  ///
  /// In es, this message translates to:
  /// **'Inicio'**
  String get home;

  /// No description provided for @library.
  ///
  /// In es, this message translates to:
  /// **'Biblioteca'**
  String get library;

  /// No description provided for @search.
  ///
  /// In es, this message translates to:
  /// **'Buscar'**
  String get search;

  /// No description provided for @settings.
  ///
  /// In es, this message translates to:
  /// **'Configuración'**
  String get settings;

  /// No description provided for @mostPlayed.
  ///
  /// In es, this message translates to:
  /// **'Más escuchado'**
  String get mostPlayed;

  /// No description provided for @topMostPlayed.
  ///
  /// In es, this message translates to:
  /// **'Top #{count} más escuchado'**
  String topMostPlayed(Object count);

  /// No description provided for @noMostPlayedSongs.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay canciones más escuchadas'**
  String get noMostPlayedSongs;

  /// No description provided for @favorites.
  ///
  /// In es, this message translates to:
  /// **'Favoritos'**
  String get favorites;

  /// No description provided for @noFavoriteSongs.
  ///
  /// In es, this message translates to:
  /// **'Aún no tienes canciones favoritas'**
  String get noFavoriteSongs;

  /// No description provided for @play.
  ///
  /// In es, this message translates to:
  /// **'Reproducir'**
  String get play;

  /// No description provided for @refresh.
  ///
  /// In es, this message translates to:
  /// **'Actualizar'**
  String get refresh;

  /// No description provided for @removeFromFavorites.
  ///
  /// In es, this message translates to:
  /// **'Quitar de favoritos'**
  String get removeFromFavorites;

  /// No description provided for @addToFavorites.
  ///
  /// In es, this message translates to:
  /// **'Añadir a favoritos'**
  String get addToFavorites;

  /// No description provided for @removeFromQueue.
  ///
  /// In es, this message translates to:
  /// **'Quitar de la cola'**
  String get removeFromQueue;

  /// No description provided for @addToQueue.
  ///
  /// In es, this message translates to:
  /// **'Agregar a la cola'**
  String get addToQueue;

  /// No description provided for @addToPlaylist.
  ///
  /// In es, this message translates to:
  /// **'Agregar a playlist'**
  String get addToPlaylist;

  /// No description provided for @mostPlayedBadge.
  ///
  /// In es, this message translates to:
  /// **'MÁS ESCUCHADO'**
  String get mostPlayedBadge;

  /// No description provided for @favoriteBadge.
  ///
  /// In es, this message translates to:
  /// **'FAVORITO'**
  String get favoriteBadge;

  /// No description provided for @explore.
  ///
  /// In es, this message translates to:
  /// **'Explorar'**
  String get explore;

  /// No description provided for @music.
  ///
  /// In es, this message translates to:
  /// **'Música'**
  String get music;

  /// No description provided for @songs.
  ///
  /// In es, this message translates to:
  /// **'Canciones'**
  String get songs;

  /// No description provided for @albums.
  ///
  /// In es, this message translates to:
  /// **'Álbumes'**
  String get albums;

  /// No description provided for @artists.
  ///
  /// In es, this message translates to:
  /// **'Artistas'**
  String get artists;

  /// No description provided for @playlists.
  ///
  /// In es, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// No description provided for @playlistCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1 {1 playlist} other {{count} playlists}}'**
  String playlistCount(num count);

  /// No description provided for @noAlbums.
  ///
  /// In es, this message translates to:
  /// **'No hay álbumes en tu biblioteca.'**
  String get noAlbums;

  /// No description provided for @noArtists.
  ///
  /// In es, this message translates to:
  /// **'No hay artistas en tu biblioteca.'**
  String get noArtists;

  /// No description provided for @libraryEmpty.
  ///
  /// In es, this message translates to:
  /// **'Tu biblioteca está vacía'**
  String get libraryEmpty;

  /// No description provided for @scanMusicDescription.
  ///
  /// In es, this message translates to:
  /// **'Escanea tu carpeta de música para encontrar canciones.'**
  String get scanMusicDescription;

  /// No description provided for @scanMayTake.
  ///
  /// In es, this message translates to:
  /// **'Este proceso puede tardar de 1 a 5 minutos.'**
  String get scanMayTake;

  /// No description provided for @scanning.
  ///
  /// In es, this message translates to:
  /// **'Escaneando...'**
  String get scanning;

  /// No description provided for @scanMusic.
  ///
  /// In es, this message translates to:
  /// **'Escanear música'**
  String get scanMusic;

  /// No description provided for @updateList.
  ///
  /// In es, this message translates to:
  /// **'Actualizar lista'**
  String get updateList;

  /// No description provided for @foundSongs.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1 {# canción encontrada} other {# canciones encontradas}}'**
  String foundSongs(num count);

  /// No description provided for @noFavoriteSongsLibrary.
  ///
  /// In es, this message translates to:
  /// **'No tienes canciones favoritas'**
  String get noFavoriteSongsLibrary;

  /// No description provided for @noFavoriteSongsDescription.
  ///
  /// In es, this message translates to:
  /// **'Marca canciones como favoritas para verlas aquí.'**
  String get noFavoriteSongsDescription;

  /// No description provided for @addAllToQueue.
  ///
  /// In es, this message translates to:
  /// **'Agregar todo a la cola'**
  String get addAllToQueue;

  /// No description provided for @ready.
  ///
  /// In es, this message translates to:
  /// **'Listo'**
  String get ready;

  /// No description provided for @changeOrder.
  ///
  /// In es, this message translates to:
  /// **'Cambiar orden'**
  String get changeOrder;

  /// No description provided for @removeFavoriteConfirmation.
  ///
  /// In es, this message translates to:
  /// **'¿Quieres quitar \"{song}\" de tus favoritos?'**
  String removeFavoriteConfirmation(Object song);

  /// No description provided for @remove.
  ///
  /// In es, this message translates to:
  /// **'Quitar'**
  String get remove;

  /// No description provided for @noPlaylists.
  ///
  /// In es, this message translates to:
  /// **'No tienes playlists'**
  String get noPlaylists;

  /// No description provided for @createPlaylistDescription.
  ///
  /// In es, this message translates to:
  /// **'Crea una playlist para organizar tu música.'**
  String get createPlaylistDescription;

  /// No description provided for @newPlaylist.
  ///
  /// In es, this message translates to:
  /// **'Nueva playlist'**
  String get newPlaylist;

  /// No description provided for @importPlaylist.
  ///
  /// In es, this message translates to:
  /// **'Importar playlist'**
  String get importPlaylist;

  /// No description provided for @addPlaylist.
  ///
  /// In es, this message translates to:
  /// **'Agregar playlist'**
  String get addPlaylist;

  /// No description provided for @renamePlaylist.
  ///
  /// In es, this message translates to:
  /// **'Renombrar playlist'**
  String get renamePlaylist;

  /// No description provided for @playlistName.
  ///
  /// In es, this message translates to:
  /// **'Nombre de la playlist'**
  String get playlistName;

  /// No description provided for @exportPlaylist.
  ///
  /// In es, this message translates to:
  /// **'Exportar playlist'**
  String get exportPlaylist;

  /// No description provided for @deletePlaylist.
  ///
  /// In es, this message translates to:
  /// **'Eliminar playlist'**
  String get deletePlaylist;

  /// No description provided for @deletePlaylistConfirmation.
  ///
  /// In es, this message translates to:
  /// **'¿Quieres eliminar \"{playlist}\"?'**
  String deletePlaylistConfirmation(Object playlist);

  /// No description provided for @cancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get save;

  /// No description provided for @currentlyPlaying.
  ///
  /// In es, this message translates to:
  /// **'Esta canción se está reproduciendo actualmente.'**
  String get currentlyPlaying;

  /// No description provided for @alreadyInQueue.
  ///
  /// In es, this message translates to:
  /// **'Esta canción ya está en la cola.'**
  String get alreadyInQueue;

  /// No description provided for @queueContainsSongs.
  ///
  /// In es, this message translates to:
  /// **'La cola ya contiene canciones. ¿Qué quieres hacer?'**
  String get queueContainsSongs;

  /// No description provided for @replaceQueue.
  ///
  /// In es, this message translates to:
  /// **'Reemplazar cola'**
  String get replaceQueue;

  /// No description provided for @options.
  ///
  /// In es, this message translates to:
  /// **'Opciones'**
  String get options;

  /// No description provided for @noAlbum.
  ///
  /// In es, this message translates to:
  /// **'Sin álbum'**
  String get noAlbum;

  /// No description provided for @unknownArtist.
  ///
  /// In es, this message translates to:
  /// **'Artista desconocido'**
  String get unknownArtist;

  /// No description provided for @libraryEmptyTitle.
  ///
  /// In es, this message translates to:
  /// **'Tu biblioteca está vacía'**
  String get libraryEmptyTitle;

  /// No description provided for @libraryEmptyDescription.
  ///
  /// In es, this message translates to:
  /// **'Escanea tu carpeta de música para encontrar canciones.'**
  String get libraryEmptyDescription;

  /// No description provided for @scanDurationHint.
  ///
  /// In es, this message translates to:
  /// **'Este proceso puede tardar de 1 a 5 minutos.'**
  String get scanDurationHint;

  /// No description provided for @songsFound.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1 {1 canción encontrada} other {{count} canciones encontradas}}'**
  String songsFound(num count);

  /// No description provided for @songCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0 {0 canciones} =1 {1 canción} other {{count} canciones}}'**
  String songCount(num count);

  /// No description provided for @done.
  ///
  /// In es, this message translates to:
  /// **'Listo'**
  String get done;

  /// No description provided for @removeFromFavoritesQuestion.
  ///
  /// In es, this message translates to:
  /// **'¿Quieres quitar \"{title}\" de tus favoritos?'**
  String removeFromFavoritesQuestion(Object title);

  /// No description provided for @songAlreadyInQueue.
  ///
  /// In es, this message translates to:
  /// **'Esta canción ya está en la cola.'**
  String get songAlreadyInQueue;

  /// No description provided for @deletePlaylistQuestion.
  ///
  /// In es, this message translates to:
  /// **'¿Quieres eliminar \"{name}\"?'**
  String deletePlaylistQuestion(Object name);

  /// No description provided for @noPlaylistsTitle.
  ///
  /// In es, this message translates to:
  /// **'No tienes playlists'**
  String get noPlaylistsTitle;

  /// No description provided for @noPlaylistsDescription.
  ///
  /// In es, this message translates to:
  /// **'Crea una playlist para organizar tu música.'**
  String get noPlaylistsDescription;

  /// No description provided for @noFavoritesTitle.
  ///
  /// In es, this message translates to:
  /// **'No tienes canciones favoritas'**
  String get noFavoritesTitle;

  /// No description provided for @noFavoritesDescription.
  ///
  /// In es, this message translates to:
  /// **'Marca canciones como favoritas para verlas aquí.'**
  String get noFavoritesDescription;

  /// No description provided for @playlistQueueTitle.
  ///
  /// In es, this message translates to:
  /// **'La cola ya contiene canciones'**
  String get playlistQueueTitle;

  /// No description provided for @whatToDoWithSong.
  ///
  /// In es, this message translates to:
  /// **'¿Qué quieres hacer con esta canción?'**
  String get whatToDoWithSong;

  /// No description provided for @clearQueue.
  ///
  /// In es, this message translates to:
  /// **'Borrar cola'**
  String get clearQueue;

  /// No description provided for @addEntirePlaylist.
  ///
  /// In es, this message translates to:
  /// **'Agregar toda la playlist'**
  String get addEntirePlaylist;

  /// No description provided for @addEntirePlaylistDescription.
  ///
  /// In es, this message translates to:
  /// **'Esta acción borrará la cola actual y agregará toda la playlist.'**
  String get addEntirePlaylistDescription;

  /// No description provided for @ok.
  ///
  /// In es, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @removeFromPlaylist.
  ///
  /// In es, this message translates to:
  /// **'Quitar de la playlist'**
  String get removeFromPlaylist;

  /// No description provided for @removeSongFromPlaylistQuestion.
  ///
  /// In es, this message translates to:
  /// **'¿Quieres quitar \"{title}\" de esta playlist?'**
  String removeSongFromPlaylistQuestion(Object title);

  /// No description provided for @back.
  ///
  /// In es, this message translates to:
  /// **'Regresar'**
  String get back;

  /// No description provided for @removeSongFromPlaylistError.
  ///
  /// In es, this message translates to:
  /// **'No se pudo quitar la canción de la playlist'**
  String get removeSongFromPlaylistError;

  /// No description provided for @playlistNameHint.
  ///
  /// In es, this message translates to:
  /// **'Mi playlist'**
  String get playlistNameHint;

  /// No description provided for @create.
  ///
  /// In es, this message translates to:
  /// **'Crear'**
  String get create;

  /// No description provided for @playlistDoesNotExist.
  ///
  /// In es, this message translates to:
  /// **'Esta playlist ya no existe'**
  String get playlistDoesNotExist;

  /// No description provided for @playlistIsEmpty.
  ///
  /// In es, this message translates to:
  /// **'Esta playlist está vacía'**
  String get playlistIsEmpty;

  /// No description provided for @saveOrder.
  ///
  /// In es, this message translates to:
  /// **'Guardar orden'**
  String get saveOrder;

  /// No description provided for @closePlayer.
  ///
  /// In es, this message translates to:
  /// **'Cerrar reproductor'**
  String get closePlayer;

  /// No description provided for @noSongPlaying.
  ///
  /// In es, this message translates to:
  /// **'No hay ninguna canción reproduciéndose'**
  String get noSongPlaying;

  /// No description provided for @minimizePlayer.
  ///
  /// In es, this message translates to:
  /// **'Minimizar reproductor'**
  String get minimizePlayer;

  /// No description provided for @nowPlaying.
  ///
  /// In es, this message translates to:
  /// **'Reproduciendo'**
  String get nowPlaying;

  /// No description provided for @previous.
  ///
  /// In es, this message translates to:
  /// **'Anterior'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In es, this message translates to:
  /// **'Siguiente'**
  String get next;

  /// No description provided for @queue.
  ///
  /// In es, this message translates to:
  /// **'Cola'**
  String get queue;

  /// No description provided for @repeatOff.
  ///
  /// In es, this message translates to:
  /// **'No repetir'**
  String get repeatOff;

  /// No description provided for @repeatSong.
  ///
  /// In es, this message translates to:
  /// **'Repetir canción'**
  String get repeatSong;

  /// No description provided for @repeatQueue.
  ///
  /// In es, this message translates to:
  /// **'Repetir lista'**
  String get repeatQueue;

  /// No description provided for @shuffleEnabled.
  ///
  /// In es, this message translates to:
  /// **'Aleatorio activado'**
  String get shuffleEnabled;

  /// No description provided for @shuffleDisabled.
  ///
  /// In es, this message translates to:
  /// **'Aleatorio desactivado'**
  String get shuffleDisabled;

  /// No description provided for @queueTitle.
  ///
  /// In es, this message translates to:
  /// **'Cola de espera'**
  String get queueTitle;

  /// No description provided for @queueEmpty.
  ///
  /// In es, this message translates to:
  /// **'La cola está vacía'**
  String get queueEmpty;

  /// No description provided for @pause.
  ///
  /// In es, this message translates to:
  /// **'Pausar'**
  String get pause;

  /// No description provided for @searchDescription.
  ///
  /// In es, this message translates to:
  /// **'Encuentra música en tu biblioteca y descubre más para escuchar.'**
  String get searchDescription;

  /// No description provided for @searchFieldHint.
  ///
  /// In es, this message translates to:
  /// **'Canciones, artistas o álbumes'**
  String get searchFieldHint;

  /// No description provided for @clearSearch.
  ///
  /// In es, this message translates to:
  /// **'Limpiar búsqueda'**
  String get clearSearch;

  /// No description provided for @searchingYouTube.
  ///
  /// In es, this message translates to:
  /// **'Buscando en YouTube...'**
  String get searchingYouTube;

  /// No description provided for @searchAlsoYouTube.
  ///
  /// In es, this message translates to:
  /// **'Buscar también en YouTube'**
  String get searchAlsoYouTube;

  /// No description provided for @localResult.
  ///
  /// In es, this message translates to:
  /// **'{count} resultado local'**
  String localResult(Object count);

  /// Cantidad de resultados encontrados en la biblioteca local
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1 {1 resultado local} other {{count} resultados locales}}'**
  String localResults(int count);

  /// No description provided for @youtubeResult.
  ///
  /// In es, this message translates to:
  /// **'{count} resultado de YouTube'**
  String youtubeResult(Object count);

  /// Cantidad de resultados encontrados en YouTube
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1 {1 resultado de YouTube} other {{count} resultados de YouTube}}'**
  String youtubeResults(int count);

  /// No description provided for @showMore.
  ///
  /// In es, this message translates to:
  /// **'Mostrar más'**
  String get showMore;

  /// No description provided for @noMoreResults.
  ///
  /// In es, this message translates to:
  /// **'No hay más resultados'**
  String get noMoreResults;

  /// No description provided for @noYouTubeResults.
  ///
  /// In es, this message translates to:
  /// **'No encontramos resultados en YouTube.'**
  String get noYouTubeResults;

  /// No description provided for @tryAnotherSearch.
  ///
  /// In es, this message translates to:
  /// **'Intenta con otra búsqueda.'**
  String get tryAnotherSearch;

  /// Mensaje cuando no se encuentran canciones en la biblioteca para una búsqueda
  ///
  /// In es, this message translates to:
  /// **'No encontramos \"{query}\"'**
  String noLibraryResults(String query);

  /// No description provided for @noLibraryMatches.
  ///
  /// In es, this message translates to:
  /// **'No hay coincidencias en tu biblioteca local.'**
  String get noLibraryMatches;

  /// No description provided for @whatToListen.
  ///
  /// In es, this message translates to:
  /// **'¿Qué quieres escuchar?'**
  String get whatToListen;

  /// No description provided for @searchDescriptionLong.
  ///
  /// In es, this message translates to:
  /// **'Busca una canción, artista o álbum. Sonara revisará tu música y podrás ampliar la búsqueda con YouTube.'**
  String get searchDescriptionLong;

  /// No description provided for @playbackTitle.
  ///
  /// In es, this message translates to:
  /// **'Reproducción'**
  String get playbackTitle;

  /// No description provided for @currentlyPlayingMessage.
  ///
  /// In es, this message translates to:
  /// **'Esta canción se está reproduciendo actualmente.'**
  String get currentlyPlayingMessage;

  /// No description provided for @alreadyInQueueMessage.
  ///
  /// In es, this message translates to:
  /// **'Esta canción ya está en la cola.'**
  String get alreadyInQueueMessage;

  /// No description provided for @queueContainsSongsMessage.
  ///
  /// In es, this message translates to:
  /// **'La cola ya contiene canciones. ¿Qué quieres hacer?'**
  String get queueContainsSongsMessage;

  /// No description provided for @downloadPreparing.
  ///
  /// In es, this message translates to:
  /// **'Preparando descarga...'**
  String get downloadPreparing;

  /// No description provided for @downloadCompleted.
  ///
  /// In es, this message translates to:
  /// **'Descarga completada'**
  String get downloadCompleted;

  /// No description provided for @downloadFailed.
  ///
  /// In es, this message translates to:
  /// **'No se pudo descargar'**
  String get downloadFailed;

  /// No description provided for @downloadingAudio.
  ///
  /// In es, this message translates to:
  /// **'Descargando audio'**
  String get downloadingAudio;

  /// No description provided for @downloadSuccessDescription.
  ///
  /// In es, this message translates to:
  /// **'El audio se descargó correctamente y ya está disponible en tu biblioteca.'**
  String get downloadSuccessDescription;

  /// No description provided for @finishingConverting.
  ///
  /// In es, this message translates to:
  /// **'Finalizando y convirtiendo el audio...'**
  String get finishingConverting;

  /// No description provided for @updatingLibrary.
  ///
  /// In es, this message translates to:
  /// **'Actualizando biblioteca...'**
  String get updatingLibrary;

  /// No description provided for @downloadMayTake.
  ///
  /// In es, this message translates to:
  /// **'La descarga puede tardar un par de minutos.'**
  String get downloadMayTake;

  /// No description provided for @downloadAudio.
  ///
  /// In es, this message translates to:
  /// **'Descargar audio'**
  String get downloadAudio;

  /// No description provided for @fileName.
  ///
  /// In es, this message translates to:
  /// **'Nombre del archivo'**
  String get fileName;

  /// No description provided for @format.
  ///
  /// In es, this message translates to:
  /// **'Formato'**
  String get format;

  /// No description provided for @mp3CompatibleDescription.
  ///
  /// In es, this message translates to:
  /// **'Formato compatible con la mayoría de reproductores'**
  String get mp3CompatibleDescription;

  /// No description provided for @afterDownload.
  ///
  /// In es, this message translates to:
  /// **'Después de descargar'**
  String get afterDownload;

  /// No description provided for @playlistWillBeSelected.
  ///
  /// In es, this message translates to:
  /// **'Se seleccionará una playlist después'**
  String get playlistWillBeSelected;

  /// No description provided for @optional.
  ///
  /// In es, this message translates to:
  /// **'Opcional'**
  String get optional;

  /// No description provided for @download.
  ///
  /// In es, this message translates to:
  /// **'Descargar'**
  String get download;

  /// No description provided for @enterFileName.
  ///
  /// In es, this message translates to:
  /// **'Escribe un nombre para el archivo.'**
  String get enterFileName;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
