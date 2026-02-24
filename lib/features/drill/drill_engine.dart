import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart'; 
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/audio.dart';
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
  final bool isPro;
  final String? videoPath;

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

class DrillEngineNotifier extends Notifier<DrillState> with WidgetsBindingObserver {
  static int _globalSessionId = 0;
  static bool _isGlobalFinishing = false;

  // --- AUDIO POOL OPTIMIZATION ---
  static final List<IAudioPlayer> _playerPool = [];
  static int _poolIndex = 0;

  static const Duration _firstCalloutDelay = Duration(milliseconds: 1500);
  static CameraController? _cameraController;
  
  bool _isStoppingVideo = false;
  bool _isStarting = false;

  CameraController? get cameraController => _cameraController;
  
  final _stopwatch = Stopwatch();
  Timer? _ticker, _nextTimer, _holdTimer;

  final Map<String, String> _assetForId = {};
  String? _lastCalloutId;
  bool _initialized = false;
  bool _finishing = false;

  AudioFactory get _audio => ref.read(audioFactoryProvider);
  IntervalStrategy get _intervals => ref.read(intervalStrategyProvider);

  @override
  DrillState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _disposeInternal();
    });
    return DrillState.idle(const Duration(minutes: 5));
  }

  // Handle Memory Leaks if app is backgrounded
  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState == AppLifecycleState.inactive || appState == AppLifecycleState.paused) {
      if (state.running && !state.finished) {
        stop(); // Safely shut down camera and save
      }
    }
  }

  Future<void> preloadCamera() async {
    await _initializeCamera(session: null); 
  }

  Future<void> disposeCamera() async {
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
    bool playStartWhistle = true,
  }) async {
    if (_isStarting) return;
    _isStarting = true;

    try {
      if (_isGlobalFinishing) return;

      _globalSessionId++;
      final thisSession = _globalSessionId;

      _cancelTimers();
      
      // Initialize Audio Pool - Prevents UI Lockups
      for (var p in _playerPool) { try { await p.dispose(); } catch(_) {} }
      _playerPool.clear();
      for (int i = 0; i < 3; i++) {
        _playerPool.add(_audio.createPlayer(debugLabel: 'pool_worker_$i'));
      }
      _poolIndex = 0;

      _finishing = false;
      _isStoppingVideo = false;
      _assetForId.clear();
      
      final bool alreadyReady = _cameraController != null && _cameraController!.value.isInitialized;

      state = state.copyWith(
        running: true,
        paused: false,
        finished: false,
        elapsed: Duration.zero,
        total: Duration(seconds: config.totalDurationSeconds),
        isPro: isPro,
        videoPath: null,
        cameraInitialized: alreadyReady,
        isRecording: false,      
      );
      
      if (config.videoEnabled && !alreadyReady) {
        await _initializeCamera(session: thisSession);
        if (thisSession != _globalSessionId || state.finished) return;
      }

      final selected = allCallouts.where((c) => config.enabledCalloutIds.contains(c.id)).toList();

      await _preloadAudio(selected);
      if (thisSession != _globalSessionId || state.finished) return;

      if (playStartWhistle) {
        await _playFirstAvailableOnCallout([
          'assets/audio/callouts/whistle_start.wav',
          'assets/audio/callouts/whistle_start.mp3',
        ], thisSession);
        await Future.delayed(const Duration(milliseconds: 1600));
      }
    
      if (thisSession != _globalSessionId || state.finished) return;

      if (config.videoEnabled && state.cameraInitialized) {
        await _startRecording();
      }

      _stopwatch..reset()..start();

      _ticker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (thisSession != _globalSessionId || _finishing) {
          timer.cancel();
          return;
        }

        final elapsed = _stopwatch.elapsed;
        final int videoLimitSeconds = state.isPro ? 600 : 60;

        // FIX: Ticker Race Condition
        // Use an else-if structure to prevent firing both the limit trigger and the finish trigger simultaneously
        if (config.videoEnabled && state.isRecording && elapsed.inSeconds >= videoLimitSeconds) {
          _stopAndSaveVideo();
        } else if (elapsed >= state.total && !_isStoppingVideo) {
          timer.cancel();
          _finish(playEndWhistle: true, session: thisSession);
          return;
        }
        
        state = state.copyWith(running: true, elapsed: elapsed);
      });

      _nextTimer = Timer(_firstCalloutDelay, () {
        if (thisSession == _globalSessionId && !state.finished) {
          _fire(selected, config, thisSession);
        }
      });
    } catch (e) {
      debugPrint('[drill] CRITICAL START ERROR: $e');
    } finally {
      _isStarting = false;
    }
  }

  void pause() {
    if (state.finished || state.paused) return;
    _cancelTimers(keepTicker: true);
    _stopwatch.stop();
    state = state.copyWith(paused: true);
  }

  void resume({required DrillConfig config, required List<Callout> allCallouts}) {
    if (state.finished || !state.paused) return;
    _stopwatch.start();
    final selected = allCallouts.where((c) => config.enabledCalloutIds.contains(c.id)).toList();
    
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

 Future<void> _fire(List<Callout> selected, DrillConfig cfg, int session) async {
    if (session != _globalSessionId || state.finished || selected.isEmpty) return;

    final next = _pickRandomCallout(selected);
    _lastCalloutId = next.id;

    unawaited(HapticFeedback.lightImpact());
    
    // Non-blocking fire
    _playCallout(next, session, cfg);

    if (session != _globalSessionId) return;
    final newCount = state.calloutsCompleted + 1;

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

    try {
      _cancelTimers();
      _stopwatch.stop();

      // FIX: Synchronize Stop Lock
      // If the ticker already triggered _stopAndSaveVideo (due to the 60s limit),
      // we must wait for it to finish rather than skipping it.
      if (_isStoppingVideo) {
        int attempts = 0;
        while (_isStoppingVideo && attempts < 50) { // Max 5 seconds waiting
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;
        }
      } else if (state.isRecording) {
        await _stopAndSaveVideo().timeout(const Duration(seconds: 5));
      }
      
      state = state.copyWith(
        cameraInitialized: false, 
        running: false,
        paused: false,
        isRecording: false,
      );
      
      // FIX: Increase Disposal Delay
      // Increase delay drastically to give the native Android MediaRecorder
      // time to write the MP4 "moov" atom metadata to disk before destruction.
      await Future.delayed(const Duration(milliseconds: 1500));

      final controller = _cameraController;
      _cameraController = null;
      if (controller != null) {
        try {
          await controller.dispose().timeout(const Duration(seconds: 2));
        } catch (e) {
          debugPrint('[camera] Dispose error: $e');
        }
      }

      state = state.copyWith(
        finished: true,
        holdRemaining: null,
        cameraInitialized: false, 
        isRecording: false,
      );

      for (var p in _playerPool) { try { await p.stop(); } catch (_) {} }

      if (playEndWhistle) {
        await _playFirstAvailableOnCallout([
          'assets/audio/callouts/whistle_end.wav',
          'assets/audio/callouts/whistle_end.mp3',
        ], _globalSessionId);
      }
    } finally {
      await _disposeInternal();
      _isGlobalFinishing = false;
    }
  }

  Future<void> _initializeCamera({int? session}) async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      state = state.copyWith(cameraInitialized: true);
      return; 
    }

    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera, Permission.microphone, Permission.storage
    ].request();

    if (statuses[Permission.camera] != PermissionStatus.granted) {
      state = state.copyWith(cameraInitialized: false);
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

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
      state = state.copyWith(cameraInitialized: true);

    } catch (e) {
      state = state.copyWith(cameraInitialized: false);
      _cameraController = null;
    }
  }

  Future<void> _startRecording() async {
    final controller = _cameraController;
    if (controller != null && controller.value.isInitialized) {
      try {
        await controller.startVideoRecording();
        state = state.copyWith(isRecording: true);
      } catch (e) {
        state = state.copyWith(isRecording: false);
      }
    }
  }

  Future<void> _stopAndSaveVideo() async {
    if (_isStoppingVideo || _cameraController == null) return;
    if (!_cameraController!.value.isRecordingVideo) return;

    _isStoppingVideo = true;
    try {
      final XFile rawVideo = await _cameraController!.stopVideoRecording();
      state = state.copyWith(
        isRecording: false,
        videoPath: rawVideo.path, 
      );
    } catch (e) {
      state = state.copyWith(isRecording: false);
    } finally {
      _isStoppingVideo = false;
    }
  }

  // BUG FIX: Pooled custom audio to stop UI stutter
  Future<void> _playCallout(Callout c, int session, DrillConfig config) async {
    if (_playerPool.isEmpty || session != _globalSessionId) return;

    final p = _playerPool[_poolIndex];
    _poolIndex = (_poolIndex + 1) % _playerPool.length;

    final customPath = config.customAudioPaths[c.id];
    
    try {
      if (customPath != null && File(customPath).existsSync()) {
        await p.setDeviceFile(customPath);
      } else {
        final targetId = c.audioAssetAlias ?? c.id;
        final asset = _assetForId[targetId];
        if (asset != null) await p.setAsset(asset);
      }
      if (session == _globalSessionId) await p.play();
    } catch (_) {
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  Future<bool> _playFirstAvailableOnCallout(List<String> candidates, int session) async {
    if (_playerPool.isEmpty) return false;
    
    for (final asset in candidates) {
      try {
        final p = _playerPool[_poolIndex];
        _poolIndex = (_poolIndex + 1) % _playerPool.length;

        await p.setAsset(asset);
        if (session != _globalSessionId) return false;
        await p.play();
        return true; 
      } catch (e) {}
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
    for (var p in _playerPool) {
      try { await p.stop(); await p.dispose(); } catch (_) {}
    }
    _playerPool.clear();
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