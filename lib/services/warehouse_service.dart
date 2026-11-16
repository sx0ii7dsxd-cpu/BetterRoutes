import 'dart:math';

import '../database/app_database.dart';
import '../models/warehouse_model.dart';
import '../repositories/warehouse_repository.dart';
import 'database_id_generator.dart';

class WarehouseService {
  WarehouseService(this._repository);

  factory WarehouseService.local() {
    return WarehouseService(SqliteWarehouseRepository(AppDatabase.instance));
  }

  final WarehouseRepository _repository;
  static final Random _random = Random.secure();

  Future<List<Warehouse>> getAll() => _repository.getAll();

  Future<Warehouse?> getById(String id) => _repository.getById(id);

  Future<List<Warehouse>> search(String query) => _repository.search(query);

  Future<Warehouse> create({
    required String name,
    required String address,
    required String contactName,
    required String contactNumber,
    String locationNote = '',
    required double latitude,
    required double longitude,
  }) async {
    final _WarehouseInput input = _validateInput(
      name: name,
      address: address,
      contactName: contactName,
      contactNumber: contactNumber,
      locationNote: locationNote,
      latitude: latitude,
      longitude: longitude,
    );
    final DateTime now = DateTime.now().toUtc();
    final String id = DatabaseIdGenerator.generate();
    final Warehouse warehouse = Warehouse(
      id: id,
      code: _newCode(),
      name: input.name,
      address: input.address,
      contactName: input.contactName,
      contactNumber: input.contactNumber,
      locationNote: input.locationNote,
      latitude: latitude,
      longitude: longitude,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.insert(warehouse);
    return warehouse;
  }

  Future<Warehouse> update({
    required Warehouse existing,
    required String name,
    required String address,
    required String contactName,
    required String contactNumber,
    String locationNote = '',
    required double latitude,
    required double longitude,
  }) async {
    final _WarehouseInput input = _validateInput(
      name: name,
      address: address,
      contactName: contactName,
      contactNumber: contactNumber,
      locationNote: locationNote,
      latitude: latitude,
      longitude: longitude,
    );
    final Warehouse updated = existing.copyWith(
      name: input.name,
      address: input.address,
      contactName: input.contactName,
      contactNumber: input.contactNumber,
      locationNote: input.locationNote,
      latitude: latitude,
      longitude: longitude,
      updatedAt: DateTime.now().toUtc(),
    );
    await _repository.update(updated);
    return updated;
  }

  Future<void> delete(String id) => _repository.delete(id);

  static _WarehouseInput _validateInput({
    required String name,
    required String address,
    required String contactName,
    required String contactNumber,
    required String locationNote,
    required double latitude,
    required double longitude,
  }) {
    final String normalizedName = name.trim();
    final String normalizedAddress = address.trim();
    final String normalizedContactName = contactName.trim();
    final String normalizedContactNumber = contactNumber.trim();
    if (normalizedName.isEmpty ||
        normalizedAddress.isEmpty ||
        normalizedContactName.isEmpty ||
        normalizedContactNumber.isEmpty) {
      throw const FormatException(
        'Name, address, contact name, and contact number are required.',
      );
    }
    if (normalizedContactNumber.replaceAll(RegExp(r'\D'), '').length < 7) {
      throw const FormatException('Enter a valid contact number.');
    }
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('Select a valid warehouse location.');
    }

    return _WarehouseInput(
      name: normalizedName,
      address: normalizedAddress,
      contactName: normalizedContactName,
      contactNumber: normalizedContactNumber,
      locationNote: locationNote.trim(),
    );
  }

  static String _newCode() =>
      'WH-${_random.nextInt(1000000).toString().padLeft(6, '0')}';
}

class _WarehouseInput {
  const _WarehouseInput({
    required this.name,
    required this.address,
    required this.contactName,
    required this.contactNumber,
    required this.locationNote,
  });

  final String name;
  final String address;
  final String contactName;
  final String contactNumber;
  final String locationNote;
}
