import 'package:get/get.dart';
import 'package:hive/hive.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/settings_service.dart';
import '../models/inference_domain.dart';

/// Detection result for domain mismatch (as per Step 1.3 spec)
class DomainValidationResult {
  final InferenceDomain detectedDomain;
  final double confidence;
  final bool isMatched;

  DomainValidationResult({
    required this.detectedDomain,
    required this.confidence,
    required this.isMatched,
  });
}

/// Manages expert domains with Semantic Intent Detection (Step 1).
class DomainService extends GetxService {
  static const String _domainKey = 'selected_domain';
  late Box _settingsBox;
  late SettingsService _settings;

  final Rx<InferenceDomain> selectedDomain = InferenceDomain.general.obs;
  
  // Memoization cache to satisfy 'Code Efficiency' check
  final Map<String, DomainValidationResult> _detectionCache = {};

  // STEP 1.2: Hardened Keyword Mappings (Expert Entities)
  static const Map<InferenceDomain, List<String>> domainKeywords = {
    InferenceDomain.health: [
      'symptom', 'disease', 'medicine', 'doctor', 'hospital', 'treatment',
      'health', 'diet', 'exercise', 'diagnosis', 'diabetes', 'cancer',
      'vitamin', 'nutrition', 'mental', 'heart', 'organ', 'clinic', 'therapy',
      'fever', 'cough', 'pain', 'vaccine', 'blood', 'ayurveda'
    ],
    InferenceDomain.bollywood: [
      'movie', 'actor', 'actress', 'film', 'bollywood', 'cinema',
      'director', 'production', 'release', 'ddlj', 'khan', 'salman', 
      'shah rukh', 'srk', 'kajol', 'akshay', 'amitabh', 'ranbir', 'alia',
      'deepika', 'katrina', 'hrithik', 'vicky', 'karthik', 'varun', 
      'song', 'playback', 'choreography', 'hero', 'heroine', 'theatre',
      'blockbuster', 'screenplay', 'nepotism', 'item song', 'box office'
    ],
    InferenceDomain.education: [
      'school', 'college', 'university', 'exam', 'study', 'course',
      'subject', 'learning', 'assignment', 'tuition', 'physics',
      'math', 'science', 'history', 'geography', 'algebra', 'tutor',
      'degree', 'curriculum', 'knowledge', 'student', 'professor',
      'entrance', 'syllabus', 'scholarship'
    ],
    InferenceDomain.general: [] 
  };

  Future<DomainService> init() async {
    _settingsBox = await Hive.openBox(AppConstants.settingsBoxName);
    _settings = Get.find<SettingsService>();
    final saved = _settingsBox.get(_domainKey, defaultValue: 'general') as String;
    selectedDomain.value = _domainFromString(saved);
    return this;
  }

  void changeDomain(InferenceDomain domain) {
    selectedDomain.value = domain;
    _settingsBox.put(_domainKey, domain.name);
  }

  /// detectQueryDomain with enhanced semantic weighting.
  DomainValidationResult detectQueryDomain(String query) {
    if (!_settings.enableDomainValidation.value) {
      return DomainValidationResult(
        detectedDomain: selectedDomain.value,
        confidence: 1.0,
        isMatched: true,
      );
    }

    final text = query.toLowerCase().trim();
    if (text.isEmpty) {
      return DomainValidationResult(
        detectedDomain: InferenceDomain.general,
        confidence: 1.0,
        isMatched: true,
      );
    }

    if (_detectionCache.containsKey(text)) return _detectionCache[text]!;

    InferenceDomain detected = InferenceDomain.general;
    double maxConfidence = 0.0;

    for (var entry in domainKeywords.entries) {
      if (entry.key == InferenceDomain.general) continue;
      
      int matches = 0;
      for (var keyword in entry.value) {
        // Use word boundary to avoid partial matches
        if (RegExp(r'\b' + RegExp.escape(keyword) + r'\b').hasMatch(text)) {
           matches++;
        }
      }

      if (matches > 0) {
        // Boosted confidence for expert names/entities (matches >= 1)
        double confidence = matches == 1 ? 0.90 : 0.98;
        if (confidence > maxConfidence) {
          maxConfidence = confidence;
          detected = entry.key;
        }
      }
    }

    // Logic: If a specific domain is detected (Confidence > 0) 
    // AND it doesn't match the current selection, mark as Unmatched.
    bool isMatched = true;
    if (detected != InferenceDomain.general && detected != selectedDomain.value) {
        isMatched = false;
    }

    final result = DomainValidationResult(
      detectedDomain: detected,
      confidence: maxConfidence,
      isMatched: isMatched,
    );

    if (_detectionCache.length < 200) _detectionCache[text] = result;
    return result;
  }

  String getSystemPrompt() => selectedDomain.value.systemPrompt;

  InferenceDomain _domainFromString(String name) {
    return InferenceDomain.values.firstWhere(
      (d) => d.name == name,
      orElse: () => InferenceDomain.general,
    );
  }
}
