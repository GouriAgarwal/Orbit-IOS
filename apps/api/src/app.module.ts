import { Module } from '@nestjs/common';
import { EventsController } from './modules/events/events.controller';
import { EventsService } from './modules/events/events.service';
import { HealthController } from './modules/health/health.controller';
import { AuthModule } from './modules/auth/auth.module';
import { PrismaService } from './database/prisma.service';
import { AuthGuard } from './common/auth.guard';
import { ClubsController } from './modules/clubs/clubs.controller';
import { ProfilesController } from './modules/profiles/profiles.controller';
import { TeamsController } from './modules/teams/teams.controller';
import { SafetyController } from './modules/safety/safety.controller';
import { InboxController } from './modules/inbox/inbox.controller';
import { ConnectionsController } from './modules/connections/connections.controller';
import { AIController } from './modules/ai/ai.controller';
import { GeminiService } from './modules/ai/gemini.service';

@Module({ imports: [AuthModule], controllers: [HealthController, EventsController, ClubsController, ProfilesController, TeamsController, SafetyController, InboxController, ConnectionsController, AIController], providers: [EventsService, PrismaService, AuthGuard, GeminiService] })
export class AppModule {}
