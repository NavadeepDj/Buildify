import { Transport } from './transport.js';
import { GeminiFallbackRouter } from './fallback.js';
import { ChatMessage, ChatCompletion, ChatCompletionChunk } from './types.js';

export interface ChatCompletionParams {
  messages: ChatMessage[];
  model?: string;
  stream?: boolean;
  temperature?: number;
  max_tokens?: number;
  [key: string]: unknown;
}

export class Completions {
  private transport: Transport;
  private fallback?: GeminiFallbackRouter;

  constructor(transport: Transport, fallback?: GeminiFallbackRouter) {
    this.transport = transport;
    this.fallback = fallback;
  }

  create(params: ChatCompletionParams & { stream: true }): Promise<AsyncGenerator<ChatCompletionChunk>>;
  create(params: ChatCompletionParams & { stream?: false }): Promise<ChatCompletion>;
  create(params: ChatCompletionParams): Promise<ChatCompletion | AsyncGenerator<ChatCompletionChunk>>;
  async create(params: ChatCompletionParams): Promise<ChatCompletion | AsyncGenerator<ChatCompletionChunk>> {
    const { stream = false, model = 'default', messages, ...rest } = params;
    const payload = {
      model,
      messages,
      stream,
      ...rest,
    };

    try {
      if (stream) {
        return this.transport.streamSSE('/v1/chat/completions', payload);
      } else {
        return await this.transport.postJson<ChatCompletion>('/v1/chat/completions', payload);
      }
    } catch (err) {
      if (this.fallback) {
        return this.fallback.handleChat(messages, stream);
      }
      throw err;
    }
  }
}

export class Chat {
  public completions: Completions;

  constructor(transport: Transport, fallback?: GeminiFallbackRouter) {
    this.completions = new Completions(transport, fallback);
  }
}
