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

class DrillEngineNotifier extends Notifier<DrillState> {
  static int _globalSessionId = 0;
  static bool _isGlobalFinishing = false;

  // --- AUDIO POOL OPTIMIZATION ---
  static final List<IAudioPlayer> _playerPool = [];
  static int _poolIndex = 0;

  static const Duration _firstCalloutDelay = Duration(milliseconds: 1500);
  static CameraController? _cameraController;
  final AudioPlayer _audioPlayer = AudioPlayer(); 
  
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
    ref.onDispose(_disposeInternal);
    return DrillState.idle(const Duration(minutes: 5));
  }

  Future<void> preloadCamera() async {
    print('[drill] Pre-warming camera...');
    await _initializeCamera(session: null); 
  }

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
    if (_isStarting) return;
    _isStarting = true;

    try {
      if (_isGlobalFinishing) {
        print('[drill] Wait: Still finishing previous drill...');
        return;
      }

      _globalSessionId++;
      final thisSession = _globalSessionId;

      _cancelTimers();
      
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
      
      if (config.videoEnabled) {
        if (!alreadyReady) {
          try {
            await _initializeCamera(session: thisSession);
          } catch (e) {
            print('[drill] Camera init failed inside start: $e');
          }
        }
        if (thisSession != _globalSessionId || state.finished) return;
      }

      final selected = allCallouts
          .where((c) => config.enabledCalloutIds.contains(c.id))
          .toList();

      if (thisSession != _globalSessionId || state.finished) return;

      await _preloadAudio(selected, config); // Pass config for dynamic durations
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
        // FREE vs PAID GATE logic enforcement 
        final int videoLimitSeconds = state.isPro ? 600 : 60;

        if (config.videoEnabled && state.isRecording) {
          if (elapsed.inSeconds >= videoLimitSeconds) {
            _stopAndSaveVideo();
          }
        }

        if (elapsed >= state.total) {
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
      print('[drill] CRITICAL START ERROR: $e');
    } finally {
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

 Future<void> _fire(List<Callout> selected, DrillConfig cfg, int session) async {
    if (session != _globalSessionId || state.finished || selected.isEmpty) return;

    final next = _pickRandomCallout(selected);
    _lastCalloutId = next.id;

    unawaited(HapticFeedback.lightImpact());
    
    await _playCallout(next, session, cfg);

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

      if (state.isRecording) {
        try {
          await _stopAndSaveVideo().timeout(const Duration(seconds: 5));
        } catch (e) {
           print('[drill] Video stop timed out or failed in finish: $e');
        }
      }
      
      state = state.copyWith(
        cameraInitialized: false, 
        running: false,
        paused: false,
        isRecording: false,
      );
      
      await Future.delayed(const Duration(milliseconds: 100));

      final controller = _cameraController;
      _cameraController = null;
      if (controller != null) {
        try {
          await controller.dispose().timeout(const Duration(seconds: 2));
        } catch (e) {
          print('[camera] Dispose error (ignored): $e');
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
    } catch (e) {
      print("[drill] Critical error in _finish: $e");
      state = state.copyWith(finished: true);
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

    if (_cameraController != null) {
      try {
        await _cameraController!.dispose();
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {}
      _cameraController = null;
    }

    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.videos, 
      Permission.photos,
      Permission.storage, 
    ].request();

    if (statuses[Permission.camera] != PermissionStatus.granted) {
      state = state.copyWith(cameraInitialized: false);
      return;
    }

    if (session != null && session != _globalSessionId) return;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
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

      if ((session != null && session != _globalSessionId) || state.finished) {
        await controller.dispose();
        _cameraController = null;
        return;
      }

      state = state.copyWith(cameraInitialized: true);

    } catch (e) {
      state = state.copyWith(cameraInitialized: false);
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
      } catch (e) {
        state = state.copyWith(isRecording: false);
      }
    }
  }

  Future<void> _stopAndSaveVideo() async {
    if (_isStoppingVideo) return;
    
    final controller = _cameraController;
    if (controller == null) return;

    if (!controller.value.isRecordingVideo) {
       state = state.copyWith(isRecording: false);
       return;
    }

    _isStoppingVideo = true;
    try {
      final XFile rawVideo = await controller.stopVideoRecording();
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

  /// DYNAMIC ASSET RESOLVER: Matches UI picker selection to available physical assets
  String _getDynamicAssetId(Callout c, DrillConfig config) {
    if (c.type == 'Duration') {
      final dur = config.calloutOverrideDurations[c.id] ?? c.defaultDurationSeconds;
      
      // Fallback routing if a user selects 45s, but only 60s asset exists
      if (c.id == 'hand_fight') {
        if (dur <= 15) return 'hand_15';
        if (dur <= 30) return 'hand_30';
        return 'hand_60'; 
      }
      if (c.id == 'foot_fire') {
        if (dur <= 5) return 'foot_fire5';
        return 'foot_fire15'; 
      }
    }
    return c.audioAssetAlias ?? c.id;
  }

  Future<void> _playCallout(Callout c, int session, DrillConfig config) async {
    if (session != _globalSessionId) return;

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

    if (_playerPool.isEmpty) return;
    try {
      final targetId = _getDynamicAssetId(c, config); // Use the new resolver
      String? asset = _assetForId[targetId];
      
      if (asset != null) {
        final p = _playerPool[_poolIndex];
        _poolIndex = (_poolIndex + 1) % _playerPool.length;
        
        await p.setAsset(asset);
        if (session != _globalSessionId) return;
        await p.play();
      }
    } catch (_) {
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  Future<bool> _playFirstAvailableOnCallout(List<String> candidates, int session) async {
    if (_playerPool.isEmpty) return false;
    
    for (final asset in candidates) {
      if (session != _globalSessionId) return false;
      
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

  Future<void> _preloadAudio(List<Callout> selected, DrillConfig config) async {
    Future<bool> _exists(String path) async {
      try { await rootBundle.load(path); return true; } catch (_) { return false; }
    }

   for (final c in selected) {
      final targetId = _getDynamicAssetId(c, config); // Preload the specific duration chosen
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
    
    for (var p in _playerPool) {
      try {
        await p.stop();
        await p.dispose();
      } catch (_) {}
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