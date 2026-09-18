class Playlist {
  final String id;

  final String name;

  final List<String> songIds;

  final DateTime dateCreated;

  const Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    required this.dateCreated,
  });

  int get songCount {
    return songIds.length;
  }

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? songIds,
    DateTime? dateCreated,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      songIds: songIds ?? this.songIds,
      dateCreated: dateCreated ?? this.dateCreated,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'songIds': songIds,
      'dateCreated': dateCreated.toIso8601String(),
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final rawSongIds = json['songIds'];

    return Playlist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      songIds: rawSongIds is List
          ? List<String>.unmodifiable(rawSongIds.whereType<String>())
          : const <String>[],
      dateCreated:
          DateTime.tryParse(json['dateCreated'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
