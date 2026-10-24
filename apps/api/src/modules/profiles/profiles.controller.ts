import { BadRequestException, Body, Controller, Delete, Get, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuthGuard } from '../../common/auth.guard';

type UserRequest = { user: { id: string } };

@Controller('me')
@UseGuards(AuthGuard)
export class ProfilesController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('profile')
  get(@Req() req: UserRequest) {
    return this.prisma.studentProfile.findUnique({ where: { userId: req.user.id }, include: { projects: { orderBy: { createdAt: 'desc' } }, college: { select: { id: true, name: true } } } });
  }

  @Patch('profile')
  async update(@Req() req: UserRequest, @Body() body: { displayName?: string; course?: string; year?: number; bio?: string; collegeId?: string; visibility?: 'campus' | 'public' | 'private'; skills?: string[]; interests?: string[]; portfolioUrl?: string; achievements?: string[] }) {
    if (body.displayName !== undefined && (!body.displayName.trim() || body.displayName.length > 80)) throw new BadRequestException({ error: { code: 'INVALID_PROFILE', message: 'Display name must be 1–80 characters.' } });
    const cleanList = (list?: string[]) => list?.map((item) => item.trim()).filter(Boolean).slice(0, 30);
    return this.prisma.studentProfile.update({ where: { userId: req.user.id }, data: {
      ...(body.displayName !== undefined ? { displayName: body.displayName.trim() } : {}),
      ...(body.course !== undefined ? { course: body.course.trim() } : {}),
      ...(body.year !== undefined ? { year: body.year >= 1 && body.year <= 8 ? body.year : null } : {}),
      ...(body.bio !== undefined ? { bio: body.bio.trim().slice(0, 500) } : {}),
      ...(body.collegeId !== undefined ? { collegeId: body.collegeId || null } : {}),
      ...(body.visibility !== undefined ? { visibility: body.visibility } : {}),
      ...(body.skills !== undefined ? { skills: cleanList(body.skills) } : {}),
      ...(body.interests !== undefined ? { interests: cleanList(body.interests) } : {}),
      ...(body.portfolioUrl !== undefined ? { portfolioUrl: body.portfolioUrl.trim().slice(0, 500) || null } : {}),
      ...(body.achievements !== undefined ? { achievements: cleanList(body.achievements) } : {}),
    }, include: { projects: true } });
  }

  @Post('projects')
  createProject(@Req() req: UserRequest, @Body() body: { title: string; description?: string; url?: string }) {
    const title = body.title?.trim();
    if (!title || title.length > 100) throw new BadRequestException({ error: { code: 'INVALID_PROJECT', message: 'Project title is required and must be under 100 characters.' } });
    return this.prisma.project.create({ data: { studentId: req.user.id, title, description: body.description?.trim().slice(0, 1000) ?? '', url: body.url?.trim() || null } });
  }

  @Patch('projects/:projectId')
  async updateProject(@Req() req: UserRequest, @Param('projectId') projectId: string, @Body() body: { title?: string; description?: string; url?: string }) {
    const result = await this.prisma.project.updateMany({ where: { id: projectId, studentId: req.user.id }, data: {
      ...(body.title !== undefined ? { title: body.title.trim().slice(0, 100) } : {}),
      ...(body.description !== undefined ? { description: body.description.trim().slice(0, 1000) } : {}),
      ...(body.url !== undefined ? { url: body.url.trim() || null } : {}),
    } });
    if (!result.count) throw new BadRequestException({ error: { code: 'PROJECT_NOT_FOUND', message: 'Project was not found.' } });
    return { success: true };
  }

  @Delete('projects/:projectId')
  async deleteProject(@Req() req: UserRequest, @Param('projectId') projectId: string) {
    await this.prisma.project.deleteMany({ where: { id: projectId, studentId: req.user.id } });
    return { success: true };
  }
}
