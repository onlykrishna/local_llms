import 'package:get/get.dart';
import 'rag_retrieval_service.dart';

class Citation {
  final int index;
  final String fileName;
  final String pageNumber;
  final String? sourceLabel;
  final String? domain;

  Citation({
    required this.index,
    required this.fileName,
    required this.pageNumber,
    this.sourceLabel,
    this.domain,
  });
}

class SourceCitationService extends GetxService {
  /// Builds citations from RetrievedChunk metadata directly.
  List<Citation> buildCitations(List<RetrievedChunk> chunks) {
    return chunks.asMap().entries.map((e) {
      final i = e.key;
      final c = e.value;
      return Citation(
        index: i + 1,
        sourceLabel: c.sourceLabel, // already "filename, p.N"
        fileName: c.sourceLabel.split(',').first.trim(),
        pageNumber: c.pageNumber.toString(),
        domain: c.domain,
      );
    }).toList();
  }

  List<Citation> parseCitations(String rawResponse) {
    List<Citation> citations = [];
    
    // Regex to match: [1] health_faq.pdf, p.4
    final citationRegex = RegExp(r'\[(\d+)\]\s*([^,]+),\s*p(?:age)?\.?\s*(\d+)', caseSensitive: false);
    
    final lines = rawResponse.split('\n');
    for (var line in lines) {
      final matches = citationRegex.allMatches(line);
      for (var match in matches) {
        if (match.groupCount >= 3) {
          int index = int.tryParse(match.group(1) ?? '0') ?? 0;
          String fileName = match.group(2)?.trim() ?? '';
          String pageNumber = match.group(3)?.trim() ?? '';
          
          if (index > 0 && fileName.isNotEmpty && pageNumber.isNotEmpty) {
            // Deduplicate
            if (!citations.any((c) => c.fileName == fileName && c.pageNumber == pageNumber)) {
               citations.add(Citation(index: index, fileName: fileName, pageNumber: pageNumber));
            }
          }
        }
      }
    }
    
    return citations;
  }
}
