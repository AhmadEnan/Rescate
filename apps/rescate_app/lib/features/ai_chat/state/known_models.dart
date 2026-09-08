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
    'https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf',
  ),
);

// Qwen3-Embedding-0.6B — enables rag_v3 retrieval. Without it the app still
// works using the legacy lexical retriever. The published GGUFs are Q5_K_M
// (444MB) and Q8 (639MB); Q5 is the smallest trustworthy conversion.
// TODO(pin): re-point to a project-built Q4 with pinned sha256 before release.
final KnownModel kEmbedderModel = KnownModel(
  id: 'embedder',
  displayName: 'Retrieval model (Qwen3 Embedding 0.6B, Q5)',
  description:
      'Unlocks smarter offline retrieval (rag_v3). Optional but recommended: '
      'without it the app falls back to a simpler search.',
  fileName: 'qwen3-embedding-0.6b-q5km.gguf',
  downloadUrl: Uri.parse(
    'https://huggingface.co/CompendiumLabs/qwen3-embedding-0.6b-gguf/resolve/main/qwen3-embedding-0.6b-q5km.gguf',
  ),
  sizeBytes: 465000000, // 444 MB; used for progress until content-length arrives
);

final List<KnownModel> kKnownModels = [kChatModel, kEmbedderModel];
