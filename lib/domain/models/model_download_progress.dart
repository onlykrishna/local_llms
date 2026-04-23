enum DownloadStatus { idle, downloading, paused, completed, failed, verifying }

class ModelDownloadProgress {
  final String modelId;
  final int bytesReceived;
  final int totalBytes;
  final double percent;
  final DownloadStatus status;
  final String? error;

  const ModelDownloadProgress({
    required this.modelId,
    required this.bytesReceived,
    required this.totalBytes,
    required this.percent,
    required this.status,
    this.error,
  });

  factory ModelDownloadProgress.initial(String id) {
    return ModelDownloadProgress(
      modelId: id,
      bytesReceived: 0,
      totalBytes: 0,
      percent: 0.0,
      status: DownloadStatus.idle,
    );
  }

  ModelDownloadProgress copyWith({
    int? bytesReceived,
    int? totalBytes,
    double? percent,
    DownloadStatus? status,
    String? error,
  }) {
    return ModelDownloadProgress(
      modelId: modelId,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      totalBytes: totalBytes ?? this.totalBytes,
      percent: percent ?? this.percent,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }
}
