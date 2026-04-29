import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/services/settings_service.dart';
import '../../domain/services/inference_router.dart';
import '../controllers/chat_controller.dart';
import '../pages/history_page.dart';
import '../pages/settings_page.dart';
import '../pages/kb_manager_page.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsService>();
    final controller = Get.find<ChatController>();
    final router = Get.find<InferenceRouterService>();
    final theme = Theme.of(context);

    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                const SizedBox(height: 16),
                Obx(() =>
                    _BackendStatusCard(backend: router.currentBackend.value)),
                const SizedBox(height: 24),

                _DrawerItem(
                  icon: Icons.history_rounded,
                  label: 'Chat History',
                  subtitle: 'Recall past interactions',
                  color: theme.colorScheme.secondary,
                  onTap: () {
                    Get.back();
                    Get.to(() => const HistoryPage());
                  },
                ),
                _DrawerItem(
                  icon: Icons.library_books_rounded,
                  label: 'Knowledge Base',
                  subtitle: 'Manage document context',
                  color: theme.colorScheme.tertiary,
                  onTap: () {
                    Get.back();
                    Get.to(() => const KbManagerPage());
                  },
                ),
                // _DrawerItem(
                //   icon: Icons.settings_rounded,
                //   label: 'Global Settings',
                //   subtitle: 'API keys & Network',
                //   color: theme.colorScheme.primary.withOpacity(0.8),
                //   onTap: () {
                //     Get.back();
                //     Get.to(() => const SettingsPage());
                //   },
                // ),

                const Divider(height: 40),

                // Obx(() => _ThemeToggle(
                //       isDarkMode: settings.isDarkMode.value,
                //       onChanged: settings.toggleDarkMode,
                //     )),

                _DrawerItem(
                  icon: Icons.delete_outline_rounded,
                  label: 'Clear Current Chat',
                  color: theme.colorScheme.error,
                  isDestructive: true,
                  onTap: () {
                    Get.back();
                    controller.clearChat();
                  },
                ),
              ],
            ),
          ),
          _buildFooter(theme),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
        bottom: 24,
        left: 24,
        right: 24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            isDark
                ? const Color(0xFF2E1A47)
                : theme.colorScheme.primary.withOpacity(0.8),
            theme.colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Image.asset(
              'assets/images/logo_icon.png',
              width: 32,
              height: 32,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Offline AI',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Grounded Assistant',
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          children: [
            const Divider(height: 1),
            const SizedBox(height: 20),
            Image.asset(
              'assets/images/logo_full.png',
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 8),
            Text(
              'Powered by Aeologic',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'v2.5.0-GROUNDED',
              style: TextStyle(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                  fontSize: 9,
                  fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackendStatusCard extends StatelessWidget {
  final InferenceBackend backend;
  const _BackendStatusCard({required this.backend});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _color.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              _PulseIndicator(color: _color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SYSTEM STATUS',
                      style: TextStyle(
                          color: _color.withOpacity(0.6),
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _getLabel(Get.find<SettingsService>().modelLabel),
                      style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    Text(
                      _getSubtitle(backend,
                          Get.find<SettingsService>().selectedModel.value),
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color get _color {
    switch (backend) {
      case InferenceBackend.ollama:
        return const Color(0xFF5D38BB);
      case InferenceBackend.onDevice:
        return const Color(0xFFFFB4AB);
    }
  }

  String _getLabel(String modelLabel) {
    switch (backend) {
      case InferenceBackend.ollama:
        return 'Ollama LAN';
      case InferenceBackend.onDevice:
        return modelLabel;
    }
  }

  String _getSubtitle(InferenceBackend backend, String modelPath) {
    switch (backend) {
      case InferenceBackend.ollama:
        return 'Network · Private host';
      case InferenceBackend.onDevice:
        final isPhi = modelPath.toLowerCase().contains('phi');
        return isPhi ? 'Offline · 3.8B Parameter' : 'Offline · 1.0B Parameter';
    }
  }
}

class _PulseIndicator extends StatefulWidget {
  final Color color;
  const _PulseIndicator({required this.color});

  @override
  State<_PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<_PulseIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withOpacity(1 - _controller.value),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.5 * (1 - _controller.value)),
                blurRadius: 10 * _controller.value,
                spreadRadius: 5 * _controller.value,
              )
            ],
          ),
        );
      },
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isDestructive;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isDestructive ? color.withOpacity(0.05) : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color:
                            isDestructive ? color : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant
                                .withOpacity(0.6),
                            fontSize: 11),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  final bool isDarkMode;
  final Function(bool) onChanged;

  const _ThemeToggle({required this.isDarkMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(
              isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: isDarkMode ? theme.colorScheme.secondary : Colors.amber,
              size: 20,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Aetheric Glow',
                style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
              ),
            ),
            Switch(
              value: isDarkMode,
              onChanged: onChanged,
              activeColor: theme.colorScheme.secondary,
              activeTrackColor: theme.colorScheme.primary.withOpacity(0.2),
            ),
          ],
        ),
      ),
    );
  }
}
