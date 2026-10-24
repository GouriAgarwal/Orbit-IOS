import { BadRequestException, Body, ConflictException, Controller, Delete, ForbiddenException, Get, NotFoundException, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '../../common/auth.guard';
import { PrismaService } from '../../database/prisma.service';

type UserRequest = { user: { id: string } };

@Controller('clubs')
export class ClubsController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('colleges')
  colleges() { return this.prisma.college.findMany({ orderBy: { name: 'asc' } }); }

  @Get('me')
  @UseGuards(AuthGuard)
  myClubs(@Req() request: UserRequest) {
    return this.prisma.club.findMany({ where: { memberships: { some: { userId: request.user.id, status: 'active' } } }, include: { college: true, memberships: { where: { userId: request.user.id, status: 'active' }, select: { role: true } } }, orderBy: { name: 'asc' } }).then((clubs) => clubs.map(({ memberships, ...club }) => ({ ...club, currentRole: memberships[0]?.role ?? 'editor' })));
  }

  @Get(':clubId/members')
  @UseGuards(AuthGuard)
  async members(@Req() request: UserRequest, @Param('clubId') clubId: string) {
    await this.requireManager(request.user.id, clubId);
    return this.prisma.clubMembership.findMany({ where: { clubId }, include: { user: { select: { id: true, studentProfile: { select: { displayName: true, course: true, year: true } } } } }, orderBy: [{ status: 'asc' }, { createdAt: 'asc' }] });
  }

  @Post(':clubId/invitations')
  @UseGuards(AuthGuard)
  async invite(@Req() request: UserRequest, @Param('clubId') clubId: string, @Body() body: { email: string; role?: 'manager' | 'editor' }) {
    const actor = await this.requireManager(request.user.id, clubId);
    const email = body.email?.trim().toLowerCase();
    if (!email || !/^\S+@\S+\.\S+$/.test(email)) throw new BadRequestException({ error: { code: 'INVALID_EMAIL', message: 'Enter a valid student email.' } });
    const role = body.role === 'manager' && actor.role === 'owner' ? 'manager' : 'editor';
    if (body.role === 'manager' && actor.role !== 'owner') throw new ForbiddenException({ error: { code: 'ROLE_ASSIGNMENT_DENIED', message: 'Only the club owner can invite managers.' } });
    const [club, user] = await Promise.all([
      this.prisma.club.findUnique({ where: { id: clubId }, select: { id: true, name: true, collegeId: true } }),
      this.prisma.user.findUnique({ where: { emailNormalized: email }, include: { studentProfile: true } }),
    ]);
    if (!club) throw new NotFoundException({ error: { code: 'CLUB_NOT_FOUND', message: 'Club was not found.' } });
    if (!user?.studentProfile || user.accountStatus !== 'active') throw new NotFoundException({ error: { code: 'STUDENT_NOT_FOUND', message: 'No active Orbit student account was found for that email.' } });
    if (user.id === request.user.id) throw new BadRequestException({ error: { code: 'SELF_INVITATION', message: 'You are already a club member.' } });
    if (user.studentProfile.collegeId !== club.collegeId) throw new BadRequestException({ error: { code: 'COLLEGE_MISMATCH', message: 'Invite students whose profile is set to this club’s college.' } });
    const existing = await this.prisma.clubMembership.findUnique({ where: { clubId_userId: { clubId, userId: user.id } } });
    if (existing?.status === 'active') throw new ConflictException({ error: { code: 'ALREADY_A_MEMBER', message: 'This student is already an active member.' } });
    const [membership] = await this.prisma.$transaction([
      this.prisma.clubMembership.upsert({ where: { clubId_userId: { clubId, userId: user.id } }, create: { clubId, userId: user.id, role, status: 'invited' }, update: { role, status: 'invited' }, include: { user: { select: { id: true, studentProfile: { select: { displayName: true } } } } } }),
      this.prisma.notification.create({ data: { userId: user.id, type: 'club_invitation', title: 'Club invitation', body: `You have been invited to join ${club.name}.`, payload: { clubId, role } } }),
    ]);
    return membership;
  }

  @Patch(':clubId/members/:userId')
  @UseGuards(AuthGuard)
  async updateMemberRole(@Req() request: UserRequest, @Param('clubId') clubId: string, @Param('userId') userId: string, @Body() body: { role: 'manager' | 'editor' }) {
    const actor = await this.requireManager(request.user.id, clubId);
    if (actor.role !== 'owner') throw new ForbiddenException({ error: { code: 'ROLE_ASSIGNMENT_DENIED', message: 'Only the club owner can change member roles.' } });
    if (!['manager', 'editor'].includes(body.role)) throw new BadRequestException({ error: { code: 'INVALID_ROLE', message: 'Choose manager or editor.' } });
    const result = await this.prisma.clubMembership.updateMany({ where: { clubId, userId, role: { not: 'owner' } }, data: { role: body.role } });
    if (!result.count) throw new NotFoundException({ error: { code: 'MEMBER_NOT_FOUND', message: 'Club member was not found.' } });
    return { success: true };
  }

  @Delete(':clubId/members/:userId')
  @UseGuards(AuthGuard)
  async removeMember(@Req() request: UserRequest, @Param('clubId') clubId: string, @Param('userId') userId: string) {
    const actor = await this.requireManager(request.user.id, clubId);
    const target = await this.prisma.clubMembership.findUnique({ where: { clubId_userId: { clubId, userId } } });
    if (!target || target.role === 'owner') throw new NotFoundException({ error: { code: 'MEMBER_NOT_FOUND', message: 'Club member was not found.' } });
    if (actor.role !== 'owner' && target.role !== 'editor') throw new ForbiddenException({ error: { code: 'MEMBER_REMOVAL_DENIED', message: 'Only the club owner can remove a manager.' } });
    await this.prisma.clubMembership.delete({ where: { clubId_userId: { clubId, userId } } });
    return { success: true };
  }

  @Post()
  @UseGuards(AuthGuard)
  async create(@Req() request: UserRequest, @Body() body: { collegeId: string; name: string; description?: string }) {
    const name = body.name?.trim();
    if (!name || name.length > 100 || !body.collegeId) throw new BadRequestException({ error: { code: 'INVALID_CLUB', message: 'Choose a college and provide a club name under 100 characters.' } });
    return this.prisma.club.create({
      data: { collegeId: body.collegeId, name, description: body.description?.trim() ?? '', memberships: { create: { userId: request.user.id, role: 'owner' } } },
      include: { college: true },
    });
  }

  private async requireManager(userId: string, clubId: string) {
    const membership = await this.prisma.clubMembership.findUnique({ where: { clubId_userId: { clubId, userId } } });
    if (!membership || membership.status !== 'active' || !['owner', 'manager'].includes(membership.role)) throw new ForbiddenException({ error: { code: 'CLUB_ACCESS_DENIED', message: 'Only active club owners and managers can manage members.' } });
    return membership;
  }
}
