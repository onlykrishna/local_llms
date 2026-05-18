class PdfChunk {
  final String id;           // sha256 hash of (docId + chunkIndex)
  final String docId;        // parent PdfDocument.id
  final String fileName;     // for citation display
  final int pageNumber;      // 1-based page number
  final int chunkIndex;      // position within document
  final String text;         // raw text content
  final List<double> embedding; // 1536-dim float vector

  PdfChunk({
    required this.id,
    required this.docId,
    required this.fileName,
    required this.pageNumber,
    required this.chunkIndex,
    required this.text,
    required this.embedding,
  });

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'docId': docId,
    'fileName': fileName,
    'pageNumber': pageNumber,
    'chunkIndex': chunkIndex,
    'text': text,
    'embedding': embedding,
  };

  factory PdfChunk.fromFirestore(Map<String, dynamic> map) => PdfChunk(
    id: map['id'] as String,
    docId: map['docId'] as String,
    fileName: map['fileName'] as String,
    pageNumber: map['pageNumber'] as int,
    chunkIndex: map['chunkIndex'] as int,
    text: map['text'] as String,
    embedding: List<double>.from(
      (map['embedding'] as List<dynamic>).map((e) => (e as num).toDouble()),
    ),
  );
}

// Used in chat responses to show source attribution
class ChunkCitation {
  final String fileName;
  final int pageNumber;
  final double score; // cosine similarity score

  ChunkCitation({
    required this.fileName,
    required this.pageNumber,
    required this.score,
  });
}
