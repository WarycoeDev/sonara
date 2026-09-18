import 'package:flutter/material.dart';

import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'app/sonara_app.dart';
import 'features/player/presentation/controllers/player_controller.dart';
import 'app/crossfade_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CrossfadeService.instance.initialize();

  JustAudioMediaKit.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.sonara.playback',
    androidNotificationChannelName: 'Reproducción de música',
    androidNotificationOngoing: true,
    androidNotificationClickStartsActivity: true,
    androidNotificationIcon: 'drawable/ic_stat_ic_notification',
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => PlayerController(),
      child: const SonaraApp(),
    ),
  );
}
