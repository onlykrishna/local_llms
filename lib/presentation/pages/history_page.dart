import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/chat_controller.dart';
import '../../domain/entities/chat_message.dart';

class HistoryPage extends GetView<ChatController> {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _confirmClear(context),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.messages.isEmpty) {
          return const Center(child: Text('No history found.'));
        }
        
        return ListView.builder(
          itemCount: controller.messages.length,
          itemBuilder: (context, index) {
            final message = controller.messages[index];
            return ListTile(
              leading: Icon(
                message.isUser ? Icons.person : Icons.auto_awesome,
                color: message.isUser ? Colors.blue : Colors.teal,
              ),
              title: Text(
                message.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                DateFormat('MMM dd, hh:mm a').format(message.timestamp),
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () {
                // Return to chat and maybe scroll to this message? 
                // For now, just a snackbar
                Get.snackbar('Message Detail', message.content);
              },
            );
          },
        );
      }),
    );
  }

  void _confirmClear(BuildContext context) {
    Get.defaultDialog(
      title: 'Clear Everything?',
      middleText: 'This will delete all messages locally.',
      textConfirm: 'Delete',
      textCancel: 'Cancel',
      confirmTextColor: Colors.white,
      buttonColor: Colors.red,
      onConfirm: () {
        controller.clearChat();
        Get.back();
      },
    );
  }
}
