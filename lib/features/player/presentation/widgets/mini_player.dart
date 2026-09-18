import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/app_localizations.dart';

import '../controllers/player_controller.dart';

import '../../../library/domain/models/song.dart';

import '../player_page.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;

  late final Animation<Offset> _slideAnimation;

  bool _wasVisible = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 150),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
  }

  @override
  void dispose() {
    _animationController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Selector<
      PlayerController,
      ({
        Song? song,
        Duration position,
        Duration duration,
        bool isPlaying,
        bool hasPrevious,
        bool hasNext,
      })
    >(
      selector: (_, controller) => (
        song: controller.currentSong,
        position: controller.position,
        duration: controller.duration,
        isPlaying: controller.isPlaying,
        hasPrevious: controller.hasPrevious,
        hasNext: controller.hasNext,
      ),
      builder: (context, data, child) {
        final song = data.song;

        final isVisible = song != null;

        if (isVisible && !_wasVisible) {
          _wasVisible = true;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _animationController.forward(from: 0);
            }
          });
        }

        if (!isVisible && _wasVisible) {
          _wasVisible = false;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _animationController.reverse();
            }
          });
        }

        if (!isVisible) {
          return const SizedBox.shrink();
        }

        final controller = context.read<PlayerController>();

        return SlideTransition(
          position: _slideAnimation,
          child: Dismissible(
            key: ValueKey(song.filePath),
            direction: DismissDirection.down,
            dismissThresholds: const {DismissDirection.down: 0.4},
            confirmDismiss: (direction) async {
              await controller.removeCurrentSong();
              return false;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _openPlayer(context);
              },
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: _calculateProgress(data.position, data.duration),
                      minHeight: 2,
                    ),
                    SizedBox(
                      height: 62,
                      child: Row(
                        children: [
                          const SizedBox(width: 16),

                          _MiniPlayerArtwork(coverPath: song.coverPath),

                          const SizedBox(width: 16),

                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_formatTime(data.position)}/${_formatTime(data.duration)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),

                          IconButton(
                            iconSize: 26,
                            tooltip: l10n.previous,
                            onPressed: data.hasPrevious
                                ? () {
                                    controller.playPrevious();
                                  }
                                : null,
                            icon: const Icon(Icons.skip_previous),
                          ),

                          IconButton(
                            iconSize: 30,
                            tooltip: data.isPlaying ? l10n.pause : l10n.play,
                            onPressed: () {
                              controller.togglePlayPause();
                            },
                            icon: Icon(
                              data.isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                          ),

                          IconButton(
                            iconSize: 26,
                            tooltip: l10n.next,
                            onPressed: data.hasNext
                                ? () {
                                    controller.playNext();
                                  }
                                : null,
                            icon: const Icon(Icons.skip_next),
                          ),

                          const SizedBox(width: 8),
                        ],
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

  void _openPlayer(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final isDesktop =
        Theme.of(context).platform == TargetPlatform.linux ||
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.macOS;

    if (isDesktop) {
      showGeneralDialog(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
        barrierLabel: l10n.closePlayer,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 300),
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
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: ScaleTransition(
              scale: Tween<double>(
                begin: 0.92,
                end: 1.0,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
      );

      return;
    }

    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return const PlayerPage();
        },
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          final slideAnimation = Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curvedAnimation);

          return SlideTransition(position: slideAnimation, child: child);
        },
      ),
    );
  }

  /// Evita saltos de estado desfasados en el segundo 0:00.
  double _calculateProgress(Duration position, Duration duration) {
    final totalMs = duration.inMilliseconds;

    final posMs = position.inMilliseconds;

    if (totalMs <= 0 || posMs < 0) {
      return 0.0;
    }

    /// Si la posición es mayor que la duración o si está reiniciando.
    if (posMs > totalMs) {
      return 0.0;
    }

    return (posMs / totalMs).clamp(0.0, 1.0);
  }

  String _formatTime(Duration duration) {
    if (duration <= Duration.zero) {
      return '0:00';
    }

    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// ------------------------------------------------------------
/// PORTADA DEL MINI PLAYER
/// ------------------------------------------------------------

class _MiniPlayerArtwork extends StatelessWidget {
  final String? coverPath;

  const _MiniPlayerArtwork({required this.coverPath});

  static const MethodChannel _mediaStoreChannel = MethodChannel(
    'sonara/media_store',
  );

  @override
  Widget build(BuildContext context) {
    final path = coverPath;

    if (path == null || path.isEmpty) {
      return _defaultArtwork(context);
    }

    if (path.startsWith('content://')) {
      return _AndroidMiniPlayerArtwork(contentUri: path);
    }

    return _buildFileArtwork(context, path);
  }

  Widget _buildFileArtwork(BuildContext context, String path) {
    final file = File(path);

    if (!file.existsSync()) {
      return _defaultArtwork(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        file,
        width: 42,
        height: 42,
        fit: BoxFit.cover,
        cacheWidth: 128,
        cacheHeight: 128,
        filterQuality: FilterQuality.low,
        errorBuilder: (context, error, stackTrace) {
          return _defaultArtwork(context);
        },
      ),
    );
  }

  Widget _defaultArtwork(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Center(
        child: Icon(
          Icons.music_note,
          size: 28,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// PORTADA ANDROID
/// ------------------------------------------------------------

class _AndroidMiniPlayerArtwork extends StatefulWidget {
  final String contentUri;

  const _AndroidMiniPlayerArtwork({required this.contentUri});

  @override
  State<_AndroidMiniPlayerArtwork> createState() =>
      _AndroidMiniPlayerArtworkState();
}

class _AndroidMiniPlayerArtworkState extends State<_AndroidMiniPlayerArtwork> {
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
  void didUpdateWidget(covariant _AndroidMiniPlayerArtwork oldWidget) {
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
        return const SizedBox(width: 42, height: 42);
      }

      return _defaultArtwork(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        bytes,
        width: 42,
        height: 42,
        fit: BoxFit.cover,
        cacheWidth: 128,
        cacheHeight: 128,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return _defaultArtwork(context);
        },
      ),
    );
  }

  Widget _defaultArtwork(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Center(
        child: Icon(
          Icons.music_note,
          size: 28,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
