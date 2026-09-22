"""Example: Hybrid Edge-to-Cloud fallback using Google Gemini 2.0 Flash."""

import os
from buildify import Buildify

def main():
    # Provide your Gemini API key (or set GEMINI_API_KEY environment variable)
    gemini_key = os.getenv("GEMINI_API_KEY", "your-gemini-api-key")

    print("Initializing Buildify client with Gemini 2.0 Flash fallback...")
    client = Buildify(
        base_url="http://192.168.1.55:8080", # Your phone IP
        gemini_api_key=gemini_key,
        fallback_model="gemini-2.0-flash",
        fallback_on_offline=True, # Auto-reroutes to Gemini 2.0 Flash if phone goes offline!
    )

    response = client.chat.completions.create(
        model="default",
        messages=[
            {"role": "user", "content": "Write a 3-word slogan for edge computing."}
        ],
    )

    print(f"Model used: {response.model}")
    print(f"Result: {response.content}")

if __name__ == "__main__":
    main()
