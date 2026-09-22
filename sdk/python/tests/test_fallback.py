from unittest.mock import patch, MagicMock
from buildify import Buildify, ChatCompletion


def test_gemini_fallback_when_phone_unreachable():
    client = Buildify(
        base_url="http://unreachable-phone:8080",
        gemini_api_key="mock-api-key",
        fallback_model="gemini-2.0-flash",
        fallback_on_offline=True,
    )

    mock_gemini_response = ChatCompletion(
        id="gemini-2.0-flash",
        model="gemini-2.0-flash",
        choices=[
            {
                "index": 0,
                "message": {"role": "assistant", "content": "I am responding via Gemini 2.0 Flash fallback!"},
                "finish_reason": "stop"
            }
        ]
    )

    # Simulate phone transport throwing connection error
    with patch.object(client._transport, "post_json", side_effect=ConnectionError("Failed to connect to phone")):
        with patch.object(client._fallback_router, "handle_chat", return_value=mock_gemini_response):
            response = client.chat.completions.create(
                model="gemma-2b",
                messages=[{"role": "user", "content": "Hi"}],
            )
            assert response.content == "I am responding via Gemini 2.0 Flash fallback!"
            assert response.model == "gemini-2.0-flash"

    client.close()
