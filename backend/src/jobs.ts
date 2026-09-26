import {readFile} from 'node:fs/promises';
import {postgres} from './postgres.js';
import {publish,type Bundle} from './ingestion.js';
import {Store} from './store.js';
import {ingestRealtime,resolveUpdate} from './realtime.js';
import {ApnsAdapter,monitor} from './live.js';
import {Vault} from './security.js';
const url=process.env.DATABASE_URL;if(!url)throw new Error('DATABASE_URL required');
const db=postgres(url);
try{
  const command=process.argv[2];
  if(command==='cleanup')await new Store(db).cleanup(Date.now());
  else if(command==='publish'&&process.argv[3])await publish(db,JSON.parse(await readFile(process.argv[3],'utf8')) as Bundle);
  else if(command==='realtime'&&process.argv[3]&&process.argv[4])await ingestRealtime(new Store(db),process.argv[3],JSON.parse(await readFile(process.argv[4],'utf8')));
  else if(command==='monitor'){
    const env=process.env;
    if(!env.ENCRYPTION_KEY||!env.APNS_TEAM_ID||!env.APNS_KEY_ID||!env.APNS_PRIVATE_KEY_FILE||!env.APNS_BUNDLE_ID||!['sandbox','production'].includes(env.APNS_ENVIRONMENT??''))throw new Error('APNs configuration required');
    const store=new Store(db),vault=new Vault(env.ENCRYPTION_KEY),push=new ApnsAdapter({teamId:env.APNS_TEAM_ID,keyId:env.APNS_KEY_ID,privateKey:await readFile(env.APNS_PRIVATE_KEY_FILE,'utf8'),bundleId:env.APNS_BUNDLE_ID,environment:env.APNS_ENVIRONMENT as 'sandbox'|'production'});
    try{console.log(await monitor(store,vault,push,s=>resolveUpdate(store,s)));}finally{push.close();}
  }
  else throw new Error('Usage: jobs.ts cleanup | publish <bundle.json> | realtime <provider> <updates.json> | monitor');
}finally{await db.close();}
