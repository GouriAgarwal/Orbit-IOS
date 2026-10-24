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

  @Get('verification/me')
  @UseGuards(AuthGuard)
  verificationRequests(@Req() request: UserRequest) {
    return this.prisma.clubVerificationRequest.findMany({
      where: { applicantId: request.user.id },
      include: { club: { include: { college: true } } },
      orderBy: { submittedAt: 'desc' },
    });
  }

  @Post(':clubId/verification')
  @UseGuards(AuthGuard)
  async resubmitVerification(@Req() request: UserRequest, @Param('clubId') clubId: string, @Body() body: { proofUrl: string; proofNotes: string }) {
    const existing = await this.prisma.clubVerificationRequest.findFirst({ where: { clubId, applicantId: request.user.id }, include: { club: true }, orderBy: { submittedAt: 'desc' } });
    if (!existing || existing.status !== 'rejected') throw new NotFoundException({ error: { code: 'VERIFICATION_RESUBMISSION_UNAVAILABLE', message: 'Only the applicant of a rejected club request can resubmit it.' } });
    const proofUrl = body.proofUrl?.trim();
    const proofNotes = body.proofNotes?.trim();
    let parsedProofUrl: URL | undefined;
    try { parsedProofUrl = new URL(proofUrl); } catch { /* validated below */ }
    if (!parsedProofUrl || parsedProofUrl.protocol !== 'https:' || !proofNotes || proofNotes.length < 10 || proofNotes.length > 1000) throw new BadRequestException({ error: { code: 'INVALID_CLUB_VERIFICATION', message: 'Provide an official HTTPS club or college page and 10–1,000 characters explaining the proof.' } });
    const eligibleAt = new Date(Date.now() + 48 * 60 * 60 * 1000);
    const [claim] = await this.prisma.$transaction([
      this.prisma.clubVerificationRequest.update({ where: { id: existing.id }, data: { proofUrl: parsedProofUrl.toString(), proofNotes, status: 'pending', submittedAt: new Date(), eligibleAt, reviewedAt: null, reviewNote: null }, include: { club: { include: { college: true } } } }),
      this.prisma.club.update({ where: { id: clubId }, data: { verificationStatus: 'pending' } }),
    ]);
    return claim;
  }

  @Get('verification/queue')
  @UseGuards(AuthGuard)
  async verificationQueue(@Req() request: UserRequest) {
    await this.requireVerifier(request.user.id);
    return this.prisma.clubVerificationRequest.findMany({
      where: { status: 'pending' },
      include: { club: { include: { college: true } }, applicant: { select: { emailNormalized: true, studentProfile: { select: { displayName: true } } } } },
      orderBy: [{ eligibleAt: 'asc' }, { submittedAt: 'asc' }],
    });
  }

  @Patch('verification/:requestId')
  @UseGuards(AuthGuard)
  async decideVerification(@Req() request: UserRequest, @Param('requestId') requestId: string, @Body() body: { decision: string; note?: string }) {
    await this.requireVerifier(request.user.id);
    if (!['approve', 'reject'].includes(body.decision)) throw new BadRequestException({ error: { code: 'INVALID_VERIFICATION_DECISION', message: 'Choose approve or reject.' } });
    const claim = await this.prisma.clubVerificationRequest.findUnique({ where: { id: requestId }, include: { club: true, applicant: { select: { emailNormalized: true } } } });
    if (!claim || claim.status !== 'pending') throw new NotFoundException({ error: { code: 'VERIFICATION_REQUEST_UNAVAILABLE', message: 'This verification request is no longer pending.' } });
    const reviewNote = body.note?.trim().slice(0, 500) ?? '';
    if (body.decision === 'approve' && claim.eligibleAt > new Date()) {
      throw new BadRequestException({ error: { code: 'VERIFICATION_HOLD_ACTIVE', message: `The 48-hour holding period ends at ${claim.eligibleAt.toISOString()}.` } });
    }
    await this.prisma.$transaction(async (tx) => {
      const updated = await tx.clubVerificationRequest.updateMany({ where: { id: requestId, status: 'pending' }, data: { status: body.decision === 'approve' ? 'approved' : 'rejected', reviewedAt: new Date(), reviewNote } });
      if (!updated.count) throw new ConflictException({ error: { code: 'VERIFICATION_REQUEST_UNAVAILABLE', message: 'This verification request was already reviewed.' } });
      await tx.club.update({ where: { id: claim.clubId }, data: { verificationStatus: body.decision === 'approve' ? 'verified' : 'rejected' } });
      if (body.decision === 'approve') {
        await tx.clubMembership.upsert({ where: { clubId_userId: { clubId: claim.clubId, userId: claim.applicantId } }, create: { clubId: claim.clubId, userId: claim.applicantId, role: 'owner', status: 'active' }, update: { role: 'owner', status: 'active' } });
      }
      await tx.notification.create({ data: { userId: claim.applicantId, type: `club_verification_${body.decision}`, title: body.decision === 'approve' ? 'Club verified' : 'Verification needs changes', body: body.decision === 'approve' ? `${claim.club.name} is verified. You can now manage the club in Orbit.` : `${claim.club.name} needs more verification information.${reviewNote ? ` Reviewer note: ${reviewNote}` : ''}`, payload: { clubId: claim.clubId, verificationRequestId: requestId } } });
    });
    return { success: true, verificationStatus: body.decision === 'approve' ? 'verified' : 'rejected' };
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
  async create(@Req() request: UserRequest, @Body() body: { collegeId: string; name: string; description?: string; proofUrl: string; proofNotes: string }) {
    const name = body.name?.trim();
    const proofUrl = body.proofUrl?.trim();
    const proofNotes = body.proofNotes?.trim();
    let parsedProofUrl: URL | undefined;
    try { parsedProofUrl = new URL(proofUrl); } catch { /* validated below */ }
    if (!name || name.length > 100 || !body.collegeId || !parsedProofUrl || parsedProofUrl.protocol !== 'https:' || !proofNotes || proofNotes.length < 10 || proofNotes.length > 1000) {
      throw new BadRequestException({ error: { code: 'INVALID_CLUB_VERIFICATION', message: 'Provide the college, club name, an official HTTPS club or college page, and 10–1,000 characters explaining the proof.' } });
    }
    const eligibleAt = new Date(Date.now() + 48 * 60 * 60 * 1000);
    return this.prisma.club.create({
      data: {
        collegeId: body.collegeId,
        name,
        description: body.description?.trim() ?? '',
        verificationStatus: 'pending',
        verificationRequest: { create: { applicantId: request.user.id, proofUrl: parsedProofUrl.toString(), proofNotes, eligibleAt } },
      },
      include: { college: true, verificationRequest: true },
    });
  }

  private async requireVerifier(userId: string) {
    const allowed = (process.env.ORBIT_CLUB_VERIFIER_EMAILS ?? '').split(',').map((email) => email.trim().toLowerCase()).filter(Boolean);
    if (!allowed.length) throw new ForbiddenException({ error: { code: 'CLUB_VERIFICATION_NOT_CONFIGURED', message: 'Club verification reviewers have not been configured.' } });
    const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { emailNormalized: true } });
    if (!user || !allowed.includes(user.emailNormalized)) throw new ForbiddenException({ error: { code: 'CLUB_VERIFIER_REQUIRED', message: 'Only a configured Orbit club verifier can review club claims.' } });
  }

  private async requireManager(userId: string, clubId: string) {
    const membership = await this.prisma.clubMembership.findUnique({ where: { clubId_userId: { clubId, userId } } });
    if (!membership || membership.status !== 'active' || !['owner', 'manager'].includes(membership.role)) throw new ForbiddenException({ error: { code: 'CLUB_ACCESS_DENIED', message: 'Only active club owners and managers can manage members.' } });
    return membership;
  }
}
