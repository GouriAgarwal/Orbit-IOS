import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PrismaService } from '../../database/prisma.service';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

@Module({
  imports: [JwtModule.register({ secret: process.env.ACCESS_TOKEN_SECRET ?? 'local-only-change-me', signOptions: { expiresIn: '15m' } })],
  controllers: [AuthController],
  providers: [AuthService, PrismaService],
  exports: [JwtModule, PrismaService],
})
export class AuthModule {}
