import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../library/domain/models/song.dart';
import 'controllers/player_controller.dart';
import '../data/services/cover_color_service.dart';

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
          final theme = Theme.of(dialogContext);

          return SafeArea(
            child: Center(
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 460,
                    maxHeight: 860,
                  ),
                  child: const PlayerPage(),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
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
      body: Selector<PlayerController, Song?>(
        selector: (_, controller) => controller.currentSong,
        builder: (context, song, child) {
          // El fondo va FUERA del SafeArea para que el degradado
          // llegue hasta detrás de la barra de estado.
          return _CoverGradientBackground(
            song: song,
            child: SafeArea(
              child: song == null
                  ? Center(
                      child: Text(
                        l10n.noSongPlaying,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    )
                  : _PlayerLayout(song: song),
            ),
          );
        },
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
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      );
}

/* ========================================================================= */
/* COVER GRADIENT BACKGROUND                                                 */
/* ========================================================================= */
class _CoverGradientBackground extends StatefulWidget {
  final Song? song;
  final Widget child;

  const _CoverGradientBackground({required this.song, required this.child});

  @override
  State<_CoverGradientBackground> createState() =>
      _CoverGradientBackgroundState();
}

class _CoverGradientBackgroundState extends State<_CoverGradientBackground> {
  Color? _seed;
  String? _requestedKey;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _CoverGradientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  void _refresh() {
    final song = widget.song;

    if (song == null) {
      // Se conserva el último color para que el degradado no salte durante
      // la animación de salida.
      _requestedKey = null;
      return;
    }

    final key = CoverColorService.keyFor(song);

    if (key == _requestedKey) {
      return;
    }

    _requestedKey = key;

    final cached = CoverColorService.instance.peek(song);

    if (cached != null) {
      _seed = cached;
      return;
    }

    unawaited(_loadSeed(song, key));
  }

  Future<void> _loadSeed(Song song, String key) async {
    final seed = await CoverColorService.instance.seedFor(song);

    if (!mounted || key != _requestedKey) {
      return;
    }

    setState(() {
      _seed = seed;
    });
  }

  /// Convierte el color dominante de la carátula en un tono que se vea bien
  /// como fondo: oscuro y saturado en modo oscuro, pastel en modo claro.
  static Color _tint(Color seed, bool isDark) {
    final hsv = HSVColor.fromColor(seed);
    final isGrey = hsv.saturation < 0.08;

    if (isDark) {
      final saturation = isGrey
          ? hsv.saturation
          : hsv.saturation.clamp(0.4, 0.8).toDouble();

      return HSVColor.fromAHSV(1, hsv.hue, saturation, 0.38).toColor();
    }

    final saturation = isGrey
        ? hsv.saturation
        : (hsv.saturation * 0.55).clamp(0.14, 0.42).toDouble();

    return HSVColor.fromAHSV(1, hsv.hue, saturation, 0.97).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final isDark = theme.brightness == Brightness.dark;

    final target = _seed == null
        ? theme.colorScheme.primaryContainer
        : _tint(_seed!, isDark);

    // El degradado vive en su propia capa (RepaintBoundary) y separado del
    // contenido: al animar el color solo se repinta el fondo, no todo el
    // reproductor.
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: target),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, color, _) {
                final top = color ?? target;
                // ignore: deprecated_member_use
                final middle = Color.alphaBlend(top.withOpacity(0.45), surface);

                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [top, middle, surface],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Lee carátulas `content://` de Android una sola vez y las comparte entre
/// la carátula grande, el degradado y la cola (antes se leía varias veces por
/// el MethodChannel). Cache LRU pequeña para no gastar memoria.

/// Saca un color dominante de la carátula de forma barata: decodifica la
/// imagen a 24x24 (fuera del hilo de UI) y promedia los tonos más vivos.
/// Reemplaza a ColorScheme.fromImageProvider, que era lo que hacía laguear.

/* ========================================================================= */
/* LAYOUT                                                                    */
/* ========================================================================= */

class _PlayerLayout extends StatelessWidget {
  final Song song;

  const _PlayerLayout({required this.song});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 680;

        return Column(
          children: [
            const _PlayerHeader(),
            Expanded(
              child: _PlayerContent(song: song, compact: compact),
            ),
          ],
        );
      },
    );
  }
}

class _PlayerContent extends StatelessWidget {
  final Song song;
  final bool compact;

  const _PlayerContent({required this.song, required this.compact});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    final horizontalPadding = size.width < 400 ? 18.0 : 24.0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        compact ? 4 : 10,
        horizontalPadding,
        24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              SizedBox(height: compact ? 8 : 20),

              _HeroArtwork(song: song, compact: compact),

              SizedBox(height: compact ? 18 : 26),

              _SongTitle(song: song),

              SizedBox(height: compact ? 12 : 20),

              const _ModernProgress(),

              SizedBox(height: compact ? 6 : 14),

              const _MainPlaybackControls(),

              SizedBox(height: compact ? 12 : 50),

              const _SecondaryControls(),

              SizedBox(height: compact ? 10 : 18),
            ],
          ),
        ),
      ),
    );
  }
}

/* ========================================================================= */
/* HEADER                                                                    */
/* ========================================================================= */

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SizedBox(
      height: 60,
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop();
            },
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            tooltip: l10n.minimizePlayer,
          ),

          Expanded(
            child: Text(
              l10n.nowPlaying,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          IconButton(
            onPressed: () async {
              final controller = context.read<PlayerController>();

              await controller.removeCurrentSong();
              await controller.clearQueue();

              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop();
              }
            },
            icon: const Icon(Icons.close_rounded),
            tooltip: l10n.closePlayer,
          ),
        ],
      ),
    );
  }
}

/* ========================================================================= */
/* ARTWORK                                                                   */
/* ========================================================================= */
class _HeroArtwork extends StatelessWidget {
  final Song song;
  final bool compact;

  const _HeroArtwork({required this.song, required this.compact});

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        final artworkSize = math.min(availableWidth, compact ? 270.0 : 360.0);

        // Decodifica la imagen al tamaño real en pantalla y no a su
        // resolución original: es lo que más pesa al cambiar de canción.
        final cacheSize = math.max(1, (artworkSize * devicePixelRatio).round());

        return RepaintBoundary(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                  child: child,
                ),
              );
            },
            child: SizedBox(
              key: ValueKey(
                '${song.id}|'
                '${song.coverPath ?? ''}|'
                '${song.fileLastModified ?? 0}',
              ),
              width: artworkSize,
              height: artworkSize,
              child: _AlbumArtwork(
                coverPath: song.coverPath,
                coverBytes: song.coverBytes,
                cacheSize: cacheSize,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AlbumArtwork extends StatelessWidget {
  final String? coverPath;
  final Uint8List? coverBytes;
  final int cacheSize;

  const _AlbumArtwork({
    required this.coverPath,
    required this.coverBytes,
    required this.cacheSize,
  });

  Future<void> _showArtworkMenu(BuildContext context) async {
    final controller = context.read<PlayerController>();

    if (Platform.isAndroid) {
      await HapticFeedback.mediumImpact();
    }

    if (!context.mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _ArtworkMenu(
          sheetContext: sheetContext,
          controller: controller,
          hasArtwork:
              (coverBytes != null && coverBytes!.isNotEmpty) ||
              (coverPath != null && coverPath!.isNotEmpty),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        _showArtworkMenu(context);
      },
      onSecondaryTap: () {
        _showArtworkMenu(context);
      },
      child: _buildArtwork(context),
    );
  }

  Widget _buildArtwork(BuildContext context) {
    final bytes = coverBytes;

    if (bytes != null && bytes.isNotEmpty) {
      return _MemoryArtwork(bytes: bytes, cacheSize: cacheSize);
    }

    final path = coverPath;

    if (path == null || path.isEmpty) {
      return const _DefaultArtwork();
    }

    if (path.startsWith('content://')) {
      return _AndroidAlbumArtwork(contentUri: path, cacheSize: cacheSize);
    }

    return _FileArtwork(path: path, cacheSize: cacheSize);
  }
}

class _MemoryArtwork extends StatelessWidget {
  final Uint8List bytes;
  final int cacheSize;

  const _MemoryArtwork({required this.bytes, required this.cacheSize});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Image.memory(
          bytes,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          cacheWidth: cacheSize,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          // ignore: unnecessary_underscores
          errorBuilder: (_, __, ___) {
            return const _DefaultArtwork();
          },
        ),
      ),
    );
  }
}

class _FileArtwork extends StatelessWidget {
  final String path;
  final int cacheSize;

  const _FileArtwork({required this.path, required this.cacheSize});

  @override
  Widget build(BuildContext context) {
    // Sin existsSync(): era IO síncrono en el hilo de UI. Si el archivo no
    // existe, errorBuilder ya muestra la carátula por defecto.
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Image.file(
          File(path),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          cacheWidth: cacheSize,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          // ignore: unnecessary_underscores
          errorBuilder: (_, __, ___) {
            return const _DefaultArtwork();
          },
        ),
      ),
    );
  }
}

class _DefaultArtwork extends StatelessWidget {
  const _DefaultArtwork();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.music_note_rounded,
            size: 110,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/* ========================================================================= */
/* ANDROID ARTWORK                                                           */
/* ========================================================================= */
class _AndroidAlbumArtwork extends StatefulWidget {
  final String contentUri;
  final int cacheSize;

  const _AndroidAlbumArtwork({
    required this.contentUri,
    required this.cacheSize,
  });

  @override
  State<_AndroidAlbumArtwork> createState() => _AndroidAlbumArtworkState();
}

class _AndroidAlbumArtworkState extends State<_AndroidAlbumArtwork> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _AndroidAlbumArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.contentUri != widget.contentUri) {
      _resolve();
    }
  }

  void _resolve() {
    final uri = widget.contentUri;
    final cached = ArtworkBytesLoader.peek(uri);

    // Si ya está en memoria se muestra en el mismo frame, sin parpadeo.
    if (cached != null) {
      _bytes = cached;
      _loading = false;
      return;
    }

    _bytes = null;
    _loading = true;

    unawaited(_load(uri));
  }

  Future<void> _load(String uri) async {
    final bytes = await ArtworkBytesLoader.load(uri);

    if (!mounted || uri != widget.contentUri) {
      return;
    }

    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null || _bytes!.isEmpty) {
      if (_loading) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const SizedBox.expand(),
          ),
        );
      }

      return const _DefaultArtwork();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Image.memory(
          _bytes!,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          cacheWidth: widget.cacheSize,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          // ignore: unnecessary_underscores
          errorBuilder: (_, __, ___) {
            return const _DefaultArtwork();
          },
        ),
      ),
    );
  }
}

/* ========================================================================= */
/* ARTWORK MENU                                                              */
/* ========================================================================= */

class _ArtworkMenu extends StatelessWidget {
  final BuildContext sheetContext;
  final PlayerController controller;
  final bool hasArtwork;

  const _ArtworkMenu({
    required this.sheetContext,
    required this.controller,
    required this.hasArtwork,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.save_alt_rounded),
            title: Text(l10n.saveArtwork),
            enabled: hasArtwork,
            onTap: !hasArtwork
                ? null
                : () async {
                    Navigator.of(sheetContext, rootNavigator: true).pop();

                    final saved = await controller.saveCurrentArtwork();

                    if (!context.mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            saved ? l10n.artworkSaved : l10n.artworkSaveFailed,
                          ),
                        ),
                      );
                  },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: Text(l10n.changeArtwork),
            onTap: () async {
              Navigator.of(sheetContext, rootNavigator: true).pop();

              final result = await controller.changeCurrentArtwork();

              if (!context.mounted || result == null) {
                return;
              }

              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      result ? l10n.artworkChanged : l10n.artworkChangeFailed,
                    ),
                  ),
                );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: Text(l10n.deleteArtwork),
            enabled: hasArtwork,
            onTap: !hasArtwork
                ? null
                : () async {
                    Navigator.of(sheetContext, rootNavigator: true).pop();

                    final confirmed = await _confirmDelete(context);

                    if (!confirmed) {
                      return;
                    }

                    final deleted = await controller.clearCurrentArtwork();

                    if (!context.mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            deleted
                                ? l10n.artworkDeleted
                                : l10n.artworkDeleteFailed,
                          ),
                        ),
                      );
                  },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.deleteArtwork),
          content: Text(l10n.deleteArtworkQuestion),
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

    return result == true;
  }
}

/* ========================================================================= */
/* SONG INFORMATION                                                          */
/* ========================================================================= */

class _SongTitle extends StatelessWidget {
  final Song song;

  const _SongTitle({required this.song});

  @override
  Widget build(BuildContext context) {
    final artist = song.artist?.trim();
    final theme = Theme.of(context);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Column(
        key: ValueKey('${song.id}-${song.title}-${song.artist}'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _ScrollingSongTitle(title: song.title),
          ),
          if (artist != null && artist.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              artist,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScrollingSongTitle extends StatefulWidget {
  final String title;

  const _ScrollingSongTitle({required this.title});

  @override
  State<_ScrollingSongTitle> createState() => _ScrollingSongTitleState();
}

class _ScrollingSongTitleState extends State<_ScrollingSongTitle> {
  final ScrollController _controller = ScrollController();

  double? _distance;
  int _generation = 0;

  static const double _gap = 48;

  @override
  void didUpdateWidget(covariant _ScrollingSongTitle oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.title != widget.title) {
      _distance = null;
      _generation++;

      if (_controller.hasClients) {
        _controller.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  TextStyle _style(BuildContext context) {
    return Theme.of(context).textTheme.headlineSmall!
        .copyWith(fontWeight: FontWeight.w600);
  }

  double _measure(BuildContext context, TextStyle style) {
    final mediaQuery = MediaQuery.maybeOf(context);

    final painter = TextPainter(
      text: TextSpan(text: widget.title, style: style),
      textDirection: Directionality.of(context),
      textScaler: mediaQuery?.textScaler ?? TextScaler.noScaling,
      maxLines: 1,
    );

    painter.layout();

    final width = painter.width;
    painter.dispose();

    return width;
  }

  void _configure(double distance) {
    if (_distance != null && (_distance! - distance).abs() < 0.5) {
      return;
    }

    _distance = distance;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) {
        return;
      }

      _controller.jumpTo(0);
      _startMarquee(distance);
    });
  }

  void _startMarquee(double distance) {
    _generation++;

    final generation = _generation;

    unawaited(_runMarquee(distance, generation));
  }

  Future<void> _runMarquee(double distance, int generation) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    if (!mounted || generation != _generation || !_controller.hasClients) {
      return;
    }

    try {
      await _controller.animateTo(
        distance,
        duration: Duration(
          milliseconds: ((distance / 45) * 1000).round().clamp(2200, 15000),
        ),
        curve: Curves.linear,
      );
    } catch (_) {
      return;
    }

    if (!mounted || generation != _generation) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 900));

    if (!mounted || generation != _generation || !_controller.hasClients) {
      return;
    }

    _controller.jumpTo(0);

    unawaited(_runMarquee(distance, generation));
  }

  @override
  Widget build(BuildContext context) {
    final style = _style(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final textWidth = _measure(context, style);

        if (textWidth <= availableWidth + 0.5) {
          return SizedBox(
            width: double.infinity,
            child: Text(
              widget.title,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: style,
            ),
          );
        }

        final distance = textWidth + _gap + 8;

        _configure(distance);

        return ClipRect(
          child: SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    softWrap: false,
                    style: style,
                  ),
                  const SizedBox(width: _gap),
                  Text(
                    widget.title,
                    maxLines: 1,
                    softWrap: false,
                    style: style,
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

/* ========================================================================= */
/* PROGRESS                                                                  */
/* ========================================================================= */

class _ModernProgress extends StatefulWidget {
  const _ModernProgress();

  @override
  State<_ModernProgress> createState() => _ModernProgressState();
}

class _ModernProgressState extends State<_ModernProgress> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerController, ({Duration position, Duration duration})>(
      selector: (_, controller) =>
          (position: controller.position, duration: controller.duration),
      builder: (context, data, child) {
        final controller = context.read<PlayerController>();

        final maxValue = math.max(1, data.duration.inMilliseconds).toDouble();

        final positionValue = data.position.inMilliseconds.toDouble();

        final value = (_dragValue ?? positionValue).clamp(0.0, maxValue);

        final displayPosition = Duration(milliseconds: value.round());

        return RepaintBoundary(
          child: Column(
            children: [
              Slider(
                min: 0,
                max: maxValue,
                value: value,
                onChangeStart: (value) {
                  setState(() {
                    _dragValue = value;
                  });
                },
                onChanged: (value) {
                  setState(() {
                    _dragValue = value;
                  });
                },
                onChangeEnd: (value) async {
                  await controller.seek(Duration(milliseconds: value.round()));

                  if (mounted) {
                    setState(() {
                      _dragValue = null;
                    });
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatTime(displayPosition),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      _formatTime(data.duration),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
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

    final seconds = duration.inSeconds;
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;

    return '$minutes:${remaining.toString().padLeft(2, '0')}';
  }
}

/* ========================================================================= */
/* MAIN CONTROLS                                                             */
/* ========================================================================= */

class _MainPlaybackControls extends StatelessWidget {
  const _MainPlaybackControls();

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
              icon: const Icon(Icons.skip_previous_rounded),
              iconSize: 36,
              tooltip: l10n.previous,
            ),

            FilledButton(
              onPressed: controller.togglePlayPause,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(20),
                minimumSize: const Size(78, 78),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: Icon(
                  state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  key: ValueKey(state.isPlaying),
                  size: 40,
                ),
              ),
            ),

            IconButton(
              onPressed: state.hasNext ? controller.playNext : null,
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 36,
              tooltip: l10n.next,
            ),
          ],
        );
      },
    );
  }
}

/* ========================================================================= */
/* SECONDARY CONTROLS                                                        */
/* ========================================================================= */

class _SecondaryControls extends StatelessWidget {
  const _SecondaryControls();

  @override
  Widget build(BuildContext context) {
    return Selector<
      PlayerController,
      ({bool shuffle, SonaraRepeatMode repeatMode, bool isFavorite})
    >(
      selector: (_, controller) => (
        shuffle: controller.isShuffleEnabled,
        repeatMode: controller.repeatMode,
        isFavorite: controller.isFavorite,
      ),
      builder: (context, state, child) {
        final controller = context.read<PlayerController>();

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _PlayerOptionButton(
              icon: state.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: '',
              isActive: state.isFavorite,
              onPressed: controller.toggleFavorite,
            ),

            _PlayerOptionButton(
              icon: _repeatIcon(state.repeatMode),
              label: '',
              isActive: state.repeatMode != SonaraRepeatMode.off,
              onPressed: () {
                _showRepeatModes(context);
              },
            ),

            _PlayerOptionButton(
              icon: Icons.queue_music_rounded,
              label: '',
              onPressed: () {
                _showQueue(context);
              },
            ),
          ],
        );
      },
    );
  }

  static IconData _repeatIcon(SonaraRepeatMode mode) {
    switch (mode) {
      case SonaraRepeatMode.off:
      case SonaraRepeatMode.all:
        return Icons.repeat_rounded;

      case SonaraRepeatMode.one:
        return Icons.repeat_one_rounded;
    }
  }

  void _showRepeatModes(BuildContext context) {
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
      isScrollControlled: true,
      builder: (_) {
        return const _RedesignedQueueSheet();
      },
    );
  }
}

/* ========================================================================= */
/* BOTTOM ACTIONS                                                            */
/* ========================================================================= */

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
        : theme.colorScheme.onSurfaceVariant;

    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onPressed,
                icon: Icon(icon),
                color: color,
                iconSize: 25,
                visualDensity: VisualDensity.compact,
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ========================================================================= */
/* MODES SHEET                                                               */
/* ========================================================================= */

class _ModesSheet extends StatelessWidget {
  final BuildContext sheetContext;

  const _ModesSheet({required this.sheetContext});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child:
          Selector<
            PlayerController,
            ({bool shuffle, SonaraRepeatMode repeatMode})
          >(
            selector: (_, controller) => (
              shuffle: controller.isShuffleEnabled,
              repeatMode: controller.repeatMode,
            ),
            builder: (context, state, child) {
              final controller = context.read<PlayerController>();

              final primary = Theme.of(context).colorScheme.primary;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    secondary: Icon(
                      Icons.shuffle_rounded,
                      color: state.shuffle ? primary : null,
                    ),
                    title: Text(
                      state.shuffle
                          ? l10n.shuffleEnabled
                          : l10n.shuffleDisabled,
                    ),
                    value: state.shuffle,
                    onChanged: (_) {
                      controller.toggleShuffle();
                    },
                  ),

                  _RepeatModeTile(
                    icon: Icons.repeat_rounded,
                    label: l10n.repeatOff,
                    isSelected: state.repeatMode == SonaraRepeatMode.off,
                    onTap: () {
                      controller.setRepeatMode(SonaraRepeatMode.off);

                      Navigator.of(sheetContext, rootNavigator: true).pop();
                    },
                  ),

                  _RepeatModeTile(
                    icon: Icons.repeat_one_rounded,
                    label: l10n.repeatSong,
                    isSelected: state.repeatMode == SonaraRepeatMode.one,
                    onTap: () {
                      controller.setRepeatMode(SonaraRepeatMode.one);

                      Navigator.of(sheetContext, rootNavigator: true).pop();
                    },
                  ),

                  _RepeatModeTile(
                    icon: Icons.repeat_rounded,
                    label: l10n.repeatQueue,
                    isSelected: state.repeatMode == SonaraRepeatMode.all,
                    onTap: () {
                      controller.setRepeatMode(SonaraRepeatMode.all);

                      Navigator.of(sheetContext, rootNavigator: true).pop();
                    },
                  ),

                  const SizedBox(height: 12),
                ],
              );
            },
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
    final primary = Theme.of(context).colorScheme.primary;

    return ListTile(
      leading: Icon(icon, color: isSelected ? primary : null),
      title: Text(label),
      selected: isSelected,
      onTap: onTap,
    );
  }
}

/* ========================================================================= */
/* QUEUE                                                                     */
/* ========================================================================= */

class _RedesignedQueueSheet extends StatelessWidget {
  const _RedesignedQueueSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.32,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.queueTitle,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
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
                      if (data.queue.isEmpty) {
                        return Center(child: Text(l10n.queueEmpty));
                      }

                      return ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: data.queue.length,
                        buildDefaultDragHandles: false,
                        itemBuilder: (context, index) {
                          final song = data.queue[index];

                          return _QueueItem(
                            key: ValueKey(song.id),
                            song: song,
                            index: index,
                            isCurrent: song.id == data.currentSongId,
                          );
                        },
                        // ignore: deprecated_member_use
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
    final controller = context.read<PlayerController>();

    final scheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey('queue_${song.id}'),
      direction: isCurrent
          ? DismissDirection.none
          : DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.35,
        DismissDirection.endToStart: 0.35,
      },
      background: const _QueueDismissBackground(
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: const _QueueDismissBackground(
        alignment: Alignment.centerRight,
      ),
      onDismissed: (_) {
        controller.removeFromQueue(song);
      },
      child: Material(
        color: isCurrent
            // ignore: deprecated_member_use
            ? scheme.primary.withOpacity(0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final queue = List<Song>.from(controller.queue);

            await controller.playFromQueue(queue, startIndex: index);

            if (context.mounted) {
              Navigator.of(context, rootNavigator: true).pop();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _QueueArtwork(
                  coverPath: song.coverPath,
                  coverBytes: song.coverBytes,
                  isCurrent: isCurrent,
                  size: 48,
                  borderRadius: 10,
                ),

                const SizedBox(width: 13),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isCurrent ? scheme.primary : null,
                        ),
                      ),
                      if (song.artist != null && song.artist!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          song.artist!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle_rounded),
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

class _QueueDismissBackground extends StatelessWidget {
  final Alignment alignment;

  const _QueueDismissBackground({required this.alignment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: scheme.error,
      child: Icon(Icons.remove_circle_outline_rounded, color: scheme.onError),
    );
  }
}

/* ========================================================================= */
/* QUEUE ARTWORK                                                             */
/* ========================================================================= */

class _QueueArtwork extends StatelessWidget {
  final String? coverPath;
  final Uint8List? coverBytes;
  final bool isCurrent;
  final double size;
  final double borderRadius;

  const _QueueArtwork({
    required this.coverPath,
    required this.coverBytes,
    required this.isCurrent,
    required this.size,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = coverBytes;

    if (bytes != null && bytes.isNotEmpty) {
      return _buildImage(
        context,
        Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: 128,
          cacheHeight: 128,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          // ignore: unnecessary_underscores
          errorBuilder: (_, __, ___) {
            return _fallback(context);
          },
        ),
      );
    }

    final path = coverPath;

    if (path == null || path.isEmpty) {
      return _fallback(context);
    }

    if (path.startsWith('content://')) {
      return _AndroidQueueArtwork(
        contentUri: path,
        size: size,
        borderRadius: borderRadius,
        isCurrent: isCurrent,
      );
    }

    return _buildImage(
      context,
      Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: 128,
        cacheHeight: 128,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        // ignore: unnecessary_underscores
        errorBuilder: (_, __, ___) {
          return _fallback(context);
        },
      ),
    );
  }

  Widget _buildImage(BuildContext context, Widget image) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: image,
        ),
        if (isCurrent)
          _QueuePlayingOverlay(size: size, borderRadius: borderRadius),
      ],
    );
  }

  Widget _fallback(BuildContext context) {
    final color = isCurrent
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(
          isCurrent ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
          size: size * 0.55,
          color: color,
        ),
      ),
    );
  }
}

/* ========================================================================= */
/* ANDROID QUEUE ARTWORK                                                     */
/* ========================================================================= */

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
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _AndroidQueueArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.contentUri != widget.contentUri) {
      _resolve();
    }
  }

  void _resolve() {
    final uri = widget.contentUri;
    final cached = ArtworkBytesLoader.peek(uri);

    if (cached != null) {
      _bytes = cached;
      _loading = false;
      return;
    }

    _bytes = null;
    _loading = true;

    unawaited(_load(uri));
  }

  Future<void> _load(String uri) async {
    final bytes = await ArtworkBytesLoader.load(uri);

    if (!mounted || uri != widget.contentUri) {
      return;
    }

    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null || _bytes!.isEmpty) {
      if (_loading) {
        return SizedBox(width: widget.size, height: widget.size);
      }

      return _fallback(context);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Image.memory(
            _bytes!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            cacheWidth: 128,
            cacheHeight: 128,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            // ignore: unnecessary_underscores
            errorBuilder: (_, __, ___) {
              return _fallback(context);
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

  Widget _fallback(BuildContext context) {
    final color = widget.isCurrent
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: Icon(
          widget.isCurrent
              ? Icons.graphic_eq_rounded
              : Icons.music_note_rounded,
          size: widget.size * 0.55,
          color: color,
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
        Icons.graphic_eq_rounded,
        size: size * 0.5,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
