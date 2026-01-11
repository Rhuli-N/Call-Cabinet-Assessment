# ==============================================================================
# Multi-stage build for smaller image size and better security
# ==============================================================================

# ------------------------------------------------------------------------------
# STAGE 1: Builder - Install dependencies
# ------------------------------------------------------------------------------
FROM python:3.11-slim as builder

# Set working directory
WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements only (cached if unchanged)    
COPY requirements.txt .

# Install Python dependencies into a virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ------------------------------------------------------------------------------
# STAGE 2: Runtime - Final lightweight image
# ------------------------------------------------------------------------------
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy only the virtual environment from builder
COPY --from=builder /opt/venv /opt/venv

# Set environment variables
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Create non-root user for security
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

# Copy application code
COPY --chown=appuser:appuser main.py .

# Switch to non-root user
USER appuser

# Expose port 8000 (FastAPI default)
EXPOSE 8000

# Run the application with uvicorn
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]