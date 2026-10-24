import { BadRequestException, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '../../common/auth.guard';
import { PrismaService } from '../../database/prisma.service';

type UserRequest = { user: { id: string } };

@Controller('me')
@UseGuards(AuthGuard)
export class InboxController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('inbox')
  async inbox(@Req() request: UserRequest) {
    const userId = request.user.id;
    const [incomingTeamRequests, outgoingTeamRequests, incomingTeamInvitations, connectionRequests, notifications, clubInvitations] = await Promise.all([
      this.prisma.teamRequest.findMany({ where: { status: 'pending', team: { ownerId: userId }, initiatorId: { not: userId } }, include: { team: { select: { id: true, name: true } }, role: { select: { id: true, title: true, description: true, requiredSkills: true, openings: true, filled: true, isOpen: true } }, student: { select: { id: true, studentProfile: { select: { displayName: true, bio: true, course: true, year: true, skills: true, interests: true, portfolioUrl: true, projects: { select: { id: true, title: true, description: true, url: true } } } } } } }, orderBy: { createdAt: 'desc' } }),
      this.prisma.teamRequest.findMany({
        where: { studentId: userId, initiatorId: userId },
        include: { team: { select: { id: true, name: true, owner: { select: { studentProfile: { select: { displayName: true } } } } } } },
        orderBy: { updatedAt: 'desc' },
      }),
      this.prisma.teamRequest.findMany({ where: { studentId: userId, initiatorId: { not: userId }, status: 'pending' }, include: { team: { select: { id: true, name: true, owner: { select: { studentProfile: { select: { displayName: true } } } } } }, role: { select: { id: true, title: true } } }, orderBy: { createdAt: 'desc' } }),
      this.prisma.connectionRequest.findMany({ where: { OR: [{ senderId: userId }, { recipientId: userId }], status: { in: ['pending', 'accepted'] } }, include: { sender: { select: { id: true, studentProfile: { select: { displayName: true } } } }, recipient: { select: { id: true, studentProfile: { select: { displayName: true } } } } }, orderBy: { updatedAt: 'desc' } }),
      this.prisma.notification.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, take: 50 }),
      this.prisma.clubMembership.findMany({ where: { userId, status: 'invited' }, include: { club: { select: { id: true, name: true, college: { select: { name: true } } } } }, orderBy: { createdAt: 'desc' } }),
    ]);
    const normalizedConnections = connectionRequests.map((item) => ({ ...item, incoming: item.recipientId === userId, person: item.senderId === userId ? item.recipient : item.sender }));
    return { incomingTeamRequests, outgoingTeamRequests, incomingTeamInvitations, connectionRequests: normalizedConnections, notifications, clubInvitations };
  }

  @Post('club-invitations/:membershipId/:decision')
  async decideClubInvitation(@Req() request: UserRequest, @Param('membershipId') membershipId: string, @Param('decision') decision: string) {
    if (!['accept', 'decline'].includes(decision)) throw new BadRequestException({ error: { code: 'INVALID_DECISION', message: 'Decision must be accept or decline.' } });
    const invitation = await this.prisma.clubMembership.findFirst({ where: { id: membershipId, userId: request.user.id, status: 'invited' } });
    if (!invitation) throw new BadRequestException({ error: { code: 'INVITATION_UNAVAILABLE', message: 'This club invitation is no longer available.' } });
    if (decision === 'accept') await this.prisma.clubMembership.update({ where: { id: membershipId }, data: { status: 'active' } });
    else await this.prisma.clubMembership.delete({ where: { id: membershipId } });
    return { success: true };
  }

  @Post('notifications/:notificationId/read')
  async markRead(@Req() request: UserRequest, @Param('notificationId') notificationId: string) {
    await this.prisma.notification.updateMany({ where: { id: notificationId, userId: request.user.id, readAt: null }, data: { readAt: new Date() } });
    return { success: true };
  }
}
