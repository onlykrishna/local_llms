import 'package:objectbox/objectbox.dart';

@Entity()
class DocumentChunk {
  @Id()
  int id = 0;
  
  @Index()
  int sourceDocId;
  
  @Index()
  String domain;
  
  int chunkIndex;
  int pageNumber;
  String text;
  String sourceLabel;
  
  @HnswIndex(
    dimensions: 384,
    distanceType: VectorDistanceType.cosine,
    neighborsPerNode: 32,
    indexingSearchCount: 200,
  )
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;
  
  @Property(type: PropertyType.date)
  DateTime createdAt;

  DocumentChunk({
    this.id = 0,
    required this.sourceDocId,
    required this.domain,
    required this.chunkIndex,
    required this.pageNumber,
    required this.text,
    required this.sourceLabel,
    this.embedding,
    required this.createdAt,
  });
}
