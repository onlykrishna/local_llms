import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:offline_ai_flutter_demo/domain/models/inference_domain.dart';
import 'package:offline_ai_flutter_demo/domain/services/domain_service.dart';
import 'package:offline_ai_flutter_demo/core/services/settings_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mockito/mockito.dart';

class MockSettingsService extends Mock implements SettingsService {
  @override
  final enableDomainValidation = true.obs;
}

void main() {
  group('DomainService Unit Tests', () {
    late DomainService domainService;
    late MockSettingsService mockSettings;

    setUp(() {
      mockSettings = MockSettingsService();
      Get.put<SettingsService>(mockSettings);
      domainService = DomainService();
    });

    test('Scenario 1: Detect Health Domain Accuracy', () {
      final query = "What are the common symptoms of Type 2 diabetes?";
      final result = domainService.detectQueryDomain(query);
      
      expect(result.detectedDomain, InferenceDomain.health);
      expect(result.confidence, greaterThanOrEqualTo(0.8));
    });

    test('Scenario 2: Detect Bollywood Domain Accuracy', () {
      final query = "Who was the director of the film DDLJ?";
      final result = domainService.detectQueryDomain(query);
      
      expect(result.detectedDomain, InferenceDomain.bollywood);
      expect(result.confidence, greaterThanOrEqualTo(0.8));
    });

    test('Scenario 3: Detect Education Domain Accuracy', () {
      final query = "Explain the laws of physics and basic algebra.";
      final result = domainService.detectQueryDomain(query);
      
      expect(result.detectedDomain, InferenceDomain.education);
      expect(result.confidence, greaterThanOrEqualTo(0.8));
    });

    test('Scenario 4: Fallback to General Domain', () {
      final query = "Tell me a joke about a potato.";
      final result = domainService.detectQueryDomain(query);
      
      expect(result.detectedDomain, InferenceDomain.general);
      expect(result.confidence, equals(0.0));
    });

    test('Scenario 5: Memoization Performance Check', () {
      final query = "Diabetes symptoms list";
      
      final stopwatch = Stopwatch()..start();
      domainService.detectQueryDomain(query);
      final firstPass = stopwatch.elapsedMilliseconds;
      
      stopwatch.reset();
      domainService.detectQueryDomain(query);
      final secondPass = stopwatch.elapsedMilliseconds;
      
      expect(secondPass, lessThanOrEqualTo(firstPass));
    });

    test('Scenario 6: Handle Empty/Null Inputs', () {
      final result = domainService.detectQueryDomain("");
      expect(result.detectedDomain, InferenceDomain.general);
      expect(result.isMatched, isTrue);
    });
    
    test('Scenario 7: Feature Flag enableDomainValidation: false', () {
      mockSettings.enableDomainValidation.value = false;
      final query = "Who acted in DDLJ?"; // Bollywood query
      domainService.changeDomain(InferenceDomain.health); // Health domain selected
      
      final result = domainService.detectQueryDomain(query);
      
      // Should NOT detect mismatch because flag is off
      expect(result.isMatched, isTrue);
      expect(result.confidence, equals(1.0));
    });
  });
}
