import { Body, Controller, Get, Headers, Post, UnauthorizedException } from '@nestjs/common';
import { AuthService } from './auth.service';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('register') register(@Body() body: { email: string; password: string; displayName: string }) {
    return this.auth.register(body);
  }

  @Post('login') login(@Body() body: { email: string; password: string }) {
    return this.auth.login(body);
  }

  @Post('refresh') refresh(@Body() body: { refreshToken: string }) { return this.auth.refresh(body.refreshToken); }

  @Post('logout') logout(@Body() body: { refreshToken: string }) { return this.auth.logout(body.refreshToken); }

  @Get('me') async me(@Headers('authorization') authorization?: string) {
    const token = authorization?.startsWith('Bearer ') ? authorization.slice(7) : '';
    if (!token) throw new UnauthorizedException({ error: { code: 'AUTH_REQUIRED', message: 'Sign in to continue.' } });
    return this.auth.me(token);
  }
}
