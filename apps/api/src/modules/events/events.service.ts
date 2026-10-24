import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '@prisma/client';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';

@Injectable()
export class EventsService {
  constructor(private readonly prisma: PrismaService) {}

  async uploadPoster(userId: string, clubId: string, imageBase64: string) {
    if (!clubId || typeof imageBase64 !== 'string') throw new BadRequestException({ error: { code: 'INVALID_POSTER', message: 'Choose a club and a JPEG event photo.' } });
    await this.assertOrganizer(userId, clubId);
    const encoded = imageBase64.replace(/^data:image\/jpeg;base64,/i, '');
    if (!/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) throw new BadRequestException({ error: { code: 'INVALID_POSTER', message: 'The selected photo could not be read. Choose a JPEG image.' } });
    const image = Buffer.from(encoded, 'base64');
    if (image.length < 4 || image.length > 5 * 1024 * 1024 || image[0] !== 0xff || image[1] !== 0xd8 || image[2] !== 0xff) {
      throw new BadRequestException({ error: { code: 'INVALID_POSTER', message: 'Event photos must be JPEG images no larger than 5 MB.' } });
    }
    const filename = `${randomUUID()}.jpg`;
    const directory = join(process.cwd(), 'uploads', 'event-posters');
    await mkdir(directory, { recursive: true });
    await writeFile(join(directory, filename), image, { flag: 'wx' });
    return { posterUrl: `/api/v1/events/posters/${filename}` };
  }

  async list(query: { campus?: string; category?: string; from?: string; to?: string; q?: string; cursor?: string }) {
    const rows = await this.prisma.event.findMany({
      where: {
        status: 'published',
        ...(query.category ? { category: { equals: query.category, mode: 'insensitive' } } : {}),
        ...(query.q ? { OR: [{ title: { contains: query.q, mode: 'insensitive' } }, { description: { contains: query.q, mode: 'insensitive' } }] } : {}),
        ...(query.from || query.to ? { startsAt: { ...(query.from ? { gte: new Date(query.from) } : {}), ...(query.to ? { lte: new Date(query.to) } : {}) } } : {}),
      },
      include: { club: { include: { college: true } } }, orderBy: [{ startsAt: 'asc' }, { id: 'asc' }],
      take: 21, ...(query.cursor ? { skip: 1, cursor: { id: query.cursor } } : {}),
    });
    const data = rows.slice(0, 20).map(({ club, ...event }) => ({ ...event, club: { id: club.id, name: club.name, college: club.college.name } }));
    return { data, nextCursor: rows.length > 20 ? rows[19].id : null };
  }

  async get(id: string) {
    const event = await this.prisma.event.findFirst({ where: { id, status: 'published' }, include: { club: { include: { college: true } } } });
    if (!event) throw new NotFoundException({ error: { code: 'EVENT_NOT_FOUND', message: 'Event was not found.' } });
    return { ...event, club: { id: event.club.id, name: event.club.name, college: event.club.college.name } };
  }

  async mine(userId: string) {
    return this.prisma.event.findMany({
      where: { club: { memberships: { some: { userId, status: 'active' } } } },
      include: { club: { include: { college: true } } }, orderBy: { updatedAt: 'desc' },
    });
  }

  async myRegistrations(userId: string) {
    const rows = await this.prisma.registration.findMany({
      where: { studentId: userId, status: { in: ['registered', 'waitlisted', 'attended', 'no_show'] } },
      include: { event: { include: { club: { include: { college: true } } } } }, orderBy: { registeredAt: 'desc' },
    });
    return rows.map(({ event, ...registration }) => ({ ...registration, event: { ...event, club: { id: event.club.id, name: event.club.name, college: event.club.college.name } } }));
  }

  async savedEvents(userId: string) {
    const rows = await this.prisma.savedEvent.findMany({ where: { studentId: userId }, include: { event: { include: { club: { include: { college: true } } } } }, orderBy: { savedAt: 'desc' } });
    return rows.map(({ event, ...saved }) => ({ ...saved, event: { ...event, club: { id: event.club.id, name: event.club.name, college: event.club.college.name } } }));
  }

  async saveEvent(userId: string, eventId: string) {
    const event = await this.prisma.event.findFirst({ where: { id: eventId, status: 'published' } });
    if (!event) throw new NotFoundException({ error: { code: 'EVENT_NOT_FOUND', message: 'Event was not found.' } });
    return this.prisma.savedEvent.upsert({ where: { studentId_eventId: { studentId: userId, eventId } }, create: { studentId: userId, eventId }, update: {} });
  }

  async unsaveEvent(userId: string, eventId: string) {
    await this.prisma.savedEvent.deleteMany({ where: { studentId: userId, eventId } });
    return { success: true };
  }

  async register(userId: string, eventId: string) {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await this.prisma.$transaction(async (tx) => {
          const event = await tx.event.findUnique({ where: { id: eventId } });
          if (!event || event.status !== 'published') throw new NotFoundException({ error: { code: 'EVENT_NOT_FOUND', message: 'Event is not available for registration.' } });
          if (event.minStudentsPerTeam !== 1 || event.maxStudentsPerTeam !== 1) throw new BadRequestException({ error: { code: 'TEAM_REQUIRED', message: `Register with a team of ${event.minStudentsPerTeam}–${event.maxStudentsPerTeam} students. Find or create a team for this event.` } });
          if (event.registrationMode !== 'native') throw new BadRequestException({ error: { code: 'EXTERNAL_REGISTRATION', message: 'This event uses an external registration form.' } });
          const now = new Date();
          if (event.registrationDeadline && event.registrationDeadline <= now) throw new BadRequestException({ error: { code: 'REGISTRATION_CLOSED', message: 'Registration is closed.' } });
          if (event.startsAt <= now) throw new BadRequestException({ error: { code: 'EVENT_STARTED', message: 'This event has already started.' } });
          const existing = await tx.registration.findUnique({ where: { eventId_studentId: { eventId, studentId: userId } } });
          if (existing && existing.status !== 'cancelled') return existing;
          const activeCount = await tx.registration.count({ where: { eventId, status: { in: ['registered', 'attended'] } } });
          const status = event.capacity !== null && activeCount >= event.capacity ? 'waitlisted' : 'registered';
          if (existing) return tx.registration.update({ where: { id: existing.id }, data: { status, registeredAt: now, cancelledAt: null } });
          return tx.registration.create({ data: { eventId, studentId: userId, status, registeredAt: now } });
        }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
      } catch (error) {
        if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2034' && attempt < 2) continue;
        if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
          const current = await this.prisma.registration.findUnique({ where: { eventId_studentId: { eventId, studentId: userId } } });
          if (current && current.status !== 'cancelled') return current;
        }
        throw error;
      }
    }
    throw new BadRequestException({ error: { code: 'REGISTRATION_RETRY', message: 'Please try registering again.' } });
  }

  async cancelRegistration(userId: string, eventId: string) {
    await this.prisma.$transaction(async (tx) => {
      const result = await tx.registration.updateMany({ where: { eventId, studentId: userId, status: { in: ['registered', 'waitlisted'] } }, data: { status: 'cancelled', cancelledAt: new Date() } });
      if (!result.count) throw new NotFoundException({ error: { code: 'REGISTRATION_NOT_FOUND', message: 'Active registration was not found.' } });
      const event = await tx.event.findUnique({ where: { id: eventId } });
      if (event?.capacity !== null && event?.capacity !== undefined) {
        const occupied = await tx.registration.count({ where: { eventId, status: { in: ['registered', 'attended'] } } });
        if (occupied < event.capacity) {
          const firstWaitlisted = await tx.registration.findFirst({ where: { eventId, status: 'waitlisted' }, orderBy: [{ registeredAt: 'asc' }, { id: 'asc' }] });
          if (firstWaitlisted) await tx.registration.update({ where: { id: firstWaitlisted.id }, data: { status: 'registered' } });
        }
      }
    });
    return { success: true };
  }

  async attendees(userId: string, eventId: string) {
    const event = await this.prisma.event.findUnique({ where: { id: eventId } });
    if (!event) throw new NotFoundException({ error: { code: 'EVENT_NOT_FOUND', message: 'Event was not found.' } });
    await this.assertOrganizer(userId, event.clubId);
    return this.prisma.registration.findMany({ where: { eventId, status: { in: ['registered', 'waitlisted', 'attended', 'no_show'] } }, include: { student: { select: { id: true, studentProfile: { select: { displayName: true, course: true, year: true } } } } }, orderBy: { registeredAt: 'asc' } });
  }

  async updateAttendance(userId: string, eventId: string, registrationId: string, status: 'attended' | 'no_show') {
    const event = await this.prisma.event.findUnique({ where: { id: eventId } });
    if (!event) throw new NotFoundException({ error: { code: 'EVENT_NOT_FOUND', message: 'Event was not found.' } });
    await this.assertOrganizer(userId, event.clubId);
    const result = await this.prisma.registration.updateMany({
      where: { id: registrationId, eventId, status: { in: ['registered', 'attended', 'no_show'] } },
      data: { status },
    });
    if (!result.count) throw new NotFoundException({ error: { code: 'REGISTRATION_NOT_FOUND', message: 'An active registration was not found.' } });
    return { success: true, status };
  }

  async create(userId: string, input: Record<string, unknown>) {
    const clubId = String(input.clubId ?? '');
    await this.assertOrganizer(userId, clubId);
    const event = this.eventInput(input);
    if (!event.title || !event.description || !event.category || !event.startsAt || !event.endsAt || !event.format) throw new BadRequestException({ error: { code: 'INVALID_EVENT', message: 'Provide title, description, category, format, and valid start and end times.' } });
    // Organizer-created events are immediately visible to students; campus review
    // is not part of the event publishing flow.
    return this.prisma.event.create({ data: { ...event, clubId, status: 'published' } });
  }

  async update(userId: string, eventId: string, input: Record<string, unknown>) {
    const existing = await this.prisma.event.findUnique({ where: { id: eventId } });
    if (!existing) throw new NotFoundException({ error: { code: 'EVENT_NOT_FOUND', message: 'Event was not found.' } });
    await this.assertOrganizer(userId, existing.clubId);
    if (existing.status === 'cancelled' || existing.status === 'completed') throw new BadRequestException({ error: { code: 'EVENT_NOT_EDITABLE', message: 'Cancelled or completed events cannot be edited.' } });
    if (input.minStudentsPerTeam !== undefined || input.maxStudentsPerTeam !== undefined) {
      const min = Number(input.minStudentsPerTeam ?? existing.minStudentsPerTeam);
      const max = Number(input.maxStudentsPerTeam ?? existing.maxStudentsPerTeam);
      if (!Number.isInteger(min) || !Number.isInteger(max) || min < 1 || max < min || max > 100) throw new BadRequestException({ error: { code: 'INVALID_TEAM_SIZE', message: 'Enter a minimum of at least 1 and a maximum that is not below it.' } });
      const registrations = await this.prisma.registration.count({ where: { eventId, status: { not: 'cancelled' } } });
      if (registrations > 0) throw new BadRequestException({ error: { code: 'TEAM_SIZE_LOCKED', message: 'Team size requirements cannot change after students register.' } });
    }
    return this.prisma.event.update({ where: { id: eventId }, data: this.eventInput(input, true) });
  }

  async delete(userId: string, eventId: string) {
    const event = await this.prisma.event.findUnique({ where: { id: eventId }, select: { id: true, clubId: true } });
    if (!event) throw new NotFoundException({ error: { code: 'EVENT_NOT_FOUND', message: 'Event was not found.' } });
    await this.assertOrganizer(userId, event.clubId);
    await this.prisma.event.delete({ where: { id: event.id } });
    return { success: true };
  }

  async submit(userId: string, eventId: string, publish = false) {
    const event = await this.prisma.event.findUnique({ where: { id: eventId }, include: { club: true } });
    if (!event) throw new NotFoundException({ error: { code: 'EVENT_NOT_FOUND', message: 'Event was not found.' } });
    await this.assertOrganizer(userId, event.clubId);
    if (['cancelled', 'completed'].includes(event.status)) throw new BadRequestException({ error: { code: 'INVALID_EVENT_TRANSITION', message: 'This event cannot be published in its current status.' } });
    return this.prisma.event.update({ where: { id: event.id }, data: { status: 'published' } });
  }

  private async assertOrganizer(userId: string, clubId: string) {
    const membership = await this.prisma.clubMembership.findUnique({ where: { clubId_userId: { clubId, userId } } });
    if (!membership || membership.status !== 'active') throw new ForbiddenException({ error: { code: 'CLUB_ACCESS_DENIED', message: 'You are not an active member of this club.' } });
  }

  private eventInput(input: Record<string, unknown>): Prisma.EventUncheckedCreateInput;
  private eventInput(input: Record<string, unknown>, partial: true): Prisma.EventUncheckedUpdateInput;
  private eventInput(input: Record<string, unknown>, partial = false): Prisma.EventUncheckedCreateInput | Prisma.EventUncheckedUpdateInput {
    const title = typeof input.title === 'string' ? input.title.trim() : '';
    const description = typeof input.description === 'string' ? input.description.trim() : '';
    const category = typeof input.category === 'string' ? input.category.trim() : '';
    const startsAt = new Date(String(input.startsAt ?? ''));
    const endsAt = new Date(String(input.endsAt ?? ''));
    const minStudentsPerTeam = Number(input.minStudentsPerTeam ?? 1);
    const maxStudentsPerTeam = Number(input.maxStudentsPerTeam ?? 1);
    const registrationDeadline = input.registrationDeadline ? new Date(String(input.registrationDeadline)) : null;
    const capacity = input.capacity;
    const externalUrl = typeof input.externalUrl === 'string' ? input.externalUrl.trim() : '';
    const posterUrl = typeof input.posterUrl === 'string' ? input.posterUrl.trim() : '';
    if (!partial && (!title || !description || !category || Number.isNaN(startsAt.getTime()) || Number.isNaN(endsAt.getTime()) || endsAt <= startsAt || !['in_person', 'online', 'hybrid'].includes(String(input.format)))) {
      throw new BadRequestException({ error: { code: 'INVALID_EVENT', message: 'Provide a title, description, category, and valid start and end times.' } });
    }
    if (input.capacity !== undefined && capacity !== null && (!Number.isInteger(capacity) || Number(capacity) < 1)) throw new BadRequestException({ error: { code: 'INVALID_CAPACITY', message: 'Capacity must be a positive whole number or left empty.' } });
    if ((!partial || input.minStudentsPerTeam !== undefined || input.maxStudentsPerTeam !== undefined) && (!Number.isInteger(minStudentsPerTeam) || !Number.isInteger(maxStudentsPerTeam) || minStudentsPerTeam < 1 || maxStudentsPerTeam < minStudentsPerTeam || maxStudentsPerTeam > 100)) throw new BadRequestException({ error: { code: 'INVALID_TEAM_SIZE', message: 'Enter a minimum of at least 1 and a maximum that is not below it.' } });
    if (input.registrationDeadline && (Number.isNaN(registrationDeadline?.getTime()) || (!Number.isNaN(startsAt.getTime()) && registrationDeadline! >= startsAt))) throw new BadRequestException({ error: { code: 'INVALID_REGISTRATION_DEADLINE', message: 'Registration deadline must be before the event starts.' } });
    if (input.registrationMode === 'external' && (!externalUrl || !URL.canParse(externalUrl))) throw new BadRequestException({ error: { code: 'INVALID_REGISTRATION_URL', message: 'Enter a valid external registration URL.' } });
    if (input.posterUrl && !/^\/api\/v1\/events\/posters\/[0-9a-f-]{36}\.jpg$/i.test(posterUrl)) throw new BadRequestException({ error: { code: 'INVALID_POSTER_URL', message: 'Upload an event photo using the event photo picker.' } });
    return {
      ...(!partial ? { clubId: String(input.clubId ?? '') } : {}),
      ...(title ? { title } : {}), ...(description ? { description } : {}), ...(category ? { category } : {}),
      ...(typeof input.format === 'string' ? { format: input.format as 'in_person' | 'online' | 'hybrid' } : {}),
      ...(input.venue !== undefined ? { venue: input.venue as string | null } : {}),
      ...(!Number.isNaN(startsAt.getTime()) ? { startsAt } : {}), ...(!Number.isNaN(endsAt.getTime()) ? { endsAt } : {}),
      ...(input.registrationDeadline !== undefined ? { registrationDeadline } : {}),
      ...(input.capacity !== undefined ? { capacity: capacity as number | null } : {}),
      ...(input.posterUrl !== undefined ? { posterUrl: input.posterUrl === null ? null : posterUrl || null } : {}),
      ...(!partial ? { minStudentsPerTeam, maxStudentsPerTeam } : {}),
      ...(partial && input.minStudentsPerTeam !== undefined ? { minStudentsPerTeam } : {}),
      ...(partial && input.maxStudentsPerTeam !== undefined ? { maxStudentsPerTeam } : {}),
      ...(input.registrationMode === 'external' ? { registrationMode: 'external' as const, externalUrl } : { registrationMode: 'native' as const, externalUrl: null }),
    };
  }
}
