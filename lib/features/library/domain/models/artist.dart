import 'song.dart';

class Artist {
  final String name;
  final List<Song> songs;

  const Artist({required this.name, required this.songs});

  int get songCount => songs.length;
}
