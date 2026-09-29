import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../search/data/services/youtube_search_service.dart';

class YouTubeDownloadDialog {
  YouTubeDownloadDialog._();

  static Future<YouTubeDownloadRequest?> show(
    BuildContext context,
    YouTubeSearchResult result,
  ) async {
    return showModalBottomSheet<YouTubeDownloadRequest>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return _YouTubeDownloadSheet(result: result);
      },
    );
  }
}

// MODELO DE LA SOLICITUD

class YouTubeDownloadRequest {
  final YouTubeSearchResult result;

  final String fileName;

  final bool addToPlaylist;

  const YouTubeDownloadRequest({
    required this.result,
    required this.fileName,
    required this.addToPlaylist,
  });
}

// MENÚ DE DESCARGA

class _YouTubeDownloadSheet extends StatefulWidget {
  final YouTubeSearchResult result;

  const _YouTubeDownloadSheet({required this.result});

  @override
  State<_YouTubeDownloadSheet> createState() => _YouTubeDownloadSheetState();
}

class _YouTubeDownloadSheetState extends State<_YouTubeDownloadSheet> {
  late final TextEditingController _fileNameController;

  bool _addToPlaylist = false;

  @override
  void initState() {
    super.initState();

    _fileNameController = TextEditingController(
      text: _cleanFileName(widget.result.title),
    );
  }

  @override
  void dispose() {
    _fileNameController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.viewInsetsOf(context).bottom;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // =========================================================
              // TÍTULO
              // =========================================================

              Text(
                l10n.downloadAudio,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 16),

              // =========================================================
              // INFORMACIÓN DEL VIDEO
              // =========================================================
              Material(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          widget.result.thumbnailUrl,
                          width: 112,
                          height: 63,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 112,
                              height: 63,
                              color: colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.music_note_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.result.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            const SizedBox(height: 3),

                            Text(
                              widget.result.author,
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
              ),

              const SizedBox(height: 24),

              // =========================================================
              // NOMBRE DEL ARCHIVO
              // =========================================================
              Text(
                l10n.fileName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 8),

              Material(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: TextField(
                  controller: _fileNameController,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.drive_file_rename_outline_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    suffixText: '.mp3',
                    suffixStyle: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // =========================================================
              // FORMATO
              // =========================================================
              Text(
                l10n.format,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 8),

              Material(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.audio_file_rounded,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MP3',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            const SizedBox(height: 3),

                            Text(
                              l10n.mp3CompatibleDescription,
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
              ),

              const SizedBox(height: 24),

              // =========================================================
              // PLAYLIST
              // =========================================================
              Text(
                l10n.afterDownload,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 8),

              Material(
                color: _addToPlaylist
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    setState(() {
                      _addToPlaylist = !_addToPlaylist;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: Icon(
                              _addToPlaylist
                                  ? Icons.playlist_add_check_rounded
                                  : Icons.playlist_add_rounded,
                              color: _addToPlaylist
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.addToPlaylist,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: _addToPlaylist
                                      ? colorScheme.onPrimaryContainer
                                      : null,
                                ),
                              ),

                              const SizedBox(height: 3),

                              Text(
                                _addToPlaylist
                                    ? l10n.playlistWillBeSelected
                                    : l10n.optional,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _addToPlaylist
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),

                        Checkbox(
                          value: _addToPlaylist,
                          onChanged: (value) {
                            setState(() {
                              _addToPlaylist = value ?? false;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // =========================================================
              // BOTONES
              // =========================================================
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(l10n.cancel),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        final fileName = _cleanFileName(
                          _fileNameController.text,
                        );

                        if (fileName.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.enterFileName)),
                          );

                          return;
                        }

                        Navigator.of(context).pop(
                          YouTubeDownloadRequest(
                            result: widget.result,
                            fileName: fileName,
                            addToPlaylist: _addToPlaylist,
                          ),
                        );
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: Text(l10n.download),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _cleanFileName(String value) {
    var result = value.trim();

    // Eliminamos extensiones si el usuario las escribió.
    const extensions = ['.mp3', '.m4a', '.aac', '.webm', '.ogg'];

    for (final extension in extensions) {
      if (result.toLowerCase().endsWith(extension)) {
        result = result.substring(0, result.length - extension.length);
        break;
      }
    }

    // Caracteres inválidos para nombres de archivo.
    result = result.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');

    return result.trim();
  }
}
