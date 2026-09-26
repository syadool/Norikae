import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import type {Database} from './store.js';
import {postgres} from './postgres.js';
export async function migrate(db:Database){
  const sql=await readFile(new URL('../migrations/001_initial.sql',import.meta.url),'utf8');
  await db.transaction(async tx=>{await tx.query(sql);});
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  if(!process.env.DATABASE_URL)throw new Error('DATABASE_URL required');
  const db=postgres(process.env.DATABASE_URL);try{await migrate(db);}finally{await db.close();}
}
