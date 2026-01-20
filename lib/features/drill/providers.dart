import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'drill_engine.dart';

export 'models.dart';
export 'drill_engine.dart';

// --- Shared Preferences Provider ---
// We use a FutureProvider to ensure prefs are ready before use
final sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

// --- UI State Providers ---
final languageProvider = StateProvider<String>((ref) => 'en');
final showCalloutButtonsProvider = StateProvider<bool>((ref) => true);

// --- PERSISTED PRO STATUS ---
final isProProvider = NotifierProvider<IsProNotifier, bool>(() {
  return IsProNotifier();
});

class IsProNotifier extends Notifier<bool> {
  static const _keyIsPro = 'is_pro_user';

  @override
  bool build() {
    // 1. Attempt to load from prefs immediately if available
    // Note: In a real app with async purchase verification, you might check a PurchaseService here.
    // For now, we check local storage for the simulated toggle.
    _load();
    return false; // Default to false until loaded
  }

  Future<void> _load() async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    state = prefs.getBool(_keyIsPro) ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setBool(_keyIsPro, state);
  }

  Future<void> setStatus(bool isPro) async {
    state = isPro;
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setBool(_keyIsPro, state);
  }
}

// --- PERSISTED DRILL CONFIGURATION ---
final drillConfigProvider = NotifierProvider<DrillConfigNotifier, DrillConfig>(() {
  return DrillConfigNotifier();
});

class DrillConfigNotifier extends Notifier<DrillConfig> {
  static const _keyConfig = 'drill_config_v1';

  @override
  DrillConfig build() {
    // Initialize with defaults, then load from disk
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
        state = DrillConfig.fromJson(jsonString);
      }
    } catch (e) {
      // If error (e.g. format change), keep defaults
      print("Error loading drill config: $e");
    }
  }

  Future<void> _save() async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setString(_keyConfig, state.toJson());
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

// --- USER PROFILE (With Persistence) ---
final userProfileProvider = NotifierProvider<UserProfileNotifier, UserProfile>(() {
  return UserProfileNotifier();
});

class UserProfileNotifier extends Notifier<UserProfile> {
  static const _keyWeight = 'user_weight';
  static const _keyTeam = 'user_team';

  @override
  UserProfile build() {
    _loadPersistence();
    return const UserProfile(id: 'local_user', weightLbs: 150.0);
  }

  Future<void> _loadPersistence() async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    final savedWeight = prefs.getDouble(_keyWeight) ?? 150.0;
    final savedTeam = prefs.getString(_keyTeam);
    
    state = state.copyWith(
      weightLbs: savedWeight,
      teamName: savedTeam
    );
  }

  Future<void> updateWeight(double newWeight) async {
    state = state.copyWith(weightLbs: newWeight);
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setDouble(_keyWeight, newWeight);
  }

  Future<void> updateTeam(String teamName) async {
    state = state.copyWith(teamName: teamName);
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setString(_keyTeam, teamName);
  }
}

// --- ENGINE PROVIDER ---
final drillEngineProvider = NotifierProvider<DrillEngineNotifier, DrillState>(() {
  return DrillEngineNotifier();
});

// --- DATA PROVIDERS ---

// 1. All available callouts (Static definition for now)
final calloutsProvider = FutureProvider<List<Callout>>((ref) async {
  return [
    // Standard Moves
    const Callout(id: 'shot', nameEn: 'Shot', nameEs: 'Tiro', type: 'Movement'),
    const Callout(id: 'sprawl', nameEn: 'Sprawl', nameEs: 'Sprawl', type: 'Movement'),
    const Callout(id: 'stance', nameEn: 'Stance', nameEs: 'Postura', type: 'Movement'),
    const Callout(id: 'circle', nameEn: 'Circle', nameEs: 'Círculo', type: 'Movement'),
    const Callout(id: 'down_block', nameEn: 'Down Block', nameEs: 'Bloqueo Abajo', type: 'Movement'),
    const Callout(id: 'fake', nameEn: 'Fake', nameEs: 'Finta', type: 'Movement'),
    const Callout(id: 'level_change', nameEn: 'Level Change', nameEs: 'Cambio de Nivel', type: 'Movement'),
    const Callout(id: 'snap_down', nameEn: 'Snap Down', nameEs: 'Jalón', type: 'Movement'),
    const Callout(id: 'high_knees', nameEn: 'High Knees', nameEs: 'Rodillas Altas', type: 'Movement'),
    
    // Duration/Intensity Variants
    const Callout(id: 'foot_fire5', nameEn: 'Foot Fire (5s)', nameEs: 'Fuego Pies (5s)', type: 'Duration', durationSeconds: 5),
    const Callout(id: 'foot_fire15', nameEn: 'Foot Fire (15s)', nameEs: 'Fuego Pies (15s)', type: 'Duration', durationSeconds: 15),
    
    const Callout(id: 'hand_15', nameEn: 'Hand Fight (15s)', nameEs: 'Manos (15s)', type: 'Duration', durationSeconds: 15),
    const Callout(id: 'hand_30', nameEn: 'Hand Fight (30s)', nameEs: 'Manos (30s)', type: 'Duration', durationSeconds: 30),
    const Callout(id: 'hand_60', nameEn: 'Hand Fight (60s)', nameEs: 'Manos (60s)', type: 'Duration', durationSeconds: 60),
  ];
});

// 2. Active Callouts (Currently essentially the same as all, but useful if we add packs later)
final calloutsForActivePackProvider = FutureProvider<List<Callout>>((ref) async {
  // In the future, this would look at UserProfile.activeVoicePackId
  // and fetch specific callouts from FireStore/Local DB.
  // For now, we return the base list.
  return ref.watch(calloutsProvider.future);
});
