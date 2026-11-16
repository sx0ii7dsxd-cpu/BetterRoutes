import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/database_timestamp.dart';
import '../models/recent_search_model.dart';

abstract interface class RecentSearchRepository {
  Future<List<RecentSearch>> getAll();
  Future<void> record(RecentSearch search, {required int maximumEntries});
  Future<void> delete(String id);
  Future<void> clear();
}

class SqliteRecentSearchRepository implements RecentSearchRepository {
  SqliteRecentSearchRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<RecentSearch>> getAll() async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.query(
      'recent_searches',
      orderBy: 'searched_at DESC, id DESC',
    );
    return rows.map(RecentSearch.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<void> record(
    RecentSearch search, {
    required int maximumEntries,
  }) async {
    final Database database = await _appDatabase.database;
    await database.transaction((Transaction transaction) async {
      final List<Map<String, Object?>> latestRows = await transaction.rawQuery(
        'SELECT searched_at FROM recent_searches '
        'ORDER BY searched_at DESC LIMIT 1',
      );
      DateTime searchedAt = search.searchedAt.toUtc();
      if (latestRows.isNotEmpty) {
        final DateTime latest = DateTime.parse(
          latestRows.single['searched_at']! as String,
        ).toUtc();
        if (!searchedAt.isAfter(latest)) {
          searchedAt = latest.add(const Duration(microseconds: 1));
        }
      }
      await transaction.rawInsert(
        '''
        INSERT INTO recent_searches (
          id, destination_key, query, place_name, address,
          latitude, longitude, provider_place_id, searched_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(destination_key) DO UPDATE SET
          query = excluded.query,
          place_name = excluded.place_name,
          address = excluded.address,
          latitude = excluded.latitude,
          longitude = excluded.longitude,
          provider_place_id = excluded.provider_place_id,
          searched_at = excluded.searched_at
        ''',
        [
          search.id,
          search.destinationKey,
          search.query,
          search.placeName,
          search.address,
          search.latitude,
          search.longitude,
          search.placeId,
          formatDatabaseTimestamp(searchedAt),
        ],
      );
      await transaction.rawDelete(
        '''
        DELETE FROM recent_searches
        WHERE id NOT IN (
          SELECT id FROM recent_searches
          ORDER BY searched_at DESC, id DESC
          LIMIT ?
        )
        ''',
        [maximumEntries],
      );
    });
  }

  @override
  Future<void> delete(String id) async {
    final Database database = await _appDatabase.database;
    final int deleted = await database.delete(
      'recent_searches',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deleted == 0) throw RecentSearchNotFoundException(id);
  }

  @override
  Future<void> clear() async {
    final Database database = await _appDatabase.database;
    await database.delete('recent_searches');
  }
}

class RecentSearchNotFoundException implements Exception {
  const RecentSearchNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'Recent search "$id" was not found.';
}
