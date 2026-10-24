import { BadRequestException, Body, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '../../common/auth.guard';
import { PrismaService } from '../../database/prisma.service';

type UserRequest = { user: { id: string } };

@Controller('connections')
@UseGuards(AuthGuard)
export class ConnectionsController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async accepted(@Req() request: UserRequest) {
    const rows = await this.prisma.connectionRequest.findMany({ where: { status: 'accepted', OR: [{ senderId: request.user.id }, { recipientId: request.user.id }] }, include: { sender: { select: { id: true, studentProfile: { select: { displayName: true } } } }, recipient: { select: { id: true, studentProfile: { select: { displayName: true } } } } } });
    return rows.map((row) => row.senderId === request.user.id ? row.recipient : row.sender);
  }

  @Post('requests')
  async request(@Req() request: UserRequest, @Body() body: { recipientId: string }) {
    const senderId = request.user.id; const recipientId = body.recipientId;
    if (!recipientId || recipientId === senderId) throw new BadRequestException({ error: { code: 'INVALID_RECIPIENT', message: 'Choose another student.' } });
    const blocked = await this.prisma.userBlock.findFirst({ where: { OR: [{ blockerId: senderId, blockedId: recipientId }, { blockerId: recipientId, blockedId: senderId }] } });
    if (blocked) throw new BadRequestException({ error: { code: 'INTERACTION_BLOCKED', message: 'This interaction is unavailable.' } });
    const existing = await this.prisma.connectionRequest.findFirst({ where: { OR: [{ senderId, recipientId }, { senderId: recipientId, recipientId: senderId }], status: { in: ['pending', 'accepted'] } } });
    if (existing) throw new BadRequestException({ error: { code: existing.status === 'accepted' ? 'ALREADY_CONNECTED' : 'REQUEST_EXISTS', message: existing.status === 'accepted' ? 'You are already connected.' : 'A connection request is already active.' } });
    const connection = await this.prisma.connectionRequest.upsert({ where: { senderId_recipientId: { senderId, recipientId } }, create: { senderId, recipientId }, update: { status: 'pending' } });
    await this.prisma.notification.create({ data: { userId: recipientId, type: 'connection_request', title: 'New connection request', body: 'A student would like to connect.', payload: { requestId: connection.id } } });
    return connection;
  }

  @Post('requests/:requestId/:decision')
  async decide(@Req() request: UserRequest, @Param('requestId') requestId: string, @Param('decision') decision: string) {
    if (!['accept', 'decline'].includes(decision)) throw new BadRequestException({ error: { code: 'INVALID_DECISION', message: 'Decision must be accept or decline.' } });
    const connection = await this.prisma.connectionRequest.findUnique({ where: { id: requestId } });
    if (!connection || connection.recipientId !== request.user.id || connection.status !== 'pending') throw new BadRequestException({ error: { code: 'REQUEST_UNAVAILABLE', message: 'Connection request is unavailable.' } });
    const updated = await this.prisma.connectionRequest.update({ where: { id: requestId }, data: { status: decision === 'accept' ? 'accepted' : 'declined' } });
    await this.prisma.notification.create({ data: { userId: connection.senderId, type: 'connection_response', title: decision === 'accept' ? 'Connection accepted' : 'Connection declined', body: decision === 'accept' ? 'Your connection request was accepted.' : 'Your connection request was declined.', payload: { requestId } } });
    return updated;
  }
}
