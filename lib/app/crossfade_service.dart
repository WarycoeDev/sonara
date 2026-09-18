import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CrossfadeService {
  CrossfadeService._();

  static final CrossfadeService instance = CrossfadeService._();

  static const String _key = 'sonara_crossfade_seconds';

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

  int get seconds => secondsNotifier.value;

  bool get enabled => seconds > 0;

  Duration get duration => Duration(seconds: seconds);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    final savedValue = prefs.getInt(_key) ?? 0;

    final safeValue = availableValues.contains(savedValue) ? savedValue : 0;

    secondsNotifier.value = safeValue;
  }

  Future<void> setSeconds(int value) async {
    final safeValue = availableValues.contains(value) ? value : 0;

    secondsNotifier.value = safeValue;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_key, safeValue);
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
