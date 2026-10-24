import { BadRequestException, Body, Controller, Get, Param, Post, Query, Req, UseGuards } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuthGuard } from '../../common/auth.guard';

type UserRequest = { user: { id: string } };
type TeamRoleInput = { title: string; description?: string; requiredSkills?: string[]; openings?: number };

@Controller()
@UseGuards(AuthGuard)
export class TeamsController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('teams')
  async list(@Req() req: UserRequest, @Query('q') q?: string, @Query('eventId') eventId?: string, @Query('matchSkills') matchSkills?: string) {
    const blocks = await this.prisma.userBlock.findMany({ where: { OR: [{ blockerId: req.user.id }, { blockedId: req.user.id }] }, select: { blockerId: true, blockedId: true } });
    const hiddenOwners = blocks.map((block) => block.blockerId === req.user.id ? block.blockedId : block.blockerId);
    const profile = matchSkills === 'true' ? await this.prisma.studentProfile.findUnique({ where: { userId: req.user.id }, select: { skills: true } }) : null;
    const skills = profile?.skills ?? [];
    const query = q?.trim();
    const teams = await this.prisma.team.findMany({
      where: {
        ownerId: { notIn: hiddenOwners },
        ...(eventId ? { eventId } : {}),
        OR: [
          { status: 'recruiting', roles: { some: { isOpen: true } } },
          { status: { in: ['full', 'locked'] }, ownerId: req.user.id },
        ],
        ...(query ? { AND: [{ OR: [
          { name: { contains: query, mode: 'insensitive' } },
          { goal: { contains: query, mode: 'insensitive' } },
          { description: { contains: query, mode: 'insensitive' } },
          { skillsNeeded: { hasSome: [query] } },
          { roles: { some: { isOpen: true, OR: [{ title: { contains: query, mode: 'insensitive' } }, { requiredSkills: { hasSome: [query] } }] } } },
        ] }] } : {}),
      },
      include: {
        owner: { select: { studentProfile: { select: { displayName: true, bio: true, skills: true, course: true, year: true } } } },
        event: { select: { id: true, title: true, startsAt: true, minStudentsPerTeam: true, maxStudentsPerTeam: true, club: { select: { name: true } } } },
        roles: { where: { isOpen: true }, orderBy: { createdAt: 'asc' } },
        memberships: { where: { status: 'active' }, include: { student: { select: { id: true, studentProfile: { select: { displayName: true, bio: true, skills: true, course: true, year: true } } } } } },
        requests: { where: { studentId: req.user.id }, select: { status: true } },
        _count: { select: { memberships: { where: { status: 'active' } } } },
      },
      orderBy: { createdAt: 'desc' }, take: 100,
    });
    const results = teams.map(({ owner, requests, ...team }) => ({
      ...team,
      owner: owner.studentProfile?.displayName ?? 'Student',
      ownerProfile: owner.studentProfile,
      isOwner: team.ownerId === req.user.id,
      myRequestStatus: requests[0]?.status ?? null,
    }));
    if (matchSkills === 'true' && skills.length) {
      const normalizedSkills = new Set(skills.map((skill) => skill.trim().toLocaleLowerCase()));
      return results.filter((team) => team.roles.some((role) => role.requiredSkills.some((skill) => normalizedSkills.has(skill.trim().toLocaleLowerCase()))));
    }
    return results;
  }

  @Post('teams')
  async create(@Req() req: UserRequest, @Body() body: { eventId: string; name: string; goal?: string; description?: string; roles?: TeamRoleInput[] }) {
    const name = body.name?.trim();
    const eventId = body.eventId?.trim();
    const roles = (body.roles ?? []).map((role) => ({
      title: role.title?.trim(),
      description: role.description?.trim().slice(0, 500) ?? '',
      requiredSkills: (role.requiredSkills ?? []).map((skill) => skill.trim()).filter(Boolean).slice(0, 12),
      openings: role.openings ?? 1,
    }));
    if (!name || name.length > 100 || !eventId || roles.length < 1 || roles.length > 12 || roles.some((role) => !role.title || role.title.length > 80 || role.requiredSkills.length < 1 || !Number.isInteger(role.openings) || role.openings < 1 || role.openings > 20)) {
      throw new BadRequestException({ error: { code: 'INVALID_TEAM', message: 'Choose an event, enter a team name, and add at least one role with required skills.' } });
    }
    const event = await this.prisma.event.findFirst({ where: { id: eventId, status: 'published', startsAt: { gt: new Date() } } });
    if (!event) throw new BadRequestException({ error: { code: 'EVENT_UNAVAILABLE', message: 'Choose an upcoming published event.' } });
    if (event.minStudentsPerTeam === 1 && event.maxStudentsPerTeam === 1) throw new BadRequestException({ error: { code: 'INDIVIDUAL_EVENT', message: 'This event accepts individual registrations and does not need teams.' } });
    const maxMembers = event.maxStudentsPerTeam;
    if (roles.reduce((sum, role) => sum + role.openings, 0) > maxMembers - 1) throw new BadRequestException({ error: { code: 'ROLE_CAPACITY', message: 'Open role seats cannot exceed the available places after the team leader.' } });
    return this.prisma.$transaction(async (tx) => {
      const team = await tx.team.create({ data: {
        ownerId: req.user.id, eventId, name,
        goal: body.goal?.trim().slice(0, 160) || 'Forming a team',
        description: body.description?.trim().slice(0, 1000) ?? '',
        skillsNeeded: [...new Set(roles.flatMap((role) => role.requiredSkills))],
        maxMembers,
        roles: { create: roles.map((role) => ({ ...role })) },
      } });
      // Team creator is immediately leader and takes one of the event's student places.
      await tx.teamMembership.create({ data: { teamId: team.id, studentId: req.user.id } });
      return tx.team.findUniqueOrThrow({ where: { id: team.id }, include: { roles: true, event: { select: { id: true, title: true, startsAt: true, minStudentsPerTeam: true, maxStudentsPerTeam: true, club: { select: { name: true } } } }, _count: { select: { memberships: { where: { status: 'active' } } } } } });
    });
  }

  @Post('teams/:teamId/requests')
  async requestJoin(@Req() req: UserRequest, @Param('teamId') teamId: string, @Body() body: { roleId: string; message?: string }) {
    const roleId = body.roleId?.trim();
    const team = await this.prisma.team.findUnique({ where: { id: teamId }, include: { roles: true } });
    if (!team || team.status !== 'recruiting') throw new BadRequestException({ error: { code: 'TEAM_CLOSED', message: 'This team is no longer recruiting.' } });
    if (team.ownerId === req.user.id) throw new BadRequestException({ error: { code: 'TEAM_OWNER', message: 'You own this team.' } });
    const role = team.roles.find((item) => item.id === roleId && item.isOpen && item.filled < item.openings);
    if (!role) throw new BadRequestException({ error: { code: 'ROLE_CLOSED', message: 'That role is no longer open.' } });
    const blocked = await this.prisma.userBlock.findFirst({ where: { OR: [{ blockerId: req.user.id, blockedId: team.ownerId }, { blockerId: team.ownerId, blockedId: req.user.id }] } });
    if (blocked) throw new BadRequestException({ error: { code: 'INTERACTION_BLOCKED', message: 'This interaction is unavailable.' } });
    const membership = await this.prisma.teamMembership.findUnique({ where: { teamId_studentId: { teamId, studentId: req.user.id } } });
    if (membership?.status === 'active') throw new BadRequestException({ error: { code: 'ALREADY_MEMBER', message: 'You are already a member of this team.' } });
    return this.prisma.teamRequest.upsert({
      where: { teamId_studentId: { teamId, studentId: req.user.id } },
      create: { teamId, studentId: req.user.id, initiatorId: req.user.id, roleId, message: body.message?.trim().slice(0, 500) ?? '' },
      update: { initiatorId: req.user.id, roleId, status: 'pending', message: body.message?.trim().slice(0, 500) ?? '' },
    });
  }

  @Get('teams/:teamId/candidates')
  async candidates(@Req() req: UserRequest, @Param('teamId') teamId: string, @Query('roleId') roleId?: string, @Query('q') q?: string) {
    const team = await this.prisma.team.findUnique({ where: { id: teamId }, include: { roles: { where: { isOpen: true } }, memberships: { where: { status: 'active' }, select: { studentId: true } } } });
    if (!team || team.ownerId !== req.user.id || team.status !== 'recruiting') throw new BadRequestException({ error: { code: 'TEAM_UNAVAILABLE', message: 'Only the team leader can invite students to an open team.' } });
    const selectedRoles = roleId ? team.roles.filter((role) => role.id === roleId) : team.roles;
    if (!selectedRoles.length) throw new BadRequestException({ error: { code: 'ROLE_CLOSED', message: 'That role is no longer open.' } });
    const requests = await this.prisma.teamRequest.findMany({ where: { teamId, status: { in: ['pending', 'accepted'] } }, select: { studentId: true } });
    const blocks = await this.prisma.userBlock.findMany({ where: { OR: [{ blockerId: req.user.id }, { blockedId: req.user.id }] }, select: { blockerId: true, blockedId: true } });
    const excluded = [...new Set([req.user.id, ...team.memberships.map((member) => member.studentId), ...requests.map((request) => request.studentId), ...blocks.map((block) => block.blockerId === req.user.id ? block.blockedId : block.blockerId)])];
    const query = q?.trim().toLocaleLowerCase();
    const candidates = await this.prisma.studentProfile.findMany({
      where: {
        userId: { notIn: excluded },
        visibility: { in: ['campus', 'public'] },
      },
      select: { userId: true, displayName: true, bio: true, skills: true, interests: true, course: true, year: true, portfolioUrl: true, projects: { where: { visibility: { in: ['campus', 'public'] } }, select: { id: true, title: true, description: true, url: true } } },
      orderBy: { displayName: 'asc' }, take: 100,
    });
    const wantedSkills = new Set(selectedRoles.flatMap((role) => role.requiredSkills).map((skill) => skill.trim().toLocaleLowerCase()));
    const matching = candidates.filter((candidate) => {
      const hasNeededSkill = candidate.skills.some((skill) => wantedSkills.has(skill.trim().toLocaleLowerCase()));
      const matchesQuery = !query || [candidate.displayName, candidate.bio, candidate.course, ...candidate.skills, ...candidate.interests]
        .some((value) => value?.toLocaleLowerCase().includes(query));
      return hasNeededSkill && matchesQuery;
    });
    // Email lookup is exact and returns only a profile the student has made visible.
    // The address itself is never included in the response.
    if (query?.includes('@')) {
      const account = await this.prisma.user.findUnique({
        where: { emailNormalized: query },
        select: { id: true, accountStatus: true, studentProfile: { select: { userId: true, displayName: true, bio: true, skills: true, interests: true, course: true, year: true, portfolioUrl: true, visibility: true, projects: { where: { visibility: { in: ['campus', 'public'] } }, select: { id: true, title: true, description: true, url: true } } } } },
      });
      if (account?.accountStatus === 'active' && account.studentProfile && account.studentProfile.visibility !== 'private' && !excluded.includes(account.id) && !matching.some((candidate) => candidate.userId === account.id)) {
        const { visibility: _visibility, ...profile } = account.studentProfile!;
        matching.unshift({ ...profile, userId: account.id });
      }
    }
    return matching.map(({ userId, ...profile }) => ({ id: userId, studentProfile: profile }));
  }

  @Post('teams/:teamId/invitations')
  async invite(@Req() req: UserRequest, @Param('teamId') teamId: string, @Body() body: { studentId: string; roleId: string; message?: string }) {
    const team = await this.prisma.team.findUnique({ where: { id: teamId }, include: { roles: { where: { isOpen: true } } } });
    if (!team || team.ownerId !== req.user.id || team.status !== 'recruiting') throw new BadRequestException({ error: { code: 'TEAM_UNAVAILABLE', message: 'Only the team leader can invite students to an open team.' } });
    const role = team.roles.find((item) => item.id === body.roleId && item.filled < item.openings);
    if (!role) throw new BadRequestException({ error: { code: 'ROLE_CLOSED', message: 'That role is no longer open.' } });
    const studentId = body.studentId;
    const candidate = await this.prisma.studentProfile.findFirst({ where: { userId: studentId, visibility: { in: ['campus', 'public'] } }, select: { userId: true, skills: true } });
    if (!candidate || studentId === req.user.id) throw new BadRequestException({ error: { code: 'CANDIDATE_UNAVAILABLE', message: 'This student is not available for that role.' } });
    const blocked = await this.prisma.userBlock.findFirst({ where: { OR: [{ blockerId: req.user.id, blockedId: studentId }, { blockerId: studentId, blockedId: req.user.id }] } });
    if (blocked) throw new BadRequestException({ error: { code: 'INTERACTION_BLOCKED', message: 'This interaction is unavailable.' } });
    const membership = await this.prisma.teamMembership.findUnique({ where: { teamId_studentId: { teamId, studentId } } });
    if (membership?.status === 'active') throw new BadRequestException({ error: { code: 'ALREADY_MEMBER', message: 'This student is already a member of the team.' } });
    const prior = await this.prisma.teamRequest.findUnique({ where: { teamId_studentId: { teamId, studentId } } });
    if (prior?.status === 'pending' || prior?.status === 'accepted') throw new BadRequestException({ error: { code: 'REQUEST_EXISTS', message: 'This student already has an active application or invitation.' } });
    return this.prisma.teamRequest.upsert({
      where: { teamId_studentId: { teamId, studentId } },
      create: { teamId, studentId, initiatorId: req.user.id, roleId: role.id, message: body.message?.trim().slice(0, 500) ?? '' },
      update: { initiatorId: req.user.id, roleId: role.id, status: 'pending', message: body.message?.trim().slice(0, 500) ?? '' },
    });
  }

  @Post('teams/:teamId/lock')
  async lock(@Req() req: UserRequest, @Param('teamId') teamId: string) {
    return this.prisma.$transaction(async (tx) => {
      const team = await tx.team.findUnique({ where: { id: teamId }, include: { event: true, memberships: { where: { status: 'active' } } } });
      if (!team || team.ownerId !== req.user.id || !team.event) throw new BadRequestException({ error: { code: 'TEAM_UNAVAILABLE', message: 'Only the team leader can lock a team connected to an event.' } });
      if (team.status === 'locked') return { success: true, status: team.status, registeredCount: team.memberships.length };
      if (!['recruiting', 'full'].includes(team.status)) throw new BadRequestException({ error: { code: 'TEAM_CLOSED', message: 'This team cannot be locked.' } });
      const event = team.event;
      const count = team.memberships.length;
      if (event.status !== 'published' || event.startsAt <= new Date() || (event.registrationDeadline && event.registrationDeadline <= new Date())) throw new BadRequestException({ error: { code: 'REGISTRATION_CLOSED', message: 'Registration for this event is closed.' } });
      if (event.minStudentsPerTeam === 1 && event.maxStudentsPerTeam === 1) throw new BadRequestException({ error: { code: 'INDIVIDUAL_EVENT', message: 'This event uses individual registration and does not need teams.' } });
      if (count < event.minStudentsPerTeam || count > event.maxStudentsPerTeam || count > team.maxMembers) throw new BadRequestException({ error: { code: 'TEAM_SIZE_REQUIREMENT', message: `This team needs ${event.minStudentsPerTeam}–${event.maxStudentsPerTeam} students before it can lock.` } });
      const members = team.memberships.map((member) => member.studentId);
      const existing = await tx.registration.findMany({ where: { eventId: event.id, studentId: { in: members }, status: { in: ['registered', 'attended'] } }, select: { studentId: true } });
      if (existing.length) throw new BadRequestException({ error: { code: 'ALREADY_REGISTERED', message: 'One or more team members are already registered for this event.' } });
      const registeredCount = await tx.registration.count({ where: { eventId: event.id, status: { in: ['registered', 'attended'] } } });
      if (event.capacity !== null && registeredCount + count > event.capacity) throw new BadRequestException({ error: { code: 'EVENT_FULL', message: 'There are not enough event places for this whole team.' } });
      const now = new Date();
      for (const studentId of members) {
        await tx.registration.upsert({
          where: { eventId_studentId: { eventId: event.id, studentId } },
          create: { eventId: event.id, studentId, status: 'registered', registeredAt: now },
          update: { status: 'registered', registeredAt: now, cancelledAt: null },
        });
      }
      await tx.team.update({ where: { id: team.id }, data: { status: 'locked' } });
      return { success: true, status: 'locked', registeredCount: count };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
  }

  @Get('me/team-requests')
  requests(@Req() req: UserRequest) {
    return this.prisma.teamRequest.findMany({
      where: { team: { ownerId: req.user.id }, initiatorId: { not: req.user.id } },
      include: {
        team: { select: { id: true, name: true } },
        role: { select: { id: true, title: true, description: true, requiredSkills: true, openings: true, filled: true, isOpen: true } },
        student: { select: { id: true, studentProfile: { select: { displayName: true, bio: true, course: true, year: true, skills: true, interests: true, portfolioUrl: true, projects: { select: { id: true, title: true, description: true, url: true } } } } } },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  @Post('team-requests/:requestId/:decision')
  async decide(@Req() req: UserRequest, @Param('requestId') requestId: string, @Param('decision') decision: string) {
    if (decision !== 'accept' && decision !== 'decline') throw new BadRequestException({ error: { code: 'INVALID_DECISION', message: 'Decision must be accept or decline.' } });
    return this.prisma.$transaction(async (tx) => {
      const application = await tx.teamRequest.findUnique({ where: { id: requestId }, include: { team: true, role: true } });
      if (!application || application.status !== 'pending') throw new BadRequestException({ error: { code: 'REQUEST_UNAVAILABLE', message: 'Team request is unavailable.' } });
      const isTeamInvitation = application.initiatorId === application.team.ownerId;
      const allowed = isTeamInvitation ? application.studentId === req.user.id : application.team.ownerId === req.user.id;
      if (!allowed) throw new BadRequestException({ error: { code: 'REQUEST_UNAVAILABLE', message: 'Team request is unavailable.' } });
      if (decision === 'decline') return tx.teamRequest.update({ where: { id: requestId }, data: { status: 'declined' } });
      if (!application.role || !application.role.isOpen || application.role.filled >= application.role.openings) throw new BadRequestException({ error: { code: 'ROLE_CLOSED', message: 'This role has already been filled.' } });
      const count = await tx.teamMembership.count({ where: { teamId: application.teamId, status: 'active' } });
      if (count >= application.team.maxMembers) throw new BadRequestException({ error: { code: 'TEAM_FULL', message: 'The team has reached its member limit.' } });
      await tx.teamMembership.upsert({ where: { teamId_studentId: { teamId: application.teamId, studentId: application.studentId } }, create: { teamId: application.teamId, studentId: application.studentId }, update: { status: 'active' } });
      await tx.teamRole.update({ where: { id: application.roleId! }, data: { filled: { increment: 1 }, ...(application.role.filled + 1 >= application.role.openings ? { isOpen: false } : {}) } });
      await tx.team.update({ where: { id: application.teamId }, data: { status: count + 1 >= application.team.maxMembers ? 'full' : 'recruiting' } });
      return tx.teamRequest.update({ where: { id: requestId }, data: { status: 'accepted' } });
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
  }
}
