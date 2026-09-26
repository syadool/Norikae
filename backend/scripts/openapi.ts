import {writeFile} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {buildApp} from '../src/app.js';
import type {Database} from '../src/store.js';
const db:Database={async query(){throw new Error('OpenAPI export must not query DB');},async transaction(){throw new Error('OpenAPI export must not query DB');},async close(){}};
const app=await buildApp({db,encryptionKey:randomBytes(32).toString('base64')});
await writeFile('openapi.json',JSON.stringify(app.swagger(),null,2)+'\n');
await app.close();
