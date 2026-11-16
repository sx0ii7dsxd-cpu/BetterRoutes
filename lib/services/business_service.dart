import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/business_model.dart';
import '../repositories/business_repository.dart';
import 'database_id_generator.dart';

class BusinessService {
  BusinessService(this._repository);

  factory BusinessService.local() {
    return BusinessService(SqliteBusinessRepository(AppDatabase.instance));
  }

  final BusinessRepository _repository;

  Future<List<Business>> getForOwner(String ownerUid) {
    _validateOwnerUid(ownerUid);
    return _repository.getForOwner(ownerUid);
  }

  Future<Business?> getByIdForOwner(String id, String ownerUid) {
    _validateOwnerUid(ownerUid);
    return _repository.getByIdForOwner(id, ownerUid);
  }

  Future<int> getTruckCountForOwner(String id, String ownerUid) async {
    _validateOwnerUid(ownerUid);
    if (await _repository.getByIdForOwner(id, ownerUid) == null) {
      throw BusinessNotFoundException(id);
    }
    return _repository.countTrucksForOwner(id, ownerUid);
  }

  Future<Business> create({
    required String ownerUid,
    required String name,
  }) async {
    _validateOwnerUid(ownerUid);
    final String normalizedName = _validateName(name);
    final DateTime now = DateTime.now().toUtc();
    final Business business = Business(
      id: DatabaseIdGenerator.generate(),
      ownerUid: ownerUid,
      name: normalizedName,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.insert(business);
    return business;
  }

  Future<Business> update({
    required String ownerUid,
    required Business existing,
    required String name,
  }) async {
    _validateOwnerUid(ownerUid);
    if (existing.ownerUid != ownerUid ||
        await _repository.getByIdForOwner(existing.id, ownerUid) == null) {
      throw BusinessNotFoundException(existing.id);
    }

    final Business updated = existing.copyWith(
      name: _validateName(name),
      updatedAt: DateTime.now().toUtc(),
    );
    await _repository.update(updated);
    return updated;
  }

  Future<void> delete(String id, String ownerUid) async {
    _validateOwnerUid(ownerUid);
    if (await _repository.getByIdForOwner(id, ownerUid) == null) {
      throw BusinessNotFoundException(id);
    }
    final int truckCount = await _repository.countTrucksForOwner(id, ownerUid);
    if (truckCount > 0) throw BusinessHasTrucksException(truckCount);

    try {
      await _repository.delete(id, ownerUid);
    } on DatabaseException {
      final int remainingTruckCount = await _repository.countTrucksForOwner(
        id,
        ownerUid,
      );
      if (remainingTruckCount > 0) {
        throw BusinessHasTrucksException(remainingTruckCount);
      }
      rethrow;
    }
  }

  static String _validateName(String name) {
    final String normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const FormatException('Business name is required.');
    }
    return normalizedName;
  }

  static void _validateOwnerUid(String ownerUid) {
    if (ownerUid.trim().isEmpty) {
      throw const FormatException('A signed-in Firebase account is required.');
    }
  }
}

class BusinessHasTrucksException implements Exception {
  const BusinessHasTrucksException(this.truckCount);

  final int truckCount;

  @override
  String toString() =>
      'This business still has $truckCount associated '
      '${truckCount == 1 ? 'truck' : 'trucks'}.';
}
