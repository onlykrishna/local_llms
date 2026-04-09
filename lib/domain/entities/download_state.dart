import 'package:hive/hive.dart';

class DownloadState extends HiveObject {
  final String modelId;
  final int bytesReceived;
  final int totalBytes;

  DownloadState({
    required this.modelId,
    required this.bytesReceived,
    required this.totalBytes,
  });
}

class DownloadStateAdapter extends TypeAdapter<DownloadState> {
  @override
  final int typeId = 2;

  @override
  DownloadState read(BinaryReader reader) {
    return DownloadState(
      modelId: reader.read() as String,
      bytesReceived: reader.read() as int,
      totalBytes: reader.read() as int,
    );
  }

  @override
  void write(BinaryWriter writer, DownloadState obj) {
    writer.write(obj.modelId);
    writer.write(obj.bytesReceived);
    writer.write(obj.totalBytes);
  }
}
