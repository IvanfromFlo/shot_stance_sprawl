// models.dart
import 'package:flutter/foundation.dart';
import 'dart:convert';

@immutable
class UserProfile {
  final String id;
  final String? activeVoicePackId;
  final double weightLbs;
  final int age; 
  final String? teamName;
  final String? profileImageUrl; 

  const UserProfile({
    required this.id,
    this.activeVoicePackId,
    this.weightLbs = 150.0,
    this.age = 18, 
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
  final String type; 
  final int defaultDurationSeconds; 
  final String? audioUrl; 
  final bool isCustom;
  final String? audioAssetAlias; 

  const Callout({
    required this.id,
    required this.nameEn,
    required this.nameEs,
    required this.type,
    this.defaultDurationSeconds = 0, 
    this.audioUrl,
    this.isCustom = false,
    this.audioAssetAlias, 
  });

  // ADDED: copyWith to allow renaming custom callouts
  Callout copyWith({
    String? id,
    String? nameEn,
    String? nameEs,
    String? type,
    int? defaultDurationSeconds,
    String? audioUrl,
    bool? isCustom,
    String? audioAssetAlias,
  }) {
    return Callout(
      id: id ?? this.id,
      nameEn: nameEn ?? this.nameEn,
      nameEs: nameEs ?? this.nameEs,
      type: type ?? this.type,
      defaultDurationSeconds: defaultDurationSeconds ?? this.defaultDurationSeconds,
      audioUrl: audioUrl ?? this.audioUrl,
      isCustom: isCustom ?? this.isCustom,
      audioAssetAlias: audioAssetAlias ?? this.audioAssetAlias,
    );
  }

  String get name => nameEn;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nameEn': nameEn,
      'nameEs': nameEs,
      'type': type,
      'defaultDurationSeconds': defaultDurationSeconds,
      'audioUrl': audioUrl,
      'isCustom': isCustom,
      'audioAssetAlias': audioAssetAlias,
    };
  }

  factory Callout.fromMap(String id, Map<String, dynamic> data) {
    final rawDur = data['defaultDurationSeconds'] ?? data['durationSeconds']; 
    
    return Callout(
      id: data['id'] ?? id, 
      nameEn: (data['nameEn'] as String?) ?? (data['name'] as String?) ?? 'Callout',
      nameEs: (data['nameEs'] as String?) ?? (data['name'] as String?) ?? 'Comando',
      type: (data['type'] as String?) ?? 'Movement',
      defaultDurationSeconds: (rawDur as num?)?.toInt() ?? 0, 
      audioUrl: data['audioUrl'] as String?,
      isCustom: (data['isCustom'] as bool?) ?? false,
      audioAssetAlias: data['audioAssetAlias'] as String?, 
    );
  }

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
  final Map<String, int> calloutOverrideDurations; 
  final bool videoEnabled;

  const DrillConfig({
    this.totalDurationSeconds = 60,
    this.minIntervalSeconds = 2.0,
    this.maxIntervalSeconds = 4.0,
    this.enabledCalloutIds = const {},
    this.customAudioPaths = const {},
    this.calloutOverrideDurations = const {}, 
    this.videoEnabled = false,
  });

  double get metValue {
    if (maxIntervalSeconds <= 2.0) return 11.5; 
    if (maxIntervalSeconds <= 4.0) return 8.5;  
    return 6.0; 
  }

  DrillConfig copyWith({
    int? totalDurationSeconds,
    double? minIntervalSeconds,
    double? maxIntervalSeconds,
    Set<String>? enabledCalloutIds,
    Map<String, String>? customAudioPaths,
    Map<String, int>? calloutOverrideDurations, 
    bool? videoEnabled,
  }) {
    return DrillConfig(
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      minIntervalSeconds: minIntervalSeconds ?? this.minIntervalSeconds,
      maxIntervalSeconds: maxIntervalSeconds ?? this.maxIntervalSeconds,
      enabledCalloutIds: enabledCalloutIds ?? this.enabledCalloutIds,
      customAudioPaths: customAudioPaths ?? this.customAudioPaths,
      calloutOverrideDurations: calloutOverrideDurations ?? this.calloutOverrideDurations, 
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
      'calloutOverrideDurations': calloutOverrideDurations, 
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
      calloutOverrideDurations: Map<String, int>.from(map['calloutOverrideDurations'] ?? {}), 
      videoEnabled: map['videoEnabled'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory DrillConfig.fromJson(String source) => 
      DrillConfig.fromMap(json.decode(source));
}