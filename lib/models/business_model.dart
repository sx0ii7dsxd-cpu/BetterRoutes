class Business {
  const Business({
    required this.id,
    required this.ownerUid,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String ownerUid;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toDatabaseMap() => {
    'id': id,
    'owner_uid': ownerUid,
    'name': name,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory Business.fromDatabaseMap(Map<String, Object?> row) => Business(
    id: row['id']! as String,
    ownerUid: row['owner_uid']! as String,
    name: row['name']! as String,
    createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
  );

  Business copyWith({String? name, DateTime? updatedAt}) => Business(
    id: id,
    ownerUid: ownerUid,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
