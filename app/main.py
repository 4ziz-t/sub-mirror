import os
import logging
from typing import Optional

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
import httpx
from dotenv import load_dotenv

load_dotenv()

ORIGIN_URL = os.getenv("ORIGIN_URL", "").rstrip("/")
TIMEOUT = float(os.getenv("TIMEOUT", "30"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length",
    "content-encoding",
}

# ====================== LOGGING ======================
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s | %(levelname)-7s | %(message)s",
)
logger = logging.getLogger("sub-mirror")

app = FastAPI(
    title="Remnawave Subscription Mirror",
    docs_url=None,
    redoc_url=None,
)

if not ORIGIN_URL:
    logger.error("ORIGIN_URL is not set!")
    raise RuntimeError("ORIGIN_URL environment variable is required")


@app.get("/health")
async def health():
    return {"status": "ok", "origin": ORIGIN_URL}


@app.api_route("/{path:path}", methods=["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"])
async def proxy(path: str, request: Request):

    target_url = f"{ORIGIN_URL}/{path}" if path else ORIGIN_URL
    if request.url.query:
        target_url += f"?{request.url.query}"

    headers = {}
    for key, value in request.headers.items():
        if key.lower() not in HOP_BY_HOP_HEADERS:
            headers[key] = value

    client_ip = request.client.host if request.client else "0.0.0.0"
    headers["X-Real-IP"] = client_ip
    headers["X-Forwarded-For"] = client_ip
    headers["X-Forwarded-Proto"] = "https"
    headers["X-Forwarded-Host"] = request.headers.get("host", "")

    body = await request.body()

    logger.info(f"{request.method} {path or '/'} → {target_url} | IP: {client_ip}")

    try:
        async with httpx.AsyncClient(
            timeout=TIMEOUT,
            follow_redirects=False,
            verify=True,
        ) as client:
            resp = await client.request(
                method=request.method,
                url=target_url,
                headers=headers,
                content=body,
            )
    except httpx.TimeoutException:
        logger.error(f"Timeout while proxying {target_url}")
        return JSONResponse(
            status_code=504,
            content={"error": "Gateway Timeout"},
        )
    except Exception as e:
        logger.exception(f"Proxy error: {e}")
        return JSONResponse(
            status_code=502,
            content={"error": "Bad Gateway", "detail": str(e)},
        )

    response_headers = {}
    for key, value in resp.headers.items():
        if key.lower() not in HOP_BY_HOP_HEADERS:
            response_headers[key] = value

    return Response(
        content=resp.content,
        status_code=resp.status_code,
        headers=response_headers,
        media_type=resp.headers.get("content-type"),
    )


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.exception(f"Unhandled error: {exc}")
    return JSONResponse(
        status_code=500,
        content={"error": "Internal Server Error"},
    )
