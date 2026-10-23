import { Controller, Get, NotFoundException, Param, Query } from '@nestjs/common';
import { EventsService } from './events.service';

@Controller('events')
export class EventsController {
  constructor(private readonly events: EventsService) {}

  @Get()
  list(@Query('campus') campus?: string, @Query('category') category?: string, @Query('from') from?: string, @Query('to') to?: string, @Query('q') q?: string) {
    const data = this.events.list({ campus, category, from, to, q });
    return { data, nextCursor: null };
  }

  @Get(':eventId')
  detail(@Param('eventId') eventId: string) {
    const event = this.events.get(eventId);
    if (!event) throw new NotFoundException({ error: { code: 'EVENT_NOT_FOUND', message: 'Event was not found.' } });
    return event;
  }
}
