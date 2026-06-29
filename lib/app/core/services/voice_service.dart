import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'google_tts_service.dart';

/// Provides on-device Speech-to-Text and Text-to-Speech.
///
/// STT/TTS routing:
///   • All providers → on-device STT (speech_to_text) + on-device TTS (flutter_tts).
///
/// TODO (cloud STT/TTS for API modes):
///   When API providers are active (OpenAI / Groq), the preferred path would be:
///     - STT: OpenAI Whisper (`POST /audio/transcriptions`)
///     - TTS: OpenAI TTS (`POST /audio/speech`)
///   This is not implemented in this pass to keep scope manageable. On-device
///   STT/TTS is used for all providers as an acceptable first pass.
///   Flag: See "Explicitly Out of Scope" in the implementation prompt for context.
class VoiceService extends GetxService {
  // ── Reactive state ──────────────────────────────────────
  final RxBool isListening = false.obs;
  final RxBool isSpeaking = false.obs;
  final RxBool isInitialized = false.obs;
  final RxString liveTranscript = ''.obs;
  final RxString voiceError = ''.obs;

  // ── Internal components ──────────────────────────────────
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isReleasingRecognizer = false;

  @override
  void onInit() {
    super.onInit();
    _initTts();
  }

  Future<void> _initTts() async {
    // Set language to English
    await _tts.setLanguage('en-US');

    // Speech rate: 0.5 is natural conversational pace
    await _tts.setSpeechRate(0.5);

    // Pitch: 1.0 is neutral
    await _tts.setPitch(1.0);

    // Volume: maximum
    await _tts.setVolume(1.0);

    // Select the highest quality available voice
    await _selectBestVoice();

    _tts.setStartHandler(() => isSpeaking.value = true);

    _tts.setCompletionHandler(() {
      isSpeaking.value = false;
    });

    _tts.setErrorHandler((message) {
      debugPrint('❌ TTS error: $message');
      isSpeaking.value = false;
    });
  }

  Future<void> _selectBestVoice() async {
    try {
      final voices = await _tts.getVoices as List<dynamic>?;
      if (voices == null || voices.isEmpty) return;

      // Priority order for voice selection:
      // 1. en-US neural/wavenet voices (highest quality)
      // 2. en-US premium voices
      // 3. en-US default voices
      // 4. Any English voice
      
      final voiceList = voices
          .map((v) => Map<String, String>.from(v as Map))
          .toList();

      // Try to find a neural/premium quality voice
      Map<String, String>? bestVoice;

      // First preference: neural voices (Google's highest quality)
      bestVoice = voiceList.firstWhereOrNull(
        (v) =>
            (v['locale']?.startsWith('en') ?? false) &&
            ((v['name']?.toLowerCase().contains('neural') ?? false) ||
             (v['name']?.toLowerCase().contains('wavenet') ?? false)),
      );

      // Second preference: any en-US voice with "premium" in name
      bestVoice ??= voiceList.firstWhereOrNull(
        (v) =>
            (v['locale']?.startsWith('en-US') ?? false) &&
            (v['name']?.toLowerCase().contains('premium') ?? false),
      );

      // Third preference: en-US female voice (generally clearer on Android)
      bestVoice ??= voiceList.firstWhereOrNull(
        (v) =>
            (v['locale']?.startsWith('en-US') ?? false) &&
            ((v['name']?.toLowerCase().contains('female') ?? false) ||
             (v['name']?.toLowerCase().contains('woman') ?? false)),
      );

      // Fourth preference: any en-US voice
      bestVoice ??= voiceList.firstWhereOrNull(
        (v) => v['locale']?.startsWith('en-US') ?? false,
      );

      // Fifth preference: any English voice
      bestVoice ??= voiceList.firstWhereOrNull(
        (v) => v['locale']?.startsWith('en') ?? false,
      );

      if (bestVoice != null) {
        await _tts.setVoice(bestVoice);
        debugPrint('🔊 TTS voice selected: ${bestVoice['name']} (${bestVoice['locale']})');
      } else {
        debugPrint('🔊 TTS: no preferred voice found, using system default');
      }
    } catch (e) {
      debugPrint('🔊 TTS voice selection error: $e — using system default');
      // Non-fatal: app continues with default voice
    }
  }

  // ── Permission ───────────────────────────────────────────

  /// Requests microphone permission (and speech recognition on iOS).
  /// Returns true if granted.
  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  // ── STT ──────────────────────────────────────────────────

  /// Initializes the speech recognizer and requests mic permission.
  /// Returns true if the device is ready for speech recognition.
  Future<bool> initSpeech() async {
    if (isInitialized.value) return true;
    voiceError.value = '';

    final hasPermission = await requestMicPermission();
    if (!hasPermission) {
      voiceError.value = 'Microphone permission denied. '
          'Please enable it in device Settings.';
      return false;
    }

    try {
      final available = await _stt.initialize(
        onError: (error) {
          isListening.value = false;
          voiceError.value = 'STT error: ${error.errorMsg}';
          debugPrint('❌ VoiceService STT error: ${error.errorMsg}');
        },
        onStatus: (status) {
          debugPrint('🎤 VoiceService STT status: $status');
          if (status == 'done' || status == 'notListening') {
            isListening.value = false;
          }
        },
      );

      if (!available) {
        voiceError.value = 'Speech recognition is not available on this device.';
        return false;
      }

      isInitialized.value = true;
      return true;
    } catch (e) {
      voiceError.value = 'Failed to initialize speech recognition: $e';
      debugPrint('❌ VoiceService init error: $e');
      return false;
    }
  }

  /// Starts listening for speech.
  /// [onResult] receives the final confirmed transcript.
  /// [onPartial] receives interim results (used for live captions in voice mode).
  Future<void> startListening({
    required void Function(String text) onResult,
    void Function(String partial)? onPartial,
  }) async {
    voiceError.value = '';

    // Guard: don't start if still releasing from previous session
    if (_isReleasingRecognizer) {
      debugPrint('🎤 VoiceService: recognizer still releasing, skipping start');
      return;
    }

    // Guard: don't start if already listening
    if (_stt.isListening) {
      debugPrint('🎤 VoiceService: already listening, skipping start');
      return;
    }

    final ready = await initSpeech();
    if (!ready) return;

    liveTranscript.value = '';
    isListening.value = true;

    await _stt.listen(
      onResult: (result) {
        liveTranscript.value = result.recognizedWords;
        if (result.finalResult) {
          isListening.value = false;
          final text = result.recognizedWords;
          debugPrint('🎤 VoiceService final result: "$text"');
          onResult(text);
        } else {
          onPartial?.call(result.recognizedWords);
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 4),
        localeId: 'en_US',
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
      ),
    );
  }

  /// Stops the STT listener immediately.
  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
    try {
      await _stt.cancel();
    } catch (_) {}
    isListening.value = false;

    // CRITICAL: wait for Android SpeechRecognizer to fully release
    // before allowing a new startListening() call
    await Future.delayed(const Duration(milliseconds: 800));
  }

  /// Dedicated release of recognizer to clean up native resources
  Future<void> releaseRecognizer() async {
    _isReleasingRecognizer = true;
    isListening.value = false;
    try {
      await _stt.stop();
    } catch (_) {}
    try {
      await _stt.cancel();
    } catch (_) {}
    // Wait for Android's SpeechRecognizer to fully clean up
    // 1200ms is the safe minimum observed on Samsung Galaxy devices
    await Future.delayed(const Duration(milliseconds: 1200));
    _isReleasingRecognizer = false;
  }

  // ── TTS ──────────────────────────────────────────────────

  /// Speaks [text] aloud using the active TTS provider.
  ///
  /// Routing:
  ///   All modes → on-device flutter_tts.
  ///   TODO: When API providers are active, prefer cloud TTS (OpenAI/Google TTS)
  ///   with on-device flutter_tts as fallback.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;

    isSpeaking.value = true;

    try {
      // Try Google Cloud TTS first (much better quality)
      final googleTts = Get.find<GoogleTtsService>();
      if (googleTts.isAvailable) {
        await googleTts.speak(text);
        isSpeaking.value = false;
        return;
      }
    } catch (_) {
      // GoogleTtsService not registered or unavailable — fall through
    }

    // Fallback: on-device flutter_tts
    final completer = Completer<void>();

    _tts.setCompletionHandler(() {
      isSpeaking.value = false;
      if (!completer.isCompleted) completer.complete();
    });

    _tts.setErrorHandler((message) {
      debugPrint('❌ TTS fallback error: $message');
      isSpeaking.value = false;
      if (!completer.isCompleted) completer.complete();
    });

    debugPrint('🔊 VoiceService: Speaking via on-device TTS (provider: fallback)');
    await _tts.speak(text);

    await completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () { isSpeaking.value = false; },
    );
  }

  /// Stops any ongoing TTS playback.
  Future<void> stopSpeaking() async {
    try {
      final googleTts = Get.find<GoogleTtsService>();
      await googleTts.stop();
    } catch (_) {}
    try { await _tts.stop(); } catch (_) {}
    isSpeaking.value = false;
  }

  @override
  void onClose() {
    _stt.cancel();
    _tts.stop();
    super.onClose();
  }
}
