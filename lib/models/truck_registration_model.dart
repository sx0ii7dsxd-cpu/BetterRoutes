import 'package:cloud_firestore/cloud_firestore.dart';

class TruckRegistrationModel {
  const TruckRegistrationModel({
    required this.requestId,
    required this.registrationNumber,
    required this.truckType,
    required this.capacity,
    required this.capacityUnit,
    required this.details,
    required this.driverName,
    required this.driverContactNumber,
    required this.warehouseId,
    required this.warehouseCode,
    required this.requestedByUid,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String requestId;
  final String registrationNumber;
  final String truckType;
  final double capacity;
  final String? capacityUnit;
  final String? details;
  final String driverName;
  final String driverContactNumber;
  final String warehouseId;
  final String warehouseCode;
  final String requestedByUid;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory TruckRegistrationModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Truck request ${snapshot.id} has no data.');
    }

    final capacity = data['capacity'];
    if (capacity is! num) {
      throw StateError('Truck request ${snapshot.id} has invalid capacity.');
    }

    return TruckRegistrationModel(
      requestId: _requiredString(data, 'requestId', snapshot.id),
      registrationNumber:
          _requiredString(data, 'registrationNumber', snapshot.id),
      truckType: _requiredString(data, 'truckType', snapshot.id),
      capacity: capacity.toDouble(),
      capacityUnit: _optionalString(data['capacityUnit']),
      details: _optionalString(data['details']),
      driverName: _requiredString(data, 'driverName', snapshot.id),
      driverContactNumber:
          _requiredString(data, 'driverContactNumber', snapshot.id),
      warehouseId: _requiredString(data, 'warehouseId', snapshot.id),
      warehouseCode: _requiredString(data, 'warehouseCode', snapshot.id),
      requestedByUid: _requiredString(data, 'requestedByUid', snapshot.id),
      status: _requiredString(data, 'status', snapshot.id),
      createdAt: _timestamp(data['createdAt']),
      updatedAt: _timestamp(data['updatedAt']),
    );
  }

  static String _requiredString(
    Map<String, dynamic> data,
    String field,
    String documentId,
  ) {
    final value = data[field];
    if (value is! String || value.trim().isEmpty) {
      throw StateError('Truck request $documentId has an invalid $field.');
    }
    return value;
  }

  static String? _optionalString(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value;
  }

  static DateTime? _timestamp(Object? value) {
    return value is Timestamp ? value.toDate() : null;
  }
}
