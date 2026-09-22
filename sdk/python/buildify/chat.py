"""OpenAI-compatible Chat Completions API client."""

from typing import List, Dict, Any, Union, Iterator, AsyncIterator, Optional
from .types import ChatMessage, ChatCompletion, ChatCompletionChunk
from .transport import BuildifyTransport, AsyncBuildifyTransport


class Completions:
    """Synchronous Chat Completions endpoint."""

    def __init__(self, transport: BuildifyTransport, fallback_handler=None):
        self._transport = transport
        self._fallback = fallback_handler

    def create(
        self,
        messages: List[Union[Dict[str, Any], ChatMessage]],
        model: str = "default",
        stream: bool = False,
        temperature: Optional[float] = None,
        max_tokens: Optional[int] = None,
        **kwargs,
    ) -> Union[ChatCompletion, Iterator[ChatCompletionChunk]]:
        formatted_messages = [
            m.model_dump() if isinstance(m, ChatMessage) else m for m in messages
        ]
        payload: Dict[str, Any] = {
            "model": model,
            "messages": formatted_messages,
            "stream": stream,
        }
        if temperature is not None:
            payload["temperature"] = temperature
        if max_tokens is not None:
            payload["max_tokens"] = max_tokens
        payload.update(kwargs)

        try:
            if stream:
                return self._stream_generator(payload)
            else:
                data = self._transport.post_json("/v1/chat/completions", payload)
                return ChatCompletion.model_validate(data)
        except Exception as e:
            if self._fallback:
                return self._fallback.handle_chat(messages=formatted_messages, stream=stream, **kwargs)
            raise e

    def _stream_generator(self, payload: Dict[str, Any]) -> Iterator[ChatCompletionChunk]:
        for chunk_data in self._transport.stream_sse("/v1/chat/completions", payload):
            yield ChatCompletionChunk.model_validate(chunk_data)


class AsyncCompletions:
    """Asynchronous Chat Completions endpoint."""

    def __init__(self, transport: AsyncBuildifyTransport, fallback_handler=None):
        self._transport = transport
        self._fallback = fallback_handler

    async def create(
        self,
        messages: List[Union[Dict[str, Any], ChatMessage]],
        model: str = "default",
        stream: bool = False,
        temperature: Optional[float] = None,
        max_tokens: Optional[int] = None,
        **kwargs,
    ) -> Union[ChatCompletion, AsyncIterator[ChatCompletionChunk]]:
        formatted_messages = [
            m.model_dump() if isinstance(m, ChatMessage) else m for m in messages
        ]
        payload: Dict[str, Any] = {
            "model": model,
            "messages": formatted_messages,
            "stream": stream,
        }
        if temperature is not None:
            payload["temperature"] = temperature
        if max_tokens is not None:
            payload["max_tokens"] = max_tokens
        payload.update(kwargs)

        try:
            if stream:
                return self._async_stream_generator(payload)
            else:
                data = await self._transport.post_json("/v1/chat/completions", payload)
                return ChatCompletion.model_validate(data)
        except Exception as e:
            if self._fallback:
                return await self._fallback.handle_chat_async(messages=formatted_messages, stream=stream, **kwargs)
            raise e

    async def _async_stream_generator(self, payload: Dict[str, Any]) -> AsyncIterator[ChatCompletionChunk]:
        async for chunk_data in self._transport.stream_sse("/v1/chat/completions", payload):
            yield ChatCompletionChunk.model_validate(chunk_data)


class Chat:
    """Chat API wrapper exposing completions."""

    def __init__(self, transport: BuildifyTransport, fallback_handler=None):
        self.completions = Completions(transport, fallback_handler)


class AsyncChat:
    """Asynchronous Chat API wrapper exposing completions."""

    def __init__(self, transport: AsyncBuildifyTransport, fallback_handler=None):
        self.completions = AsyncCompletions(transport, fallback_handler)
