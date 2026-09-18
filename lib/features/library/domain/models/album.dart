import 'song.dart';

class Album {
  final String name;
  final String? artist;
  final List<Song> songs;

  const Album({required this.name, this.artist, required this.songs});

  int get songCount => songs.length;
}
