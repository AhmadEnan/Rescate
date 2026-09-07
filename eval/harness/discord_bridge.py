"""Discord bridge: talk to Rescate's model+RAG workflow from the Discord bot.

This is the exploration mirror of the app's AI pipeline (issue #14): a
Discord message in -> mirror RAG retrieve -> prompt build (exact Gemma 4
template) -> model generate -> reply, with the retrieved sources cited so
retrieval quality is visible in conversation.

Modes (RESCATE_EVAL_SERVER_URL or local GGUF — see llm_harness.get_backend):
  python3 eval/harness/discord_bridge.py --model gemma-4-e2b-q4km   # poll mode
  python3 eval/harness/discord_bridge.py --oneshot "كيف أعالج حرق؟" # single query

The poll mode reads pending messages from a queue file written by the Hermes
agent (eval/queue/inbox/*.json) and writes replies to eval/queue/outbox/.
The Hermes side moves messages in/out — see the agent-side glue in
eval/harness/README.md. This keeps the bridge free of any Discord token
handling; the agent already owns the Discord connection.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "eval"))

from rag_mirror.legacy_rag import LegacyRag  # noqa: E402
from harness.llm_harness import get_backend, ModelSpec, save_results  # noqa: E402

QUEUE_IN = _REPO / "eval" / "queue" / "inbox"
QUEUE_OUT = _REPO / "eval" / "queue" / "outbox"


def build_backend(model: str, gguf: str | None):
    if gguf:
        spec = ModelSpec(name=model, repo_id="local", gguf_file=Path(gguf).name)
        return get_backend(spec, models_dir=str(Path(gguf).parent))
    models = json.loads((_REPO / "eval" / "harness" / "models.json").read_text())
    if model not in models:
        raise SystemExit(f"Unknown model '{model}'. Known: {sorted(models)}")
    m = models[model]
    return get_backend(ModelSpec(name=model, repo_id=m["repo_id"], gguf_file=m["gguf_file"],
                                 ctx_size=m.get("ctx_size", 4096)))


def ask(rag: LegacyRag, backend, question: str, top_k: int = 5, max_tokens: int = 512) -> dict:
    ctx = rag.answer_context(question, top_k=top_k)
    gen = backend.generate(ctx["prompt"], max_tokens=max_tokens)
    return {
        "question": question,
        "answer": gen.text.strip(),
        "sources": [c["source"] for c in ctx["chunks"]],
        "scores": [round(c["score"], 1) for c in ctx["chunks"]],
        "language": ctx["language"],
        "timing": gen.to_dict(),
    }


def format_reply(result: dict) -> str:
    src = "\n".join(f"• `{s}` ({sc})" for s, sc in zip(result["sources"], result["scores"]))
    return (
        f"**Rescate mirror** ({result['language'].upper()} · {result['timing']['generated_tokens']} tok · "
        f"{result['timing']['total_ms']:.0f} ms)\n\n"
        f"{result['answer']}\n\n**Retrieved chunks:**\n{src}"
    )


def poll_once(rag, backend, state_path: Path) -> int:
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state = json.loads(state_path.read_text()) if state_path.exists() else {"seen": []}
    seen = set(state["seen"])
    handled = 0
    for msg_file in sorted(QUEUE_IN.glob("*.json")):
        msg = json.loads(msg_file.read_text())
        mid = msg.get("id") or msg_file.stem
        if mid in seen:
            continue
        result = ask(rag, backend, msg["text"])
        out = {
            "id": mid,
            "reply": format_reply(result),
            "result": result,
            "answered_at": time.time(),
        }
        QUEUE_OUT.mkdir(parents=True, exist_ok=True)
        (QUEUE_OUT / f"{mid}.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))
        seen.add(mid)
        msg_file.unlink(missing_ok=True)
        handled += 1
    state["seen"] = sorted(seen)[-500:]
    state_path.write_text(json.dumps(state))
    return handled


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="gemma-4-e2b-q4km")
    ap.add_argument("--gguf", help="direct GGUF path override")
    ap.add_argument("--oneshot", help="single question, prints answer, exits")
    ap.add_argument("--poll", action="store_true", help="serve the Discord queue loop")
    ap.add_argument("--interval", type=float, default=2.0)
    ap.add_argument("--top-k", type=int, default=5)
    ap.add_argument("--max-tokens", type=int, default=512)
    args = ap.parse_args()

    rag = LegacyRag()
    backend = build_backend(args.model, args.gguf)

    if args.oneshot:
        result = ask(rag, backend, args.oneshot, top_k=args.top_k, max_tokens=args.max_tokens)
        print(format_reply(result))
        save_results(result, f"oneshot_{uuid.uuid4().hex[:8]}")
        return 0

    if args.poll:
        print(f"Serving Discord mirror queue ({args.model}). Ctrl-C to stop.")
        while True:
            n = poll_once(rag, backend, _REPO / "eval" / "queue" / "state.json")
            if n:
                print(f"answered {n} message(s)")
            time.sleep(args.interval)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
