# Cost Optimization: Scale-to-Zero

## Configuration
The infrastructure is configured to **scale to zero replicas** when idle, significantly reducing costs during off-hours.

```hcl
template {
  min_replicas = 0  # Scale to ZERO when idle
  max_replicas = 3  # Scale up to 3 during high traffic
  
  http_scale_rule {
    concurrent_requests = 10  # Add 1 replica per 10 concurrent requests
  }
}
```

## When It Works
1. **No traffic** → Container Apps scales down to 0 replicas after ~5 minutes of inactivity
2. **Request arrives** → Container spins up in 3-5 seconds (cold start)
3. **Traffic increases** → Auto-scales up to 3 replicas based on concurrent requests
4. **Traffic decreases** → Scales back down automatically

## Cost Breakdown Example

| Scenario | Replicas | Cost/Month | Savings |
|----------|----------|------------|---------|
| **Always-on** (1 replica 24/7) | 1 | ~$50-100 | 0% |
| **Scale-to-zero** (low traffic) | 0-1 | ~$5-15 | **70-85%** |
| **Business hours only** (9am-5pm) | 0-2 | ~$15-30 | **60-70%** |
