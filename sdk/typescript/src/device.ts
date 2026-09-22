import { Transport } from './transport.js';
import { DeviceStats } from './types.js';

export class Device {
  private transport: Transport;

  constructor(transport: Transport) {
    this.transport = transport;
  }

  async stats(): Promise<DeviceStats> {
    try {
      return await this.transport.getJson<DeviceStats>('/api/device/stats');
    } catch {
      const isHealthy = await this.health();
      return {
        status: isHealthy ? 'running' : 'unreachable',
        port: 8080,
      };
    }
  }

  async health(): Promise<boolean> {
    try {
      const res = await this.transport.getJson<{ status?: string }>('/health');
      return res?.status === 'ok' || res?.status === 'loading model';
    } catch {
      return false;
    }
  }
}
