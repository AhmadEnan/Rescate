# LLM Device Benchmark

The fixed prompt set is in `fixed_prompts.json` and is also exposed as
`fixedLlmBenchmarkCases` from `package:ai_inference/ai_inference.dart`.

For each checkpoint, use the same GGUF file and build mode:

1. From PowerShell, change to `apps/rescate_app`.
2. Build and install a profile APK with `RESCATE_PROFILER=true` and the same
   dart defines used by the app.
3. Load the model, run one warm-up turn for every case, then run every case at
   least three times in the listed order.
4. Pull the newest `profiler/session_*_chat_turn.json` files and keep the
   profiler report plus `adb logcat` output as the device artifact.

The report envelope produced by `LlmBenchmarkReport` is versioned. It accepts
both standalone `llm.turn` traces and app-owned `chat.turn` traces. Each
measurement records total time, TTFT, resolved backend, resolved GPU layers,
native prompt/decode token counts, native phase times, and tokens per second.
It also carries the effective thread and batch parameters used for model load,
so CPU and prefill sweeps remain comparable.
Do not compare runs that differ in model file, build mode, thermal state, or
prompt order.

Example Windows commands (PowerShell):

```powershell
Set-Location C:\dev\Rescate\apps\rescate_app
& C:\Users\Ahmed\flutter\bin\flutter.bat build apk --profile `
  --dart-define=RESCATE_PROFILER=true `
  --dart-define-from-file=dart_defines.json
adb devices
$device = "<paste-one-device-serial-here>"
adb -s $device install -r build\app\outputs\flutter-apk\app-profile.apk
adb -s $device logcat -c
```

Open the app, load the same model, wait for loading to finish, and run one
warm-up turn. Then run each measured prompt three times. Wait for every answer
to finish before starting the next prompt; the profiler file is exported only
after generation completes.

After the final answer, dump logcat without starting a blocking live stream:

```powershell
adb -s $device logcat -d -v threadtime > C:\dev\Rescate\benchmarks\device_logcat.txt
```

After the measured turns, locate and pull the exported report (the package
application ID is `com.example.rescate_app`):

```powershell
adb -s $device shell run-as com.example.rescate_app find app_flutter/profiler -type f -name "session_*_chat_turn.json"
adb -s $device exec-out run-as com.example.rescate_app cat app_flutter/profiler/session_<timestamp>_chat_turn.json > C:\dev\Rescate\profiler_report.json
```

Run the `find` command only after a model answer has completed. If it still
reports that `app_flutter/profiler` does not exist, the app did not export a
profile for that turn; return `device_logcat.txt` instead of guessing another
directory.

Convert the pulled raw profiler export from the repository root:

```powershell
Set-Location C:\dev\Rescate
& C:\Users\Ahmed\flutter\bin\dart.bat run `
  packages\ai_inference\tool\benchmark_report.dart `
  profiler_report.json benchmarks\benchmark_report.json
```

Required artifact names for a checkpoint are:

- `profiler_report.json` (raw exported profiler report);
- `benchmark_report.json` (the compact `LlmBenchmarkReport` envelope);
- `device_logcat.txt` (native backend/load diagnostics).
