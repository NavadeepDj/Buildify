"""Local network discovery for finding Buildify phones on Wi-Fi without manual IP setup."""

import socket
import json
from typing import Optional, Dict, Any


def discover_phone(timeout: float = 2.0, port: int = 8257) -> Optional[Dict[str, Any]]:
    """Broadcasts a discovery probe on the local network to find active Buildify servers.

    Returns a dictionary with 'ip', 'port', 'model', and 'tunnel_url' if found, else None.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(timeout)

    try:
        query = b"BUILDIFY_DISCOVER"
        sock.sendto(query, ("255.255.255.255", port))

        while True:
            try:
                data, addr = sock.recvfrom(2048)
                payload = json.loads(data.decode("utf-8"))
                if payload.get("service") == "buildify-ai":
                    ip = addr[0]
                    return {
                        "ip": ip,
                        "port": payload.get("port", 8080),
                        "model": payload.get("model", "default"),
                        "tunnel_url": payload.get("tunnel_url"),
                        "base_url": f"http://{ip}:{payload.get('port', 8080)}",
                    }
            except socket.timeout:
                break
            except Exception:
                continue
    finally:
        sock.close()

    return None
