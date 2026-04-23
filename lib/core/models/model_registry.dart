import 'package:flutter/foundation.dart';

enum RecommendedFor { chat, coding, multilingual, reasoning }

class ModelDefinition {
  final String id;
  final String displayName;
  final String description;
  final String sizeLabel;
  final int sizeBytes;
  final String downloadUrl;
  final String fileName;
  final bool isRecommended;
  final List<String> tags;
  final int minRamGb;
  final RecommendedFor purpose;
  final String huggingFaceRepo;
  final String? sha256;

  const ModelDefinition({
    required this.id,
    required this.displayName,
    required this.description,
    required this.sizeLabel,
    required this.sizeBytes,
    required this.downloadUrl,
    required this.fileName,
    this.isRecommended = false,
    required this.tags,
    required this.minRamGb,
    required this.purpose,
    required this.huggingFaceRepo,
    this.sha256,
  });

  bool get isHighEnd => minRamGb >= 12;
}

class ModelRegistry {
  static const List<ModelDefinition> models = [
    // GEMMA 4 MODELS (Next-Gen 2026 Edge Models)
    ModelDefinition(
      id: 'gemma4_e2b',
      displayName: 'Gemma 4 E2B',
      description: 'Optimized for edge performance (~48 tok/s). Incredible speed for real-time mobile interaction.',
      sizeLabel: '1.5GB',
      sizeBytes: 1610612736,
      downloadUrl: 'https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF/resolve/main/google_gemma-4-E2B-it-Q4_K_M.gguf',
      fileName: 'google_gemma-4-E2B-it-Q4_K_M.gguf',
      isRecommended: true,
      tags: ['Google', 'Edge', 'Fast'],
      minRamGb: 4,
      purpose: RecommendedFor.chat,
      huggingFaceRepo: 'google/gemma-4-E2B-it',
    ),
    ModelDefinition(
      id: 'gemma4_e4b',
      displayName: 'Gemma 4 E4B',
      description: 'Superior reasoning and vision capabilities. Best-in-class multi-modal edge logic.',
      sizeLabel: '2.8GB',
      sizeBytes: 3006477107,
      downloadUrl: 'https://huggingface.co/bartowski/google_gemma-4-E4B-it-GGUF/resolve/main/google_gemma-4-E4B-it-Q4_K_M.gguf',
      fileName: 'google_gemma-4-E4B-it-Q4_K_M.gguf',
      isRecommended: true,
      tags: ['Google', 'Reasoning', 'Vision'],
      minRamGb: 8,
      purpose: RecommendedFor.reasoning,
      huggingFaceRepo: 'google/gemma-4-E4B-it',
    ),

    // GEMMA 3 MODELS (High Quality Q4_K_M)
    ModelDefinition(
      id: 'gemma3_1b',
      displayName: 'Gemma 3 1B',
      description: 'Google\'s next-gen 1B. Upgraded to Q4_K_M for better factual coherence than XS.',
      sizeLabel: '690MB',
      sizeBytes: 690 * 1024 * 1024,
      downloadUrl: 'https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/google_gemma-3-1b-it-Q4_K_M.gguf',
      fileName: 'google_gemma-3-1b-it-Q4_K_M.gguf',
      isRecommended: true,
      tags: ['Google', 'Lite', 'Verified'],
      minRamGb: 2,
      purpose: RecommendedFor.chat,
      huggingFaceRepo: 'google/gemma-3-1b-it-GGUF',
    ),
    ModelDefinition(
      id: 'gemma3_4b',
      displayName: 'Gemma 3 4B',
      description: 'Balanced powerhouse. Excellent for reasoning and instruction following.',
      sizeLabel: '2.5GB',
      sizeBytes: 2684354560,
      downloadUrl: 'https://huggingface.co/bartowski/google_gemma-3-4b-it-GGUF/resolve/main/google_gemma-3-4b-it-Q4_K_M.gguf',
      fileName: 'google_gemma-3-4b-it-Q4_K_M.gguf',
      isRecommended: false,
      tags: ['Google', 'Balanced'],
      minRamGb: 6,
      purpose: RecommendedFor.reasoning,
      huggingFaceRepo: 'google/gemma-3-4b-it-GGUF',
    ),

    // QWEN 2.5 MODELS (The new standard for knowledge)
    ModelDefinition(
      id: 'qwen2_5_3b',
      displayName: 'Qwen 2.5 3B',
      description: 'Alibaba centerpiece. Best-in-class factual accuracy for 3B parameter models.',
      sizeLabel: '2.1GB',
      sizeBytes: 2147483648,
      downloadUrl: 'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      fileName: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      isRecommended: true,
      tags: ['Alibaba', 'Factual', 'High-Accuracy'],
      minRamGb: 4,
      purpose: RecommendedFor.chat,
      huggingFaceRepo: 'Qwen/Qwen2.5-3B-Instruct',
    ),
    ModelDefinition(
      id: 'qwen2_5_1_5b',
      displayName: 'Qwen 2.5 1.5B',
      description: 'Exceptional efficiency. Punches way above its weight for reasoning and facts.',
      sizeLabel: '1.1GB',
      sizeBytes: 1181116006,
      downloadUrl: 'https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      fileName: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      isRecommended: true,
      tags: ['Alibaba', 'Efficient', 'Knowledge'],
      minRamGb: 4,
      purpose: RecommendedFor.multilingual,
      huggingFaceRepo: 'Qwen/Qwen2.5-1.5B-Instruct',
    ),

    // LLAMA MODELS
    ModelDefinition(
      id: 'llama3_2_1b',
      displayName: 'LLaMA 3.2 1B',
      description: 'Meta\'s mobile standard. Optimized for low-power ARM architectures.',
      sizeLabel: '743MB',
      sizeBytes: 779100160,
      downloadUrl: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-IQ4_XS.gguf',
      fileName: 'Llama-3.2-1B-Instruct-IQ4_XS.gguf',
      tags: ['Meta', 'Lite'],
      minRamGb: 2,
      purpose: RecommendedFor.chat,
      huggingFaceRepo: 'Meta-Llama/Llama-3.2-1B-Instruct',
    ),
    ModelDefinition(
      id: 'llama3_2_3b',
      displayName: 'LLaMA 3.2 3B',
      description: 'Meta\'s flagship 3B. Balanced instruction following and context memory.',
      sizeLabel: '1.9GB',
      sizeBytes: 2040109465,
      downloadUrl: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      fileName: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      tags: ['Meta', 'Balanced'],
      minRamGb: 4,
      purpose: RecommendedFor.chat,
      huggingFaceRepo: 'Meta-Llama/Llama-3.2-3B-Instruct',
    ),

    // OTHER MODELS
    ModelDefinition(
      id: 'smollm2_1_7b',
      displayName: 'SmolLM2 1.7B',
      description: 'Fast, compact, and consistent for everyday mobile tasks.',
      sizeLabel: '1.1GB',
      sizeBytes: 1181116006,
      downloadUrl: 'https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/resolve/main/smollm2-1.7b-instruct-q4_k_m.gguf',
      fileName: 'smollm2-1.7b-instruct-q4_k_m.gguf',
      tags: ['HuggingFace', 'Fast'],
      minRamGb: 2,
      purpose: RecommendedFor.chat,
      huggingFaceRepo: 'HuggingFaceTB/SmolLM2-1.7B-Instruct',
    ),
    ModelDefinition(
      id: 'phi4_mini',
      displayName: 'Phi-4 Mini',
      description: 'Microsoft reasoning specialist. Heavyweight intelligence in a compact frame.',
      sizeLabel: '2.3GB',
      sizeBytes: 2469606195,
      downloadUrl: 'https://huggingface.co/bartowski/phi-4-mini-instruct-GGUF/resolve/main/phi-4-mini-instruct-Q4_K_M.gguf',
      fileName: 'phi-4-mini-instruct-Q4_K_M.gguf',
      tags: ['Microsoft', 'Reasoning'],
      minRamGb: 4,
      purpose: RecommendedFor.reasoning,
      huggingFaceRepo: 'microsoft/phi-4-mini-instruct',
    ),
  ];
}
