import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { ConfigService } from '@nestjs/config';
import * as fs from 'fs'
import * as path from 'path';
const __certs_root = path.join(process.cwd(),'certs')

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    httpsOptions:{
      key: fs.readFileSync(path.join(__certs_root, 'server.key')),
      cert: fs.readFileSync(path.join(__certs_root, 'server.crt')),
      ca: fs.readFileSync(path.join(__certs_root, 'ca.crt')),
      //mtls
      requestCert:true,
      rejectUnauthorized:true
    }
  });
  await app.listen(process.env.PORT ?? 3000);
  console.log(`[${new Date().toISOString()}]:[started]:[${process.env.PORT}]`)
}
bootstrap();
