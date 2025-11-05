from fastapi import FastAPI
from pydantic import BaseModel
from vllm import LLM, SamplingParams
from transformers import AutoTokenizer
import uvicorn
import os


MODEL_NAME = "deepseek-ai/DeepSeek-R1-0528-Qwen3-8B"

tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

# Получаем параметры из переменных окружения или используем значения по умолчанию
gpu_memory_util = float(os.environ.get("GPU_MEMORY_UTILIZATION", "0.85"))
max_model_length = int(os.environ.get("MAX_MODEL_LEN", "8192"))  # Qwen3 поддерживает больший контекст

print(f"🔧 Параметры загрузки модели:")
print(f"   GPU Memory Utilization: {gpu_memory_util}")
print(f"   Max Model Length: {max_model_length}")

try:
    llm = LLM(
        model=MODEL_NAME,
        tensor_parallel_size=1,
        gpu_memory_utilization=gpu_memory_util,
        max_model_len=max_model_length,
        enforce_eager=False,  # Используем оптимизированный режим
    )
except ValueError as e:
    if "max seq len" in str(e).lower() or "kv cache" in str(e).lower():
        print(f"⚠️  Ошибка с max_model_len={max_model_length}, пробую уменьшить до 4096...")
        max_model_length = 4096
        llm = LLM(
            model=MODEL_NAME,
            tensor_parallel_size=1,
            gpu_memory_utilization=0.75,  # Еще меньше
            max_model_len=4096,
            enforce_eager=False,
        )
    else:
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

