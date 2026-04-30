import 'package:hive/hive.dart';

@HiveType(typeId: 3)
class PdfDocumentMeta extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String fileName;

  @HiveField(2)
  final String internalPath;

  @HiveField(3)
  final String? originalPath;

  @HiveField(4)
  final DateTime embeddedAt;

  @HiveField(5)
  final int pageCount;

  @HiveField(6)
  final int chunkCount;

  @HiveField(7)
  final String status; // 'indexed' | 'processing' | 'failed'

  @HiveField(8)
  final String source; // 'user_uploaded' | 'bundled'

  PdfDocumentMeta({
    required this.id,
    required this.fileName,
    required this.internalPath,
    this.originalPath,
    required this.embeddedAt,
    required this.pageCount,
    required this.chunkCount,
    required this.status,
    required this.source,
  });

  PdfDocumentMeta copyWith({
    String? status,
    int? pageCount,
    int? chunkCount,
  }) {
    return PdfDocumentMeta(
      id: id,
      fileName: fileName,
      internalPath: internalPath,
      originalPath: originalPath,
      embeddedAt: embeddedAt,
      pageCount: pageCount ?? this.pageCount,
      chunkCount: chunkCount ?? this.chunkCount,
      status: status ?? this.status,
      source: source,
    );
  }
}

class PdfDocumentMetaAdapter extends TypeAdapter<PdfDocumentMeta> {
  @override
  final int typeId = 3;

  @override
  PdfDocumentMeta read(BinaryReader reader) {
    return PdfDocumentMeta(
      id: reader.read() as String,
      fileName: reader.read() as String,
      internalPath: reader.read() as String,
      originalPath: reader.read() as String?,
      embeddedAt: DateTime.fromMillisecondsSinceEpoch(reader.read() as int),
      pageCount: reader.read() as int,
      chunkCount: reader.read() as int,
      status: reader.read() as String,
      source: reader.read() as String,
    );
  }

  @override
  void write(BinaryWriter writer, PdfDocumentMeta obj) {
    writer.write(obj.id);
    writer.write(obj.fileName);
    writer.write(obj.internalPath);
    writer.write(obj.originalPath);
    writer.write(obj.embeddedAt.millisecondsSinceEpoch);
    writer.write(obj.pageCount);
    writer.write(obj.chunkCount);
    writer.write(obj.status);
    writer.write(obj.source);
  }
}
