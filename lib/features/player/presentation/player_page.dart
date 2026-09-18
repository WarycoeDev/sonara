import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../library/domain/models/song.dart';
import 'controllers/player_controller.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  static Future<void> open(BuildContext context) async {
    final platform = Theme.of(context).platform;

    final isDesktop =
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS;

    if (isDesktop) {
      await showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
        barrierLabel: AppLocalizations.of(context)!.closePlayer,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return SafeArea(
            child: Center(
              child: Material(
                color: Theme.of(dialogContext).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 420,
                    maxHeight: 820,
                  ),
                  child: const PlayerPage(),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      );

      return;
    }

    await Navigator.of(context, rootNavigator: true).push(_PlayerPageRoute());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: Selector<PlayerController, Song?>(
          selector: (_, controller) => controller.currentSong,
          builder: (context, song, child) {
            if (song == null) {
              return Center(child: Text(l10n.noSongPlaying));
            }

            return _PlayerLayout(key: ValueKey(song.id), song: song);
          },
        ),
      ),
    );
  }
}

class _PlayerPageRoute extends PageRouteBuilder<void> {
  _PlayerPageRoute()
    : super(
        opaque: true,
        maintainState: true,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return const RepaintBoundary(child: PlayerPage());
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          final positionAnimation = Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curvedAnimation);

          return SlideTransition(position: positionAnimation, child: child);
        },
      );
}

class _PlayerLayout extends StatelessWidget {
  final Song song;

  const _PlayerLayout({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    final width = size.width;
    final height = size.height;

    final widthScale = width / 420;
    final heightScale = height / 820;

    final scale = widthScale < heightScale ? widthScale : heightScale;

    final safeScale = scale.clamp(0.55, 1.4).toDouble();

    final horizontalPadding = (24 * safeScale).clamp(12.0, 40.0).toDouble();

    final availableWidth = width - (horizontalPadding * 2);

    final artworkSize = availableWidth.clamp(140.0, height * 0.42).toDouble();

    return Column(
      children: [
        _PlayerHeader(height: (60 * safeScale).clamp(48.0, 76.0).toDouble()),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              children: [
                RepaintBoundary(
                  child: SizedBox(
                    width: artworkSize,
                    height: artworkSize,
                    child: _AlbumArtwork(coverPath: song.coverPath),
                  ),
                ),
                SizedBox(height: (18 * safeScale).clamp(10.0, 28.0).toDouble()),
                _SongInformation(
                  title: song.title,
                  artist: song.artist,
                  safeScale: safeScale,
                ),
                SizedBox(height: (12 * safeScale).clamp(8.0, 20.0).toDouble()),
                const _ProgressSection(),
                SizedBox(height: (8 * safeScale).clamp(4.0, 16.0).toDouble()),
                _PlaybackControls(safeScale: safeScale),
                SizedBox(height: (32 * safeScale).clamp(14.0, 32.0).toDouble()),
                const _PlayerTools(),
                const Spacer(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  final double height;

  const _PlayerHeader({required this.height});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      height: height,
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              // Minimizar el reproductor.
              // La cola NO se borra.
              Navigator.of(context, rootNavigator: true).pop();
            },
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: l10n.minimizePlayer,
          ),
          Expanded(child: Text(l10n.nowPlaying, textAlign: TextAlign.center)),
          IconButton(
            onPressed: () async {
              final controller = context.read<PlayerController>();

              // Al cerrar explícitamente el reproductor,
              // se elimina la canción actual y la cola.
              await controller.removeCurrentSong();

              await controller.clearQueue();

              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop();
              }
            },
            icon: const Icon(Icons.close),
            tooltip: l10n.closePlayer,
          ),
        ],
      ),
    );
  }
}

class _SongInformation extends StatelessWidget {
  final String title;
  final String? artist;
  final double safeScale;

  const _SongInformation({
    required this.title,
    required this.artist,
    required this.safeScale,
  });

  @override
  Widget build(BuildContext context) {
    final hasArtist = artist != null && artist!.trim().isNotEmpty;

    final theme = Theme.of(context);

    return RepaintBoundary(
      child: Column(
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: (24 * safeScale).clamp(16.0, 32.0).toDouble(),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasArtist) ...[
            const SizedBox(height: 6),
            Text(
              artist!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: (16 * safeScale).clamp(12.0, 22.0).toDouble(),
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressSection extends StatefulWidget {
  const _ProgressSection();

  @override
  State<_ProgressSection> createState() => _ProgressSectionState();
}

class _ProgressSectionState extends State<_ProgressSection> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerController, ({Duration position, Duration duration})>(
      selector: (_, controller) =>
          (position: controller.position, duration: controller.duration),
      builder: (context, data, child) {
        final durationMs = data.duration.inMilliseconds;
        final positionMs = data.position.inMilliseconds;

        final isInvalidState =
            durationMs <= 0 || positionMs < 0 || positionMs > durationMs;

        final realProgress = isInvalidState
            ? 0.0
            : (positionMs / durationMs).clamp(0.0, 1.0);

        final currentSliderValue = _isDragging ? _dragValue : realProgress;

        final displayPosition = _isDragging
            ? Duration(milliseconds: (durationMs * _dragValue).round())
            : (isInvalidState ? Duration.zero : data.position);

        return RepaintBoundary(
          child: Column(
            children: [
              Slider(
                value: currentSliderValue,
                onChangeStart: (value) {
                  setState(() {
                    _isDragging = true;
                    _dragValue = value;
                  });
                },
                onChanged: durationMs <= 0
                    ? null
                    : (value) {
                        setState(() {
                          _dragValue = value;
                        });
                      },
                onChangeEnd: (value) {
                  final targetDuration = Duration(
                    milliseconds: (durationMs * value).round(),
                  );

                  context.read<PlayerController>().seek(targetDuration);

                  setState(() {
                    _isDragging = false;
                  });
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatTime(displayPosition)),
                    Text(_formatTime(data.duration)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatTime(Duration duration) {
    if (duration <= Duration.zero) {
      return '0:00';
    }

    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PlaybackControls extends StatelessWidget {
  final double safeScale;

  const _PlaybackControls({required this.safeScale});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Selector<
      PlayerController,
      ({bool isPlaying, bool hasPrevious, bool hasNext})
    >(
      selector: (_, controller) => (
        isPlaying: controller.isPlaying,
        hasPrevious: controller.hasPrevious,
        hasNext: controller.hasNext,
      ),
      builder: (context, state, child) {
        final controller = context.read<PlayerController>();

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: state.hasPrevious ? controller.playPrevious : null,
              iconSize: (36 * safeScale).clamp(26.0, 48.0).toDouble(),
              icon: const Icon(Icons.skip_previous),
              tooltip: l10n.previous,
            ),
            FilledButton(
              onPressed: controller.togglePlayPause,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.all(
                  (20 * safeScale).clamp(12.0, 28.0).toDouble(),
                ),
              ),
              child: Icon(
                state.isPlaying ? Icons.pause : Icons.play_arrow,
                size: (42 * safeScale).clamp(30.0, 56.0).toDouble(),
              ),
            ),
            IconButton(
              onPressed: state.hasNext ? controller.playNext : null,
              iconSize: (36 * safeScale).clamp(26.0, 48.0).toDouble(),
              icon: const Icon(Icons.skip_next),
              tooltip: l10n.next,
            ),
          ],
        );
      },
    );
  }
}

class _PlayerTools extends StatelessWidget {
  const _PlayerTools();

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerController, SonaraRepeatMode>(
      selector: (_, controller) => controller.repeatMode,
      builder: (context, repeatMode, child) {
        final l10n = AppLocalizations.of(context)!;

        return Row(
          children: [
            Expanded(
              child: _PlayerOptionButton(
                icon: Icons.more_horiz,
                label: l10n.options,
                onPressed: () {
                  _showOptions(context);
                },
              ),
            ),
            Expanded(
              child: _PlayerOptionButton(
                icon: _repeatIcon(repeatMode),
                label: _repeatLabel(context, repeatMode),
                isActive: repeatMode != SonaraRepeatMode.off,
                onPressed: () {
                  _showModes(context);
                },
              ),
            ),
            Expanded(
              child: _PlayerOptionButton(
                icon: Icons.queue_music,
                label: l10n.queue,
                onPressed: () {
                  _showQueue(context);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Selector<PlayerController, bool>(
          selector: (_, controller) => controller.isFavorite,
          builder: (context, isFavorite, child) {
            final l10n = AppLocalizations.of(context)!;

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
                      await context.read<PlayerController>().toggleFavorite();

                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext, rootNavigator: true).pop();
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showModes(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _ModesSheet(sheetContext: sheetContext);
      },
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return const _QueueSheet();
      },
    );
  }

  static IconData _repeatIcon(SonaraRepeatMode mode) {
    switch (mode) {
      case SonaraRepeatMode.off:
        return Icons.repeat;

      case SonaraRepeatMode.one:
        return Icons.repeat_one;

      case SonaraRepeatMode.all:
        return Icons.repeat;
    }
  }

  static String _repeatLabel(BuildContext context, SonaraRepeatMode mode) {
    final l10n = AppLocalizations.of(context)!;

    switch (mode) {
      case SonaraRepeatMode.off:
        return l10n.repeatOff;

      case SonaraRepeatMode.one:
        return l10n.repeatSong;

      case SonaraRepeatMode.all:
        return l10n.repeatQueue;
    }
  }
}

class _ModesSheet extends StatelessWidget {
  final BuildContext sheetContext;

  const _ModesSheet({required this.sheetContext});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Selector<
      PlayerController,
      ({bool shuffle, SonaraRepeatMode repeatMode})
    >(
      selector: (_, controller) => (
        shuffle: controller.isShuffleEnabled,
        repeatMode: controller.repeatMode,
      ),
      builder: (context, state, child) {
        final controller = context.read<PlayerController>();

        final primaryColor = Theme.of(context).colorScheme.primary;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                secondary: Icon(
                  Icons.shuffle,
                  color: state.shuffle ? primaryColor : null,
                ),
                title: Text(
                  state.shuffle ? l10n.shuffleEnabled : l10n.shuffleDisabled,
                ),
                value: state.shuffle,
                onChanged: (_) {
                  controller.toggleShuffle();
                },
              ),
              _RepeatModeTile(
                icon: Icons.repeat,
                label: l10n.repeatOff,
                isSelected: state.repeatMode == SonaraRepeatMode.off,
                onTap: () {
                  controller.setRepeatMode(SonaraRepeatMode.off);

                  Navigator.of(sheetContext, rootNavigator: true).pop();
                },
              ),
              _RepeatModeTile(
                icon: Icons.repeat_one,
                label: l10n.repeatSong,
                isSelected: state.repeatMode == SonaraRepeatMode.one,
                onTap: () {
                  controller.setRepeatMode(SonaraRepeatMode.one);

                  Navigator.of(sheetContext, rootNavigator: true).pop();
                },
              ),
              _RepeatModeTile(
                icon: Icons.repeat,
                label: l10n.repeatQueue,
                isSelected: state.repeatMode == SonaraRepeatMode.all,
                onTap: () {
                  controller.setRepeatMode(SonaraRepeatMode.all);

                  Navigator.of(sheetContext, rootNavigator: true).pop();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: SizedBox(
        height: 400,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.queueTitle,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child:
                  Selector<
                    PlayerController,
                    ({List<Song> queue, String? currentSongId})
                  >(
                    selector: (_, controller) => (
                      queue: controller.queue,
                      currentSongId: controller.currentSong?.id,
                    ),
                    builder: (context, data, child) {
                      final queue = data.queue;

                      if (queue.isEmpty) {
                        return Center(child: Text(l10n.queueEmpty));
                      }

                      return ReorderableListView.builder(
                        itemCount: queue.length,
                        buildDefaultDragHandles: false,
                        itemBuilder: (context, index) {
                          final song = queue[index];

                          final isCurrent = song.id == data.currentSongId;

                          return _QueueItem(
                            key: ValueKey(song.id),
                            song: song,
                            index: index,
                            isCurrent: isCurrent,
                          );
                        },
                        onReorder: (oldIndex, newIndex) {
                          if (newIndex > oldIndex) {
                            newIndex--;
                          }

                          context.read<PlayerController>().reorderQueue(
                            oldIndex,
                            newIndex,
                          );
                        },
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueItem extends StatelessWidget {
  final Song song;
  final int index;
  final bool isCurrent;

  const _QueueItem({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final controller = context.read<PlayerController>();

    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      // La identidad depende únicamente de la canción.
      // No debe depender del índice porque este cambia al eliminar
      // elementos de la cola.
      key: ValueKey('queue_${song.id}'),

      direction: DismissDirection.horizontal,

      dismissThresholds: const {
        DismissDirection.startToEnd: 0.35,
        DismissDirection.endToStart: 0.35,
      },

      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: colorScheme.error,
        child: Icon(Icons.remove_circle_outline, color: colorScheme.onError),
      ),

      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: colorScheme.error,
        child: Icon(Icons.remove_circle_outline, color: colorScheme.onError),
      ),

      confirmDismiss: (_) async {
        // La canción actual no puede eliminarse deslizando.
        return !isCurrent;
      },

      onDismissed: (_) {
        controller.removeFromQueue(song);
      },

      child: ListTile(
        leading: _QueueArtwork(
          coverPath: song.coverPath,
          isCurrent: isCurrent,
          size: 40,
          borderRadius: 6,
        ),

        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: isCurrent
              ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                )
              : null,
        ),

        subtitle: song.artist != null && song.artist!.isNotEmpty
            ? Text(song.artist!, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,

        trailing: ReorderableDragStartListener(
          index: index,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.drag_handle),
          ),
        ),

        onTap: () async {
          final queue = List<Song>.from(controller.queue);

          await controller.playFromQueue(queue, startIndex: index);

          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        },
      ),
    );
  }
}

class _QueueArtwork extends StatelessWidget {
  final String? coverPath;
  final bool isCurrent;
  final double size;
  final double borderRadius;

  const _QueueArtwork({
    required this.coverPath,
    required this.isCurrent,
    required this.size,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final path = coverPath;

    if (path == null || path.isEmpty) {
      return _buildFallback(context);
    }

    if (path.startsWith('content://')) {
      return _AndroidQueueArtwork(
        contentUri: path,
        size: size,
        borderRadius: borderRadius,
        isCurrent: isCurrent,
      );
    }

    return _buildFileArtwork(context, path);
  }

  Widget _buildFileArtwork(BuildContext context, String path) {
    final file = File(path);

    if (!file.existsSync()) {
      return _buildFallback(context);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
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
              return _buildFallback(context);
            },
          ),
        ),
        if (isCurrent)
          _QueuePlayingOverlay(size: size, borderRadius: borderRadius),
      ],
    );
  }

  Widget _buildFallback(BuildContext context) {
    final iconColor = isCurrent
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(
          isCurrent ? Icons.graphic_eq : Icons.music_note,
          size: size * 0.55,
          color: iconColor,
        ),
      ),
    );
  }
}

class _AndroidQueueArtwork extends StatefulWidget {
  final String contentUri;
  final double size;
  final double borderRadius;
  final bool isCurrent;

  const _AndroidQueueArtwork({
    required this.contentUri,
    required this.size,
    required this.borderRadius,
    required this.isCurrent,
  });

  @override
  State<_AndroidQueueArtwork> createState() => _AndroidQueueArtworkState();
}

class _AndroidQueueArtworkState extends State<_AndroidQueueArtwork> {
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
  void didUpdateWidget(covariant _AndroidQueueArtwork oldWidget) {
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
        if (widget.isCurrent)
          _QueuePlayingOverlay(
            size: widget.size,
            borderRadius: widget.borderRadius,
          ),
      ],
    );
  }

  Widget _buildFallback(BuildContext context) {
    final iconColor = widget.isCurrent
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: Icon(
          widget.isCurrent ? Icons.graphic_eq : Icons.music_note,
          size: widget.size * 0.55,
          color: iconColor,
        ),
      ),
    );
  }
}

class _QueuePlayingOverlay extends StatelessWidget {
  final double size;
  final double borderRadius;

  const _QueuePlayingOverlay({required this.size, required this.borderRadius});

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
        size: size * 0.5,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _PlayerOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isActive;

  const _PlayerOptionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final color = isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onPressed,
            iconSize: 28,
            color: color,
            icon: Icon(icon),
          ),
          SizedBox(
            width: double.infinity,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _RepeatModeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RepeatModeTile({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return ListTile(
      leading: Icon(icon, color: isSelected ? primaryColor : null),
      title: Text(label),
      selected: isSelected,
      onTap: onTap,
    );
  }
}

class _AlbumArtwork extends StatelessWidget {
  final String? coverPath;

  const _AlbumArtwork({required this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;

    if (path == null || path.isEmpty) {
      return _buildDefaultArtwork(context);
    }

    if (path.startsWith('content://')) {
      return _AndroidAlbumArtwork(contentUri: path);
    }

    return _buildFileArtwork(context, path);
  }

  Widget _buildFileArtwork(BuildContext context, String path) {
    final file = File(path);

    if (!file.existsSync()) {
      return _buildDefaultArtwork(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Image.file(
          file,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return const _DefaultArtwork();
          },
        ),
      ),
    );
  }

  Widget _buildDefaultArtwork(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const _DefaultArtwork(),
      ),
    );
  }
}

class _AndroidAlbumArtwork extends StatefulWidget {
  final String contentUri;

  const _AndroidAlbumArtwork({required this.contentUri});

  @override
  State<_AndroidAlbumArtwork> createState() => _AndroidAlbumArtworkState();
}

class _AndroidAlbumArtworkState extends State<_AndroidAlbumArtwork> {
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
  void didUpdateWidget(covariant _AndroidAlbumArtwork oldWidget) {
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
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const SizedBox.expand(),
        );
      }

      return _buildDefaultArtwork(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Image.memory(
          bytes,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return const _DefaultArtwork();
          },
        ),
      ),
    );
  }

  Widget _buildDefaultArtwork(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const _DefaultArtwork(),
      ),
    );
  }
}

class _DefaultArtwork extends StatelessWidget {
  const _DefaultArtwork();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.music_note,
        size: 120,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
