import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/startup_controller.dart';

class StartupPage extends StatelessWidget {
  const StartupPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(StartupController());
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background soft gradients for a premium feel
          Positioned(
            top: -50,
            right: -50,
            child: _GlowCircle(color: theme.colorScheme.primary.withOpacity(0.08), size: 300),
          ),
          Positioned(
            bottom: -100,
            left: -50,
            child: _GlowCircle(color: theme.colorScheme.secondary.withOpacity(0.08), size: 400),
          ),

          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Large, prominent logo with soft shadow
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/logo_icon.png',
                        height: 80, // Much larger for better visibility
                        width: 80,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Title and Subtitle
                    Text(
                      'OFFLINE AI',
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: Colors.black.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'SYSTEM INITIALIZATION',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                        color: Colors.black38,
                      ),
                    ),
                    
                    const SizedBox(height: 48),

                    // Log Card (Glassmorphic look)
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.black.withOpacity(0.05)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Log Header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                            child: Row(
                              children: [
                                Icon(Icons.terminal_rounded, size: 14, color: Colors.black38),
                                const SizedBox(width: 8),
                                Text(
                                  'BOOT LOGS',
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black38,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, thickness: 0.5),
                          
                          // Scrolling Logs
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20.0),
                              child: Obx(() => ListView.builder(
                                    reverse: true,
                                    itemCount: controller.logs.length,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    itemBuilder: (context, index) {
                                      final log = controller.logs[controller.logs.length - 1 - index];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 6.0),
                                        child: Text(
                                          log,
                                          style: GoogleFonts.firaCode(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: _getLogColor(log),
                                          ),
                                        ),
                                      );
                                    },
                                  )),
                            ),
                          ),
                          
                          // Integrated Progress Bar at the bottom of the card
                          Obx(() => LinearProgressIndicator(
                                value: controller.progress.value,
                                backgroundColor: Colors.transparent,
                                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                                minHeight: 4,
                              )),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Current Task Text
                    Obx(() => AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            controller.currentTask.value,
                            key: ValueKey(controller.currentTask.value),
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black54,
                            ),
                          ),
                        )),
                    
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getLogColor(String log) {
    if (log.contains('✅') || log.contains('OK')) return const Color(0xFF43A047);
    if (log.contains('🚨') || log.contains('Error') || log.contains('FAILED')) return const Color(0xFFE53935);
    if (log.contains('[STARTUP]')) return const Color(0xFF1E88E5);
    if (log.contains('[INGEST]')) return const Color(0xFFFB8C00);
    return Colors.black45;
  }
}

class _GlowCircle extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowCircle({Key? key, required this.color, required this.size}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, Colors.transparent],
        ),
      ),
    );
  }
}
