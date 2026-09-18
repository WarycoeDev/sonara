// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'Sonara';

  @override
  String get appearance => 'Apariencia';

  @override
  String get appearanceMode => 'Modo de apariencia';

  @override
  String get system => 'Sistema';

  @override
  String get light => 'Claro';

  @override
  String get dark => 'Oscuro';

  @override
  String get accentColor => 'Color de acento';

  @override
  String get colorSonara => 'Sonara';

  @override
  String get colorVioleta => 'Violeta';

  @override
  String get colorEsmeralda => 'Esmeralda';

  @override
  String get colorNaranja => 'Naranja';

  @override
  String get colorRojo => 'Rojo';

  @override
  String get colorRosa => 'Rosa';

  @override
  String get colorCian => 'Cian';

  @override
  String get playback => 'Reproducción';

  @override
  String get crossfade => 'Crossfade';

  @override
  String get disabled => 'Desactivado';

  @override
  String seconds(Object count) {
    return '$count segundos';
  }

  @override
  String secondsShort(Object count) {
    return '$count s';
  }

  @override
  String get application => 'Aplicación';

  @override
  String get language => 'Idioma';

  @override
  String get about => 'Acerca de';

  @override
  String get aboutSonara => 'Información sobre Sonara';

  @override
  String get sourceCode => 'Código fuente';

  @override
  String get viewSonaraSource => 'Ver el código de Sonara';

  @override
  String get close => 'Cerrar';

  @override
  String get aboutSonaraTitle => 'Acerca de Sonara';

  @override
  String get aboutSonaraDescription =>
      'Un reproductor de música rápido, potente y diseñado para tu día a día.';

  @override
  String get developer => 'Desarrollador';

  @override
  String get helper => 'Ayudante';

  @override
  String get openSourceLicenses => 'Licencias de código abierto';

  @override
  String get privacyPolicy => 'Política de privacidad';

  @override
  String get support => 'Soporte';

  @override
  String get allRightsReserved => 'Todos los derechos reservados.';

  @override
  String version(Object version) {
    return 'Versión $version';
  }

  @override
  String get home => 'Inicio';

  @override
  String get library => 'Biblioteca';

  @override
  String get search => 'Buscar';

  @override
  String get settings => 'Configuración';

  @override
  String get mostPlayed => 'Más escuchado';

  @override
  String topMostPlayed(Object count) {
    return 'Top #$count más escuchado';
  }

  @override
  String get noMostPlayedSongs => 'Aún no hay canciones más escuchadas';

  @override
  String get favorites => 'Favoritos';

  @override
  String get noFavoriteSongs => 'Aún no tienes canciones favoritas';

  @override
  String get play => 'Reproducir';

  @override
  String get refresh => 'Actualizar';

  @override
  String get removeFromFavorites => 'Quitar de favoritos';

  @override
  String get addToFavorites => 'Añadir a favoritos';

  @override
  String get removeFromQueue => 'Quitar de la cola';

  @override
  String get addToQueue => 'Agregar a la cola';

  @override
  String get addToPlaylist => 'Agregar a playlist';

  @override
  String get mostPlayedBadge => 'MÁS ESCUCHADO';

  @override
  String get favoriteBadge => 'FAVORITO';

  @override
  String get explore => 'Explorar';

  @override
  String get music => 'Música';

  @override
  String get songs => 'Canciones';

  @override
  String get albums => 'Álbumes';

  @override
  String get artists => 'Artistas';

  @override
  String get playlists => 'Playlists';

  @override
  String playlistCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists',
      one: '1 playlist',
    );
    return '$_temp0';
  }

  @override
  String get noAlbums => 'No hay álbumes en tu biblioteca.';

  @override
  String get noArtists => 'No hay artistas en tu biblioteca.';

  @override
  String get libraryEmpty => 'Tu biblioteca está vacía';

  @override
  String get scanMusicDescription =>
      'Escanea tu carpeta de música para encontrar canciones.';

  @override
  String get scanMayTake => 'Este proceso puede tardar de 1 a 5 minutos.';

  @override
  String get scanning => 'Escaneando...';

  @override
  String get scanMusic => 'Escanear música';

  @override
  String get updateList => 'Actualizar lista';

  @override
  String foundSongs(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# canciones encontradas',
      one: '# canción encontrada',
    );
    return '$_temp0';
  }

  @override
  String get noFavoriteSongsLibrary => 'No tienes canciones favoritas';

  @override
  String get noFavoriteSongsDescription =>
      'Marca canciones como favoritas para verlas aquí.';

  @override
  String get addAllToQueue => 'Agregar todo a la cola';

  @override
  String get ready => 'Listo';

  @override
  String get changeOrder => 'Cambiar orden';

  @override
  String removeFavoriteConfirmation(Object song) {
    return '¿Quieres quitar \"$song\" de tus favoritos?';
  }

  @override
  String get remove => 'Quitar';

  @override
  String get noPlaylists => 'No tienes playlists';

  @override
  String get createPlaylistDescription =>
      'Crea una playlist para organizar tu música.';

  @override
  String get newPlaylist => 'Nueva playlist';

  @override
  String get importPlaylist => 'Importar playlist';

  @override
  String get addPlaylist => 'Agregar playlist';

  @override
  String get renamePlaylist => 'Renombrar playlist';

  @override
  String get playlistName => 'Nombre de la playlist';

  @override
  String get exportPlaylist => 'Exportar playlist';

  @override
  String get deletePlaylist => 'Eliminar playlist';

  @override
  String deletePlaylistConfirmation(Object playlist) {
    return '¿Quieres eliminar \"$playlist\"?';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get currentlyPlaying =>
      'Esta canción se está reproduciendo actualmente.';

  @override
  String get alreadyInQueue => 'Esta canción ya está en la cola.';

  @override
  String get queueContainsSongs =>
      'La cola ya contiene canciones. ¿Qué quieres hacer?';

  @override
  String get replaceQueue => 'Reemplazar cola';

  @override
  String get options => 'Opciones';

  @override
  String get noAlbum => 'Sin álbum';

  @override
  String get unknownArtist => 'Artista desconocido';

  @override
  String get libraryEmptyTitle => 'Tu biblioteca está vacía';

  @override
  String get libraryEmptyDescription =>
      'Escanea tu carpeta de música para encontrar canciones.';

  @override
  String get scanDurationHint => 'Este proceso puede tardar de 1 a 5 minutos.';

  @override
  String songsFound(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count canciones encontradas',
      one: '1 canción encontrada',
    );
    return '$_temp0';
  }

  @override
  String songCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count canciones',
      one: '1 canción',
      zero: '0 canciones',
    );
    return '$_temp0';
  }

  @override
  String get done => 'Listo';

  @override
  String removeFromFavoritesQuestion(Object title) {
    return '¿Quieres quitar \"$title\" de tus favoritos?';
  }

  @override
  String get songAlreadyInQueue => 'Esta canción ya está en la cola.';

  @override
  String deletePlaylistQuestion(Object name) {
    return '¿Quieres eliminar \"$name\"?';
  }

  @override
  String get noPlaylistsTitle => 'No tienes playlists';

  @override
  String get noPlaylistsDescription =>
      'Crea una playlist para organizar tu música.';

  @override
  String get noFavoritesTitle => 'No tienes canciones favoritas';

  @override
  String get noFavoritesDescription =>
      'Marca canciones como favoritas para verlas aquí.';

  @override
  String get playlistQueueTitle => 'La cola ya contiene canciones';

  @override
  String get whatToDoWithSong => '¿Qué quieres hacer con esta canción?';

  @override
  String get clearQueue => 'Borrar cola';

  @override
  String get addEntirePlaylist => 'Agregar toda la playlist';

  @override
  String get addEntirePlaylistDescription =>
      'Esta acción borrará la cola actual y agregará toda la playlist.';

  @override
  String get ok => 'OK';

  @override
  String get removeFromPlaylist => 'Quitar de la playlist';

  @override
  String removeSongFromPlaylistQuestion(Object title) {
    return '¿Quieres quitar \"$title\" de esta playlist?';
  }

  @override
  String get back => 'Regresar';

  @override
  String get removeSongFromPlaylistError =>
      'No se pudo quitar la canción de la playlist';

  @override
  String get playlistNameHint => 'Mi playlist';

  @override
  String get create => 'Crear';

  @override
  String get playlistDoesNotExist => 'Esta playlist ya no existe';

  @override
  String get playlistIsEmpty => 'Esta playlist está vacía';

  @override
  String get saveOrder => 'Guardar orden';

  @override
  String get closePlayer => 'Cerrar reproductor';

  @override
  String get noSongPlaying => 'No hay ninguna canción reproduciéndose';

  @override
  String get minimizePlayer => 'Minimizar reproductor';

  @override
  String get nowPlaying => 'Reproduciendo';

  @override
  String get previous => 'Anterior';

  @override
  String get next => 'Siguiente';

  @override
  String get queue => 'Cola';

  @override
  String get repeatOff => 'No repetir';

  @override
  String get repeatSong => 'Repetir canción';

  @override
  String get repeatQueue => 'Repetir lista';

  @override
  String get shuffleEnabled => 'Aleatorio activado';

  @override
  String get shuffleDisabled => 'Aleatorio desactivado';

  @override
  String get queueTitle => 'Cola de espera';

  @override
  String get queueEmpty => 'La cola está vacía';

  @override
  String get pause => 'Pausar';

  @override
  String get searchDescription =>
      'Encuentra música en tu biblioteca y descubre más para escuchar.';

  @override
  String get searchFieldHint => 'Canciones, artistas o álbumes';

  @override
  String get clearSearch => 'Limpiar búsqueda';

  @override
  String get searchingYouTube => 'Buscando en YouTube...';

  @override
  String get searchAlsoYouTube => 'Buscar también en YouTube';

  @override
  String localResult(Object count) {
    return '$count resultado local';
  }

  @override
  String localResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados locales',
      one: '1 resultado local',
    );
    return '$_temp0';
  }

  @override
  String youtubeResult(Object count) {
    return '$count resultado de YouTube';
  }

  @override
  String youtubeResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados de YouTube',
      one: '1 resultado de YouTube',
    );
    return '$_temp0';
  }

  @override
  String get showMore => 'Mostrar más';

  @override
  String get noMoreResults => 'No hay más resultados';

  @override
  String get noYouTubeResults => 'No encontramos resultados en YouTube.';

  @override
  String get tryAnotherSearch => 'Intenta con otra búsqueda.';

  @override
  String noLibraryResults(String query) {
    return 'No encontramos \"$query\"';
  }

  @override
  String get noLibraryMatches => 'No hay coincidencias en tu biblioteca local.';

  @override
  String get whatToListen => '¿Qué quieres escuchar?';

  @override
  String get searchDescriptionLong =>
      'Busca una canción, artista o álbum. Sonara revisará tu música y podrás ampliar la búsqueda con YouTube.';

  @override
  String get playbackTitle => 'Reproducción';

  @override
  String get currentlyPlayingMessage =>
      'Esta canción se está reproduciendo actualmente.';

  @override
  String get alreadyInQueueMessage => 'Esta canción ya está en la cola.';

  @override
  String get queueContainsSongsMessage =>
      'La cola ya contiene canciones. ¿Qué quieres hacer?';

  @override
  String get downloadPreparing => 'Preparando descarga...';

  @override
  String get downloadCompleted => 'Descarga completada';

  @override
  String get downloadFailed => 'No se pudo descargar';

  @override
  String get downloadingAudio => 'Descargando audio';

  @override
  String get downloadSuccessDescription =>
      'El audio se descargó correctamente y ya está disponible en tu biblioteca.';

  @override
  String get finishingConverting => 'Finalizando y convirtiendo el audio...';

  @override
  String get updatingLibrary => 'Actualizando biblioteca...';

  @override
  String get downloadMayTake => 'La descarga puede tardar un par de minutos.';

  @override
  String get downloadAudio => 'Descargar audio';

  @override
  String get fileName => 'Nombre del archivo';

  @override
  String get format => 'Formato';

  @override
  String get mp3CompatibleDescription =>
      'Formato compatible con la mayoría de reproductores';

  @override
  String get afterDownload => 'Después de descargar';

  @override
  String get playlistWillBeSelected => 'Se seleccionará una playlist después';

  @override
  String get optional => 'Opcional';

  @override
  String get download => 'Descargar';

  @override
  String get enterFileName => 'Escribe un nombre para el archivo.';
}
