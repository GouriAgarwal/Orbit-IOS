import { BadRequestException, Body, Controller, Delete, Get, NotFoundException, Param, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '../../common/auth.guard';
import { PrismaService } from '../../database/prisma.service';

type UserRequest = { user: { id: string } };

@Controller()
@UseGuards(AuthGuard)
export class SafetyController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('me/blocks')
  blocks(@Req() request: UserRequest) {
    return this.prisma.userBlock.findMany({ where: { blockerId: request.user.id }, include: { blocked: { select: { id: true, studentProfile: { select: { displayName: true } } } } }, orderBy: { createdAt: 'desc' } });
  }

  @Post('me/blocks')
  async block(@Req() request: UserRequest, @Body() body: { userId: string }) {
    if (!body.userId || body.userId === request.user.id) throw new BadRequestException({ error: { code: 'INVALID_BLOCK', message: 'Choose another student to block.' } });
    if (!await this.prisma.user.findUnique({ where: { id: body.userId }, select: { id: true } })) throw new NotFoundException({ error: { code: 'USER_NOT_FOUND', message: 'Student was not found.' } });
    return this.prisma.userBlock.upsert({ where: { blockerId_blockedId: { blockerId: request.user.id, blockedId: body.userId } }, create: { blockerId: request.user.id, blockedId: body.userId }, update: {} });
  }

  @Delete('me/blocks/:userId')
  async unblock(@Req() request: UserRequest, @Param('userId') userId: string) {
    await this.prisma.userBlock.deleteMany({ where: { blockerId: request.user.id, blockedId: userId } });
    return { success: true };
  }

  @Post('reports')
  async report(@Req() request: UserRequest, @Body() body: { targetType: string; targetId: string; reason: string; details?: string }) {
    if (!['user', 'event', 'team', 'club'].includes(body.targetType) || !body.targetId || !body.reason?.trim()) throw new BadRequestException({ error: { code: 'INVALID_REPORT', message: 'Choose a report reason and valid content to report.' } });
    return this.prisma.report.create({ data: { reporterId: request.user.id, targetType: body.targetType as 'user' | 'event' | 'team' | 'club', targetId: body.targetId, reason: body.reason.trim().slice(0, 100), details: body.details?.trim().slice(0, 1000) ?? '' } });
  }
}
