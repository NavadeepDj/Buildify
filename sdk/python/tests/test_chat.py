import pytest
import httpx
from unittest.mock import patch, MagicMock
from buildify import Buildify, AsyncBuildify, ChatCompletion, ChatCompletionChunk


def test_chat_completion_non_streaming():
    client = Buildify(base_url="http://192.168.1.100:8080")

    mock_response = {
        "id": "chatcmpl-123",
        "object": "chat.completion",
        "created": 1677652288,
        "model": "gemma-2b",
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": "Hello! I am running on your Android phone."},
                "finish_reason": "stop"
            }
        ]
    }

    with patch.object(client._transport, "post_json", return_value=mock_response):
        completion = client.chat.completions.create(
            model="gemma-2b",
            messages=[{"role": "user", "content": "Hi"}],
            stream=False,
        )

        assert isinstance(completion, ChatCompletion)
        assert completion.content == "Hello! I am running on your Android phone."
        assert completion.model == "gemma-2b"

    client.close()


def test_chat_completion_streaming():
    client = Buildify(base_url="http://192.168.1.100:8080")

    mock_chunks = [
        {
            "id": "chatcmpl-123",
            "object": "chat.completion.chunk",
            "created": 1677652288,
            "model": "gemma-2b",
            "choices": [{"index": 0, "delta": {"content": "Hello"}, "finish_reason": None}]
        },
        {
            "id": "chatcmpl-123",
            "object": "chat.completion.chunk",
            "created": 1677652288,
            "model": "gemma-2b",
            "choices": [{"index": 0, "delta": {"content": " from phone!"}, "finish_reason": "stop"}]
        },
    ]

    with patch.object(client._transport, "stream_sse", return_value=iter(mock_chunks)):
        stream = client.chat.completions.create(
            model="gemma-2b",
            messages=[{"role": "user", "content": "Hi"}],
            stream=True,
        )

        collected = []
        for chunk in stream:
            assert isinstance(chunk, ChatCompletionChunk)
            collected.append(chunk.delta_text)

        assert "".join(collected) == "Hello from phone!"

    client.close()


import asyncio

def test_async_chat_completion():
    async def _run():
        client = AsyncBuildify(base_url="http://192.168.1.100:8080")

        mock_response = {
            "id": "chatcmpl-456",
            "object": "chat.completion",
            "created": 1677652288,
            "model": "smollm",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": "Async response"},
                    "finish_reason": "stop"
                }
            ]
        }

        with patch.object(client._transport, "post_json", return_value=mock_response):
            completion = await client.chat.completions.create(
                model="smollm",
                messages=[{"role": "user", "content": "Hi"}],
                stream=False,
            )

            assert isinstance(completion, ChatCompletion)
            assert completion.content == "Async response"

        await client.aclose()
    asyncio.run(_run())
