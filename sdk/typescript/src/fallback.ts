import { ChatMessage, ChatCompletion, ChatCompletionChunk } from './types.js';

export class GeminiFallbackRouter {
  private apiKey: string;
  private model: string;

  constructor(apiKey: string, model: string = 'gemini-2.0-flash') {
    this.apiKey = apiKey;
    this.model = model;
  }

  async handleChat(messages: ChatMessage[], stream: boolean = false): Promise<ChatCompletion | AsyncGenerator<ChatCompletionChunk>> {
    if (stream) {
      return this.handleStream(messages);
    }

    const url = `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent?key=${this.apiKey}`;
    const contents = messages.map(m => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }]
    }));

    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contents }),
    });

    if (!resp.ok) {
      throw new Error(`Gemini Fallback HTTP ${resp.status}: ${await resp.text()}`);
    }

    const data = await resp.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text || '';

    return {
      id: 'gemini-2.0-flash',
      object: 'chat.completion',
      created: Date.now(),
      model: this.model,
      choices: [
        {
          index: 0,
          message: { role: 'assistant', content: text },
          finish_reason: 'stop',
        }
      ]
    };
  }

  async *handleStream(messages: ChatMessage[]): AsyncGenerator<ChatCompletionChunk> {
    const completion = await this.handleChat(messages, false) as ChatCompletion;
    const text = completion.choices[0]?.message?.content || '';

    yield {
      id: 'gemini-2.0-flash-chunk',
      object: 'chat.completion.chunk',
      created: Date.now(),
      model: this.model,
      choices: [
        {
          index: 0,
          delta: { role: 'assistant', content: text },
          finish_reason: 'stop',
        }
      ]
    };
  }
}
