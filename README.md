# my_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## MapTiler map

The MapLibre map uses style ID `01a17d04-02f5-792b-8055-66c8af6dad5f`.
The local `.env.maptiler.json` contains this ID and a placeholder API key.
Replace the placeholder locally with your MapTiler API key; this file is
gitignored. Keep `.env.maptiler.example.json` as the safe template.

The sun/moon control switches between the configured MapTiler style and
MapTiler's dark Streets style. Without a MapTiler key, it switches between
OpenStreetMap's standard tiles and CARTO's dark tiles.

Run the app with:

```sh
flutter run -d YXVCOZ4DCQQC5XYT --dart-define-from-file=.env.maptiler.json
```

MapTiler API keys are needed by the client to load the style and tiles; restrict
the key in your MapTiler account. Until a real key is configured, the app uses
the existing OpenStreetMap renderer. If MapLibre does not finish loading its
style, it falls back to OpenStreetMap.

To make plain `flutter run` use these arguments in PowerShell, add this
function to your PowerShell profile (`$PROFILE`):

```powershell
function flutter {
    $flutterCommand = (Get-Command flutter.bat -CommandType Application).Source

    if ($args.Count -eq 0 -or $args[0] -eq 'run') {
        & $flutterCommand run -d YXVCOZ4DCQQC5XYT --dart-define-from-file=.env.maptiler.json @($args | Select-Object -Skip 1)
    } else {
        & $flutterCommand @args
    }
}
```

Create or open the profile with `notepad $PROFILE`, save the function, and
restart PowerShell. This changes only the PowerShell command on your machine;
`flutter build`, `flutter pub`, and other Flutter commands continue to work
normally. In VS Code, use the `BetterRoutes (MapTiler)` launch profile.

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
