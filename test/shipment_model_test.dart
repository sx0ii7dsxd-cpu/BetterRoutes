import 'package:better_routes/models/shipment_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses shipment fields, coordinates, and timestamps safely', () {
    final createdAt = Timestamp.fromDate(DateTime(2026, 11, 17, 12));
    final shipment = ShipmentModel.fromData({
      'trackingCode': 'SHP-ABC123',
      'status': 'in_transit',
      'origin': {'name': 'Origin Hub', 'latitude': 26.9, 'longitude': 75.7},
      'currentLocation': const GeoPoint(27.1, 75.9),
      'estimatedDelivery': createdAt,
      'authorizedUserUids': ['user-1'],
      'createdAt': createdAt,
    }, documentId: 'shipment-1');

    expect(shipment.shipmentId, 'shipment-1');
    expect(shipment.status, 'in_transit');
    expect(shipment.origin?.hasCoordinates, isTrue);
    expect(shipment.currentLocation?.latitude, 27.1);
    expect(shipment.estimatedDelivery, createdAt.toDate());
    expect(shipment.destination, isNull);
    expect(shipment.authorizedUserUids, ['user-1']);
  });

  test('preserves unknown statuses without crashing', () {
    final shipment = ShipmentModel.fromData({
      'trackingCode': 'SHP-XYZ789',
      'status': 'future_status',
    }, documentId: 'shipment-2');

    expect(shipment.status, 'future_status');
    expect(shipment.origin, isNull);
    expect(shipment.destination, isNull);
    expect(shipment.currentLocation, isNull);
  });

  test('rejects shipment records without a tracking code', () {
    expect(
      () => ShipmentModel.fromData({}, documentId: 'shipment-3'),
      throwsStateError,
    );
  });

  test('parses shipment events without requiring optional fields', () {
    final event = ShipmentEventModel.fromData({
      'status': 'picked_up',
      'title': 'Shipment picked up',
      'timestamp': Timestamp.fromDate(DateTime(2026, 11, 17)),
      'location': const GeoPoint(26.9, 75.7),
    }, documentId: 'event-1');

    expect(event.eventId, 'event-1');
    expect(event.status, 'picked_up');
    expect(event.latitude, 26.9);
    expect(event.longitude, 75.7);
    expect(event.description, isNull);
  });
}
