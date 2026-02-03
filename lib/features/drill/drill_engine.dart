import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart'; 
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

// FFmpeg imports for Watermarking
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

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
  
  // New fields for Freemium Logic & Video Handoff
  final bool isPro;
  final String? videoPath;

  // Getters for UI convenience
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
    this.isPro = false,
    this.videoPath,
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
    bool? isPro,
    String? videoPath,
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
      isPro: isPro ?? this.isPro,
      videoPath: videoPath ?? this.videoPath,
    );
  }

  static DrillState idle(Duration total) =>
      DrillState(running: false, paused: false, elapsed: Duration.zero, total: total);
}

class DrillEngineNotifier extends Notifier<DrillState> {
  // --- STATIC GLOBALS ---
  static int _globalSessionId = 0;
  static IAudioPlayer? _activeCalloutPlayer;
  static bool _isGlobalFinishing = false;

  // --- Instance timing & resources ---
  static const Duration _firstCalloutDelay = Duration(milliseconds: 1500);
  static CameraController? _cameraController;
  final AudioPlayer _audioPlayer = AudioPlayer(); // Custom recording player
  
  // Lock to prevent double-stopping video
  bool _isStoppingVideo = false;
  
  // NEW: Add a flag to prevent re-entry into start()
  bool _isStarting = false;

  // Public getter for UI to show CameraPreview
  CameraController? get cameraController => _cameraController;
  
  final _stopwatch = Stopwatch();
  Timer? _ticker, _nextTimer, _holdTimer;

  final Map<String, String> _assetForId = {};
  String? _lastCalloutId;
  bool _initialized = false;
  bool _finishing = false;

  // Helper to extract logo from assets for FFmpeg
  Future<String> _getLogoFilePath() async {
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

  // NEW: Call this when user toggles video ON in Home Screen
  Future<void> preloadCamera() async {
    print('[drill] Pre-warming camera...');
    // Pass null session to indicate manual pre-warm (ignores session checks)
    await _initializeCamera(session: null); 
  }

  // NEW: Call this when user toggles video OFF
  Future<void> disposeCamera() async {
    print('[drill] Disposing camera...');
    if (_cameraController != null) {
      await _cameraController!.dispose();
      _cameraController = null;
    }
    state = state.copyWith(cameraInitialized: false);
  }

  Future<void> start({
    required DrillConfig config,
    required List<Callout> allCallouts,
    required bool isPro, 
    bool configureAudioSession = true,
    bool playStartWhistle = true,
  }) async {
    // NEW: Prevent re-entry loop (Debounce)
    if (_isStarting) return;
    _isStarting = true;

    try {
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
      _isStoppingVideo = false;
      _assetForId.clear();
      
      // CHECK FOR PRE-WARMED CAMERA
      final bool alreadyReady = _cameraController != null && _cameraController!.value.isInitialized;

      // Store isPro status immediately AND RESET CAMERA STATE (Respecting pre-warm)
      state = state.copyWith(
        running: true,
        paused: false,
        finished: false,
        elapsed: Duration.zero,
        total: Duration(seconds: config.totalDurationSeconds),
        isPro: isPro,
        videoPath: null,
        cameraInitialized: alreadyReady, // Keep true if pre-warmed
        isRecording: false,       // Explicit reset
      );
      
      if (config.videoEnabled) {
        // Only initialize if NOT already ready
        if (!alreadyReady) {
          try {
            await _initializeCamera(session: thisSession);
          } catch (e) {
            print('[drill] Camera init failed inside start (likely hardware issue): $e');
            // Important: Don't return/abort. Just continue without camera.
          }
        }
        
        // If stopped during init, abort
        if (thisSession != _globalSessionId || state.finished) return;
      }

      final selected = allCallouts
          .where((c) => config.enabledCalloutIds.contains(c.id))
          .toList();


      if (thisSession != _globalSessionId || state.finished) return;

      // 5. PRELOAD & WHISTLE
      await _preloadAudio(selected);
      if (thisSession != _globalSessionId || state.finished) return;

      if (playStartWhistle) {
        await _playFirstAvailableOnCallout([
          'assets/audio/callouts/whistle_start.wav',
          'assets/audio/callouts/whistle_start.mp3',
        ], thisSession);
        
        await Future.delayed(const Duration(milliseconds: 1600));
      }
    
      // 6. FINAL CHECKPOINT
      if (thisSession != _globalSessionId || state.finished) return;

      // Only record if camera ACTUALLY initialized (it might have failed silently above)
      if (config.videoEnabled && state.cameraInitialized) {
        await _startRecording();
      }

      _stopwatch..reset()..start();

      // 7. TICKER START (With Limits)
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (thisSession != _globalSessionId || _finishing) {
          timer.cancel();
          return;
        }

        final elapsed = _stopwatch.elapsed;

        // VIDEO CUTOFF LOGIC: Enforce 60s for Free, 10m for Pro
        final int videoLimitSeconds = state.isPro ? 600 : 60;

        if (config.videoEnabled && state.isRecording) {
          if (elapsed.inSeconds >= videoLimitSeconds) {
            // Stop recording safely
            _stopAndSaveVideo();
          }
        }

        if (elapsed >= state.total) {
          timer.cancel();
          // Force finish logic
          _finish(playEndWhistle: true, session: thisSession);
          return;
        }
        state = state.copyWith(running: true, elapsed: elapsed);
      });

      // 8. SCHEDULE FIRST CALLOUT
      _nextTimer = Timer(_firstCalloutDelay, () {
        if (thisSession == _globalSessionId && !state.finished) {
          _fire(selected, config, thisSession);
        }
      });
    } catch (e) {
      // NEW: Catch-all for start errors to prevent the "reset loop"
      print('[drill] CRITICAL START ERROR: $e');
    } finally {
      // NEW: Always reset the starting flag
      _isStarting = false;
    }
  }

  void pause() {
    if (!_initialized && !state.running) return; 
    if (state.finished || state.paused) return;
    _cancelTimers(keepTicker: true);
    _stopwatch.stop();
    state = state.copyWith(paused: true);
  }

  void resume({required DrillConfig config, required List<Callout> allCallouts}) {
    if (state.finished || !state.paused) return;
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
  // ENGINE LOGIC
  // ===========================================================================

 Future<void> _fire(List<Callout> selected, DrillConfig cfg, int session) async {
    // CRITICAL: If finished, stop immediately
    if (session != _globalSessionId || state.finished || selected.isEmpty) return;

    final next = _pickRandomCallout(selected);
    _lastCalloutId = next.id;

    unawaited(HapticFeedback.lightImpact());
    
    // 1. Play Audio
    await _playCallout(next, session, cfg);

    if (session != _globalSessionId) return;
    final newCount = state.calloutsCompleted + 1;

    // 2. Determine Duration
    final overrideDuration = cfg.calloutOverrideDurations[next.id];
    final effectiveDuration = overrideDuration ?? next.defaultDurationSeconds;

    final delay = _intervals.next(cfg.minIntervalSeconds, cfg.maxIntervalSeconds);
    
    if (next.type == 'Duration' && effectiveDuration > 0) {
      final hold = Duration(seconds: effectiveDuration);
      
      state = state.copyWith(
        lastCallout: next, 
        holdRemaining: hold, 
        calloutsCompleted: newCount, 
      );

      _holdTimer?.cancel();
      _holdTimer = Timer(hold, () {
        if (session == _globalSessionId && !state.finished) {
          state = state.copyWith(holdRemaining: null);
          _scheduleNext(delay, cfg, selected, session);
        }
      });
    } else {
      state = state.copyWith(
        lastCallout: next, 
        holdRemaining: null,
        calloutsCompleted: newCount,
      );
      _scheduleNext(delay, cfg, selected, session);
    }
  }

  void _scheduleNext(double delaySeconds, DrillConfig cfg, List<Callout> selected, int session) {
    _nextTimer?.cancel();
    _nextTimer = Timer(
      Duration(milliseconds: (delaySeconds * 1000).round()),
      () {
        if (session == _globalSessionId && !state.finished) {
          _fire(selected, cfg, session);
        }
      },
    );
  }

  Future<void> _finish({bool playEndWhistle = true, int? session}) async {
    if (session != null && session != _globalSessionId) return;
    if (_isGlobalFinishing || state.finished) return;
    
    _isGlobalFinishing = true; 
    print('[drill] >>> LOCK ACQUIRED: Finishing Session ${_globalSessionId} <<<');

    try {
      // 1. CANCEL TIMERS FIRST to stop audio loop
      _cancelTimers();
      _stopwatch.stop();

      // 2. STOP RECORDING (if active)
      if (state.isRecording) {
        // NEW: Add timeout to prevent hang if camera API is unresponsive
        try {
          await _stopAndSaveVideo().timeout(const Duration(seconds: 5));
        } catch (e) {
           print('[drill] Video stop timed out or failed in finish: $e');
        }
      }
      
      // 3. UI CLEANUP
      state = state.copyWith(
        cameraInitialized: false, 
        running: false,
        paused: false,
        isRecording: false,
      );
      
      // Short delay to let UI detach camera
      await Future.delayed(const Duration(milliseconds: 100));

      // 4. DISPOSE CAMERA SAFELY (With Timeout)
      final controller = _cameraController;
      _cameraController = null;
      if (controller != null) {
        try {
          await controller.dispose().timeout(const Duration(seconds: 2), onTimeout: () {
            print('[camera] Dispose timed out - forcing continue');
          });
        } catch (e) {
          print('[camera] Dispose error (ignored): $e');
        }
      }

      // 5. MARK AS FINISHED
      state = state.copyWith(
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
      }
    } catch (e) {
      print("[drill] Critical error in _finish: $e");
      // Even if error, force finished state so UI doesn't hang
      state = state.copyWith(finished: true);
    } finally {
      await _disposeInternal();
      _isGlobalFinishing = false;
      print('[drill] >>> LOCK RELEASED <<<');
    }
  }

// ===========================================================================
  // CAMERA & NOTIFICATION HELPERS
  // ===========================================================================

  // UPDATED: Session is now named and optional
  Future<void> _initializeCamera({int? session}) async {
    // 0. CHECK IF ALREADY INITIALIZED (Skip if pre-warmed)
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      state = state.copyWith(cameraInitialized: true);
      return; 
    }

    // 1. CLEANUP PREVIOUS IF ANY (Only if broken)
    if (_cameraController != null) {
      try {
        await _cameraController!.dispose();
        // NEW: Give OS time to release hardware resource
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        print('[camera] Warning: cleanup of old controller failed: $e');
      }
      _cameraController = null;
    }

    // 2. PERMISSIONS
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.videos, 
      Permission.photos,
      Permission.storage, 
    ].request();

    if (statuses[Permission.camera] != PermissionStatus.granted) {
      print('[camera] Camera permission denied');
      state = state.copyWith(cameraInitialized: false);
      return;
    }

    // Abort if session changed (only if running within a specific session)
    if (session != null && session != _globalSessionId) return;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        print('[camera] No cameras found. Initialization aborted.');
        state = state.copyWith(cameraInitialized: false);
        return;
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front, 
        ResolutionPreset.medium, 
        enableAudio: true,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
      );

      _cameraController = controller;
      await controller.initialize();

      // NEW: Critical check - if user stopped drill during init, do NOT update state
      // Only check session validity if we were actually given a session
      if ((session != null && session != _globalSessionId) || state.finished) {
        await controller.dispose();
        _cameraController = null;
        return;
      }

      state = state.copyWith(cameraInitialized: true);
      print('[camera] Camera initialized successfully');

    } catch (e) {
      // Caught exception: ensure state is false so we don't try to use it
      print('[camera] Init error caught: $e');
      state = state.copyWith(cameraInitialized: false);
      
      // Cleanup partially initialized controller if any
      if (_cameraController != null) {
        try { await _cameraController!.dispose(); } catch (_) {}
        _cameraController = null;
      }
    }
  }

  Future<void> _startRecording() async {
    final controller = _cameraController;
    if (controller != null && controller.value.isInitialized) {
      try {
        await controller.startVideoRecording();
        state = state.copyWith(isRecording: true);
        print('[camera] Recording started');
      } catch (e) {
        print('[camera] Start recording error: $e');
        state = state.copyWith(isRecording: false);
      }
    }
  }

  Future<void> _stopAndSaveVideo() async {
    // Lock to prevent double execution from timer + finish logic
    if (_isStoppingVideo) return;
    
    final controller = _cameraController;
    if (controller == null) return;

    // NEW: Check if actually recording before trying to stop
    // This prevents crashes if camera init failed but stop was called
    if (!controller.value.isRecordingVideo) {
       print('[drill] Skipping stopVideoRecording - camera was not recording.');
       state = state.copyWith(isRecording: false);
       return;
    }

    _isStoppingVideo = true;
    try {
      final XFile rawVideo = await controller.stopVideoRecording();
      print('[DrillEngine] Video saved to: ${rawVideo.path}');
      
      state = state.copyWith(
        isRecording: false,
        videoPath: rawVideo.path, 
      );
    } catch (e) {
      print('[drill] Error stopping video: $e');
      state = state.copyWith(isRecording: false);
    } finally {
      _isStoppingVideo = false;
    }
  }

  // ===========================================================================
  // AUDIO HELPERS
  // ===========================================================================

  Future<void> _playCallout(Callout c, int session, DrillConfig config) async {
    if (session != _globalSessionId) return;

    // 1. Custom Voice
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

    // 2. Asset
   final p = _activeCalloutPlayer;
    if (p == null) return;
    try {
      final targetId = c.audioAssetAlias ?? c.id;
      String? asset = _assetForId[targetId];
      
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
        // continue
      }
    }
    return false;
  }

  Future<void> _preloadAudio(List<Callout> selected) async {
    Future<bool> _exists(String path) async {
      try { await rootBundle.load(path); return true; } catch (_) { return false; }
    }

   for (final c in selected) {
      final targetId = c.audioAssetAlias ?? c.id;
      final base = 'assets/audio/callouts/$targetId';
      String? found;
      for (final path in <String>['$base.wav', '$base.mp3', '$base.m4a']) {
        if (await _exists(path)) { found = path; break; }
      }
      if (found != null) _assetForId[targetId] = found;
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
  static const _keyConfig = 'drill_config_v1';

  @override
  DrillConfig build() {
    _load();
    return const DrillConfig(
      totalDurationSeconds: 60,
      minIntervalSeconds: 2.0,
      maxIntervalSeconds: 4.0,
      enabledCalloutIds: {'shot', 'stance', 'sprawl'},
      videoEnabled: false,
    );
  }

  Future<void> _load() async {
    try {
      final prefs = await ref.read(sharedPrefsProvider.future);
      final jsonString = prefs.getString(_keyConfig);
      
      if (jsonString != null) {
        final loaded = DrillConfig.fromJson(jsonString);
        // Force video to OFF when the app loads
        state = loaded.copyWith(videoEnabled: false);
      }
    } catch (e) {
      print("Error loading drill config: $e");
    }
  }

  Future<void> _save() async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setString(_keyConfig, state.toJson());
  }

  // Sets the duration for a specific callout (5, 15, 30, 60)
  void setCalloutDuration(String id, int duration) {
    final map = Map<String, int>.from(state.calloutOverrideDurations);
    map[id] = duration;
    state = state.copyWith(calloutOverrideDurations: map);
    _save();
  }

  void toggleCallout(String id, {required bool enabled}) {
    final ids = Set<String>.from(state.enabledCalloutIds);
    if (enabled) ids.add(id); else ids.remove(id);
    state = state.copyWith(enabledCalloutIds: ids);
    _save();
  }

  void setIntervalRange({required double minSeconds, required double maxSeconds}) {
    state = state.copyWith(minIntervalSeconds: minSeconds, maxIntervalSeconds: maxSeconds);
    _save();
  }

  void setTotalDurationSeconds(int seconds) {
    state = state.copyWith(totalDurationSeconds: seconds);
    _save();
  }

  void toggleVideo() {
    state = state.copyWith(videoEnabled: !state.videoEnabled);
    _save();
  }

  void updateCalloutAudio(String id, String path) {
    final paths = Map<String, String>.from(state.customAudioPaths);
    paths[id] = path;
    state = state.copyWith(customAudioPaths: paths);
    _save();
  }
}
