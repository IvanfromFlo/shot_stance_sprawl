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
final isProProvider = StateProvider<bool>((ref) => false);
final showCalloutButtonsProvider = StateProvider<bool>((ref) => true);

// --- User Profile Provider (With Persistence) ---
final userProfileProvider = NotifierProvider<UserProfileNotifier, UserProfile>(() {
  return UserProfileNotifier();
});

class UserProfileNotifier extends Notifier<UserProfile> {
  // Keys for persistence
  static const _keyWeight = 'user_weight';
  static const _keyTeam = 'user_team';

  @override
  UserProfile build() {
    // 1. Initialize with default
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

// --- Configuration Provider ---
final drillConfigProvider = NotifierProvider<DrillConfigNotifier, DrillConfig>(() {
  return DrillConfigNotifier();
});

// --- Engine Provider ---
final drillEngineProvider = NotifierProvider<DrillEngineNotifier, DrillState>(() {
  return DrillEngineNotifier();
});

// --- Callout Data (Updated with uploaded assets) ---
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
