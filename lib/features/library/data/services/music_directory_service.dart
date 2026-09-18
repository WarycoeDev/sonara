import 'dart:io';

class MusicDirectoryService {
  Future<List<String>> getMusicDirectories() async {
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];

      if (home == null || home.isEmpty) {
        return const <String>[];
      }

      return <String>['$home/Music' /*'$home/Downloads', '$home/Desktop'*/];
    }

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];

      if (userProfile == null || userProfile.isEmpty) {
        return const <String>[];
      }

      return <String>['$userProfile\\Music'];
    }

    return const <String>[];
  }
}
