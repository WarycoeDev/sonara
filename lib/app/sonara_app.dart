import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart';
import 'dynamic_accent_service.dart';
import 'locale_service.dart';
import 'theme_service.dart';

class SonaraApp extends StatefulWidget {
  const SonaraApp({super.key});

  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static final ValueNotifier<String> colorThemeNotifier = ValueNotifier<String>(
    AppTheme.defaultColorTheme,
  );

  static final ValueNotifier<Locale?> localeNotifier = ValueNotifier<Locale?>(
    null,
  );

  @override
  State<SonaraApp> createState() => _SonaraAppState();
}

class _SonaraAppState extends State<SonaraApp> {
  // Se junta todo en un solo Listenable para no anidar builders.
  late final Listenable _appListenable = Listenable.merge([
    SonaraApp.themeModeNotifier,
    SonaraApp.colorThemeNotifier,
    SonaraApp.localeNotifier,
    DynamicAccentService.instance.accentNotifier,
  ]);

  @override
  void initState() {
    super.initState();
    _loadThemes();
  }

  Future<void> _loadThemes() async {
    final themeMode = await ThemeService.loadThemeMode();
    final savedColorTheme = await ThemeService.loadColorTheme();
    final savedLocale = await LocaleService.loadLocale();

    final colorTheme = AppTheme.colorThemes.containsKey(savedColorTheme)
        ? savedColorTheme
        : AppTheme.defaultColorTheme;

    SonaraApp.themeModeNotifier.value = themeMode;
    SonaraApp.colorThemeNotifier.value = colorTheme;
    SonaraApp.localeNotifier.value = savedLocale;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _appListenable,
      builder: (context, child) {
        final themeMode = SonaraApp.themeModeNotifier.value;
        final colorTheme = SonaraApp.colorThemeNotifier.value;
        final locale = SonaraApp.localeNotifier.value;

        // Color de la carátula; null = usar el color elegido en Ajustes.
        final accent = DynamicAccentService.instance.accentNotifier.value;

        return MaterialApp(
          title: 'Sonara',
          debugShowCheckedModeBanner: false,

          locale: locale,

          supportedLocales: const [Locale('es'), Locale('en')],

          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          theme: AppTheme.lightTheme(colorTheme, accentOverride: accent),
          darkTheme: AppTheme.darkTheme(colorTheme, accentOverride: accent),
          themeMode: themeMode,

          // Transición suave al cambiar de acento entre canciones.
          themeAnimationDuration: const Duration(milliseconds: 450),
          themeAnimationCurve: Curves.easeOutCubic,

          home: child,
        );
      },
      // AppShell se construye una sola vez y no se recrea al cambiar el tema.
      child: const AppShell(),
    );
  }
}
