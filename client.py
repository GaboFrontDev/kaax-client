"""Kaax AI sales client — builds ClientConfig for the core engine.

This is the entry point for the kaax-client repo. It loads config.yaml
and returns a ClientConfig ready to pass to MultiAgentSupervisor.

Usage (in core's agent.py or any entrypoint):
    from client import build_client_config
    config = build_client_config()
"""

from __future__ import annotations

from pathlib import Path

# core is mounted as a submodule at ./core/
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent / "core"))

from client_config import load_client_config, ClientConfig  # noqa: E402


_CONFIG_PATH = Path(__file__).resolve().parent / "config.yaml"


def build_client_config() -> ClientConfig:
    """Load and return the Kaax AI ClientConfig."""
    return load_client_config(str(_CONFIG_PATH))
