from fastapi import FastAPI
from pydantic import BaseModel
from vllm import LLM, SamplingParams
from transformers import AutoTokenizer
import uvicorn
import os


# Получаем имя модели из переменной окружения (обязательно)
MODEL_NAME = os.environ.get("MODEL_NAME")
if not MODEL_NAME:
    raise ValueError("MODEL_NAME environment variable is required!")

# Получаем параметры из переменных окружения или используем значения по умолчанию
gpu_memory_util = float(os.environ.get("GPU_MEMORY_UTILIZATION", "0.85"))
max_model_length = int(os.environ.get("MAX_MODEL_LEN", "4096"))
trust_remote_code = os.environ.get("TRUST_REMOTE_CODE", "false").lower() == "true"
endpoint_name = os.environ.get("ENDPOINT_NAME", "generate")
api_title = os.environ.get("API_TITLE", f"{MODEL_NAME.split('/')[-1]} API")

print(f"🔧 Загрузка модели: {MODEL_NAME}")
print(f"🔧 Параметры загрузки:")
print(f"   GPU Memory Utilization: {gpu_memory_util}")
print(f"   Max Model Length: {max_model_length}")
print(f"   Trust Remote Code: {trust_remote_code}")
print(f"   Endpoint: /{endpoint_name}")

# Загружаем tokenizer
try:
    tokenizer = AutoTokenizer.from_pretrained(
        MODEL_NAME,
        trust_remote_code=trust_remote_code
    )
except Exception as e:
    print(f"⚠️  Ошибка загрузки tokenizer: {e}")
    print("💡 Пробую с trust_remote_code=True...")
    tokenizer = AutoTokenizer.from_pretrained(
        MODEL_NAME,
        trust_remote_code=True
    )
    trust_remote_code = True

# Загружаем модель
try:
    llm = LLM(
        model=MODEL_NAME,
        tensor_parallel_size=1,
        gpu_memory_utilization=gpu_memory_util,
        max_model_len=max_model_length,
        enforce_eager=False,
        trust_remote_code=trust_remote_code,
    )
except ValueError as e:
    if "max seq len" in str(e).lower() or "kv cache" in str(e).lower():
        print(f"⚠️  Ошибка с max_model_len={max_model_length}, пробую уменьшить до 2048...")
        max_model_length = 2048
        llm = LLM(
            model=MODEL_NAME,
            tensor_parallel_size=1,
            gpu_memory_utilization=0.7,
            max_model_len=2048,
            enforce_eager=False,
            trust_remote_code=trust_remote_code,
        )
    else:
        raise
except Exception as e:
    if "model type" in str(e).lower() or "architecture" in str(e).lower():
        print(f"⚠️  Ошибка загрузки модели: {e}")
        if not trust_remote_code:
            print("💡 Пробую с trust_remote_code=True...")
            try:
                llm = LLM(
                    model=MODEL_NAME,
                    tensor_parallel_size=1,
                    gpu_memory_utilization=gpu_memory_util,
                    max_model_len=max_model_length,
                    enforce_eager=False,
                    trust_remote_code=True,
                )
            except Exception as e2:
                print(f"❌ Ошибка даже с trust_remote_code=True: {e2}")
                raise
        else:
            raise
    else:
        raise

app = FastAPI(title=api_title)


class GenerateRequest(BaseModel):
    prompt: str
    temperature: float = 0.3
    max_tokens: int = 1024


@app.post(f"/{endpoint_name}")
async def generate(request: GenerateRequest):
    messages = [{"role": "user", "content": request.prompt}]
    
    # Пробуем применить chat template
    try:
        prompt_text = tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
        )
    except Exception:
        # Если chat template не работает, используем просто prompt
        prompt_text = request.prompt
    
    sampling_params = SamplingParams(
        temperature=request.temperature,
        top_p=0.9,
        top_k=50,
        max_tokens=request.max_tokens,
    )

    outputs = llm.generate(
        prompt_text,
        use_tqdm=False,
        sampling_params=sampling_params,
    )

    # Получаем ответ
    if hasattr(outputs[0].outputs[0], 'text'):
        response_text = outputs[0].outputs[0].text.strip()
    else:
        response_text = tokenizer.decode(
            outputs[0].outputs[0].token_ids,
            skip_special_tokens=True
        ).strip()
    
    return {"response": response_text}


if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8080"))
    uvicorn.run(app, host=host, port=port)

