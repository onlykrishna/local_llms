import 'package:get/get.dart';
import 'package:hive/hive.dart';
import '../../core/network/ollama_client.dart';
import '../../core/services/fallback_dataset_service.dart';
import '../../core/services/settings_service.dart';
import '../../data/repositories/chat_repository_impl.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_repository.dart';
import '../controllers/chat_controller.dart';
import '../../core/constants/app_constants.dart';

class ChatBinding extends Bindings {
  @override
  void dependencies() {
    // Services
    Get.put(SettingsService().init());
    Get.put(FallbackDatasetService().init());

    // Data Sources & Clients
    final ollamaClient = OllamaClient();
    
    // Repository
    final ChatRepository repository = ChatRepositoryImpl(
      ollamaClient,
      Get.find<FallbackDatasetService>(),
      Hive.box<ChatMessage>(AppConstants.chatBoxName),
    );
    Get.put<ChatRepository>(repository);

    // Controller
    Get.put(ChatController(repository));
  }
}
