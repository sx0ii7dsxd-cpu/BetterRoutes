import 'dart:convert';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.photoUrl,
    required this.providerIds,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uid;
  final String displayName;
  final String email;
  final String photoUrl;
  final List<String> providerIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toDatabaseMap() => {
    'uid': uid,
    'display_name': displayName,
    'email': email,
    'photo_url': photoUrl,
    'provider_ids': jsonEncode(providerIds),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory UserProfile.fromDatabaseMap(Map<String, Object?> row) {
    final List<Object?> decodedProviderIds =
        jsonDecode(row['provider_ids']! as String) as List<Object?>;
    return UserProfile(
      uid: row['uid']! as String,
      displayName: row['display_name']! as String,
      email: row['email']! as String,
      photoUrl: row['photo_url']! as String,
      providerIds: decodedProviderIds.cast<String>(),
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    );
  }
}
