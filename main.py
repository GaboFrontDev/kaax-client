"""Kaax AI client entrypoint.

Boots the core engine with the Kaax ClientConfig.

Run locally:
    uv run uvicorn main:app --port 8200 --reload

Run Chainlit:
    uv run chainlit run core/chainlit_app.py --port 8000
"""

from __future__ import annotations

import sys
from pathlib import Path

# Mount core engine on the path
sys.path.insert(0, str(Path(__file__).resolve().parent / "core"))

from client import build_client_config  # noqa: E402
from api.dependencies import set_client_config  # noqa: E402

# Register Kaax ClientConfig before the app is created
set_client_config(build_client_config())

from api.main import app  # noqa: E402, F401 — exported for uvicorn
