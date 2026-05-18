enum ProcessingStatus { uploading, processing, ready, error }

class PdfDocument {
  final String id;          // Firestore doc ID (uuid v4)
  final String fileName;    // original file name
  final String storagePath; // Firebase Storage path
  final String downloadUrl; // public download URL
  final int pageCount;
  final int chunkCount;
  final DateTime uploadedAt;
  final ProcessingStatus status;

  PdfDocument({
    required this.id,
    required this.fileName,
    required this.storagePath,
    required this.downloadUrl,
    required this.pageCount,
    required this.chunkCount,
    required this.uploadedAt,
    required this.status,
  });

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'fileName': fileName,
    'storagePath': storagePath,
    'downloadUrl': downloadUrl,
    'pageCount': pageCount,
    'chunkCount': chunkCount,
    'uploadedAt': uploadedAt.toIso8601String(),
    'status': status.name,
  };

  factory PdfDocument.fromFirestore(Map<String, dynamic> map) =>
    PdfDocument(
      id: map['id'] as String,
      fileName: map['fileName'] as String,
      storagePath: map['storagePath'] as String,
      downloadUrl: map['downloadUrl'] as String,
      pageCount: map['pageCount'] as int,
      chunkCount: map['chunkCount'] as int,
      uploadedAt: DateTime.parse(map['uploadedAt'] as String),
      status: ProcessingStatus.values
          .firstWhere((s) => s.name == map['status']),
    );
}
