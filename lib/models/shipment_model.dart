import 'package:cloud_firestore/cloud_firestore.dart';

class ShipmentPlace {
  const ShipmentPlace({this.name, this.address, this.latitude, this.longitude});

  final String? name;
  final String? address;
  final double? latitude;
  final double? longitude;

  factory ShipmentPlace.fromMap(Object? value) {
    if (value is! Map) return const ShipmentPlace();
    return ShipmentPlace(
      name: _optionalString(value['name']),
      address: _optionalString(value['address']),
      latitude: _optionalDouble(value['latitude']),
      longitude: _optionalDouble(value['longitude']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
  }

  bool get hasCoordinates => latitude != null && longitude != null;
}

class ShipmentEventModel {
  const ShipmentEventModel({
    required this.eventId,
    required this.status,
    required this.title,
    required this.description,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.updatedBy,
  });

  final String eventId;
  final String status;
  final String title;
  final String? description;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final DateTime? timestamp;
  final String? updatedBy;

  factory ShipmentEventModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Shipment event ${snapshot.id} has no data.');
    }
    return ShipmentEventModel.fromData(data, documentId: snapshot.id);
  }

  factory ShipmentEventModel.fromData(
    Map<String, dynamic> data, {
    required String documentId,
  }) {
    return ShipmentEventModel(
      eventId: _optionalString(data['eventId']) ?? documentId,
      status: _optionalString(data['status']) ?? 'unknown',
      title: _optionalString(data['title']) ?? 'Shipment update',
      description: _optionalString(data['description']),
      locationName: _optionalString(data['locationName']),
      latitude: _geoPointLatitude(data['location']),
      longitude: _geoPointLongitude(data['location']),
      timestamp: _timestamp(data['timestamp']),
      updatedBy: _optionalString(data['updatedBy']),
    );
  }
}

class ShipmentModel {
  const ShipmentModel({
    required this.shipmentId,
    required this.trackingCode,
    required this.status,
    required this.origin,
    required this.destination,
    required this.warehouseId,
    required this.warehouseCode,
    required this.truckId,
    required this.driverName,
    required this.driverContact,
    required this.currentLocation,
    required this.estimatedDelivery,
    required this.createdByUid,
    required this.authorizedUserUids,
    required this.createdAt,
    required this.updatedAt,
  });

  final String shipmentId;
  final String trackingCode;
  final String status;
  final ShipmentPlace? origin;
  final ShipmentPlace? destination;
  final String? warehouseId;
  final String? warehouseCode;
  final String? truckId;
  final String? driverName;
  final String? driverContact;
  final GeoPoint? currentLocation;
  final DateTime? estimatedDelivery;
  final String? createdByUid;
  final List<String> authorizedUserUids;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ShipmentModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Shipment ${snapshot.id} has no data.');
    }
    return ShipmentModel.fromData(data, documentId: snapshot.id);
  }

  factory ShipmentModel.fromData(
    Map<String, dynamic> data, {
    required String documentId,
  }) {
    final shipmentId = _optionalString(data['shipmentId']) ?? documentId;
    final trackingCode = _optionalString(data['trackingCode']);
    if (trackingCode == null) {
      throw StateError('Shipment $shipmentId has no tracking code.');
    }

    return ShipmentModel(
      shipmentId: shipmentId,
      trackingCode: trackingCode,
      status: _optionalString(data['status']) ?? 'unknown',
      origin: data['origin'] == null
          ? null
          : ShipmentPlace.fromMap(data['origin']),
      destination: data['destination'] == null
          ? null
          : ShipmentPlace.fromMap(data['destination']),
      warehouseId: _optionalString(data['warehouseId']),
      warehouseCode: _optionalString(data['warehouseCode']),
      truckId: _optionalString(data['truckId']),
      driverName: _optionalString(data['driverName']),
      driverContact: _optionalString(data['driverContact']),
      currentLocation: _geoPoint(data['currentLocation']),
      estimatedDelivery: _timestamp(data['estimatedDelivery']),
      createdByUid: _optionalString(data['createdByUid']),
      authorizedUserUids: _stringList(data['authorizedUserUids']),
      createdAt: _timestamp(data['createdAt']),
      updatedAt: _timestamp(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shipmentId': shipmentId,
      'trackingCode': trackingCode,
      'status': status,
      if (origin != null) 'origin': origin!.toMap(),
      if (destination != null) 'destination': destination!.toMap(),
      if (warehouseId != null) 'warehouseId': warehouseId,
      if (warehouseCode != null) 'warehouseCode': warehouseCode,
      if (truckId != null) 'truckId': truckId,
      if (driverName != null) 'driverName': driverName,
      if (driverContact != null) 'driverContact': driverContact,
      if (currentLocation != null) 'currentLocation': currentLocation,
      if (estimatedDelivery != null)
        'estimatedDelivery': Timestamp.fromDate(estimatedDelivery!),
      if (createdByUid != null) 'createdByUid': createdByUid,
      'authorizedUserUids': authorizedUserUids,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }
}

String? _optionalString(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

List<String> _stringList(Object? value) {
  if (value is! Iterable) return const [];
  return [
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

double? _optionalDouble(Object? value) {
  return value is num ? value.toDouble() : null;
}

GeoPoint? _geoPoint(Object? value) {
  return value is GeoPoint ? value : null;
}

double? _geoPointLatitude(Object? value) {
  return _geoPoint(value)?.latitude;
}

double? _geoPointLongitude(Object? value) {
  return _geoPoint(value)?.longitude;
}

DateTime? _timestamp(Object? value) {
  return value is Timestamp ? value.toDate() : null;
}
