//home_screen
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
import 'package:shot_stance_sprawl/drill_runner.dart'; 
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
    final overrideMap = ref.watch(drillConfigProvider).calloutOverrideDurations;
    // Get current duration selection or default
    final currentDuration = overrideMap[callout.id] ?? callout.defaultDurationSeconds;
    
    final isPro = ref.watch(isProProvider);
    final lang = ref.watch(languageProvider);
    final displayName = lang == 'es' ? callout.nameEs : callout.nameEn;

    return Card(
      elevation: enabled ? 3 : 1,
      color: enabled 
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3) 
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: enabled ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => onChanged(!enabled),
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // 1. CENTER CONTENT (Name & On/Off status)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: enabled ? Theme.of(context).colorScheme.onSurface : Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (enabled)
                    Text("ON", style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900)),
                ],
              ),
            ),

            // 2. TOP RIGHT: Lock / Mic
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () {
                  if (isPro) {
                    onRecordTapped();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Upgrade to Pro to customize audio!'),
                        action: SnackBarAction(label: 'UPGRADE', onPressed: () => ref.read(isProProvider.notifier).setStatus(true)),
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).canvasColor.withOpacity(0.5),
                  ),
                  child: Icon(
                    !isPro && !callout.isCustom ? Icons.lock : (hasRecording ? Icons.mic : Icons.mic_none),
                    size: 16,
                    color: !isPro ? Colors.orange : (hasRecording ? Colors.blue : Colors.grey),
                  ),
                ),
              ),
            ),

            // 3. BOTTOM RIGHT: Duration Selector (Only for 'Duration' types)
            if (callout.type == 'Duration')
              Positioned(
                bottom: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () {
                    if (!enabled) return; // Only change time if active
                    _showDurationPicker(context, ref, callout.id, currentDuration);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: enabled ? Theme.of(context).colorScheme.primary : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${currentDuration}s",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: enabled ? Colors.white : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDurationPicker(BuildContext context, WidgetRef ref, String id, int current) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 200,
          child: Column(
            children: [
              const Text("Select Duration", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [5, 15, 30, 60].map((val) {
                  final isSelected = val == current;
                  return ChoiceChip(
                    label: Text("${val}s"),
                    selected: isSelected,
                    onSelected: (_) {
                      ref.read(drillConfigProvider.notifier).setCalloutDuration(id, val);
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
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

