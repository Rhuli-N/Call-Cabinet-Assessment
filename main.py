import asyncio
import random
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Header, BackgroundTasks, Depends
from pydantic import BaseModel

app = FastAPI(title="Smarsh Backend Assessment")

# --- IN-MEMORY DATA STORE (Mocking SQL/Elastic) ---
DB = {}

def get_db():
    """
    Dependency function that provides database access.
    
    FastAPI will call this function and inject the result into endpoints.
    """
    return DB


# --- MODELS ---
class TranscriptPayload(BaseModel):
    conversation_id: str
    text: str

class AgentResponse(BaseModel):
    conversation_id: str
    sentiment_score: float
    summary: str
    tags: List[str]
    status: str

# --- ASYNC PROCESSOR (Simulating your "Pipeline") ---
async def run_data_pipeline(tenant_id: str, data: TranscriptPayload, db: dict):
    """
    Simulates a microservice that processes data asynchronously.
    """
    await asyncio.sleep(3)  # Simulate Queue Latency
    
    # Simulate Non-Deterministic AI Enrichment
    base_sentiment = 0.8
    variance = random.uniform(-0.1, 0.1)
    
    result = {
        "conversation_id": data.conversation_id,
        "sentiment_score": round(base_sentiment + variance, 3),
        "summary": f"Processed text length {len(data.text)}.",
        "tags": ["finance", "risk"] if "money" in data.text else ["general"],
        "status": "COMPLETED",
        "tenant_id": tenant_id
    }
    
    # Persist to Mock DB
    if tenant_id not in db:
        db[tenant_id] = {}
    db[tenant_id][data.conversation_id] = result

# --- ENDPOINTS ---
@app.post("/ingest", status_code=202)
async def ingest_transcript(
    payload: TranscriptPayload,
    background_tasks: BackgroundTasks,
    x_tenant_id: str = Header(...),
    db: dict = Depends(get_db)
):
    if not x_tenant_id:
        raise HTTPException(status_code=400, detail="Missing Tenant ID")
    
    background_tasks.add_task(run_data_pipeline, x_tenant_id, payload, db)
    return {"message": "Ingest started", "job_id": payload.conversation_id, "status": "QUEUED"}

@app.get("/results/{conversation_id}", response_model=AgentResponse)
async def get_result(conversation_id: str, x_tenant_id: str = Header(...), db: dict = Depends(get_db)):
    """
    Retrieves processed data. STRICTLY ISOLATED by x_tenant_id.
    """
    tenant_db = db.get(x_tenant_id, {})
    item = tenant_db.get(conversation_id)
    
    if not item:
        raise HTTPException(status_code=404, detail="Item not found or processing")
    return item