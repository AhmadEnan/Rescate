#!/usr/bin/env python3
"""Serve Rescate model replies to the Hermes Discord bot via the eval queue.

Watches eval/queue/inbox/ for questions the agent drops in and writes answers
to eval/queue/outbox/. One message per JSON file:
  inbox:  {"id": "<unique>", "text": "<question>"}
  outbox: {"id": ..., "reply": "<formatted answer>", "model": ...}

Run:  eval/.venv/bin/python eval/harness/queue_serve.py [--model NAME] [--interval 2]
The active model name is read from eval/queue/current_model.txt unless
overridden with --model. Logs to eval/queue/serve.log
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import traceback
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "eval"))

from rag_mirror.legacy_rag import LegacyRag  # noqa: E402
from harness.discord_bridge import (  # noqa: E402
    ask, build_backend, format_reply, QUEUE_IN, QUEUE_OUT, _REPO as REPO,
)

STATE = _REPO / "eval" / "queue" / "state.json"
CURRENT_MODEL = _REPO / "eval" / "queue" / "current_model.txt"


def current_model() -> str:
    return CURRENT_MODEL.read_text().strip() if CURRENT_MODEL.exists() else "qwen3.5-2b"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", help="model name (models.json key); default from current_model.txt")
    ap.add_argument("--interval", type=float, default=2.0)
    ap.add_argument("--max-tokens", type=int, default=400)
    args = ap.parse_args()

    fixed_model = args.model
    rag = LegacyRag()
    backend = None
    loaded_model = ""
    log = open(_REPO / "eval" / "queue" / "serve.log", "a")

    def say(msg: str) -> None:
        line = f"{time.strftime('%H:%M:%S')} {msg}"
        print(line, flush=True)
        log.write(line + "\n")
        log.flush()

    say(f"queue_serve up; inbox={QUEUE_IN}")

    def ensure_backend(model: str):
        nonlocal backend, loaded_model
        if backend is None or model != loaded_model:
            say(f"loading model: {model}")
            backend = build_backend(model, None)
            loaded_model = model
            say(f"model ready: {model}")

    while True:
        try:
            model = fixed_model or current_model()
            ensure_backend(model)
        except Exception:
            say("model load failed:\n" + traceback.format_exc())
            time.sleep(10)
            continue

        served = 0
        for msg_file in sorted(QUEUE_IN.glob("*.json")):
            try:
                msg = json.loads(msg_file.read_text())
                mid = msg.get("id") or msg_file.stem
                text = (msg.get("text") or "").strip()
                if not text:
                    msg_file.unlink(missing_ok=True)
                    continue
                say(f"answering {mid}: {text[:80]!r}")
                result = ask(rag, backend, text, max_tokens=args.max_tokens,
                             model_name=model)
                out = {
                    "id": mid,
                    "reply": format_reply(result),
                    "model": model,
                    "answered_at": time.time(),
                }
                QUEUE_OUT.mkdir(parents=True, exist_ok=True)
                (QUEUE_OUT / f"{mid}.json").write_text(
                    json.dumps(out, ensure_ascii=False, indent=1))
                msg_file.unlink(missing_ok=True)
                served += 1
            except Exception:
                say("message failed:\n" + traceback.format_exc())
                # leave the file so it can be retried/inspected
        time.sleep(args.interval if served == 0 else 0.2)


if __name__ == "__main__":
    raise SystemExit(main())
