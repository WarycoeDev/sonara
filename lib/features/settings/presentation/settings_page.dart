// ignore_for_file: duplicate_ignore, deprecated_member_use

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/crossfade_service.dart';
import '../../../app/locale_service.dart';
import '../../../app/sonara_app.dart';
import '../../../app/theme_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../player/data/services/audio_player_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  static const String _appVersion = '2.5.0';

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
                    // ignore: deprecated_member_use
                    groupValue: currentThemeMode,
                    // ignore: deprecated_member_use
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
                    // ignore: deprecated_member_use
                    groupValue: currentThemeMode,
                    // ignore: deprecated_member_use
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
                    // ignore: deprecated_member_use
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

  void _showReplayGainPreampDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final service = AudioPlayerService.instance;

            double currentPreamp = service.replayGainPreampDb;

            return AlertDialog(
              title: const Text('ReplayGain Preamp'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      '${currentPreamp >= 0 ? '+' : ''}'
                      '${currentPreamp.toStringAsFixed(1)} dB',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Slider(
                      value: currentPreamp,
                      min: -24,
                      max: 24,
                      divisions: 96,
                      label:
                          '${currentPreamp >= 0 ? '+' : ''}'
                          '${currentPreamp.toStringAsFixed(1)} dB',
                      onChanged: (value) {
                        setDialogState(() {
                          currentPreamp = value;
                        });

                        unawaited(
                          service.setReplayGainPreampDb(value, persist: false),
                        );
                      },
                      onChangeEnd: (value) {
                        unawaited(
                          service.setReplayGainPreampDb(value, persist: true),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text('-24 dB'), Text('0 dB'), Text('+24 dB')],
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
                  child: Text(AppLocalizations.of(context)!.close),
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
              //'v&_appVersion\n\n'
              'v'
              '${SettingsPage._appVersion}\n\n'
              '${l10n.aboutSonaraDescription}\n\n'
              '• ${l10n.developer}: Warycoe\n'
              '• ${l10n.helper}: El Sabelotodo\n'
              '• ${l10n.openSourceLicenses}: Licencia del Pdto\n'
              '• ${l10n.privacyPolicy}: Política del Pdto\n'
              '• ${l10n.support}: warycoe.dev@gmail.com\n\n'
              '© 2026 Warycoe. '
              '${l10n.allRightsReserved}',
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
      body: ScrollConfiguration(
        behavior: const _SettingsScrollBehavior(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SettingsSection(
              title: l10n.appearance,
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: SonaraApp.themeModeNotifier,
                  builder: (context, themeMode, child) {
                    return _SettingsTile(
                      icon: Icons.brightness_6_outlined,
                      title: l10n.appearanceMode,
                      subtitle: _themeName,
                      onTap: _showThemeDialog,
                    );
                  },
                ),
                ValueListenableBuilder<String>(
                  valueListenable: SonaraApp.colorThemeNotifier,
                  builder: (context, colorTheme, child) {
                    return _SettingsTile(
                      icon: Icons.color_lens_outlined,
                      title: l10n.accentColor,
                      subtitle: _getColorThemeName(context, colorTheme),
                      onTap: _showColorThemeDialog,
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            _SettingsSection(
              title: l10n.playback,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: CrossfadeService.instance.secondsNotifier,
                  builder: (context, seconds, child) {
                    return _SettingsTile(
                      icon: Icons.multitrack_audio_outlined,
                      title: l10n.crossfade,
                      subtitle: seconds == 0
                          ? l10n.disabled
                          : l10n.seconds(seconds),
                      onTap: _showCrossfadeDialog,
                    );
                  },
                ),
                ValueListenableBuilder<double>(
                  valueListenable:
                      AudioPlayerService.instance.replayGainPreampNotifier,
                  builder: (context, preamp, child) {
                    final text =
                        '${preamp >= 0 ? '+' : ''}'
                        '${preamp.toStringAsFixed(1)} dB';

                    return _SettingsTile(
                      icon: Icons.equalizer_outlined,
                      title: 'ReplayGain Preamp',
                      subtitle: text,
                      onTap: _showReplayGainPreampDialog,
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            _SettingsSection(
              title: l10n.application,
              children: [
                ValueListenableBuilder<Locale?>(
                  valueListenable: SonaraApp.localeNotifier,
                  builder: (context, locale, child) {
                    return _SettingsTile(
                      icon: Icons.language_outlined,
                      title: l10n.language,
                      subtitle: _languageName,
                      onTap: _showLanguageDialog,
                    );
                  },
                ),
                _SettingsTile(
                  icon: Icons.info_outline,
                  title: l10n.about,
                  subtitle: l10n.aboutSonara,
                  trailing: Icons.chevron_right_rounded,
                  onTap: _showAboutDialog,
                ),
                _SettingsTile(
                  icon: Icons.code_outlined,
                  title: l10n.sourceCode,
                  subtitle: l10n.viewSonaraSource,
                  trailing: Icons.open_in_new_rounded,
                  onTap: _openSourceCode,
                ),
              ],
            ),

            const SizedBox(height: 32),

            Center(
              child: Text(
                'Sonara',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            const SizedBox(height: 4),

            Center(
              child: Text(
                l10n.version(SettingsPage._appVersion),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          ..._withSpacing(children),
        ],
      ),
    );
  }

  List<Widget> _withSpacing(List<Widget> children) {
    final result = <Widget>[];

    for (var i = 0; i < children.length; i++) {
      result.add(children[i]);

      if (i < children.length - 1) {
        result.add(const SizedBox(height: 8));
      }
    }

    return result;
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final IconData? trailing;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing = Icons.chevron_right_rounded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 21,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(trailing, size: 21, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsScrollBehavior extends MaterialScrollBehavior {
  const _SettingsScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
