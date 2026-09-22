import { Transport } from './transport.js';
import { Chat } from './chat.js';
import { Device } from './device.js';
import { GeminiFallbackRouter } from './fallback.js';
import { BuildifyOptions } from './types.js';

export class Buildify {
  public baseUrl: string;
  public chat: Chat;
  public device: Device;
  private transport: Transport;

  constructor(options: BuildifyOptions = {}) {
    this.baseUrl = options.baseUrl || 'http://localhost:8080';

    let fallbackRouter: GeminiFallbackRouter | undefined;
    if (options.fallbackOnOffline || options.geminiApiKey) {
      const apiKey = options.geminiApiKey || (typeof process !== 'undefined' ? process.env?.GEMINI_API_KEY : '');
      if (apiKey) {
        fallbackRouter = new GeminiFallbackRouter(apiKey, options.fallbackModel || 'gemini-2.0-flash');
      }
    }

    this.transport = new Transport(this.baseUrl, options.apiKey, options.timeout);
    this.chat = new Chat(this.transport, fallbackRouter);
    this.device = new Device(this.transport);
  }
}
