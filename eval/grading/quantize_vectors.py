"""Quantize the 7535x1024 f32 vector matrix to int8 (per-vector min/max scale)
and measure quality impact on the 48-case retrieval suite."""
import json, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
import numpy as np

V = np.load('/home/melezaly/Projects/Rescate/eval/rag_mirror/vectors.npy')
print("f32 shape:", V.shape, f"{V.nbytes/1e6:.1f} MB")

# per-row symmetric int8 quantization: scale = max|v| / 127
scale = np.abs(V).max(axis=1, keepdims=True) / 127.0
scale = np.maximum(scale, 1e-9)
Q8 = np.clip(np.round(V / scale), -127, 127).astype(np.int8)
print("q8 bytes:", Q8.nbytes / 1e6, "MB")
np.save('/home/melezaly/Projects/Rescate/eval/rag_mirror/vectors_q8.npy', Q8)
np.save('/home/melezaly/Projects/Rescate/eval/rag_mirror/vectors_q8_scale.npy', scale.astype(np.float32))

# quality: dequantize and measure cosine distortion + suite impact
Vq = Q8.astype(np.float32) * scale
Vq /= np.maximum(np.linalg.norm(Vq, axis=1, keepdims=True), 1e-9)
Vn = V / np.maximum(np.linalg.norm(V, axis=1, keepdims=True), 1e-9)
sims_diag = (Vn * Vq).sum(axis=1)
print(f"mean self-cosine f32 vs q8: {sims_diag.mean():.4f}, p5: {np.percentile(sims_diag,5):.4f}")
