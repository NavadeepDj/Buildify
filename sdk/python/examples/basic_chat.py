"""Example: Connecting to your phone's Buildify AI server and streaming chat tokens."""

import sys
from buildify import Buildify

def main():
    print("Connecting to Buildify on your phone...")
    # You can pass base_url="http://192.168.1.xxx:8080" or let it auto-discover!
    client = Buildify()

    print(f"Connected to: {client.base_url}")
    
    # 1. Check device health & battery telemetry
    stats = client.device.stats()
    print(f"Server Status: {stats.status}")
    if stats.battery_pct is not None:
        print(f"Phone Battery: {stats.battery_pct}% (Charging: {stats.is_charging})")

    # 2. Stream a chat completion from the phone's local LLM
    print("\nPrompt: Explain quantum computing in two sentences.")
    print("Response: ", end="", flush=True)

    stream = client.chat.completions.create(
        model="default",
        messages=[
            {"role": "system", "content": "You are a concise, helpful assistant."},
            {"role": "user", "content": "Explain quantum computing in two sentences."}
        ],
        stream=True,
    )

    for chunk in stream:
        token = chunk.delta_text
        sys.stdout.write(token)
        sys.stdout.flush()

    print("\n\nDone! Successfully streamed tokens directly from Android phone.")

if __name__ == "__main__":
    main()
