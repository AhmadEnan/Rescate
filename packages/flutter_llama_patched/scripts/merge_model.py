
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
