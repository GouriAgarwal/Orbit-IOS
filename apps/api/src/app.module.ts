import { Module } from '@nestjs/common';
import { EventsController } from './modules/events/events.controller';
import { EventsService } from './modules/events/events.service';
import { HealthController } from './modules/health/health.controller';

@Module({ controllers: [HealthController, EventsController], providers: [EventsService] })
export class AppModule {}
