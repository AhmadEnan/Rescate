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
`sqlite3.dll` is bundled with the OS but is not on the DLL search path for
the Dart test runner. Either:

1. Add SQLite to your `PATH` (download `sqlite-dll-win-x64-*.zip` from
   https://www.sqlite.org/download.html and extract it into a folder that is
   on `PATH`), **or**
2. Install [Visual C++ Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe)
   and copy `sqlite3.dll` next to the test runner.

Verify with `flutter test` inside this package — a missing DLL surfaces as
`sqlite3.OpenException` / "Failed to open dynamic library".

