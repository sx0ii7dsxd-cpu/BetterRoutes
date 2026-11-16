class Warehouse {
  const Warehouse({
    required this.id,
    required this.code,
    required this.name,
    required this.address,
    required this.contactName,
    required this.contactNumber,
    required this.locationNote,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String code;
  final String name;
  final String address;
  final String contactName;
  final String contactNumber;
  final String locationNote;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toDatabaseMap() => {
    'id': id,
    'warehouse_code': code,
    'name': name,
    'address': address,
    'contact_name': contactName,
    'contact_number': contactNumber,
    'location_note': locationNote,
    'latitude': latitude,
    'longitude': longitude,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory Warehouse.fromDatabaseMap(Map<String, Object?> row) {
    return Warehouse(
      id: row['id']! as String,
      code: row['warehouse_code']! as String,
      name: row['name']! as String,
      address: row['address']! as String,
      contactName: row['contact_name']! as String,
      contactNumber: row['contact_number']! as String,
      locationNote: row['location_note']! as String,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    );
  }

  Warehouse copyWith({
    String? name,
    String? address,
    String? contactName,
    String? contactNumber,
    String? locationNote,
    double? latitude,
    double? longitude,
    DateTime? updatedAt,
  }) {
    return Warehouse(
      id: id,
      code: code,
      name: name ?? this.name,
      address: address ?? this.address,
      contactName: contactName ?? this.contactName,
      contactNumber: contactNumber ?? this.contactNumber,
      locationNote: locationNote ?? this.locationNote,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
