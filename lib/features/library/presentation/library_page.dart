import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../favorites/data/favorites_repository.dart';
import '../../player/presentation/controllers/player_controller.dart';
import '../data/repositories/local_library_repository.dart';
import '../data/repositories/playlists_repository.dart';
import '../domain/models/album.dart';
import '../domain/models/artist.dart';
import '../domain/models/playlist.dart';
import '../domain/models/song.dart';
import 'library_playlist_page.dart';
import 'playlist_dialogs.dart';
import 'song_options.dart';

enum LibraryCategory { songs, albums, artists, podcasts, playlists, favorites }

const String _noAlbumKey = '__sonara_no_album__';
const String _unknownArtistKey = '__sonara_unknown_artist__';

enum _SongTapAction { replaceQueue, addToQueue, removeFromQueue, cancel }

enum _PlaylistMenuAction { rename, export, delete, create, import }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final LocalLibraryRepository _repository = LocalLibraryRepository();
  final PlaylistsRepository _playlistsRepository = PlaylistsRepository();
  final FavoritesRepository _favoritesRepository = FavoritesRepository();

  late final PlayerController _playerController;

  List<Song> _songs = const [];
  List<Song> _favoriteSongs = const [];
  List<Album> _albums = const [];
  List<Album> _podcasts = const [];
  List<Artist> _artists = const [];
  List<Playlist> _playlists = const [];

  bool _isLoading = false;
  bool _isScanning = false;
  bool _hasLoaded = false;
  bool _isReorderingFavorites = false;

  LibraryCategory _selectedCategory = LibraryCategory.songs;

  @override
  void initState() {
    super.initState();

    _playerController = context.read<PlayerController>();
    _playerController.addListener(_handlePlayerChanged);

    _playlistsRepository.addListener(_handlePlaylistsChanged);
    _favoritesRepository.addListener(_handleFavoritesChanged);

    _loadLibrary();
    _loadPlaylists();
    _loadFavorites();
  }

  @override
  void dispose() {
    _playerController.removeListener(_handlePlayerChanged);

    _playlistsRepository.removeListener(_handlePlaylistsChanged);
    _favoritesRepository.removeListener(_handleFavoritesChanged);

    super.dispose();
  }

  // ============================================================
  // PLAYLISTS
  // ============================================================

  Future<void> _loadPlaylists() async {
    try {
      await _playlistsRepository.initialize();

      if (!mounted) {
        return;
      }

      setState(() {
        _playlists = List.unmodifiable(_playlistsRepository.playlists);
      });
    } catch (_) {}
  }

  void _handlePlaylistsChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      _playlists = List.unmodifiable(_playlistsRepository.playlists);
    });
  }

  // ============================================================
  // ARTWORK
  // ============================================================

  void _handlePlayerChanged() {
    if (!mounted) {
      return;
    }

    final currentSong = _playerController.currentSong;

    if (currentSong == null) {
      return;
    }

    final index = _songs.indexWhere((song) => song.id == currentSong.id);

    if (index == -1) {
      return;
    }

    final previousSong = _songs[index];

    final songChanged =
        previousSong.coverPath != currentSong.coverPath ||
        previousSong.coverBytes != currentSong.coverBytes ||
        previousSong.fileSize != currentSong.fileSize ||
        previousSong.fileLastModified != currentSong.fileLastModified ||
        previousSong.title != currentSong.title ||
        previousSong.artist != currentSong.artist ||
        previousSong.album != currentSong.album ||
        previousSong.isFavorite != currentSong.isFavorite ||
        previousSong.volumeGain != currentSong.volumeGain;

    if (!songChanged) {
      return;
    }

    final updatedSongs = List<Song>.from(_songs);

    updatedSongs[index] = currentSong;

    _updateLibrary(updatedSongs);

    setState(() {});
  }

  // ============================================================
  // FAVORITES
  // ============================================================

  Future<void> _loadFavorites() async {
    try {
      await _favoritesRepository.initialize();

      List<Song> songs = _songs;

      if (songs.isEmpty) {
        songs = await _repository.getSongs();

        if (songs.isNotEmpty && _songs.isEmpty) {
          _updateLibrary(songs);
        }
      }

      final songsById = <String, Song>{for (final song in songs) song.id: song};

      final favorites = <Song>[];

      for (final songId in _favoritesRepository.favoriteIds) {
        final song = songsById[songId];

        if (song != null) {
          favorites.add(song);
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _favoriteSongs = List.unmodifiable(favorites);
      });
    } catch (_) {}
  }

  void _handleFavoritesChanged() {
    if (!mounted) {
      return;
    }

    _loadFavorites();
  }

  // ============================================================
  // LIBRARY
  // ============================================================

  Future<void> _loadLibrary() async {
    if (_hasLoaded || _isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final songs = await _repository.getSongs();

      if (!mounted) {
        return;
      }

      _updateLibrary(songs);

      _playerController.syncLibrarySongs(songs);

      setState(() {
        _hasLoaded = true;
        _isLoading = false;
      });

      await _loadFavorites();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _scanMusic() async {
    if (_isScanning) {
      return;
    }

    setState(() {
      _isScanning = true;
    });

    try {
      await _repository.scanLibrary();

      final songs = await _repository.getSongs();

      if (!mounted) {
        return;
      }

      _updateLibrary(songs);

      _playerController.syncLibrarySongs(songs);

      setState(() {
        _hasLoaded = true;
        _isLoading = false;
        _isScanning = false;
      });

      await _loadFavorites();
    } catch (error) {
      debugPrint('[SONARA SCAN] Error: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _isScanning = false;
        _isLoading = false;
      });
    }
  }

  void _updateLibrary(List<Song> songs) {
    _songs = List.unmodifiable(songs);

    final albumGroups = <String, List<Song>>{};
    final artistGroups = <String, List<Song>>{};
    final podcastGroups = <String, List<Song>>{};

    bool isPodcast(Song song) =>
        song.filePath.replaceAll('\\', '/').toLowerCase().contains('/podcast/');

    for (final song in _songs) {
      if (isPodcast(song)) {
        final normalizedPath = song.filePath.replaceAll('\\', '/');
        final parentPath = normalizedPath.substring(
          0,
          normalizedPath.lastIndexOf('/'),
        );
        final folderName = parentPath.substring(
          parentPath.lastIndexOf('/') + 1,
        );
        final podcastName = folderName.isNotEmpty ? folderName : song.title;
        (podcastGroups[podcastName] ??= <Song>[]).add(song);
        continue;
      }

      final rawAlbum = song.album?.trim();

      final albumName = rawAlbum != null && rawAlbum.isNotEmpty
          ? rawAlbum
          : _noAlbumKey;

      final rawArtist = song.artist?.trim();

      final artistName = rawArtist != null && rawArtist.isNotEmpty
          ? rawArtist
          : _unknownArtistKey;

      (albumGroups[albumName] ??= <Song>[]).add(song);
      (artistGroups[artistName] ??= <Song>[]).add(song);
    }

    final albums =
        albumGroups.entries.map((entry) {
          final albumSongs = entry.value;

          final artist = albumSongs
              .map((song) => song.artist?.trim())
              .firstWhere(
                (value) => value != null && value.isNotEmpty,
                orElse: () => null,
              );

          return Album(
            name: entry.key,
            artist: artist,
            songs: List.unmodifiable(albumSongs),
          );
        }).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

    final artists =
        artistGroups.entries.map((entry) {
          return Artist(name: entry.key, songs: List.unmodifiable(entry.value));
        }).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

    final podcasts =
        podcastGroups.entries.map((entry) {
          return Album(name: entry.key, songs: List.unmodifiable(entry.value));
        }).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

    _albums = List.unmodifiable(albums);
    _podcasts = List.unmodifiable(podcasts);
    _artists = List.unmodifiable(artists);

    final songsById = <String, Song>{for (final song in _songs) song.id: song};

    final favorites = <Song>[];

    for (final songId in _favoritesRepository.favoriteIds) {
      final song = songsById[songId];

      if (song != null) {
        favorites.add(song);
      }
    }

    _favoriteSongs = List.unmodifiable(favorites);
  }

  String _displayAlbumName(BuildContext context, String name) {
    final l10n = AppLocalizations.of(context)!;

    if (name == _noAlbumKey) {
      return l10n.noAlbum;
    }

    return name;
  }

  String _displayArtistName(BuildContext context, String name) {
    final l10n = AppLocalizations.of(context)!;

    if (name == _unknownArtistKey) {
      return l10n.unknownArtist;
    }

    return name;
  }

  void _selectCategory(LibraryCategory category) {
    if (_selectedCategory == category) {
      return;
    }

    setState(() {
      _selectedCategory = category;
      _isReorderingFavorites = false;
    });
  }

  // ============================================================
  // NAVIGATION
  // ============================================================

  void _openPlaylistPage({
    required String title,
    String? subtitle,
    required List<Song> songs,
    required IconData icon,
    String? playlistId,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return LibraryPlaylistPage(
            title: title,
            subtitle: subtitle,
            songs: songs,
            icon: icon,
            playlistId: playlistId,
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: child,
          );
        },
      ),
    );
  }

  void _openAlbum(Album album) {
    _openPlaylistPage(
      title: _displayAlbumName(context, album.name),
      subtitle: album.artist == null
          ? null
          : _displayArtistName(context, album.artist!),
      songs: album.songs,
      icon: Icons.album_outlined,
    );
  }

  void _openPodcast(Album podcast) {
    _openPlaylistPage(
      title: podcast.name,
      subtitle: AppLocalizations.of(context)!.songCount(podcast.songCount),
      songs: podcast.songs,
      icon: Icons.podcasts,
    );
  }

  void _openArtist(Artist artist) {
    _openPlaylistPage(
      title: _displayArtistName(context, artist.name),
      songs: artist.songs,
      icon: Icons.person_outline,
    );
  }

  List<Song> _resolvePlaylistSongs(Playlist playlist) {
    if (playlist.songIds.isEmpty || _songs.isEmpty) {
      return const [];
    }

    final songsById = <String, Song>{for (final song in _songs) song.id: song};

    final resolvedSongs = <Song>[];

    for (final songId in playlist.songIds) {
      final song = songsById[songId];

      if (song != null) {
        resolvedSongs.add(song);
      }
    }

    return List.unmodifiable(resolvedSongs);
  }

  void _openPlaylist(Playlist playlist) {
    final l10n = AppLocalizations.of(context)!;

    final songs = _resolvePlaylistSongs(playlist);

    _openPlaylistPage(
      title: playlist.name,
      subtitle: l10n.songCount(songs.length),
      songs: songs,
      icon: Icons.playlist_play,
      playlistId: playlist.id,
    );
  }

  // ============================================================
  // PLAYLIST ACTIONS
  // ============================================================

  Future<void> _createPlaylist() async {
    await PlaylistDialogs.showCreatePlaylist(context);
  }

  Future<void> _importPlaylist() async {
    try {
      await _playlistsRepository.importPlaylist();
    } catch (_) {}
  }

  Future<void> _exportPlaylist(Playlist playlist) async {
    try {
      await _playlistsRepository.exportPlaylist(playlist.id);
    } catch (_) {}
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final l10n = AppLocalizations.of(context)!;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.deletePlaylist),
          content: Text(l10n.deletePlaylistQuestion(playlist.name)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(l10n.remove),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    await _playlistsRepository.deletePlaylist(playlist.id);
  }

  Future<void> _renamePlaylist(Playlist playlist) async {
    final l10n = AppLocalizations.of(context)!;

    String newName = playlist.name;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.renamePlaylist),
          content: TextFormField(
            initialValue: playlist.name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.playlistName),
            onChanged: (value) {
              newName = value;
            },
            onFieldSubmitted: (value) {
              final trimmedName = value.trim();

              if (trimmedName.isNotEmpty) {
                Navigator.of(dialogContext).pop(trimmedName);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final trimmedName = newName.trim();

                if (trimmedName.isEmpty) {
                  return;
                }

                Navigator.of(dialogContext).pop(trimmedName);
              },
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );

    if (result == null) {
      return;
    }

    final trimmedName = result.trim();

    if (trimmedName.isEmpty || trimmedName == playlist.name) {
      return;
    }

    await _playlistsRepository.renamePlaylist(playlist.id, trimmedName);
  }

  // ============================================================
  // FAVORITES
  // ============================================================

  void _toggleReorderingFavorites() {
    setState(() {
      _isReorderingFavorites = !_isReorderingFavorites;
    });
  }

  Future<void> _reorderFavorites(int oldIndex, int newIndex) async {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }

      final mutableList = List<Song>.from(_favoriteSongs);

      final item = mutableList.removeAt(oldIndex);

      mutableList.insert(newIndex, item);

      _favoriteSongs = List.unmodifiable(mutableList);
    });

    final newIds = _favoriteSongs.map((song) => song.id).toList();

    try {
      if (_favoritesRepository.hasReorderSupport) {
        await _favoritesRepository.reorderFavorites(newIds);
      } else {
        await _favoritesRepository.saveFavorites(newIds);
      }
    } catch (_) {}
  }

  Future<void> _removeFavorite(Song song) async {
    try {
      await _favoritesRepository.removeFavorite(song.id);
    } catch (_) {}
  }

  Future<void> _addFavoritesToQueue() async {
    final l10n = AppLocalizations.of(context)!;

    if (_favoriteSongs.isEmpty) {
      return;
    }

    final playerController = context.read<PlayerController>();

    final hasQueue = playerController.queue.isNotEmpty;

    if (hasQueue) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(l10n.addAllToQueue),
            content: Text(l10n.queueContainsSongs),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(false);
                },
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      if (confirmed != true || !mounted) {
        return;
      }
    }

    final favoriteSongs = List<Song>.from(_favoriteSongs);

    await playerController.playFromQueue(favoriteSongs, startIndex: 0);
  }

  String get _categoryTitle {
    final l10n = AppLocalizations.of(context)!;

    switch (_selectedCategory) {
      case LibraryCategory.songs:
        return l10n.music;

      case LibraryCategory.albums:
        return l10n.albums;

      case LibraryCategory.artists:
        return l10n.artists;

      case LibraryCategory.podcasts:
        return l10n.podcasts;

      case LibraryCategory.playlists:
        return l10n.playlists;

      case LibraryCategory.favorites:
        return l10n.favorites;
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        // ignore: deprecated_member_use
        cacheExtent: 500,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _LibraryHeader(
                selectedCategory: _selectedCategory,
                categoryTitle: _categoryTitle,
                titleLarge: textTheme.titleLarge,
                onSelectCategory: _selectCategory,
              ),
            ),
          ),
          _buildCategoryContent(),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildCategoryContent() {
    if (_isLoading &&
        _songs.isEmpty &&
        _selectedCategory != LibraryCategory.playlists) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    switch (_selectedCategory) {
      case LibraryCategory.songs:
        return _buildSongsContent();

      case LibraryCategory.albums:
        return _buildAlbumsContent();

      case LibraryCategory.artists:
        return _buildArtistsContent();

      case LibraryCategory.podcasts:
        return _buildPodcastsContent();

      case LibraryCategory.playlists:
        return _buildPlaylistsContent();

      case LibraryCategory.favorites:
        return _buildFavoritesContent();
    }
  }

  Widget _buildSongsContent() {
    final musicSongs = _songs
        .where((song) {
          final path = song.filePath.replaceAll('\\\\', '/').toLowerCase();
          return !path.contains('/podcast/');
        })
        .toList(growable: false);

    if (musicSongs.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: _EmptyLibraryState(
            isScanning: _isScanning,
            onScan: _scanMusic,
          ),
        ),
      );
    }

    return _SongsSliverList(
      songs: musicSongs,
      isScanning: _isScanning,
      onScan: _scanMusic,
    );
  }

  Widget _buildFavoritesContent() {
    if (_favoriteSongs.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: _EmptyFavoritesState(
            onScan: _scanMusic,
            isScanning: _isScanning,
          ),
        ),
      );
    }

    return _FavoritesSliverList(
      songs: _favoriteSongs,
      isReordering: _isReorderingFavorites,
      onReorder: _reorderFavorites,
      onAddToQueue: _addFavoritesToQueue,
      onToggleReorder: _toggleReorderingFavorites,
      onRemoveFavorite: _removeFavorite,
    );
  }

  Widget _buildAlbumsContent() {
    final l10n = AppLocalizations.of(context)!;

    if (_albums.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text(l10n.noAlbums)),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: _albums.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemBuilder: (context, index) {
          final album = _albums[index];

          return _AlbumListTile(
            album: album,
            displayName: _displayAlbumName(context, album.name),
            onTap: () => _openAlbum(album),
          );
        },
      ),
    );
  }

  Widget _buildPodcastsContent() {
    final l10n = AppLocalizations.of(context)!;

    if (_podcasts.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text(l10n.noPodcasts)),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: _podcasts.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemBuilder: (context, index) {
          final podcast = _podcasts[index];
          return _AlbumListTile(
            album: podcast,
            displayName: podcast.name,
            onTap: () => _openPodcast(podcast),
            fallbackIcon: Icons.podcasts,
          );
        },
      ),
    );
  }

  Widget _buildArtistsContent() {
    final l10n = AppLocalizations.of(context)!;

    if (_artists.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text(l10n.noArtists)),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: _artists.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemBuilder: (context, index) {
          final artist = _artists[index];

          return _ArtistListTile(
            artist: artist,
            displayName: _displayArtistName(context, artist.name),
            onTap: () => _openArtist(artist),
          );
        },
      ),
    );
  }

  Widget _buildPlaylistsContent() {
    if (_playlists.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: _PlaylistsHeader(
                playlistCount: 0,
                onCreatePlaylist: _createPlaylist,
                onImportPlaylist: _importPlaylist,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            const SliverToBoxAdapter(child: _EmptyPlaylistsState()),
          ],
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: _PlaylistsHeader(
              playlistCount: _playlists.length,
              onCreatePlaylist: _createPlaylist,
              onImportPlaylist: _importPlaylist,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverList.builder(
            itemCount: _playlists.length,
            itemBuilder: (context, index) {
              final playlist = _playlists[index];

              final songs = _resolvePlaylistSongs(playlist);

              return _PlaylistListTile(
                playlist: playlist,
                songs: songs,
                onTap: () => _openPlaylist(playlist),
                onRename: () => _renamePlaylist(playlist),
                onExport: () => _exportPlaylist(playlist),
                onDelete: () => _deletePlaylist(playlist),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ANCHORED POPUP MENU
// ============================================================

Future<T?> _showAnchoredMenu<T>({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<PopupMenuEntry<T>> items,
}) async {
  final anchorContext = anchorKey.currentContext;

  if (anchorContext == null) {
    return null;
  }

  final renderObject = anchorContext.findRenderObject();

  if (renderObject is! RenderBox) {
    return null;
  }

  final overlayRenderObject = Overlay.of(context).context.findRenderObject();

  if (overlayRenderObject is! RenderBox) {
    return null;
  }

  final anchorTopLeft = renderObject.localToGlobal(
    Offset.zero,
    ancestor: overlayRenderObject,
  );

  final anchorRect = anchorTopLeft & renderObject.size;

  final overlaySize = overlayRenderObject.size;

  final position = RelativeRect.fromLTRB(
    anchorRect.right - 8,
    anchorRect.bottom + 4,
    overlaySize.width - anchorRect.right + 8,
    overlaySize.height - anchorRect.bottom,
  );

  return showMenu<T>(
    context: context,
    position: position,
    elevation: 5,
    color: Theme.of(context).colorScheme.surfaceContainer,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.black26,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        // ignore: deprecated_member_use
        color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.45),
      ),
    ),
    menuPadding: const EdgeInsets.symmetric(vertical: 6),
    items: items,
  );
}

// ============================================================
// PLAYLIST POPUP ITEM
// ============================================================

class _PlaylistPopupItem extends PopupMenuEntry<_PlaylistMenuAction> {
  final _PlaylistMenuAction value;
  final IconData icon;
  final String label;
  final Color? iconColor;
  final Color? textColor;

  const _PlaylistPopupItem({
    required this.value,
    required this.icon,
    required this.label,
    this.iconColor,
    this.textColor,
  });

  @override
  double get height => 52;

  @override
  bool represents(_PlaylistMenuAction? value) {
    return value == this.value;
  }

  @override
  State<_PlaylistPopupItem> createState() => _PlaylistPopupItemState();
}

class _PlaylistPopupItemState extends State<_PlaylistPopupItem> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final foregroundColor = widget.textColor ?? colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).pop(widget.value);
          },
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(widget.icon, color: widget.iconColor ?? foregroundColor),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: foregroundColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HEADER
// ============================================================

class _LibraryHeader extends StatelessWidget {
  final LibraryCategory selectedCategory;
  final String categoryTitle;
  final TextStyle? titleLarge;
  final ValueChanged<LibraryCategory> onSelectCategory;

  const _LibraryHeader({
    required this.selectedCategory,
    required this.categoryTitle,
    required this.titleLarge,
    required this.onSelectCategory,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.explore,
          style: titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _LibraryCategories(
          selectedCategory: selectedCategory,
          onSelectCategory: onSelectCategory,
        ),
        const SizedBox(height: 32),
        Text(
          categoryTitle,
          style: titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _LibraryCategories extends StatelessWidget {
  final LibraryCategory selectedCategory;
  final ValueChanged<LibraryCategory> onSelectCategory;

  const _LibraryCategories({
    required this.selectedCategory,
    required this.onSelectCategory,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _LibraryCategoryButton(
          icon: Icons.music_note,
          label: l10n.songs,
          isSelected: selectedCategory == LibraryCategory.songs,
          onPressed: () {
            onSelectCategory(LibraryCategory.songs);
          },
        ),
        _LibraryCategoryButton(
          icon: Icons.album_outlined,
          label: l10n.albums,
          isSelected: selectedCategory == LibraryCategory.albums,
          onPressed: () {
            onSelectCategory(LibraryCategory.albums);
          },
        ),
        _LibraryCategoryButton(
          icon: Icons.person_outline,
          label: l10n.artists,
          isSelected: selectedCategory == LibraryCategory.artists,
          onPressed: () {
            onSelectCategory(LibraryCategory.artists);
          },
        ),
        _LibraryCategoryButton(
          icon: Icons.podcasts,
          label: l10n.podcasts,
          isSelected: selectedCategory == LibraryCategory.podcasts,
          onPressed: () {
            onSelectCategory(LibraryCategory.podcasts);
          },
        ),
        _LibraryCategoryButton(
          icon: Icons.playlist_play,
          label: l10n.playlists,
          isSelected: selectedCategory == LibraryCategory.playlists,
          onPressed: () {
            onSelectCategory(LibraryCategory.playlists);
          },
        ),
        _LibraryCategoryButton(
          icon: Icons.favorite,
          label: l10n.favorites,
          isSelected: selectedCategory == LibraryCategory.favorites,
          onPressed: () {
            onSelectCategory(LibraryCategory.favorites);
          },
        ),
      ],
    );
  }
}

class _LibraryCategoryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  const _LibraryCategoryButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 19,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// EMPTY STATES
// ============================================================

class _EmptyLibraryState extends StatelessWidget {
  final bool isScanning;
  final VoidCallback onScan;

  const _EmptyLibraryState({required this.isScanning, required this.onScan});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_music_outlined,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.libraryEmptyTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.libraryEmptyDescription, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              l10n.scanDurationHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: isScanning ? null : onScan,
              icon: isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open),
              label: Text(isScanning ? l10n.scanning : l10n.scanMusic),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFavoritesState extends StatelessWidget {
  final bool isScanning;
  final VoidCallback onScan;

  const _EmptyFavoritesState({required this.isScanning, required this.onScan});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 48, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              l10n.noFavoritesTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.noFavoritesDescription, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SONGS
// ============================================================

class _SongsSliverList extends StatelessWidget {
  final List<Song> songs;
  final bool isScanning;
  final VoidCallback onScan;

  const _SongsSliverList({
    required this.songs,
    required this.isScanning,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: _SongsHeader(
              songCount: songs.length,
              isScanning: isScanning,
              onScan: onScan,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
          SliverList.builder(
            itemCount: songs.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemBuilder: (context, index) {
              final song = songs[index];

              return _LibrarySongCard(key: ValueKey(song.id), song: song);
            },
          ),
        ],
      ),
    );
  }
}

class _LibrarySongCard extends StatelessWidget {
  final Song song;

  const _LibrarySongCard({super.key, required this.song});

  Future<void> _handleSongTap(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    final playerController = context.read<PlayerController>();

    final queue = playerController.queue;

    final isCurrentSong = playerController.currentSong?.id == song.id;

    if (queue.isEmpty) {
      await playerController.playSong(song);
      return;
    }

    final isInQueue = playerController.isInQueue(song.id);

    final action = await showDialog<_SongTapAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.playback),
          content: Text(
            isCurrentSong
                ? l10n.currentlyPlaying
                : isInQueue
                ? l10n.songAlreadyInQueue
                : l10n.queueContainsSongs,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_SongTapAction.cancel);
              },
              child: Text(l10n.cancel),
            ),
            if (!isCurrentSong)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(
                    isInQueue
                        ? _SongTapAction.removeFromQueue
                        : _SongTapAction.addToQueue,
                  );
                },
                child: Text(isInQueue ? l10n.removeFromQueue : l10n.addToQueue),
              ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_SongTapAction.replaceQueue);
              },
              child: Text(l10n.replaceQueue),
            ),
          ],
        );
      },
    );

    if (!context.mounted || action == null || action == _SongTapAction.cancel) {
      return;
    }

    switch (action) {
      case _SongTapAction.replaceQueue:
        await playerController.clearQueue();
        await playerController.playSong(song);
        break;

      case _SongTapAction.addToQueue:
        if (!playerController.isInQueue(song.id)) {
          await playerController.addToQueue(song);
        }
        break;

      case _SongTapAction.removeFromQueue:
        if (playerController.currentSong?.id != song.id) {
          playerController.removeFromQueue(song);
        }
        break;

      case _SongTapAction.cancel:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final artist = song.artist?.trim() ?? '';

    final hasArtist = artist.isNotEmpty;

    return Selector<
      PlayerController,
      ({bool isCurrentSong, String? coverPath, Uint8List? coverBytes})
    >(
      selector: (_, controller) {
        final currentSong = controller.currentSong;

        final isCurrentSong = currentSong?.id == song.id;

        final effectiveCoverPath = isCurrentSong
            ? currentSong?.coverPath
            : song.coverPath;

        final effectiveCoverBytes = isCurrentSong
            ? currentSong?.coverBytes
            : song.coverBytes;

        return (
          isCurrentSong: isCurrentSong,
          coverPath: effectiveCoverPath,
          coverBytes: effectiveCoverBytes,
        );
      },
      builder: (context, state, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: InkWell(
            onTap: () => _handleSongTap(context),
            onLongPress: () {
              SongOptions.show(context, song);
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  _LibraryArtwork(
                    key: ValueKey(
                      '${song.id}_'
                      '${state.coverPath ?? 'no_path'}_'
                      '${state.coverBytes?.hashCode ?? 0}',
                    ),
                    coverPath: state.coverPath,
                    coverBytes: state.coverBytes,
                    size: 48,
                    borderRadius: 14,
                    isPlaying: state.isCurrentSong,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: state.isCurrentSong
                                ? colorScheme.primary
                                : null,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          hasArtist ? artist : l10n.unknownArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(song.duration),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Builder(
                    builder: (buttonContext) {
                      return Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            SongOptions.show(
                              context,
                              song,
                              anchorContext: buttonContext,
                            );
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(Icons.more_vert),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// FAVORITES
// ============================================================

class _FavoritesSliverList extends StatelessWidget {
  final List<Song> songs;
  final bool isReordering;
  final ReorderCallback onReorder;
  final VoidCallback onAddToQueue;
  final VoidCallback onToggleReorder;
  final Future<void> Function(Song song) onRemoveFavorite;

  const _FavoritesSliverList({
    required this.songs,
    required this.isReordering,
    required this.onReorder,
    required this.onAddToQueue,
    required this.onToggleReorder,
    required this.onRemoveFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: songs.isNotEmpty ? onAddToQueue : null,
                    icon: const Icon(Icons.queue_music),
                    label: Text(l10n.addAllToQueue),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: songs.isNotEmpty ? onToggleReorder : null,
                  icon: Icon(isReordering ? Icons.check : Icons.swap_vert),
                  label: Text(isReordering ? l10n.done : l10n.changeOrder),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverReorderableList(
            itemCount: songs.length,
            // ignore: deprecated_member_use
            onReorder: onReorder,
            itemBuilder: (context, index) {
              final song = songs[index];

              Widget child = _FavoriteSongCard(
                key: ValueKey(song.id),
                song: song,
                isReordering: isReordering,
                reorderIndex: index,
              );

              if (!isReordering) {
                child = Dismissible(
                  key: ValueKey('favorite_${song.id}'),
                  direction: DismissDirection.startToEnd,
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    color: Theme.of(context).colorScheme.error,
                    child: Icon(
                      Icons.remove_circle_outline,
                      color: Theme.of(context).colorScheme.onError,
                    ),
                  ),
                  confirmDismiss: (_) async {
                    return await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) {
                            return AlertDialog(
                              title: Text(l10n.removeFromFavorites),
                              content: Text(
                                l10n.removeFromFavoritesQuestion(song.title),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(dialogContext).pop(false);
                                  },
                                  child: Text(l10n.cancel),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    Navigator.of(dialogContext).pop(true);
                                  },
                                  child: Text(l10n.remove),
                                ),
                              ],
                            );
                          },
                        ) ??
                        false;
                  },
                  onDismissed: (_) async {
                    await onRemoveFavorite(song);
                  },
                  child: child,
                );
              }

              return child;
            },
          ),
        ],
      ),
    );
  }
}

class _FavoriteSongCard extends StatelessWidget {
  final Song song;
  final bool isReordering;
  final int reorderIndex;

  const _FavoriteSongCard({
    super.key,
    required this.song,
    required this.isReordering,
    required this.reorderIndex,
  });

  Future<void> _handleSongTap(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    final playerController = context.read<PlayerController>();

    final queue = playerController.queue;

    final isCurrentSong = playerController.currentSong?.id == song.id;

    if (queue.isEmpty) {
      await playerController.playSong(song);
      return;
    }

    final isInQueue = playerController.isInQueue(song.id);

    final action = await showDialog<_SongTapAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.playback),
          content: Text(
            isCurrentSong
                ? l10n.currentlyPlaying
                : isInQueue
                ? l10n.songAlreadyInQueue
                : l10n.queueContainsSongs,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_SongTapAction.cancel);
              },
              child: Text(l10n.cancel),
            ),
            if (!isCurrentSong)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(
                    isInQueue
                        ? _SongTapAction.removeFromQueue
                        : _SongTapAction.addToQueue,
                  );
                },
                child: Text(isInQueue ? l10n.removeFromQueue : l10n.addToQueue),
              ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_SongTapAction.replaceQueue);
              },
              child: Text(l10n.replaceQueue),
            ),
          ],
        );
      },
    );

    if (!context.mounted || action == null || action == _SongTapAction.cancel) {
      return;
    }

    switch (action) {
      case _SongTapAction.replaceQueue:
        await playerController.clearQueue();
        await playerController.playSong(song);
        break;

      case _SongTapAction.addToQueue:
        if (!playerController.isInQueue(song.id)) {
          await playerController.addToQueue(song);
        }
        break;

      case _SongTapAction.removeFromQueue:
        if (playerController.currentSong?.id != song.id) {
          playerController.removeFromQueue(song);
        }
        break;

      case _SongTapAction.cancel:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final artist = song.artist?.trim() ?? '';
    final hasArtist = artist.isNotEmpty;

    return Selector<
      PlayerController,
      ({bool isCurrentSong, String? coverPath, Uint8List? coverBytes})
    >(
      selector: (_, controller) {
        final currentSong = controller.currentSong;

        final isCurrentSong = currentSong?.id == song.id;

        final effectiveCoverPath = isCurrentSong
            ? currentSong?.coverPath
            : song.coverPath;

        final effectiveCoverBytes = isCurrentSong
            ? currentSong?.coverBytes
            : song.coverBytes;

        return (
          isCurrentSong: isCurrentSong,
          coverPath: effectiveCoverPath,
          coverBytes: effectiveCoverBytes,
        );
      },
      builder: (context, state, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Material(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            elevation: isReordering ? 1 : 0,
            child: InkWell(
              onTap: isReordering ? null : () => _handleSongTap(context),
              onLongPress: isReordering
                  ? null
                  : () {
                      SongOptions.show(context, song);
                    },
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    _LibraryArtwork(
                      key: ValueKey(
                        '${song.id}_'
                        '${state.coverPath ?? 'no_path'}_'
                        '${state.coverBytes?.hashCode ?? 0}',
                      ),
                      coverPath: state.coverPath,
                      coverBytes: state.coverBytes,
                      size: 48,
                      borderRadius: 14,
                      isPlaying: state.isCurrentSong,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: state.isCurrentSong
                                  ? colorScheme.primary
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            hasArtist ? artist : l10n.unknownArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!isReordering) ...[
                      Text(
                        _formatDuration(song.duration),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Builder(
                        builder: (buttonContext) {
                          return Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                SongOptions.show(
                                  context,
                                  song,
                                  anchorContext: buttonContext,
                                );
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: const SizedBox(
                                width: 44,
                                height: 44,
                                child: Icon(Icons.more_vert),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    if (isReordering)
                      ReorderableDragStartListener(
                        index: reorderIndex,
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(child: Icon(Icons.drag_handle)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SongsHeader extends StatelessWidget {
  final int songCount;
  final bool isScanning;
  final VoidCallback onScan;

  const _SongsHeader({
    required this.songCount,
    required this.isScanning,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.songsFound(songCount),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          onPressed: isScanning ? null : onScan,
          icon: isScanning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: l10n.updateList,
        ),
      ],
    );
  }
}

// ============================================================
// PLAYLIST HEADER
// ============================================================

class _PlaylistsHeader extends StatefulWidget {
  final int playlistCount;
  final VoidCallback onCreatePlaylist;
  final VoidCallback onImportPlaylist;

  const _PlaylistsHeader({
    required this.playlistCount,
    required this.onCreatePlaylist,
    required this.onImportPlaylist,
  });

  @override
  State<_PlaylistsHeader> createState() => _PlaylistsHeaderState();
}

class _PlaylistsHeaderState extends State<_PlaylistsHeader> {
  final GlobalKey _menuKey = GlobalKey();

  Future<void> _showPlaylistActions() async {
    final l10n = AppLocalizations.of(context)!;

    final action = await _showAnchoredMenu<_PlaylistMenuAction>(
      context: context,
      anchorKey: _menuKey,
      items: [
        _PlaylistPopupItem(
          value: _PlaylistMenuAction.create,
          icon: Icons.add,
          label: l10n.newPlaylist,
        ),
        _PlaylistPopupItem(
          value: _PlaylistMenuAction.import,
          icon: Icons.file_upload_outlined,
          label: l10n.importPlaylist,
        ),
      ],
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _PlaylistMenuAction.create:
        widget.onCreatePlaylist();
        break;

      case _PlaylistMenuAction.import:
        widget.onImportPlaylist();
        break;

      case _PlaylistMenuAction.rename:
      case _PlaylistMenuAction.export:
      case _PlaylistMenuAction.delete:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            AppLocalizations.of(context)!.playlistCount(widget.playlistCount),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Material(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: _menuKey,
            onTap: _showPlaylistActions,
            borderRadius: BorderRadius.circular(16),
            child: const SizedBox(
              width: 46,
              height: 46,
              child: Icon(Icons.add),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// EMPTY PLAYLISTS
// ============================================================

class _EmptyPlaylistsState extends StatelessWidget {
  const _EmptyPlaylistsState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.playlist_play, size: 48, color: colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                l10n.noPlaylistsTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(l10n.noPlaylistsDescription, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PLAYLIST TILE
// ============================================================

class _PlaylistListTile extends StatefulWidget {
  final Playlist playlist;
  final List<Song> songs;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _PlaylistListTile({
    required this.playlist,
    required this.songs,
    required this.onTap,
    required this.onRename,
    required this.onExport,
    required this.onDelete,
  });

  @override
  State<_PlaylistListTile> createState() => _PlaylistListTileState();
}

class _PlaylistListTileState extends State<_PlaylistListTile> {
  final GlobalKey _menuKey = GlobalKey();

  Future<void> _showPlaylistMenu() async {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    final action = await _showAnchoredMenu<_PlaylistMenuAction>(
      context: context,
      anchorKey: _menuKey,
      items: [
        _PlaylistPopupItem(
          value: _PlaylistMenuAction.rename,
          icon: Icons.edit_outlined,
          label: l10n.renamePlaylist,
        ),
        _PlaylistPopupItem(
          value: _PlaylistMenuAction.export,
          icon: Icons.file_download_outlined,
          label: l10n.exportPlaylist,
        ),
        _PlaylistPopupItem(
          value: _PlaylistMenuAction.delete,
          icon: Icons.delete_outline,
          label: l10n.remove,
          iconColor: colorScheme.error,
          textColor: colorScheme.error,
        ),
      ],
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _PlaylistMenuAction.rename:
        widget.onRename();
        break;

      case _PlaylistMenuAction.export:
        widget.onExport();
        break;

      case _PlaylistMenuAction.delete:
        widget.onDelete();
        break;

      case _PlaylistMenuAction.create:
      case _PlaylistMenuAction.import:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final firstSong = widget.songs.isNotEmpty ? widget.songs.first : null;

    final coverPath = firstSong?.coverPath;

    final coverBytes = firstSong?.coverBytes;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: _showPlaylistMenu,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                _LibraryArtwork(
                  key: ValueKey(
                    '${widget.playlist.id}_'
                    '${coverPath ?? 'no_cover'}_'
                    '${coverBytes?.hashCode ?? 0}',
                  ),
                  coverPath: coverPath,
                  coverBytes: coverBytes,
                  size: 48,
                  borderRadius: 14,
                  fallbackIcon: Icons.playlist_play,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.songCount(widget.songs.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: _menuKey,
                    onTap: _showPlaylistMenu,
                    borderRadius: BorderRadius.circular(14),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.more_vert),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ALBUM
// ============================================================

class _AlbumListTile extends StatelessWidget {
  final Album album;
  final String displayName;
  final VoidCallback onTap;
  final IconData fallbackIcon;

  const _AlbumListTile({
    required this.album,
    required this.displayName,
    required this.onTap,
    this.fallbackIcon = Icons.album_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final artist = album.artist?.trim();

    final displayArtist = artist != null && artist.isNotEmpty
        ? artist == _unknownArtistKey
              ? l10n.unknownArtist
              : artist
        : null;

    final firstSong = album.songs.isNotEmpty ? album.songs.first : null;

    final coverPath = firstSong?.coverPath;

    final coverBytes = firstSong?.coverBytes;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                _LibraryArtwork(
                  key: ValueKey(
                    '${album.name}_'
                    '${coverPath ?? 'no_cover'}_'
                    '${coverBytes?.hashCode ?? 0}',
                  ),
                  coverPath: coverPath,
                  coverBytes: coverBytes,
                  size: 48,
                  borderRadius: 14,
                  fallbackIcon: fallbackIcon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        displayArtist != null
                            ? '$displayArtist · ${l10n.songCount(album.songCount)}'
                            : l10n.songCount(album.songCount),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(child: Icon(Icons.chevron_right)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ARTIST
// ============================================================

class _ArtistListTile extends StatelessWidget {
  final Artist artist;
  final String displayName;
  final VoidCallback onTap;

  const _ArtistListTile({
    required this.artist,
    required this.displayName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final firstSong = artist.songs.isNotEmpty ? artist.songs.first : null;

    final coverPath = firstSong?.coverPath;

    final coverBytes = firstSong?.coverBytes;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                _LibraryArtwork(
                  key: ValueKey(
                    '${artist.name}_'
                    '${coverPath ?? 'no_cover'}_'
                    '${coverBytes?.hashCode ?? 0}',
                  ),
                  coverPath: coverPath,
                  coverBytes: coverBytes,
                  size: 48,
                  borderRadius: 24,
                  fallbackIcon: Icons.person_outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.songCount(artist.songCount),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(child: Icon(Icons.chevron_right)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// LIBRARY ARTWORK
// ============================================================

class _LibraryArtwork extends StatelessWidget {
  final String? coverPath;
  final Uint8List? coverBytes;
  final double size;
  final double borderRadius;
  final IconData fallbackIcon;
  final bool isPlaying;

  const _LibraryArtwork({
    super.key,
    required this.coverPath,
    required this.coverBytes,
    required this.size,
    required this.borderRadius,
    this.fallbackIcon = Icons.music_note,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = coverBytes;

    if (bytes != null && bytes.isNotEmpty) {
      return Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: 128,
              cacheHeight: 128,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                return _buildFallback(context);
              },
            ),
          ),
          if (isPlaying)
            _PlayingOverlay(size: size, borderRadius: borderRadius),
        ],
      );
    }

    final path = coverPath;

    if (path == null || path.isEmpty) {
      return _buildFallback(context);
    }

    if (path.startsWith('content://')) {
      return _AndroidLibraryArtwork(
        key: ValueKey(path),
        uri: path,
        size: size,
        borderRadius: borderRadius,
        fallbackIcon: fallbackIcon,
        isPlaying: isPlaying,
      );
    }

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: Image.network(
              path,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: 128,
              cacheHeight: 128,
              filterQuality: FilterQuality.low,
              errorBuilder: (context, error, stackTrace) {
                return _buildFallback(context);
              },
            ),
          ),
          if (isPlaying)
            _PlayingOverlay(size: size, borderRadius: borderRadius),
        ],
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Image.file(
            File(path),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: 128,
            cacheHeight: 128,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return _buildFallback(context);
            },
          ),
        ),
        if (isPlaying) _PlayingOverlay(size: size, borderRadius: borderRadius),
      ],
    );
  }

  Widget _buildFallback(BuildContext context) {
    final iconColor = isPlaying
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(
          isPlaying ? Icons.graphic_eq : fallbackIcon,
          size: size * 0.48,
          color: iconColor,
        ),
      ),
    );
  }
}

// ============================================================
// ANDROID CONTENT URI ARTWORK
// ============================================================

class _AndroidLibraryArtwork extends StatefulWidget {
  final String uri;
  final double size;
  final double borderRadius;
  final IconData fallbackIcon;
  final bool isPlaying;

  const _AndroidLibraryArtwork({
    super.key,
    required this.uri,
    required this.size,
    required this.borderRadius,
    required this.fallbackIcon,
    required this.isPlaying,
  });

  @override
  State<_AndroidLibraryArtwork> createState() => _AndroidLibraryArtworkState();
}

class _AndroidLibraryArtworkState extends State<_AndroidLibraryArtwork> {
  static const MethodChannel _channel = MethodChannel('sonara/media_store');

  static final Map<String, Uint8List?> _coverCache = {};

  static final Map<String, Future<Uint8List?>> _loadingCache = {};

  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(covariant _AndroidLibraryArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.uri != widget.uri) {
      _bytes = null;
      _loading = true;
      _loadCover();
    }
  }

  Future<void> _loadCover() async {
    final uri = widget.uri;

    if (_coverCache.containsKey(uri)) {
      if (mounted) {
        setState(() {
          _bytes = _coverCache[uri];
          _loading = false;
        });
      }

      return;
    }

    try {
      final future = _loadingCache.putIfAbsent(uri, () async {
        try {
          final result = await _channel.invokeMethod<dynamic>(
            'readContentUri',
            <String, dynamic>{'uri': uri},
          );

          if (result is Uint8List) {
            return result;
          }

          if (result is List) {
            return Uint8List.fromList(result.cast<int>());
          }

          return null;
        } catch (_) {
          return null;
        } finally {
          _loadingCache.remove(uri);
        }
      });

      final bytes = await future;

      _coverCache[uri] = bytes;

      if (mounted) {
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;

    if (bytes == null || bytes.isEmpty) {
      if (_loading) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }

      return _buildFallback(context);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Image.memory(
            bytes,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            cacheWidth: 128,
            cacheHeight: 128,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return _buildFallback(context);
            },
          ),
        ),
        if (widget.isPlaying)
          _PlayingOverlay(size: widget.size, borderRadius: widget.borderRadius),
      ],
    );
  }

  Widget _buildFallback(BuildContext context) {
    final iconColor = widget.isPlaying
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: Icon(
          widget.isPlaying ? Icons.graphic_eq : widget.fallbackIcon,
          size: widget.size * 0.48,
          color: iconColor,
        ),
      ),
    );
  }
}

// ============================================================
// PLAYING OVERLAY
// ============================================================

class _PlayingOverlay extends StatelessWidget {
  final double size;
  final double borderRadius;

  const _PlayingOverlay({required this.size, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        Icons.graphic_eq,
        color: Theme.of(context).colorScheme.primary,
        size: size * 0.5,
      ),
    );
  }
}

// ============================================================
// UTILS
// ============================================================

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;

  final minutes = totalSeconds ~/ 60;

  final seconds = totalSeconds % 60;

  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
