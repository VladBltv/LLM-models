from fastapi import FastAPI
from pydantic import BaseModel
from vllm import LLM, SamplingParams
from transformers import AutoTokenizer
import uvicorn


MODEL_NAME = "Vikhrmodels/Vikhr-Nemo-12B-Instruct-R-21-09-24"


tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

llm = LLM(
    model=MODEL_NAME,
    tensor_parallel_size=1,
    gpu_memory_utilization=0.9,
    max_model_len=1024,
)


app = FastAPI(title="Vikhr-Nemo-12B-Instruct API")

class GenerateRequest(BaseModel):
    prompt: str
    temperature: float = 0.3


@app.post("/generate_vikhr")
def generate_vikhr(request: GenerateRequest):
    messages = [{"role": "user", "content": request.prompt}]
    prompt_text = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    sampling_params = SamplingParams(
        temperature=request.temperature,
        top_p=0.9,
        top_k=42,
        max_tokens=1024,
    )

    outputs = llm.generate(prompt_text, use_tqdm=False, sampling_params=sampling_params)
    response_text = outputs[0].outputs[0].text

    return {"response": response_text}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8082)
