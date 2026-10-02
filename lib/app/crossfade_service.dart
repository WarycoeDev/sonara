import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sonara/core/services/sonara_storage_service.dart';

class CrossfadeService {
  CrossfadeService._();

  static final CrossfadeService instance = CrossfadeService._();

  static const String _fileName = 'crossfade_settings.json';

  static const List<int> availableValues = [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
  ];

  final ValueNotifier<int> secondsNotifier = ValueNotifier<int>(0);

  bool _initialized = false;
  Future<void>? _initializeFuture;

  int get seconds => secondsNotifier.value;

  bool get enabled => seconds > 0;

  Duration get duration => Duration(seconds: seconds);

  /// Obtiene la referencia al archivo JSON de configuración en la carpeta `files`.
  Future<File> _getStorageFile() async {
    final filesDirectory = await SonaraStorageService.getFilesDirectory();
    return File(p.join(filesDirectory.path, _fileName));
  }

  Future<void> initialize() {
    if (_initialized) {
      return Future<void>.value();
    }

    final currentInitialization = _initializeFuture;

    if (currentInitialization != null) {
      return currentInitialization;
    }

    final initialization = _performInitialize();

    _initializeFuture = initialization;

    return initialization.whenComplete(() {
      if (identical(_initializeFuture, initialization)) {
        _initializeFuture = null;
      }
    });
  }

  Future<void> _performInitialize() async {
    try {
      final file = await _getStorageFile();

      if (await file.exists()) {
        final content = await file.readAsString(encoding: utf8);

        if (content.isNotEmpty) {
          final decoded = jsonDecode(content);

          if (decoded is Map<String, dynamic>) {
            final savedValue = decoded['crossfade_seconds'];

            if (savedValue is int && availableValues.contains(savedValue)) {
              secondsNotifier.value = savedValue;
            }
          }
        }
      }

      _initialized = true;
    } catch (error) {
      debugPrint('[CrossfadeService] Error al cargar configuración: $error');
      _initialized = false;
    }
  }

  Future<void> setSeconds(int value) async {
    await initialize();

    final safeValue = availableValues.contains(value) ? value : 0;

    secondsNotifier.value = safeValue;

    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _getStorageFile();

      final data = {'crossfade_seconds': secondsNotifier.value};

      await file.writeAsString(jsonEncode(data), encoding: utf8, flush: true);
    } catch (error) {
      debugPrint('[CrossfadeService] Error al guardar configuración: $error');
    }
  }

  String get displayName {
    if (seconds <= 0) {
      return 'Desactivado';
    }

    return '$seconds segundos';
  }

  void dispose() {
    secondsNotifier.dispose();
  }
}
