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
