# BetterRoutes

## Project report and implementation reference

BetterRoutes is a Flutter application for location discovery, route planning,
navigation assistance, and logistics workflow management. The application is
designed around a dark, mobile-first interface with a purple/amethyst visual
identity. It currently combines:

- Firebase authentication
- Device location and permission handling
- Searchable map locations
- OpenStreetMap fallback map rendering
- Optional MapLibre/MapTiler map styling
- MapTiler geocoding suggestions
- OSRM driving-route calculation
- Multiple route alternatives
- Intermediate route stops
- Route preview and route-detail panels
- Live navigation progress estimation and off-route detection
- Warehouse registration
- Truck registration request flow
- Shipment ID lookup flow
- User profile and sign-out

This document is intentionally detailed so it can be used as the technical
source material for a Word report, project demonstration, viva, or
implementation handover.

> **Implementation status:** The map and route-planning features are
> functional prototypes connected to external map/routing services. Warehouse
> registration, truck registration, and shipment tracking currently provide
> polished UI flows with local/in-memory state and validation. They are not yet
> connected to Firestore or a production logistics backend.

---

## 1. Executive summary

BetterRoutes addresses two related use cases:

1. **Personal or operational route planning**
   - Find a place by name.
   - View it on a map.
   - Select a starting point, destination, and optional intermediate stops.
   - Request one or more driving routes.
   - Compare route distance, estimated duration, and route summaries.
   - Start a location-aware navigation preview.

2. **Logistics operations**
   - Register a warehouse and generate a warehouse code.
   - Review the warehouse overview and truck activity sections.
   - Submit a truck and driver registration request against a warehouse code.
   - Look up a shipment by a validated shipment ID format.

The application starts with an animated branded splash screen. It then
branches according to Firebase authentication state:

```text
Application start
    |
    v
Firebase.initializeApp(...)
    |
    v
Animated splash screen
    |
    +-- Signed out --> Welcome screen --> Login/register
    |                                      |
    |                                      v
    |                                  Firebase Auth
    |
    +-- Signed in ------------------------------+
                                                   |
                                                   v
                                                Map page
```

After successful email/password or Google authentication, the user is taken
to the map page. The profile page can sign the user out and return to the
welcome screen.

---

## 2. Current implementation at a glance

### Implemented and connected

- Flutter application shell and Material 3 theme.
- Firebase initialization through generated FlutterFire configuration.
- Email/password sign in.
- Email/password account creation.
- Display-name update during account creation.
- Google sign-in using `google_sign_in`.
- Firebase password-reset email.
- Authentication-specific user-facing error messages.
- Authentication-aware splash routing.
- Device location service and permission checks.
- Current-location map centering.
- MapTiler geocoding search suggestions.
- OpenStreetMap tile map fallback.
- MapLibre map rendering when a valid MapTiler configuration is supplied.
- Automatic fallback from MapLibre to the standard map when the custom style
  does not load or cannot be controlled.
- Selected-place details, directions, sharing, and map positioning.
- OSRM route requests with GeoJSON geometry.
- Alternative route calculation when no intermediate stops are selected.
- Ordered multi-stop route calculation.
- Route geometry validation and malformed-response handling.
- Route preview with alternative selection.
- Route camera fitting around the selected route.
- Location-based navigation progress estimation.
- Off-route detection using a 100 metre threshold.
- Monotonic navigation progress so the displayed progress does not move
  backwards when GPS readings fluctuate.
- Warehouse form validation and generated warehouse code.
- Truck form validation and warehouse-code format checking.
- Shipment ID format validation and lookup-state presentation.
- Profile display, provider information, avatar initials, and sign-out.
- Focused unit and widget coverage for route services and route UI.

### Present but intentionally incomplete

- Warehouse records are not persisted.
- Truck requests are not persisted or sent for administrator approval.
- Warehouse-code validation checks the format only; it does not query
  Firestore.
- Shipment lookup does not query a shipment data source.
- The shipment result card explicitly reports that shipment data is
  unavailable.
- The home quick-action card for route planning still displays a
  “coming soon” message; route planning is currently reached through a
  selected place’s **Directions** action.
- Saved places and recent searches are UI placeholders.
- Route optimization is not implemented. OSRM alternatives are displayed, but
  there is no business-specific fleet optimization algorithm.
- Turn-by-turn instructions are not generated because route requests use
  `steps=false`.
- There is no backend role model, warehouse administrator workflow, driver
  workflow, shipment event stream, or Firestore data layer yet.
- Linux Firebase options are not configured in the generated configuration.

---

## 3. Technology stack

### Application technology

| Area | Technology |
|---|---|
| Cross-platform framework | Flutter |
| Primary language | Dart |
| UI | Flutter Material 3 |
| Authentication | Firebase Authentication |
| Google authentication | `google_sign_in` |
| Maps fallback | `flutter_map` with OpenStreetMap tiles |
| Optional styled map | `maplibre_gl` with MapTiler style JSON |
| Place search | MapTiler Geocoding API |
| Routing | OSRM public routing service |
| Location | `geolocator` |
| Map coordinates | `latlong2` and MapLibre coordinate types |
| HTTP | `http` |
| Sharing | `share_plus` |
| Testing | `flutter_test`, `http/testing.dart` |
| Android build | Gradle Kotlin DSL, Android Gradle Plugin, Kotlin |

### Declared package dependencies

The direct dependencies are declared in [`pubspec.yaml`](./pubspec.yaml):

- `cupertino_icons` for Cupertino icon support.
- `flutter_map` for OpenStreetMap tile rendering and fallback polylines.
- `firebase_auth` for account authentication.
- `firebase_core` for Firebase startup.
- `google_sign_in` for Google account authentication.
- `http` for MapTiler and OSRM requests.
- `geolocator` for location services and permission handling.
- `latlong2` for the fallback map coordinate model.
- `maplibre_gl` for the optional MapTiler-styled map.
- `share_plus` for sharing selected-place links.

The exact resolved dependency graph is captured in
[`pubspec.lock`](./pubspec.lock).

---

## 4. Repository structure

```text
BetterRoutes/
├── assets/
│   └── images/
│       └── BetterRoutes.png
├── android/
│   ├── app/
│   │   ├── build.gradle.kts
│   │   ├── google-services.json
│   │   └── src/main/
│   │       ├── AndroidManifest.xml
│   │       └── kotlin/com/betterroutes/app/MainActivity.kt
│   ├── build.gradle.kts
│   └── settings.gradle.kts
├── ios/
│   ├── Runner/
│   ├── Runner.xcodeproj/
│   ├── Runner.xcworkspace/
│   └── GoogleService-Info.plist
├── lib/
│   ├── main.dart
│   ├── firebase_options.dart
│   ├── pages/
│   │   ├── map_page.dart
│   │   ├── place_search_service.dart
│   │   ├── profile_menu.dart
│   │   ├── placeholder_page.dart
│   │   ├── route_calculation_service.dart
│   │   ├── route_navigation_progress.dart
│   │   ├── route_planning_page.dart
│   │   ├── route_preview_panel.dart
│   │   ├── track_shipment_page.dart
│   │   ├── truck_registration_page.dart
│   │   └── warehouse_page.dart
│   └── screens/
│       ├── auth_screen.dart
│       └── splash_screen.dart
├── test/
│   ├── route_calculation_service_test.dart
│   ├── route_navigation_progress_test.dart
│   ├── route_planning_page_test.dart
│   ├── route_preview_panel_test.dart
│   └── widget_test.dart
├── .env.maptiler.example.json
├── .env.maptiler.json
├── analysis_options.yaml
├── BetterRoutes-Project-Review.txt
├── firebase.json
├── pubspec.yaml
└── pubspec.lock
```

Generated directories such as `build/`, `.dart_tool/`, and platform
intermediate files are build outputs and are not application source.

---

## 5. Application startup and navigation

### `lib/main.dart`

The `main()` function:

1. Calls `WidgetsFlutterBinding.ensureInitialized()`.
2. Initializes Firebase with
   `DefaultFirebaseOptions.currentPlatform`.
3. Starts `BetterRoutesApp`.

`BetterRoutesApp` configures:

- Application title: `BetterRoutes`.
- Material 3.
- White default scaffold background for the outer app theme.
- A seed color of `0xFFB39DDB`.
- Roboto as the default font family.
- `SplashScreen` as the initial page.

The `HomePage` is the signed-out welcome screen. It displays the BetterRoutes
asset, the slogan “Every journey, made better.”, supporting copy, and a
**Get Started** button that opens `AuthScreen`.

### `lib/screens/splash_screen.dart`

The splash screen is more than a static loading page:

- It animates the BetterRoutes brand opacity.
- It displays the logo and “Smarter routes. Better journeys.”.
- It draws a road scene and moves a truck from right to left.
- The route transition begins after approximately four seconds.
- The destination is selected from `FirebaseAuth.instance.currentUser`.
- Signed-out users go to `HomePage`.
- Signed-in users go directly to `MapPage`.
- The transition uses a short fade and scale animation.
- Timers and animation controllers are disposed correctly.

This means a previously authenticated user does not need to pass through the
login screen on every launch.

### Main authenticated navigation

`MapPage` acts as the authenticated application hub. It can open:

- `ProfileMenu`
- `WarehousePage`
- `TruckRegistrationPage`
- `TrackShipmentPage`
- `RoutePlanningPage` through selected-place directions
- Bottom sheets for selected-place details, route preview, and map actions

Pages use Flutter navigation routes and return route-plan data from
`RoutePlanningPage` to `MapPage`.

---

## 6. Authentication implementation

### `lib/screens/auth_screen.dart`

`AuthScreen` supports two modes:

- Existing-user sign in.
- New-account registration.

The registration form adds a full-name field. After account creation, the
name is stored with `FirebaseAuth.currentUser.updateDisplayName`.

### Email/password flow

The email/password flow:

1. Validates the form.
2. Sets a loading state to disable duplicate submissions.
3. Calls either:
   - `signInWithEmailAndPassword`, or
   - `createUserWithEmailAndPassword`.
4. Shows a success message.
5. Clears the navigation stack and opens `MapPage`.

Special handling improves the user experience:

- A missing or invalid credential can switch the screen to registration mode.
- An already-registered email can switch back to sign-in mode.
- Firebase error codes are converted into readable messages.
- Network, password-strength, rate-limit, and invalid-email cases are
  surfaced to the user.

### Google sign-in flow

The Google flow:

1. Initializes the Google sign-in singleton with the configured server client
   ID.
2. Starts Google authentication.
3. Reads the returned ID token.
4. Creates a Firebase Google credential.
5. Calls `FirebaseAuth.instance.signInWithCredential`.
6. Navigates to `MapPage` after success.

Configuration failures and authentication failures are shown as a snackbar
instead of being silently ignored.

### Password reset

The password-reset action:

- Requires a syntactically valid email.
- Calls `sendPasswordResetEmail`.
- Reports success or Firebase errors using the shared message behavior.

### `lib/pages/profile_menu.dart`

The profile page reads the current Firebase `User` and displays:

- Display name, with email-prefix fallback.
- Email address.
- Sign-in provider, such as Google or email/password.
- Network profile image where available.
- Initials fallback when no image is available.

The **Sign out** action calls Firebase sign-out and returns to `HomePage`.

---

## 7. Location and map system

### `lib/pages/map_page.dart`

`MapPage` is the largest application page and coordinates:

- Location state.
- Search state.
- Map renderer state.
- Selected place state.
- Route-plan state.
- Navigation-progress state.
- Logistics-page navigation.

### Location state machine

The page uses the following internal states:

```text
checking
ready
serviceDisabled
denied
deniedForever
```

The startup location process:

1. Checks whether device location services are enabled.
2. Checks existing permission.
3. Requests permission when it is denied but requestable.
4. Handles permanently denied permission separately.
5. Obtains a high-accuracy current position.
6. Stores the position and renders the map.

The UI provides actions for:

- Opening application settings for permanently denied permission.
- Opening device location settings when location services are disabled.
- Retrying location resolution.

Location errors are translated into a user-facing state panel. The page does
not assume location is always available; route planning can represent an
empty starting field when current location cannot be obtained.

### OpenStreetMap fallback renderer

The fallback map uses `flutter_map` and the public tile URL:

```text
https://tile.openstreetmap.org/{z}/{x}/{y}.png
```

It renders:

- Current-position marker.
- Searched-place marker.
- Route start marker.
- Intermediate-stop markers.
- Destination marker.
- Alternative route polylines.
- A highlighted selected route polyline.
- OpenStreetMap attribution.

The fallback route camera uses `CameraFit.coordinates` and leaves bottom
space for the route-preview panel.

### MapLibre/MapTiler renderer

When the MapTiler API key and style ID are configured, `MapPage` attempts to
use `maplibre_gl`:

- The style URL is generated from the MapTiler style ID and API key.
- The map waits for the style to load.
- Route lines are drawn as MapLibre line annotations.
- Current location, searched locations, stops, origin, and destination are
  drawn as MapLibre circle annotations.
- The camera can animate to a searched location or route bounds.

The MapLibre path is guarded by a timeout. If the style does not load within
the configured period, or a platform error occurs while drawing or controlling
the map, the page:

1. Disables the MapLibre renderer.
2. Clears the MapLibre controller state.
3. Displays a message.
4. Continues with the OpenStreetMap fallback.

This fallback is important because the map remains usable when MapTiler
configuration, network access, native map support, or style loading fails.

### Place search

The search bar:

- Requires at least two characters before requesting suggestions.
- Debounces requests by approximately 400 milliseconds.
- Tracks a generation number so stale asynchronous responses are ignored.
- Uses the current position as a proximity hint when available.
- Shows a list of suggestions beneath the search field.
- Moves the camera to the selected result.
- Stores the result name, address, and coordinates.

After a place is selected, the bottom panel offers:

- **Directions**: opens route planning.
- **Share**: creates an OpenStreetMap coordinate URL and opens the platform
  share sheet.
- **Details**: opens a detail sheet with the selected place data.

### Map bottom panels

The lower map sheet changes according to application state:

1. **Project panel**
   - Plan a route card.
   - Saved places card.
   - Track delivery card.
   - Recent searches card.

2. **Selected-place panel**
   - Selected place name and address.
   - Directions, share, and details actions.

3. **Route preview panel**
   - Route endpoints and intermediate stops.
   - Alternative route cards.
   - Start and exit navigation controls.
   - Route details.
   - Edit stops.
   - Clear route.
   - Navigation status and off-route messaging.

The sheet is implemented with a draggable scrollable layout so it can coexist
with the map and remain usable on smaller screens.

---

## 8. Place search service

### `lib/pages/place_search_service.dart`

`PlaceSearchService` is a small HTTP client around the MapTiler Geocoding API.
It exposes:

```dart
Future<List<PlaceSearchResult>> search(
  String rawQuery, {
  double? proximityLatitude,
  double? proximityLongitude,
});
```

### `PlaceSearchResult`

Each result contains:

- `name`: short feature name.
- `displayName`: complete display label.
- `address`: optional address suffix.
- `latitude`.
- `longitude`.

### Request behavior

Requests are made to:

```text
https://api.maptiler.com/geocoding/<query>.json
```

with:

- The configured API key.
- Autocomplete enabled.
- A maximum of ten results.
- English language.
- Country limited to India.
- Optional longitude/latitude proximity.
- An eight-second timeout.

### Response validation

The service validates:

- HTTP success status.
- A map-shaped JSON response.
- A `features` list.
- A coordinate array.
- Numeric finite coordinates.
- Latitude range `-90..90`.
- Longitude range `-180..180`.
- Non-empty display labels.

Invalid features are skipped. Invalid service-level responses are reported
through `PlaceSearchException` or a format error, allowing the page to show a
useful search message.

### Resource ownership

The service accepts an optional `http.Client`. When it creates the client
itself, it owns and closes it in `dispose()`. This makes the service easier to
test and prevents the page from closing a shared client accidentally.

---

## 9. Route planning

### `lib/pages/route_planning_page.dart`

The route planner is a stateful page that supports:

- Starting location.
- Destination.
- Zero or more intermediate stops.
- Search suggestions for every location field.
- Swapping origin and destination.
- Removing a stop.
- Adding a new stop.
- Route calculation.
- Returning a `RoutePlanResult` to the map page.

The page can receive initial locations from `MapPage`. It also accepts
optional injected `PlaceSearchService` and `RouteCalculationService`
instances, which keeps the page testable and allows ownership to be explicit.

### Search-field behavior

Each location field:

- Uses its own controller and focus node.
- Debounces search input.
- Clears the selected coordinate when the text changes.
- Ignores stale search responses using a generation counter.
- Shows loading, no-results, missing-key, and service-error messages.
- Stores the complete selected `PlaceSearchResult` when a suggestion is
  tapped.

Swapping locations also reverses intermediate stops so the route remains
logically ordered.

### Route validation

Before a request is made, the planner verifies that:

- A valid origin has been selected.
- A valid destination has been selected.
- Every intermediate stop has a valid selected coordinate.

Typing arbitrary text without selecting a suggestion does not create an
accidental route coordinate.

### Route result

The planner returns:

```dart
RoutePlanResult(
  from: ...,
  to: ...,
  viaStops: ...,
  routes: ...,
)
```

The map page receives this result, draws the route, fits the camera, and
displays the route preview sheet.

---

## 10. Route calculation service

### `lib/pages/route_calculation_service.dart`

`RouteCalculationService` calls the public OSRM endpoint:

```text
https://router.project-osrm.org/route/v1/driving/<coordinates>
```

Coordinates are sent in OSRM’s required `longitude,latitude` order.

### Request parameters

Every request uses:

- `overview=full`
- `geometries=geojson`
- `steps=false`

When there are no intermediate stops:

- `alternatives=true`

When intermediate stops exist:

- `alternatives=false`

The service sends the route through all selected waypoints in their displayed
order:

```text
from;via-stop-1;via-stop-2;to
```

### Route models

#### `RouteCoordinate`

Stores a latitude and longitude pair.

#### `OsrmRoute`

Stores:

- Full route geometry.
- Distance in metres.
- Duration in seconds.
- Optional OSRM weight name.
- Optional distinct road summaries combined from route legs.

#### `RoutePlanResult`

Stores:

- Origin.
- Destination.
- Intermediate stops.
- One or more OSRM routes.

### Response and error handling

The service handles:

- Request timeout after 20 seconds.
- Connection failures.
- Socket failures.
- TLS failures.
- Non-200 HTTP responses.
- Malformed JSON.
- Missing or invalid OSRM response shape.
- `NoRoute`.
- Other OSRM error codes.
- Empty route arrays.
- Invalid route geometry.

Each route is parsed independently. A malformed alternative is discarded
while valid alternatives are retained. The whole operation fails only when no
valid route remains.

Route geometry validation rejects:

- Non-LineString geometries.
- Missing coordinates.
- Fewer than two points.
- Non-numeric coordinates.
- Non-finite values.
- Latitude outside `-90..90`.
- Longitude outside `-180..180`.
- Negative distance or duration.

The service uses a custom `RouteCalculationException` so the UI can present
domain-specific messages instead of exposing raw JSON or transport errors.

---

## 11. Route preview and navigation

### `lib/pages/route_preview_panel.dart`

The preview panel receives a `RoutePlanResult` and callback functions from the
map page. It is intentionally presentation-focused: route selection,
navigation, editing, and clearing are delegated back to `MapPage`.

The panel displays:

- Origin.
- Intermediate stops.
- Destination.
- Number of routes.
- Distance.
- Estimated duration.
- Optional route weight.
- Optional road summary.
- Selected and unselected route styles.

Available actions:

- Select an alternative.
- Start navigation.
- Exit navigation.
- Open route details.
- Edit stops.
- Clear the route.

Route details show the data actually returned by OSRM. The UI does not invent
turn-by-turn instructions when the request did not ask OSRM for steps.

### `lib/pages/route_navigation_progress.dart`

`RouteNavigationProgress` calculates a GPS position’s progress against a route
polyline. It returns:

- Remaining distance in metres.
- Remaining duration.
- Distance from the route in metres.
- Progress distance along the route.

The calculation:

1. Iterates across every route segment.
2. Calculates segment lengths using a haversine-distance method.
3. Projects the current position onto each segment using a local
   latitude/longitude-to-metre approximation.
4. Chooses the closest projected point.
5. Converts progress to a route fraction.
6. Scales OSRM’s original distance and duration to estimate remaining values.

The `minimumProgressMeters` argument enforces monotonic progress. This avoids
the displayed route progress moving backwards because of ordinary GPS noise.

The route is considered off-route when the nearest route point is more than
100 metres away.

### Live navigation behavior in `MapPage`

When navigation starts:

- Location access is checked again.
- Location services and permissions are validated independently from the
  initial map load.
- A position stream is subscribed to.
- Progress is recalculated using the selected route.
- The map and panel update as positions arrive.
- The greatest displayed progress is retained.
- An unavailable-location state is presented if live updates cannot be used.

If location access is not available, route preview remains possible, but live
navigation is not started. The user receives an action to open location
settings, app settings, or retry.

---

## 12. Logistics pages

The logistics pages share the same visual language as the map: dark
background, raised surfaces, purple primary actions, muted explanatory text,
rounded cards, and compact responsive layouts.

### Warehouse management

File: [`lib/pages/warehouse_page.dart`](./lib/pages/warehouse_page.dart)

The warehouse page has two main states:

1. **Empty state**
   - Explains that no warehouse is registered.
   - Provides a **Register Warehouse** action.
   - Shows an associated-trucks introduction.

2. **Registered warehouse dashboard**
   - Shows warehouse name and details.
   - Displays generated warehouse code.
   - Shows address and contact information.
   - Presents approved, pending, and rejected truck sections.
   - Provides **Update warehouse details**.

The registration form collects:

- Warehouse name.
- Address.
- Contact name.
- Contact number.
- Location.

Required fields are validated before registration. A code is generated in the
format:

```text
WH-123456
```

The current implementation stores the registration in widget state and
displays a success snackbar. It does not write to Firestore yet.

### Truck registration

File: [`lib/pages/truck_registration_page.dart`](./lib/pages/truck_registration_page.dart)

The form collects:

- Vehicle registration number.
- Truck type.
- Vehicle capacity.
- Optional vehicle details.
- Driver name.
- Driver contact number.
- Warehouse code.

Truck types currently include:

- Mini truck.
- Box truck.
- Heavy truck.
- Refrigerated truck.

The warehouse code validation:

- Trims and uppercases input.
- Requires the format `WH-` followed by six digits.
- Shows a short loading state.
- Reports that the format is accepted.
- Clearly states that Firestore resolution is still pending.

Submission requires a valid form and a successful warehouse-code format
check. The page then displays a registration-submitted state and an
administrator-approval snackbar. No request is persisted yet.

### Shipment tracking

File: [`lib/pages/track_shipment_page.dart`](./lib/pages/track_shipment_page.dart)

The shipment page accepts an ID in the format:

```text
SHP-ABC123
```

The validation rule requires:

- Prefix `SHP-`.
- Six to twelve uppercase letters or digits after the prefix.

After a valid lookup:

- The search button shows a loading state.
- The ID is normalized to uppercase.
- A result card is shown.
- The current card explains that shipment data is unavailable.
- Timeline, current location, and delivery estimate remain unavailable until
  a real shipment data source is connected.

This behavior is deliberately explicit: the app does not display fabricated
shipment progress.

### Generic placeholder page

File: [`lib/pages/placeholder_page.dart`](./lib/pages/placeholder_page.dart)

This reusable page supports future features that need:

- A title and icon.
- Introductory message.
- Configurable input fields.
- Optional status card.
- A primary future-action button.
- Return-to-map navigation.

It currently communicates that the feature will be connected to BetterRoutes
services in a future update.

---

## 13. Firebase and platform configuration

### Firebase

Firebase project configuration is generated in
[`lib/firebase_options.dart`](./lib/firebase_options.dart). It contains
platform-specific options for:

- Android.
- iOS.
- macOS.
- Web.
- Windows.

Firebase is also wired into:

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `macos/Runner/GoogleService-Info.plist`
- `firebase.json`
- Android Google Services Gradle plugin.

Linux is not configured in `firebase_options.dart`; attempting to initialize
the current generated configuration on Linux throws an unsupported-platform
error.

Firebase API keys and application identifiers are client configuration, not
server secrets, but they must still be restricted in Firebase and Google
Cloud consoles. Do not copy private credentials, unrestricted production
tokens, or local environment values into this README.

### Android

The Android application ID is:

```text
com.betterroutes.app
```

The manifest declares:

- Internet permission.
- Coarse location permission.
- Fine location permission.

These are required for Firebase/network calls and location-aware map
behavior. The application uses the Flutter embedding and a Kotlin
`MainActivity`.

Android builds use:

- Gradle Kotlin DSL.
- Android Gradle Plugin.
- Kotlin Android plugin.
- Google Services plugin.
- Flutter Gradle plugin.

The Android build configuration currently targets Java/Kotlin 17 source
compatibility. The MapLibre dependency may require a newer JDK in some
environments; use the JDK requirement reported by the resolved MapLibre and
Android toolchain when building locally.

### iOS, macOS, web, Windows, and Linux

Flutter platform projects are present for iOS, macOS, web, Windows, and
Linux. The primary application behavior remains in `lib/`, while each
platform supplies its runner and native configuration.

Before shipping to a platform, verify:

- Firebase registration for that platform.
- Map/location permission declarations.
- Native MapLibre support.
- Share-sheet behavior.
- Google sign-in client configuration.
- Release signing and bundle/application identifiers.

---

## 14. MapTiler configuration and local setup

The MapTiler configuration is provided to Dart with compile-time defines:

- `MAPTILER_API_KEY`
- `MAPTILER_STYLE_ID`

The safe template is
[`.env.maptiler.example.json`](./.env.maptiler.example.json). The local
[`.env.maptiler.json`](./.env.maptiler.json) file is ignored by Git and
must not be copied into documentation or shared publicly.

Create or update the local file with values from the MapTiler account, then
run:

```powershell
flutter pub get
flutter run --dart-define-from-file=.env.maptiler.json
```

To select an Android device explicitly:

```powershell
flutter devices
flutter run -d <device-id> --dart-define-from-file=.env.maptiler.json
```

The application remains capable of using the OpenStreetMap fallback when a
valid MapTiler configuration is not available or MapLibre cannot load its
style. Place suggestions still require a valid MapTiler API key.

MapTiler keys should be restricted by allowed applications, domains, package
identifiers, or usage limits where supported. Rotate any key that has been
shared outside the intended local environment.

---

## 15. Testing strategy

The tests use injected HTTP clients and service instances rather than making
real network calls. This keeps tests deterministic and verifies request
construction and error handling.

### Route calculation tests

File: [`test/route_calculation_service_test.dart`](./test/route_calculation_service_test.dart)

Coverage includes:

- OSRM driving alternatives request.
- Correct `longitude,latitude` coordinate ordering.
- Full GeoJSON geometry request.
- Multi-stop waypoint ordering.
- Alternative behavior with and without intermediate stops.
- `NoRoute` error.
- Malformed and out-of-range geometry.
- Retaining valid alternatives when one alternative is malformed.
- Route summaries and weight names.
- Rejecting invalid coordinates before any HTTP request.

### Navigation progress tests

File: [`test/route_navigation_progress_test.dart`](./test/route_navigation_progress_test.dart)

Coverage includes:

- Remaining distance and duration at mid-route.
- Off-route detection.
- Monotonic progress when a minimum progress has already been displayed.

### Route planner widget tests

File: [`test/route_planning_page_test.dart`](./test/route_planning_page_test.dart)

Coverage includes:

- Returning a calculated route plan to the caller.
- Place suggestions for origin and destination.
- Proximity parameters.
- Swapping locations.
- Adding a searchable intermediate stop.
- Passing the selected stop through to OSRM.
- Empty-result and search-failure messages.
- Behavior when current location is unavailable.

### Route preview widget tests

File: [`test/route_preview_panel_test.dart`](./test/route_preview_panel_test.dart)

Coverage includes:

- Alternative route selection.
- Start, edit, and clear callbacks.
- Live navigation summary.
- Exiting navigation without clearing the route.
- Route details showing real route summaries.
- Avoiding invented turn-by-turn instructions.

### Basic app test

File: [`test/widget_test.dart`](./test/widget_test.dart)

This verifies that the root `BetterRoutesApp` widget can be constructed.

### Recommended validation commands

Run these from the project root:

```powershell
flutter pub get
flutter analyze
flutter test
```

For a focused route test run:

```powershell
flutter test test/route_calculation_service_test.dart `
  test/route_navigation_progress_test.dart `
  test/route_planning_page_test.dart `
  test/route_preview_panel_test.dart
```

For Android packaging:

```powershell
flutter build apk --debug --dart-define-from-file=.env.maptiler.json
```

The exact Android JDK and SDK versions should be checked on the target
machine before a release build.

---

## 16. Design system and user experience

The current UI uses a consistent dark logistics/map theme:

| Token | Value | Purpose |
|---|---|---|
| Background | `#17131F` | Main screen background |
| Surface | `#211C2B` | Cards, fields, and panels |
| Raised surface | `#292334` | Elevated route/menu content |
| Primary purple | `#B39DDB` | Buttons, selected route, accents |
| Primary text | `#F7F5FC` | Headings and important values |
| Muted text | `#B5AEC5` | Supporting copy |
| Border | `#383044` | Card and field borders |
| Navigation green | `#5CC6A3` | Current position/start state |

Common UX patterns include:

- Rounded cards and bottom sheets.
- Floating map controls.
- Loading indicators on asynchronous actions.
- Snackbar feedback after mutations or failures.
- Empty states rather than blank screens.
- Explicit permission recovery actions.
- Responsive constrained form widths.
- Scrollable forms for smaller devices.
- Clear disabled states during network operations.
- Visible attribution for OpenStreetMap data.

---

## 17. Data ownership and state boundaries

The current application has three practical state layers:

### Authentication state

Owned by Firebase Auth and read through `FirebaseAuth.instance.currentUser`.
It controls splash routing, profile information, and sign-out.

### Map/session state

Owned by `_MapPageState`, including:

- Current position.
- Search result.
- Active route plan.
- Selected route.
- Map renderer state.
- Navigation subscription.

This state lasts for the active page session and is not persisted.

### Logistics form state

Owned by each logistics page’s state object:

- Warehouse details exist only while the page state remains alive.
- Truck submission status exists only in the current page.
- Shipment search state exists only in the current page.

The next backend phase should move durable business records into repository
services and persistent data models rather than adding Firestore calls
directly inside large widgets.

---

## 18. Security and reliability considerations

Current safeguards include:

- No local MapTiler environment file is intended to be committed.
- User-facing errors avoid exposing raw authentication or HTTP payloads.
- Route coordinates and returned geometry are range-validated.
- HTTP requests have timeouts.
- Search and route clients are disposed.
- Stale asynchronous search responses are ignored.
- Location permission states are handled explicitly.
- MapLibre failures fall back to a usable renderer.
- The shipment page does not fabricate tracking data.

Before production release:

1. Move logistics persistence behind authenticated services.
2. Enforce Firebase security rules by user and role.
3. Add server-side validation for warehouse, truck, and shipment identifiers.
4. Protect privileged administrator actions.
5. Restrict MapTiler and Google API keys.
6. Replace public/shared routing infrastructure with a monitored service or
   an application backend where operational reliability requires it.
7. Add rate limiting and abuse protection for search and route requests.
8. Add structured logging and crash reporting.
9. Add release signing instead of the current debug signing configuration.
10. Review privacy, location-consent, retention, and data-export behavior.

---

## 19. Known limitations

The following limitations are intentional and should be stated in a project
report:

- The public OSRM endpoint is not a guaranteed production SLA.
- MapTiler search requires a configured API key.
- MapLibre style loading depends on network access and native platform
  support.
- The fallback OpenStreetMap tile service must be used according to its
  usage policy and attribution requirements.
- Location accuracy depends on device hardware and permission choice.
- Navigation progress is an estimate based on route geometry; it is not a
  turn-by-turn navigation engine.
- `steps=false` means the app has no spoken or visual turn instructions.
- Route alternatives are OSRM alternatives, not fleet-optimization results.
- Warehouse, truck, and shipment data are not persistent.
- The current warehouse dashboard contains empty truck-status sections.
- Authentication is configured for the current Firebase project and platform
  registrations must be maintained.
- Linux Firebase configuration is not available in the generated options.

---

## 20. Recommended next implementation phases

### Phase 1: Persist warehouse management

- Create a Firestore warehouse model.
- Store owner/user ID, name, address, contact, location, and generated code.
- Load the current user’s warehouse on page entry.
- Prevent duplicate warehouse codes.
- Add update and delete behavior.
- Apply Firestore security rules.

### Phase 2: Persist truck registration

- Add truck and driver data models.
- Resolve warehouse codes against Firestore.
- Store requests with `pending`, `approved`, and `rejected` status.
- Add administrator review actions.
- Show real truck lists in the warehouse dashboard.
- Add duplicate registration checks.

### Phase 3: Implement shipment tracking

- Define shipment, event, location, and ETA models.
- Connect shipment lookup to Firestore or a logistics API.
- Render a real status timeline.
- Show latest location and route progress.
- Restrict shipment visibility to authorized users.

### Phase 4: Improve route planning

- Expose route planning directly from the project panel.
- Add saved places and recent searches.
- Add route persistence.
- Add travel-mode selection.
- Request OSRM steps when turn instructions are required.
- Add route recalculation when the user leaves the route.

### Phase 5: Logistics optimization

- Add orders and delivery stops.
- Add vehicle capacity and driver constraints.
- Add time windows and priority.
- Add a backend optimization service.
- Compare optimized route cost, distance, duration, and capacity usage.

### Phase 6: Production readiness

- Add state-management and repository layers as complexity grows.
- Add environment-specific Firebase projects.
- Add release signing and CI builds.
- Add crash reporting and analytics with privacy review.
- Add accessibility testing and localization.
- Add integration tests on physical Android and iOS devices.

---

## 21. Suggested Word-report structure

The following structure can be used directly when creating the formal report:

1. Title page.
2. Abstract.
3. Problem statement.
4. Project objectives.
5. Scope of the current implementation.
6. Functional requirements.
7. Non-functional requirements.
8. Technology-stack justification.
9. System architecture.
10. Application startup and authentication flow.
11. Map and location implementation.
12. Place search and geocoding implementation.
13. Route-planning implementation.
14. OSRM integration and route-data validation.
15. Route preview and live navigation logic.
16. Warehouse management implementation.
17. Truck registration implementation.
18. Shipment tracking implementation.
19. User interface and design system.
20. Firebase and platform configuration.
21. Testing strategy and test results.
22. Security and reliability considerations.
23. Current limitations.
24. Future enhancement roadmap.
25. Conclusion.

### Report-writing prompt

Use the following prompt to generate a narrative report from this README:

> Write a formal software-project report for **BetterRoutes**, a Flutter-based
> cross-platform route-planning and logistics application. Describe the
> application as it is currently implemented, not as an imagined production
> system. Explain the problem it addresses, its objectives, architecture,
> startup flow, Firebase authentication, location permission handling, map
> rendering, MapTiler geocoding, OSRM route calculation, route alternatives,
> intermediate stops, route preview, navigation-progress estimation,
> off-route detection, warehouse management, truck registration, shipment
> tracking, profile management, testing strategy, security considerations,
> limitations, and future work. Clearly distinguish functional integrations
> from UI prototypes and simulated asynchronous states. Include data models,
> important validation rules, error-handling behavior, external services,
> platform configuration, and the rationale for the OpenStreetMap fallback.
> Explain how the tests use injected HTTP clients and widget callbacks to
> verify deterministic behavior. Use headings, tables, numbered workflows,
> and implementation-focused prose suitable for a Word document. Do not
> include API keys, passwords, private credentials, generated build artifacts,
> or claims that Firestore persistence, turn-by-turn instructions, route
> optimization, or live shipment data are already complete.

---

## 22. Quick-start checklist

1. Install Flutter and verify the selected Dart SDK satisfies the constraint in
   [`pubspec.yaml`](./pubspec.yaml).
2. Configure Android Studio/Xcode and a supported device or emulator.
3. Run `flutter pub get`.
4. Confirm Firebase platform files and project registrations.
5. Create a local ignored MapTiler environment file from the example template.
6. Restrict the MapTiler key in the provider console.
7. Run the app with `--dart-define-from-file`.
8. Grant location permission when prompted.
9. Test signed-out welcome and authentication flows.
10. Test place search and selected-place actions.
11. Test route calculation with and without intermediate stops.
12. Test route alternative selection and navigation preview.
13. Test warehouse, truck, and shipment prototype flows.
14. Run `flutter analyze` and `flutter test` before sharing a build.

---

## 23. Conclusion

BetterRoutes has progressed from a basic Flutter/Firebase starter into a
working route-planning and logistics UI prototype. Its strongest completed
area is the map and routing pipeline: the app resolves location, searches
places, calculates and validates routes, renders alternatives, previews route
metadata, and estimates live progress with explicit fallback behavior.

The logistics pages establish the product workflow and interaction design for
warehouse management, truck registration, and shipment tracking. Their next
step is backend integration and durable data ownership. The codebase already
contains service boundaries, injected clients, explicit error models, and
focused tests that provide a good foundation for that expansion.
