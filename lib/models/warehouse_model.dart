import 'package:cloud_firestore/cloud_firestore.dart';

class WarehouseModel {
  const WarehouseModel({
    required this.warehouseId,
    required this.code,
    required this.name,
    required this.address,
    required this.contactName,
    required this.contactNumber,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.ownerUid,
    required this.createdAt,
    required this.updatedAt,
  });

  final String warehouseId;
  final String code;
  final String name;
  final String address;
  final String contactName;
  final String contactNumber;
  final String location;
  final double? latitude;
  final double? longitude;
  final String ownerUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory WarehouseModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Warehouse document ${snapshot.id} has no data.');
    }

    return WarehouseModel(
      warehouseId: _requiredString(data, 'warehouseId', snapshot.id),
      code: _requiredString(data, 'code', snapshot.id),
      name: _requiredString(data, 'name', snapshot.id),
      address: _requiredString(data, 'address', snapshot.id),
      contactName: _requiredString(data, 'contactName', snapshot.id),
      contactNumber: _requiredString(data, 'contactNumber', snapshot.id),
      location: _optionalString(data['location']),
      latitude: _optionalDouble(data['latitude']),
      longitude: _optionalDouble(data['longitude']),
      ownerUid: _requiredString(data, 'ownerUid', snapshot.id),
      createdAt: _timestamp(data['createdAt']),
      updatedAt: _timestamp(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore({
    required Object createdAt,
    required Object updatedAt,
  }) {
    return {
      'warehouseId': warehouseId,
      'code': code,
      'name': name,
      'address': address,
      'contactName': contactName,
      'contactNumber': contactNumber,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'ownerUid': ownerUid,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  static String _requiredString(
    Map<String, dynamic> data,
    String field,
    String documentId,
  ) {
    final value = data[field];
    if (value is! String || value.trim().isEmpty) {
      throw StateError('Warehouse $documentId has an invalid $field.');
    }
    return value;
  }

  static String _optionalString(Object? value) {
    return value is String ? value : '';
  }

  static DateTime? _timestamp(Object? value) {
    return value is Timestamp ? value.toDate() : null;
  }

  static double? _optionalDouble(Object? value) {
    return value is num ? value.toDouble() : null;
  }
}
