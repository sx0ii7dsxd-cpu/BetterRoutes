import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:better_routes/pages/warehouse_location_picker.dart';

void main() {
  testWidgets(
    'manual map selection confirms coordinates after current-location denial',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      LatLng? selectedLocation;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selectedLocation = await Navigator.of(context).push<LatLng>(
                    MaterialPageRoute<LatLng>(
                      builder: (_) => WarehouseLocationPicker(
                        currentLocationProvider: () async {
                          throw const WarehouseLocationException(
                            'Location permission was denied.',
                          );
                        },
                        tileProvider: _FailingTileProvider(),
                      ),
                    ),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byTooltip('Use current location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Map tiles could not load.'), findsOneWidget);
      expect(
        find.textContaining('Location permission was denied.'),
        findsOneWidget,
      );
      expect(find.byType(FlutterMap), findsOneWidget);

      final Finder map = find.byType(FlutterMap);
      await tester.drag(map, const Offset(70, 40));
      await tester.pumpAndSettle();
      expect(find.text('Selected location'), findsOneWidget);
      await tester.tap(find.text('Confirm location'));
      await tester.pumpAndSettle();

      expect(find.byType(FlutterMap), findsNothing);
      expect(selectedLocation, isNotNull);
      expect(selectedLocation!.latitude, inInclusiveRange(-90, 90));
      expect(selectedLocation!.longitude, inInclusiveRange(-180, 180));
    },
  );

  testWidgets('editing starts at the saved coordinates', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: WarehouseLocationPicker(
          initialLatitude: 26.9124,
          initialLongitude: 75.7873,
          tileProvider: _OfflineTileProvider(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('26.912400, 75.787300'), findsOneWidget);
    expect(find.text('Confirm location'), findsOneWidget);
  });
}

class _FailingTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return const AssetImage('missing-map-tile.png');
  }
}

class _OfflineTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MemoryImage(TileProvider.transparentImage);
  }
}
