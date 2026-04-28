import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/model_registry.dart';
import '../../core/theme/aetheric_glow_extension.dart';
import '../../domain/models/model_download_progress.dart';
import '../../core/services/settings_service.dart';
import '../controllers/model_manager_controller.dart';

class ModelManagerPage extends GetView<ModelManagerController> {
  const ModelManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Get.find<SettingsService>();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Manage Models'),
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainer.withOpacity(0.8),
            ],
          ),
        ),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: kToolbarHeight + 40)),
            
            // Section: Filter Chips
            SliverToBoxAdapter(
              child: _buildFilterChips(context),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Section: Downloaded Models
            _buildSectionHeader(context, 'On-Device Library'),
            SliverToBoxAdapter(
              child: Column(
                children: ModelRegistry.models.map((model) {
                  return StreamBuilder<ModelDownloadProgress>(
                    stream: controller.getDownloadProgress(model.id),
                    builder: (context, snapshot) {
                      final status = snapshot.data?.status ?? DownloadStatus.idle;
                      if (status != DownloadStatus.completed) return const SizedBox.shrink();
                      
                      return Obx(() => _ModelCard(
                        model: model,
                        progress: snapshot.data,
                        isActive: settings.selectedModelId.value == model.id,
                        onActivate: () => controller.setActiveModel(model.id),
                        onDelete: () => _confirmDelete(context, model),
                      )).animate().fadeIn().slideX();
                    },
                  );
                }).toList(),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),

            // Section: Available to Download
            _buildSectionHeader(context, 'Available Intelligence'),
            SliverToBoxAdapter(
              child: Obx(() => Column(
                children: controller.filteredModels.map((model) {
                  return StreamBuilder<ModelDownloadProgress>(
                    stream: controller.getDownloadProgress(model.id),
                    builder: (context, snapshot) {
                      final status = snapshot.data?.status ?? DownloadStatus.idle;
                      if (status == DownloadStatus.completed) return const SizedBox.shrink();
                      
                      return _ModelCard(
                        model: model,
                        progress: snapshot.data,
                        isActive: false,
                        onDownload: () => controller.startDownload(model.id),
                        onPause: () => controller.pauseDownload(model.id),
                        onCancel: () => controller.cancelDownload(model.id),
                      ).animate().fadeIn().slideY(begin: 0.1, end: 0);
                    },
                  );
                }).toList(),
              )),
            ),
            
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: controller.categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = controller.categories[index];
          return Obx(() {
            final isSelected = controller.selectedCategory.value == cat;
            return ChoiceChip(
              label: Text(cat),
              selected: isSelected,
              onSelected: (_) => controller.filterModels(cat),
              backgroundColor: theme.colorScheme.surfaceContainer,
              selectedColor: theme.colorScheme.primary.withOpacity(0.2),
              labelStyle: TextStyle(
                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              side: BorderSide(
                color: isSelected ? theme.colorScheme.primary : Colors.transparent,
              ),
            );
          });
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, ModelDefinition model) {
    Get.dialog(
      AlertDialog(
        title: Text('Delete ${model.displayName}?'),
        content: const Text('This will remove the model file from your device and reclaim storage space.'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              controller.deleteModel(model.id);
              Get.back();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final ModelDefinition model;
  final ModelDownloadProgress? progress;
  final bool isActive;
  final VoidCallback? onActivate;
  final VoidCallback? onDelete;
  final VoidCallback? onDownload;
  final VoidCallback? onPause;
  final VoidCallback? onCancel;

  const _ModelCard({
    required this.model,
    this.progress,
    required this.isActive,
    this.onActivate,
    this.onDelete,
    this.onDownload,
    this.onPause,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glow = AethericGlowExtension.of(context);
    final status = progress?.status ?? DownloadStatus.idle;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: glow.glassSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isActive 
              ? theme.colorScheme.primary.withOpacity(0.5) 
              : glow.glassStroke!,
          width: isActive ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: glow.blurAmount!, sigmaY: glow.blurAmount!),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                model.displayName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (model.isRecommended) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Recommended',
                                    style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            model.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isActive)
                      Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                    else if (status == DownloadStatus.completed)
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: theme.colorScheme.error.withOpacity(0.6)),
                        onPressed: onDelete,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Specs & Tags
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _SpecTile(
                      icon: Icons.storage_rounded,
                      label: model.sizeLabel,
                    ),
                    _SpecTile(
                      icon: Icons.memory_rounded,
                      label: 'Min ${model.minRamGb}GB RAM',
                      isWarning: model.isHighEnd,
                    ),
                    Wrap(
                      spacing: 4,
                      children: model.tags.take(2).map((t) => _TagChip(label: t)).toList(),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Action Area
                _buildActionArea(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionArea(BuildContext context) {
    final theme = Theme.of(context);
    final status = progress?.status ?? DownloadStatus.idle;

    if (status == DownloadStatus.completed) {
      return Row(
        children: [
          Expanded(
            child: isActive
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'ACTIVE ENGINE',
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0, fontSize: 12),
                      ),
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onActivate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('SET AS ACTIVE'),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
              tooltip: 'Purge from storage',
            ),
          ),
        ],
      );
    }

    if (status == DownloadStatus.downloading || status == DownloadStatus.paused || status == DownloadStatus.verifying) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress?.percent,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${((progress?.percent ?? 0) * 100).toInt()}%',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                status == DownloadStatus.verifying ? 'Verifying Integrity...' : 'Downloading Local Meta-Cortex...',
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
              ),
              Row(
                children: [
                  if (status == DownloadStatus.downloading)
                    IconButton(icon: const Icon(Icons.pause_rounded), onPressed: onPause)
                  else if (status == DownloadStatus.paused)
                    IconButton(icon: const Icon(Icons.play_arrow_rounded), onPressed: onDownload),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: onCancel),
                ],
              ),
            ],
          ),
        ],
      );
    }

    // Default: Not downloaded
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.download_rounded, size: 18),
        label: const Text('INITIATE DOWNLOAD'),
        onPressed: () {
          if (model.isHighEnd) {
             _confirmLargeDownload(context);
          } else {
             onDownload?.call();
          }
        },
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: theme.colorScheme.primary),
        ),
      ),
    );
  }

  void _confirmLargeDownload(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('High-End Model Check'),
        content: Text('The ${model.displayName} requires significant resources (${model.minRamGb}GB RAM recorded min). Ensure your device has sufficient memory before proceeding.'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              onDownload?.call();
              Get.back();
            },
            child: const Text('Download Anyway'),
          ),
        ],
      ),
    );
  }
}

class _SpecTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isWarning;

  const _SpecTile({required this.icon, required this.label, this.isWarning = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: isWarning ? Colors.orange : theme.colorScheme.primary),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11, 
            fontWeight: FontWeight.w600,
            color: isWarning ? Colors.orange : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
