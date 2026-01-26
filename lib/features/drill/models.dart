import 'package:flutter/foundation.dart';
import 'dart:convert';

@immutable
class UserProfile {
  final String id;
  final String? activeVoicePackId;
  final double weightLbs;
  final int age; // Added Age field
  final String? teamName;
  final String? profileImageUrl; // For the user image

  const UserProfile({
    required this.id,
    this.activeVoicePackId,
    this.weightLbs = 150.0,
    this.age = 18, // Default age
    this.teamName,
    this.profileImageUrl,
  });

  UserProfile copyWith({
    String? id,
    String? activeVoicePackId,
    double? weightLbs,
    int? age,
    String? teamName,
    String? profileImageUrl,
  }) {
    return UserProfile(
      id: id ?? this.id,
      activeVoicePackId: activeVoicePackId ?? this.activeVoicePackId,
      weightLbs: weightLbs ?? this.weightLbs,
      age: age ?? this.age,
      teamName: teamName ?? this.teamName,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    );
  }

  // Helper for the calorie formula: Calories = MET * kg * hours
  double get weightKg => weightLbs * 0.453592;

  factory UserProfile.fromMap(String id, Map<String, dynamic> data) {
    return UserProfile(
      id: id,
      activeVoicePackId: data['activeVoicePackId'] as String?,
      weightLbs: (data['weightLbs'] as num?)?.toDouble() ?? 150.0,
      age: (data['age'] as num?)?.toInt() ?? 18,
      teamName: data['teamName'] as String?,
      profileImageUrl: data['profileImageUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'activeVoicePackId': activeVoicePackId,
      'weightLbs': weightLbs,
      'age': age,
      'teamName': teamName,
      'profileImageUrl': profileImageUrl,
    };
  }
}

@immutable
class VoicePack {
  final String id;
  final String name;
  final String ownerId;
  final bool isCustom;
  const VoicePack({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.isCustom,
  });

  factory VoicePack.fromMap(String id, Map<String, dynamic> data) {
    return VoicePack(
      id: id,
      name: (data['name'] as String?) ?? 'Untitled',
      ownerId: (data['ownerId'] as String?) ?? '',
      isCustom: (data['isCustom'] as bool?) ?? false,
    );
  }
}

@immutable
class Callout {
  final String id;
  final String nameEn;
  final String nameEs;
  final String type; // 'Movement' | 'Duration'
  final int defaultDurationSeconds; //  Renamed and non-nullable default
  final String? audioUrl; 
  final bool isCustom;
  final String? audioAssetAlias; //Points to the physical file ID (e.g. 'hand_15')

  const Callout({
    required this.id,
    required this.nameEn,
    required this.nameEs,
    required this.type,
    this.defaultDurationSeconds = 0, // Default to 0
    this.audioUrl,
    this.isCustom = false,
    this.audioAssetAlias, // 
  });

  // Simple helper, though UI usually handles language based on provider
  String get name => nameEn;

  // Added toMap for saving custom callouts to SharedPreferences
Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nameEn': nameEn,
      'nameEs': nameEs,
      'type': type,
      'defaultDurationSeconds': defaultDurationSeconds, // CHANGED
      'audioUrl': audioUrl,
      'isCustom': isCustom,
      'audioAssetAlias': audioAssetAlias, // NEW
    };
  }

  factory Callout.fromMap(String id, Map<String, dynamic> data) {
    // Simplified duration parsing
    final rawDur = data['defaultDurationSeconds'] ?? data['durationSeconds']; 
    
    return Callout(
      id: data['id'] ?? id, 
      nameEn: (data['nameEn'] as String?) ?? (data['name'] as String?) ?? 'Callout',
      nameEs: (data['nameEs'] as String?) ?? (data['name'] as String?) ?? 'Comando',
      type: (data['type'] as String?) ?? 'Movement',
      defaultDurationSeconds: (rawDur as num?)?.toInt() ?? 0, // CHANGED
      audioUrl: data['audioUrl'] as String?,
      isCustom: (data['isCustom'] as bool?) ?? false,
      audioAssetAlias: data['audioAssetAlias'] as String?, // NEW
    );
  }

  // Factory for loading from JSON (SharedPreferences)
  factory Callout.fromJson(Map<String, dynamic> json) => Callout.fromMap(json['id'] ?? 'unknown', json);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Callout && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class DrillConfig {
  final int totalDurationSeconds;
  final double minIntervalSeconds;
  final double maxIntervalSeconds;
  final Set<String> enabledCalloutIds;
  final Map<String, String> customAudioPaths;
  final Map<String, int> calloutOverrideDurations; // call out toggle
  final bool videoEnabled;

  const DrillConfig({
    this.totalDurationSeconds = 60,
    this.minIntervalSeconds = 2.0,
    this.maxIntervalSeconds = 4.0,
    this.enabledCalloutIds = const {},
    this.customAudioPaths = const {},
    this.calloutOverrideDurations = const {}, // call out toggle
    this.videoEnabled = false,
  });

  // MET Value

  DrillConfig copyWith({
    int? totalDurationSeconds,
    double? minIntervalSeconds,
    double? maxIntervalSeconds,
    Set<String>? enabledCalloutIds,
    Map<String, String>? customAudioPaths,
    Map<String, int>? calloutOverrideDurations, // calll out toggle
    bool? videoEnabled,
  }) {
    return DrillConfig(
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      minIntervalSeconds: minIntervalSeconds ?? this.minIntervalSeconds,
      maxIntervalSeconds: maxIntervalSeconds ?? this.maxIntervalSeconds,
      enabledCalloutIds: enabledCalloutIds ?? this.enabledCalloutIds,
      customAudioPaths: customAudioPaths ?? this.customAudioPaths,
      calloutOverrideDurations: calloutOverrideDurations ?? this.calloutOverrideDurations, // call out toggle
      videoEnabled: videoEnabled ?? this.videoEnabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalDurationSeconds': totalDurationSeconds,
      'minIntervalSeconds': minIntervalSeconds,
      'maxIntervalSeconds': maxIntervalSeconds,
      'enabledCalloutIds': enabledCalloutIds.toList(),
      'customAudioPaths': customAudioPaths,
      'calloutOverrideDurations': calloutOverrideDurations, // call out toggle
      'videoEnabled': videoEnabled,
    };
  }

  factory DrillConfig.fromMap(Map<String, dynamic> map) {
    return DrillConfig(
      totalDurationSeconds: map['totalDurationSeconds']?.toInt() ?? 60,
      minIntervalSeconds: map['minIntervalSeconds']?.toDouble() ?? 2.0,
      maxIntervalSeconds: map['maxIntervalSeconds']?.toDouble() ?? 4.0,
      enabledCalloutIds: Set<String>.from(map['enabledCalloutIds'] ?? []),
      customAudioPaths: Map<String, String>.from(map['customAudioPaths'] ?? {}),
      calloutOverrideDurations: Map<String, int>.from(map['calloutOverrideDurations'] ?? {}), // call out toggle
      videoEnabled: map['videoEnabled'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory DrillConfig.fromJson(String source) => 
      DrillConfig.fromMap(json.decode(source));
}
