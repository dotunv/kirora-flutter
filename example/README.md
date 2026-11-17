# Kirora Flutter example

A small app that exercises the SDK: set up a key, identify, track events, flip consent and push,
and watch the SDK's log.

```sh
flutter pub get
flutter run --dart-define=KIRORA_KEY=kirora_pk_... --dart-define=KIRORA_API=https://...
```

Both defines are optional; the Setup screen takes the same values. Push on Android needs your own
`android/app/google-services.json`. See the package README for the Android SDK setup.
