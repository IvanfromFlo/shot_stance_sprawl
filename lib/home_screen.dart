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

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // Helper to determine difficulty text
  String _currentDifficulty(DrillConfig config) {
    final difficulty = {
      'Easy (3–5s)': (3.0, 5.0),
      'Medium (2–4s)': (2.0, 4.0),
      'Hard (1–2s)': (1.0, 2.0),
    };

    for (final e in difficulty.entries) {
      final (minS, maxS) = e.value;
      if ((config.minIntervalSeconds - minS).abs() < 0.05 &&
          (config.maxIntervalSeconds - maxS).abs() < 0.05) {
        return e.key;
      }
    }
    return 'Medium (2–4s)';
  }

  void _showSettings(BuildContext context, WidgetRef ref) {
    final config = ref.watch(drillConfigProvider);
    final notifier = ref.read(drillConfigProvider.notifier);
    final isPro = ref.watch(isProProvider);

    // Map display labels to actual values
    final difficulties = {
      'Easy (3–5s)': (3.0, 5.0),
      'Medium (2–4s)': (2.0, 4.0),
      'Hard (1–2s)': (1.0, 2.0),
      'Dan Gable (0.5–1.5s)': (0.5, 1.5),
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            
            // 1. Video Toggle
            SwitchListTile(
              title: const Text('Video Recording'),
              subtitle: const Text('Saves to gallery'),
              value: config.videoEnabled,
              onChanged: (val) {
                notifier.toggleVideo();
              },
            ),

            // 2. Difficulty Picker
            ListTile(
              title: const Text('Difficulty'),
              subtitle: Text(_currentDifficulty(config)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context); 
                showModalBottomSheet(
                  context: context,
                  builder: (ctx) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: difficulties.entries.map((e) {
                      return ListTile(
                        title: Text(e.key),
                        onTap: () {
                          notifier.setIntervalRange(
                            minSeconds: e.value.$1, 
                            maxSeconds: e.value.$2
                          );
                          Navigator.pop(ctx);
                          _showSettings(context, ref); 
                        },
                        trailing: (config.minIntervalSeconds == e.value.$1) 
                            ? const Icon(Icons.check, color: Colors.blue) 
                            : null,
                      );
                    }).toList(),
                  ),
                );
              },
            ),
            
            const Divider(),
            
            // 3. MASTER TOGGLE (For Development/Testing)
            SwitchListTile(
              title: const Text('Simulate Pro Mode'),
              subtitle: const Text('Dev Only: Unlock all features'),
              secondary: Icon(Icons.stars, color: isPro ? Colors.amber : Colors.grey),
              value: isPro,
              onChanged: (val) {
                // Use the new toggle method from the Notifier
                ref.read(isProProvider.notifier).setStatus(val);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showRecordingSheet(BuildContext context, WidgetRef ref, String id, String name) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RecordingSheetContent(calloutId: id, calloutName: name),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(drillConfigProvider);
    final engine = ref.watch(drillEngineProvider);
    final calloutsAsync = ref.watch(calloutsProvider);
    final lang = ref.watch(languageProvider);
    final notifier = ref.read(drillConfigProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shot Stance Sprawl'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettings(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // VIDEO WATERMARK PREVIEW AREA
            if (config.videoEnabled) ...[
              Container(
                height: 250,
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
                          // Watermark Overlay in Preview
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
              lang == 'es' ? 'Comandos' : 'Callouts',
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
                    onRecordTapped: () => _showRecordingSheet(context, ref, c.id, lang == 'es' ? c.nameEs : c.nameEn),
                  );
                },
              ),
            ),
            const SizedBox(height: 100), // Space for start button
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final engineNotifier = ref.read(drillEngineProvider.notifier);
          final isPro = ref.watch(isProProvider); // Read toggle
          
          if (engine.running) {
            engineNotifier.stop(); 
          } else {
            calloutsAsync.whenData((allCallouts) {
              engineNotifier.start(
                config: config,
                allCallouts: allCallouts,
                isPro: isPro, // Pass it here
              );
            });
          }
        },
        label: Text(engine.running ? 'STOP' : 'START DRILL'),
        icon: Icon(engine.running ? Icons.stop : Icons.play_arrow),
        backgroundColor: engine.running ? Colors.red : null,
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
                        // Upsell logic for non-pro users
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Upgrade to Pro to record custom cues!'),
                            action: SnackBarAction(
                              label: 'UPGRADE',
                              onPressed: () {
                                // In a real app, navigate to paywall here
                                debugPrint("Navigate to paywall");
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
  String? recordedPath; // Local state to hold the new file path

  @override
  void dispose() {
    recorder.dispose();
    audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (await recorder.hasPermission()) {
      final dir = await getApplicationDocumentsDirectory();
      // Use timestamp to avoid caching issues
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
    
    // Save to global config
    if (path != null) {
      ref.read(drillConfigProvider.notifier).updateCalloutAudio(widget.calloutId, path);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if we have a path from config (previous) or local (just recorded)
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
              // RECORD BUTTON
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

              // PLAY BUTTON (Only if file exists and not recording)
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
