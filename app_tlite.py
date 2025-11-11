from fastapi import FastAPI
from pydantic import BaseModel
from transformers import AutoTokenizer
from vllm import LLM, SamplingParams
import uvicorn
import os


MODEL_NAME = "t-tech/T-lite-it-1.0"

tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
llm = LLM(
    model=MODEL_NAME,
    tensor_parallel_size=1,
    gpu_memory_utilization=0.9,
    max_model_len=1024,
)


app = FastAPI(title="T-lite-it-1.0 API")


class GenerateRequest(BaseModel):
    prompt: str
    temperature: float = 0.3
    top_p: 0.8
    top_k: 70


@app.post("/generate_tlite")
async def generate_tlite(request: GenerateRequest):
    messages = [
        {
            "role": "system",
            "content": (
                "Ты T-lite, виртуальный ассистент в Weyland-Yutani. "
                "Твоя задача — быть полезным диалоговым ассистентом."
            ),
        },
        {"role": "user", "content": request.prompt},
    ]
    sampling_params = SamplingParams(
        temperature=request.temperature,
        repetition_penalty=1.05,
        top_p=request.top_p,
        top_k=request.top_k,
        max_tokens=2048,
        )


    prompt_token_ids = tokenizer.apply_chat_template(
        messages,
        add_generation_prompt=True,
        tokenize=False,
    )


    outputs = llm.generate(
        prompt_token_ids,
        sampling_params=sampling_params,
    )

    result = outputs[0].outputs[0].text.strip()
    return {"response": result}


if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8083"))
    uvicorn.run(app, host=host, port=port)
