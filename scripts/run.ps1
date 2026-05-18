# Launches the Rescate app with the Vulkan dart-defines baked in so you never
# need to remember them. Pass any extra `flutter run` arguments.
#
#   .\scripts\run.ps1                  # debug, attached
#   .\scripts\run.ps1 --release        # release build
#   .\scripts\run.ps1 -d <deviceId>    # pick a specific device

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir ".."))
$AppDir = Join-Path $RootDir "apps/rescate_app"

Set-Location $AppDir
flutter run --dart-define-from-file="dart_defines.json" $args
