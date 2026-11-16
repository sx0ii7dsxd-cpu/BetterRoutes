# BetterRoutes

> A Flutter-based route planning and logistics application for discovering
> places, calculating driving routes, and managing delivery workflows.

## Overview

BetterRoutes combines map-based route planning with early logistics features
for warehouses, trucks, and shipments. The application uses Firebase for
authentication, MapTiler for place search and optional map styling, OSRM for
driving-route calculation, and OpenStreetMap as a reliable map fallback.

The current version is a functional prototype. Route planning and map
interaction are connected to external services. Warehouse records use
temporary local SQLite storage for the college demonstration; this is not the
planned Firestore architecture.

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
- SQLite-backed warehouse markers with name labels and tap-for-details
- Locally saved places and a capped, deduplicated recent-search list
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

- SQLite-backed warehouse creation, search, editing, and deletion
- Warehouse address/contact details, generated warehouse codes, timestamps,
  and map-pinned coordinates
- Warehouse overview and truck-activity sections
- SQLite-backed business profiles and truck registration, search, details,
  editing, and confirmed deletion
- Truck/driver details linked to one owned business and one warehouse
- Pending truck-approval status and status filtering
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
| Temporary warehouse, profile, business, truck, saved-place, and recent-search storage | SQLite (`sqflite`) |
| Sharing | `share_plus` |
| Testing | Flutter Test |

## Project structure

```text
lib/
├── database/
│   └── app_database.dart       # SQLite initialization and schema migrations
├── models/
│   ├── business_model.dart     # Business data model
│   ├── database_timestamp.dart # Stable UTC database timestamp encoding
│   ├── place_identity.dart     # Stable saved/recent destination keys
│   ├── place_search_result.dart
│   ├── recent_search_model.dart
│   ├── saved_place_model.dart
│   ├── truck_model.dart        # Truck data model
│   ├── user_profile_model.dart # Local Firebase profile data
│   └── warehouse_model.dart    # Warehouse data model
├── repositories/
│   ├── business_repository.dart
│   ├── recent_search_repository.dart
│   ├── saved_place_repository.dart
│   ├── truck_repository.dart
│   ├── user_profile_repository.dart
│   └── warehouse_repository.dart
├── services/
│   ├── business_service.dart
│   ├── database_id_generator.dart
│   ├── recent_search_service.dart
│   ├── saved_place_service.dart
│   ├── truck_service.dart
│   ├── user_profile_service.dart
│   └── warehouse_service.dart
├── theme/
│   └── app_colors.dart        # Shared application colors
├── main.dart                    # Application entry point and theme
├── firebase_options.dart        # FlutterFire platform configuration
├── screens/
│   ├── splash_screen.dart        # Animated startup and auth routing
│   └── auth_screen.dart          # Login, registration, Google sign-in
└── pages/
    ├── map_page.dart             # Main map, search, navigation, menu
    ├── place_search_service.dart # MapTiler geocoding client
    ├── recent_searches_page.dart
    ├── saved_places_page.dart
    ├── route_planning_page.dart  # Route and stop selection
    ├── route_calculation_service.dart
    ├── route_navigation_progress.dart
    ├── route_preview_panel.dart
    ├── profile_menu.dart
    ├── business_management_page.dart
    ├── warehouse_page.dart          # Warehouse management UI
    ├── warehouse_location_picker.dart # OpenStreetMap coordinate picker
    ├── truck_registration_page.dart # Truck list, search, and CRUD UI
    ├── track_shipment_page.dart
    └── placeholder_page.dart

test/
├── route_calculation_service_test.dart
├── route_navigation_progress_test.dart
├── route_planning_page_test.dart
├── route_preview_panel_test.dart
├── saved_places_pages_test.dart
├── saved_places_service_test.dart
├── warehouse_service_test.dart
├── warehouse_location_picker_test.dart
└── widget_test.dart
```

## Getting started

Requirements: Flutter/Dart SDK `3.13.5` or newer, a configured Android or
iOS development environment, Firebase platform configuration, a MapTiler API
key for place suggestions, and a device or emulator. Warehouse map selection
uses OpenStreetMap tiles and does not require GPS permission; permission is
requested only if the optional current-location control is used.

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

- SQLite warehouse, business, and truck CRUD, search, validation, ownership,
  foreign-key deletion safety, and restart persistence
- Business deletion safeguards and the associated-truck management dialog
- Warehouse truck activity, truck details, and activity refresh after
  reassignment
- Version 1-to-3 SQLite migration preserving warehouse records and coordinates
- Version 2-to-3 migration preserving warehouses, profile, business, and truck
  records and relationships
- Saved-place deduplication, validation, local persistence, and removal
- Recent-search deduplication, ordering, 50-entry retention, clear/delete, and
  persistence
- Saved-place and recent-search selection and clear-history screens
- Local Firebase profile synchronization without storing passwords
- Warehouse map selection, confirmation, saved coordinates, and continuing
  manual selection after GPS permission denial
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
5. Dedicated services isolate MapTiler search, OSRM route requests, and local
   saved-place/recent-search persistence.
6. Warehouse, business, truck, local-profile, saved-place, and recent-search
   UI depend on service and repository contracts, so SQLite can be replaced
   without coupling SQL queries to widgets.
7. Reusable panels and pages handle route results and logistics workflows.

HTTP clients and service instances can be injected into route-related pages,
which keeps network-dependent tests deterministic and avoids real API calls
during widget tests.

## Current limitations

- Warehouse data is stored locally in SQLite for the demonstration. It is not
  synchronized between devices and will be replaced by the planned Firestore
  implementation.
- Business, local profile, and truck data are also stored locally in SQLite
  and are not synchronized between devices.
- The project does not define an agreed business schema. For this temporary
  phase, a business consists only of a name and Firebase owner UID; a user may
  own multiple businesses, and each truck references one business.
- Truck approval is stored as `pending`; administrator approval workflows are
  not implemented.
- Shipment tracking is a validated UI flow without a live shipment backend.
- Route alternatives are provided by OSRM, not a fleet-optimization engine.
- Turn-by-turn instructions are not implemented.
- Live navigation is a progress estimate, not a complete navigation system.
- Saved places and recent searches are stored locally on this installation;
  they are not synchronized between devices or Firebase accounts.
- Linux Firebase configuration is not currently generated.

## Temporary SQLite database (version 3)

The version-3 database retains the `warehouses` table, adds local profile,
business, and truck tables, and adds saved-place and recent-search tables.
It upgrades version-1 and version-2 installations without dropping existing
records.

The `warehouses` table contains:

| Column | SQLite type | Purpose |
|---|---|---|
| `id` | `TEXT PRIMARY KEY` | Generated UUID |
| `warehouse_code` | `TEXT UNIQUE` | Generated `WH-123456` code |
| `name`, `address`, `contact_name`, `contact_number` | `TEXT NOT NULL` | Existing warehouse form fields |
| `location_note` | `TEXT NOT NULL` | Optional existing location/landmark note |
| `latitude`, `longitude` | `REAL` | Numeric map coordinates; stored together |
| `created_at`, `updated_at` | `TEXT NOT NULL` | UTC ISO-8601 timestamps |

The `user_profiles` table stores a Firebase UID, display name, email, photo
URL, provider IDs, and timestamps. Firebase Authentication remains the
authentication authority; passwords and authentication tokens are not stored
in SQLite.

The `businesses` table contains an ID, owner Firebase UID, business name, and
timestamps. The name-only definition is a temporary minimal assumption
because no approved business model or field list exists in the source or
project documentation.

The `trucks` table contains an ID, unique registration number, existing truck
type, free-text capacity and optional details, driver name/contact number,
`warehouse_id`, `business_id`, approval status, and timestamps. Warehouse and
business details are referenced by foreign keys rather than copied into truck
rows. Foreign-key enforcement is enabled for every database connection, and
referenced warehouses or businesses cannot be deleted. Truck and business
deletions require explicit confirmation in the UI.

Warehouse address text is entered manually; the current map stack has no
reverse-geocoding integration.

The `saved_places` table stores a generated ID, a unique destination key,
place name/display name, optional address and provider ID, numeric latitude
and longitude, and a UTC saved timestamp. Places are deduplicated by provider
ID when available, otherwise by normalized coordinates and name.

The `recent_searches` table stores a unique destination key, the query, place
name/address, optional provider ID and coordinates, and a UTC searched
timestamp. Re-selecting a destination updates its existing row and timestamp;
only the 50 most recent destinations are retained. Entries without
coordinates can still be reopened through the existing place search.

Saved places and recent searches are device-local and are not tied to a
Firebase profile. The MapTiler result is applied directly to the map so its
coordinates and provider identity are retained; typed map searches use the
existing Nominatim geocoding flow.

The database is local to the app installation and intended only for the
demonstration. `sqflite` targets Android, iOS, and macOS; this temporary
implementation does not provide SQLite persistence on Flutter web, Windows,
or Linux.

## Roadmap

- Add Firestore models and security rules for warehouses and trucks
- Implement administrator approval for truck registrations
- Connect shipment lookup to real shipment events and locations
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
