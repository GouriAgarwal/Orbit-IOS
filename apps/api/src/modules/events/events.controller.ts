import { BadRequestException, Body, Controller, Delete, Get, NotFoundException, Param, Patch, Post, Query, Req, Res, StreamableFile, UseGuards } from '@nestjs/common';
import { AuthGuard } from '../../common/auth.guard';
import { EventsService } from './events.service';
import { createReadStream, existsSync } from 'node:fs';
import { join } from 'node:path';

@Controller('events')
export class EventsController {
  constructor(private readonly events: EventsService) {}

  @Post('posters')
  @UseGuards(AuthGuard)
  uploadPoster(@Req() request: { user: { id: string } }, @Body() body: { clubId: string; imageBase64: string }) {
    return this.events.uploadPoster(request.user.id, body.clubId, body.imageBase64);
  }

  @Get('posters/:filename')
  poster(@Param('filename') filename: string, @Res({ passthrough: true }) response: any) {
    if (!/^[0-9a-f-]{36}\.jpg$/i.test(filename)) throw new NotFoundException();
    const path = join(process.cwd(), 'uploads', 'event-posters', filename);
    if (!existsSync(path)) throw new NotFoundException();
    response.setHeader('Cache-Control', 'public, max-age=86400');
    return new StreamableFile(createReadStream(path), { type: 'image/jpeg', disposition: 'inline' });
  }

  @Get()
  list(@Query('campus') campus?: string, @Query('category') category?: string, @Query('from') from?: string, @Query('to') to?: string, @Query('q') q?: string, @Query('cursor') cursor?: string) {
    return this.events.list({ campus, category, from, to, q, cursor });
  }

  @Get('mine')
  @UseGuards(AuthGuard)
  mine(@Req() request: { user: { id: string } }) { return this.events.mine(request.user.id); }

  @Get('my-registrations')
  @UseGuards(AuthGuard)
  myRegistrations(@Req() request: { user: { id: string } }) { return this.events.myRegistrations(request.user.id); }

  @Get('my-saved')
  @UseGuards(AuthGuard)
  saved(@Req() request: { user: { id: string } }) { return this.events.savedEvents(request.user.id); }

  @Post(':eventId/save')
  @UseGuards(AuthGuard)
  save(@Req() request: { user: { id: string } }, @Param('eventId') eventId: string) { return this.events.saveEvent(request.user.id, eventId); }

  @Delete(':eventId/save')
  @UseGuards(AuthGuard)
  unsave(@Req() request: { user: { id: string } }, @Param('eventId') eventId: string) { return this.events.unsaveEvent(request.user.id, eventId); }

  @Post(':eventId/registrations')
  @UseGuards(AuthGuard)
  register(@Req() request: { user: { id: string } }, @Param('eventId') eventId: string) { return this.events.register(request.user.id, eventId); }

  @Delete(':eventId/registrations/me')
  @UseGuards(AuthGuard)
  cancel(@Req() request: { user: { id: string } }, @Param('eventId') eventId: string) { return this.events.cancelRegistration(request.user.id, eventId); }

  @Get(':eventId/registrations')
  @UseGuards(AuthGuard)
  attendees(@Req() request: { user: { id: string } }, @Param('eventId') eventId: string) { return this.events.attendees(request.user.id, eventId); }

  @Patch(':eventId/registrations/:registrationId')
  @UseGuards(AuthGuard)
  attendance(@Req() request: { user: { id: string } }, @Param('eventId') eventId: string, @Param('registrationId') registrationId: string, @Body() body: { status: 'attended' | 'no_show' }) {
    if (!['attended', 'no_show'].includes(body.status)) throw new BadRequestException({ error: { code: 'INVALID_ATTENDANCE_STATUS', message: 'Status must be attended or no_show.' } });
    return this.events.updateAttendance(request.user.id, eventId, registrationId, body.status);
  }

  @Get(':eventId')
  detail(@Param('eventId') eventId: string) {
    return this.events.get(eventId);
  }

  @Delete(':eventId')
  @UseGuards(AuthGuard)
  delete(@Req() request: { user: { id: string } }, @Param('eventId') eventId: string) {
    return this.events.delete(request.user.id, eventId);
  }

  @Post()
  @UseGuards(AuthGuard)
  create(@Req() request: { user: { id: string } }, @Body() body: Record<string, unknown>) { return this.events.create(request.user.id, body); }

  @Patch(':eventId')
  @UseGuards(AuthGuard)
  update(@Req() request: { user: { id: string } }, @Param('eventId') eventId: string, @Body() body: Record<string, unknown>) { return this.events.update(request.user.id, eventId, body); }

  @Post(':eventId/submit')
  @UseGuards(AuthGuard)
  submit(@Req() request: { user: { id: string } }, @Param('eventId') eventId: string) { return this.events.submit(request.user.id, eventId); }

  @Post(':eventId/publish')
  @UseGuards(AuthGuard)
  publish(@Req() request: { user: { id: string } }, @Param('eventId') eventId: string) { return this.events.submit(request.user.id, eventId, true); }
}
