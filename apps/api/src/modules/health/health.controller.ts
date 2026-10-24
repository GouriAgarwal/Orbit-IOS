import { Controller, Get } from '@nestjs/common';

@Controller('health')
export class HealthController {
  @Get()
  health() { return { status: 'ok', service: 'orbit-api', timestamp: new Date().toISOString() }; }
}
