import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { createHash, randomBytes } from 'node:crypto';
import { PrismaService } from '../../database/prisma.service';

@Injectable()
export class AuthService {
  constructor(private readonly prisma: PrismaService, private readonly jwt: JwtService) {}
  private hashToken(token: string) { return createHash('sha256').update(token).digest('hex'); }

  async register(input: { email: string; password: string; displayName: string }) {
    const email = input.email?.trim().toLowerCase();
    const displayName = input.displayName?.trim();
    if (!email || !/^\S+@\S+\.\S+$/.test(email) || !displayName || displayName.length > 80 || !input.password || input.password.length > 128) {
      throw new ConflictException({ error: { code: 'INVALID_REGISTRATION', message: 'Enter a valid email, display name, and password.' } });
    }
    if (await this.prisma.user.findUnique({ where: { emailNormalized: email } })) throw new ConflictException({ error: { code: 'EMAIL_IN_USE', message: 'An account already exists for this email.' } });
    const user = await this.prisma.user.create({ data: { emailNormalized: email, passwordHash: await argon2.hash(input.password, { type: argon2.argon2id }), studentProfile: { create: { displayName } } } });
    return this.createSession(user.id, user.emailNormalized);
  }

  async login(input: { email: string; password: string }) {
    const email = input.email?.trim().toLowerCase() ?? '';
    const user = await this.prisma.user.findUnique({ where: { emailNormalized: email }, include: { studentProfile: true } });
    if (!user || user.accountStatus !== 'active' || !await argon2.verify(user.passwordHash, input.password ?? '')) throw new UnauthorizedException({ error: { code: 'INVALID_CREDENTIALS', message: 'Email or password is incorrect.' } });
    return this.createSession(user.id, user.emailNormalized);
  }

  private async createSession(userId: string, email: string) {
    const refreshToken = randomBytes(48).toString('base64url');
    await this.prisma.session.create({ data: { userId, refreshTokenHash: this.hashToken(refreshToken), expiresAt: new Date(Date.now() + 30 * 86400000) } });
    return { accessToken: await this.jwt.signAsync({ sub: userId, email }), refreshToken, tokenType: 'Bearer', expiresIn: 900 };
  }

  async refresh(token: string) {
    const session = await this.prisma.session.findUnique({ where: { refreshTokenHash: this.hashToken(token ?? '') }, include: { user: true } });
    if (!session || session.revokedAt || session.expiresAt <= new Date() || session.user.accountStatus !== 'active') throw new UnauthorizedException({ error: { code: 'SESSION_INVALID', message: 'Sign in again to continue.' } });
    const next = randomBytes(48).toString('base64url');
    const rotated = await this.prisma.session.updateMany({ where: { id: session.id, refreshTokenHash: this.hashToken(token), revokedAt: null, expiresAt: { gt: new Date() } }, data: { refreshTokenHash: this.hashToken(next), expiresAt: new Date(Date.now() + 30 * 86400000) } });
    if (rotated.count !== 1) throw new UnauthorizedException({ error: { code: 'SESSION_INVALID', message: 'Sign in again to continue.' } });
    return { accessToken: await this.jwt.signAsync({ sub: session.user.id, email: session.user.emailNormalized }), refreshToken: next, tokenType: 'Bearer', expiresIn: 900 };
  }

  async logout(token: string) {
    await this.prisma.session.updateMany({ where: { refreshTokenHash: this.hashToken(token ?? ''), revokedAt: null }, data: { revokedAt: new Date() } });
    return { success: true };
  }

  async me(token: string) {
    try {
      const payload = await this.jwt.verifyAsync<{ sub: string }>(token);
      const user = await this.prisma.user.findUnique({ where: { id: payload.sub }, include: { studentProfile: true } });
      if (!user || user.accountStatus !== 'active') throw new Error('inactive');
      return { id: user.id, profile: user.studentProfile };
    } catch { throw new UnauthorizedException({ error: { code: 'TOKEN_INVALID', message: 'Sign in again to continue.' } }); }
  }
}
