import 'package:objectbox/objectbox.dart';

@Entity()
class SourceDocument {
  @Id()
  int id = 0;
  
  String fileName;
  String filePath;
  String domain;
  int pageCount;
  int chunkCount;
  
  @Property(type: PropertyType.date)
  DateTime uploadedAt;
  
  String status;
  String? errorMessage;

  SourceDocument({
    this.id = 0,
    required this.fileName,
    required this.filePath,
    required this.domain,
    required this.pageCount,
    required this.chunkCount,
    required this.uploadedAt,
    required this.status,
    this.errorMessage,
  });
}
