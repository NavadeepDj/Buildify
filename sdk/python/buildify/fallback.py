"""Hybrid fallback router to Google Gemini 2.0 Flash when edge device is offline or battery low."""

import os
from typing import List, Dict, Any, Iterator, AsyncIterator, Union, Optional
import httpx
from .types import ChatCompletion, ChatCompletionChoice, ChatMessage, ChatCompletionChunk, ChatCompletionChunkChoice, ChatDelta


class GeminiFallbackRouter:
    """Routes chat completion requests to Gemini 2.0 Flash when phone server is unavailable."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        model: str = "gemini-2.0-flash",
    ):
        self.api_key = api_key or os.getenv("GEMINI_API_KEY")
        self.model = model

    def _convert_messages_to_gemini(self, messages: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        contents = []
        for msg in messages:
            role = msg.get("role", "user")
            gemini_role = "model" if role == "assistant" else "user"
            content = msg.get("content", "")
            contents.append({"role": gemini_role, "parts": [{"text": content}]})
        return contents

    def handle_chat(
        self,
        messages: List[Dict[str, Any]],
        stream: bool = False,
        **kwargs,
    ) -> Union[ChatCompletion, Iterator[ChatCompletionChunk]]:
        if not self.api_key:
            raise RuntimeError("Gemini fallback requested, but no GEMINI_API_KEY provided.")

        try:
            # Try importing unified google-genai SDK first
            from google import genai
            client = genai.Client(api_key=self.api_key)

            if stream:
                return self._stream_genai_sdk(client, messages)
            else:
                prompt = "\n".join([f"{m.get('role')}: {m.get('content')}" for m in messages])
                resp = client.models.generate_content(
                    model=self.model,
                    contents=prompt,
                )
                text = resp.text or ""
                return ChatCompletion(
                    model=self.model,
                    choices=[
                        ChatCompletionChoice(
                            index=0,
                            message=ChatMessage(role="assistant", content=text),
                            finish_reason="stop",
                        )
                    ],
                )
        except ImportError:
            # Fallback to direct HTTP request to Gemini REST API if SDK is not installed
            return self._handle_chat_http(messages, stream=stream)

    def _stream_genai_sdk(self, client: Any, messages: List[Dict[str, Any]]) -> Iterator[ChatCompletionChunk]:
        prompt = "\n".join([f"{m.get('role')}: {m.get('content')}" for m in messages])
        response_stream = client.models.generate_content_stream(
            model=self.model,
            contents=prompt,
        )
        for chunk in response_stream:
            text = chunk.text or ""
            yield ChatCompletionChunk(
                model=self.model,
                choices=[
                    ChatCompletionChunkChoice(
                        index=0,
                        delta=ChatDelta(role="assistant", content=text),
                        finish_reason=None,
                    )
                ],
            )

    def _handle_chat_http(self, messages: List[Dict[str, Any]], stream: bool = False) -> ChatCompletion:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent?key={self.api_key}"
        gemini_contents = self._convert_messages_to_gemini(messages)
        payload = {"contents": gemini_contents}

        with httpx.Client(timeout=30.0) as client:
            resp = client.post(url, json=payload)
            resp.raise_for_status()
            data = resp.json()

            candidates = data.get("candidates", [])
            text = ""
            if candidates:
                parts = candidates[0].get("content", {}).get("parts", [])
                text = "".join([p.get("text", "") for p in parts])

            return ChatCompletion(
                model=self.model,
                choices=[
                    ChatCompletionChoice(
                        index=0,
                        message=ChatMessage(role="assistant", content=text),
                        finish_reason="stop",
                    )
                ],
            )

    async def handle_chat_async(
        self,
        messages: List[Dict[str, Any]],
        stream: bool = False,
        **kwargs,
    ) -> Union[ChatCompletion, AsyncIterator[ChatCompletionChunk]]:
        # Sync-to-async wrapper for Gemini fallback
        result = self.handle_chat(messages=messages, stream=stream, **kwargs)
        if stream:
            async def _aiter():
                for item in result:
                    yield item
            return _aiter()
        return result
