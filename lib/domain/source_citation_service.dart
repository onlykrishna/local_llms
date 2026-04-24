import 'package:get/get.dart';

class Citation {
  final int index;
  final String fileName;
  final String pageNumber;

  Citation({required this.index, required this.fileName, required this.pageNumber});
}

class SourceCitationService extends GetxService {
  List<Citation> parseCitations(String rawResponse) {
    List<Citation> citations = [];
    
    // Regex to match: [1] health_faq.pdf, p.4
    // Or sometimes model might output: [1] health_faq.pdf, page 4
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
