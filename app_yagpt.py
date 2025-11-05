from fastapi import FastAPI
from pydantic import BaseModel
from vllm import LLM, SamplingParams
from transformers import AutoTokenizer
import uvicorn
import os


MODEL_NAME = "yandex/YandexGPT-5-Lite-8B-instruct"

tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

# Получаем параметры из переменных окружения или используем значения по умолчанию
gpu_memory_util = float(os.environ.get("GPU_MEMORY_UTILIZATION", "0.9"))
max_model_length = int(os.environ.get("MAX_MODEL_LEN", "16384"))

llm = LLM(
    model=MODEL_NAME,
    tensor_parallel_size=1,
    gpu_memory_utilization=gpu_memory_util,
    max_model_len=max_model_length,  # Ограничиваем длину контекста для экономии памяти KV cache
)

app = FastAPI(title="YandexGPT-8B-Lite-Instruct service")


class GenerateRequest(BaseModel):
    prompt: str
    temperature: float = 0.3


@app.post("/generate_yagpt")
def generate_yagpt(request: GenerateRequest):
    messages = [{"role": "user", "content": request.prompt}]
    input_ids = tokenizer.apply_chat_template(
        messages, tokenize=True, add_generation_prompt=True
    )[1:]
    text = tokenizer.decode(input_ids)

    sampling_params = SamplingParams(
        temperature=request.temperature,
        top_p=0.9,
        max_tokens=1024,
    )

    outputs = llm.generate(text, use_tqdm=False, sampling_params=sampling_params)
    response_text = tokenizer.decode(
        outputs[0].outputs[0].token_ids, skip_special_tokens=True
    )
    return {"response": response_text}


if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8081"))
    uvicorn.run(app, host=host, port=port)
