export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
  name?: string;
}

export interface ChatCompletionChoice {
  index: number;
  message: ChatMessage;
  finish_reason?: string | null;
}

export interface ChatCompletion {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: ChatCompletionChoice[];
}

export interface ChatDelta {
  role?: string;
  content?: string;
}

export interface ChatCompletionChunkChoice {
  index: number;
  delta: ChatDelta;
  finish_reason?: string | null;
}

export interface ChatCompletionChunk {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: ChatCompletionChunkChoice[];
}

export interface DeviceStats {
  status: string;
  active_model?: string | null;
  battery_pct?: number | null;
  is_charging?: boolean | null;
  thermal_state?: string | null;
  port: number;
  tunnel_url?: string | null;
}

export interface BuildifyOptions {
  baseUrl?: string;
  apiKey?: string;
  timeout?: number;
  geminiApiKey?: string;
  fallbackModel?: string;
  fallbackOnOffline?: boolean;
}
