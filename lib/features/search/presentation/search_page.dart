import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';

import '../../library/data/repositories/local_library_repository.dart';
import '../../library/domain/models/song.dart';
import '../../library/presentation/song_options.dart';
import '../../player/presentation/controllers/player_controller.dart';
import '../../search/data/services/youtube_download_service.dart';
import '../../search/data/services/youtube_search_service.dart';
import 'youtube_download_dialog.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();

  final FocusNode _searchFocusNode = FocusNode();

  final LocalLibraryRepository _libraryRepository = LocalLibraryRepository();

  final YouTubeSearchService _youtubeSearchService = YouTubeSearchService();

  final YouTubeDownloadService _youtubeDownloadService =
      YouTubeDownloadService();

  final ValueNotifier<_SearchState> _searchState = ValueNotifier(
    const _SearchState.idle(),
  );

  Timer? _searchDebounce;

  int _requestToken = 0;
  int _youtubeRequestToken = 0;

  bool _isDownloading = false;

  void _dismissKeyboard() {
    _searchFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void initState() {
    super.initState();

    _searchController.addListener(_onSearchChanged);
  }

  // CAMBIO EN LA BARRA DE BÚSQUEDA

  void _onSearchChanged() {
    final query = _searchController.text.trim();

    _searchDebounce?.cancel();

    _youtubeRequestToken++;

    if (query.isEmpty) {
      _requestToken++;

      _searchState.value = const _SearchState.idle();

      return;
    }

    _searchState.value = _searchState.value.copyWithQuery(query);

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _performSearch(query);
    });
  }

  // BÚSQUEDA LOCAL

  Future<void> _performSearch(String query) async {
    if (!mounted) {
      return;
    }

    final myToken = ++_requestToken;

    _searchState.value = _searchState.value.copyWith(
      query: query,
      isSearching: true,
    );

    try {
      final results = await _libraryRepository.searchSongs(query);

      if (!mounted || myToken != _requestToken) {
        return;
      }

      if (_searchState.value.query != query) {
        return;
      }

      _searchState.value = _searchState.value.copyWith(
        query: query,
        isSearching: false,
        results: results,
      );
    } catch (error) {
      if (!mounted || myToken != _requestToken) {
        return;
      }

      _searchState.value = _searchState.value.copyWith(
        query: query,
        isSearching: false,
        results: const [],
      );

      debugPrint('Error buscando en la biblioteca: $error');
    }
  }

  // BÚSQUEDA EN YOUTUBE

  Future<void> _searchYouTube(String query) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return;
    }

    final myToken = ++_youtubeRequestToken;

    _searchState.value = _searchState.value.copyWith(
      isYouTubeSearching: true,
      isLoadingMoreYouTube: false,
      hasSearchedYouTube: true,
      hasMoreYouTube: false,
      youtubeResults: const [],
    );

    try {
      final results = await _youtubeSearchService.search(trimmedQuery);

      if (!mounted || myToken != _youtubeRequestToken) {
        return;
      }

      if (_searchState.value.query != trimmedQuery) {
        return;
      }

      _searchState.value = _searchState.value.copyWith(
        isYouTubeSearching: false,
        isLoadingMoreYouTube: false,
        hasSearchedYouTube: true,
        hasMoreYouTube: results.isNotEmpty,
        youtubeResults: results,
      );
    } catch (error, stackTrace) {
      if (!mounted || myToken != _youtubeRequestToken) {
        return;
      }

      _searchState.value = _searchState.value.copyWith(
        isYouTubeSearching: false,
        isLoadingMoreYouTube: false,
        hasSearchedYouTube: true,
        hasMoreYouTube: false,
        youtubeResults: const [],
      );

      debugPrint('Error buscando en YouTube: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // CARGAR MÁS RESULTADOS DE YOUTUBE

  Future<void> _loadMoreYouTube() async {
    final currentState = _searchState.value;

    if (currentState.isLoadingMoreYouTube ||
        currentState.isYouTubeSearching ||
        !currentState.hasMoreYouTube ||
        !currentState.hasSearchedYouTube) {
      return;
    }

    final currentQuery = currentState.query;

    if (currentQuery.isEmpty) {
      return;
    }

    final myToken = _youtubeRequestToken;

    _searchState.value = currentState.copyWith(isLoadingMoreYouTube: true);

    try {
      final newResults = await _youtubeSearchService.loadMore();

      if (!mounted || myToken != _youtubeRequestToken) {
        return;
      }

      if (_searchState.value.query != currentQuery) {
        return;
      }

      final existingResults = List<YouTubeSearchResult>.from(
        _searchState.value.youtubeResults,
      );

      final existingIds = existingResults.map((result) => result.id).toSet();

      final uniqueNewResults = newResults.where(
        (result) => existingIds.add(result.id),
      );

      existingResults.addAll(uniqueNewResults);

      _searchState.value = _searchState.value.copyWith(
        isLoadingMoreYouTube: false,
        hasMoreYouTube: newResults.isNotEmpty,
        youtubeResults: existingResults,
      );
    } catch (error, stackTrace) {
      if (!mounted || myToken != _youtubeRequestToken) {
        return;
      }

      _searchState.value = _searchState.value.copyWith(
        isLoadingMoreYouTube: false,
      );

      debugPrint('Error cargando más resultados de YouTube: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // DESCARGAR AUDIO DE YOUTUBE

  Future<void> _downloadYouTubeAudio(
    BuildContext context,
    YouTubeSearchResult result,
  ) async {
    _dismissKeyboard();

    if (_isDownloading) {
      return;
    }

    final request = await YouTubeDownloadDialog.show(context, result);

    _dismissKeyboard();

    if (request == null || !mounted || !context.mounted) {
      return;
    }

    _isDownloading = true;

    final l10n = AppLocalizations.of(context)!;

    final progressNotifier = ValueNotifier<double>(0);
    final statusNotifier = ValueNotifier<String>(l10n.downloadPreparing);
    final completedNotifier = ValueNotifier<bool>(false);
    final errorNotifier = ValueNotifier<String?>(null);

    var progressDialogOpen = false;

    try {
      _dismissKeyboard();

      progressDialogOpen = true;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          final colorScheme = theme.colorScheme;
          final dialogL10n = AppLocalizations.of(dialogContext)!;

          return PopScope(
            canPop: false,
            child: AlertDialog(
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              content: ValueListenableBuilder<bool>(
                valueListenable: completedNotifier,
                builder: (context, completed, _) {
                  return ValueListenableBuilder<String?>(
                    valueListenable: errorNotifier,
                    builder: (context, errorMessage, _) {
                      final hasError = errorMessage != null;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (completed)
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 30,
                                color: colorScheme.primary,
                              ),
                            )
                          else if (hasError)
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.error_outline_rounded,
                                size: 28,
                                color: colorScheme.error,
                              ),
                            )
                          else
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.download_rounded,
                                size: 28,
                                color: colorScheme.primary,
                              ),
                            ),

                          const SizedBox(height: 20),

                          Text(
                            completed
                                ? dialogL10n.downloadCompleted
                                : hasError
                                ? dialogL10n.downloadFailed
                                : dialogL10n.downloadingAudio,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 8),

                          if (!completed && !hasError)
                            ValueListenableBuilder<String>(
                              valueListenable: statusNotifier,
                              builder: (context, status, _) {
                                return Text(
                                  status,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                );
                              },
                            ),

                          if (completed)
                            Text(
                              dialogL10n.downloadSuccessDescription,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),

                          if (hasError)
                            Text(
                              errorMessage,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),

                          if (!completed && !hasError) ...[
                            const SizedBox(height: 24),

                            ValueListenableBuilder<double>(
                              valueListenable: progressNotifier,
                              builder: (context, progress, _) {
                                final normalizedProgress = progress.clamp(
                                  0.0,
                                  100.0,
                                );

                                return Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: normalizedProgress / 100,
                                        minHeight: 8,
                                        backgroundColor:
                                            colorScheme.surfaceContainerHighest,
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    Text(
                                      '${normalizedProgress.toStringAsFixed(0)}%',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: colorScheme.primary,
                                          ),
                                    ),
                                  ],
                                );
                              },
                            ),

                            const SizedBox(height: 16),

                            Text(
                              dialogL10n.downloadMayTake,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant.withOpacity(
                                  0.55,
                                ),
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],

                          if (completed || hasError) ...[
                            const SizedBox(height: 24),

                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () {
                                  if (dialogContext.mounted) {
                                    Navigator.of(
                                      dialogContext,
                                      rootNavigator: true,
                                    ).pop();
                                  }
                                },
                                child: Text(dialogL10n.close),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      );

      final downloadedSong = await _youtubeDownloadService.downloadAudio(
        result: request.result,
        fileName: request.fileName,
        onProgress: (progress) {
          if (!progressNotifier.hasListeners) {
            return;
          }

          progressNotifier.value = progress;

          if (progress <= 0) {
            statusNotifier.value = l10n.downloadPreparing;
          } else if (progress >= 100) {
            statusNotifier.value = l10n.finishingConverting;
          } else {
            statusNotifier.value =
                '${l10n.downloadingAudio}... ${progress.toStringAsFixed(0)}%';
          }
        },
      );

      try {
        statusNotifier.value = l10n.updatingLibrary;

        await _libraryRepository.scanLibrary();
      } catch (error, stackTrace) {
        debugPrint(
          'Error actualizando biblioteca después de descargar: $error',
        );

        debugPrintStack(stackTrace: stackTrace);
      }

      completedNotifier.value = true;

      if (request.addToPlaylist) {
        debugPrint(
          'Pendiente: agregar "${downloadedSong.title}" a una playlist.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Error descargando audio de YouTube: $error');

      debugPrintStack(stackTrace: stackTrace);

      errorNotifier.value = l10n.downloadFailed;
    } finally {
      _isDownloading = false;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();

    _youtubeSearchService.dispose();

    _youtubeDownloadService.dispose();

    _searchFocusNode.dispose();

    _searchController.dispose();

    _searchState.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _dismissKeyboard,
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              // ===============================================================
              // DESCRIPCIÓN
              // ===============================================================
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Text(
                    l10n.searchDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

              // ===============================================================
              // BARRA DE BÚSQUEDA
              // ===============================================================
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _SearchField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    searchState: _searchState,
                  ),
                ),
              ),

              // ===============================================================
              // BOTÓN YOUTUBE
              // ===============================================================
              if (Platform.isAndroid)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                    child: ValueListenableBuilder<_SearchState>(
                      valueListenable: _searchState,
                      builder: (context, state, _) {
                        return _SearchActions(
                          query: state.query,
                          isSearching: state.isYouTubeSearching,
                          onSearchYouTube: () {
                            _searchYouTube(state.query);
                          },
                        );
                      },
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // ===============================================================
              // RESULTADOS
              // ===============================================================
              ValueListenableBuilder<_SearchState>(
                valueListenable: _searchState,
                builder: (context, state, _) {
                  if (state.hasQuery) {
                    return _SearchResultsSliver(
                      state: state,
                      theme: theme,
                      onLoadMoreYouTube: _loadMoreYouTube,
                      onDownloadYouTube: _downloadYouTubeAudio,
                    );
                  }

                  return const _DefaultSearchViewSliver();
                },
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }
}

// ESTADO DE BÚSQUEDA

class _SearchState {
  final String query;

  final bool isSearching;

  final List<Song> results;

  final bool isYouTubeSearching;

  final bool isLoadingMoreYouTube;

  final bool hasSearchedYouTube;

  final bool hasMoreYouTube;

  final List<YouTubeSearchResult> youtubeResults;

  const _SearchState({
    required this.query,
    required this.isSearching,
    required this.results,
    required this.isYouTubeSearching,
    required this.isLoadingMoreYouTube,
    required this.hasSearchedYouTube,
    required this.hasMoreYouTube,
    required this.youtubeResults,
  });

  const _SearchState.idle()
    : query = '',
      isSearching = false,
      results = const [],
      isYouTubeSearching = false,
      isLoadingMoreYouTube = false,
      hasSearchedYouTube = false,
      hasMoreYouTube = false,
      youtubeResults = const [];

  bool get hasQuery => query.isNotEmpty;

  _SearchState copyWith({
    String? query,
    bool? isSearching,
    List<Song>? results,
    bool? isYouTubeSearching,
    bool? isLoadingMoreYouTube,
    bool? hasSearchedYouTube,
    bool? hasMoreYouTube,
    List<YouTubeSearchResult>? youtubeResults,
  }) {
    return _SearchState(
      query: query ?? this.query,
      isSearching: isSearching ?? this.isSearching,
      results: results ?? this.results,
      isYouTubeSearching: isYouTubeSearching ?? this.isYouTubeSearching,
      isLoadingMoreYouTube: isLoadingMoreYouTube ?? this.isLoadingMoreYouTube,
      hasSearchedYouTube: hasSearchedYouTube ?? this.hasSearchedYouTube,
      hasMoreYouTube: hasMoreYouTube ?? this.hasMoreYouTube,
      youtubeResults: youtubeResults ?? this.youtubeResults,
    );
  }

  _SearchState copyWithQuery(String query) {
    return _SearchState(
      query: query,
      isSearching: false,
      results: const [],
      isYouTubeSearching: false,
      isLoadingMoreYouTube: false,
      hasSearchedYouTube: false,
      hasMoreYouTube: false,
      youtubeResults: const [],
    );
  }
}

enum _DownloadDialogStatus { downloading, success, error }

class _DownloadDialogState {
  final _DownloadDialogStatus status;

  final String title;

  final String message;

  const _DownloadDialogState({
    required this.status,
    required this.title,
    required this.message,
  });

  const _DownloadDialogState.downloading()
    : status = _DownloadDialogStatus.downloading,
      title = 'Descargando audio',
      message = 'Preparando la descarga y convirtiendo el audio a MP3...';

  _DownloadDialogState.success(String message)
    : status = _DownloadDialogStatus.success,
      title = 'Descarga completada',
      message = message;

  _DownloadDialogState.error(String message)
    : status = _DownloadDialogStatus.error,
      title = 'Error en la descarga',
      message = message;
}

// BARRA DE BÚSQUEDA

class _SearchField extends StatelessWidget {
  final TextEditingController controller;

  final FocusNode focusNode;

  final ValueNotifier<_SearchState> searchState;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.searchState,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: ValueListenableBuilder<_SearchState>(
        valueListenable: searchState,
        builder: (context, state, _) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            onTapOutside: (_) {
              focusNode.unfocus();
            },
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: l10n.searchFieldHint,
              hintStyle: TextStyle(
                color: colorScheme.onSurfaceVariant.withOpacity(0.75),
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: colorScheme.primary,
              ),
              suffixIcon: state.hasQuery
                  ? IconButton(
                      onPressed: () {
                        controller.clear();
                        focusNode.unfocus();
                      },
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: l10n.clearSearch,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 17,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ACCIONES DE BÚSQUEDA

class _SearchActions extends StatelessWidget {
  final String query;

  final bool isSearching;

  final VoidCallback onSearchYouTube;

  const _SearchActions({
    required this.query,
    required this.isSearching,
    required this.onSearchYouTube,
  });

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isSearching ? null : onSearchYouTube,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.7),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colorScheme.primary.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSearching)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.play_circle_fill_rounded,
                    size: 17,
                    color: colorScheme.primary,
                  ),
                const SizedBox(width: 7),
                Text(
                  isSearching ? l10n.searchingYouTube : l10n.searchAlsoYouTube,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                if (!isSearching) ...[
                  const SizedBox(width: 5),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// RESULTADOS

class _SearchResultsSliver extends StatelessWidget {
  final _SearchState state;

  final ThemeData theme;

  final VoidCallback onLoadMoreYouTube;

  final Future<void> Function(BuildContext context, YouTubeSearchResult result)
  onDownloadYouTube;

  const _SearchResultsSliver({
    required this.state,
    required this.theme,
    required this.onLoadMoreYouTube,
    required this.onDownloadYouTube,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final hasLocalResults = state.results.isNotEmpty;
    final hasYouTubeResults = state.youtubeResults.isNotEmpty;

    return SliverMainAxisGroup(
      slivers: [
        if (state.isSearching && !hasLocalResults)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 56),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),

        if (hasLocalResults) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.localResults(state.results.length),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (state.isSearching)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.separated(
              itemCount: state.results.length,
              itemBuilder: (context, index) {
                final song = state.results[index];

                return RepaintBoundary(
                  child: _SearchSongListTile(
                    key: ValueKey(song.id),
                    song: song,
                  ),
                );
              },
              separatorBuilder: (_, __) {
                return Divider(
                  height: 1,
                  indent: 70,
                  color: colorScheme.outlineVariant.withOpacity(0.45),
                );
              },
            ),
          ),
        ],

        if (!state.isSearching &&
            !hasLocalResults &&
            !state.hasSearchedYouTube &&
            !state.isYouTubeSearching)
          _EmptyResultsSliver(query: state.query),

        if (state.isYouTubeSearching)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.searchingYouTube,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (state.hasSearchedYouTube &&
            !state.isYouTubeSearching &&
            hasYouTubeResults)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.play_circle_fill_rounded,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.youtubeResults(state.youtubeResults.length),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (state.hasSearchedYouTube &&
            !state.isYouTubeSearching &&
            hasYouTubeResults)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.separated(
              itemCount: state.youtubeResults.length,
              itemBuilder: (context, index) {
                final result = state.youtubeResults[index];

                return RepaintBoundary(
                  child: _YouTubeSearchListTile(
                    key: ValueKey(result.id),
                    result: result,
                    onDownload: onDownloadYouTube,
                  ),
                );
              },
              separatorBuilder: (_, __) {
                return Divider(
                  height: 1,
                  indent: 118,
                  color: colorScheme.outlineVariant.withOpacity(0.45),
                );
              },
            ),
          ),

        if (state.hasSearchedYouTube &&
            !state.isYouTubeSearching &&
            hasYouTubeResults)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Center(
                child: state.isLoadingMoreYouTube
                    ? SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: colorScheme.primary,
                        ),
                      )
                    : state.hasMoreYouTube
                    ? OutlinedButton.icon(
                        onPressed: onLoadMoreYouTube,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(l10n.showMore),
                      )
                    : Text(
                        l10n.noMoreResults,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ),

        if (state.hasSearchedYouTube &&
            !state.isYouTubeSearching &&
            !hasYouTubeResults)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              child: Column(
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 36,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noYouTubeResults,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.tryAnotherSearch,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// RESULTADO DE YOUTUBE

class _YouTubeSearchListTile extends StatelessWidget {
  final YouTubeSearchResult result;

  final Future<void> Function(BuildContext context, YouTubeSearchResult result)
  onDownload;

  const _YouTubeSearchListTile({
    super.key,
    required this.result,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () async {
        await onDownload(context, result);
      },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Image.network(
                    result.thumbnailUrl,
                    width: 112,
                    height: 63,
                    fit: BoxFit.cover,
                    cacheWidth: 256,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, __, ___) {
                      return Container(
                        width: 112,
                        height: 63,
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.play_circle_outline_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                  if (result.duration != null)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatYouTubeDuration(result.duration!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// SIN RESULTADOS

class _EmptyResultsSliver extends StatelessWidget {
  final String query;

  const _EmptyResultsSliver({required this.query});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 32,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.noLibraryResults(query),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.noLibraryMatches,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// VISTA INICIAL

class _DefaultSearchViewSliver extends StatelessWidget {
  const _DefaultSearchViewSliver();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.65),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.manage_search_rounded,
                  size: 42,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                l10n.whatToListen,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                l10n.searchDescriptionLong,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// CANCIÓN LOCAL

class _SearchSongListTile extends StatelessWidget {
  final Song song;

  const _SearchSongListTile({super.key, required this.song});

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
        final dialogL10n = AppLocalizations.of(dialogContext)!;

        return AlertDialog(
          title: Text(dialogL10n.playbackTitle),
          content: Text(
            isCurrentSong
                ? dialogL10n.currentlyPlayingMessage
                : isInQueue
                ? dialogL10n.alreadyInQueueMessage
                : dialogL10n.queueContainsSongsMessage,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_SongTapAction.cancel);
              },
              child: Text(dialogL10n.cancel),
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
                child: Text(
                  isInQueue
                      ? dialogL10n.removeFromQueue
                      : dialogL10n.addToQueue,
                ),
              ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_SongTapAction.replaceQueue);
              },
              child: Text(dialogL10n.replaceQueue),
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
    final artist = song.artist;

    final hasArtist = artist != null && artist.trim().isNotEmpty;

    final l10n = AppLocalizations.of(context)!;

    return Selector<PlayerController, bool>(
      selector: (_, controller) {
        return controller.currentSong?.id == song.id;
      },
      builder: (context, isCurrentSong, _) {
        final theme = Theme.of(context);

        return ListTile(
          onTap: () {
            _handleSongTap(context);
          },
          onLongPress: () {
            SongOptions.show(context, song);
          },
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          leading: _LibraryArtwork(
            coverPath: song.coverPath,
            size: 48,
            borderRadius: 10,
            isPlaying: isCurrentSong,
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: isCurrentSong
                ? theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  )
                : theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
          ),
          subtitle: hasArtist
              ? Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatDuration(song.duration),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () {
                  SongOptions.show(context, song);
                },
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                tooltip: l10n.options,
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _SongTapAction { replaceQueue, addToQueue, removeFromQueue, cancel }

// GESTIÓN DE CARÁTULAS

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
        if (isPlaying) _PlayingOverlay(size: size, borderRadius: borderRadius),
      ],
    );
  }

  Widget _buildFallback(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Icon(
          isPlaying ? Icons.graphic_eq : fallbackIcon,
          size: size * 0.45,
          color: isPlaying ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// CARÁTULAS ANDROID

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

  int _requestId = 0;

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
    final requestId = ++_requestId;

    final uri = widget.uri;

    if (_coverCache.containsKey(uri)) {
      if (!mounted || requestId != _requestId) {
        return;
      }

      setState(() {
        _bytes = _coverCache[uri];
        _loading = false;
      });

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

      if (!mounted || requestId != _requestId) {
        return;
      }

      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) {
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
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: Center(
        child: Icon(
          widget.isPlaying ? Icons.graphic_eq : widget.fallbackIcon,
          size: widget.size * 0.45,
          color: widget.isPlaying
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// INDICADOR DE REPRODUCCIÓN

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
        color: Colors.black54,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        Icons.graphic_eq,
        color: Theme.of(context).colorScheme.primary,
        size: size * 0.45,
      ),
    );
  }
}

// FORMATO DURACIÓN LOCAL

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;

  final minutes = totalSeconds ~/ 60;

  final seconds = totalSeconds % 60;

  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

// FORMATO DURACIÓN YOUTUBE

String _formatYouTubeDuration(Duration duration) {
  final hours = duration.inHours;

  final minutes = duration.inMinutes.remainder(60);

  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _formatEta(Duration duration) {
  final minutes = duration.inMinutes;

  final seconds = duration.inSeconds.remainder(60);

  if (minutes > 0) {
    return '$minutes min ${seconds.toString().padLeft(2, '0')} s';
  }

  return '$seconds s';
}
