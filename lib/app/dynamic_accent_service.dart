import 'package:flutter/material.dart';

import '../features/library/domain/models/song.dart';
import '../features/player/data/services/cover_color_service.dart';

/// Color de acento que sale de la carátula de la canción actual.
///
/// `accentNotifier.value == null` significa "usa el color elegido en Ajustes":
/// pasa cuando no hay nada reproduciéndose o la canción no tiene carátula.
class DynamicAccentService {
  DynamicAccentService._();

  static final DynamicAccentService instance = DynamicAccentService._();

  final ValueNotifier<Color?> accentNotifier = ValueNotifier<Color?>(null);

  String? _requestedKey;

  Future<void> updateForSong(Song? song) async {
    if (song == null) {
      _requestedKey = null;
      accentNotifier.value = null;
      return;
    }

    final key = CoverColorService.keyFor(song);

    if (key == _requestedKey) {
      return;
    }

    _requestedKey = key;

    final cached = CoverColorService.instance.peek(song);

    if (cached != null) {
      accentNotifier.value = cached;
      return;
    }

    // Mientras carga se conserva el acento anterior para que no parpadee.
    final seed = await CoverColorService.instance.seedFor(song);

    // Ignora el resultado si mientras tanto cambió la canción.
    if (key != _requestedKey) {
      return;
    }

    accentNotifier.value = seed;
  }
}
