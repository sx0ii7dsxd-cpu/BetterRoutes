import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/shipment_model.dart';
import '../models/saved_place_model.dart';
import '../models/truck_registration_model.dart';
import '../models/warehouse_model.dart';
import '../pages/place_search_service.dart';
import 'warehouse_code_generator.dart';
import 'trusted_operations_service.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _warehouses =>
      _firestore.collection('warehouses');

  CollectionReference<Map<String, dynamic>> get _truckRequests =>
      _firestore.collection('truckRegistrationRequests');

  CollectionReference<Map<String, dynamic>> get _shipments =>
      _firestore.collection('shipments');

  CollectionReference<Map<String, dynamic>> get _warehouseCodeReservations =>
      _firestore.collection('warehouseCodeReservations');

  CollectionReference<Map<String, dynamic>> _userCollection(String name) {
    final user = _requireUser();
    return _firestore.collection('users').doc(user.uid).collection(name);
  }

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to use this feature.');
    }
    return user;
  }

  Future<WarehouseModel> createWarehouse({
    required String name,
    required String address,
    required String contactName,
    required String contactNumber,
    required String location,
    required double? latitude,
    required double? longitude,
  }) async {
    final user = _requireUser();
    for (var attempt = 0; attempt < 20; attempt++) {
      final document = _warehouses.doc();
      final warehouseId = document.id;
      final code = generateWarehouseCode();
      final reservation = _warehouseCodeReservations.doc(code);
      final now = FieldValue.serverTimestamp();

      try {
        await _firestore.runTransaction((transaction) async {
          final existingReservation = await transaction.get(reservation);
          if (existingReservation.exists) {
            throw const _WarehouseCodeCollision();
          }

          transaction.set(reservation, {
            'warehouseId': warehouseId,
            'ownerUid': user.uid,
          });
          transaction.set(document, {
            'warehouseId': warehouseId,
            'code': code,
            'name': name.trim(),
            'address': address.trim(),
            'contactName': contactName.trim(),
            'contactNumber': contactNumber.trim(),
            'location': location.trim(),
            'latitude': latitude,
            'longitude': longitude,
            'ownerUid': user.uid,
            'createdAt': now,
            'updatedAt': now,
          });
        });

        return WarehouseModel.fromFirestore(await document.get());
      } on _WarehouseCodeCollision {
        continue;
      }
    }

    throw StateError(
      'Could not reserve a unique warehouse code. Please try again.',
    );
  }

  Future<List<WarehouseModel>> getMyWarehouses() async {
    final user = _requireUser();
    final snapshot = await _warehouses
        .where('ownerUid', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map(WarehouseModel.fromFirestore).toList();
  }

  Stream<List<WarehouseModel>> watchMyWarehouses() {
    final user = _requireUser();
    return _warehouses
        .where('ownerUid', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(WarehouseModel.fromFirestore).toList(),
        );
  }

  Future<void> updateWarehouse({
    required WarehouseModel warehouse,
    required String name,
    required String address,
    required String contactName,
    required String contactNumber,
    required String location,
    required double? latitude,
    required double? longitude,
  }) async {
    final user = _requireUser();
    if (warehouse.ownerUid != user.uid) {
      throw StateError('You are not authorized to update this warehouse.');
    }

    await _warehouses.doc(warehouse.warehouseId).update({
      'name': name.trim(),
      'address': address.trim(),
      'contactName': contactName.trim(),
      'contactNumber': contactNumber.trim(),
      'location': location.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteWarehouse(String warehouseId) async {
    _requireUser();
    final trustedService = TrustedOperationsService(auth: _auth);
    try {
      await trustedService.deleteWarehouse(warehouseId);
    } finally {
      trustedService.dispose();
    }
  }

  Stream<List<SavedPlaceModel>> watchSavedPlaces() =>
      _userCollection('savedPlaces')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(SavedPlaceModel.fromFirestore).toList(),
          );

  Future<void> savePlace(PlaceSearchResult place) async {
    final places = _userCollection('savedPlaces');
    final existing = await places
        .where('displayName', isEqualTo: place.displayName)
        .limit(1)
        .get();
    final reference = existing.docs.isEmpty
        ? places.doc()
        : existing.docs.first.reference;
    await reference.set({
      'name': place.name,
      'displayName': place.displayName,
      'address': place.address,
      'latitude': place.latitude,
      'longitude': place.longitude,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteSavedPlace(String placeId) async {
    await _userCollection('savedPlaces').doc(placeId).delete();
  }

  Stream<List<SavedPlaceModel>> watchRecentSearches() =>
      _userCollection('recentSearches')
          .orderBy('searchedAt', descending: true)
          .limit(20)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(SavedPlaceModel.fromFirestore).toList(),
          );

  Future<void> addRecentSearch(PlaceSearchResult place) async {
    final searches = _userCollection('recentSearches');
    final existing = await searches
        .where('displayName', isEqualTo: place.displayName)
        .limit(1)
        .get();
    final reference = existing.docs.isEmpty
        ? searches.doc()
        : existing.docs.first.reference;
    await reference.set({
      'name': place.name,
      'displayName': place.displayName,
      'address': place.address,
      'latitude': place.latitude,
      'longitude': place.longitude,
      'searchedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clearRecentSearches() async {
    final snapshot = await _userCollection('recentSearches').get();
    final batch = _firestore.batch();
    for (final document in snapshot.docs) {
      batch.delete(document.reference);
    }
    await batch.commit();
  }

  Future<WarehouseModel?> findMyWarehouseByCode(String code) async {
    final user = _requireUser();
    final normalizedCode = code.trim().toUpperCase();
    final snapshot = await _warehouses
        .where('ownerUid', isEqualTo: user.uid)
        .where('code', isEqualTo: normalizedCode)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return WarehouseModel.fromFirestore(snapshot.docs.single);
  }

  Future<TruckRegistrationModel> submitTruckRegistration({
    required String registrationNumber,
    required String truckType,
    required double capacity,
    required String? capacityUnit,
    required String? details,
    required String driverName,
    required String driverContactNumber,
    required String warehouseCode,
  }) async {
    final user = _requireUser();
    final warehouse = await findMyWarehouseByCode(warehouseCode);
    if (warehouse == null) {
      throw StateError('That warehouse code is invalid or not owned by you.');
    }

    final document = _truckRequests.doc();
    final now = FieldValue.serverTimestamp();
    await document.set({
      'requestId': document.id,
      'registrationNumber': registrationNumber.trim().toUpperCase(),
      'truckType': truckType,
      'capacity': capacity,
      if (capacityUnit != null && capacityUnit.trim().isNotEmpty)
        'capacityUnit': capacityUnit.trim(),
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
      'driverName': driverName.trim(),
      'driverContactNumber': driverContactNumber.trim(),
      'warehouseId': warehouse.warehouseId,
      'warehouseCode': warehouse.code,
      'requestedByUid': user.uid,
      'status': 'pending',
      'createdAt': now,
      'updatedAt': now,
    });

    return TruckRegistrationModel.fromFirestore(await document.get());
  }

  Future<List<TruckRegistrationModel>> getMyTruckRegistrationRequests() async {
    final user = _requireUser();
    final snapshot = await _truckRequests
        .where('requestedByUid', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map(TruckRegistrationModel.fromFirestore).toList();
  }

  Stream<List<TruckRegistrationModel>> watchMyTruckRegistrationRequests() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.error(
        StateError('You must be signed in to use this feature.'),
      );
    }

    return _truckRequests
        .where('requestedByUid', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(TruckRegistrationModel.fromFirestore).toList(),
        );
  }

  Future<ShipmentModel?> findShipmentByTrackingCode(String trackingCode) async {
    final user = _requireUser();
    final normalizedCode = trackingCode.trim().toUpperCase();
    final snapshot = await _shipments
        .where('trackingCode', isEqualTo: normalizedCode)
        .where('authorizedUserUids', arrayContains: user.uid)
        .get();
    if (snapshot.docs.isEmpty) return null;
    if (snapshot.docs.length > 1) {
      throw StateError('Multiple shipments use this tracking code.');
    }
    return ShipmentModel.fromFirestore(snapshot.docs.single);
  }

  Future<ShipmentModel?> getShipmentById(String shipmentId) async {
    _requireUser();
    final snapshot = await _shipments.doc(shipmentId).get();
    if (!snapshot.exists) return null;
    return ShipmentModel.fromFirestore(snapshot);
  }

  Stream<ShipmentModel?> watchShipment(String shipmentId) {
    _requireUser();
    return _shipments
        .doc(shipmentId)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.exists ? ShipmentModel.fromFirestore(snapshot) : null,
        );
  }

  Future<List<ShipmentEventModel>> getShipmentEvents(String shipmentId) async {
    _requireUser();
    final snapshot = await _shipments
        .doc(shipmentId)
        .collection('events')
        .orderBy('timestamp', descending: true)
        .get();
    return snapshot.docs.map(ShipmentEventModel.fromFirestore).toList();
  }

  Stream<List<ShipmentEventModel>> watchShipmentEvents(String shipmentId) {
    _requireUser();
    return _shipments
        .doc(shipmentId)
        .collection('events')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(ShipmentEventModel.fromFirestore).toList(),
        );
  }
}

class _WarehouseCodeCollision implements Exception {
  const _WarehouseCodeCollision();
}
