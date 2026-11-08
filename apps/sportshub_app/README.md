# sportshub_app

The SportsHub app for the web, Android and iOS. It is a thin shell: `lib/main.dart` lists the modules, and everything else lives in `packages/`. See the [main README](../../README.md).

```sh
flutter run -d chrome --web-port 3000 --dart-define-from-file=env.json
```

Or, from the `sporthubs` folder, `./scripts/run_web.sh` (port 3000, or 3001 when 3000 is taken).
