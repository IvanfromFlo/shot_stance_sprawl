import 'package:flutter/foundation.dart';
import 'dart:convert';

@immutable
class UserProfile {
  final String id;
  final String? activeVoicePackId;
  final double weightLbs; 
  final String? teamName;
  final String? profileImageUrl;

  const UserProfile({
    required this.id,
    this.activeVoicePackId,
    this.weightLbs = 150.0,
    this.teamName,
    this.profileImageUrl,
  });

    UserProfile copyWith({
        String? id,
        String? activeVoicePackId,
        double? weightLbs,
        String? teamName,
        String? profileImageUrl,
      }) {
        return UserProfile(
          id: id ?? this.id,
          activeVoicePackId: activeVoicePackId ?? this.activeVoicePackId,
          weightLbs: weightLbs ?? this.weightLbs,
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
      teamName: data['teamName'] as String?,
      profileImageUrl: data['profileImageUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'activeVoicePackId': activeVoicePackId,
      'weightLbs': weightLbs,
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
  final int? durationSeconds;
  final String? audioUrl;

  const Callout({
    required this.id,
    required this.nameEn,
    required this.nameEs,
    required this.type,
    this.durationSeconds,
    this.audioUrl,
  });

  String get name => nameEn;

  factory Callout.fromMap(String id, Map<String, dynamic> data) {
    final rawDur = data['durationSeconds'];
    int? dur;
    if (rawDur is int) dur = rawDur;
    if (rawDur is double) dur = rawDur.round();
    return Callout(
      id: id,
      nameEn: (data['nameEn'] as String?) ?? (data['name'] as String?) ?? 'Callout',
      nameEs: (data['nameEs'] as String?) ?? (data['name'] as String?) ?? 'Comando',
      type: (data['type'] as String?) ?? 'Movement',
      durationSeconds: dur,
      audioUrl: data['audioUrl'] as String?,
    );
  }

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
  final bool videoEnabled;

  const DrillConfig({
    this.totalDurationSeconds = 60,
    this.minIntervalSeconds = 2.0,
    this.maxIntervalSeconds = 4.0,
    this.enabledCalloutIds = const {},
    this.customAudioPaths = const {},
    this.videoEnabled = false,
  });

  double get metValue {
    if (maxIntervalSeconds <= 2.0) return 11.5;
    if (maxIntervalSeconds <= 3.0) return 9.5;
    if (maxIntervalSeconds <= 4.0) return 7.5;
    if (maxIntervalSeconds <= 5.0) return 6.0;
    return 4.5;
  }

  DrillConfig copyWith({
    int? totalDurationSeconds,
    double? minIntervalSeconds,
    double? maxIntervalSeconds,
    Set<String>? enabledCalloutIds,
    Map<String, String>? customAudioPaths,
    bool? videoEnabled,
  }) {
    return DrillConfig(
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      minIntervalSeconds: minIntervalSeconds ?? this.minIntervalSeconds,
      maxIntervalSeconds: maxIntervalSeconds ?? this.maxIntervalSeconds,
      enabledCalloutIds: enabledCalloutIds ?? this.enabledCalloutIds,
      customAudioPaths: customAudioPaths ?? this.customAudioPaths,
      videoEnabled: videoEnabled ?? this.videoEnabled,
    );
  }

  // --- SERIALIZATION FOR PERSISTENCE ---
  
  Map<String, dynamic> toMap() {
    return {
      'totalDurationSeconds': totalDurationSeconds,
      'minIntervalSeconds': minIntervalSeconds,
      'maxIntervalSeconds': maxIntervalSeconds,
      'enabledCalloutIds': enabledCalloutIds.toList(),
      'customAudioPaths': customAudioPaths,
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
      videoEnabled: map['videoEnabled'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory DrillConfig.fromJson(String source) => 
      DrillConfig.fromMap(json.decode(source));
}
