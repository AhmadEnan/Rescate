# PR structure for the rag_v3 + embedder work (dependency analysis)

## Current branch topology (verified)

feature/eval-harness-2 (24 commits ahead of main) already CONTAINS:
  e6bc095 [Storage] Sandboxed model storage (#9 work, = PR #24 head)
  b629861 [APK] ARM64-only (#8, = PR #23 head)
  a9bc249..  (CI branch, = PR #22 head)

i.e. the eval branch was stacked on top of #22 -> #23 -> #24 in order.
main..HEAD = 24 commits; remote main has none of them yet.

## The dependency question

Sheref's concern: embedder/model-loading "should be part of one of the last
PRs" (i.e. #24 ModelStore) but worries about a CIRCULAR DEPENDENCY.

Verified: there is NO circular dependency, and here is the layering:

  Layer 0 (app, #24/PR-24):  ModelStore - sandbox dir, atomic import,
                             SAF picker, no knowledge of WHAT a model is
                             used for. Zero imports from ai_inference/src/rag.
  Layer 1 (package):         ai_inference: LegacyRag, LlmService, llamadart
  Layer 2 (package, NEW):    ai_inference/src/rag/* - rag_v3, triage, prompts
  Layer 3 (package, NEW):    embedder_service - depends on llamadart +
                             rag/*; knows NOTHING about ModelStore (takes a
                             plain filesystem path via load(modelPath))
  Layer 4 (app, glue):       llm_state.dart - calls BOTH ModelStore (path
                             resolution) and EmbedderService (load). This is
                             the ONLY place the two worlds meet.

The apparent circularity dissolves because EmbedderService does not import
ModelStore; it receives a path. The app-level glue (llm_state) is allowed to
know both - that's what the app layer is for.

## Why the embedder download belongs with #24 conceptually

#24's whole point was "model lifecycle without storage permissions". The
embedder GGUF is just another model file: same sandbox dir, same atomic
import, same .sha256 sidecar. The in-app download flow (URL -> stream ->
.part -> hash -> rename) is a ModelStore capability (it already has the
import machinery; only the source differs: HTTP instead of SAF URI).

## Recommended PR structure (no stacking needed)

Option chosen: ONE PR for the model-lifecycle additions, targeted at #24's
branch (or main after #24 merges - GitHub retargets automatically):

  PR-A "[Storage] In-app model + embedder downloads" (extends #24)
    - ModelStore.downloadModel(url, name): streams HTTP -> .part -> sha256
      -> rename; reuses existing atomic machinery + progress callbacks
    - ModelSetupScreen: "Required models" section - chat model + embedder,
      each with size + download button + progress; import-from-file stays
      as the offline alternative
    - embedder registry: knownModels map {chat: gemma-4-E2B Q4_K_M,
      embedder: Qwen3-Embedding-0.6B Q4_K_M} with HF URLs + expected sizes
    - NO rag code in this PR; pure lifecycle

  PR-B "[RAG] rag_v3 retrieval + triage + warzone prompts" (the big one)
    - packages/ai_inference: assets, rag_v3, triage, prompts, tests
    - depends on NOTHING from PR-A at code level (embedder_service takes
      a path; if PR-A hasn't landed, path is absent => LegacyRag fallback)

  PR-C "[RAG] Wire rag_v3 into llm_service + embedder activation"
    - llm_service call-site switch (both turns)
    - llm_state startup wiring (assets + embedder load)
    - embedder_service.dart itself
    - commits to merge AFTER A+B; harmless without A (fallback), inert
      without B (old path)

Merge order: #22 -> #23 -> #24 -> PR-A -> PR-B -> PR-C.
Each PR compiles and passes tests independently. No cycles: A is storage
domain, B is retrieval domain, C is the composition root.

## What Sheref was right about

Putting embedder lifecycle INSIDE #24 originally would have been wrong for
the opposite reason: #24 is already reviewed and waiting, and adding a
370MB download feature to it would reopen a settled PR. Better: A extends
the merged/merging #24 as a fast-follow with the same domain vocabulary.
