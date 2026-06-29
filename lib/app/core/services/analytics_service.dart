import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:get/get.dart';

class AnalyticsService extends GetxService {
  final _analytics = FirebaseAnalytics.instance;

  Future<void> logMessageSent(String provider) async {
    await _analytics.logEvent(
      name: 'message_sent',
      parameters: {'provider': provider},
    );
  }

  Future<void> logPdfUploaded(int pageCount) async {
    await _analytics.logEvent(
      name: 'pdf_uploaded',
      parameters: {'page_count': pageCount},
    );
  }

  Future<void> logPdfQueried() async {
    await _analytics.logEvent(name: 'pdf_queried');
  }

  Future<void> logProviderSwitched(String to) async {
    await _analytics.logEvent(
      name: 'provider_switched',
      parameters: {'to': to},
    );
  }

  /// [type] — 'camera' | 'photos' | 'files'
  Future<void> logAttachmentUsed(String type) async {
    await _analytics.logEvent(
      name: 'attachment_used',
      parameters: {'type': type},
    );
  }

  /// [mode] — 'stt' (short-tap mic) | 'live' (long-press / live voice screen)
  Future<void> logVoiceInputUsed(String mode) async {
    await _analytics.logEvent(
      name: 'voice_input_used',
      parameters: {'mode': mode},
    );
  }

  Future<void> logOfflineModelDownloaded() async {
    await _analytics.logEvent(name: 'offline_model_downloaded');
  }
}
