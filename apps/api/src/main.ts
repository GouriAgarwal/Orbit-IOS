import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  const bodyParser = require('body-parser') as { json: (options: { limit: string }) => any; urlencoded: (options: { extended: boolean; limit: string }) => any };
  app.use(bodyParser.json({ limit: '7mb' }));
  app.use(bodyParser.urlencoded({ extended: true, limit: '7mb' }));
  app.setGlobalPrefix('api/v1');
  app.enableCors({ origin: false });
  await app.listen(Number(process.env.PORT ?? 3000));
}

void bootstrap();
