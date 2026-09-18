import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../player/presentation/controllers/player_controller.dart';
import '../data/repositories/playlists_repository.dart';
import '../domain/models/song.dart';
import 'song_options.dart';

const double _kSongTileExtent = 62.0;

/// Caché global para las portadas obtenidas mediante content://
class _ArtworkMemoryCache {
  _ArtworkMemoryCache._();

  static const MethodChannel _mediaStoreChannel = MethodChannel(
    'sonara/media_store',
  );

  static final Map<String, Uint8List?> _cache = <String, Uint8List?>{};
  static final Map<String, Future<Uint8List?>> _pending =
      <String, Future<Uint8List?>>{};

  static bool isCached(String contentUri) => _cache.containsKey(contentUri);

  static Uint8List? getSync(String contentUri) => _cache[contentUri];

  static Future<Uint8List?> load(String contentUri) {
    if (_cache.containsKey(contentUri)) {
      return Future.value(_cache[contentUri]);
    }

    final existingRequest = _pending[contentUri];

    if (existingRequest != null) {
      return existingRequest;
    }

    final request = _load(contentUri);

    _pending[contentUri] = request;

    return request;
  }

  static Future<Uint8List?> _load(String contentUri) async {
    try {
      final result = await _mediaStoreChannel.invokeMethod<dynamic>(
        'readContentUri',
        <String, dynamic>{'uri': contentUri},
      );

      Uint8List? bytes;

      if (result is Uint8List) {
        bytes = result;
      } else if (result is List) {
        bytes = Uint8List.fromList(result.cast<int>());
      }

      _cache[contentUri] = bytes;

      return bytes;
    } catch (_) {
      _cache[contentUri] = null;
      return null;
    } finally {
      _pending.remove(contentUri);
    }
  }
}

class LibraryPlaylistPage extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<Song> songs;
  final IconData icon;
  final String? playlistId;

  const LibraryPlaylistPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.songs,
    required this.icon,
    this.playlistId,
  });

  @override
  State<LibraryPlaylistPage> createState() => _LibraryPlaylistPageState();
}

class _LibraryPlaylistPageState extends State<LibraryPlaylistPage>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  final GlobalKey<SliverAnimatedListState> _animatedListKey =
      GlobalKey<SliverAnimatedListState>();

  final PlaylistsRepository _playlistsRepository = PlaylistsRepository();

  late List<Song> _songs;
  late final bool _hasSubtitle;

  bool _isReordering = false;

  bool get _canReorder => widget.playlistId != null;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _playlistsRepository.addListener(_handlePlaylistsChanged);

    _songs = _resolveOrderedSongs();

    _hasSubtitle =
        widget.subtitle != null && widget.subtitle!.trim().isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant LibraryPlaylistPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.playlistId != widget.playlistId ||
        oldWidget.songs != widget.songs) {
      _songs = _resolveOrderedSongs();
    }
  }

  @override
  void dispose() {
    _playlistsRepository.removeListener(_handlePlaylistsChanged);

    _scrollController.dispose();

    super.dispose();
  }

  void _handlePlaylistsChanged() {
    if (!mounted) return;

    setState(() {
      _songs = _resolveOrderedSongs();

      if (_songs.isEmpty) {
        _isReordering = false;
      }
    });
  }

  List<Song> _resolveOrderedSongs() {
    final playlistId = widget.playlistId;

    if (playlistId == null) {
      return List<Song>.from(widget.songs);
    }

    final playlist = _playlistsRepository.getPlaylist(playlistId);

    if (playlist == null) {
      return [];
    }

    final songsById = <String, Song>{
      for (final song in widget.songs) song.id: song,
    };

    final updatedSongs = <Song>[];

    for (final songId in playlist.songIds) {
      final song = songsById[songId];

      if (song != null) {
        updatedSongs.add(song);
      }
    }

    return updatedSongs;
  }

  Future<void> _removeSongFromPlaylist(Song song) async {
    final playlistId = widget.playlistId;

    if (playlistId == null) return;

    final index = _songs.indexWhere((item) => item.id == song.id);

    if (index == -1) return;

    // Eliminamos inmediatamente de la lista visual.
    //
    // Esto es importante porque SliverAnimatedList necesita saber
    // inmediatamente qué elemento debe desaparecer.
    setState(() {
      _songs.removeAt(index);
    });

    // Animamos el cierre del espacio que ocupaba la canción.
    _animatedListKey.currentState?.removeItem(index, (context, animation) {
      return _buildAnimatedRemovedSong(song: song, animation: animation);
    }, duration: const Duration(milliseconds: 300));

    try {
      await _playlistsRepository.removeSongFromPlaylist(playlistId, song.id);
    } catch (_) {
      if (!mounted) return;

      // Si la operación falló, restauramos la canción
      // en su posición original.
      setState(() {
        if (index <= _songs.length) {
          _songs.insert(index, song);
        } else {
          _songs.add(song);
        }
      });

      _animatedListKey.currentState?.insertItem(
        index,
        duration: const Duration(milliseconds: 300),
      );

      final l10n = AppLocalizations.of(context)!;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.removeSongFromPlaylistError)));
    }
  }

  Widget _buildAnimatedRemovedSong({
    required Song song,
    required Animation<double> animation,
  }) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    );

    return SizeTransition(
      sizeFactor: curvedAnimation,
      axisAlignment: -1.0,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SizedBox(
          height: _kSongTileExtent,
          child: _buildSongTile(
            context,
            song,
            isReorderable: false,
            showDivider: false,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleReorder() async {
    if (!_canReorder) return;

    if (_isReordering) {
      final playlistId = widget.playlistId;

      if (playlistId != null) {
        final newSongIds = _songs
            .map((song) => song.id)
            .toList(growable: false);

        try {
          await _playlistsRepository.reorderSongs(playlistId, newSongIds);
        } catch (_) {
          if (mounted) {
            setState(() {
              _songs = _resolveOrderedSongs();
            });
          }
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _isReordering = !_isReordering;
    });
  }

  void _reorderSongs(int oldIndex, int newIndex) {
    if (!_canReorder) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final mutableList = List<Song>.from(_songs);

    final song = mutableList.removeAt(oldIndex);

    mutableList.insert(newIndex, song);

    setState(() {
      _songs = mutableList;
    });
  }

  Future<void> _playSong(PlayerController playerController, Song song) async {
    if (playerController.queue.isEmpty) {
      await playerController.playSongFromList([song], song);

      return;
    }

    if (!mounted) return;

    final l10n = AppLocalizations.of(context)!;

    final isInQueue = playerController.isInQueue(song.id);

    final isCurrentSong = playerController.currentSong?.id == song.id;

    final action = await showDialog<_QueueAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.playlistQueueTitle),
          content: Text(
            isCurrentSong
                ? l10n.currentlyPlaying
                : isInQueue
                ? l10n.songAlreadyInQueue
                : l10n.whatToDoWithSong,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_QueueAction.cancel);
              },
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: isCurrentSong
                  ? null
                  : () {
                      Navigator.of(
                        dialogContext,
                      ).pop(isInQueue ? _QueueAction.remove : _QueueAction.add);
                    },
              child: Text(isInQueue ? l10n.removeFromQueue : l10n.addToQueue),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_QueueAction.replace);
              },
              child: Text(l10n.clearQueue),
            ),
          ],
        );
      },
    );

    if (!mounted || action == null || action == _QueueAction.cancel) {
      return;
    }

    switch (action) {
      case _QueueAction.remove:
        if (!isCurrentSong) {
          playerController.removeFromQueue(song);
        }
        break;

      case _QueueAction.add:
        if (!playerController.isInQueue(song.id)) {
          await playerController.addToQueue(song);
        }
        break;

      case _QueueAction.replace:
        await playerController.clearQueue();

        await playerController.playSongFromList([song], song);
        break;

      case _QueueAction.cancel:
        break;
    }
  }

  Future<void> _addAllToQueue(PlayerController playerController) async {
    if (_songs.isEmpty) return;

    if (playerController.queue.isNotEmpty) {
      final l10n = AppLocalizations.of(context)!;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(l10n.addEntirePlaylist),
            content: Text(l10n.addEntirePlaylistDescription),
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
                child: Text(l10n.ok),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return;
    }

    await playerController.playSongFromList(_songs, _songs.first);

    if (_songs.length > 1) {
      playerController.addSongsToQueue(_songs.skip(1).toList(growable: false));
    }
  }

  Widget _buildDismissibleSong({required Song song, required Widget child}) {
    return Dismissible(
      key: ValueKey('dismiss_${song.id}'),
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
        final l10n = AppLocalizations.of(context)!;

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(l10n.removeFromPlaylist),
              content: Text(l10n.removeSongFromPlaylistQuestion(song.title)),
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

        return confirmed == true;
      },
      onDismissed: (_) {
        // No esperamos el Future aquí.
        //
        // _removeSongFromPlaylist() elimina inmediatamente
        // el elemento de _songs y después actualiza el repositorio.
        unawaited(_removeSongFromPlaylist(song));
      },
      child: child,
    );
  }

  Widget _buildSongTile(
    BuildContext context,
    Song song, {
    required bool isReorderable,
    int? reorderIndex,
    required bool showDivider,
  }) {
    Widget tile = _SongListTile(
      key: ValueKey('song_${song.id}'),
      song: song,
      isReorderable: isReorderable,
      reorderIndex: reorderIndex,
      onTap: () async {
        final controller = context.read<PlayerController>();

        await _playSong(controller, song);
      },
      onLongPress: isReorderable ? null : () => SongOptions.show(context, song),
    );

    if (_canReorder && !isReorderable) {
      tile = _buildDismissibleSong(song: song, child: tile);
    }

    return RepaintBoundary(
      child: SizedBox(
        height: _kSongTileExtent,
        child: DecoratedBox(
          decoration: showDivider
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 0.5,
                    ),
                  ),
                )
              : const BoxDecoration(),
          child: tile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _PlaylistHeader(
              title: widget.title,
              onBack: () {
                Navigator.of(context).pop();
              },
            ),
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                cacheExtent: 250,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _PlaylistInfo(
                        title: widget.title,
                        subtitle: widget.subtitle,
                        icon: widget.icon,
                        songCount: _songs.length,
                        hasSubtitle: _hasSubtitle,
                        songs: _songs,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _songs.isNotEmpty
                                  ? () async {
                                      final controller = context
                                          .read<PlayerController>();

                                      await _addAllToQueue(controller);
                                    }
                                  : null,
                              icon: const Icon(Icons.queue_music),
                              label: Text(l10n.addAllToQueue),
                            ),
                          ),
                          if (_canReorder) ...[
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _songs.isNotEmpty
                                  ? _toggleReorder
                                  : null,
                              icon: Icon(
                                _isReordering ? Icons.check : Icons.swap_vert,
                              ),
                              label: Text(
                                _isReordering ? l10n.done : l10n.changeOrder,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: _canReorder && _isReordering
                        ? SliverReorderableList(
                            itemCount: _songs.length,
                            onReorder: _reorderSongs,
                            proxyDecorator: (child, index, animation) {
                              return AnimatedBuilder(
                                animation: animation,
                                child: child,
                                builder: (context, child) {
                                  return Material(
                                    elevation: 6,
                                    shadowColor: Colors.black38,
                                    color: theme.scaffoldBackgroundColor,
                                    child: child,
                                  );
                                },
                              );
                            },
                            itemBuilder: (context, index) {
                              final song = _songs[index];

                              return Container(
                                key: ValueKey(song.id),
                                height: _kSongTileExtent,
                                child: _buildSongTile(
                                  context,
                                  song,
                                  isReorderable: true,
                                  reorderIndex: index,
                                  showDivider: index != _songs.length - 1,
                                ),
                              );
                            },
                          )
                        : SliverAnimatedList(
                            key: _animatedListKey,
                            initialItemCount: _songs.length,
                            itemBuilder: (context, index, animation) {
                              final song = _songs[index];

                              return SizeTransition(
                                sizeFactor: CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                ),
                                axisAlignment: -1.0,
                                child: _buildSongTile(
                                  context,
                                  song,
                                  isReorderable: false,
                                  showDivider: index != _songs.length - 1,
                                ),
                              );
                            },
                          ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _QueueAction { replace, add, remove, cancel }

class _PlaylistHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _PlaylistHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            tooltip: l10n.back,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistInfo extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final int songCount;
  final bool hasSubtitle;
  final List<Song> songs;

  const _PlaylistInfo({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.songCount,
    required this.hasSubtitle,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final coverPath = songs.isNotEmpty ? songs.first.coverPath : null;

    return Column(
      children: [
        _PlaylistArtwork(coverPath: coverPath, fallbackIcon: icon),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.songCount(songCount),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _PlaylistArtwork extends StatelessWidget {
  final String? coverPath;
  final IconData fallbackIcon;

  const _PlaylistArtwork({required this.coverPath, required this.fallbackIcon});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;

    if (path == null || path.isEmpty) {
      return _buildFallback(context);
    }

    if (path.startsWith('content://')) {
      return _AndroidLibraryArtwork(
        contentUri: path,
        size: 96,
        borderRadius: 12,
        fallbackIcon: fallbackIcon,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(path),
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        cacheWidth: 192,
        cacheHeight: 192,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildFallback(context),
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Center(
        child: Icon(
          fallbackIcon,
          size: 96,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SongListTile extends StatelessWidget {
  final Song song;
  final bool isReorderable;
  final int? reorderIndex;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SongListTile({
    super.key,
    required this.song,
    this.isReorderable = false,
    this.reorderIndex,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerController, bool>(
      selector: (_, controller) => controller.currentSong?.id == song.id,
      shouldRebuild: (previous, next) => previous != next,
      builder: (context, isPlaying, _) {
        final theme = Theme.of(context);
        final artist = song.artist;
        final hasArtist = artist != null && artist.isNotEmpty;

        return Center(
          child: ListTile(
            onTap: onTap,
            onLongPress: onLongPress,
            minVerticalPadding: 0,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.only(left: 12, right: 0),
            leading: _LibraryArtwork(
              coverPath: song.coverPath,
              size: 40,
              borderRadius: 6,
              isPlaying: isPlaying,
            ),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: isPlaying
                  ? theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    )
                  : null,
            ),
            subtitle: hasArtist
                ? Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis)
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!isReorderable) _SongTrailing(song: song),
                if (isReorderable && reorderIndex != null)
                  ReorderableDragStartListener(
                    index: reorderIndex!,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
        contentUri: path,
        size: size,
        borderRadius: borderRadius,
        fallbackIcon: fallbackIcon,
        isPlaying: isPlaying,
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
            cacheWidth: 96,
            cacheHeight: 96,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _buildFallback(context),
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
  final String contentUri;
  final double size;
  final double borderRadius;
  final IconData fallbackIcon;
  final bool isPlaying;

  const _AndroidLibraryArtwork({
    required this.contentUri,
    required this.size,
    required this.borderRadius,
    required this.fallbackIcon,
    this.isPlaying = false,
  });

  @override
  State<_AndroidLibraryArtwork> createState() => _AndroidLibraryArtworkState();
}

class _AndroidLibraryArtworkState extends State<_AndroidLibraryArtwork> {
  Uint8List? _bytes;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    if (_ArtworkMemoryCache.isCached(widget.contentUri)) {
      _bytes = _ArtworkMemoryCache.getSync(widget.contentUri);

      _isLoading = false;
    } else {
      _loadArtwork();
    }
  }

  @override
  void didUpdateWidget(covariant _AndroidLibraryArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.contentUri != widget.contentUri) {
      if (_ArtworkMemoryCache.isCached(widget.contentUri)) {
        _bytes = _ArtworkMemoryCache.getSync(widget.contentUri);

        _isLoading = false;
      } else {
        _bytes = null;

        _isLoading = true;

        _loadArtwork();
      }
    }
  }

  Future<void> _loadArtwork() async {
    final bytes = await _ArtworkMemoryCache.load(widget.contentUri);

    if (!mounted) return;

    setState(() {
      _bytes = bytes;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;

    if (bytes == null || bytes.isEmpty) {
      if (_isLoading) {
        return SizedBox(width: widget.size, height: widget.size);
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
            cacheWidth: 96,
            cacheHeight: 96,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _buildFallback(context),
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

class _SongTrailing extends StatelessWidget {
  final Song song;

  const _SongTrailing({required this.song});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatDuration(song.duration),
          style: Theme.of(context).textTheme.bodySmall,
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
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;

    final minutes = totalSeconds ~/ 60;

    final seconds = totalSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
