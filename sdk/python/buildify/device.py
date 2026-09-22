"""Device telemetry, status, and health client."""

from typing import Dict, Any, Optional
from .types import DeviceStats
from .transport import BuildifyTransport, AsyncBuildifyTransport


class Device:
    """Synchronous device telemetry and management."""

    def __init__(self, transport: BuildifyTransport):
        self._transport = transport

    def stats(self) -> DeviceStats:
        """Retrieves phone battery, thermal, and server status."""
        try:
            data = self._transport.get_json("/api/device/stats")
            return DeviceStats.model_validate(data)
        except Exception:
            # Fallback when only llama-server is active without full backend daemon
            health = self.health()
            return DeviceStats(status="running" if health else "unreachable")

    def health(self) -> bool:
        """Checks if the edge inference server is responding."""
        try:
            data = self._transport.get_json("/health")
            return data.get("status") in ("ok", "loading model")
        except Exception:
            return False


class AsyncDevice:
    """Asynchronous device telemetry and management."""

    def __init__(self, transport: AsyncBuildifyTransport):
        self._transport = transport

    async def stats(self) -> DeviceStats:
        """Retrieves phone battery, thermal, and server status."""
        try:
            data = await self._transport.get_json("/api/device/stats")
            return DeviceStats.model_validate(data)
        except Exception:
            health = await self.health()
            return DeviceStats(status="running" if health else "unreachable")

    async def health(self) -> bool:
        """Checks if the edge inference server is responding."""
        try:
            data = await self._transport.get_json("/health")
            return data.get("status") in ("ok", "loading model")
        except Exception:
            return False
