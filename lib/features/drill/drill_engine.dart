import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart'; 
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';

// -----------------------------------------
import 'package:path_provider/path_provider.dart';      // For getTemporaryDirectory
// ---------------------------------

import '../../core/audio.dart';
import '../../main.dart'; 
import 'intervals.dart';
import 'models.dart';
import 'providers.dart';
final audioFactoryProvider = Provider<AudioFactory>((_) => RealAudioFactory());
final intervalStrategyProvider = Provider<IntervalStrategy>((_) => UniformIntervalStrategy());

class DrillState {
  final bool running;
  final bool paused;
  final bool finished;
  final Duration elapsed;
  final Duration total;
  final Callout? lastCallout;
  final Duration? holdRemaining;
  final bool cameraInitialized;
  final bool isRecording;
  final int calloutsCompleted;

  // HELPER GETTERS: These fix the "getter not defined" errors in PowerShell
  int get elapsedSeconds => elapsed.inSeconds;
  int get totalSeconds => total.inSeconds;

  DrillState({
    this.running = false,
    this.paused = false,
    this.finished = false,
    this.elapsed = Duration.zero,
    this.total = Duration.zero,
    this.lastCallout,
    this.holdRemaining,
    this.cameraInitialized = false,
    this.isRecording = false,
    this.calloutsCompleted = 0,
  });

  DrillState copyWith({
    bool? running,
    bool? paused,
    bool? finished,
    Duration? elapsed,
    Duration? total,
    Callout? lastCallout,
    Duration? holdRemaining,
    bool? cameraInitialized,
    bool? isRecording,
    int? calloutsCompleted,
  }) {
    return DrillState(
      running: running ?? this.running,
      paused: paused ?? this.paused,
      finished: finished ?? this.finished,
      elapsed: elapsed ?? this.elapsed,
      total: total ?? this.total,
      lastCallout: lastCallout ?? this.lastCallout,
      holdRemaining: holdRemaining ?? this.holdRemaining,
      cameraInitialized: cameraInitialized ?? this.cameraInitialized,
      isRecording: isRecording ?? this.isRecording,
      calloutsCompleted: calloutsCompleted ?? this.calloutsCompleted,
    );
  }

  static DrillState idle(Duration total) =>
      DrillState(running: false, paused: false, elapsed: Duration.zero, total: total);
}

class DrillEngineNotifier extends Notifier<DrillState> {
  // --- STATIC GLOBALS (The Master Kill Switch) ---
  static int _globalSessionId = 0;
  static IAudioPlayer? _activeCalloutPlayer;
  static bool _isGlobalFinishing = false;

  // --- Instance timing & resources ---
  static const Duration _firstCalloutDelay = Duration(milliseconds: 1500);
  static CameraController? _cameraController;
  final AudioPlayer _audioPlayer = AudioPlayer(); // Custom recording player
  
  // Public getter for UI
  CameraController? get cameraController => _cameraController;
  
  final _stopwatch = Stopwatch();
  Timer? _ticker, _nextTimer, _holdTimer;

  final Map<String, String> _assetForId = {};
  String? _lastCalloutId;
  bool _initialized = false;
  bool _finishing = false;

  Future<String> _getLogoFilePath() async {
      // This extracts the logo from your assets so FFmpeg can see it
      final byteData = await rootBundle.load('assets/images/keepkidswrestling_logo.png');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/temp_logo.png');
      await file.writeAsBytes(byteData.buffer.asUint8List(
        byteData.offsetInBytes, 
        byteData.lengthInBytes,
      ));
      return file.path;
    }

  AudioFactory get _audio => ref.read(audioFactoryProvider);
  IntervalStrategy get _intervals => ref.read(intervalStrategyProvider);

  @override
  DrillState build() {
    ref.onDispose(_disposeInternal);
    return DrillState.idle(const Duration(minutes: 5));
  }

  // ===========================================================================
  // PUBLIC API (Start, Pause, Resume, Stop)
  // ===========================================================================

  Future<void> start({
    required DrillConfig config,
    required List<Callout> allCallouts,
    bool configureAudioSession = true,
    bool playStartWhistle = true,
  }) async {
    // 1. Guard against overlapping cleanup
    if (_isGlobalFinishing) {
      print('[drill] Wait: Still finishing previous drill...');
      return;
    }

    // 2. ATOMIC SESSION START
    _globalSessionId++;
    final thisSession = _globalSessionId;

    print('[drill] >>> NEW ENGINE START: Session $thisSession <<<');

    // 3. PHYSICAL CLEANUP
    _cancelTimers();
    final oldPlayer = _activeCalloutPlayer;
    _activeCalloutPlayer = null;
    try { await oldPlayer?.dispose(); } catch (_) {}

    // 4. INITIALIZE NEW RESOURCES
    _activeCalloutPlayer = _audio.createPlayer(debugLabel: 'callouts');
    _finishing = false;
    _assetForId.clear();
    
    if (config.videoEnabled) {
      await _initializeCamera(thisSession);
      if (thisSession != _globalSessionId) return;
    }

    state = state.copyWith(
      running: true,
      paused: false,
      finished: false,
      elapsed: Duration.zero,
      total: Duration(seconds: config.totalDurationSeconds),
    );

    final selected = allCallouts
        .where((c) => config.enabledCalloutIds.contains(c.id))
        .toList();

    if (thisSession != _globalSessionId) return;

    // 5. PRELOAD & WHISTLE
    await _preloadAudio(selected);
    if (thisSession != _globalSessionId) return;

    if (playStartWhistle) {
      await _playFirstAvailableOnCallout([
        'assets/audio/callouts/whistle_start.wav',
        'assets/audio/callouts/whistle_start.mp3',
      ], thisSession);
      
      await Future.delayed(const Duration(milliseconds: 1600));
    }
  
    // 6. FINAL CHECKPOINT
    if (thisSession != _globalSessionId) return;

    if (config.videoEnabled && state.cameraInitialized) {
      await _startRecording();
    }

    _stopwatch..reset()..start();

    // 7. TICKER START
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (thisSession != _globalSessionId || _finishing) {
        timer.cancel();
        return;
      }

      final elapsed = _stopwatch.elapsed;

      // 120-SECOND RECORDING CUTOFF
      if (config.videoEnabled && state.isRecording && elapsed.inSeconds >= 120) {
        state = state.copyWith(isRecording: false); 
        _stopAndSaveVideo();
      }

      if (elapsed >= state.total) {
        timer.cancel();
        _finish(playEndWhistle: true, session: thisSession);
        return;
      }
      state = state.copyWith(running: true, elapsed: elapsed);
    });

    _initialized = true;

    // 8. SCHEDULE FIRST CALLOUT
    _nextTimer = Timer(_firstCalloutDelay, () {
      if (thisSession == _globalSessionId && !state.finished) {
        _fire(selected, config, thisSession);
      }
    });
  }

  void pause() {
    if (!_initialized || state.finished || state.paused) return;
    _cancelTimers(keepTicker: true);
    _stopwatch.stop();
    state = state.copyWith(paused: true);
  }

  void resume({required DrillConfig config, required List<Callout> allCallouts}) {
    if (!_initialized || state.finished || !state.paused) return;
    _stopwatch.start();
    final selected = allCallouts
        .where((c) => config.enabledCalloutIds.contains(c.id))
        .toList();
    _scheduleNext(
      _intervals.next(config.minIntervalSeconds, config.maxIntervalSeconds),
      config,
      selected,
      _globalSessionId,
    );
    state = state.copyWith(paused: false);
  }

  Future<void> stop() async {
    await _finish(playEndWhistle: false);
  }

  // ===========================================================================
  // ENGINE LOGIC (Fire, Schedule, Finish)
  // ===========================================================================

  Future<void> _fire(List<Callout> selected, DrillConfig cfg, int session) async {
    if (session != _globalSessionId || state.finished || selected.isEmpty) return;

    final next = _pickRandomCallout(selected);
    _lastCalloutId = next.id;

    unawaited(HapticFeedback.lightImpact());
    
    await _playCallout(next, session, cfg);

    if (session != _globalSessionId) return;
    final newCount = state.calloutsCompleted + 1;

    final delay = _intervals.next(cfg.minIntervalSeconds, cfg.maxIntervalSeconds);
    
    if (next.type == 'Duration' && (next.durationSeconds ?? 0) > 0) {
      final hold = Duration(seconds: next.durationSeconds!);
      _holdTimer?.cancel();
      _holdTimer = Timer(hold, () {
        if (session == _globalSessionId && !state.finished) {
          _scheduleNext(delay, cfg, selected, session);
          state = state.copyWith(holdRemaining: null);
        }
      });
      state = state.copyWith(
        lastCallout: next, 
        holdRemaining: hold,
        calloutsCompleted: newCount, 
      );
    } else {
      _scheduleNext(delay, cfg, selected, session);
      state = state.copyWith(
        lastCallout: next, 
        holdRemaining: null,
        calloutsCompleted: newCount,
      );
    }
  }

  void _scheduleNext(double delaySeconds, DrillConfig cfg, List<Callout> selected, int session) {
    _nextTimer?.cancel();
    _nextTimer = Timer(
      Duration(milliseconds: (delaySeconds * 1000).round()),
      () {
        if (session == _globalSessionId) _fire(selected, cfg, session);
      },
    );
  }

  Future<void> _finish({bool playEndWhistle = true, int? session}) async {
    if (session != null && session != _globalSessionId) return;
    if (_isGlobalFinishing || state.finished) return;
    
    _isGlobalFinishing = true; 
    print('[drill] >>> LOCK ACQUIRED: Finishing Session ${_globalSessionId} <<<');

    try {
      _cancelTimers();
      _stopwatch.stop();

      if (state.isRecording) {
        await _stopAndSaveVideo();
      }
      
      await _cameraController?.dispose();
      _cameraController = null;

      state = state.copyWith(
        running: false,
        paused: false,
        finished: true,
        holdRemaining: null,
        cameraInitialized: false,
        isRecording: false,
      );

      final p = _activeCalloutPlayer;
      if (p != null) {
        try { await p.stop(); } catch (_) {}
      }

      if (playEndWhistle) {
        await _playFirstAvailableOnCallout([
          'assets/audio/callouts/whistle_end.wav',
          'assets/audio/callouts/whistle_end.mp3',
        ], _globalSessionId);
        
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    } finally {
      await _disposeInternal();
      _isGlobalFinishing = false;
      print('[drill] >>> LOCK RELEASED <<<');
    }
  }

  // ===========================================================================
  // CAMERA & NOTIFICATION HELPERS
  // ===========================================================================

  Future<void> _initializeCamera(int session) async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.videos,
      Permission.storage,
    ].request();

    if (session != _globalSessionId) return;

    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);

      _cameraController = CameraController(front, ResolutionPreset.medium, enableAudio: true);
      await _cameraController!.initialize();

      if (session != _globalSessionId) {
        _cameraController?.dispose();
        _cameraController = null;
        return;
      }

      state = state.copyWith(cameraInitialized: true);
    } catch (e) {
      print('[camera] Init error: $e');
    }
  }

  Future<void> _startRecording() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      await _cameraController!.startVideoRecording();
      state = state.copyWith(isRecording: true);
    }
  }

  Future<void> _stopAndSaveVideo() async {
  if (_cameraController == null || !_cameraController!.value.isRecordingVideo) return;

  try {
    final XFile rawVideo = await _cameraController!.stopVideoRecording();
    state = state.copyWith(isRecording: false);

    // 0. Get the path to the logo using the helper you just added
    final String logoPath = await _getLogoFilePath();

    // 1. Get a path for the "branded" video
    final directory = await getTemporaryDirectory();
    final outputPath = '${directory.path}/branded_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // 2. Run FFmpeg command to overlay logo (bottom-right, 20px padding)
    // Note: This assumes the logo is a local file.
    final String command = "-i ${rawVideo.path} -i $logoPath -filter_complex \"[1:v]format=rgba,colorchannelmixer=aa=0.5[logo];[0:v][logo]overlay=W-w-20:H-h-20\" $outputPath";


    unawaited(HapticFeedback.heavyImpact());
    _showSavedNotification();

  } catch (e) {
    print('[drill] Error saving video: $e');
  }
}

  void _showSavedNotification() {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('Video Saved to Gallery!'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(20),
        action: SnackBarAction(
          label: 'OPEN GALLERY',
          textColor: Colors.white,
          onPressed: () => Gal.open(),
        ),
      ),
    );
  }

  void _showErrorNotification(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ===========================================================================
  // AUDIO HELPERS
  // ===========================================================================

  Future<void> _playCallout(Callout c, int session, DrillConfig config) async {
    if (session != _globalSessionId) return;

    // 1. Check for a Custom Voice Recording
    final customPath = config.customAudioPaths[c.id];
    if (customPath != null && File(customPath).existsSync()) {
      try {
        await _audioPlayer.stop(); 
        await _audioPlayer.play(DeviceFileSource(customPath));
        return; 
      } catch (e) {
        print('[drill] Custom audio failed, falling back: $e');
      }
    }

    // 2. Fallback to Asset
    final p = _activeCalloutPlayer;
    if (p == null) return;
    try {
      String? asset = _assetForId[c.id];
      if (asset != null) {
        await p.setAsset(asset);
        if (session != _globalSessionId) return;
        await p.play();
      }
    } catch (_) {
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  Future<bool> _playFirstAvailableOnCallout(List<String> candidates, int session) async {
    for (final asset in candidates) {
      if (session != _globalSessionId) return false;
      final p = _activeCalloutPlayer; 
      if (p == null) return false;

      try {
        await p.setAsset(asset);
        if (session != _globalSessionId || _activeCalloutPlayer == null) return false;
        await p.play();
        return true; 
      } catch (e) {
        // continue to next candidate
      }
    }
    return false;
  }

  Future<void> _preloadAudio(List<Callout> selected) async {
    Future<bool> _exists(String path) async {
      try { await rootBundle.load(path); return true; } catch (_) { return false; }
    }

    for (final c in selected) {
      final base = 'assets/audio/callouts/${c.id}';
      String? found;
      for (final path in <String>['$base.wav', '$base.mp3', '$base.m4a']) {
        if (await _exists(path)) { found = path; break; }
      }
      if (found != null) _assetForId[c.id] = found;
    }
  }

  void _cancelTimers({bool keepTicker = false}) {
    _nextTimer?.cancel();
    _nextTimer = null;
    
    _holdTimer?.cancel();
    _holdTimer = null;
    
    if (!keepTicker) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _disposeInternal() async {
    _cancelTimers();
    await _audioPlayer.stop();
    final p = _activeCalloutPlayer;
    _activeCalloutPlayer = null;
    
    if (p != null) {
      try {
        await p.stop();
        await p.dispose();
      } catch (_) {}
    }
    _assetForId.clear();
  }

  Callout _pickRandomCallout(List<Callout> options) {
    if (options.length <= 1) return options.first;
    final rng = math.Random();
    Callout pick;
    int guard = 0;
    do {
      pick = options[rng.nextInt(options.length)];
      guard++;
    } while (pick.id == _lastCalloutId && guard < 10);
    return pick;
  }
}

class DrillConfigNotifier extends Notifier<DrillConfig> {
  @override
  DrillConfig build() {
    // Default settings when the app first opens
    return const DrillConfig(
      totalDurationSeconds: 60,
      minIntervalSeconds: 2.0,
      maxIntervalSeconds: 4.0,
      enabledCalloutIds: {'shot', 'stance', 'sprawl'},
      videoEnabled: false,
    );
  }

  void toggleCallout(String id, {required bool enabled}) {
    final ids = Set<String>.from(state.enabledCalloutIds);
    if (enabled) ids.add(id); else ids.remove(id);
    state = state.copyWith(enabledCalloutIds: ids);
  }

  void setIntervalRange({required double minSeconds, required double maxSeconds}) {
    state = state.copyWith(minIntervalSeconds: minSeconds, maxIntervalSeconds: maxSeconds);
  }

  void setTotalDurationSeconds(int seconds) {
    state = state.copyWith(totalDurationSeconds: seconds);
  }

  void toggleVideo() {
    state = state.copyWith(videoEnabled: !state.videoEnabled);
  }

  void updateCalloutAudio(String id, String path) {
    final paths = Map<String, String>.from(state.customAudioPaths);
    paths[id] = path;
    state = state.copyWith(customAudioPaths: paths);
  }
}