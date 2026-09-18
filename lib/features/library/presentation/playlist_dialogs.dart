import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../data/repositories/playlists_repository.dart';
import '../domain/models/playlist.dart';

class PlaylistDialogs {
  PlaylistDialogs._();

  static Future<Playlist?> showCreatePlaylist(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return const _CreatePlaylistDialog();
      },
    );

    if (name == null || name.trim().isEmpty) {
      return null;
    }

    return PlaylistsRepository().createPlaylist(name.trim());
  }
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();

    if (name.isEmpty) {
      return;
    }

    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.newPlaylist),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: l10n.playlistName,
          hintText: l10n.playlistNameHint,
        ),
        onSubmitted: (_) {
          _submit();
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.create)),
      ],
    );
  }
}
