"""Buildify AI Python SDK

Official client library for connecting to Buildify Edge AI servers running locally on Android phones.
"""

from .client import Buildify, AsyncBuildify
from .types import (
    ChatMessage,
    ChatCompletion,
    ChatCompletionChoice,
    ChatCompletionChunk,
    ChatCompletionChunkChoice,
    ChatDelta,
    DeviceStats,
    ModelInfo,
)
from .discovery import discover_phone

__version__ = "0.1.0"
__all__ = [
    "Buildify",
    "AsyncBuildify",
    "ChatMessage",
    "ChatCompletion",
    "ChatCompletionChoice",
    "ChatCompletionChunk",
    "ChatCompletionChunkChoice",
    "ChatDelta",
    "DeviceStats",
    "ModelInfo",
    "discover_phone",
]
