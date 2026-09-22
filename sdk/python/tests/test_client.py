import pytest
from buildify import Buildify, AsyncBuildify, ChatMessage


def test_buildify_client_init():
    client = Buildify(base_url="http://192.168.1.55:8080", api_key="secret-key")
    assert client.base_url == "http://192.168.1.55:8080"
    client.close()


def test_buildify_context_manager():
    with Buildify(base_url="http://localhost:8080") as client:
        assert client.base_url == "http://localhost:8080"


import asyncio

def test_async_buildify_context_manager():
    async def _run():
        async with AsyncBuildify(base_url="http://localhost:8080") as client:
            assert client.base_url == "http://localhost:8080"
    asyncio.run(_run())


def test_chat_message_model():
    msg = ChatMessage(role="user", content="Hello world")
    assert msg.role == "user"
    assert msg.content == "Hello world"
    data = msg.model_dump()
    assert data["role"] == "user"
    assert data["content"] == "Hello world"
