import os
import sys

# Устанавливаем переменную окружения для transformers
os.environ["TRUST_REMOTE_CODE"] = "true"

# Проверяем и обновляем transformers ДО любых импортов
print("🔧 Проверка версии transformers...")
try:
    import subprocess
    # Получаем текущую версию
    result = subprocess.run(
        [sys.executable, "-m", "pip", "show", "transformers"],
        capture_output=True,
        text=True,
        timeout=30
    )
    current_version = None
    if result.returncode == 0:
        for line in result.stdout.split('\n'):
            if line.startswith('Version:'):
                current_version = line.split(':')[1].strip()
                break
    print(f"   Текущая версия: {current_version or 'неизвестна'}")
    
    # Обновляем transformers до последней версии (принудительно)
    print("🔧 Обновление transformers до последней версии...")
    result = subprocess.run(
        [sys.executable, "-m", "pip", "install", "--upgrade", "--force-reinstall", "transformers>=4.40.0", "--no-cache-dir"],
        timeout=300,
        capture_output=True,
        text=True
    )
    if result.returncode == 0:
        print("✅ transformers обновлен")
        # Проверяем новую версию
        result2 = subprocess.run(
            [sys.executable, "-m", "pip", "show", "transformers"],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result2.returncode == 0:
            for line in result2.stdout.split('\n'):
                if line.startswith('Version:'):
                    new_version = line.split(':')[1].strip()
                    print(f"   Новая версия: {new_version}")
                    break
    else:
        print(f"⚠️  transformers не обновлен")
        print(f"   Ошибка: {result.stderr[:200]}")
        print("💡 Продолжаю с текущей версией...")
except Exception as e:
    print(f"⚠️  Ошибка проверки/обновления transformers: {e}")
    print("💡 Продолжаю с текущей версией...")

# Импортируем библиотеки ПОСЛЕ обновления
from fastapi import FastAPI
from pydantic import BaseModel

# Импортируем transformers и проверяем версию
print("🔧 Импорт transformers...")
try:
    import transformers
    transformers_version = transformers.__version__
    print(f"   Версия transformers в Python: {transformers_version}")
    
    # Проверяем, достаточно ли новая версия (qwen3 требует transformers >= 4.40.0)
    version_parts = transformers_version.split('.')
    major = int(version_parts[0]) if len(version_parts) > 0 and version_parts[0].isdigit() else 0
    minor = int(version_parts[1]) if len(version_parts) > 1 and version_parts[1].isdigit() else 0
    
    if major < 4 or (major == 4 and minor < 40):
        print(f"⚠️  ВНИМАНИЕ: Версия transformers {transformers_version} слишком старая для qwen3")
        print("💡 Требуется transformers >= 4.40.0")
        print("💡 Принудительное обновление...")
        result = subprocess.run(
            [sys.executable, "-m", "pip", "install", "--upgrade", "--force-reinstall", "transformers>=4.40.0", "--no-cache-dir"],
            timeout=300,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            # Перезагружаем модуль
            import importlib
            importlib.reload(transformers)
            transformers_version = transformers.__version__
            print(f"   ✅ После обновления: {transformers_version}")
        else:
            print(f"   ❌ Ошибка обновления: {result.stderr[:300]}")
            raise RuntimeError(f"Не удалось обновить transformers до версии >= 4.40.0. Текущая версия: {transformers_version}")
    else:
        print(f"✅ Версия transformers {transformers_version} подходит для qwen3")
except Exception as e:
    print(f"❌ КРИТИЧЕСКАЯ ОШИБКА проверки transformers: {e}")
    raise

from transformers import AutoTokenizer

MODEL_NAME = "deepseek-ai/DeepSeek-R1-0528-Qwen3-8B"

# Очищаем кэш transformers перед загрузкой (на всякий случай)
print("🔧 Очистка кэша transformers...")
try:
    from transformers.utils import TRANSFORMERS_CACHE
    import shutil
    if os.path.exists(TRANSFORMERS_CACHE):
        print(f"   Кэш найден: {TRANSFORMERS_CACHE}")
        # Не удаляем полностью, только для этой модели
        model_cache = os.path.join(TRANSFORMERS_CACHE, "models--" + MODEL_NAME.replace("/", "--"))
        if os.path.exists(model_cache):
            print(f"   Очистка кэша модели: {model_cache}")
            shutil.rmtree(model_cache, ignore_errors=True)
except Exception as e:
    print(f"   ⚠️  Не удалось очистить кэш: {e}")

# Загружаем tokenizer с trust_remote_code для поддержки qwen3 архитектуры
print("🔧 Загрузка tokenizer с trust_remote_code=True...")
try:
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, trust_remote_code=True)
    print("✅ Tokenizer загружен")
except Exception as e:
    print(f"⚠️  Ошибка загрузки tokenizer: {e}")
    print("💡 Пробую без trust_remote_code...")
    try:
        tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, trust_remote_code=False)
        print("⚠️  Tokenizer загружен БЕЗ trust_remote_code (может не работать для qwen3)")
    except Exception as e2:
        print(f"❌ КРИТИЧЕСКАЯ ОШИБКА загрузки tokenizer: {e2}")
        raise

# Импортируем vLLM ПОСЛЕ обновления transformers
print("🔧 Импорт vLLM...")
try:
    from vllm import LLM, SamplingParams
    import vllm
    # Проверяем версию vLLM
    try:
        vllm_version = vllm.__version__
        print(f"   Версия vLLM: {vllm_version}")
    except:
        print("   Версия vLLM: неизвестна")
    import uvicorn
    print("✅ vLLM импортирован")
except Exception as e:
    print(f"❌ КРИТИЧЕСКАЯ ОШИБКА импорта vLLM: {e}")
    print("💡 Попробуйте обновить vLLM: pip install --upgrade vllm")
    raise

# Получаем параметры из переменных окружения или используем значения по умолчанию
gpu_memory_util = float(os.environ.get("GPU_MEMORY_UTILIZATION", "0.85"))
max_model_length = int(os.environ.get("MAX_MODEL_LEN", "8192"))  # Qwen3 поддерживает больший контекст

print(f"🔧 Параметры загрузки модели:")
print(f"   GPU Memory Utilization: {gpu_memory_util}")
print(f"   Max Model Length: {max_model_length}")
print(f"   Trust Remote Code: True")

try:
    print("🔧 Загрузка модели через vLLM...")
    print(f"   Модель: {MODEL_NAME}")
    print(f"   trust_remote_code: True")
    print(f"   max_model_len: {max_model_length}")
    print(f"   gpu_memory_utilization: {gpu_memory_util}")
    llm = LLM(
        model=MODEL_NAME,
        tensor_parallel_size=1,
        gpu_memory_utilization=gpu_memory_util,
        max_model_len=max_model_length,
        enforce_eager=False,  # Используем оптимизированный режим
        trust_remote_code=True,  # Необходимо для qwen3 архитектуры
    )
    print("✅ Модель успешно загружена!")
except ValueError as e:
    error_msg = str(e).lower()
    if "max seq len" in error_msg or "kv cache" in error_msg:
        print(f"⚠️  Ошибка с max_model_len={max_model_length}")
        print(f"   Детали: {str(e)[:500]}")
        print("💡 Пробую уменьшить max_model_len до 4096...")
        max_model_length = 4096
        gpu_memory_util = 0.75
        llm = LLM(
            model=MODEL_NAME,
            tensor_parallel_size=1,
            gpu_memory_utilization=gpu_memory_util,
            max_model_len=4096,
            enforce_eager=False,
            trust_remote_code=True,
        )
        print("✅ Модель загружена с уменьшенными параметрами!")
    else:
        print(f"❌ ValueError при загрузке модели: {e}")
        raise
except KeyError as e:
    error_msg = str(e).lower()
    if "qwen3" in error_msg:
        print(f"❌ КРИТИЧЕСКАЯ ОШИБКА: KeyError для 'qwen3'")
        print(f"   Это означает, что transformers не распознает архитектуру qwen3")
        print(f"   Текущая версия transformers: {transformers.__version__}")
        print(f"   Требуется transformers >= 4.40.0")
        print("💡 Попробуйте:")
        print("   1. pip install --upgrade --force-reinstall transformers>=4.40.0")
        print("   2. pip install --upgrade vllm")
        raise RuntimeError(f"transformers не поддерживает qwen3. Версия: {transformers.__version__}") from e
    else:
        print(f"❌ KeyError при загрузке модели: {e}")
        raise
except Exception as e:
    error_msg = str(e).lower()
    if "qwen3" in error_msg or "model type" in error_msg or "architecture" in error_msg:
        print(f"❌ КРИТИЧЕСКАЯ ОШИБКА загрузки модели qwen3")
        print(f"   Тип ошибки: {type(e).__name__}")
        print(f"   Сообщение: {str(e)[:800]}")
        print(f"   Версия transformers: {transformers.__version__}")
        print("💡 Решение:")
        print("   1. Убедитесь, что transformers >= 4.40.0")
        print("   2. Обновите vLLM: pip install --upgrade vllm")
        print("   3. Проверьте, что trust_remote_code=True передается в LLM()")
        raise RuntimeError(f"Не удалось загрузить модель qwen3: {e}") from e
    else:
        print(f"❌ Неожиданная ошибка при загрузке модели:")
        print(f"   Тип: {type(e).__name__}")
        print(f"   Сообщение: {str(e)[:800]}")
        raise

app = FastAPI(title="DeepSeek-R1-0528-Qwen3-8B API")


class GenerateRequest(BaseModel):
    prompt: str
    temperature: float = 0.3


@app.post("/generate_deepseek")
async def generate_deepseek(request: GenerateRequest):
    messages = [{"role": "user", "content": request.prompt}]
    
    # Применяем chat template
    prompt_text = tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True,
    )
    
    sampling_params = SamplingParams(
        temperature=request.temperature,
        top_p=0.9,
        top_k=50,
        max_tokens=2048,  # DeepSeek R1 может генерировать длинные ответы
    )

    outputs = llm.generate(
        prompt_text,
        use_tqdm=False,
        sampling_params=sampling_params,
    )

    response_text = outputs[0].outputs[0].text.strip()
    return {"response": response_text}


if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8085"))
    uvicorn.run(app, host=host, port=port)

