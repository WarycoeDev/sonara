import 'dart:typed_data';

enum SongSource { local, downloaded }

class Song {
  final String id;
  final String filePath;
  final String title;
  final String? artist;
  final String? album;
  final Duration duration;
  final String? coverPath;
  final Uint8List? coverBytes;
  final DateTime dateAdded;
  final SongSource source;
  final bool isFavorite;
  final double? volumeGain;
  final int? fileLastModified;
  final int? fileSize;

  const Song({
    required this.id,
    required this.filePath,
    required this.title,
    this.artist,
    this.album,
    required this.duration,
    this.coverPath,
    this.coverBytes,
    required this.dateAdded,
    required this.source,
    this.isFavorite = false,
    this.volumeGain,
    this.fileLastModified,
    this.fileSize,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'filePath': filePath,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration.inMilliseconds,
      'coverPath': coverPath,
      'dateAdded': dateAdded.millisecondsSinceEpoch,
      'source': source.name,
      'isFavorite': isFavorite,
      'volumeGain': volumeGain,
      'fileLastModified': fileLastModified,
      'fileSize': fileSize,
    };
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source']?.toString();

    final source = SongSource.values.firstWhere(
      (value) => value.name == sourceName,
      orElse: () => SongSource.local,
    );

    final durationValue = json['duration'];
    final dateAddedValue = json['dateAdded'];
    final fileLastModifiedValue = json['fileLastModified'];
    final fileSizeValue = json['fileSize'];
    final volumeGainValue = json['volumeGain'];

    return Song(
      id: json['id']?.toString() ?? '',
      filePath: json['filePath']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Sin título',
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      duration: Duration(
        milliseconds: durationValue is num ? durationValue.toInt() : 0,
      ),
      coverPath: json['coverPath'] as String?,
      dateAdded: dateAddedValue is num
          ? DateTime.fromMillisecondsSinceEpoch(dateAddedValue.toInt())
          : DateTime.now(),
      source: source,
      isFavorite: json['isFavorite'] == true,
      volumeGain: volumeGainValue is num ? volumeGainValue.toDouble() : null,
      fileLastModified: fileLastModifiedValue is num
          ? fileLastModifiedValue.toInt()
          : null,
      fileSize: fileSizeValue is num ? fileSizeValue.toInt() : null,
    );
  }

  Song copyWith({
    String? id,
    String? filePath,
    String? title,
    String? artist,
    String? album,
    Duration? duration,

    // Permite distinguir:
    //
    // coverPath omitido  -> conservar
    // coverPath: null    -> borrar
    // coverPath: "..."   -> reemplazar
    //
    Object? coverPath = _unset,

    Object? coverBytes = _unset,

    DateTime? dateAdded,
    SongSource? source,
    bool? isFavorite,

    Object? volumeGain = _unset,
    Object? fileLastModified = _unset,
    Object? fileSize = _unset,
  }) {
    return Song(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,

      coverPath: identical(coverPath, _unset)
          ? this.coverPath
          : coverPath as String?,

      coverBytes: identical(coverBytes, _unset)
          ? this.coverBytes
          : coverBytes as Uint8List?,

      dateAdded: dateAdded ?? this.dateAdded,
      source: source ?? this.source,
      isFavorite: isFavorite ?? this.isFavorite,

      volumeGain: identical(volumeGain, _unset)
          ? this.volumeGain
          : volumeGain as double?,

      fileLastModified: identical(fileLastModified, _unset)
          ? this.fileLastModified
          : fileLastModified as int?,

      fileSize: identical(fileSize, _unset) ? this.fileSize : fileSize as int?,
    );
  }

  static const Object _unset = Object();
}
