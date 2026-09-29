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
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 170),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 1.15), end: Offset.zero).animate(
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Dismissible(
              key: ValueKey(song.filePath),
              direction: DismissDirection.down,
              dismissThresholds: const {DismissDirection.down: 0.4},
              confirmDismiss: (direction) async {
                await controller.removeCurrentSong();
                return false;
              },
              child: _MiniPlayerCard(
                song: song,
                position: data.position,
                duration: data.duration,
                isPlaying: data.isPlaying,
                hasPrevious: data.hasPrevious,
                hasNext: data.hasNext,
                l10n: l10n,
                onTap: () => _openPlayer(context),
                onPrevious: controller.playPrevious,
                onPlayPause: controller.togglePlayPause,
                onNext: controller.playNext,
                progress: _calculateProgress(data.position, data.duration),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openPlayer(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final platform = Theme.of(context).platform;

    final isDesktop =
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS;

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

  double _calculateProgress(Duration position, Duration duration) {
    final totalMs = duration.inMilliseconds;
    final posMs = position.inMilliseconds;

    if (totalMs <= 0 || posMs < 0) {
      return 0.0;
    }

    if (posMs > totalMs) {
      return 0.0;
    }

    return (posMs / totalMs).clamp(0.0, 1.0);
  }
}

/// ------------------------------------------------------------
/// CARD PRINCIPAL
/// ------------------------------------------------------------

class _MiniPlayerCard extends StatelessWidget {
  final Song song;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool hasPrevious;
  final bool hasNext;
  final AppLocalizations l10n;
  final VoidCallback onTap;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final double progress;

  const _MiniPlayerCard({
    required this.song,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.hasPrevious,
    required this.hasNext,
    required this.l10n,
    required this.onTap,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 18,
                spreadRadius: 1,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                  child: Row(
                    children: [
                      _MiniPlayerArtwork(coverPath: song.coverPath, size: 50),

                      const SizedBox(width: 12),

                      Expanded(
                        child: _MiniPlayerInfo(
                          title: song.title,
                          position: position,
                          duration: duration,
                        ),
                      ),

                      const SizedBox(width: 4),

                      _MiniPlayerControlButton(
                        tooltip: l10n.previous,
                        icon: Icons.skip_previous_rounded,
                        enabled: hasPrevious,
                        onPressed: hasPrevious ? onPrevious : null,
                      ),

                      const SizedBox(width: 2),

                      _MiniPlayerPlayButton(
                        isPlaying: isPlaying,
                        tooltip: isPlaying ? l10n.pause : l10n.play,
                        onPressed: onPlayPause,
                      ),

                      const SizedBox(width: 2),

                      _MiniPlayerControlButton(
                        tooltip: l10n.next,
                        icon: Icons.skip_next_rounded,
                        enabled: hasNext,
                        onPressed: hasNext ? onNext : null,
                      ),
                    ],
                  ),
                ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(3),
                      backgroundColor: colorScheme.primary.withOpacity(0.10),
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

/// ------------------------------------------------------------
/// INFORMACIÓN
/// ------------------------------------------------------------

class _MiniPlayerInfo extends StatelessWidget {
  final String title;
  final Duration position;
  final Duration duration;

  const _MiniPlayerInfo({
    required this.title,
    required this.position,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${_formatTime(position)} / ${_formatTime(duration)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
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
/// BOTONES SECUNDARIOS
/// ------------------------------------------------------------

class _MiniPlayerControlButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;

  const _MiniPlayerControlButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 23,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          foregroundColor: enabled
              ? colorScheme.onSurface
              : colorScheme.onSurface.withOpacity(0.28),
          minimumSize: const Size(40, 40),
          maximumSize: const Size(40, 40),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// BOTÓN PLAY / PAUSE
/// ------------------------------------------------------------

class _MiniPlayerPlayButton extends StatelessWidget {
  final bool isPlaying;
  final String tooltip;
  final VoidCallback onPressed;

  const _MiniPlayerPlayButton({
    required this.isPlaying,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: IconButton.filled(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (child, animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey(isPlaying),
            size: 23,
          ),
        ),
        style: IconButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(44, 44),
          maximumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// PORTADA
/// ------------------------------------------------------------

class _MiniPlayerArtwork extends StatelessWidget {
  final String? coverPath;
  final double size;

  const _MiniPlayerArtwork({required this.coverPath, this.size = 50});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;

    if (path == null || path.isEmpty) {
      return _defaultArtwork(context);
    }

    if (path.startsWith('content://')) {
      return _AndroidMiniPlayerArtwork(contentUri: path, size: size);
    }

    return _buildFileArtwork(context, path);
  }

  Widget _buildFileArtwork(BuildContext context, String path) {
    final file = File(path);

    if (!file.existsSync()) {
      return _defaultArtwork(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.file(
        file,
        width: size,
        height: size,
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
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * 0.52,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// PORTADA ANDROID / CONTENT URI
/// ------------------------------------------------------------

class _AndroidMiniPlayerArtwork extends StatefulWidget {
  final String contentUri;
  final double size;

  const _AndroidMiniPlayerArtwork({required this.contentUri, this.size = 50});

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
        return SizedBox(width: widget.size, height: widget.size);
      }

      return _defaultArtwork(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
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
          return _defaultArtwork(context);
        },
      ),
    );
  }

  Widget _defaultArtwork(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: widget.size * 0.52,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}
