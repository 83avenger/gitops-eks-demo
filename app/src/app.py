"""
GitOps Demo App — FastAPI
Shows pod info, environment, deployment details in real time.
Perfect for demonstrating rolling updates and GitOps sync.
"""

import os
import time
import socket
import platform
from datetime import datetime, timezone
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse
import uvicorn

app = FastAPI(title="GitOps Demo App")

# ── Prometheus metrics ────────────────────────────────────────
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["endpoint"]
)

START_TIME = time.time()

# ── App metadata (injected via env vars from K8s ConfigMap) ───
APP_VERSION   = os.getenv("APP_VERSION",   "1.0.0")
ENVIRONMENT   = os.getenv("ENVIRONMENT",   "local")
LOG_LEVEL     = os.getenv("LOG_LEVEL",     "debug")
POD_NAME      = os.getenv("POD_NAME",      socket.gethostname())
POD_NAMESPACE = os.getenv("POD_NAMESPACE", "default")
NODE_NAME     = os.getenv("NODE_NAME",     "local-node")

# ── Colour per environment (visual demo aid) ──────────────────
ENV_COLOURS = {
    "dev":     {"bg": "#1a1a2e", "accent": "#e94560", "badge": "#e94560"},
    "staging": {"bg": "#0a3d62", "accent": "#f9ca24", "badge": "#f9ca24"},
    "prod":    {"bg": "#1e3c1e", "accent": "#6ab04c", "badge": "#6ab04c"},
    "local":   {"bg": "#2d2d2d", "accent": "#a29bfe", "badge": "#a29bfe"},
}
COLOURS = ENV_COLOURS.get(ENVIRONMENT, ENV_COLOURS["local"])


# ── Routes ────────────────────────────────────────────────────

@app.get("/healthz")
async def healthz():
    """Liveness probe — is the app alive?"""
    REQUEST_COUNT.labels("GET", "/healthz", "200").inc()
    return {"status": "ok", "timestamp": datetime.now(timezone.utc).isoformat()}


@app.get("/ready")
async def ready():
    """Readiness probe — is the app ready to serve traffic?"""
    REQUEST_COUNT.labels("GET", "/ready", "200").inc()
    return {"status": "ready", "pod": POD_NAME}


@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/info")
async def info():
    """JSON endpoint — useful for testing deployments via curl"""
    REQUEST_COUNT.labels("GET", "/api/info", "200").inc()
    uptime = int(time.time() - START_TIME)
    return {
        "app":         "gitops-demo",
        "version":     APP_VERSION,
        "environment": ENVIRONMENT,
        "pod": {
            "name":      POD_NAME,
            "namespace": POD_NAMESPACE,
            "node":      NODE_NAME,
        },
        "uptime_seconds": uptime,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "python":    platform.python_version(),
    }


@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard — visually shows deployment info for demo"""
    REQUEST_COUNT.labels("GET", "/", "200").inc()

    uptime_secs = int(time.time() - START_TIME)
    uptime_str  = f"{uptime_secs // 3600}h {(uptime_secs % 3600) // 60}m {uptime_secs % 60}s"
    timestamp   = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="refresh" content="10">
  <title>GitOps Demo — {ENVIRONMENT.upper()}</title>
  <style>
    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
    body {{
      font-family: 'Segoe UI', system-ui, sans-serif;
      background: {COLOURS["bg"]};
      color: #e0e0e0;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 2rem;
    }}
    .card {{
      background: rgba(255,255,255,0.05);
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 16px;
      padding: 2.5rem;
      max-width: 700px;
      width: 100%;
      backdrop-filter: blur(10px);
    }}
    .header {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 2rem;
      flex-wrap: wrap;
      gap: 1rem;
    }}
    .title {{
      font-size: 1.8rem;
      font-weight: 700;
      color: #fff;
    }}
    .title span {{ color: {COLOURS["accent"]}; }}
    .badge {{
      background: {COLOURS["badge"]};
      color: #000;
      font-weight: 700;
      font-size: 0.85rem;
      padding: 0.4rem 1rem;
      border-radius: 999px;
      text-transform: uppercase;
      letter-spacing: 0.1em;
    }}
    .grid {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 1rem;
      margin-bottom: 1.5rem;
    }}
    .metric {{
      background: rgba(255,255,255,0.05);
      border-radius: 10px;
      padding: 1.2rem;
      border-left: 3px solid {COLOURS["accent"]};
    }}
    .metric-label {{
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.1em;
      color: #888;
      margin-bottom: 0.4rem;
    }}
    .metric-value {{
      font-size: 1.1rem;
      font-weight: 600;
      color: #fff;
      word-break: break-all;
    }}
    .metric-value.highlight {{ color: {COLOURS["accent"]}; }}
    .status-bar {{
      display: flex;
      align-items: center;
      gap: 0.5rem;
      padding: 1rem;
      background: rgba(106,176,76,0.1);
      border: 1px solid rgba(106,176,76,0.3);
      border-radius: 10px;
      margin-bottom: 1.5rem;
    }}
    .dot {{
      width: 10px;
      height: 10px;
      border-radius: 50%;
      background: #6ab04c;
      animation: pulse 2s infinite;
    }}
    @keyframes pulse {{
      0%, 100% {{ opacity: 1; }}
      50% {{ opacity: 0.4; }}
    }}
    .footer {{
      text-align: center;
      font-size: 0.8rem;
      color: #555;
      margin-top: 1.5rem;
    }}
    .footer span {{ color: {COLOURS["accent"]}; }}
    .endpoints {{
      margin-top: 1.5rem;
      padding: 1rem;
      background: rgba(0,0,0,0.2);
      border-radius: 10px;
    }}
    .endpoints h3 {{
      font-size: 0.8rem;
      text-transform: uppercase;
      letter-spacing: 0.1em;
      color: #666;
      margin-bottom: 0.8rem;
    }}
    .endpoint {{
      display: flex;
      gap: 1rem;
      align-items: center;
      padding: 0.3rem 0;
      font-size: 0.9rem;
    }}
    .method {{
      background: {COLOURS["accent"]};
      color: #000;
      font-size: 0.7rem;
      font-weight: 700;
      padding: 0.15rem 0.5rem;
      border-radius: 4px;
      min-width: 42px;
      text-align: center;
    }}
    code {{
      color: #ccc;
      font-family: 'Consolas', monospace;
    }}
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <div class="title">GitOps <span>Demo</span> App</div>
      <div class="badge">{ENVIRONMENT}</div>
    </div>

    <div class="status-bar">
      <div class="dot"></div>
      <span style="color:#6ab04c; font-weight:600;">Healthy</span>
      <span style="color:#666; margin-left:auto; font-size:0.85rem;">
        Auto-refreshes every 10s
      </span>
    </div>

    <div class="grid">
      <div class="metric">
        <div class="metric-label">Version</div>
        <div class="metric-value highlight">{APP_VERSION}</div>
      </div>
      <div class="metric">
        <div class="metric-label">Environment</div>
        <div class="metric-value">{ENVIRONMENT}</div>
      </div>
      <div class="metric">
        <div class="metric-label">Pod Name</div>
        <div class="metric-value highlight">{POD_NAME}</div>
      </div>
      <div class="metric">
        <div class="metric-label">Namespace</div>
        <div class="metric-value">{POD_NAMESPACE}</div>
      </div>
      <div class="metric">
        <div class="metric-label">Node</div>
        <div class="metric-value">{NODE_NAME}</div>
      </div>
      <div class="metric">
        <div class="metric-label">Uptime</div>
        <div class="metric-value">{uptime_str}</div>
      </div>
      <div class="metric">
        <div class="metric-label">Log Level</div>
        <div class="metric-value">{LOG_LEVEL}</div>
      </div>
      <div class="metric">
        <div class="metric-label">Last Updated</div>
        <div class="metric-value" style="font-size:0.9rem">{timestamp}</div>
      </div>
    </div>

    <div class="endpoints">
      <h3>Available Endpoints</h3>
      <div class="endpoint">
        <span class="method">GET</span>
        <code>/</code>
        <span style="color:#666">This dashboard</span>
      </div>
      <div class="endpoint">
        <span class="method">GET</span>
        <code>/api/info</code>
        <span style="color:#666">JSON deployment info</span>
      </div>
      <div class="endpoint">
        <span class="method">GET</span>
        <code>/healthz</code>
        <span style="color:#666">Liveness probe</span>
      </div>
      <div class="endpoint">
        <span class="method">GET</span>
        <code>/ready</code>
        <span style="color:#666">Readiness probe</span>
      </div>
      <div class="endpoint">
        <span class="method">GET</span>
        <code>/metrics</code>
        <span style="color:#666">Prometheus metrics</span>
      </div>
    </div>

    <div class="footer">
      Deployed via <span>GitOps</span> · ArgoCD + EKS · 
      Built by <span>GitHub Actions</span>
    </div>
  </div>
</body>
</html>"""

    return HTMLResponse(content=html)


if __name__ == "__main__":
    uvicorn.run("app:app", host="0.0.0.0", port=8080, reload=False)
