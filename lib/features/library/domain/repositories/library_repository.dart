import '../models/album.dart';
import '../models/artist.dart';
import '../models/song.dart';

abstract class LibraryRepository {
  Future<List<Song>> getSongs();

  Future<List<Album>> getAlbums();

  Future<List<Artist>> getArtists();

  Future<List<Song>> searchSongs(String query);

  Future<void> scanLibrary();
}
