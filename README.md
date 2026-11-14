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
The sun/moon control switches between the configured MapTiler style and
MapTiler's dark Streets style. Without a MapTiler key, it switches between
OpenStreetMap's standard tiles and CARTO's dark tiles.

Run the app with:

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
The Android project already declares Internet and location permissions and
uses a minimum SDK above MapLibre's Android API 21 requirement. MapLibre
`0.27.1` requires JDK 21 or newer; use a compatible JDK for Android builds.

## Email change verification

Changing the account email uses a Node.js API deployed to Vercel and
server-only Firebase Admin SDK access to Auth and Firestore. Each request sends
the current Firebase ID token for server-side verification. One six-digit code
is sent through Resend to the current email; after it is verified, Firebase
Auth is updated to the new email. The new address is not marked as verified by
this flow. Codes expire after 10 minutes, failed attempts are limited, resends
are cooled down and capped, and an unfinished request can be resumed. A
different email change cannot start until the 24-hour request window expires.
Google sign-in continues to use the same Google account; only the
BetterRoutes/Firebase account email changes.

The Vercel API is in `functions/` and exposes
`POST /api/email-change` with the actions `emailChangeStatus`,
`startEmailChange` (`newEmail`), `verifyOldEmailCode` (`code`), and
`resendEmailChangeCode`. Successful responses retain the existing status
fields; API errors use `{ "error": { "code", "message", "details" } }`.
Firestore rules continue to deny client access to the private flow and rate
limit documents.

To deploy without Firebase Cloud Functions or requiring Firebase Blaze:

1. Make sure Cloud Firestore is initialized in the existing Firebase project,
   and verify the sender domain in Resend.
2. Create a Vercel project from this repository and set its **Root Directory**
   to `functions`. Deploy it as a Node.js project (Node 22).
3. Add these environment variables in the Vercel project settings. Keep the
   service-account JSON and API secrets server-side; never put them in Flutter,
   source control, or chat:

   - `FIREBASE_PROJECT_ID`: `betterroutes-79436`
   - `FIREBASE_SERVICE_ACCOUNT_JSON`: the complete JSON for a dedicated
     Firebase service account with the required Auth and Firestore access
   - `RESEND_API_KEY`: the Resend API key
   - `OTP_HMAC_SECRET`: a randomly generated secret (for example,
     `openssl rand -hex 32`)
   - `EMAIL_FROM`: a sender on the verified Resend domain, such as
     `BetterRoutes <security@example.com>`
   - `EMAIL_CHANGE_ALLOWED_ORIGINS` (optional): comma-separated web-app origins
     allowed to call the API from a browser

4. Deploy the Vercel project and set the API URL in Flutter builds. For
   example:

   ```sh
   flutter run -d YXVCOZ4DCQQC5XYT \
     --dart-define-from-file=.env.maptiler.json \
     --dart-define=EMAIL_CHANGE_API_URL=https://YOUR_PROJECT.vercel.app/api/email-change
   ```

   Use the same `EMAIL_CHANGE_API_URL` define for release builds. The URL is
   not a secret. The client sends an ID token on each request; Resend and
   service-account credentials remain on Vercel.

Vercel Hobby has plan-specific usage limits and is intended for non-commercial
projects; review Vercel's current terms and limits before deploying.
