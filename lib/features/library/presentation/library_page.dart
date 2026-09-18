import 'dart:io';
import 'dart:typed_data';

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

enum LibraryCategory { songs, albums, artists, playlists, favorites }

const double _kSongTileExtent = 73.0;

const String _noAlbumKey = '__sonara_no_album__';
const String _unknownArtistKey = '__sonara_unknown_artist__';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final LocalLibraryRepository _repository = LocalLibraryRepository();
  final PlaylistsRepository _playlistsRepository = PlaylistsRepository();
  final FavoritesRepository _favoritesRepository = FavoritesRepository();

  List<Song> _songs = const [];
  List<Song> _favoriteSongs = const [];
  List<Album> _albums = const [];
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

    _playlistsRepository.addListener(_handlePlaylistsChanged);
    _favoritesRepository.addListener(_handleFavoritesChanged);

    _loadLibrary();
    _loadPlaylists();
    _loadFavorites();
  }

  @override
  void dispose() {
    _playlistsRepository.removeListener(_handlePlaylistsChanged);
    _favoritesRepository.removeListener(_handleFavoritesChanged);

    super.dispose();
  }

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

      setState(() {
        _hasLoaded = true;
        _isLoading = false;
        _isScanning = false;
      });

      await _loadFavorites();
    } catch (_) {
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

    for (final song in _songs) {
      final rawAlbum = song.album?.trim();
      final albumName = (rawAlbum != null && rawAlbum.isNotEmpty)
          ? rawAlbum
          : _noAlbumKey;

      final rawArtist = song.artist?.trim();
      final artistName = (rawArtist != null && rawArtist.isNotEmpty)
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

    _albums = List.unmodifiable(albums);
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

      case LibraryCategory.playlists:
        return l10n.playlists;

      case LibraryCategory.favorites:
        return l10n.favorites;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: CustomScrollView(
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

      case LibraryCategory.playlists:
        return _buildPlaylistsContent();

      case LibraryCategory.favorites:
        return _buildFavoritesContent();
    }
  }

  Widget _buildSongsContent() {
    if (_songs.isEmpty) {
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
      songs: _songs,
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
      sliver: SliverList.separated(
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
        separatorBuilder: (_, __) {
          return const Divider(height: 1);
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
      sliver: SliverList.separated(
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
        separatorBuilder: (_, __) {
          return const Divider(height: 1);
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
          SliverList.separated(
            itemCount: _playlists.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
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
            separatorBuilder: (_, __) {
              return const Divider(height: 1);
            },
          ),
        ],
      ),
    );
  }
}

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
        Text(l10n.explore, style: titleLarge),
        const SizedBox(height: 12),
        _LibraryCategories(
          selectedCategory: selectedCategory,
          onSelectCategory: onSelectCategory,
        ),
        const SizedBox(height: 32),
        Text(categoryTitle, style: titleLarge),
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
    if (isSelected) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
    );
  }
}

class _EmptyLibraryState extends StatelessWidget {
  final bool isScanning;
  final VoidCallback onScan;

  const _EmptyLibraryState({required this.isScanning, required this.onScan});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              l10n.libraryEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.libraryEmptyDescription, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              l10n.scanDurationHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_border, size: 48),
            const SizedBox(height: 16),
            Text(
              l10n.noFavoritesTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.noFavoritesDescription, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

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
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverFixedExtentList.builder(
            itemCount: songs.length,
            itemExtent: _kSongTileExtent,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemBuilder: (context, index) {
              final song = songs[index];
              final isLast = index == songs.length - 1;

              return _SongTileRow(
                key: ValueKey(song.id),
                song: song,
                showDivider: !isLast,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SongTileRow extends StatelessWidget {
  final Song song;
  final bool showDivider;

  const _SongTileRow({
    super.key,
    required this.song,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: dividerColor, width: 1))
            : null,
      ),
      child: _SongListTile(song: song),
    );
  }
}

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
    final theme = Theme.of(context);
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
            onReorder: onReorder,
            itemBuilder: (context, index) {
              final song = songs[index];

              final songTile = _SongListTile(
                song: song,
                isReorderable: isReordering,
                reorderIndex: index,
              );

              return Material(
                key: ValueKey(song.id),
                color: theme.scaffoldBackgroundColor,
                elevation: isReordering ? 2 : 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isReordering)
                      songTile
                    else
                      Dismissible(
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
                                      l10n.removeFromFavoritesQuestion(
                                        song.title,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(dialogContext)
                                              .pop(false);
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
                        child: songTile,
                      ),
                    if (index < songs.length - 1) const Divider(height: 1),
                  ],
                ),
              );
            },
          ),
        ],
      ),
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

    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.songsFound(songCount),
            style: Theme.of(context).textTheme.titleMedium,
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

class _SongListTile extends StatelessWidget {
  final Song song;
  final bool isReorderable;
  final int? reorderIndex;

  const _SongListTile({
    super.key,
    required this.song,
    this.isReorderable = false,
    this.reorderIndex,
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

    final artist = song.artist?.trim() ?? '';
    final hasArtist = artist.isNotEmpty;

    return Selector<PlayerController, bool>(
      selector: (_, controller) {
        return controller.currentSong?.id == song.id;
      },
      builder: (context, isCurrentSong, _) {
        final theme = Theme.of(context);

        return ListTile(
          onTap: isReorderable ? null : () => _handleSongTap(context),

          onLongPress: isReorderable
              ? null
              : () {
                  SongOptions.show(context, song);
                },

          contentPadding: const EdgeInsets.only(left: 12, right: 0),

          leading: _LibraryArtwork(
            coverPath: song.coverPath,
            size: 40,
            borderRadius: 6,
            isPlaying: isCurrentSong,
          ),

          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: isCurrentSong
                ? theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  )
                : null,
          ),

          subtitle: Text(
            hasArtist ? artist : l10n.noAlbum,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isReorderable) ...[
                Text(
                  _formatDuration(song.duration),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () {
                    SongOptions.show(context, song);
                  },
                  icon: const Icon(Icons.more_vert),
                  tooltip: l10n.options,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
              if (isReorderable && reorderIndex != null)
                ReorderableDragStartListener(
                  index: reorderIndex!,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

enum _SongTapAction { replaceQueue, addToQueue, removeFromQueue, cancel }

class _PlaylistsHeader extends StatelessWidget {
  final int playlistCount;
  final VoidCallback onCreatePlaylist;
  final VoidCallback onImportPlaylist;

  const _PlaylistsHeader({
    required this.playlistCount,
    required this.onCreatePlaylist,
    required this.onImportPlaylist,
  });

  void _showPlaylistActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(l10n.newPlaylist),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onCreatePlaylist();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: Text(l10n.importPlaylist),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onImportPlaylist();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.playlistCount(playlistCount),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          onPressed: () {
            _showPlaylistActions(context);
          },
          icon: const Icon(Icons.add),
          tooltip: l10n.addPlaylist,
        ),
      ],
    );
  }
}

class _EmptyPlaylistsState extends StatelessWidget {
  const _EmptyPlaylistsState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.playlist_play, size: 48),
            const SizedBox(height: 16),
            Text(
              l10n.noPlaylistsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.noPlaylistsDescription, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _PlaylistListTile extends StatelessWidget {
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

  void _showPlaylistMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(l10n.renamePlaylist),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onRename();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: Text(l10n.exportPlaylist),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onExport();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text(
                    l10n.remove,
                    style: TextStyle(color: colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onDelete();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final coverPath = songs.isNotEmpty ? songs.first.coverPath : null;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 12,
      leading: _LibraryArtwork(
        coverPath: coverPath,
        size: 40,
        borderRadius: 6,
        fallbackIcon: Icons.playlist_play,
      ),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.songCount(songs.length)),
      trailing: IconButton(
        onPressed: () {
          _showPlaylistMenu(context);
        },
        icon: const Icon(Icons.more_vert),
        tooltip: l10n.options,
      ),
      onTap: onTap,
      onLongPress: () {
        _showPlaylistMenu(context);
      },
    );
  }
}

class _AlbumListTile extends StatelessWidget {
  final Album album;
  final String displayName;
  final VoidCallback onTap;

  const _AlbumListTile({
    required this.album,
    required this.displayName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final artist = album.artist;
    final hasArtist = artist != null && artist.trim().isNotEmpty;

    final coverPath = album.songs.isNotEmpty
        ? album.songs.first.coverPath
        : null;

    final displayArtist = hasArtist
        ? (artist == _unknownArtistKey ? l10n.unknownArtist : artist!)
        : null;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 12,
      leading: _LibraryArtwork(
        coverPath: coverPath,
        size: 40,
        borderRadius: 6,
        fallbackIcon: Icons.album_outlined,
      ),
      title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: displayArtist != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(l10n.songCount(album.songCount)),
              ],
            )
          : Text(l10n.songCount(album.songCount)),
      trailing: const SizedBox(
        width: 40,
        child: Center(child: Icon(Icons.chevron_right)),
      ),
      onTap: onTap,
    );
  }
}

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

    final coverPath = artist.songs.isNotEmpty
        ? artist.songs.first.coverPath
        : null;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 12,
      leading: _LibraryArtwork(
        coverPath: coverPath,
        size: 40,
        borderRadius: 6,
        fallbackIcon: Icons.person_outline,
      ),
      title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.songCount(artist.songCount)),
      trailing: const SizedBox(
        width: 40,
        child: Center(child: Icon(Icons.chevron_right)),
      ),
      onTap: onTap,
    );
  }
}

class _LibraryArtwork extends StatelessWidget {
  final String? coverPath;
  final double size;
  final double borderRadius;
  final IconData fallbackIcon;
  final bool isPlaying;

  const _LibraryArtwork({
    required this.coverPath,
    required this.size,
    required this.borderRadius,
    this.fallbackIcon = Icons.music_note,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
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

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;

  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
