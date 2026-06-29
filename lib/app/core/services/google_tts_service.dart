import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class GoogleTtsService extends GetxService {
  final RxBool isSpeaking = false.obs;
  AudioPlayer? _player;
  static const String _endpoint =
      'https://texttospeech.googleapis.com/v1/text:synthesize';

  // Neural2 voice — highest quality, free tier included
  // en-US-Neural2-F is a clear, natural female voice
  // en-US-Neural2-D is a clear, natural male voice
  static const String _voiceName = 'en-US-Neural2-F';
  static const String _languageCode = 'en-US';

  String? get _apiKey {
    final key = dotenv.env['GOOGLE_TTS_API_KEY']?.trim();
    return (key != null && key.isNotEmpty) ? key : null;
  }

  bool get isAvailable => _apiKey != null;

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    final key = _apiKey;
    if (key == null) {
      debugPrint('⚠️ GoogleTtsService: no API key, falling back to on-device TTS');
      return; // caller handles fallback
    }

    isSpeaking.value = true;
    try {
      // Build SSML-wrapped request for better naturalness
      final ssml = '<speak>${_escapeXml(text)}</speak>';

      final response = await http.post(
        Uri.parse('$_endpoint?key=$key'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'input': {'ssml': ssml},
          'voice': {
            'languageCode': _languageCode,
            'name': _voiceName,
          },
          'audioConfig': {
            'audioEncoding': 'MP3',
            'speakingRate': 1.0,   // natural pace
            'pitch': 0.0,          // neutral pitch
            'volumeGainDb': 0.0,
            'effectsProfileId': ['handset-class-device'], // optimized for phone speaker
          },
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('❌ GoogleTtsService error: ${response.statusCode} ${response.body}');
        isSpeaking.value = false;
        return;
      }

      final data = jsonDecode(response.body);
      final audioBase64 = data['audioContent'] as String;
      final audioBytes = base64Decode(audioBase64);

      // Write to temp file and play
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await tempFile.writeAsBytes(audioBytes);

      _player ??= AudioPlayer();
      await _player!.setFilePath(tempFile.path);

      final completer = Completer<void>();
      _player!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (!completer.isCompleted) completer.complete();
        }
      });

      await _player!.play();
      await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {},
      );

      // Clean up temp file
      try { await tempFile.delete(); } catch (_) {}

    } catch (e) {
      debugPrint('❌ GoogleTtsService exception: $e');
    } finally {
      isSpeaking.value = false;
    }
  }

  Future<void> stop() async {
    try { await _player?.stop(); } catch (_) {}
    isSpeaking.value = false;
  }

  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  @override
  void onClose() {
    _player?.dispose();
    super.onClose();
  }
}
