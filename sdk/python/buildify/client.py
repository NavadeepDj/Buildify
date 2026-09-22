"""Main entry point for Buildify Client SDK."""

import os
from typing import Optional
from .transport import BuildifyTransport, AsyncBuildifyTransport
from .chat import Chat, AsyncChat
from .device import Device, AsyncDevice
from .discovery import discover_phone
from .fallback import GeminiFallbackRouter


class Buildify:
    """Synchronous Client for Buildify Edge AI Server."""

    def __init__(
        self,
        base_url: Optional[str] = None,
        api_key: Optional[str] = None,
        timeout: float = 60.0,
        gemini_api_key: Optional[str] = None,
        fallback_model: str = "gemini-2.0-flash",
        fallback_on_offline: bool = False,
    ):
        resolved_url = base_url or os.getenv("BUILDIFY_BASE_URL")
        if not resolved_url:
            # Try auto-discovering on local network
            discovered = discover_phone(timeout=1.5)
            if discovered:
                resolved_url = discovered["base_url"]
            else:
                resolved_url = "http://localhost:8080"

        self.base_url = resolved_url
        self._fallback_router = None
        if fallback_on_offline or gemini_api_key or os.getenv("GEMINI_API_KEY"):
            self._fallback_router = GeminiFallbackRouter(
                api_key=gemini_api_key,
                model=fallback_model,
            )

        self._transport = BuildifyTransport(
            base_url=self.base_url,
            api_key=api_key or os.getenv("BUILDIFY_API_KEY"),
            timeout=timeout,
        )

        self.chat = Chat(self._transport, fallback_handler=self._fallback_router)
        self.device = Device(self._transport)

    @classmethod
    def discover(cls, timeout: float = 3.0, **kwargs) -> "Buildify":
        """Discovers a Buildify edge phone on the local Wi-Fi and returns a connected client."""
        info = discover_phone(timeout=timeout)
        if not info:
            raise ConnectionError(
                "Could not find any Buildify server on the local Wi-Fi. "
                "Ensure your phone is on the same Wi-Fi with AI server started, or pass base_url explicitly."
            )
        return cls(base_url=info["base_url"], **kwargs)

    def close(self):
        self._transport.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


class AsyncBuildify:
    """Asynchronous Client for Buildify Edge AI Server."""

    def __init__(
        self,
        base_url: Optional[str] = None,
        api_key: Optional[str] = None,
        timeout: float = 60.0,
        gemini_api_key: Optional[str] = None,
        fallback_model: str = "gemini-2.0-flash",
        fallback_on_offline: bool = False,
    ):
        resolved_url = base_url or os.getenv("BUILDIFY_BASE_URL", "http://localhost:8080")
        self.base_url = resolved_url

        self._fallback_router = None
        if fallback_on_offline or gemini_api_key or os.getenv("GEMINI_API_KEY"):
            self._fallback_router = GeminiFallbackRouter(
                api_key=gemini_api_key,
                model=fallback_model,
            )

        self._transport = AsyncBuildifyTransport(
            base_url=self.base_url,
            api_key=api_key or os.getenv("BUILDIFY_API_KEY"),
            timeout=timeout,
        )

        self.chat = AsyncChat(self._transport, fallback_handler=self._fallback_router)
        self.device = AsyncDevice(self._transport)

    async def aclose(self):
        await self._transport.aclose()

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        await self.aclose()
