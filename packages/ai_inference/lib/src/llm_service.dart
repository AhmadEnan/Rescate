// packages/ai_inference/lib/src/llm_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:dev_profiler/dev_profiler.dart';
import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import 'device_profile.dart';
import 'rag/embedder_service.dart';
import 'rag/rag_service.dart';
import 'legacy_rag.dart';
import 'llm_config.dart';
import 'llm_load_diagnostics.dart';
import 'llm_load_strategy.dart';
import 'runtime_diagnostics.dart';
import 'tools/tool_call.dart';
import 'tools/tool_executor.dart';

/// Which logical channel a streamed [LlmToken] belongs to.
///
/// Thinking-enabled Gemma 4 emits `<|channel>thought\n…<channel|>` *before*
/// the visible answer. [LlmService.generateStream] parses these markers out of
/// the raw token stream and tags each chunk with its channel so the UI can
/// route them separately (a collapsible reasoning section vs. the bubble's
/// answer text).
enum LlmChannel {
  /// Text inside `<|channel>thought\n…<channel|>` — the model's reasoning.
  thought,

  /// Everything outside the thought block — the user-visible answer.
  answer,
}

/// A streamed text chunk plus the channel it belongs to.
class LlmToken {
  const LlmToken(this.text, this.channel);
  final String text;
  final LlmChannel channel;
}

/// Status of the [LlmService] model lifecycle.
enum LlmStatus {
  /// No model has been loaded yet.
  idle,

  /// A model is currently being loaded from disk.
  loading,

  /// Model is loaded and ready for inference.
  ready,

  /// Model is actively generating a response.
  generating,

  /// An unrecoverable error occurred. Check [LlmService.lastError].
  error,
}

/// Singleton service that wraps `llamadart`'s [LlamaEngine] to provide:
/// - Model lifecycle management (load / unload).
/// - Streaming token generation via [generateStream].
/// - Observable [status] and [lastError] for UI state binding.
///
/// ### Usage
/// ```dart
/// final service = LlmService.instance;
/// await service.loadModel('/path/to/model.gguf');
/// await for (final token in service.generateStream('Hello', isArabic: false)) {
///   buffer.write(token);
/// }
/// ```
class LlmService extends ChangeNotifier {
  LlmService._();

  static final LlmService instance = LlmService._();

  LlamaEngine? _engine;

  LlmStatus _status = LlmStatus.idle;
  String? _lastError;
  String? _loadedModelPath;
  Map<String, Object?> _loadedRuntimeConfig = <String, Object?>{};

  /// Optional tool registry. When non-null, [generateStreamWithTools] declares
  /// these tools to the model and dispatches any emitted tool_call via
  /// [ToolRegistry.executor].
  ToolRegistry? toolRegistry;

  /// Maximum number of model → tool → model round-trips per user turn.
  /// Guards against infinite tool-call loops.
  static const int maxToolRoundTrips = 2;

  /// Time budget for a single tool executor invocation.
  static const Duration toolTimeout = Duration(seconds: 45);

  /// Attach (or replace) the tool registry used by [generateStreamWithTools].
  void attachToolRegistry(ToolRegistry registry) {
    toolRegistry = registry;
  }

  // ── Public getters ─────────────────────────────────────────────────────────

  /// Current lifecycle status.
  LlmStatus get status => _status;

  /// The last error message, non-null only when [status] is [LlmStatus.error].
  String? get lastError => _lastError;

  /// Absolute path of the currently loaded model file, or null.
  String? get loadedModelPath => _loadedModelPath;

  /// Returns `true` when the model is loaded and idle (ready to generate).
  bool get isReady => _status == LlmStatus.ready;

  /// Returns `true` when a generation is in progress.
  bool get isGenerating => _status == LlmStatus.generating;

  // ── Model lifecycle ────────────────────────────────────────────────────────

  /// Loads the GGUF model at [modelPath].
  ///
  /// Walks a hardware fallback ladder ([buildFallbackLadder]) and persists
  /// a sticky load-attempt marker before each native call so a SIGSEGV in
  /// libllama / libggml does not crash-loop the user on next launch.
  ///
  /// Safe to call multiple times — will unload a previously loaded model
  /// first. Throws [LlmException] if every rung fails.
  Future<void> loadModel(String modelPath) async {
    return Profiler.span('llm.loadModel', () async {
      final TraceHandle? trace = Profiler.openTrace(
        'llm.loadModel',
        data: <String, Object?>{'model': modelPath},
      );
      try {
        if (_status == LlmStatus.generating) {
          throw const LlmException('Cannot load a new model while generating.');
        }

        // Unload any existing model first.
        if (_status == LlmStatus.ready || _engine != null) {
          await _unloadSilently();
        }

        _setStatus(LlmStatus.loading);
        _lastError = null;

        await LlmLoadDiagnostics.appendLog(
          '=== loadModel start path=$modelPath ===',
        );

        // 1. Preflight: bail early on missing / truncated / non-GGUF files.
        final TraceStep? preflightStep = trace?.begin('llm.load.preflight');
        final GgufFileCheck check = await LlmLoadDiagnostics.validateGgufFile(
          modelPath,
        );
        preflightStep?.op(1);
        preflightStep?.end();
        await LlmLoadDiagnostics.appendLog('preflight: $check');
        if (!check.isValid) {
          _loadedModelPath = null;
          _setStatus(LlmStatus.error);
          final String msg = check.error ?? 'unknown preflight error';
          _lastError = 'Model file rejected: $msg';
          throw LlmException(_lastError!);
        }

        // 2. Build fallback ladder using the active device profile.
        final DeviceProfile profile =
            LlmDefaults.activeProfile ?? DeviceProfile.fallback;
        final List<LlmLoadRung> ladder = buildFallbackLadder(profile);
        // Resolve against the ACTUAL ladder — slow-Vulkan SoCs get a shorter,
        // already-CPU-only ladder where the literal index 3 is out of range.
        final int cpuRung = firstCpuRungIndex(ladder);
        await LlmLoadDiagnostics.appendLog(
          'profile: ${_safeJson(profile.toJson())}',
        );
        if (hasSlowVulkanCompute(profile.socModel)) {
          await LlmLoadDiagnostics.appendLog(
            'soc=${profile.socModel} is a known slow-Vulkan part — '
            'ladder is CPU-only (${ladder.length} rungs)',
          );
          Profiler.event(
            'llm.load.slowVulkanSoc',
            data: <String, Object?>{
              'socModel': profile.socModel,
              'rungs': ladder.length,
            },
          );
        }

        // 3. Read the sticky marker. If it points at the same model, skip past
        //    the last attempted rung — it crashed last time. If it points at a
        //    different model, clear it (a different file has a different
        //    memory profile and shouldn't be penalised).
        final TraceStep? diagStep = trace?.begin('llm.load.diagnostics');
        final LoadAttempt? previous = await LlmLoadDiagnostics.readAttempt();
        int startRung = 0;
        if (previous != null) {
          if (previous.modelPath == modelPath) {
            startRung = previous.nextRungAfterCrash;
            // GPU-collapse: if the prior attempt used a GPU backend and crashed,
            // skip every remaining GPU rung. Observed on Mali-G57 / MT6789:
            // rungs 0, 1, and 2 all SIGSEGV in the same Vulkan buffer-alloc
            // path, so trying the rest of the GPU bucket only burns cold
            // starts.
            if (previous.crashedOnGpuBackend && startRung < cpuRung) {
              await LlmLoadDiagnostics.appendLog(
                'previous attempt crashed on GPU backend (${previous.backend}) '
                '→ collapsing remaining GPU rungs, jumping to $cpuRung',
              );
              startRung = cpuRung;
            }
            await LlmLoadDiagnostics.appendLog(
              'previous attempt detected: $previous → startRung=$startRung',
            );
          } else {
            await LlmLoadDiagnostics.appendLog(
              'previous attempt for different model — clearing: $previous',
            );
            await LlmLoadDiagnostics.clearAttempt();
          }
        }

        if (startRung >= ladder.length) {
          _loadedModelPath = null;
          _setStatus(LlmStatus.error);
          _lastError =
              'This model has failed to load with every fallback configuration on this device. '
              'Try a smaller quant (e.g. Q4_K_S) or a smaller model.';
          await LlmLoadDiagnostics.appendLog(
            'ladder exhausted before start; aborting',
          );
          throw LlmException(_lastError!);
        }

        // 4. If free RAM is clearly insufficient for any GPU rung, jump straight
        //    to CPU (rung 3). We still want to log the attempt the GPU rung would
        //    have used for diagnostics.
        final int freeMb = await LlmLoadDiagnostics.readFreeRamMb();
        final int requiredMb = (check.sizeBytes / (1024 * 1024) * 1.2).ceil();
        await LlmLoadDiagnostics.appendLog(
          'memory: freeRamMb=$freeMb requiredMb≈$requiredMb fileSizeMb=${(check.sizeBytes / 1048576).toStringAsFixed(1)}',
        );
        if (freeMb > 0 &&
            freeMb < requiredMb &&
            startRung < cpuRung) {
          await LlmLoadDiagnostics.appendLog(
            'free RAM below required threshold — jumping to rung $cpuRung',
          );
          startRung = cpuRung;
        }
        diagStep?.end();

        // 5. Walk the ladder.
        Object? lastException;
        for (int rung = startRung; rung < ladder.length; rung++) {
          final LlmLoadRung step = ladder[rung];
          final TraceStep? rungStep = trace?.begin('llm.load.rung');
          rungStep?.setData('rung', rung);
          rungStep?.setData('description', step.description);
          rungStep?.setData('backend', step.params.preferredBackend.name);
          await LlmLoadDiagnostics.appendLog(
            'attempting rung=$rung ${step.description} '
            '(${describeModelParams(step.params)})',
          );

          // Sticky marker BEFORE calling into FFI — survives a SIGSEGV.
          await LlmLoadDiagnostics.writeAttempt(
            LoadAttempt(
              rung: rung,
              modelPath: modelPath,
              timestampMs: DateTime.now().millisecondsSinceEpoch,
              note: step.description,
              backend: step.params.preferredBackend.name,
            ),
          );

          try {
            _engine = LlamaEngine(LlamaBackend());
            await Profiler.span(
              'llm.engine.loadModel',
              () => _engine!.loadModel(modelPath, modelParams: step.params),
            );

            await Profiler.span('rag.initialize', LegacyRag.initialize);
            await LlmLoadDiagnostics.clearAttempt();
            await LlmLoadDiagnostics.appendLog('rung=$rung SUCCESS');

            // Ask the native backend what actually became active. The
            // requested ModelParams are not sufficient: llamadart may resolve
            // a different backend or GPU layer count after probing the device.
            final runtime = await _readRuntimeDiagnostics();
            _loadedRuntimeConfig = <String, Object?>{
              ...runtime,
              'requestedBackend': step.params.preferredBackend.name,
              'requestedGpuLayers': step.params.gpuLayers,
              'threads': step.params.numberOfThreads,
              'threadsBatch': step.params.numberOfThreadsBatch,
              'batchSize': step.params.batchSize,
              'microBatchSize': step.params.microBatchSize,
              'contextSize': step.params.contextSize,
            };

            _loadedModelPath = modelPath;
            _setStatus(LlmStatus.ready);
            rungStep?.op(1);
            rungStep?.end();
            // Emit the ACTUAL resolved backend config (the dead-code event in
            // LlmDefaults.buildModelParams() never fires on the production
            // path because loadModel uses step.params from
            // buildFallbackLadder, not buildModelParams). Captures the final
            // rung's params so future profiler reports show what was REALLY
            // used — flashAttention, threads, batch sizes, KV types, etc.
            Profiler.event(
              'llm.backend',
              data: <String, Object?>{
                'resolved': step.params.preferredBackend.name,
                'actualBackend': runtime['backend'],
                'actualGpuLayers': runtime['gpuLayers'],
                'cpuVariant': runtime['cpuVariant'],
                'availableBackends': runtime['availableBackends'],
                'rung': rung,
                'gpuLayers': step.params.gpuLayers,
                'ctx': step.params.contextSize,
                'batchSize': step.params.batchSize,
                'microBatchSize': step.params.microBatchSize,
                'threads': step.params.numberOfThreads,
                'threadsBatch': step.params.numberOfThreadsBatch,
                'mlock': step.params.useMlock,
                'mmap': step.params.useMmap,
                'flashAttention': step.params.flashAttention.name,
                'kvK': step.params.cacheTypeK.name,
                'kvV': step.params.cacheTypeV.name,
                'splitMode': step.params.splitMode.name,
                'mainGpu': step.params.mainGpu,
                'modelBytes': check.sizeBytes,
                'description': step.description,
              },
            );
            Profiler.event(
              'llm.load.rungSuccess',
              data: <String, Object?>{
                'rung': rung,
                'description': step.description,
              },
            );
            debugPrint('[LlmService] Model loaded (rung=$rung): $modelPath');
            unawaited(Profiler.exportJson(label: 'model_load'));
            return;
          } catch (e, st) {
            lastException = e;
            rungStep?.setData('failed', e.toString());
            rungStep?.end();
            // Emit a per-rung failure event so future profiler reports show
            // how the fallback ladder executed on this device — essential
            // for diagnosing the Mali-G57-class GPU collapse case.
            Profiler.event(
              'llm.load.rungFail',
              data: <String, Object?>{
                'rung': rung,
                'description': step.description,
                'backend': step.params.preferredBackend.name,
                'error': e.toString(),
              },
            );
            await LlmLoadDiagnostics.appendLog(
              'rung=$rung FAILED ${e.runtimeType}: $e',
            );
            debugPrint('[LlmService] rung=$rung failed: $e\n$st');
            await _unloadSilently();
            // Try next rung.
          }
        }

        // 6. All rungs exhausted in this session — keep the sticky marker so the
        //    auto-load path on next launch refuses politely instead of retrying.
        _loadedModelPath = null;
        _setStatus(LlmStatus.error);
        _lastError =
            'Model failed to load on every fallback configuration. Last error: $lastException';
        throw LlmException(_lastError!);
      } finally {
        trace?.end();
      }
    });
  }

  /// Unloads the current model and releases native memory.
  Future<void> unloadModel() async {
    await _unloadSilently();
    _setStatus(LlmStatus.idle);
  }

  // ── Inference ──────────────────────────────────────────────────────────────

  /// Streams generated tokens for [userMessage].
  ///
  /// Prepends the appropriate system prompt (EN or AR) and wraps the combined
  /// text in the instruct prompt format before sending to llama.cpp.
  ///
  /// When [trace] is non-null (a `chat.turn` trace opened by the caller), the
  /// pipeline steps below are recorded as its children; otherwise a dedicated
  /// `llm.turn` trace is opened. Every step carries wall time + operation
  /// counts, and the finished run is enriched with native llama.cpp timings
  /// from [LlamaEngine.getPerformanceContext].
  ///
  /// Throws [LlmNotReadyException] if no model is loaded.
  /// Throws [LlmException] on generation errors.
  Stream<LlmToken> generateStream(
    String userMessage, {
    bool isArabic = false,
    TraceHandle? trace,
    String? benchmarkCaseId,
  }) async* {
    if (!isReady || _engine == null) {
      throw LlmNotReadyException();
    }

    _setStatus(LlmStatus.generating);

    final TraceHandle? turn =
        trace ??
        Profiler.openTrace(
          'llm.turn',
          data: <String, Object?>{
            'lang': isArabic ? 'ar' : 'en',
            'model': _loadedModelPath ?? '',
            if (benchmarkCaseId != null) 'benchmark_case': benchmarkCaseId,
          },
        );

    if (benchmarkCaseId != null) {
      turn?.setData('benchmark_case', benchmarkCaseId);
    }

    final totalSw = Stopwatch()..start();
    final ttftSw = Stopwatch()..start();
    final rssStart = _profileRssStart();
    var firstTokenSeen = false;
    var tokenCount = 0;
    var thoughtTokens = 0;
    var answerTokens = 0;
    var splitOps = 0;
    var tokenSamples = 0;
    var tokenSumMs = 0;
    var tokenMinMs = -1;
    var tokenMaxMs = 0;

    TraceStep? stepRag;
    TraceStep? stepDecode;

    // KV prefix reuse: rely on llamadart's in-session `reusePromptPrefix`
    // (set on GenerationParams below). The disk-based stateSaveFile/Load
    // path was unsound — the engine's KV at save time held the FULL turn,
    // not just the system prefix, so loading it on the next turn confused
    // the prefix matcher. Revisit only if measurements show a cross-session
    // win is worth the engineering. For now drop it.
    try {
      // ── RAG v3 path (non-tool turn) ──────────────────────────────────────
      stepRag = turn?.begin('rag.search');
      String fullPrompt;
      List<double>? queryVec;
      if (EmbedderService.instance.isReady) {
        try {
          queryVec = await EmbedderService.instance.embed(userMessage);
        } catch (_) {
          queryVec = null;
        }
      }
      final ragResult = await RagService.instance.buildPromptV3(
        question: userMessage,
        queryVec:
            queryVec == null ? null : Float32List.fromList(queryVec),
        enableThinking: LlmDefaults.enableThinking,
      );
      fullPrompt = ragResult.prompt;
      stepRag?.setData('sources', ragResult.sources);
      stepRag?.setData('v3', queryVec != null);
      stepRag?.setData('triaged', ragResult.triaged);
      stepRag?.setData('prompt_chars', fullPrompt.length);
      // Token counting is diagnostic-only and must never block a turn. It
      // runs BEFORE stepRag.end(): setData is a no-op on a closed step.
      if (kProfilerEnabled) {
        try {
          final promptTokens = await _engine!.getTokenCount(fullPrompt);
          stepRag?.setData('prompt_tokens', promptTokens);
          turn?.setData('prompt_tokens', promptTokens);
        } catch (_) {}
      }
      stepRag?.end();
      Profiler.count('rag.v3.used', queryVec != null ? 1 : 0);

      const params = GenerationParams(
        temp: LlmDefaults.temperature,
        topP: LlmDefaults.topP,
        topK: LlmDefaults.topK,
        minP: LlmDefaults.minP,
        penalty: LlmDefaults.repeatPenalty,
        maxTokens: LlmDefaults.maxTokens,
        stopSequences: LlmDefaults.stopSequences,
        reusePromptPrefix: true,
      );

      Profiler.event(
        'llm.sampler',
        data: <String, Object?>{
          'temp': params.temp,
          'topP': params.topP,
          'topK': params.topK,
          'minP': params.minP,
          'penalty': params.penalty,
          'maxTokens': params.maxTokens,
          'stopSequences': params.stopSequences,
          'reusePromptPrefix': params.reusePromptPrefix,
          'path': 'noTools',
        },
      );

      final stream = _engine!.generate(fullPrompt, params: params);

      // ── Channel splitter ───────────────────────────────────────────────────
      // Tokens from llama.cpp may chop the literal markers `<|channel>` and
      // `<channel|>` across boundaries, so we accumulate into a buffer and
      // only emit the safe prefix (everything except the last N-1 chars, where
      // N is the longest marker length). Drop markers + the `{name}\n` line
      // that follows the opener so the visible payload stays clean.
      const opener = '<|channel>';
      const closer = '<channel|>';
      const maxMarkerTail =
          (opener.length > closer.length ? opener.length : closer.length) - 1;
      var channel = LlmChannel.answer;
      var buffer = '';

      stepDecode = turn?.begin('llm.decode');
      final arrivalSw = Stopwatch()..start();

      await for (final token in stream) {
        if (!firstTokenSeen) {
          firstTokenSeen = true;
          ttftSw.stop();
          Profiler.event(
            'llm.ttft',
            data: <String, Object?>{'ms': ttftSw.elapsedMilliseconds},
          );
          arrivalSw
            ..reset()
            ..start();
        } else {
          final gapMs = arrivalSw.elapsedMilliseconds;
          arrivalSw
            ..reset()
            ..start();
          tokenSamples++;
          tokenSumMs += gapMs;
          if (tokenMinMs < 0 || gapMs < tokenMinMs) tokenMinMs = gapMs;
          if (gapMs > tokenMaxMs) tokenMaxMs = gapMs;
        }
        tokenCount++;
        stepDecode?.op(1);
        if (channel == LlmChannel.thought) {
          thoughtTokens++;
        } else {
          answerTokens++;
        }
        buffer += token;

        // Re-enter the state machine until no more transitions/emissions are
        // possible for the current buffer.
        var progressing = true;
        while (progressing) {
          progressing = false;
          splitOps++;
          if (channel == LlmChannel.answer) {
            final idx = buffer.indexOf(opener);
            if (idx >= 0) {
              if (idx > 0) {
                yield LlmToken(buffer.substring(0, idx), LlmChannel.answer);
              }
              // After the opener we expect "{name}\n" before the thought
              // content begins. Skip up to (and including) the newline.
              final afterOpener = idx + opener.length;
              final nlIdx = buffer.indexOf('\n', afterOpener);
              if (nlIdx < 0) {
                // The full header hasn't arrived; preserve opener + tail and
                // wait for the next token.
                buffer = buffer.substring(idx);
                break;
              }
              buffer = buffer.substring(nlIdx + 1);
              channel = LlmChannel.thought;
              progressing = true;
            } else if (buffer.length > maxMarkerTail) {
              final safeEnd = buffer.length - maxMarkerTail;
              yield LlmToken(buffer.substring(0, safeEnd), LlmChannel.answer);
              buffer = buffer.substring(safeEnd);
            }
          } else {
            final idx = buffer.indexOf(closer);
            if (idx >= 0) {
              if (idx > 0) {
                yield LlmToken(buffer.substring(0, idx), LlmChannel.thought);
              }
              buffer = buffer.substring(idx + closer.length);
              channel = LlmChannel.answer;
              progressing = true;
            } else if (buffer.length > maxMarkerTail) {
              final safeEnd = buffer.length - maxMarkerTail;
              yield LlmToken(buffer.substring(0, safeEnd), LlmChannel.thought);
              buffer = buffer.substring(safeEnd);
            }
          }
        }
      }
      arrivalSw.stop();

      // Flush any trailing buffered text on the current channel. If we were
      // mid-thought when the stream ended (no closer arrived), the partial
      // reasoning still belongs to the thought channel.
      if (buffer.isNotEmpty) {
        yield LlmToken(buffer, channel);
      }
      Profiler.count('llm.tokens', tokenCount);
      Profiler.count('llm.tokens.thought', thoughtTokens);
      Profiler.count('llm.tokens.answer', answerTokens);
      Profiler.count('llm.channel_split_ops', splitOps);

      stepDecode
        ?..setData('ttft_ms', ttftSw.elapsedMilliseconds)
        ..setData('tokens', tokenCount)
        ..setData('tokens_thought', thoughtTokens)
        ..setData('tokens_answer', answerTokens)
        ..setData('channel_split_ops', splitOps);
      if (tokenSamples > 0) {
        stepDecode
          ?..setData('token_gap_ms_min', tokenMinMs)
          ..setData('token_gap_ms_max', tokenMaxMs)
          ..setData('token_gap_ms_mean', (tokenSumMs / tokenSamples).round());
      }
      stepDecode?.end();

      await _attachNativeTimings(turn);
    } catch (e) {
      _lastError = e.toString();
      _setStatus(LlmStatus.error);
      throw LlmException('Generation failed: $e');
    } finally {
      totalSw.stop();
      _profileRecordGenerateStream(totalSw.elapsedMilliseconds, rssStart);
      // Only reset to ready if we didn't hit an error.
      if (_status == LlmStatus.generating) {
        _setStatus(LlmStatus.ready);
      }
      // Only finalize a trace we opened ourselves — a caller-supplied
      // `chat.turn` trace is owned and ended by the caller.
      if (trace == null) {
        turn?.end();
      }
    }
  }

  /// Streams generated tokens for [userMessage] with tool calling enabled.
  ///
  /// Declares [toolRegistry]'s tools to the model in the system turn. If the
  /// model emits a complete `<|tool_call>...<tool_call|>` block, we stop
  /// consuming the stream, dispatch the call via [ToolRegistry.executor],
  /// append the rendered `<|tool_response>...<tool_response|>` to the prompt,
  /// and re-invoke generation. Hard-capped at [maxToolRoundTrips] round-trips.
  ///
  /// When [toolRegistry] is null this falls through to plain generation.
  ///
  /// The tool_call markup itself is suppressed from the emitted token stream
  /// — only the prose before the call (and any prose after the response) is
  /// visible to the consumer.
  ///
  /// See [generateStream] for [trace] semantics.
  Stream<LlmToken> generateStreamWithTools(
    String userMessage, {
    bool isArabic = false,
    TraceHandle? trace,
    String? benchmarkCaseId,
  }) async* {
    if (!isReady || _engine == null) {
      throw LlmNotReadyException();
    }

    final registry = toolRegistry;
    if (registry == null) {
      yield* generateStream(
        userMessage,
        isArabic: isArabic,
        trace: trace,
        benchmarkCaseId: benchmarkCaseId,
      );
      return;
    }

    _setStatus(LlmStatus.generating);

    final TraceHandle? turn =
        trace ??
        Profiler.openTrace(
          'llm.turn',
          data: <String, Object?>{
            'lang': isArabic ? 'ar' : 'en',
            'model': _loadedModelPath ?? '',
            if (benchmarkCaseId != null) 'benchmark_case': benchmarkCaseId,
          },
        );

    if (benchmarkCaseId != null) {
      turn?.setData('benchmark_case', benchmarkCaseId);
    }

    try {
      // ── RAG v3 path ───────────────────────────────────────────────────────
      // RagService owns asset loading + LegacyRag fallback. When the embedder
      // is ready we embed the query and use the validated rag_v3 pipeline
      // (sentence-level dense retrieval + triage + warzone prompt); otherwise
      // we transparently fall back to LegacyRag so the app never blocks on
      // the embedder download.
      final TraceStep? stepRag = turn?.begin('rag.search');
      String prompt;
      List<String> ragSources;
      var ragTriaged = false;
      final ragSw = Stopwatch()..start();
      List<double>? queryVec;
      if (EmbedderService.instance.isReady) {
        try {
          queryVec = await EmbedderService.instance.embed(userMessage);
        } catch (_) {
          queryVec = null; // fall back below
        }
      }
      final ragResult = await RagService.instance.buildPromptV3(
        question: userMessage,
        queryVec: queryVec == null
            ? null
            : Float32List.fromList(queryVec),
        toolDeclarations: registry.renderDeclarations(),
        enableThinking: LlmDefaults.enableThinking,
      );
      prompt = ragResult.prompt;
      ragSources = ragResult.sources;
      ragTriaged = ragResult.triaged;
      ragSw.stop();
      stepRag?.setData('sources', ragSources);
      stepRag?.setData('v3', queryVec != null);
      stepRag?.setData('triaged', ragTriaged);
      stepRag?.setData('ms', ragSw.elapsedMilliseconds);
      stepRag?.setData('prompt_chars', prompt.length);
      // Token counting runs BEFORE stepRag.end(): setData is a no-op on a
      // closed step (review round 2).
      if (kProfilerEnabled) {
        try {
          final promptTokens = await _engine!.getTokenCount(prompt);
          stepRag?.setData('prompt_tokens', promptTokens);
          turn?.setData('prompt_tokens', promptTokens);
        } catch (_) {}
      }
      stepRag?.end();
      Profiler.count('rag.v3.used', queryVec != null ? 1 : 0);

      const params = GenerationParams(
        temp: LlmDefaults.temperature,
        topP: LlmDefaults.topP,
        topK: LlmDefaults.topK,
        minP: LlmDefaults.minP,
        penalty: LlmDefaults.repeatPenalty,
        maxTokens: LlmDefaults.maxTokens,
        stopSequences: LlmDefaults.stopSequences,
        reusePromptPrefix: true,
      );

      Profiler.event(
        'llm.sampler',
        data: <String, Object?>{
          'temp': params.temp,
          'topP': params.topP,
          'topK': params.topK,
          'minP': params.minP,
          'penalty': params.penalty,
          'maxTokens': params.maxTokens,
          'stopSequences': params.stopSequences,
          'reusePromptPrefix': params.reusePromptPrefix,
          'path': 'tools',
        },
      );

      const opener = '<|channel>';
      const closer = '<channel|>';
      const callOpener = '<|tool_call>';
      const callCloser = '<tool_call|>';
      // Conservative hold-back: longest marker minus 1 so a marker straddling
      // two tokens stays buffered until complete.
      const maxMarkerTail = 12; // length of '<|tool_call>'

      for (var round = 0; round < maxToolRoundTrips; round++) {
        final TraceStep? roundStep = turn?.begin('llm.round');
        roundStep?.setData('round', round);
        final stream = _engine!.generate(prompt, params: params);

        if (kProfilerEnabled) {
          try {
            final promptTokens = await _engine!.getTokenCount(prompt);
            roundStep?.setData('prompt_tokens', promptTokens);
            roundStep?.setData('prompt_chars', prompt.length);
          } catch (_) {
            // Token counting is diagnostic-only and must never block a turn.
          }
        }

        var channel = LlmChannel.answer;
        var buffer = '';
        var emittedThisRound = '';
        var tokensThisRound = 0;
        ToolCall? completedCall;
        var splitOps = 0;

        final TraceStep? decodeStep = turn?.begin('llm.decode');
        decodeStep?.setData('round', round);

        await for (final token in stream) {
          emittedThisRound += token;
          buffer += token;
          tokensThisRound++;
          decodeStep?.op(1);

          var progressing = true;
          while (progressing) {
            progressing = false;
            splitOps++;

            if (channel == LlmChannel.answer) {
              // 1. Complete tool_call → break out and dispatch.
              final tcStart = buffer.indexOf(callOpener);
              final tcEnd = tcStart >= 0
                  ? buffer.indexOf(callCloser, tcStart + callOpener.length)
                  : -1;
              if (tcStart >= 0 && tcEnd >= 0) {
                if (tcStart > 0) {
                  yield LlmToken(
                    buffer.substring(0, tcStart),
                    LlmChannel.answer,
                  );
                }
                final fullCallText = buffer.substring(
                  tcStart,
                  tcEnd + callCloser.length,
                );
                final parsed = ToolCallParser.parse(fullCallText);
                if (parsed.isNotEmpty) {
                  completedCall = parsed.first;
                }
                buffer = buffer.substring(tcEnd + callCloser.length);
                break;
              }

              // 2. Channel switch into thought.
              final idx = buffer.indexOf(opener);
              if (idx >= 0) {
                if (idx > 0) {
                  yield LlmToken(buffer.substring(0, idx), LlmChannel.answer);
                }
                final afterOpener = idx + opener.length;
                final nlIdx = buffer.indexOf('\n', afterOpener);
                if (nlIdx < 0) {
                  buffer = buffer.substring(idx);
                  break;
                }
                buffer = buffer.substring(nlIdx + 1);
                channel = LlmChannel.thought;
                progressing = true;
                continue;
              }

              // 3. No marker found yet — emit the safe prefix, hold back tail.
              if (buffer.length > maxMarkerTail) {
                final safeEnd = buffer.length - maxMarkerTail;
                yield LlmToken(buffer.substring(0, safeEnd), LlmChannel.answer);
                buffer = buffer.substring(safeEnd);
              }
            } else {
              final idx = buffer.indexOf(closer);
              if (idx >= 0) {
                if (idx > 0) {
                  yield LlmToken(buffer.substring(0, idx), LlmChannel.thought);
                }
                buffer = buffer.substring(idx + closer.length);
                channel = LlmChannel.answer;
                progressing = true;
                continue;
              }
              if (buffer.length > maxMarkerTail) {
                final safeEnd = buffer.length - maxMarkerTail;
                yield LlmToken(
                  buffer.substring(0, safeEnd),
                  LlmChannel.thought,
                );
                buffer = buffer.substring(safeEnd);
              }
            }
          }

          if (completedCall != null) break;
        }

        decodeStep
          ?..setData('tokens', tokensThisRound)
          ..setData('channel_split_ops', splitOps)
          ..end();

        // Stream ended (or we broke out for a tool call).
        if (completedCall == null) {
          if (buffer.isNotEmpty) {
            // Strip any orphan tool_call markup the user shouldn't see.
            final cleaned = ToolCallParser.stripMarkup(buffer);
            if (cleaned.isNotEmpty) {
              yield LlmToken(cleaned, channel);
            }
          }
          roundStep?.end();
          await _attachNativeTimings(turn);
          return;
        }

        // Dispatch the tool call. The dispatcher decides its own timeout
        // behavior; we wrap it in our own as a safety net.
        final TraceStep? dispatchStep = turn?.begin('tool.dispatch');
        dispatchStep?.setData('name', completedCall.name);
        dispatchStep?.setData('round', round);
        Map<String, Object?> result;
        try {
          result = await registry.executor(completedCall).timeout(toolTimeout);
        } on TimeoutException {
          result = <String, Object?>{'error': 'timeout'};
        } catch (e) {
          result = <String, Object?>{'error': e.toString()};
        }
        dispatchStep?.op(1);
        dispatchStep?.end();

        final responseStr = ToolCallParser.renderResponse(
          completedCall.name,
          result,
        );
        Profiler.count('llm.tool_rounds', 1);
        Profiler.event(
          'llm.tool_call',
          data: <String, Object?>{
            'name': completedCall.name,
            'round': round,
            'result_keys': result.keys.toList(growable: false),
          },
        );

        // Build continuation prompt: everything emitted so far (which already
        // includes the model's <|tool_call>...<tool_call|>) + our response.
        prompt = prompt + emittedThisRound + responseStr;
        roundStep?.end();
      }

      // Round-trip cap exhausted.
      Profiler.event(
        'llm.tool_call.cap_exhausted',
        data: <String, Object?>{'cap': maxToolRoundTrips},
      );
      await _attachNativeTimings(turn);
    } catch (e) {
      _lastError = e.toString();
      _setStatus(LlmStatus.error);
      throw LlmException('Generation failed: $e');
    } finally {
      if (_status == LlmStatus.generating) {
        _setStatus(LlmStatus.ready);
      }
      // See generateStream: a caller-supplied trace is owned by the caller.
      if (trace == null) {
        turn?.end();
      }
    }
  }

  /// Enriches the [turn] trace with native llama.cpp perf counters (prompt
  /// eval / decode ms, token counts, graph reuse). Best-effort, never throws.
  Future<void> _attachNativeTimings(TraceHandle? turn) async {
    final engine = _engine;
    if (turn == null || engine == null) return;
    try {
      final perf = await engine.getPerformanceContext();
      final runtime = <String, Object?>{
        ..._loadedRuntimeConfig,
        ...(await _readRuntimeDiagnostics()),
      };
      if (runtime.isNotEmpty) turn.setData('runtime', runtime);
      if (perf != null) {
        turn.setData('native', <String, Object?>{
          'load_ms': perf.loadMs.round(),
          'prompt_eval_ms': perf.promptEvalMs.round(),
          'prompt_eval_tokens': perf.promptEvalTokens,
          'eval_ms': perf.evalMs.round(),
          'eval_tokens': perf.evalTokens,
          'sample_ms': perf.sampleMs.round(),
          'sample_count': perf.sampleCount,
          'reused_graphs': perf.reusedGraphs,
          'prompt_tokens_per_sec': perf.promptEvalMs > 0
              ? (perf.promptEvalTokens * 1000 / perf.promptEvalMs).round()
              : 0,
          'decode_tokens_per_sec': perf.evalMs > 0
              ? (perf.evalTokens * 1000 / perf.evalMs).round()
              : 0,
        });
      }
    } catch (_) {
      // Profiling must never break inference.
    }
  }

  Future<Map<String, Object?>> _readRuntimeDiagnostics() async {
    final engine = _engine;
    if (engine == null) return <String, Object?>{};
    final diagnostics = <String, Object?>{
      'cpuVariant': readLoadedCpuVariant(),
    };
    try {
      diagnostics['backend'] = await engine.getBackendName();
    } catch (_) {
      // Optional runtime diagnostics must never affect inference.
    }
    try {
      diagnostics['availableBackends'] = await engine.getAvailableBackends();
    } catch (_) {}
    try {
      diagnostics['gpuLayers'] = await engine.getResolvedGpuLayers();
    } catch (_) {}
    return diagnostics;
  }

  // Helpers around Profiler for the async* generator (which can't use Profiler.span).
  int _profileRssStart() {
    if (kReleaseMode) return 0;
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }

  void _profileRecordGenerateStream(int ms, int rssStart) {
    if (kReleaseMode) return;
    try {
      var delta = 0;
      try {
        delta = ProcessInfo.currentRss - rssStart;
      } catch (_) {}
      Profiler.recordSpan('llm.generateStream.total', ms, rssDeltaBytes: delta);
    } catch (_) {}
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setStatus(LlmStatus newStatus) {
    if (_status == newStatus) return;
    _status = newStatus;
    notifyListeners();
  }

  Future<void> _unloadSilently() async {
    try {
      if (_engine != null) {
        await _engine!.dispose();
        _engine = null;
      }
    } catch (e) {
      debugPrint('[LlmService] unload error (ignored): $e');
    }
    _loadedModelPath = null;
    _loadedRuntimeConfig = <String, Object?>{};
  }
}

// ── Exceptions ────────────────────────────────────────────────────────────────

/// Base class for all [LlmService] exceptions.
class LlmException implements Exception {
  const LlmException(this.message);
  final String message;
  @override
  String toString() => 'LlmException: $message';
}

/// Thrown when [LlmService.generateStream] is called without a loaded model.
class LlmNotReadyException extends LlmException {
  LlmNotReadyException()
    : super('No model is loaded. Call LlmService.instance.loadModel() first.');
}

String _safeJson(Object? value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return value.toString();
  }
}
