class SongStatistics {
  final String songId;
  final int playCount;
  final DateTime? lastPlayed;
  final Duration totalListenTime;

  const SongStatistics({
    required this.songId,
    this.playCount = 0,
    this.lastPlayed,
    this.totalListenTime = Duration.zero,
  });

  SongStatistics copyWith({
    String? songId,
    int? playCount,
    DateTime? lastPlayed,
    Duration? totalListenTime,
  }) {
    return SongStatistics(
      songId: songId ?? this.songId,
      playCount: playCount ?? this.playCount,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      totalListenTime: totalListenTime ?? this.totalListenTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'songId': songId,
      'playCount': playCount,
      'lastPlayed': lastPlayed?.toIso8601String(),
      'totalListenTimeSeconds': totalListenTime.inSeconds,
    };
  }

  factory SongStatistics.fromJson(Map<String, dynamic> json) {
    return SongStatistics(
      songId: json['songId'] as String,
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      lastPlayed: json['lastPlayed'] != null
          ? DateTime.tryParse(json['lastPlayed'] as String)
          : null,
      totalListenTime: Duration(
        seconds: (json['totalListenTimeSeconds'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
