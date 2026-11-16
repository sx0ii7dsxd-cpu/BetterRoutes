import '../database/app_database.dart';
import '../models/user_profile_model.dart';
import '../repositories/user_profile_repository.dart';

class UserProfileService {
  UserProfileService(this._repository);

  factory UserProfileService.local() {
    return UserProfileService(
      SqliteUserProfileRepository(AppDatabase.instance),
    );
  }

  final UserProfileRepository _repository;

  Future<UserProfile?> getByUid(String uid) {
    _validateUid(uid);
    return _repository.getByUid(uid);
  }

  Future<UserProfile> saveFromAuthentication({
    required String uid,
    required String? displayName,
    required String? email,
    required String? photoUrl,
    required List<String> providerIds,
  }) async {
    _validateUid(uid);
    final UserProfile? existing = await _repository.getByUid(uid);
    final DateTime now = DateTime.now().toUtc();
    final UserProfile profile = UserProfile(
      uid: uid,
      displayName: displayName?.trim() ?? '',
      email: email?.trim() ?? '',
      photoUrl: photoUrl?.trim() ?? '',
      providerIds: List<String>.unmodifiable(providerIds),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _repository.save(profile);
    return profile;
  }

  Future<UserProfile> updateProfile({
    required String uid,
    required String displayName,
    required String email,
    required String photoUrl,
    required List<String> providerIds,
  }) async {
    _validateUid(uid);
    final UserProfile? existing = await _repository.getByUid(uid);
    if (existing == null) throw UserProfileNotFoundException(uid);
    if (displayName.trim().isEmpty) {
      throw const FormatException('Profile name is required.');
    }
    final UserProfile updated = UserProfile(
      uid: uid,
      displayName: displayName.trim(),
      email: email.trim(),
      photoUrl: photoUrl.trim(),
      providerIds: List<String>.unmodifiable(providerIds),
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    await _repository.save(updated);
    return updated;
  }

  static void _validateUid(String uid) {
    if (uid.trim().isEmpty) {
      throw const FormatException('A Firebase UID is required.');
    }
  }
}

class UserProfileNotFoundException implements Exception {
  const UserProfileNotFoundException(this.uid);

  final String uid;

  @override
  String toString() => 'Profile "$uid" was not found.';
}
