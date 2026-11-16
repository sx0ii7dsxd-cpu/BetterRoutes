class Truck {
  const Truck({
    required this.id,
    required this.registrationNumber,
    required this.truckType,
    required this.capacity,
    required this.details,
    required this.driverName,
    required this.driverContactNumber,
    required this.warehouseId,
    required this.businessId,
    required this.approvalStatus,
    required this.createdAt,
    required this.updatedAt,
    this.warehouseName,
    this.warehouseCode,
    this.businessName,
  });

  static const List<String> supportedTypes = [
    'Mini truck',
    'Box truck',
    'Heavy truck',
    'Refrigerated truck',
  ];
  static const List<String> supportedStatuses = [
    'pending',
    'approved',
    'rejected',
  ];

  final String id;
  final String registrationNumber;
  final String truckType;
  final String capacity;
  final String details;
  final String driverName;
  final String driverContactNumber;
  final String warehouseId;
  final String businessId;
  final String approvalStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? warehouseName;
  final String? warehouseCode;
  final String? businessName;

  Map<String, Object?> toDatabaseMap() => {
    'id': id,
    'registration_number': registrationNumber,
    'truck_type': truckType,
    'capacity': capacity,
    'details': details,
    'driver_name': driverName,
    'driver_contact_number': driverContactNumber,
    'warehouse_id': warehouseId,
    'business_id': businessId,
    'approval_status': approvalStatus,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory Truck.fromDatabaseMap(Map<String, Object?> row) => Truck(
    id: row['id']! as String,
    registrationNumber: row['registration_number']! as String,
    truckType: row['truck_type']! as String,
    capacity: row['capacity']! as String,
    details: row['details']! as String,
    driverName: row['driver_name']! as String,
    driverContactNumber: row['driver_contact_number']! as String,
    warehouseId: row['warehouse_id']! as String,
    businessId: row['business_id']! as String,
    approvalStatus: row['approval_status']! as String,
    createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    warehouseName: row['warehouse_name'] as String?,
    warehouseCode: row['warehouse_code'] as String?,
    businessName: row['business_name'] as String?,
  );

  Truck copyWith({
    String? registrationNumber,
    String? truckType,
    String? capacity,
    String? details,
    String? driverName,
    String? driverContactNumber,
    String? warehouseId,
    String? businessId,
    DateTime? updatedAt,
  }) => Truck(
    id: id,
    registrationNumber: registrationNumber ?? this.registrationNumber,
    truckType: truckType ?? this.truckType,
    capacity: capacity ?? this.capacity,
    details: details ?? this.details,
    driverName: driverName ?? this.driverName,
    driverContactNumber: driverContactNumber ?? this.driverContactNumber,
    warehouseId: warehouseId ?? this.warehouseId,
    businessId: businessId ?? this.businessId,
    approvalStatus: approvalStatus,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    warehouseName: warehouseName,
    warehouseCode: warehouseCode,
    businessName: businessName,
  );
}
