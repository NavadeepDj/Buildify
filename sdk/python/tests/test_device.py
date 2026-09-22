from unittest.mock import patch
from buildify import Buildify, DeviceStats


def test_device_stats_and_health():
    client = Buildify(base_url="http://192.168.1.100:8080")

    mock_stats = {
        "status": "running",
        "active_model": "gemma-2b-it.Q4_K_M.gguf",
        "battery_pct": 82,
        "is_charging": True,
        "thermal_state": "nominal",
        "port": 8080,
        "tunnel_url": "https://fast-slug.trycloudflare.com",
    }

    with patch.object(client._transport, "get_json", return_value=mock_stats):
        stats = client.device.stats()
        assert isinstance(stats, DeviceStats)
        assert stats.status == "running"
        assert stats.battery_pct == 82
        assert stats.is_charging is True
        assert stats.tunnel_url == "https://fast-slug.trycloudflare.com"

    with patch.object(client._transport, "get_json", return_value={"status": "ok"}):
        assert client.device.health() is True

    with patch.object(client._transport, "get_json", side_effect=Exception("Connection refused")):
        assert client.device.health() is False

    client.close()
