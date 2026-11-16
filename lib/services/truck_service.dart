import '../database/app_database.dart';
import '../models/business_model.dart';
import '../models/truck_model.dart';
import '../repositories/business_repository.dart';
import '../repositories/truck_repository.dart';
import '../repositories/warehouse_repository.dart';
import 'database_id_generator.dart';

class TruckService {
  TruckService(
    this._truckRepository,
    this._businessRepository,
    this._warehouseRepository,
  );

  factory TruckService.local() {
    final AppDatabase database = AppDatabase.instance;
    return TruckService(
      SqliteTruckRepository(database),
      SqliteBusinessRepository(database),
      SqliteWarehouseRepository(database),
    );
  }

  final TruckRepository _truckRepository;
  final BusinessRepository _businessRepository;
  final WarehouseRepository _warehouseRepository;

  Future<List<Truck>> getForOwner(
    String ownerUid, {
    String? approvalStatus,
    String? businessId,
    String? warehouseId,
  }) {
    _validateOwnerUid(ownerUid);
    _validateApprovalStatus(approvalStatus);
    _validateOptionalFilter(businessId, 'business');
    _validateOptionalFilter(warehouseId, 'warehouse');
    return _truckRepository.getForOwner(
      ownerUid,
      approvalStatus: approvalStatus,
      businessId: businessId,
      warehouseId: warehouseId,
    );
  }

  Future<List<Truck>> searchForOwner(
    String ownerUid,
    String query, {
    String? approvalStatus,
    String? businessId,
    String? warehouseId,
  }) {
    _validateOwnerUid(ownerUid);
    _validateApprovalStatus(approvalStatus);
    _validateOptionalFilter(businessId, 'business');
    _validateOptionalFilter(warehouseId, 'warehouse');
    return _truckRepository.searchForOwner(
      ownerUid,
      query,
      approvalStatus: approvalStatus,
      businessId: businessId,
      warehouseId: warehouseId,
    );
  }

  Future<Truck?> getByIdForOwner(String id, String ownerUid) {
    _validateOwnerUid(ownerUid);
    return _truckRepository.getByIdForOwner(id, ownerUid);
  }

  Future<Truck> create({
    required String ownerUid,
    required String registrationNumber,
    required String truckType,
    required String capacity,
    String details = '',
    required String driverName,
    required String driverContactNumber,
    required String warehouseId,
    required String businessId,
  }) async {
    _validateOwnerUid(ownerUid);
    final _TruckInput input = _validateInput(
      registrationNumber: registrationNumber,
      truckType: truckType,
      capacity: capacity,
      details: details,
      driverName: driverName,
      driverContactNumber: driverContactNumber,
      warehouseId: warehouseId,
      businessId: businessId,
    );
    await _validateAssociations(ownerUid, input);

    final DateTime now = DateTime.now().toUtc();
    final Truck truck = Truck(
      id: DatabaseIdGenerator.generate(),
      registrationNumber: input.registrationNumber,
      truckType: input.truckType,
      capacity: input.capacity,
      details: input.details,
      driverName: input.driverName,
      driverContactNumber: input.driverContactNumber,
      warehouseId: input.warehouseId,
      businessId: input.businessId,
      approvalStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    await _truckRepository.insert(truck);
    return truck;
  }

  Future<Truck> update({
    required String ownerUid,
    required Truck existing,
    required String registrationNumber,
    required String truckType,
    required String capacity,
    String details = '',
    required String driverName,
    required String driverContactNumber,
    required String warehouseId,
    required String businessId,
  }) async {
    _validateOwnerUid(ownerUid);
    final Truck? savedTruck = await _truckRepository.getByIdForOwner(
      existing.id,
      ownerUid,
    );
    if (savedTruck == null) throw TruckNotFoundException(existing.id);
    final _TruckInput input = _validateInput(
      registrationNumber: registrationNumber,
      truckType: truckType,
      capacity: capacity,
      details: details,
      driverName: driverName,
      driverContactNumber: driverContactNumber,
      warehouseId: warehouseId,
      businessId: businessId,
    );
    await _validateAssociations(ownerUid, input);

    final Truck updated = savedTruck.copyWith(
      registrationNumber: input.registrationNumber,
      truckType: input.truckType,
      capacity: input.capacity,
      details: input.details,
      driverName: input.driverName,
      driverContactNumber: input.driverContactNumber,
      warehouseId: input.warehouseId,
      businessId: input.businessId,
      updatedAt: DateTime.now().toUtc(),
    );
    await _truckRepository.update(updated);
    return updated;
  }

  Future<void> delete(String id, String ownerUid) async {
    _validateOwnerUid(ownerUid);
    if (await _truckRepository.getByIdForOwner(id, ownerUid) == null) {
      throw TruckNotFoundException(id);
    }
    await _truckRepository.delete(id);
  }

  Future<void> _validateAssociations(String ownerUid, _TruckInput input) async {
    final Business? business = await _businessRepository.getByIdForOwner(
      input.businessId,
      ownerUid,
    );
    if (business == null) {
      throw const FormatException(
        'Select a business associated with this Firebase account.',
      );
    }
    if (await _warehouseRepository.getById(input.warehouseId) == null) {
      throw const FormatException('Select an existing warehouse.');
    }
  }

  static _TruckInput _validateInput({
    required String registrationNumber,
    required String truckType,
    required String capacity,
    required String details,
    required String driverName,
    required String driverContactNumber,
    required String warehouseId,
    required String businessId,
  }) {
    final String normalizedRegistration = registrationNumber
        .trim()
        .toUpperCase();
    final String normalizedCapacity = capacity.trim();
    final String normalizedDriverName = driverName.trim();
    final String normalizedDriverContact = driverContactNumber.trim();
    if (normalizedRegistration.isEmpty ||
        normalizedCapacity.isEmpty ||
        normalizedDriverName.isEmpty ||
        normalizedDriverContact.isEmpty ||
        warehouseId.trim().isEmpty ||
        businessId.trim().isEmpty) {
      throw const FormatException(
        'Registration, capacity, driver, contact, warehouse, and business '
        'are required.',
      );
    }
    if (!Truck.supportedTypes.contains(truckType)) {
      throw const FormatException('Select a supported truck type.');
    }
    if (normalizedDriverContact.replaceAll(RegExp(r'\D'), '').length < 7) {
      throw const FormatException('Enter a valid driver contact number.');
    }
    return _TruckInput(
      registrationNumber: normalizedRegistration,
      truckType: truckType,
      capacity: normalizedCapacity,
      details: details.trim(),
      driverName: normalizedDriverName,
      driverContactNumber: normalizedDriverContact,
      warehouseId: warehouseId,
      businessId: businessId,
    );
  }

  static void _validateOwnerUid(String ownerUid) {
    if (ownerUid.trim().isEmpty) {
      throw const FormatException('A signed-in Firebase account is required.');
    }
  }

  static void _validateApprovalStatus(String? approvalStatus) {
    if (approvalStatus != null &&
        !Truck.supportedStatuses.contains(approvalStatus)) {
      throw const FormatException('Select a supported truck status.');
    }
  }

  static void _validateOptionalFilter(String? id, String label) {
    if (id != null && id.trim().isEmpty) {
      throw FormatException('A valid $label filter is required.');
    }
  }
}

class _TruckInput {
  const _TruckInput({
    required this.registrationNumber,
    required this.truckType,
    required this.capacity,
    required this.details,
    required this.driverName,
    required this.driverContactNumber,
    required this.warehouseId,
    required this.businessId,
  });

  final String registrationNumber;
  final String truckType;
  final String capacity;
  final String details;
  final String driverName;
  final String driverContactNumber;
  final String warehouseId;
  final String businessId;
}
