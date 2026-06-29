import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/models/ai_provider.dart';
import '../../../../core/services/api_provider_service.dart';
import '../../../../core/services/local_llm_service.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/embedding_service.dart';
import '../../../../core/theme/app_theme.dart';

class AiEngineSection extends StatefulWidget {
  const AiEngineSection({super.key});

  @override
  State<AiEngineSection> createState() => _AiEngineSectionState();
}

class _AiEngineSectionState extends State<AiEngineSection> {
  final _apiService = Get.find<ApiProviderService>();
  final _localLlm = Get.find<LocalLlmService>();
  final _analytics = Get.find<AnalyticsService>();
  final _embeddingService = Get.find<EmbeddingService>();

  String? _editingKey; // which provider's key is being entered
  final _keyController = TextEditingController();

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _selectProvider(AiProvider provider) async {
    _apiService.switchProvider(provider);
    Get.snackbar(
      'AI Engine updated',
      '${provider.displayName} is now active.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _saveApiKey(AiProvider provider) async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;

    await _apiService.saveKey(provider, key);

    setState(() => _editingKey = null);
    _keyController.clear();

    // Auto-activate provider once key is successfully saved
    await _selectProvider(provider);

    Get.snackbar(
      'Key saved',
      '${provider.displayName} key saved securely.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> _downloadModel() async {
    try {
      await _localLlm.downloadModel(
        onProgress: (p) {},
      );
      await _localLlm.loadModel();
      _analytics.logOfflineModelDownloaded();
      if (mounted) {
        // Issue 9: auto-switch to Offline now that the model is ready
        _apiService.switchProvider(AiProvider.offline);
        Get.snackbar(
          '✅ Offline model ready',
          'Switched to Offline (Llama). Your device is now running AI locally.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Download failed',
          e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.error.withAlpha(200),
          colorText: Colors.white,
        );
      }
    }
  }


  Future<void> _deleteModel() async {
    await _localLlm.deleteModel();
    Get.snackbar(
      'Model deleted',
      'Storage space reclaimed.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Obx(() {
            final current = _apiService.activeProvider.value;
            final isOfflineReady = _localLlm.isModelReady.value;
            return Column(
              children: AiProvider.values.map((provider) {
                final isSelected = current == provider;
                final isEditing = _editingKey == provider.name;

                // Check key status reactively
                final bool isKeySaved = provider == AiProvider.openai
                    ? _apiService.openAiKey.value.isNotEmpty
                    : provider == AiProvider.groq
                        ? _apiService.groqKey.value.isNotEmpty
                        : provider == AiProvider.gemini
                            ? _apiService.geminiKey.value.isNotEmpty
                            : false;

                return _ProviderRow(
                  provider: provider,
                  isSelected: isSelected,
                  isEditingKey: isEditing,
                  isKeySaved: isKeySaved,
                  isOfflineReady: isOfflineReady,
                  keyController: _keyController,
                  onTap: () async {
                    if (provider == AiProvider.offline) {
                      final downloaded = await _localLlm.isModelDownloaded();
                      if (!downloaded) {
                        Get.snackbar(
                          'Download required',
                          'Download the offline model below before switching.',
                          snackPosition: SnackPosition.BOTTOM,
                        );
                        return;
                      }
                      if (!_localLlm.isModelReady.value) {
                        await _localLlm.loadModel();
                      }
                      await _selectProvider(provider);
                    } else {
                      // OpenAI or Groq
                      if (!isKeySaved) {
                        setState(() {
                          _editingKey = provider.name;
                          _keyController.clear();
                        });
                      } else {
                        await _selectProvider(provider);
                      }
                    }
                  },
                  onEditKey: provider.requiresApiKey
                      ? () => setState(() {
                            _editingKey = provider.name;
                            _keyController.clear();
                          })
                      : null,
                  onSaveKey: provider.requiresApiKey
                      ? () => _saveApiKey(provider)
                      : null,
                  onDeleteKey: provider.requiresApiKey && isKeySaved
                      ? () async {
                          await _apiService.deleteKey(provider);
                          Get.snackbar(
                            'Key deleted',
                            '${provider.displayName} API key removed.',
                            snackPosition: SnackPosition.BOTTOM,
                          );
                        }
                      : null,
                );
              }).toList(),
            );
          }),
        ),

        const SizedBox(height: AppSpacing.sm),

        // ── Offline model management ─────────────────────
        Obx(() {
          final isDownloading = _localLlm.isDownloading.value;
          final isReady = _localLlm.isModelReady.value;
          final progress = _localLlm.downloadProgress.value;
          final error = _localLlm.loadError.value;

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.memory_rounded, color: AppColors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Offline Model',
                        style: AppTextStyles.title,
                      ),
                      const Spacer(),
                      if (isReady)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withAlpha(30),
                            borderRadius: const BorderRadius.all(AppRadius.full),
                          ),
                          child: Text(
                            'Ready',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${LocalLlmService.modelFileName}\n~2 GB · Llama 3.2 3B Instruct Q4_K_M',
                    style: AppTextStyles.caption.copyWith(color: Colors.grey),
                  ),

                  if (error.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      error,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.error),
                    ),
                  ],

                  if (isDownloading) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(AppRadius.full),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: AppColors.surfaceLight,
                              color: AppColors.primary,
                              minHeight: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!isReady && !isDownloading)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                          ),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Download Model'),
                          onPressed: _downloadModel,
                        ),
                      if (isDownloading)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                          ),
                          icon: const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          label: const Text('Downloading...'),
                          onPressed: null,
                        ),
                      if (isReady) ...[
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                          ),
                          icon: const Icon(Icons.check_circle_rounded),
                          label: const Text('Model Loaded'),
                          onPressed: null,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        OutlinedButton.icon(
                          icon: Icon(Icons.delete_rounded,
                              color: AppColors.error, size: 18),
                          label: Text(
                            'Delete',
                            style: TextStyle(color: AppColors.error),
                          ),
                          onPressed: _deleteModel,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.error),
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: AppSpacing.md),

        // ── Embeddings provider (unchanged, existing logic status) ──
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            'EMBEDDINGS PROVIDER',
            style: AppTextStyles.label.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
            ),
          ),
        ),
        Card(
          child: Obx(() {
            final isOpenAi = _apiService.openAiKey.value.isNotEmpty;
            final isHfKeySaved = _embeddingService.hfKey.value.isNotEmpty;
            final isEditingHf = _editingKey == 'HuggingFace';

            return Column(
              children: [
                _EmbeddingProviderRow(
                  name: 'OpenAI',
                  subtitle: 'text-embedding-3-small · 1536 dim',
                  isActive: isOpenAi,
                ),
                const Divider(height: 1),
                _EmbeddingProviderRow(
                  name: 'HuggingFace',
                  subtitle: 'all-MiniLM-L6-v2 · 384 dim',
                  isActive: !isOpenAi,
                  isKeySaved: isHfKeySaved,
                  isEditingKey: isEditingHf,
                  keyController: _keyController,
                  onEditKey: () => setState(() {
                    _editingKey = 'HuggingFace';
                    _keyController.clear();
                  }),
                  onSaveKey: () async {
                    final key = _keyController.text.trim();
                    if (key.isNotEmpty) {
                      await _embeddingService.saveHfKey(key);
                    }
                    setState(() => _editingKey = null);
                    _keyController.clear();
                  },
                  onDeleteKey: isHfKeySaved
                      ? () async {
                          await _embeddingService.deleteHfKey();
                          Get.snackbar(
                            'Key deleted',
                            'HuggingFace API key removed.',
                            snackPosition: SnackPosition.BOTTOM,
                          );
                        }
                      : null,
                  isLast: true,
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

class _ProviderRow extends StatelessWidget {
  final AiProvider provider;
  final bool isSelected;
  final bool isEditingKey;
  final bool isKeySaved;
  final bool isOfflineReady;
  final TextEditingController keyController;
  final VoidCallback onTap;
  final VoidCallback? onEditKey;
  final VoidCallback? onSaveKey;
  final VoidCallback? onDeleteKey;

  const _ProviderRow({
    required this.provider,
    required this.isSelected,
    required this.isEditingKey,
    required this.isKeySaved,
    required this.isOfflineReady,
    required this.keyController,
    required this.onTap,
    this.onEditKey,
    this.onSaveKey,
    this.onDeleteKey,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = provider == AiProvider.values.last;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: isLast
              ? const BorderRadius.only(
                  bottomLeft: AppRadius.md,
                  bottomRight: AppRadius.md,
                )
              : BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              children: [
                // Radio indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppColors.primary : Colors.grey,
                      width: isSelected ? 2 : 1.5,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: AppSpacing.md),

                // Provider info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.displayName,
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _providerSubtitle(provider),
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),

                // Status text / Edit Key button
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStatusLabel(context),
                    if (provider.requiresApiKey) ...[
                      const SizedBox(width: AppSpacing.sm),
                      IconButton(
                        icon: Icon(
                          isKeySaved ? Icons.edit_outlined : Icons.vpn_key_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        tooltip: isKeySaved ? 'Update Key' : 'Configure Key',
                        onPressed: onEditKey,
                      ),
                      if (isKeySaved) ...[
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppColors.error,
                          ),
                          tooltip: 'Delete Key',
                          onPressed: onDeleteKey,
                        ),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),

        // Inline API key entry (expands when editing)
        if (isEditingKey)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: keyController,
                    obscureText: true,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: AppTextStyles.body,
                    decoration: InputDecoration(
                      hintText: 'Paste ${provider.displayName} API key...',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                    onSubmitted: (_) => onSaveKey?.call(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  ),
                  onPressed: onSaveKey,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),

        if (!isLast) const Divider(height: 1),
      ],
    );
  }

  Widget _buildStatusLabel(BuildContext context) {
    if (provider == AiProvider.offline) {
      return Text(
        isOfflineReady ? '2.1 GB ready' : 'Not downloaded',
        style: AppTextStyles.caption.copyWith(
          color: isOfflineReady ? AppColors.success : Colors.grey,
          fontWeight: FontWeight.w500,
        ),
      );
    } else {
      return Text(
        isKeySaved ? '●●●●●●●● saved' : 'No key set',
        style: AppTextStyles.caption.copyWith(
          color: isKeySaved ? AppColors.success : AppColors.error.withAlpha(200),
          fontWeight: FontWeight.w500,
        ),
      );
    }
  }

  String _providerSubtitle(AiProvider p) {
    switch (p) {
      case AiProvider.openai:
        return 'gpt-4o-mini · OpenAI engine';
      case AiProvider.groq:
        return 'llama-3.3-70b-versatile · Groq engine';
      case AiProvider.gemini:
        return 'gemini-1.5-flash · Gemini engine';
      case AiProvider.offline:
        return 'On-device · Llama 3.2 3B';
    }
  }
}

class _EmbeddingProviderRow extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool isActive;
  final bool isLast;
  final bool isKeySaved;
  final bool isEditingKey;
  final TextEditingController? keyController;
  final VoidCallback? onEditKey;
  final VoidCallback? onSaveKey;
  final VoidCallback? onDeleteKey;

  const _EmbeddingProviderRow({
    required this.name,
    required this.subtitle,
    required this.isActive,
    this.isLast = false,
    this.isKeySaved = false,
    this.isEditingKey = false,
    this.keyController,
    this.onEditKey,
    this.onSaveKey,
    this.onDeleteKey,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary.withAlpha(12) : null,
            borderRadius: (isLast && !isEditingKey)
                ? const BorderRadius.only(
                    bottomLeft: AppRadius.md,
                    bottomRight: AppRadius.md,
                  )
                : null,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 4,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive ? AppColors.primary : Colors.grey,
                    width: isActive ? 2 : 1.5,
                  ),
                ),
                child: isActive
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: AppTextStyles.caption.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (onEditKey != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isActive ? 'Active' : 'Inactive',
                      style: AppTextStyles.caption.copyWith(
                        color: isActive ? AppColors.success : Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isKeySaved ? '●●●●●●●● saved' : 'No key set',
                          style: AppTextStyles.caption.copyWith(
                            color: isKeySaved
                                ? AppColors.success
                                : AppColors.error.withAlpha(200),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            isKeySaved
                                ? Icons.edit_outlined
                                : Icons.vpn_key_outlined,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          tooltip: isKeySaved ? 'Update Key' : 'Configure Key',
                          onPressed: onEditKey,
                        ),
                        if (isKeySaved && onDeleteKey != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: AppColors.error,
                            ),
                            tooltip: 'Delete Key',
                            onPressed: onDeleteKey,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  isActive ? 'Active' : 'Inactive',
                  style: AppTextStyles.caption.copyWith(
                    color: isActive ? AppColors.success : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Inline API key entry
        if (isEditingKey && keyController != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: keyController,
                    obscureText: true,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: AppTextStyles.body,
                    decoration: InputDecoration(
                      hintText: 'Paste $name API key...',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                    onSubmitted: (_) => onSaveKey?.call(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  ),
                  onPressed: onSaveKey,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
