# Task C: Optimization & Internals

## Question 1: Event Loop & CPU Blocking

**Scenario:** In our main.py, we used asyncio.sleep(3). In a real scenario, calculating sentiment_score using a Transformer model is a CPU-bound operation (heavy math).

**Question:** What happens to the FastAPI server if we run a heavy CPU task directly inside an async def function? How does this affect the Python Global Interpreter Lock (GIL) and other incoming requests? Explain how you would re-architect the code to solve this blocking issue without adding new servers.

**Answer:**

When you run a heavy CPU task directly inside an async def function, the FastAPI server becomes unresponsive to other requests. The async function holds the GIL during the entire computation, blocking the event loop. Unlike await asyncio.sleep(3), which yields control back to the event loop to handle other requests, CPU-intensive work without await points never releases control.

The Python GIL (Global Interpreter Lock) is a mutex that allows only one thread to execute Python bytecode at a time. While the GIL releases during I/O operations (making async/await effective for I/O-bound tasks), it remains locked during CPU-bound computations. When a transformer model calculates sentiment scores, it holds the GIL continuously. The event loop cannot process any other incoming requests during this time, effectively making the server single-threaded and blocking all other clients.

To re-architect the code without adding new servers, use Python's ProcessPoolExecutor to offload CPU-bound work to separate processes. Each process has its own GIL, enabling true parallel execution. Here's the solution:

```python
from concurrent.futures import ProcessPoolExecutor
import asyncio

# Initialize at application startup
process_pool = ProcessPoolExecutor(max_workers=4)

def calculate_sentiment(text: str) -> float:
    """
    CPU-intensive function that runs in a separate process.
    This is where the transformer model inference happens.
    """
    # In production: model.predict(text)
    # Simulated here with time.sleep(2)
    return 0.85

async def run_data_pipeline(tenant_id: str, data: TranscriptPayload, db: dict):
    """
    Re-architected to keep the event loop responsive.
    """
    loop = asyncio.get_event_loop()
    
    # Offload CPU work to process pool - event loop stays free
    sentiment_score = await loop.run_in_executor(
        process_pool,
        calculate_sentiment,
        data.text
    )
    
    # Continue processing with the result
    result = {
        "conversation_id": data.conversation_id,
        "sentiment_score": sentiment_score,
        "status": "COMPLETED"
    }
    
    if tenant_id not in db:
        db[tenant_id] = {}
    db[tenant_id][data.conversation_id] = result

@app.on_event("shutdown")
async def shutdown():
    process_pool.shutdown(wait=True)
```

This approach works because run_in_executor returns a coroutine that the event loop can await. While the CPU work happens in a separate process (with its own GIL), the main event loop remains free to handle incoming requests. The server can now process multiple requests concurrently - some handling I/O operations and others waiting for CPU-intensive work to complete in background processes.

For production systems processing high volumes, the architecture should evolve further to use a message queue. The API would immediately return after queuing work to Azure Storage Queue, and dedicated worker processes would consume messages and perform the CPU-intensive computations independently. This decouples the API server from processing workloads entirely, but ProcessPoolExecutor provides a simpler solution that works effectively on a single server.

---

## Question 2: Memory Management (Streaming vs. Loading)

**Scenario:** A client uploads a massive transcript file (500MB JSON). If we load this into a Pydantic model (class Payload(BaseModel)), Python might consume 2GB+ of RAM due to overhead, triggering an OOM (Out of Memory) kill.

**Question:** How would you process this large JSON file in Python without loading the entire object into memory at once? Describe the specific Python libraries or patterns you would use.

**Answer:**

The memory problem occurs because json.load() reads the entire file into a Python dictionary at once. A 500MB JSON file typically expands to approximately 1GB in memory due to Python's object overhead - each dictionary key, value, and nested structure requires metadata storage. When this dictionary is then validated and converted into a Pydantic model, memory usage can double again to 2-3GB due to type checking, field validation, and the creation of model instances. On a server with 4GB RAM, this causes an out-of-memory kill.

The solution is incremental streaming using the ijson library. Rather than parsing the entire JSON structure at once, ijson reads the file incrementally and yields individual objects as they are encountered. For a JSON array of transcript objects, you process one at a time:

```python
import ijson
import asyncio

def stream_json_array(file_path: str):
    """
    Stream objects from a JSON array one at a time.
    Memory usage: O(1) per object instead of O(n) for entire file.
    """
    with open(file_path, 'rb') as file:
        # Parse items from array incrementally
        parser = ijson.items(file, 'item')
        for obj in parser:
            yield obj

async def process_large_file(file_path: str, db: dict):
    processed = 0
    
    for transcript_obj in stream_json_array(file_path):
        # Only one transcript in memory at this moment
        payload = TranscriptPayload(**transcript_obj)
        await run_data_pipeline("tenant_id", payload, db)
        
        processed += 1
        
        # Backpressure to avoid overwhelming downstream systems
        if processed % 100 == 0:
            await asyncio.sleep(0.1)
    
    return {"processed": processed}
```

Memory usage with this approach remains constant at approximately 10-50MB regardless of file size, because only the current object exists in memory. After processing each object, it becomes eligible for garbage collection before the next one is parsed.

An alternative pattern is JSONL (JSON Lines) format, where each line contains a complete JSON object. This is simpler to parse and produces the same constant memory usage:

```python
import json

def stream_jsonl(file_path: str):
    """Process newline-delimited JSON one line at a time."""
    with open(file_path, 'r') as file:
        for line in file:
            if line.strip():
                yield json.loads(line)
```

The JSONL format is often preferable for log files and data pipelines because it is simpler to parse and more resilient to corruption - a single malformed line does not invalidate the entire file.

For direct FastAPI file uploads, you can stream the incoming data rather than waiting for the complete upload:

```python
from fastapi import UploadFile

@app.post("/upload-transcripts")
async def upload_large_file(file: UploadFile):
    buffer = ""
    processed = 0
    
    # Read and process in 8KB chunks
    async for chunk in file:
        buffer += chunk.decode('utf-8')
        lines = buffer.split('\n')
        
        # Process all complete lines
        for line in lines[:-1]:
            if line.strip():
                obj = json.loads(line)
                payload = TranscriptPayload(**obj)
                await process_transcript(payload)
                processed += 1
        
        # Keep the incomplete line for next iteration
        buffer = lines[-1]
    
    return {"processed": processed}
```

The key principle across all these approaches is to process and discard each piece of data immediately rather than accumulating it in memory. This transforms the memory complexity from O(n) where n is the file size to O(1) where memory usage depends only on the size of individual objects being processed.

---

## Question 3: Database Indexing Strategy

**Scenario:** Our Transcript table has 500 million rows. We frequently query by tenant_id and created_at to show the last 7 days of data.

**Question:** Explain the difference between a B-Tree Index and a Hash Index. Which would you choose for this query pattern and why? What is the "write penalty" of adding too many indexes?

**Answer:**

A B-Tree index stores data in a sorted tree structure, which enables range queries, sorting, and prefix matching. Each node contains sorted keys that guide the search path. B-Tree indexes support operations like >=, <=, BETWEEN, and ORDER BY because the data is inherently ordered.

A Hash index computes a hash of the key and stores it in a bucket. This provides O(1) lookup time for exact matches (key = value) but cannot support range queries or sorting because the hash function destroys ordering information. Hash indexes are rarely used in practice.

For our query pattern (WHERE tenant_id = ? AND created_at >= ?), we need a B-Tree index because we're doing both an exact match on tenant_id and a range query on created_at. The optimal index is:

```sql
CREATE INDEX idx_tenant_created 
ON transcripts (tenant_id, created_at DESC);
```

The column order matters. Putting tenant_id first allows the database to quickly locate all rows for a specific tenant, then the created_at ordering lets it efficiently scan just the date range we need. The DESC ordering matches our typical ORDER BY created_at DESC query pattern, making the sort operation essentially free.

The write penalty refers to the overhead of maintaining indexes during INSERT, UPDATE, and DELETE operations. Every index must be updated whenever data changes. With no indexes, an insert is a single write operation. With five indexes, that becomes six writes - one to the table and one to each index. Each index typically adds 30-50% write overhead.

The penalty compounds with more indexes. In a high-write system, too many indexes can reduce throughput by 3-5x. Indexes also consume storage - a table with five indexes might use 60-80% additional disk space for the index data.

The key is to only index columns that appear in WHERE clauses or JOIN conditions. Each index should support actual queries. Remove unused indexes periodically by checking query statistics. For most tables, 3-5 well-designed indexes is optimal - enough to support common queries without significantly impacting write performance.