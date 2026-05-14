#!/usr/bin/env python3
"""
Скрипт для конвертации модели sphere_047_m4_overnight в формат GGUF
"""

import os
import sys
from pathlib import Path
import subprocess

def main():
    print("=== Конвертация sphere_047_m4_overnight в GGUF ===\n")
    
    # Создаем виртуальное окружение
    venv_path = Path("venv_convert")
    if not venv_path.exists():
        print("1. Создание виртуального окружения...")
        subprocess.run([sys.executable, "-m", "venv", str(venv_path)], check=True)
    
    # Определяем путь к pip в venv
    if sys.platform == "win32":
        pip_path = venv_path / "Scripts" / "pip"
        python_path = venv_path / "Scripts" / "python"
    else:
        pip_path = venv_path / "bin" / "pip"
        python_path = venv_path / "bin" / "python"
    
    # Устанавливаем необходимые зависимости
    print("\n2. Установка зависимостей...")
    packages = [
        "transformers",
        "torch",
        "peft",
        "huggingface-hub",
        "sentencepiece",
        "protobuf",
        "accelerate",
        "safetensors",
        "mistral-common",
        "gguf"
    ]
    
    subprocess.run([
        str(pip_path), "install", "--upgrade", "pip",
        "--trusted-host", "pypi.org",
        "--trusted-host", "pypi.python.org",
        "--trusted-host", "files.pythonhosted.org"
    ])
    
    subprocess.run([
        str(pip_path), "install",
        "--trusted-host", "pypi.org",
        "--trusted-host", "pypi.python.org",
        "--trusted-host", "files.pythonhosted.org"
    ] + packages, check=True)
    
    # Создаем директории
    models_dir = Path("models_temp")
    models_dir.mkdir(exist_ok=True)
    
    base_model_path = models_dir / "base_model"
    lora_path = models_dir / "lora_adapter"
    merged_path = models_dir / "merged_model"
    gguf_path = models_dir / "gguf"
    
    for path in [base_model_path, lora_path, merged_path, gguf_path]:
        path.mkdir(exist_ok=True)
    
    print("\n3. Создание скрипта объединения моделей...")
    
    # Создаем скрипт для скачивания и объединения
    merge_script = """
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel
import torch

print("Загрузка базовой модели TinyLlama...")
base_model = AutoModelForCausalLM.from_pretrained(
    "TinyLlama/TinyLlama-1.1B-Chat-v1.0",
    torch_dtype=torch.float16,
    device_map="auto"
)

print("Загрузка LoRA адаптера...")
model = PeftModel.from_pretrained(
    base_model,
    "nativemind/sphere_047_m4_overnight"
)

print("Объединение LoRA с базовой моделью...")
merged_model = model.merge_and_unload()

print("Загрузка токенизатора...")
tokenizer = AutoTokenizer.from_pretrained("nativemind/sphere_047_m4_overnight")

print("Сохранение объединенной модели...")
merged_model.save_pretrained("models_temp/merged_model", safe_serialization=True)
tokenizer.save_pretrained("models_temp/merged_model")

print("✓ Модель успешно объединена и сохранена!")
"""
    
    with open("merge_model.py", "w") as f:
        f.write(merge_script)
    
    print("\n4. Объединение LoRA с базовой моделью...")
    result = subprocess.run([str(python_path), "merge_model.py"])
    
    if result.returncode != 0:
        print("✗ Ошибка при объединении модели")
        sys.exit(1)
    
    print("\n5. Конвертация в формат GGUF...")
    convert_cmd = [
        str(python_path),
        "llama.cpp/convert_hf_to_gguf.py",
        "models_temp/merged_model",
        "--outtype", "f16",
        "--outfile", "models_temp/gguf/sphere_047_m4_overnight.gguf"
    ]
    
    result = subprocess.run(convert_cmd)
    
    if result.returncode != 0:
        print("✗ Ошибка при конвертации в GGUF")
        sys.exit(1)
    
    print("\n6. Квантизация модели...")
    # Создаем квантизованные версии
    quantize_types = ["q4_0", "q4_k_m", "q5_k_m", "q8_0"]
    
    # Сначала нужно скомпилировать llama.cpp если еще не скомпилирован
    quantize_bin = Path("llama.cpp/build/bin/llama-quantize")
    if not quantize_bin.exists():
        print("Компиляция llama.cpp...")
        os.chdir("llama.cpp")
        subprocess.run(["cmake", "-B", "build"], check=True)
        subprocess.run(["cmake", "--build", "build", "--config", "Release"], check=True)
        os.chdir("..")
    
    for qtype in quantize_types:
        print(f"\nКвантизация {qtype.upper()}...")
        quantize_cmd = [
            str(quantize_bin),
            "models_temp/gguf/sphere_047_m4_overnight.gguf",
            f"models_temp/gguf/sphere_047_m4_overnight-{qtype}.gguf",
            qtype
        ]
        subprocess.run(quantize_cmd)
    
    print("\n" + "="*60)
    print("✓ Конвертация завершена!")
    print("\nСозданные файлы:")
    print(f"  - models_temp/gguf/sphere_047_m4_overnight.gguf (F16)")
    for qtype in quantize_types:
        gguf_file = Path(f"models_temp/gguf/sphere_047_m4_overnight-{qtype}.gguf")
        if gguf_file.exists():
            size_mb = gguf_file.stat().st_size / (1024 * 1024)
            print(f"  - {gguf_file.name} ({size_mb:.1f} MB)")
    print("="*60)
    
    print("\n7. Подготовка к загрузке на HuggingFace...")
    print("\nДля загрузки на HuggingFace выполните:")
    print(f"  huggingface-cli login")
    print(f"  {python_path} upload_to_hf.py")

if __name__ == "__main__":
    main()
