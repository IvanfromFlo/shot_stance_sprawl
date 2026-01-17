// lib/data/repositories.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

// ✅ correct path to your models
import '../features/drill/models.dart';

class UserRepository {
  final FirebaseFirestore db;
  UserRepository(this.db);

  Stream<UserProfile> watchProfile(String uid) {
    final doc = db.collection('users').doc(uid);
    return doc.snapshots().map((s) {
      final data = s.data() ?? {};
      return UserProfile.fromMap(s.id, data);
    });
  }

  Future<void> setActiveVoicePack(String uid, String packId) async {
    await db.collection('users').doc(uid).set(
      {'activeVoicePackId': packId},
      SetOptions(merge: true),
    );
  }
}

class VoicePackRepository {
  final FirebaseFirestore db;
  VoicePackRepository(this.db);

  Stream<List<VoicePack>> watchPacks(String uid) {
    return db
        .collection('users')
        .doc(uid)
        .collection('voicePacks')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => VoicePack.fromMap(d.id, d.data())).toList());
  }

  Future<String> createCustomPack({
    required String ownerId,
    required String name,
  }) async {
    final ref =
        db.collection('users').doc(ownerId).collection('voicePacks').doc();
    await ref.set({
      'name': name,
      'ownerId': ownerId,
      'isCustom': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }
}

class CalloutRepository {
  final FirebaseFirestore db;
  CalloutRepository(this.db);

  Stream<List<Callout>> watchCallouts(String uid, String packId) {
    return db
        .collection('users')
        .doc(uid)
        .collection('voicePacks')
        .doc(packId)
        .collection('callouts')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Callout.fromMap(d.id, d.data())).toList());
  }

  Future<String> createCalloutWithUpload({
    required String ownerId,
    required String packId,
    required String name,
    required String type, // 'Movement' | 'Duration'
    int? durationSeconds,
    required File audioFile,
    required StorageRepository storageRepo,
  }) async {
    // 1) Upload audio
    final fileName =
        'callouts/${DateTime.now().millisecondsSinceEpoch}_${audioFile.path.split('/').last}';
    final audioUrl = await storageRepo.uploadFileAndGetUrl(
      ownerId: ownerId,
      packId: packId,
      localFile: audioFile,
      storagePath: fileName,
    );

    // 2) Save doc
    final ref = db
        .collection('users')
        .doc(ownerId)
        .collection('voicePacks')
        .doc(packId)
        .collection('callouts')
        .doc();

    await ref.set({
      'name': name,
      'type': type,
      'durationSeconds': durationSeconds,
      'audioUrl': audioUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }
}

class StorageRepository {
  final FirebaseStorage storage;
  StorageRepository(this.storage);

  Future<String> uploadFileAndGetUrl({
    required String ownerId,
    required String packId,
    required File localFile,
    required String storagePath, // e.g. 'callouts/12345_name.m4a'
  }) async {
    final ref = storage
        .ref()
        .child('users')
        .child(ownerId)
        .child('voicePacks')
        .child(packId)
        .child(storagePath);

    await ref.putFile(localFile);
    return await ref.getDownloadURL();
  }
}


