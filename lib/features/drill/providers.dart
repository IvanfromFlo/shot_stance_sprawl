import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'drill_engine.dart';

export 'models.dart';
export 'drill_engine.dart';

// --- UI State Providers ---
final languageProvider = StateProvider<String>((ref) => 'en');
final isProProvider = StateProvider<bool>((ref) => false);
final showCalloutButtonsProvider = StateProvider<bool>((ref) => true);

// --- User Profile Provider ---
// This handles the weight and team name logic
final userProfileProvider = NotifierProvider<UserProfileNotifier, UserProfile>(() {
  return UserProfileNotifier();
});

class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    return const UserProfile(id: 'local_user', weightLbs: 150.0);
  }

  void updateWeight(double newWeight) {
    state = state.copyWith(weightLbs: newWeight);
    // Optional: Add Firebase sync logic here when repository is ready
  }

  void updateTeam(String teamName) {
    state = state.copyWith(teamName: teamName);
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

// --- Callout Data ---
final calloutsProvider = FutureProvider<List<Callout>>((ref) async {
  return [
    const Callout(id: 'shot', nameEn: 'Shot', nameEs: 'Tiro', type: 'Movement'),
    const Callout(id: 'sprawl', nameEn: 'Sprawl', nameEs: 'Sprawl', type: 'Movement'),
    const Callout(id: 'stance', nameEn: 'Stance', nameEs: 'Postura', type: 'Movement'),
    const Callout(id: 'cross_face', nameEn: 'Cross Face', nameEs: 'Cara Cruzada', type: 'Movement'),
  ];
});