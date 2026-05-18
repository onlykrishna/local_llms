import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/models/ai_provider.dart';
import '../../controllers/chat_controller.dart';
import '../../../../core/services/api_provider_service.dart';

class ProviderToggle extends StatelessWidget {
  const ProviderToggle({super.key});

  void _showProviderSheet(BuildContext context, ChatController controller) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Select AI Provider',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Obx(() => ListTile(
              leading: Radio<AiProvider>(
                value: AiProvider.openai,
                groupValue: controller.activeProvider.value,
                onChanged: (_) {},
              ),
              title: const Text('OpenAI (gpt-4o-mini)'),
              onTap: () {
                Get.find<ApiProviderService>().switchProvider(AiProvider.openai);
                Get.back();
              },
            )),
            Obx(() => ListTile(
              leading: Radio<AiProvider>(
                value: AiProvider.groq,
                groupValue: controller.activeProvider.value,
                onChanged: (_) {},
              ),
              title: const Text('Groq (llama3-70b-8192)'),
              onTap: () {
                Get.find<ApiProviderService>().switchProvider(AiProvider.groq);
                Get.back();
              },
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ChatController>();

    return Obx(() => TextButton.icon(
      icon: const Icon(Icons.swap_horiz, color: Colors.white),
      label: Text(
        controller.activeProviderName,
        style: const TextStyle(color: Colors.white),
      ),
      onPressed: () => _showProviderSheet(context, controller),
    ));
  }
}
