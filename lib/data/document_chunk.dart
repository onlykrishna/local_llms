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
  
  /// The FAQ question or header text (used for retrieval scoring)
  String question;
  
  /// The actual answer or body text (used for LLM context)
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

  /// Comma-separated tags or acronyms for exact match boosting
  @Index()
  String? tags;

  @Property()
  bool isHardcoded = false;

  @Property()
  String? category;

  @Index()
  String? source;

  /// MD5 hash of chunk text — used for deduplication at ingestion time
  @Index()
  String? contentHash;

  DocumentChunk({
    this.id = 0,
    required this.sourceDocId,
    required this.domain,
    required this.chunkIndex,
    required this.pageNumber,
    this.question = '',
    required this.text,
    required this.sourceLabel,
    this.source,
    this.embedding,
    required this.createdAt,
    this.tags,
    this.isHardcoded = false,
    this.category,
    this.contentHash,
  });
}
