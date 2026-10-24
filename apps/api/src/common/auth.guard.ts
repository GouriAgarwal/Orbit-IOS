import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly jwt: JwtService) {}
  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<{ headers: { authorization?: string }; user?: { id: string } }>();
    const value = request.headers.authorization;
    if (!value?.startsWith('Bearer ')) throw new UnauthorizedException({ error: { code: 'AUTH_REQUIRED', message: 'Sign in to continue.' } });
    try {
      const payload = await this.jwt.verifyAsync<{ sub: string }>(value.slice(7));
      request.user = { id: payload.sub };
      return true;
    } catch { throw new UnauthorizedException({ error: { code: 'TOKEN_INVALID', message: 'Sign in again to continue.' } }); }
  }
}
