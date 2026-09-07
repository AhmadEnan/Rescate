"""LLM serving harness for Rescate eval experiments (issue #14 exploration).

Runs candidate models outside the app so quality can be measured before any
on-device commitment. Two backends:

- llama-cpp-python  (default; `uv pip install llama-cpp-python`)
- llama.cpp server  (if `llama-server` binary is on PATH; OpenAI-compatible)

The wrapper exposes `generate(prompt, max_tokens, stop)` and records
timing metadata (prefill/decode are surfaced by llama.cpp when available).
Model + sampler defaults mirror the app's fast path (thinking disabled).
"""
from __future__ import annotations

import json
import time
from dataclasses import dataclass, field, asdict
from pathlib import Path


@dataclass
class GenResult:
    text: str
    prompt_tokens: int = 0
    generated_tokens: int = 0
    prefill_ms: float = 0.0
    decode_ms: float = 0.0
    total_ms: float = 0.0

    @property
    def decode_tps(self) -> float:
        return self.generated_tokens / (self.decode_ms / 1000) if self.decode_ms else 0.0

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class ModelSpec:
    name: str
    repo_id: str          # HF repo (for documentation / later download)
    gguf_file: str        # filename inside the repo
    ctx_size: int = 4096
    n_threads: int = 0    # 0 = auto
    extra: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return asdict(self)


class LlamaCppBackend:
    """In-process llama.cpp via llama-cpp-python."""

    def __init__(self, model_path: str | Path, ctx_size: int = 4096, n_threads: int = 0):
        from llama_cpp import Llama  # deferred: heavy import
        kwargs = dict(n_ctx=ctx_size, verbose=False, seed=42)
        if n_threads:
            kwargs["n_threads"] = n_threads
            kwargs["n_threads_batch"] = n_threads
        self.llm = Llama(model_path=str(model_path), **kwargs)

    def generate(self, prompt: str, max_tokens: int = 512, stop: list[str] | None = None,
                 temperature: float = 0.1) -> GenResult:
        t0 = time.perf_counter()
        out = self.llm(
            prompt, max_tokens=max_tokens, stop=stop or [], temperature=temperature,
            top_p=0.9, echo=False,
        )
        total_ms = (time.perf_counter() - t0) * 1000
        # llama-cpp-python timings are coarse; token counts are exact.
        usage = out.get("usage", {}) if isinstance(out, dict) else {}
        return GenResult(
            text=out["choices"][0]["text"] if isinstance(out, dict) else out,
            prompt_tokens=int(usage.get("prompt_tokens", 0) or 0),
            generated_tokens=int(usage.get("completion_tokens", 0) or 0),
            total_ms=round(total_ms, 1),
        )


class OpenAICompatBackend:
    """Talks to a llama.cpp `llama-server` (or any OpenAI-compatible endpoint).

    Uses /v1/chat/completions so each model runs through its OWN chat template
    (from GGUF metadata) — the fair way to compare candidates. The Rescate
    system prompt + retrieved medical context are injected as messages; the
    Gemma-specific fast-thought prefill only applies to Gemma-format models.
    """

    def __init__(self, base_url: str, model: str = "default", timeout: float = 600.0):
        import urllib.request

        self.base_url = base_url.rstrip("/")
        self.model = model
        self.timeout = timeout
        self._urllib = urllib.request

    def generate(self, prompt: str, max_tokens: int = 512, stop: list[str] | None = None,
                 temperature: float = 0.1, system_prompt: str | None = None,
                 use_chat: bool = True, enable_thinking: bool | None = None) -> GenResult:
        if use_chat:
            messages = []
            if system_prompt:
                messages.append({"role": "system", "content": system_prompt})
            messages.append({"role": "user", "content": prompt})
            body = {
                "model": self.model,
                "messages": messages,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "top_p": 0.9,
                "repeat_penalty": 1.1,
                "cache_prompt": True,
            }
            if enable_thinking is not None:
                # Qwen3/3.5-style thinking toggle (honored by llama-server's
                # Jinja template application; ignored harmlessly otherwise).
                body["chat_template_kwargs"] = {"enable_thinking": enable_thinking}
            payload = json.dumps(body).encode()
            endpoint = "/v1/chat/completions"
        else:
            payload = json.dumps({
                "model": self.model,
                "prompt": prompt,
                "max_tokens": max_tokens,
                "stop": stop or [],
                "temperature": temperature,
                "top_p": 0.9,
                "cache_prompt": True,
            }).encode()
            endpoint = "/v1/completions"

        req = self._urllib.Request(
            f"{self.base_url}{endpoint}", data=payload,
            headers={"Content-Type": "application/json"},
        )
        t0 = time.perf_counter()
        with self._urllib.urlopen(req, timeout=self.timeout) as resp:
            body = json.loads(resp.read())
        total_ms = (time.perf_counter() - t0) * 1000
        choice = body["choices"][0]
        text = choice["message"]["content"] if "message" in choice else choice["text"]
        timings = body.get("timings", {})
        return GenResult(
            text=text or "",
            prompt_tokens=timings.get("prompt_n", body.get("usage", {}).get("prompt_tokens", 0)),
            generated_tokens=timings.get("predicted_n", body.get("usage", {}).get("completion_tokens", 0)),
            prefill_ms=timings.get("prompt_ms", 0.0),
            decode_ms=timings.get("predicted_ms", 0.0),
            total_ms=round(total_ms, 1),
        )


def get_backend(spec: ModelSpec, models_dir: str | Path = "~/Projects/Rescate/eval/models") -> LlamaCppBackend | OpenAICompatBackend:
    """Resolve a ModelSpec to a ready backend.

    Resolution order:
      1. $RESCATE_EVAL_SERVER_URL env → OpenAICompatBackend (external llama-server)
      2. local GGUF file in models_dir → LlamaCppBackend (in-process)
      3. else raise with download instructions
    """
    import os

    server = os.environ.get("RESCATE_EVAL_SERVER_URL")
    if server:
        return OpenAICompatBackend(server, model=spec.name)

    path = Path(models_dir).expanduser() / spec.gguf_file
    if path.exists():
        return LlamaCppBackend(path, ctx_size=spec.ctx_size, n_threads=spec.n_threads)
    raise FileNotFoundError(
        f"Model file not found: {path}\n"
        f"Download with:\n"
        f"  huggingface-cli download {spec.repo_id} {spec.gguf_file} --local-dir "
        f"{Path(models_dir).expanduser()}\n"
        f"or set RESCATE_EVAL_SERVER_URL to a running llama-server."
    )


def save_results(results: dict | list, name: str) -> Path:
    out = Path(__file__).resolve().parents[1] / "results"
    out.mkdir(exist_ok=True)
    path = out / f"{name}.json"
    path.write_text(json.dumps(results, ensure_ascii=False, indent=1, default=str))
    return path
