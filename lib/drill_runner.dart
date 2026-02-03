import 'dart:async';
import 'dart:io'; // REQUIRED: Added for File checks
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart'; 
import 'package:gal/gal.dart';

// watermark imports
import 'services/branding_service.dart'; 
import 'features/drill/providers.dart'; 

// Import the correct summary screen
import 'drill_summary_screen.dart';

class DrillRunnerScreen extends ConsumerStatefulWidget {
  const DrillRunnerScreen({super.key});
  @override
  ConsumerState<DrillRunnerScreen> createState() => _DrillRunnerScreenState();
}

class _DrillRunnerScreenState extends ConsumerState<DrillRunnerScreen> {
  static const int _countdownMs = 1000;
  int? _count;
  bool _showGo = false;
  bool _isProcessingVideo = false;
  Timer? _countTimer;

  @override
  void initState() {
    super.initState();
    // Start countdown immediately after build
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCountdown());
  }

  void _runCountdown() {
    setState(() => _count = 3);
    
    _countTimer = Timer.periodic(const Duration(milliseconds: _countdownMs), (t) async {
      if (!mounted) { t.cancel(); return; }
      
      if (_count == 3) { setState(() => _count = 2); return; }
      if (_count == 2) { setState(() => _count = 1); return; }
      
      if (_count == 1) {
        t.cancel();
        setState(() => _showGo = true);
        
        // Grab latest config and callouts
        final cfg = ref.read(drillConfigProvider);
        final callouts = await ref.read(calloutsForActivePackProvider.future);
        final isPro = ref.read(isProProvider);
        
        if (!mounted) return;

        // START THE ENGINE
        await ref.read(drillEngineProvider.notifier).start(
              config: cfg,
              allCallouts: callouts,
              isPro: isPro,
            );

        if (!mounted) return;
        setState(() => _count = null);
        
        // Hide "GO!" after a short delay
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) setState(() => _showGo = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _countTimer?.cancel();
    // Fire and forget stop is fine in dispose
    ref.read(drillEngineProvider.notifier).stop(); 
    super.dispose();
  }

  // NEW: Robust File Checker to prevent Race Conditions
  Future<bool> _waitForFileReady(String path) async {
    final file = File(path);
    int attempts = 0;
    // Try for up to 5 seconds (10 attempts * 500ms)
    while (attempts < 10) {
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0) return true; // File exists and has content
      }
      await Future.delayed(const Duration(milliseconds: 500));
      attempts++;
    }
    return false; // Timed out
  }

 @override
  Widget build(BuildContext context) {
    // 1. Listen for DRILL FINISHED to start processing
    ref.listen(drillEngineProvider, (previous, next) async {
      // Trigger only when we switch from not-finished to finished
      if (previous?.finished == false && next.finished == true) {
        
        // Prevent double-processing
        if (_isProcessingVideo) return;

        // Grab values before async gap
        final isPro = ref.read(isProProvider);
        // CRITICAL: Ensure we grab the path from the state
        String? finalPath = next.videoPath; 
        
        print("Drill Finished. Processing video path: $finalPath");

        // Use post-frame callback to avoid "Bad state" during build
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;

          // If we have a video path, process it
          if (finalPath != null && finalPath!.isNotEmpty) {
            setState(() => _isProcessingVideo = true);

            try {
              // --- HANDOFF DELAY (Fixes "Connection Aborted") ---
              // Give the camera plugin 1.5 seconds to flush the file stream
              await Future.delayed(const Duration(milliseconds: 1500));
              
              // Verify file integrity
              final isReady = await _waitForFileReady(finalPath!);
              
              if (!isReady) {
                print("Error: Video file not found or empty after waiting.");
                // Proceed without branding to at least save the raw data if possible?
                // Or just fail gracefully. For now, we continue with finalPath as is.
              }

              // --- WATERMARK LOGIC ---
              if (!isPro && isReady) {
                debugPrint("Branding video at: $finalPath");
                
                // Wrap in try-catch so branding failure doesn't lose the video
                try {
                  final brandedPath = await BrandingService().brandVideo(
                    finalPath!, 
                    'assets/images/keepkidswrestling_logo.png'
                  );
                  
                  if (brandedPath != null) {
                    // Success! Use the new branded file
                    finalPath = brandedPath; 
                    debugPrint("Branding successful: $finalPath");
                  } else {
                    debugPrint("Branding returned null, using raw video.");
                  }
                } catch (brandingError) {
                   debugPrint("Branding threw error: $brandingError. Using raw video.");
                }
              }
              
            } catch (e) {
              debugPrint("Video processing critical error: $e");
            } finally {
              if (mounted) {
                setState(() => _isProcessingVideo = false);
                
                // Navigate to Summary and pass the FINAL path
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => DrillSummaryScreen(
                      totalTime: next.elapsed,
                      calloutsCompleted: next.calloutsCompleted,
                      videoPath: finalPath, // Pass the processed (or raw) path
                    ),
                  ),
                );
              }
            }
          } else {
            // No video recorded, just go to summary
             print("No video path found. Skipping processing.");
             Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => DrillSummaryScreen(
                    totalTime: next.elapsed,
                    calloutsCompleted: next.calloutsCompleted,
                    videoPath: null,
                  ),
                ),
              );
          }
        });
      }
    });

    final state = ref.watch(drillEngineProvider);
    final cfg = ref.watch(drillConfigProvider);

    Duration remaining = state.total - state.elapsed;
    if (remaining.isNegative) remaining = Duration.zero;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drill Runner'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isProcessingVideo ? null : () async {
            await ref.read(drillEngineProvider.notifier).stop();
            if (mounted) Navigator.pop(context);
    },
        ),
      ),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _isProcessingVideo, 
            child: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                    _TimerCard(remaining: remaining, total: state.total),
                    const SizedBox(height: 8),

                    // 1. RECORDING INDICATOR
                    if (state.isRecording)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const _BlinkingDot(),
                            const SizedBox(width: 8),
                            Text(
                              "RECORDING",
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                      ),

                    // 2. DRILL INFO
                    if (state.lastCallout != null)
                      _InfoTile(
                        label: 'Last Callout',
                        value: state.lastCallout!.name,
                        icon: Icons.campaign,
                      ),
                    
                    _InfoTile(
                      label: 'Difficulty',
                      value: '${cfg.minIntervalSeconds.toStringAsFixed(1)}s – ${cfg.maxIntervalSeconds.toStringAsFixed(1)}s',
                      icon: Icons.av_timer,
                    ),

                    if (state.holdRemaining != null)
                      _InfoTile(
                        label: 'Hold Remaining',
                        value: _fmt(state.holdRemaining!),
                        icon: Icons.schedule,
                      ),

                    // 3. CAMERA PREVIEW
                    if (cfg.videoEnabled && state.cameraInitialized)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            color: Colors.black,
                            height: 300, // Fixed height to prevent layout jumps
                            width: double.infinity,
                            child: Builder(
                              builder: (context) {
                                final controller = ref.read(drillEngineProvider.notifier).cameraController;
                                if (controller == null) return const SizedBox.shrink();
                                return CameraPreview(controller);
                              },
                            ),
                          ),
                        ),
                      )
                    else if (cfg.videoEnabled)
                       const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
                    else
                      const SizedBox(height: 50),

                    // 4. ACTION BUTTONS
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _isProcessingVideo 
                              ? null // Disables button while branding
                              : (state.paused 
                                  ? () async {
                                      final callouts = await ref.read(calloutsForActivePackProvider.future);
                                      ref.read(drillEngineProvider.notifier).resume(
                                            config: cfg,
                                            allCallouts: callouts,
                                          );
                                    }
                                  : () => ref.read(drillEngineProvider.notifier).pause()),
                            icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
                            label: Text(state.paused ? 'Resume' : 'Pause'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isProcessingVideo 
                              ? null // Disables button while branding
                              : () async {
                                  await ref.read(drillEngineProvider.notifier).stop();
                                  if (mounted) Navigator.pop(context);
                                },
                            icon: const Icon(Icons.stop),
                            label: const Text('End Drill'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

          // 5. COUNTDOWN OVERLAY
          if (_count != null || _showGo)
            Positioned.fill(
              child: _CountdownOverlay(value: _showGo ? 'GO!' : '${_count ?? ''}'),
            ),

          // 6. VIDEO PROCESSING OVERLAY
          if (_isProcessingVideo)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      "Finalizing Video...",
                      style: TextStyle(
                        color: Colors.white, 
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Adding Watermark & Saving...",
                      style: TextStyle(
                        color: Colors.white70, 
                        fontSize: 14, 
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ], 
      ), 
    ); 
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s}s';
  }
}

// --- SUB WIDGETS ---

class _CountdownOverlay extends StatelessWidget {
  final String value;
  const _CountdownOverlay({required this.value});
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
          child: Text(
            value,
            key: ValueKey(value),
            style: const TextStyle(
              fontSize: 100, 
              color: Colors.white, 
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimerCard extends StatelessWidget {
  final Duration remaining;
  final Duration total;
  const _TimerCard({required this.remaining, required this.total});

  @override
  Widget build(BuildContext context) {
    // Standard progress bar (0.0 to 1.0)
    final pct = total.inMilliseconds == 0 
        ? 0.0 
        : (1.0 - (remaining.inMilliseconds / total.inMilliseconds)).clamp(0.0, 1.0);
        
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: pct, 
              borderRadius: BorderRadius.circular(4),
              minHeight: 8,
            ),
            const SizedBox(height: 16),
            Text(
              _clock(remaining),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold, 
                fontFeatures: [const FontFeature.tabularFigures()] // Keeps numbers from jumping
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();
  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _controller, child: const Icon(Icons.circle, color: Colors.red, size: 14));
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _InfoTile({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}
