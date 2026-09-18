import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeSearchResult {
  final String id;
  final String title;
  final String author;
  final String thumbnailUrl;
  final Duration? duration;

  const YouTubeSearchResult({
    required this.id,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.duration,
  });
}

class YouTubeSearchService {
  final YoutubeExplode _youtube = YoutubeExplode();

  VideoSearchList? _searchList;

  // ===========================================================================
  // BÚSQUEDA INICIAL
  // ===========================================================================

  Future<List<YouTubeSearchResult>> search(String query) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return const [];
    }

    try {
      final VideoSearchList searchList = await _youtube.search.search(
        trimmedQuery,
      );

      _searchList = searchList;

      return _convertResults(searchList);
    } catch (_) {
      _searchList = null;

      return const [];
    }
  }

  // ===========================================================================
  // SIGUIENTE PÁGINA
  // ===========================================================================

  Future<List<YouTubeSearchResult>> loadMore() async {
    final currentSearchList = _searchList;

    if (currentSearchList == null) {
      return const [];
    }

    try {
      final VideoSearchList? nextPage = await currentSearchList.nextPage();

      if (nextPage == null) {
        return const [];
      }

      _searchList = nextPage;

      return _convertResults(nextPage);
    } catch (_) {
      return const [];
    }
  }

  // ===========================================================================
  // CONVERTIR VIDEOS
  // ===========================================================================

  List<YouTubeSearchResult> _convertResults(Iterable<Video> results) {
    return results.map((video) {
      return YouTubeSearchResult(
        id: video.id.value,
        title: video.title,
        author: video.author,
        thumbnailUrl: video.thumbnails.highResUrl,
        duration: video.duration,
      );
    }).toList();
  }

  // ===========================================================================
  // CERRAR
  // ===========================================================================

  void dispose() {
    _youtube.close();
  }
}
