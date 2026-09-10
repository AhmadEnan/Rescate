// known_models.dart: registry of the models Rescate needs, with download
// sources. Share-friendly: users who received the app from someone else can
// fetch everything in-app; file import stays as the offline alternative.
//
// Sizes/checksums are pinned so the UI can show honest progress and verify
// integrity. Update checksums when bumping model versions.

class KnownModel {
  final String id; // stable key: 'chat' | 'embedder'
  final String displayName;
  final String description;
  final String fileName; // sandbox file name
  final Uri downloadUrl;
  final int? sizeBytes; // null = unknown until content-length arrives
  final String? sha256Hex; // null = no pin (still GGUF-validated + hashed)

  const KnownModel({
    required this.id,
    required this.displayName,
    required this.description,
    required this.fileName,
    required this.downloadUrl,
    this.sizeBytes,
    this.sha256Hex,
  });

  String get sizeLabel =>
      sizeBytes == null ? 'size unknown' : '${(sizeBytes! / (1024 * 1024)).round()} MB';
}

// gemma-4-E2B-it Q4_K_M, 2.6GB class.
// NOTE: replace the URL with the project's own mirror when available; the
// checksum below must be re-pinned from the actual artifact before release.
final KnownModel kChatModel = KnownModel(
  id: 'chat',
  displayName: 'Assistant model (Gemma 4 E2B, Q4)',
  description:
      'The on-device language model that generates first-aid guidance. ~2.9 GB.',
  fileName: 'gemma-4-E2B-it-Q4_K_M.gguf',
  downloadUrl: Uri.parse(
    'https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/0314792d7f1f7e229411f620751375812bb9faf2/gemma-4-E2B-it-Q4_K_M.gguf',
  ),
);

// Qwen3-Embedding-0.6B — enables rag_v3 retrieval. Without it the app still
// works using the legacy lexical retriever. The published GGUFs are Q5_K_M
// (444MB) and Q8 (639MB); Q5 is the smallest trustworthy conversion.
//
// AUTHENTICITY: URL is pinned to an immutable commit SHA (not the mutable
// `main` ref) and sha256 is pinned below — verified against the exact bytes
// of that artifact. GGUF magic bytes are NOT an authenticity check.
// TODO(release): the sha256 below must be re-verified byte-for-byte from the
// pinned artifact before store distribution.
final KnownModel kEmbedderModel = KnownModel(
  id: 'embedder',
  displayName: 'Retrieval model (Qwen3 Embedding 0.6B, Q5)',
  description:
      'Unlocks smarter offline retrieval (rag_v3). Optional but recommended: '
      'without it the app falls back to a simpler search.',
  // Single source of truth for the embedder filename: the in-app loader
  // (EmbedderService.embedderPath / llm_state activation) resolves through
  // kEmbedderModel, so download and load can never diverge.
  fileName: 'qwen3-embedding-0.6b-q5km.gguf',
  downloadUrl: Uri.parse(
    'https://huggingface.co/CompendiumLabs/qwen3-embedding-0.6b-gguf/resolve/b83f97dcea3ba569f3667953ccc6244ced69572a/qwen3-embedding-0.6b-q5km.gguf',
  ),
  sizeBytes: 444184768,
  // sha256 of the exact artifact at the pinned revision above, verified by
  // downloading it and hashing locally (444,184,768 bytes).
  sha256Hex:
      '10f8deccc8f114de962c3367f4f0715cb8800d29a1b7385ebaff5bb300605139',
);

final List<KnownModel> kKnownModels = [kChatModel, kEmbedderModel];
