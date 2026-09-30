import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sonara/features/favorites/data/favorites_repository.dart';
import 'package:sonara/features/library/data/repositories/local_library_repository.dart';
import 'package:sonara/features/library/domain/models/song.dart';
import 'package:sonara/features/player/presentation/controllers/player_controller.dart';
import 'package:sonara/features/statistics/data/statistics_repository.dart';
import 'package:sonara/l10n/app_localizations.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final LocalLibraryRepository _libraryRepository;
  late final StatisticsRepository _statisticsRepository;
  late final FavoritesRepository _favoritesRepository;

  List<Song> _mostPlayedSongs = const <Song>[];
  List<Song> _favoriteSongs = const <Song>[];

  bool _isInitialLoading = true;
  bool _isReloading = false;

  @override
  void initState() {
    super.initState();

    _libraryRepository = LocalLibraryRepository();
    _statisticsRepository = StatisticsRepository();
    _favoritesRepository = FavoritesRepository();

    _favoritesRepository.addListener(_onFavoritesChanged);

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      await Future.wait([_loadMostPlayed(), _loadFavorites()]);
    } finally {
      if (!mounted) {
        return;
      }

      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  Future<List<Song>> _loadMostPlayed({bool updateState = true}) async {
    final results = await Future.wait([
      _libraryRepository.getSongs(),
      _statisticsRepository.initialize(),
    ]);

    final songs = results[0] as List<Song>;

    final statistics = _statisticsRepository.getMostPlayed(limit: 10);

    if (statistics.isEmpty || songs.isEmpty) {
      if (mounted && updateState) {
        setState(() {
          _mostPlayedSongs = const <Song>[];
        });
      }

      return const <Song>[];
    }

    final songsById = <String, Song>{for (final song in songs) song.id: song};

    final mostPlayed = <Song>[];

    for (final statistic in statistics) {
      final song = songsById[statistic.songId];

      if (song != null && statistic.playCount > 0) {
        mostPlayed.add(song);
      }

      if (mostPlayed.length >= 10) {
        break;
      }
    }

    if (mounted && updateState) {
      setState(() {
        _mostPlayedSongs = mostPlayed;
      });
    }

    return mostPlayed;
  }

  Future<void> _reloadMostPlayed() async {
    if (_isReloading || !mounted) {
      return;
    }

    final startedAt = DateTime.now();

    setState(() {
      _isReloading = true;
    });

    await Future.delayed(const Duration(milliseconds: 350));

    if (!mounted) {
      return;
    }

    try {
      await _loadMostPlayed(updateState: true);

      const holdDuration = Duration(milliseconds: 180);

      final elapsed = DateTime.now().difference(startedAt);
      const minimumDuration = Duration(milliseconds: 700);

      final remaining = minimumDuration - elapsed;

      if (remaining > Duration.zero) {
        await Future.delayed(
          remaining > holdDuration ? remaining : holdDuration,
        );
      } else {
        await Future.delayed(holdDuration);
      }
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 180));
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isReloading = false;
    });
  }

  Future<void> _loadFavorites() async {
    await _favoritesRepository.initialize();

    final songs = await _libraryRepository.getSongs();

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
      _favoriteSongs = favorites;
    });
  }

  void _onFavoritesChanged() {
    if (!mounted) {
      return;
    }

    _loadFavorites();
  }

  void _playMostPlayed() {
    if (_mostPlayedSongs.isEmpty) {
      return;
    }

    context.read<PlayerController>().playFromQueue(
      _mostPlayedSongs,
      startIndex: 0,
    );
  }

  void _playFavorites() {
    if (_favoriteSongs.isEmpty) {
      return;
    }

    context.read<PlayerController>().playFromQueue(
      _favoriteSongs,
      startIndex: 0,
    );
  }

  void _playSong(Song song) {
    context.read<PlayerController>().playSong(song);
  }

  void _showSongOptions(BuildContext context, Song song) {
    final playerController = context.read<PlayerController>();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: Listenable.merge([_favoritesRepository, playerController]),
          builder: (context, child) {
            final l10n = AppLocalizations.of(context)!;

            final isFavorite = _favoritesRepository.isFavorite(song.id);

            final isInQueue = playerController.isInQueue(song.id);

            final isCurrentSong = playerController.currentSong?.id == song.id;

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                    ),
                    title: Text(
                      isFavorite
                          ? l10n.removeFromFavorites
                          : l10n.addToFavorites,
                    ),
                    onTap: () async {
                      await _favoritesRepository.toggleFavorite(song.id);

                      if (!sheetContext.mounted) {
                        return;
                      }

                      Navigator.of(sheetContext).pop();
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      isInQueue ? Icons.remove_from_queue : Icons.queue_music,
                    ),
                    title: Text(
                      isInQueue ? l10n.removeFromQueue : l10n.addToQueue,
                    ),
                    enabled: !isCurrentSong,
                    onTap: isCurrentSong
                        ? null
                        : () async {
                            if (isInQueue) {
                              playerController.removeFromQueue(song);
                            } else {
                              await playerController.addToQueue(song);
                            }

                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                  ),
                  ListTile(
                    leading: const Icon(Icons.playlist_add),
                    title: Text(l10n.addToPlaylist),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScrollConfiguration(
        behavior: const _SonaraScrollBehavior(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isInitialLoading)
              const _MostPlayedLoading()
            else ...[
              _MostPlayedSection(
                songs: _mostPlayedSongs,
                isReloading: _isReloading,
                onSongTap: _playSong,
                onSongLongPress: (song) => _showSongOptions(context, song),
                onPlayAll: _playMostPlayed,
                onReload: _reloadMostPlayed,
              ),
              const SizedBox(height: 16),
              _FavoritesSection(
                songs: _favoriteSongs,
                onSongTap: _playSong,
                onSongLongPress: (song) => _showSongOptions(context, song),
                onPlayAll: _playFavorites,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _favoritesRepository.removeListener(_onFavoritesChanged);

    super.dispose();
  }
}

class _SonaraScrollBehavior extends MaterialScrollBehavior {
  const _SonaraScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class _TopMostPlayedCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TopMostPlayedCard({
    required this.song,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          height: 170,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: _CoverArt(song: song, size: 150),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          l10n.mostPlayedBadge,
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              song.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (song.artist != null && song.artist!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          song.artist!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MostPlayedSection extends StatelessWidget {
  final List<Song> songs;
  final bool isReloading;
  final ValueChanged<Song> onSongTap;
  final ValueChanged<Song> onSongLongPress;
  final VoidCallback onPlayAll;
  final VoidCallback onReload;

  const _MostPlayedSection({
    required this.songs,
    required this.isReloading,
    required this.onSongTap,
    required this.onSongLongPress,
    required this.onPlayAll,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.mostPlayed,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.play,
                onPressed: songs.isEmpty ? null : onPlayAll,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
              IconButton(
                tooltip: l10n.refresh,
                onPressed: isReloading ? null : onReload,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (songs.isEmpty)
            SizedBox(
              height: 150,
              child: Center(
                child: Text(
                  l10n.noMostPlayedSongs,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: ImageFiltered(
                key: ValueKey(isReloading),
                imageFilter: ImageFilter.blur(
                  sigmaX: isReloading ? 5 : 0,
                  sigmaY: isReloading ? 5 : 0,
                ),
                child: Column(
                  children: [
                    _TopMostPlayedCard(
                      song: songs.first,
                      onTap: () => onSongTap(songs.first),
                      onLongPress: () => onSongLongPress(songs.first),
                    ),

                    if (songs.length > 1) ...[
                      const SizedBox(height: 12),

                      SizedBox(
                        height: 132,
                        child: GridView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: songs.length - 1,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                mainAxisExtent: 62,
                              ),
                          itemBuilder: (context, index) {
                            final song = songs[index + 1];
                            final position = index + 2;

                            return _MostPlayedListTile(
                              song: song,
                              position: position,
                              onTap: () => onSongTap(song),
                              onLongPress: () => onSongLongPress(song),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MostPlayedListTile extends StatelessWidget {
  final Song song;
  final int position;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MostPlayedListTile({
    required this.song,
    required this.position,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(7),
                child: Row(
                  children: [
                    _CoverArt(song: song, size: 48),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: Text(
                          song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Positioned(
                top: 5,
                right: 6,
                child: Text(
                  '#$position',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoritesSection extends StatelessWidget {
  final List<Song> songs;
  final ValueChanged<Song> onSongTap;
  final ValueChanged<Song> onSongLongPress;
  final VoidCallback onPlayAll;

  const _FavoritesSection({
    required this.songs,
    required this.onSongTap,
    required this.onSongLongPress,
    required this.onPlayAll,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.favorites,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.play,
                onPressed: songs.isEmpty ? null : onPlayAll,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (songs.isEmpty)
            SizedBox(
              height: 150,
              child: Center(
                child: Text(l10n.noFavoriteSongs, textAlign: TextAlign.center),
              ),
            )
          else
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: songs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final song = songs[index];

                  return _FavoriteCard(
                    song: song,
                    onTap: () => onSongTap(song),
                    onLongPress: () => onSongLongPress(song),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FavoriteCard({
    required this.song,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: 310,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Ink(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _CoverArt(song: song, size: 130),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: colorScheme.primaryContainer,
                        ),
                        child: Text(
                          l10n.favoriteBadge,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (song.artist != null && song.artist!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          song.artist!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        _formatDuration(song.duration),
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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

class _CoverArt extends StatelessWidget {
  final Song song;
  final double size;

  const _CoverArt({required this.song, required this.size});

  @override
  Widget build(BuildContext context) {
    final path = song.coverPath;

    if (path == null || path.isEmpty) {
      return _PlaceholderCover(size: size);
    }

    if (path.startsWith('content://')) {
      return _AndroidCoverArt(uri: path, size: size);
    }

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          path,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) {
            return _PlaceholderCover(size: size);
          },
        ),
      );
    }

    final file = File(path);

    if (file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) {
            return _PlaceholderCover(size: size);
          },
        ),
      );
    }

    return _PlaceholderCover(size: size);
  }
}

class _AndroidCoverArt extends StatefulWidget {
  final String uri;
  final double size;

  const _AndroidCoverArt({required this.uri, required this.size});

  @override
  State<_AndroidCoverArt> createState() => _AndroidCoverArtState();
}

class _AndroidCoverArtState extends State<_AndroidCoverArt> {
  static const MethodChannel _channel = MethodChannel('sonara/media_store');

  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _loadCover();
  }

  @override
  void didUpdateWidget(covariant _AndroidCoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.uri != widget.uri) {
      _bytes = null;
      _loading = true;
      _loadCover();
    }
  }

  Future<void> _loadCover() async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'readContentUri',
        <String, dynamic>{'uri': widget.uri},
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _bytes = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _bytes = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _PlaceholderCover(size: widget.size);
    }

    if (_bytes == null || _bytes!.isEmpty) {
      return _PlaceholderCover(size: widget.size);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        _bytes!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) {
          return _PlaceholderCover(size: widget.size);
        },
      ),
    );
  }
}

class _PlaceholderCover extends StatelessWidget {
  final double size;

  const _PlaceholderCover({required this.size});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.35,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _MostPlayedLoading extends StatelessWidget {
  const _MostPlayedLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 225,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);

  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
