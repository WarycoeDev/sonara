import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart';
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SonaraApp.themeModeNotifier,
      builder: (context, themeMode, child) {
        return ValueListenableBuilder<String>(
          valueListenable: SonaraApp.colorThemeNotifier,
          builder: (context, colorTheme, child) {
            return ValueListenableBuilder<Locale?>(
              valueListenable: SonaraApp.localeNotifier,
              builder: (context, locale, child) {
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

                  theme: AppTheme.lightTheme(colorTheme),
                  darkTheme: AppTheme.darkTheme(colorTheme),
                  themeMode: themeMode,
                  home: const AppShell(),
                );
              },
            );
          },
        );
      },
    );
  }
}
