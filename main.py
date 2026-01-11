import asyncio
import random
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Header, BackgroundTasks, Depends
from pydantic import BaseModel, field_validator

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
    
    @field_validator('text')
    @classmethod
    def validate_text(cls, v: str) -> str:
        """
        Validates text field before processing.
        
        Rules:
        - Must not be empty (after stripping whitespace)
        - Must not exceed 5000 characters
        
        Raises:
        - ValueError: If validation fails (FastAPI converts to 422)
        """
        # Check if empty (after stripping whitespace)
        if not v or not v.strip():
            raise ValueError('Text field cannot be empty')
        
        # Check if exceeds 5000 characters
        if len(v) > 5000:
            raise ValueError('Text field cannot exceed 5000 characters')
        
        return v

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


async def run_rescore_pipeline(tenant_id: str, conversation_id: str, db: dict):
    """
    Re-calculates sentiment score for existing transcript.
    Adds 'review_required' tag if score drops below 0.5.
    """
    await asyncio.sleep(3)  # Simulate AI processing time
    
    # Fetch existing data
    tenant_db = db.get(tenant_id, {})
    existing_transcript = tenant_db.get(conversation_id)
    
    if not existing_transcript:
        return  # Item not found
    
    old_score = existing_transcript["sentiment_score"]
    variance = random.uniform(-0.5, 0.1)  # bias toward negative
    new_score = max(0.0, min(1.0, round(old_score + variance, 3)))
    existing_transcript["sentiment_score"] = new_score
    
    if new_score < 0.5 and "review_required" not in existing_transcript["tags"]:
        existing_transcript["tags"].append("review_required")
    
    db[tenant_id][conversation_id] = existing_transcript

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

@app.post("/rescore/{conversation_id}", status_code=202)
async def rescore_transcript(
    conversation_id: str,
    background_tasks: BackgroundTasks,
    x_tenant_id: str = Header(...),
    db: dict = Depends(get_db)
):
    """
    Re-scores an existing transcript.
    """
    # Check if transcript exists before queuing
    tenant_db = db.get(x_tenant_id, {})
    if conversation_id not in tenant_db:
        raise HTTPException(status_code=404, detail="Transcript not found")
    
    # Queue the re-score task
    background_tasks.add_task(run_rescore_pipeline, x_tenant_id, conversation_id, db)
    
    return {
        "message": "Re-score started",
        "job_id": conversation_id,
        "status": "QUEUED"
    }

#--- HELPER ENDPOINT ---
@app.get("/debug/db")
async def debug_view_db(db: dict = Depends(get_db)):
    """
    DEBUG ONLY: View entire database contents.
    
    Returns the entire in-memory database structure.
    """
    return {
        "database": db,
        "tenant_count": len(db),
        "total_records": sum(len(tenant_data) for tenant_data in db.values())
    }