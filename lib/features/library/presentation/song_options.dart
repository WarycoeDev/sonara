import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../favorites/data/favorites_repository.dart';
import '../../player/presentation/controllers/player_controller.dart';
import '../data/repositories/local_library_repository.dart';
import '../data/repositories/playlists_repository.dart';
import '../domain/models/playlist.dart';
import '../domain/models/song.dart';
import 'playlist_dialogs.dart';

enum _SongOptionAction { favorite, queue, addToPlaylist }

enum _PlaylistPreviewResult { add, remove, backToPlaylistSelector }

class SongOptions {
  SongOptions._();

  static final FavoritesRepository _favoritesRepository = FavoritesRepository();

  static final PlaylistsRepository _playlistsRepository = PlaylistsRepository();

  static final LocalLibraryRepository _libraryRepository =
      LocalLibraryRepository();

  /// Muestra el menú de opciones de la canción anclado al elemento que
  /// lo abrió.
  ///
  /// [anchorContext] debe ser el BuildContext del botón/icono que dispara
  /// el menú. Si no se proporciona, se utiliza [context] como referencia.
  static Future<void> show(
    BuildContext context,
    Song song, {
    BuildContext? anchorContext,
  }) async {
    await Future.wait([
      _favoritesRepository.initialize(),
      _playlistsRepository.initialize(),
    ]);

    if (!context.mounted) {
      return;
    }

    final playerController = context.read<PlayerController>();

    final action = await _showAnchoredMenu(
      context: context,
      anchorContext: anchorContext ?? context,
      song: song,
      playerController: playerController,
    );

    if (!context.mounted || action == null) {
      return;
    }

    switch (action) {
      case _SongOptionAction.favorite:
        await _favoritesRepository.toggleFavorite(song.id);
        break;

      case _SongOptionAction.queue:
        final isInQueue = playerController.isInQueue(song.id);
        final isCurrentSong = playerController.currentSong?.id == song.id;

        if (isCurrentSong) {
          return;
        }

        if (isInQueue) {
          playerController.removeFromQueue(song);
        } else {
          await playerController.addToQueue(song);
        }
        break;

      case _SongOptionAction.addToPlaylist:
        await _showAddToPlaylist(context, song);
        break;
    }
  }

  static Future<_SongOptionAction?> _showAnchoredMenu({
    required BuildContext context,
    required BuildContext anchorContext,
    required Song song,
    required PlayerController playerController,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isFavorite = _favoritesRepository.isFavorite(song.id);
    final isInQueue = playerController.isInQueue(song.id);
    final isCurrentSong = playerController.currentSong?.id == song.id;

    final buttonRenderObject = anchorContext.findRenderObject();

    if (buttonRenderObject is! RenderBox) {
      return null;
    }

    final overlayRenderObject = Overlay.of(context).context.findRenderObject();

    if (overlayRenderObject is! RenderBox) {
      return null;
    }

    final buttonTopLeft = buttonRenderObject.localToGlobal(
      Offset.zero,
      ancestor: overlayRenderObject,
    );

    final buttonRect = buttonTopLeft & buttonRenderObject.size;
    final overlaySize = overlayRenderObject.size;

    final position = RelativeRect.fromLTRB(
      buttonRect.right - 8,
      buttonRect.bottom + 4,
      overlaySize.width - buttonRect.right + 8,
      overlaySize.height - buttonRect.bottom,
    );

    return showMenu<_SongOptionAction>(
      context: context,
      position: position,
      elevation: 4,
      color: colorScheme.surfaceContainer,
      // ignore: deprecated_member_use
      shadowColor: Colors.black.withOpacity(0.18),
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.45)),
      ),
      items: [
        _SongOptionPopupItem(
          value: _SongOptionAction.favorite,
          icon: isFavorite ? Icons.favorite : Icons.favorite_border,
          label: isFavorite ? l10n.removeFromFavorites : l10n.addToFavorites,
        ),

        _SongOptionPopupItem(
          value: _SongOptionAction.queue,
          icon: isInQueue ? Icons.remove_from_queue : Icons.queue_music,
          label: isInQueue ? l10n.removeFromQueue : l10n.addToQueue,
          enabled: !isCurrentSong,
        ),

        _SongOptionPopupItem(
          value: _SongOptionAction.addToPlaylist,
          icon: Icons.playlist_add,
          label: l10n.addToPlaylist,
        ),
      ],
    );
  }

  static Future<void> _showAddToPlaylist(
    BuildContext context,
    Song song,
  ) async {
    await _playlistsRepository.initialize();

    if (!context.mounted) {
      return;
    }

    if (_playlistsRepository.playlists.isEmpty) {
      final playlist = await PlaylistDialogs.showCreatePlaylist(context);

      if (!context.mounted || playlist == null) {
        return;
      }

      await _showAddToPlaylist(context, song);

      return;
    }

    while (context.mounted) {
      final playlists = _playlistsRepository.playlists;

      final librarySongs = await _libraryRepository.getSongs();

      if (!context.mounted) {
        return;
      }

      final selectedPlaylist = await _showPlaylistSelector(
        context,
        song,
        playlists,
        librarySongs,
      );

      if (!context.mounted || selectedPlaylist == null) {
        return;
      }

      final result = await _showPlaylistPreview(
        context,
        song,
        selectedPlaylist,
        librarySongs,
      );

      if (!context.mounted) {
        return;
      }

      if (result == _PlaylistPreviewResult.add) {
        await _playlistsRepository.addSongToPlaylist(
          selectedPlaylist.id,
          song.id,
        );

        return;
      }

      if (result == _PlaylistPreviewResult.remove) {
        await _playlistsRepository.removeSongFromPlaylist(
          selectedPlaylist.id,
          song.id,
        );

        return;
      }

      if (result == _PlaylistPreviewResult.backToPlaylistSelector) {
        continue;
      }
    }
  }

  static Future<Playlist?> _showPlaylistSelector(
    BuildContext context,
    Song song,
    List<Playlist> playlists,
    List<Song> librarySongs,
  ) async {
    return showModalBottomSheet<Playlist>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final colorScheme = theme.colorScheme;
        final l10n = AppLocalizations.of(sheetContext)!;

        return SafeArea(
          child: Container(
            height: MediaQuery.sizeOf(sheetContext).height * 0.65,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.addToPlaylist,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];

                      final playlistArtwork = _findPlaylistArtwork(
                        playlist,
                        librarySongs,
                      );

                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        leading: _SongArtwork(
                          coverPath: playlistArtwork,
                          size: 52,
                          borderRadius: 14,
                        ),
                        title: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(l10n.songCount(playlist.songCount)),
                        onTap: () {
                          Navigator.of(sheetContext).pop(playlist);
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();

                        if (!context.mounted) {
                          return;
                        }

                        final playlist =
                            await PlaylistDialogs.showCreatePlaylist(context);

                        if (!context.mounted || playlist == null) {
                          return;
                        }

                        await _showAddToPlaylist(context, song);
                      },
                      icon: const Icon(Icons.add),
                      label: Text(l10n.newPlaylist),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<_PlaylistPreviewResult?> _showPlaylistPreview(
    BuildContext context,
    Song song,
    Playlist playlist,
    List<Song> librarySongs,
  ) async {
    return showModalBottomSheet<_PlaylistPreviewResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _PlaylistPreviewSheet(
          song: song,
          playlistId: playlist.id,
          librarySongs: librarySongs,
        );
      },
    ).then((result) {
      if (result == null) {
        return _PlaylistPreviewResult.backToPlaylistSelector;
      }

      return result;
    });
  }

  static String? _findPlaylistArtwork(
    Playlist playlist,
    List<Song> librarySongs,
  ) {
    final songsById = <String, Song>{
      for (final song in librarySongs) song.id: song,
    };

    for (final songId in playlist.songIds) {
      final song = songsById[songId];

      if (song == null) {
        continue;
      }

      final coverPath = song.coverPath;

      if (coverPath != null && coverPath.isNotEmpty) {
        return coverPath;
      }
    }

    return null;
  }
}

/// Opción personalizada del menú.
///
/// Se utiliza para controlar el ripple y evitar que el efecto rectangular
/// de PopupMenuItem sobresalga del menú.
class _SongOptionPopupItem extends PopupMenuEntry<_SongOptionAction> {
  final _SongOptionAction value;
  final IconData icon;
  final String label;
  final bool enabled;

  const _SongOptionPopupItem({
    required this.value,
    required this.icon,
    required this.label,
    this.enabled = true,
  });

  @override
  double get height => 52;

  @override
  bool represents(_SongOptionAction? value) {
    return value == this.value;
  }

  @override
  State<_SongOptionPopupItem> createState() => _SongOptionPopupItemState();
}

class _SongOptionPopupItemState extends State<_SongOptionPopupItem> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final foregroundColor = widget.enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withOpacity(0.38);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.enabled
              ? () {
                  Navigator.of(context).pop(widget.value);
                }
              : null,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(widget.icon, color: foregroundColor),
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

class _PlaylistPreviewSheet extends StatefulWidget {
  final Song song;
  final String playlistId;
  final List<Song> librarySongs;

  const _PlaylistPreviewSheet({
    required this.song,
    required this.playlistId,
    required this.librarySongs,
  });

  @override
  State<_PlaylistPreviewSheet> createState() => _PlaylistPreviewSheetState();
}

class _PlaylistPreviewSheetState extends State<_PlaylistPreviewSheet> {
  final PlaylistsRepository _playlistsRepository = PlaylistsRepository();

  late List<Song> _playlistSongs;

  bool _isReordering = false;

  @override
  void initState() {
    super.initState();

    _playlistSongs = _resolvePlaylistSongs();

    _playlistsRepository.addListener(_handlePlaylistChanged);
  }

  @override
  void dispose() {
    _playlistsRepository.removeListener(_handlePlaylistChanged);

    super.dispose();
  }

  void _handlePlaylistChanged() {
    if (!mounted) {
      return;
    }

    if (_isReordering) {
      return;
    }

    setState(() {
      _playlistSongs = _resolvePlaylistSongs();
    });
  }

  List<Song> _resolvePlaylistSongs() {
    final playlist = _playlistsRepository.getPlaylist(widget.playlistId);

    if (playlist == null) {
      return [];
    }

    final songsById = <String, Song>{
      for (final song in widget.librarySongs) song.id: song,
    };

    final songs = <Song>[];

    for (final songId in playlist.songIds) {
      final song = songsById[songId];

      if (song != null) {
        songs.add(song);
      }
    }

    return songs;
  }

  Future<void> _removeSong(Song song) async {
    await _playlistsRepository.removeSongFromPlaylist(
      widget.playlistId,
      song.id,
    );
  }

  Future<void> _toggleReordering() async {
    if (_isReordering) {
      final songIds = _playlistSongs.map((song) => song.id).toList();

      try {
        await _playlistsRepository.reorderSongs(widget.playlistId, songIds);
      } catch (_) {
        if (mounted) {
          setState(() {
            _playlistSongs = _resolvePlaylistSongs();
          });
        }
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isReordering = !_isReordering;
    });
  }

  void _reorderSongs(int oldIndex, int newIndex) {
    if (!_isReordering) {
      return;
    }

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final songs = List<Song>.from(_playlistSongs);

    final song = songs.removeAt(oldIndex);

    songs.insert(newIndex, song);

    setState(() {
      _playlistSongs = songs;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final playlist = _playlistsRepository.getPlaylist(widget.playlistId);

    if (playlist == null) {
      return SafeArea(
        child: Container(
          height: MediaQuery.sizeOf(context).height * 0.75,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Center(child: Text(l10n.playlistDoesNotExist)),
        ),
      );
    }

    final alreadyAdded = playlist.songIds.contains(widget.song.id);

    return SafeArea(
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.75,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: colorScheme.outlineVariant.withOpacity(0.45),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 8),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  playlist.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(l10n.songCount(_playlistSongs.length)),
                trailing: _playlistSongs.isNotEmpty
                    ? IconButton(
                        onPressed: _toggleReordering,
                        icon: Icon(_isReordering ? Icons.check : Icons.reorder),
                        tooltip: _isReordering
                            ? l10n.saveOrder
                            : l10n.changeOrder,
                      )
                    : null,
              ),
            ),
            Expanded(
              child: _playlistSongs.isEmpty
                  ? Center(child: Text(l10n.playlistIsEmpty))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      buildDefaultDragHandles: false,
                      itemCount: _playlistSongs.length,
                      onReorder: _reorderSongs,
                      itemBuilder: (context, index) {
                        final playlistSong = _playlistSongs[index];

                        Widget songTile = ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          leading: _SongArtwork(
                            coverPath: playlistSong.coverPath,
                            size: 52,
                            borderRadius: 14,
                          ),
                          title: Text(
                            playlistSong.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            playlistSong.artist ?? l10n.unknownArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _isReordering
                              ? ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Icon(Icons.drag_handle),
                                  ),
                                )
                              : null,
                        );

                        if (_isReordering) {
                          return Material(
                            key: ValueKey(
                              '${widget.playlistId}_${playlistSong.id}',
                            ),
                            color: Colors.transparent,
                            child: songTile,
                          );
                        }

                        return Dismissible(
                          key: ValueKey(
                            '${widget.playlistId}_${playlistSong.id}',
                          ),
                          direction: DismissDirection.startToEnd,
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            decoration: BoxDecoration(
                              color: colorScheme.error,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              Icons.remove_circle_outline,
                              color: colorScheme.onError,
                            ),
                          ),
                          confirmDismiss: (_) async {
                            return await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) {
                                    return AlertDialog(
                                      title: Text(l10n.removeFromPlaylist),
                                      content: Text(
                                        l10n.removeSongFromPlaylistQuestion(
                                          playlistSong.title,
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
                                            Navigator.of(dialogContext)
                                                .pop(true);
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
                            await _removeSong(playlistSong);
                          },
                          child: songTile,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(
                      alreadyAdded
                          ? _PlaylistPreviewResult.remove
                          : _PlaylistPreviewResult.add,
                    );
                  },
                  icon: Icon(alreadyAdded ? Icons.remove : Icons.playlist_add),
                  label: Text(
                    alreadyAdded ? l10n.removeFromPlaylist : l10n.addToPlaylist,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongArtwork extends StatelessWidget {
  final String? coverPath;
  final double size;
  final double borderRadius;

  const _SongArtwork({
    required this.coverPath,
    required this.size,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final path = coverPath;

    if (path == null || path.isEmpty) {
      return _ArtworkFallback(size: size);
    }

    if (path.startsWith('content://')) {
      return _AndroidArtwork(
        contentUri: path,
        size: size,
        borderRadius: borderRadius,
      );
    }

    return _FileArtwork(path: path, size: size, borderRadius: borderRadius);
  }
}

class _FileArtwork extends StatelessWidget {
  final String path;
  final double size;
  final double borderRadius;

  const _FileArtwork({
    required this.path,
    required this.size,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(path);

    if (!file.existsSync()) {
      return _ArtworkFallback(size: size);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: 128,
        cacheHeight: 128,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return _ArtworkFallback(size: size);
        },
      ),
    );
  }
}

class _AndroidArtwork extends StatefulWidget {
  final String contentUri;
  final double size;
  final double borderRadius;

  const _AndroidArtwork({
    required this.contentUri,
    required this.size,
    required this.borderRadius,
  });

  @override
  State<_AndroidArtwork> createState() => _AndroidArtworkState();
}

class _AndroidArtworkState extends State<_AndroidArtwork> {
  static const MethodChannel _mediaStoreChannel = MethodChannel(
    'sonara/media_store',
  );

  Uint8List? _bytes;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _loadArtwork();
  }

  @override
  void didUpdateWidget(covariant _AndroidArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.contentUri != widget.contentUri) {
      _bytes = null;
      _isLoading = true;

      _loadArtwork();
    }
  }

  Future<void> _loadArtwork() async {
    try {
      final result = await _mediaStoreChannel.invokeMethod<dynamic>(
        'readContentUri',
        <String, dynamic>{'uri': widget.contentUri},
      );

      if (!mounted) {
        return;
      }

      if (result is Uint8List) {
        setState(() {
          _bytes = result;
          _isLoading = false;
        });

        return;
      }

      if (result is List) {
        setState(() {
          _bytes = Uint8List.fromList(result.cast<int>());
          _isLoading = false;
        });

        return;
      }

      setState(() {
        _bytes = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _bytes = null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;

    if (bytes == null || bytes.isEmpty) {
      if (_isLoading) {
        return SizedBox(width: widget.size, height: widget.size);
      }

      return _ArtworkFallback(size: widget.size);
    }

    return ClipRRect(
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
          return _ArtworkFallback(size: widget.size);
        },
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  final double size;

  const _ArtworkFallback({required this.size});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(
          Icons.music_note,
          size: size * 0.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
