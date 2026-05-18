@echo off
REM Launches the Rescate app with the Vulkan dart-defines baked in so you never
REM need to remember them. Pass any extra `flutter run` arguments.
REM
REM   .\scripts\run.bat                  # debug, attached
REM   .\scripts\run.bat --release        # release build
REM   .\scripts\run.bat -d <deviceId>    # pick a specific device

SETLOCAL EnableDelayedExpansion
SET "SCRIPT_DIR=%~dp0"
SET "ROOT_DIR=%SCRIPT_DIR%.."
SET "APP_DIR=%ROOT_DIR%\apps\rescate_app"

cd /d "%APP_DIR%"
flutter run --dart-define-from-file="dart_defines.json" %*
