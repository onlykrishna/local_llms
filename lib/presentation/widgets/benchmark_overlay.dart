import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/benchmark_service.dart';

class BenchmarkOverlay extends StatefulWidget {
  const BenchmarkOverlay({super.key});

  @override
  State<BenchmarkOverlay> createState() => _BenchmarkOverlayState();
}

class _BenchmarkOverlayState extends State<BenchmarkOverlay> {
  final RxBool _isExpanded = false.obs;
  final benchmark = Get.find<BenchmarkService>();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 50,
      right: 16,
      child: Obx(() {
        if (!_isExpanded.value) {
          return _buildCollapsed();
        }
        return _buildExpanded();
      }),
    );
  }

  Widget _buildCollapsed() {
    return GestureDetector(
      onTap: () => _isExpanded.value = true,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: const Icon(Icons.speed, color: Colors.cyanAccent, size: 24),
      ),
    );
  }

  Widget _buildExpanded() {
    final summary = benchmark.summarize();
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'PIPELINE METRICS',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    onPressed: () => _isExpanded.value = false,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 20),
              _buildMetricRow('P50 Total', '${summary.p50TotalMs}ms'),
              _buildMetricRow('P90 Total', '${summary.p90TotalMs}ms'),
              _buildMetricRow('P50 Inference', '${summary.p50InferenceMs}ms'),
              const SizedBox(height: 8),
              _buildMetricRow('Avg Embed', '${summary.avgEmbeddingMs}ms'),
              _buildMetricRow('Avg Retrieval', '${summary.avgRetrievalMs}ms'),
              const SizedBox(height: 8),
              _buildMetricRow('Bypass Rate', '${(summary.bypassRate * 100).toStringAsFixed(1)}%'),
              _buildMetricRow('Samples', '${summary.sampleCount}'),
              const Divider(color: Colors.white12, height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await benchmark.exportToFile();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Metrics exported to Documents')),
                          );
                        }
                      },
                      icon: const Icon(Icons.download, size: 14),
                      label: const Text('EXPORT', style: TextStyle(fontSize: 10)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent.withOpacity(0.1),
                        foregroundColor: Colors.cyanAccent,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
