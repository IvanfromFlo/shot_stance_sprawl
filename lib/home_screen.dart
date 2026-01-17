import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
// ---------------------------------

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
    print("Settings button tapped!");
    final config = ref.read(drillConfigProvider);
    final notifier = ref.read(drillConfigProvider.notifier);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            SwitchListTile(
              title: const Text('Video Recording'),
              subtitle: const Text('Saves to gallery (Free feature)'),
              value: config.videoEnabled,
              onChanged: (val) {
                notifier.toggleVideo();
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Difficulty'),
              subtitle: Text(_currentDifficulty(config)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // Add difficulty picker logic here
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
                              child: Image.asset('assets/keepkidswrestling_logo.png', width: 60), 
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final engineNotifier = ref.read(drillEngineProvider.notifier);
          
          if (engine.running) {
            // No arguments needed for stop
            engineNotifier.stop(); 
          } else {
            // Use .whenData to ensure we have the list of moves before starting
            calloutsAsync.whenData((allCallouts) {
              engineNotifier.start(
                config: config,
                allCallouts: allCallouts,
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
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      hasRecording ? Icons.mic : (isPro ? Icons.mic_none : Icons.lock_outline),
                      color: hasRecording ? Colors.blue : Colors.grey,
                      size: 20,
                    ),
                    onPressed: isPro || hasRecording 
                      ? onRecordTapped 
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Custom recordings are a Pro feature!')),
                          );
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

  @override
  void dispose() {
    recorder.dispose();
    audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(drillConfigProvider);
    final currentPath = config.customAudioPaths[widget.calloutId];
    final lang = ref.watch(languageProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Text(
            isRecording ? (lang == 'es' ? 'Grabando...' : 'Recording...') : (lang == 'es' ? 'Voz para "${widget.calloutName}"' : 'Voice for "${widget.calloutName}"'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RecordButton(
                isRecording: isRecording,
                onPressed: () async {
                  if (isRecording) {
                    final path = await recorder.stop();
                    setState(() => isRecording = false);
                    if (path != null) ref.read(drillConfigProvider.notifier).updateCalloutAudio(widget.calloutId, path);
                  } else {
                    if (await recorder.hasPermission()) {
                      final dir = await getApplicationDocumentsDirectory();
                      final path = '${dir.path}/${widget.calloutId}.m4a';
                      await recorder.start(RecordConfig(), path: path);
                      setState(() => isRecording = true);
                    }
                  }
                },
              ),
              if (currentPath != null && !isRecording)
                IconButton.filledTonal(
                  iconSize: 48,
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () => audioPlayer.play(DeviceFileSource(currentPath)),
                ),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text("Done")),
        ],
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onPressed;
  const _RecordButton({required this.isRecording, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onPressed,
          child: CircleAvatar(
            radius: 40,
            backgroundColor: isRecording ? Colors.red : Colors.blue,
            child: Icon(isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(isRecording ? "Stop" : "Record"),
      ],
    );
  }
}

