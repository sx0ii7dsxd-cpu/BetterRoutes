# BetterRoutes

> A Flutter-based route planning and logistics application for discovering
> places, calculating driving routes, and managing delivery workflows.

## Overview

BetterRoutes combines map-based route planning with early logistics features
for warehouses, trucks, and shipments. The application uses Firebase for
authentication, MapTiler for place search and optional map styling, OSRM for
driving-route calculation, and OpenStreetMap as a reliable map fallback.

The current version is a functional prototype. Route planning and map
interaction are connected to external services, while logistics records are
currently held in local widget state and are not yet persisted to Firestore.

## Features

### Authentication

- Email/password sign in and account registration
- Google Sign-In through Firebase Authentication
- Password-reset emails
- Firebase error handling with user-friendly messages
- Authentication-aware splash routing
- Profile page with provider information and sign-out

### Maps and places

- Current-device location with permission handling
- Place search with debounced MapTiler geocoding suggestions
- OpenStreetMap tile rendering through `flutter_map`
- Optional MapLibre rendering with a MapTiler style
- Automatic fallback to OpenStreetMap if MapLibre is unavailable
- Selected-place details, sharing, and camera repositioning

### Route planning

- Origin and destination selection
- Searchable intermediate stops
- Origin/destination swapping
- OSRM driving routes with GeoJSON geometry
- Multiple route alternatives
- Distance, duration, and road-summary information
- Route preview, route editing, and route clearing
- Live progress estimation from GPS updates
- Off-route detection using a 100 metre threshold

### Logistics workflows

- Warehouse registration and generated warehouse codes
- Warehouse overview and truck-activity sections
- Truck and driver registration form
- Warehouse-code format validation
- Shipment ID validation and lookup state
- Clear prototype states for unavailable backend data

## Tech stack

| Area | Technology |
|---|---|
| Framework | Flutter |
| Language | Dart |
| Authentication | Firebase Authentication |
| Place search | MapTiler Geocoding API |
| Styled map | MapLibre GL |
| Fallback map | `flutter_map` + OpenStreetMap |
| Routing | OSRM |
| Location | Geolocator |
| Sharing | `share_plus` |
| Testing | Flutter Test |

## Project structure

```text
lib/
├── main.dart                    # Application entry point and theme
├── firebase_options.dart        # FlutterFire platform configuration
├── screens/
│   ├── splash_screen.dart        # Animated startup and auth routing
│   └── auth_screen.dart          # Login, registration, Google sign-in
└── pages/
    ├── map_page.dart             # Main map, search, navigation, menu
    ├── place_search_service.dart # MapTiler geocoding client
    ├── route_planning_page.dart  # Route and stop selection
    ├── route_calculation_service.dart
    ├── route_navigation_progress.dart
    ├── route_preview_panel.dart
    ├── profile_menu.dart
    ├── warehouse_page.dart
    ├── truck_registration_page.dart
    ├── track_shipment_page.dart
    └── placeholder_page.dart

test/
├── route_calculation_service_test.dart
├── route_navigation_progress_test.dart
├── route_planning_page_test.dart
├── route_preview_panel_test.dart
└── widget_test.dart
```

## Getting started

Requirements: Flutter/Dart SDK `3.13.5` or newer, a configured Android or
iOS development environment, Firebase platform configuration, a MapTiler API
key, and a device or emulator with location support.

Clone the repository and install dependencies:

```bash
git clone https://github.com/sx0ii7dsxd-cpu/BetterRoutes.git
cd BetterRoutes/BetterRoutes
flutter pub get
```

Create a local `.env.maptiler.json` file from
`.env.maptiler.example.json`:

```json
{
  "MAPTILER_STYLE_ID": "your-style-id",
  "MAPTILER_API_KEY": "your-api-key"
}
```

Run the application:

```bash
flutter run --dart-define-from-file=.env.maptiler.json
```

The environment file is ignored by Git. Never commit API keys or private
credentials. A valid MapTiler key is required for place suggestions; the map
can fall back to OpenStreetMap when MapLibre configuration is unavailable.

## Testing and quality checks

Run the analyzer and test suite from the project root:

```bash
flutter analyze
flutter test
```

The tests cover:

- OSRM request construction and response validation
- Multiple routes and intermediate stops
- Invalid coordinates and malformed route geometry
- Navigation progress and off-route detection
- Route-planner search, swapping, and callbacks
- Route-preview actions and displayed route details

## Architecture

The application uses a lightweight Flutter page-and-service architecture:

1. `main.dart` initializes Firebase and starts the app.
2. `SplashScreen` selects the welcome or authenticated route.
3. `AuthScreen` performs Firebase authentication.
4. `MapPage` coordinates location, search, map rendering, routes, and menus.
5. Dedicated services isolate MapTiler search and OSRM route requests.
6. Reusable panels and pages handle route results and logistics workflows.

HTTP clients and service instances can be injected into route-related pages,
which keeps network-dependent tests deterministic and avoids real API calls
during widget tests.

## Current limitations

- Warehouse and truck data are not persisted.
- Shipment tracking is a validated UI flow without a live shipment backend.
- Warehouse-code validation currently checks format only.
- Route alternatives are provided by OSRM, not a fleet-optimization engine.
- Turn-by-turn instructions are not implemented.
- Live navigation is a progress estimate, not a complete navigation system.
- Saved places and recent searches are placeholders.
- Linux Firebase configuration is not currently generated.

## Roadmap

- Add Firestore models and security rules for warehouses and trucks
- Implement administrator approval for truck registrations
- Connect shipment lookup to real shipment events and locations
- Add saved places and recent searches
- Add turn-by-turn route instructions
- Add delivery orders, vehicle capacity, and route optimization
- Add release signing, CI builds, crash reporting, and production monitoring

## Data and attribution

Map functionality uses MapTiler, OpenStreetMap, and OSRM services. Follow the
terms, attribution requirements, rate limits, and API-key restrictions of each
provider before deploying the application publicly.

## License

No license has been declared for this project yet. Add a license file before
distributing the application or accepting external contributions.
