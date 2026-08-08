import json
import os
import re
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding='utf-8')

PROMPTS = [
    {
        "id": "burn",
        "isArabic": False,
        "text": "A person has a severe burn. What should I do in the first five minutes?"
    },
    {
        "id": "unconscious_breathing",
        "isArabic": False,
        "text": "Someone is unconscious but breathing normally. What position and checks should I use?"
    },
    {
        "id": "bleach_ingestion",
        "isArabic": False,
        "text": "A child may have swallowed bleach. What immediate steps are safe and what must I avoid?"
    },
    {
        "id": "arabic_burn",
        "isArabic": True,
        "text": "شخص لديه حرق شديد. ماذا أفعل في الدقائق الخمس الأولى؟"
    }
]

PACKAGE = "com.example.rescate_app"

def get_device_serial():
    try:
        out = subprocess.check_output(["adb", "devices"], text=True)
        lines = [l.strip() for l in out.splitlines() if l.strip() and not l.startswith("List of")]
        for l in lines:
            parts = l.split()
            if len(parts) >= 2 and parts[1] == "device":
                return parts[0]
    except Exception:
        pass
    return None

def adb_cmd(args):
    serial = get_device_serial()
    if serial:
        return ["adb", "-s", serial] + args
    return ["adb"] + args

def get_profiler_files():
    try:
        out = subprocess.check_output(
            adb_cmd(["shell", "run-as", PACKAGE, "ls", "-la", "app_flutter/profiler"]),
            text=True, stderr=subprocess.DEVNULL
        )
        return re.findall(r"session_\d+_\w+\.json", out)
    except Exception:
        return []

def get_latest_chat_turn():
    files = get_profiler_files()
    chat_turns = [f for f in files if "chat_turn" in f]
    return max(chat_turns) if chat_turns else None

def wait_for_turn_complete(initial_file, timeout_sec=600):
    start = time.time()
    print(f"Waiting for new chat_turn profiler export (initial: {initial_file})...")
    while time.time() - start < timeout_sec:
        current = get_latest_chat_turn()
        if current and current != initial_file:
            print(f"New chat turn exported: {current}")
            return current
        time.sleep(5)
    print("Timeout waiting for chat turn completion.")
    return None

def start_new_chat():
    print("Clicking New Chat...")
    subprocess.run(adb_cmd(["shell", "input", "tap", "830", "563"]))
    time.sleep(2)

def send_prompt(prompt_obj):
    start_new_chat()
    text = prompt_obj["text"]
    print(f"Sending prompt [{prompt_obj['id']}]: {text}")
    
    if not prompt_obj["isArabic"]:
        # Sanitize for adb input text
        escaped = text.replace(" ", "%s").replace("?", "\\?").replace("'", "\\'")
        subprocess.run(adb_cmd(["shell", "input", "tap", "471", "2015"]))
        time.sleep(1)
        subprocess.run(adb_cmd(["shell", "input", "text", escaped]))
        time.sleep(1)
        subprocess.run(adb_cmd(["shell", "input", "tap", "970", "2015"]))
    else:
        # Tapping the input field and using paste or broadcast
        subprocess.run(adb_cmd(["shell", "input", "tap", "471", "2015"]))
        time.sleep(1)
        # Pass Arabic via clip or broadcast
        subprocess.run(adb_cmd(["shell", "am", "broadcast", "-a", "ADB_INPUT_TEXT", "--es", "msg", text]))
        time.sleep(1)
        subprocess.run(adb_cmd(["shell", "input", "tap", "970", "2015"]))

def pull_and_convert(latest_file):
    print(f"Pulling {latest_file} -> profiler_report.json...")
    data = subprocess.check_output(
        adb_cmd(["shell", "run-as", PACKAGE, "cat", f"app_flutter/profiler/{latest_file}"])
    )
    with open("profiler_report.json", "wb") as f:
        f.write(data)
    
    print("Converting profiler_report.json -> benchmarks/benchmark_report.json...")
    subprocess.run(
        "dart run packages/ai_inference/tool/benchmark_report.dart profiler_report.json benchmarks/benchmark_report.json",
        shell=True, check=True
    )
    print("Benchmark report updated successfully!")

def run_suite():
    # 1 Warmup turn per case, then 3 measured turns per case in order
    runs = [
        ("warmup", p) for p in PROMPTS
    ] + [
        (f"measured_{iter_num}", p) for iter_num in range(1, 4) for p in PROMPTS
    ]
    
    print(f"Starting full benchmark suite ({len(runs)} turns total)...")
    for phase, prompt in runs:
        print(f"\n--- Starting {phase} for prompt '{prompt['id']}' ---")
        current_latest = get_latest_chat_turn()
        send_prompt(prompt)
        completed = wait_for_turn_complete(current_latest, timeout_sec=600)
        if completed:
            pull_and_convert(completed)
        else:
            print(f"FAILED: Turn did not complete for {prompt['id']} in {phase}")

if __name__ == "__main__":
    latest = get_latest_chat_turn()
    print(f"Current latest chat turn file: {latest}")
    if latest:
        pull_and_convert(latest)
    run_suite()
