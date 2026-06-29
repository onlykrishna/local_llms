import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_ai_chat_app/app/modules/settings/views/settings_screen.dart';
import 'package:flutter_ai_chat_app/app/core/services/api_provider_service.dart';
import 'package:flutter_ai_chat_app/app/core/services/local_llm_service.dart';
import 'package:flutter_ai_chat_app/app/core/services/analytics_service.dart';
import 'package:flutter_ai_chat_app/app/core/services/storage_service.dart';
import 'package:flutter_ai_chat_app/app/core/services/embedding_service.dart';
import 'package:flutter_ai_chat_app/app/core/models/ai_provider.dart';

class FakeStorageService extends GetxService implements StorageService {
  @override
  bool? getBool(String key) => false;
  
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeApiProviderService extends GetxService implements ApiProviderService {
  @override
  final Rx<AiProvider> activeProvider = AiProvider.openai.obs;
  
  @override
  final RxString openAiKey = ''.obs;
  
  @override
  final RxString groqKey = ''.obs;

  @override
  final RxString geminiKey = ''.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeLocalLlmService extends GetxService implements LocalLlmService {
  @override
  final RxBool isModelReady = false.obs;
  @override
  final RxBool isDownloading = false.obs;
  @override
  final RxDouble downloadProgress = 0.0.obs;
  @override
  final RxString loadError = ''.obs;

  @override
  Future<bool> isModelDownloaded() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeAnalyticsService extends GetxService implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeEmbeddingService extends GetxService implements EmbeddingService {
  @override
  final RxString hfKey = ''.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUp(() {
    Get.reset();
    Get.put<StorageService>(FakeStorageService());
    Get.put<ApiProviderService>(FakeApiProviderService());
    Get.put<LocalLlmService>(FakeLocalLlmService());
    Get.put<AnalyticsService>(FakeAnalyticsService());
    Get.put<EmbeddingService>(FakeEmbeddingService());
  });

  tearDown(() => Get.reset());

  testWidgets('SettingsScreen renders successfully', (WidgetTester tester) async {
    await tester.pumpWidget(
      const GetMaterialApp(
        home: SettingsScreen(),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('AI ENGINE'), findsOneWidget);
  });
}
