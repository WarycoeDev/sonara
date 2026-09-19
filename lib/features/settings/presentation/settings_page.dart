import 'package:flutter/material.dart';

import '../../../app/crossfade_service.dart';
import '../../../app/locale_service.dart';
import '../../../app/sonara_app.dart';
import '../../../app/theme_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ThemeMode get _themeMode => SonaraApp.themeModeNotifier.value;

  Locale? get _locale => SonaraApp.localeNotifier.value;

  String get _themeName {
    final l10n = AppLocalizations.of(context)!;

    switch (_themeMode) {
      case ThemeMode.light:
        return l10n.light;
      case ThemeMode.dark:
        return l10n.dark;
      case ThemeMode.system:
        return l10n.system;
    }
  }

  String get _languageName {
    final locale = _locale;
    final l10n = AppLocalizations.of(context)!;

    if (locale == null) {
      return l10n.system;
    }

    switch (locale.languageCode) {
      case 'es':
        return 'Español';
      case 'en':
        return 'English';
      default:
        return l10n.system;
    }
  }

  String _getColorThemeName(BuildContext context, String colorTheme) {
    final l10n = AppLocalizations.of(context)!;

    switch (colorTheme) {
      case 'sonara':
        return l10n.colorSonara;
      case 'violeta':
        return l10n.colorVioleta;
      case 'esmeralda':
        return l10n.colorEsmeralda;
      case 'naranja':
        return l10n.colorNaranja;
      case 'rojo':
        return l10n.colorRojo;
      case 'rosa':
        return l10n.colorRosa;
      case 'cian':
        return l10n.colorCian;
      default:
        return colorTheme;
    }
  }

  String get _colorThemeName {
    final colorTheme = SonaraApp.colorThemeNotifier.value;

    return _getColorThemeName(context, colorTheme);
  }

  Future<void> _setTheme(ThemeMode themeMode) async {
    SonaraApp.themeModeNotifier.value = themeMode;

    await ThemeService.saveThemeMode(themeMode);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openSourceCode() async {
    final uri = Uri.parse('https://github.com/WarycoeDev/sonara');

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('No se pudo abrir Source Code: $e');
    }
  }

  Future<void> _setColorTheme(String colorTheme) async {
    SonaraApp.colorThemeNotifier.value = colorTheme;

    await ThemeService.saveColorTheme(colorTheme);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _setLocale(Locale? locale) async {
    SonaraApp.localeNotifier.value = locale;

    if (locale == null) {
      await LocaleService.clearLocale();
    } else {
      await LocaleService.saveLocale(locale);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: SonaraApp.themeModeNotifier,
          builder: (context, currentThemeMode, child) {
            final l10n = AppLocalizations.of(context)!;

            return AlertDialog(
              title: Text(l10n.appearanceMode),
              contentPadding: const EdgeInsets.only(top: 8, bottom: 8),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<ThemeMode>(
                    title: Text(l10n.system),
                    value: ThemeMode.system,
                    groupValue: currentThemeMode,
                    onChanged: (value) async {
                      if (value == null) {
                        return;
                      }

                      await _setTheme(value);

                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text(l10n.light),
                    value: ThemeMode.light,
                    groupValue: currentThemeMode,
                    onChanged: (value) async {
                      if (value == null) {
                        return;
                      }

                      await _setTheme(value);

                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text(l10n.dark),
                    value: ThemeMode.dark,
                    groupValue: currentThemeMode,
                    onChanged: (value) async {
                      if (value == null) {
                        return;
                      }

                      await _setTheme(value);

                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showColorThemeDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return ValueListenableBuilder<String>(
          valueListenable: SonaraApp.colorThemeNotifier,
          builder: (context, currentColorTheme, child) {
            final l10n = AppLocalizations.of(context)!;

            return AlertDialog(
              title: Text(l10n.accentColor),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              content: SizedBox(
                width: 360,
                child: ListView(
                  shrinkWrap: true,
                  children: AppTheme.colorThemes.entries.map((entry) {
                    final colorTheme = entry.key;
                    final color = entry.value;

                    final name = _getColorThemeName(context, colorTheme);

                    final selected = colorTheme == currentColorTheme;

                    return ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(name),
                      trailing: selected
                          ? Icon(
                              Icons.check,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      selected: selected,
                      onTap: () async {
                        await _setColorTheme(colorTheme);

                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                    );
                  }).toList(),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return ValueListenableBuilder<Locale?>(
          valueListenable: SonaraApp.localeNotifier,
          builder: (context, currentLocale, child) {
            final l10n = AppLocalizations.of(context)!;

            return AlertDialog(
              title: Text(l10n.language),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<Locale?>(
                    title: Text(l10n.system),
                    value: null,
                    groupValue: currentLocale,
                    onChanged: (value) async {
                      await _setLocale(value);

                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                  ),
                  RadioListTile<Locale?>(
                    title: const Text('Español'),
                    value: const Locale('es'),
                    groupValue: currentLocale,
                    onChanged: (value) async {
                      await _setLocale(value);

                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                  ),
                  RadioListTile<Locale?>(
                    title: const Text('English'),
                    value: const Locale('en'),
                    groupValue: currentLocale,
                    onChanged: (value) async {
                      await _setLocale(value);

                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showCrossfadeDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final l10n = AppLocalizations.of(context)!;

            int currentSeconds = CrossfadeService.instance.seconds;

            return AlertDialog(
              title: Text(l10n.crossfade),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),

                    Text(
                      currentSeconds == 0
                          ? l10n.disabled
                          : l10n.seconds(currentSeconds),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),

                    const SizedBox(height: 12),

                    Slider(
                      value: currentSeconds.toDouble(),
                      min: 0,
                      max: 12,
                      divisions: 12,
                      label: currentSeconds == 0
                          ? l10n.disabled
                          : l10n.secondsShort(currentSeconds),
                      onChanged: (value) {
                        final seconds = value.round();

                        setDialogState(() {
                          currentSeconds = seconds;
                        });

                        CrossfadeService.instance.secondsNotifier.value =
                            seconds;
                      },
                      onChangeEnd: (value) async {
                        final seconds = value.round();

                        await CrossfadeService.instance.setSeconds(seconds);

                        if (dialogContext.mounted) {
                          setDialogState(() {});
                        }
                      },
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(l10n.close),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAboutDialog() {
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.aboutSonaraTitle),
          content: SingleChildScrollView(
            child: Text(
              'Sonara\n'
              'v1.4.0\n\n'
              '${l10n.aboutSonaraDescription}\n\n'
              '• ${l10n.developer}: Warycoe\n'
              '• ${l10n.helper}: El Sabelotodo\n'
              '• ${l10n.openSourceLicenses}: Licencia del Pdto\n'
              '• ${l10n.privacyPolicy}: Política del Pdto\n'
              '• ${l10n.support}: warycoe.dev@gmail.com\n\n'
              '© 2026 Warycoe. ${l10n.allRightsReserved}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(l10n.close),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: ListView(
        children: [
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              l10n.appearance,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),

          ValueListenableBuilder<ThemeMode>(
            valueListenable: SonaraApp.themeModeNotifier,
            builder: (context, themeMode, child) {
              return ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: Text(l10n.appearanceMode),
                subtitle: Text(_themeName),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showThemeDialog,
              );
            },
          ),

          ValueListenableBuilder<String>(
            valueListenable: SonaraApp.colorThemeNotifier,
            builder: (context, colorTheme, child) {
              return ListTile(
                leading: const Icon(Icons.color_lens_outlined),
                title: Text(l10n.accentColor),
                subtitle: Text(_getColorThemeName(context, colorTheme)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showColorThemeDialog,
              );
            },
          ),

          const Divider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              l10n.playback,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),

          ValueListenableBuilder<int>(
            valueListenable: CrossfadeService.instance.secondsNotifier,
            builder: (context, seconds, child) {
              return ListTile(
                leading: const Icon(Icons.multitrack_audio_outlined),
                title: Text(l10n.crossfade),
                subtitle: Text(
                  seconds == 0 ? l10n.disabled : l10n.seconds(seconds),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showCrossfadeDialog,
              );
            },
          ),

          const Divider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              l10n.application,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),

          ValueListenableBuilder<Locale?>(
            valueListenable: SonaraApp.localeNotifier,
            builder: (context, locale, child) {
              return ListTile(
                leading: const Icon(Icons.language_outlined),
                title: Text(l10n.language),
                subtitle: Text(_languageName),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showLanguageDialog,
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.about),
            subtitle: Text(l10n.aboutSonara),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showAboutDialog,
          ),

          ListTile(
            leading: const Icon(Icons.code_outlined),
            title: Text(l10n.sourceCode),
            subtitle: Text(l10n.viewSonaraSource),
            trailing: const Icon(Icons.open_in_new),
            onTap: _openSourceCode,
          ),

          const SizedBox(height: 32),

          Center(
            child: Text('Sonara', style: Theme.of(context).textTheme.bodySmall),
          ),

          const SizedBox(height: 4),

          Center(
            child: Text(
              l10n.version('1.4.0'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
