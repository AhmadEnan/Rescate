# Offline Data & Search Module

This package powers the offline backend:
- SQLite FTS5 Indexing
- MBTiles Map Rendering
- Local Media Caching & ObjectBox

Please refer to the root `CONTRIBUTING.md` before making changes.

## Running the tests

The tests in `test/` use `sqfliteFfiInit()` (from `sqflite_common_ffi`),
which loads a native SQLite library at runtime instead of a Flutter plugin.

### Linux / macOS
Works out of the box: the system `libsqlite3` is preinstalled (or install it
with your package manager, e.g. `sudo apt-get install libsqlite3-dev`).

### Windows
Stock Windows does **not** ship `sqlite3.dll` on PATH (and Modern Windows
sqlite is a Store component the Dart VM cannot load). Obtain it explicitly:

1. Download `sqlite-dll-win-x64-*.zip` from
   https://www.sqlite.org/download.html and extract `sqlite3.dll`.
2. Put it where the test runner can load it — any of:
   - the same directory as the Flutter test runner binary, or
   - a directory you add to `PATH` for the test session
     (`set PATH=%PATH%;C:\path\to\dll`), or
   - next to the `flutter_tester` executable in your Flutter SDK's `bin/cache`
     directory.

(Optionally install the [Visual C++ Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe)
if the DLL fails to load due to missing VC runtime.)

Verify with `flutter test` inside this package — a missing DLL surfaces as
`sqlite3.OpenException` / "Failed to open dynamic library".

