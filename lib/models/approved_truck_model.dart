class ApprovedTruckModel {
  const ApprovedTruckModel({
    required this.truckId,
    required this.sourceRequestId,
    required this.registrationNumber,
    required this.truckType,
    required this.capacity,
    this.capacityUnit,
    this.details,
    required this.warehouseId,
    this.warehouseCode,
    this.warehouseOwnerUid,
    this.ownerUid,
    this.driverUid,
    required this.status,
  });

  final String truckId;
  final String sourceRequestId;
  final String registrationNumber;
  final String truckType;
  final double capacity;
  final String? capacityUnit;
  final String? details;
  final String warehouseId;
  final String? warehouseCode;
  final String? warehouseOwnerUid;
  final String? ownerUid;
  final String? driverUid;
  final String status;

  factory ApprovedTruckModel.fromMap(Map<String, Object?> data) {
    String requiredString(String field) {
      final value = data[field];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Truck is missing $field.');
      }
      return value.trim();
    }

    String? optionalString(String field) {
      final value = data[field];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final capacity = data['capacity'];
    if (capacity is! num) {
      throw const FormatException('Truck has invalid capacity.');
    }

    return ApprovedTruckModel(
      truckId: requiredString('truckId'),
      sourceRequestId: optionalString('sourceRequestId') ?? '',
      registrationNumber: requiredString('registrationNumber'),
      truckType: requiredString('truckType'),
      capacity: capacity.toDouble(),
      capacityUnit: optionalString('capacityUnit'),
      details: optionalString('details'),
      warehouseId: requiredString('warehouseId'),
      warehouseCode: optionalString('warehouseCode'),
      warehouseOwnerUid: optionalString('warehouseOwnerUid'),
      ownerUid: optionalString('ownerUid'),
      driverUid: optionalString('driverUid'),
      status: requiredString('status'),
    );
  }
}
