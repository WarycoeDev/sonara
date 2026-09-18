// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Sonara';

  @override
  String get appearance => 'Appearance';

  @override
  String get appearanceMode => 'Appearance mode';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get accentColor => 'Accent color';

  @override
  String get colorSonara => 'Sonara';

  @override
  String get colorVioleta => 'Violet';

  @override
  String get colorEsmeralda => 'Emerald';

  @override
  String get colorNaranja => 'Orange';

  @override
  String get colorRojo => 'Red';

  @override
  String get colorRosa => 'Pink';

  @override
  String get colorCian => 'Cyan';

  @override
  String get playback => 'Playback';

  @override
  String get crossfade => 'Crossfade';

  @override
  String get disabled => 'Disabled';

  @override
  String seconds(Object count) {
    return '$count seconds';
  }

  @override
  String secondsShort(Object count) {
    return '$count s';
  }

  @override
  String get application => 'Application';

  @override
  String get language => 'Language';

  @override
  String get about => 'About';

  @override
  String get aboutSonara => 'Information about Sonara';

  @override
  String get sourceCode => 'Source code';

  @override
  String get viewSonaraSource => 'View Sonara source code';

  @override
  String get close => 'Close';

  @override
  String get aboutSonaraTitle => 'About Sonara';

  @override
  String get aboutSonaraDescription =>
      'A fast, powerful music player designed for your everyday listening.';

  @override
  String get developer => 'Developer';

  @override
  String get helper => 'Helper';

  @override
  String get openSourceLicenses => 'Open-source licenses';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get support => 'Support';

  @override
  String get allRightsReserved => 'All rights reserved.';

  @override
  String version(Object version) {
    return 'Version $version';
  }

  @override
  String get home => 'Home';

  @override
  String get library => 'Library';

  @override
  String get search => 'Search';

  @override
  String get settings => 'Settings';

  @override
  String get mostPlayed => 'Most Played';

  @override
  String topMostPlayed(Object count) {
    return 'Top #$count Most Played';
  }

  @override
  String get noMostPlayedSongs => 'There are no most-played songs yet';

  @override
  String get favorites => 'Favorites';

  @override
  String get noFavoriteSongs => 'You don\'t have any favorite songs';

  @override
  String get play => 'Play';

  @override
  String get refresh => 'Refresh';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get removeFromQueue => 'Remove from queue';

  @override
  String get addToQueue => 'Add to queue';

  @override
  String get addToPlaylist => 'Add to playlist';

  @override
  String get mostPlayedBadge => 'MOST PLAYED';

  @override
  String get favoriteBadge => 'FAVORITE';

  @override
  String get explore => 'Explore';

  @override
  String get music => 'Music';

  @override
  String get songs => 'Songs';

  @override
  String get albums => 'Albums';

  @override
  String get artists => 'Artists';

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
  String get noAlbums => 'There are no albums in your library.';

  @override
  String get noArtists => 'There are no artists in your library.';

  @override
  String get libraryEmpty => 'Your library is empty';

  @override
  String get scanMusicDescription => 'Scan your music folder to find songs.';

  @override
  String get scanMayTake => 'This process may take 1 to 5 minutes.';

  @override
  String get scanning => 'Scanning...';

  @override
  String get scanMusic => 'Scan music';

  @override
  String get updateList => 'Refresh list';

  @override
  String foundSongs(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# songs found',
      one: '# song found',
    );
    return '$_temp0';
  }

  @override
  String get noFavoriteSongsLibrary => 'You don\'t have any favorite songs';

  @override
  String get noFavoriteSongsDescription =>
      'Mark songs as favorites to see them here.';

  @override
  String get addAllToQueue => 'Add all to queue';

  @override
  String get ready => 'Ready';

  @override
  String get changeOrder => 'Change order';

  @override
  String removeFavoriteConfirmation(Object song) {
    return 'Do you want to remove \"$song\" from your favorites?';
  }

  @override
  String get remove => 'Remove';

  @override
  String get noPlaylists => 'You don\'t have any playlists';

  @override
  String get createPlaylistDescription =>
      'Create a playlist to organize your music.';

  @override
  String get newPlaylist => 'New playlist';

  @override
  String get importPlaylist => 'Import playlist';

  @override
  String get addPlaylist => 'Add playlist';

  @override
  String get renamePlaylist => 'Rename playlist';

  @override
  String get playlistName => 'Playlist name';

  @override
  String get exportPlaylist => 'Export playlist';

  @override
  String get deletePlaylist => 'Delete playlist';

  @override
  String deletePlaylistConfirmation(Object playlist) {
    return 'Do you want to delete \"$playlist\"?';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get currentlyPlaying => 'This song is currently playing.';

  @override
  String get alreadyInQueue => 'This song is already in the queue';

  @override
  String get queueContainsSongs =>
      'The queue already contains songs. What do you want to do?';

  @override
  String get replaceQueue => 'Replace queue';

  @override
  String get options => 'Options';

  @override
  String get noAlbum => 'No album';

  @override
  String get unknownArtist => 'Unknown artist';

  @override
  String get libraryEmptyTitle => 'Your library is empty';

  @override
  String get libraryEmptyDescription => 'Scan your music folder to find songs.';

  @override
  String get scanDurationHint => 'This process may take 1 to 5 minutes.';

  @override
  String songsFound(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs found',
      one: '1 song found',
    );
    return '$_temp0';
  }

  @override
  String songCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '1 song',
      zero: '0 songs',
    );
    return '$_temp0';
  }

  @override
  String get done => 'Done';

  @override
  String removeFromFavoritesQuestion(Object title) {
    return 'Do you want to remove \"$title\" from your favorites?';
  }

  @override
  String get songAlreadyInQueue => 'This song is already in the queue.';

  @override
  String deletePlaylistQuestion(Object name) {
    return 'Do you want to delete \"$name\"?';
  }

  @override
  String get noPlaylistsTitle => 'You have no playlists';

  @override
  String get noPlaylistsDescription =>
      'Create a playlist to organize your music.';

  @override
  String get noFavoritesTitle => 'You have no favorite songs';

  @override
  String get noFavoritesDescription =>
      'Mark songs as favorites to see them here.';

  @override
  String get playlistQueueTitle => 'The queue already contains songs';

  @override
  String get whatToDoWithSong => 'What do you want to do with this song?';

  @override
  String get clearQueue => 'Clear queue';

  @override
  String get addEntirePlaylist => 'Add entire playlist';

  @override
  String get addEntirePlaylistDescription =>
      'This will clear the current queue and add the entire playlist.';

  @override
  String get ok => 'OK';

  @override
  String get removeFromPlaylist => 'Remove from playlist';

  @override
  String removeSongFromPlaylistQuestion(Object title) {
    return 'Do you want to remove \"$title\" from this playlist?';
  }

  @override
  String get back => 'Back';

  @override
  String get removeSongFromPlaylistError =>
      'The song could not be removed from the playlist';

  @override
  String get playlistNameHint => 'My playlist';

  @override
  String get create => 'Create';

  @override
  String get playlistDoesNotExist => 'This playlist no longer exists';

  @override
  String get playlistIsEmpty => 'This playlist is empty';

  @override
  String get saveOrder => 'Save order';

  @override
  String get closePlayer => 'Close player';

  @override
  String get noSongPlaying => 'No song is currently playing';

  @override
  String get minimizePlayer => 'Minimize player';

  @override
  String get nowPlaying => 'Now Playing';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get queue => 'Queue';

  @override
  String get repeatOff => 'Don\'t repeat';

  @override
  String get repeatSong => 'Repeat song';

  @override
  String get repeatQueue => 'Repeat queue';

  @override
  String get shuffleEnabled => 'Shuffle enabled';

  @override
  String get shuffleDisabled => 'Shuffle disabled';

  @override
  String get queueTitle => 'Queue';

  @override
  String get queueEmpty => 'The queue is empty';

  @override
  String get pause => 'Pause';

  @override
  String get searchDescription =>
      'Find music in your library and discover more to listen to.';

  @override
  String get searchFieldHint => 'Songs, artists or albums';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get searchingYouTube => 'Searching YouTube...';

  @override
  String get searchAlsoYouTube => 'Search on YouTube';

  @override
  String localResult(Object count) {
    return '$count local result';
  }

  @override
  String localResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count local results',
      one: '1 local result',
    );
    return '$_temp0';
  }

  @override
  String youtubeResult(Object count) {
    return '$count YouTube result';
  }

  @override
  String youtubeResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count YouTube results',
      one: '1 YouTube result',
    );
    return '$_temp0';
  }

  @override
  String get showMore => 'Show more';

  @override
  String get noMoreResults => 'No more results';

  @override
  String get noYouTubeResults => 'We couldn\'t find any results on YouTube.';

  @override
  String get tryAnotherSearch => 'Try another search.';

  @override
  String noLibraryResults(String query) {
    return 'No results found for \"$query\"';
  }

  @override
  String get noLibraryMatches => 'There are no matches in your local library.';

  @override
  String get whatToListen => 'What do you want to listen to?';

  @override
  String get searchDescriptionLong =>
      'Search for a song, artist, or album. Sonara will check your music and you can expand the search to YouTube.';

  @override
  String get playbackTitle => 'Playback';

  @override
  String get currentlyPlayingMessage => 'This song is currently playing.';

  @override
  String get alreadyInQueueMessage => 'This song is already in the queue.';

  @override
  String get queueContainsSongsMessage =>
      'The queue already contains songs. What do you want to do?';

  @override
  String get downloadPreparing => 'Preparing download...';

  @override
  String get downloadCompleted => 'Download completed';

  @override
  String get downloadFailed => 'Download failed';

  @override
  String get downloadingAudio => 'Downloading audio';

  @override
  String get downloadSuccessDescription =>
      'The audio was downloaded successfully and is now available in your library.';

  @override
  String get finishingConverting => 'Finishing and converting audio...';

  @override
  String get updatingLibrary => 'Updating library...';

  @override
  String get downloadMayTake => 'The download may take a few of minutes.';

  @override
  String get downloadAudio => 'Download audio';

  @override
  String get fileName => 'File name';

  @override
  String get format => 'Format';

  @override
  String get mp3CompatibleDescription => 'Format compatible with most players';

  @override
  String get afterDownload => 'After downloading';

  @override
  String get playlistWillBeSelected => 'A playlist will be selected afterwards';

  @override
  String get optional => 'Optional';

  @override
  String get download => 'Download';

  @override
  String get enterFileName => 'Enter a name for the file.';
}
