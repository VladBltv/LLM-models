from fastapi import FastAPI
from pydantic import BaseModel
from vllm import LLM, SamplingParams
from transformers import AutoTokenizer
import uvicorn
import os


MODEL_NAME = "TeichAI/gpt-oss-20b-claude-4.5-sonnet-high-reasoning-distill"

tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

# Получаем параметры из переменных окружения или используем значения по умолчанию
gpu_memory_util = float(os.environ.get("GPU_MEMORY_UTILIZATION", "0.75"))
max_model_length = int(os.environ.get("MAX_MODEL_LEN", "4096"))  # Уменьшено для экономии памяти

print(f"🔧 Параметры загрузки модели:")
print(f"   GPU Memory Utilization: {gpu_memory_util}")
print(f"   Max Model Length: {max_model_length}")

try:
    llm = LLM(
        model=MODEL_NAME,
        tensor_parallel_size=1,
        gpu_memory_utilization=gpu_memory_util,
        max_model_len=max_model_length,  # Ограничиваем длину контекста для экономии памяти KV cache
        enforce_eager=False,  # Используем оптимизированный режим
    )
except ValueError as e:
    if "max seq len" in str(e).lower() or "kv cache" in str(e).lower():
        print(f"⚠️  Ошибка с max_model_len={max_model_length}, пробую уменьшить до 2048...")
        max_model_length = 2048
        llm = LLM(
            model=MODEL_NAME,
            tensor_parallel_size=1,
            gpu_memory_utilization=0.7,  # Еще меньше
            max_model_len=2048,
            enforce_eager=False,
        )
    else:
        raise

app = FastAPI(title="GPT-OSS-20B-Claude-4.5-Sonnet-High-Reasoning-Distill API")


class GenerateRequest(BaseModel):
    prompt: str
    temperature: float = 0.3


@app.post("/generate_gptoss")
async def generate_gptoss(request: GenerateRequest):
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
        max_tokens=1024,
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
    port = int(os.environ.get("PORT", "8084"))
    uvicorn.run(app, host=host, port=port)

