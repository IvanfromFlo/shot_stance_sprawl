import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

// Import your internal logic files
import 'package:shot_stance_sprawl/features/drill/models.dart';
import 'package:shot_stance_sprawl/features/drill/providers.dart';
import 'package:shot_stance_sprawl/features/drill/drill_engine.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  double _difficultyValue = 1.0; // 0.0 (Easy) to 3.0 (Dan Gable)

  // Map difficulty slider value to intervals
  final List<(String, double, double)> _difficultyLevels = [
    ('Easy (3–5s)', 3.0, 5.0),
    ('Medium (2–4s)', 2.0, 4.0),
    ('Hard (1–2s)', 1.0, 2.0),
    ('Dan Gable (0.5–1.5s)', 0.5, 1.5),
  ];

  @override
  void initState() {
    super.initState();
    // Sync local slider state with provider on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final config = ref.read(drillConfigProvider);
      // Simple logic to find closest difficulty level for initial slider position
      // Default to Medium (index 1) if exact match not found
      int index = 1; 
      for(int i=0; i<_difficultyLevels.length; i++) {
        if((config.minIntervalSeconds - _difficultyLevels[i].$2).abs() < 0.1) {
          index = i;
          break;
        }
      }
      setState(() {
        _difficultyValue = index.toDouble();
      });
    });
  }

  void _updateDifficulty(double value) {
    setState(() => _difficultyValue = value);
    final index = value.round();
    final level = _difficultyLevels[index];
    ref.read(drillConfigProvider.notifier).setIntervalRange(
      minSeconds: level.$2,
      maxSeconds: level.$3,
    );
  }

  void _showFadingToast(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 100,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: _FadeToast(message: message),
        ),
      ),
    );

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () => entry.remove());
  }

  void _showRecordingSheet(BuildContext context, WidgetRef ref, String id, String name) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RecordingSheetContent(calloutId: id, calloutName: name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(drillConfigProvider);
    final engine = ref.watch(drillEngineProvider);
    final calloutsAsync = ref.watch(calloutsProvider);
    final lang = ref.watch(languageProvider);
    final notifier = ref.read(drillConfigProvider.notifier);
    final isPro = ref.watch(isProProvider);

    final isEs = lang == 'es';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shot Stance Sprawl'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. SCROLLABLE CALLOUT LIST (Top Section)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Video Preview (Only if enabled)
                  if (config.videoEnabled) ...[
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: engine.cameraInitialized && 
                             ref.read(drillEngineProvider.notifier).cameraController != null
                          ? Stack(
                              children: [
                                CameraPreview(ref.read(drillEngineProvider.notifier).cameraController!),
                                Positioned(
                                  bottom: 10,
                                  right: 10,
                                  child: Opacity(
                                    opacity: 0.7,
                                    child: Image.asset('assets/images/keepkidswrestling_logo.png', width: 60), 
                                  ),
                                ),
                              ],
                            )
                          : const Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                    const SizedBox(height: 20),
                  ],

                  Text(
                    isEs ? 'Comandos' : 'Callouts',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  
                  calloutsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (list) => GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.4,
                      ),
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final c = list[index];
                        return _CalloutTile(
                          callout: c,
                          enabled: config.enabledCalloutIds.contains(c.id),
                          onChanged: (v) => notifier.toggleCallout(c.id, enabled: v),
                          onRecordTapped: () => _showRecordingSheet(context, ref, c.id, isEs ? c.nameEs : c.nameEn),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // 2. CONTROLS CONTAINER (Bottom Fixed Section)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A. RED RECORD BUTTON
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isEs ? 'GRABAR' : 'RECORD', 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          notifier.toggleVideo();
                          // Show toast if turning ON and NOT Pro
                          if (!config.videoEnabled && !isPro) {
                            _showFadingToast(
                              context, 
                              isEs ? 'Usuarios gratis limitados a 60s' : 'Free users limited to 60s'
                            );
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: config.videoEnabled ? Colors.red : Colors.grey[300],
                            boxShadow: config.videoEnabled 
                                ? [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)] 
                                : [],
                          ),
                          child: Icon(
                            config.videoEnabled ? Icons.videocam : Icons.videocam_off,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // B. TIME SLIDER (1 - 15 mins)
                  Row(
                    children: [
                      const Icon(Icons.timer, size: 20, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        isEs ? 'Duración:' : 'Duration:', 
                        style: const TextStyle(fontWeight: FontWeight.bold)
                      ),
                      const Spacer(),
                      Text(
                        '${(config.totalDurationSeconds / 60).round()} min',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  Slider(
                    value: (config.totalDurationSeconds / 60).toDouble(),
                    min: 1,
                    max: 15,
                    divisions: 14,
                    label: '${(config.totalDurationSeconds / 60).round()} min',
                    onChanged: (val) {
                      notifier.setTotalDurationSeconds((val * 60).round());
                    },
                  ),

                  // C. DIFFICULTY SLIDER
                  Row(
                    children: [
                      const Icon(Icons.speed, size: 20, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        isEs ? 'Dificultad:' : 'Difficulty:', 
                        style: const TextStyle(fontWeight: FontWeight.bold)
                      ),
                      const Spacer(),
                      Text(
                        _difficultyLevels[_difficultyValue.round()].$1,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
                      ),
                    ],
                  ),
                  Slider(
                    value: _difficultyValue,
                    min: 0,
                    max: 3,
                    divisions: 3,
                    onChanged: _updateDifficulty,
                  ),

                  const SizedBox(height: 16),

                  // D. START BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: () {
                        final engineNotifier = ref.read(drillEngineProvider.notifier);
                        final isProVal = ref.read(isProProvider); 
                        
                        if (engine.running) {
                          engineNotifier.stop(); 
                        } else {
                          calloutsAsync.whenData((allCallouts) {
                            engineNotifier.start(
                              config: config,
                              allCallouts: allCallouts,
                              isPro: isProVal, 
                            );
                            
                            // Navigate to Drill Runner
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const DrillRunnerScreen()),
                            );
                          });
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: engine.running ? Colors.red : Colors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: Icon(engine.running ? Icons.stop : Icons.play_arrow, size: 32),
                      label: Text(
                        engine.running ? (isEs ? 'DETENER' : 'STOP') : (isEs ? 'INICIAR DRILL' : 'START DRILL'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FadeToast extends StatefulWidget {
  final String message;
  const _FadeToast({required this.message});

  @override
  State<_FadeToast> createState() => _FadeToastState();
}

class _FadeToastState extends State<_FadeToast> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    
    _controller.forward();
    
    // Fade out after 2.5 seconds
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          widget.message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _CalloutTile extends ConsumerWidget {
  final Callout callout; 
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRecordTapped;

  const _CalloutTile({
    required this.callout,
    required this.enabled,
    required this.onChanged,
    required this.onRecordTapped,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasRecording = ref.watch(drillConfigProvider).customAudioPaths.containsKey(callout.id);
    final isPro = ref.watch(isProProvider);
    final lang = ref.watch(languageProvider);
    final displayName = lang == 'es' ? callout.nameEs : callout.nameEn;

    return Card(
      elevation: enabled ? 2 : 0,
      color: enabled ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4) : null,
      child: InkWell(
        onTap: () => onChanged(!enabled),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Transform.scale(
                    scale: 0.8, 
                    child: Switch(value: enabled, onChanged: onChanged)
                  ),
                  // FEATURE GATED BUTTON
                  // Only show mic button for "Standard" callouts to override them
                  // Custom callouts are managed in settings, so we can hide mic here or keep it for re-recording
                  if (!callout.isCustom)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isPro ? (hasRecording ? Icons.mic : Icons.mic_none) : Icons.lock,
                        color: isPro ? (hasRecording ? Colors.blue : Colors.grey) : Colors.red.withOpacity(0.5),
                        size: 20,
                      ),
                      onPressed: () {
                        if (isPro) {
                          onRecordTapped();
                        } else {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(lang == 'es' ? '¡Hazte Pro para grabar!' : 'Upgrade to Pro to record custom cues!'),
                              action: SnackBarAction(
                                label: 'UPGRADE',
                                onPressed: () {
                                  ref.read(isProProvider.notifier).setStatus(true); // Shortcut to upgrade
                                },
                              ),
                            ),
                          );
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordingSheetContent extends ConsumerStatefulWidget {
  final String calloutId;
  final String calloutName;
  const _RecordingSheetContent({required this.calloutId, required this.calloutName});

  @override
  ConsumerState<_RecordingSheetContent> createState() => _RecordingSheetContentState();
}

class _RecordingSheetContentState extends ConsumerState<_RecordingSheetContent> {
  final recorder = AudioRecorder();
  final audioPlayer = AudioPlayer();
  bool isRecording = false;
  String? recordedPath; 

  @override
  void dispose() {
    recorder.dispose();
    audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (await recorder.hasPermission()) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${widget.calloutId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      const config = RecordConfig(encoder: AudioEncoder.aacLc);
      await recorder.start(config, path: path);
      
      setState(() => isRecording = true);
    }
  }

  Future<void> _stopRecording() async {
    final path = await recorder.stop();
    setState(() {
      isRecording = false;
      recordedPath = path;
    });
    
    if (path != null) {
      ref.read(drillConfigProvider.notifier).updateCalloutAudio(widget.calloutId, path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(drillConfigProvider);
    final activePath = recordedPath ?? config.customAudioPaths[widget.calloutId];
    final lang = ref.watch(languageProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Text(
            isRecording 
              ? (lang == 'es' ? 'Grabando...' : 'Recording...') 
              : (lang == 'es' ? 'Voz: ${widget.calloutName}' : 'Voice: ${widget.calloutName}'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  GestureDetector(
                    onTap: isRecording ? _stopRecording : _startRecording,
                    child: CircleAvatar(
                      radius: 36,
                      backgroundColor: isRecording ? Colors.red : Colors.redAccent,
                      child: Icon(isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(isRecording ? "STOP" : "REC"),
                ],
              ),

              if (activePath != null && !isRecording)
                Column(
                  children: [
                    GestureDetector(
                      onTap: () => audioPlayer.play(DeviceFileSource(activePath)),
                      child: const CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.blueAccent,
                        child: Icon(Icons.play_arrow, color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text("PLAY"),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => Navigator.pop(context), 
            child: Text(lang == 'es' ? 'Listo' : 'Done'),
          ),
        ],
      ),
    );
  }
}
import 'package:shot_stance_sprawl/drill_runner.dart'; // Ensure correct import for navigation
