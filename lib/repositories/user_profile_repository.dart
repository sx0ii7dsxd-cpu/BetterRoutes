import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/user_profile_model.dart';

abstract interface class UserProfileRepository {
  Future<UserProfile?> getByUid(String uid);
  Future<void> save(UserProfile profile);
}

class SqliteUserProfileRepository implements UserProfileRepository {
  SqliteUserProfileRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<UserProfile?> getByUid(String uid) async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.query(
      'user_profiles',
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    return rows.isEmpty ? null : UserProfile.fromDatabaseMap(rows.single);
  }

  @override
  Future<void> save(UserProfile profile) async {
    final Database database = await _appDatabase.database;
    await database.rawInsert(
      '''
      INSERT INTO user_profiles (
        uid, display_name, email, photo_url, provider_ids, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(uid) DO UPDATE SET
        display_name = excluded.display_name,
        email = excluded.email,
        photo_url = excluded.photo_url,
        provider_ids = excluded.provider_ids,
        updated_at = excluded.updated_at
      ''',
      [
        profile.uid,
        profile.displayName,
        profile.email,
        profile.photoUrl,
        profile.toDatabaseMap()['provider_ids'],
        profile.createdAt.toUtc().toIso8601String(),
        profile.updatedAt.toUtc().toIso8601String(),
      ],
    );
  }
}
