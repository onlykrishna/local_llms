import 'package:get/get.dart';
import 'package:hive/hive.dart';
import '../../core/constants/app_constants.dart';
import '../models/inference_domain.dart';

/// Manages selected inference domain. Persisted in Hive 'settings' box.
class DomainService extends GetxService {
  static const String _domainKey = 'selected_domain';

  late Box _settingsBox;

  final Rx<InferenceDomain> selectedDomain = InferenceDomain.general.obs;

  Future<DomainService> init() async {
    _settingsBox = await Hive.openBox(AppConstants.settingsBoxName);
    final saved = _settingsBox.get(_domainKey, defaultValue: 'general') as String;
    selectedDomain.value = _domainFromString(saved);
    return this;
  }

  void setDomain(InferenceDomain domain) {
    selectedDomain.value = domain;
    _settingsBox.put(_domainKey, domain.name);
  }

  String getSystemPrompt() => selectedDomain.value.systemPrompt;

  InferenceDomain _domainFromString(String name) {
    return InferenceDomain.values.firstWhere(
      (d) => d.name == name,
      orElse: () => InferenceDomain.general,
    );
  }
}
