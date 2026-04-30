// CRITICAL: After any change to this entity, you MUST run:
// dart run build_runner build --delete-conflicting-outputs
import 'package:objectbox/objectbox.dart';

@Entity()
class DocumentChunk {
  @Id()
  int id = 0;
  
  @Index()
  int sourceDocId = 0;
  
  @Index()
  String domain = '';
  
  int chunkIndex = 0;
  int pageNumber = 0;
  
  /// The FAQ question or header text (used for retrieval scoring)
  String question = '';
  
  /// The actual answer or body text (used for LLM context)
  String text = '';
  
  String sourceLabel = '';
  
  @HnswIndex(
    dimensions: 384,
    distanceType: VectorDistanceType.cosine,
    neighborsPerNode: 32,
    indexingSearchCount: 200,
  )
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;
  
  @Property(type: PropertyType.date)
  DateTime? createdAt;

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
  String contentHash = '';

  @Index()
  String sourceDocumentTag = ''; // Default value for smooth migration

  DocumentChunk({
    this.id = 0,
    this.sourceDocId = 0,
    this.domain = '',
    this.chunkIndex = 0,
    this.pageNumber = 0,
    this.question = '',
    this.text = '',
    this.sourceLabel = '',
    this.source,
    this.embedding,
    this.createdAt,
    this.tags,
    this.isHardcoded = false,
    this.category,
    this.contentHash = '',
    this.sourceDocumentTag = '',
  });
}
