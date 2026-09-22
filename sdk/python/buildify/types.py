"""Data models and type definitions for the Buildify SDK."""

from typing import List, Optional, Dict, Any, Union
from pydantic import BaseModel, Field


class ChatMessage(BaseModel):
    role: str = Field(..., description="Role of the message author (system, user, assistant).")
    content: str = Field(..., description="Content of the message.")
    name: Optional[str] = None


class ChatCompletionChoice(BaseModel):
    index: int = 0
    message: ChatMessage
    finish_reason: Optional[str] = "stop"


class ChatCompletionUsage(BaseModel):
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0


class ChatCompletion(BaseModel):
    id: str = "buildify-completion"
    object: str = "chat.completion"
    created: int = 0
    model: str = "default"
    choices: List[ChatCompletionChoice]
    usage: Optional[ChatCompletionUsage] = None

    @property
    def content(self) -> str:
        """Convenience property to extract the primary assistant message text."""
        if self.choices and self.choices[0].message:
            return self.choices[0].message.content
        return ""


class ChatDelta(BaseModel):
    role: Optional[str] = None
    content: Optional[str] = ""


class ChatCompletionChunkChoice(BaseModel):
    index: int = 0
    delta: ChatDelta
    finish_reason: Optional[str] = None


class ChatCompletionChunk(BaseModel):
    id: str = "buildify-chunk"
    object: str = "chat.completion.chunk"
    created: int = 0
    model: str = "default"
    choices: List[ChatCompletionChunkChoice]

    @property
    def delta_text(self) -> str:
        """Convenience property to extract incoming delta token."""
        if self.choices and self.choices[0].delta and self.choices[0].delta.content:
            return self.choices[0].delta.content
        return ""


class DeviceStats(BaseModel):
    status: str = "running"
    active_model: Optional[str] = None
    battery_pct: Optional[int] = None
    is_charging: Optional[bool] = None
    thermal_state: Optional[str] = None
    port: int = 8080
    tunnel_url: Optional[str] = None
    extra: Dict[str, Any] = Field(default_factory=dict)


class ModelInfo(BaseModel):
    id: str
    object: str = "model"
    owned_by: str = "buildify"
