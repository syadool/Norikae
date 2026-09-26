import {buildApp} from './app.js';
import {postgres} from './postgres.js';
import {Store} from './store.js';
import {LocalScheduleProvider} from './providers/local.js';
import {NavitimeEstimateService,rapidClient} from './providers/navitime.js';
const {DATABASE_URL,ENCRYPTION_KEY}=process.env;
if(!DATABASE_URL||!ENCRYPTION_KEY)throw new Error('DATABASE_URL and ENCRYPTION_KEY required');
// Anonymous enrollment is intentionally private until App Attest verification is implemented.
if(process.env.DEPLOYMENT_MODE!=='private')throw new Error('Set DEPLOYMENT_MODE=private; public enrollment is not yet supported');
const db=postgres(DATABASE_URL);
const store=new Store(db);
let navitime:NavitimeEstimateService|undefined;
if(process.env.NAVITIME_ENABLED==='true'){
  if(!process.env.NAVITIME_ATTRIBUTION_TEXT)throw new Error('NAVITIME_ATTRIBUTION_TEXT is required when enabling NAVITIME');
  navitime=new NavitimeEstimateService(store,rapidClient(store),{provider:'navitime-rapidapi',displayText:process.env.NAVITIME_ATTRIBUTION_TEXT,...(process.env.NAVITIME_LICENSE_URL?{licenseUrl:process.env.NAVITIME_LICENSE_URL}:{})});
}
const trustProxy=process.env.TRUST_PROXY?.split(',').map(value=>value.trim()).filter(Boolean);
const app=await buildApp({trustProxy,db,encryptionKey:ENCRYPTION_KEY,logger:true,navitime,providers:[new LocalScheduleProvider(store)]});
for(const signal of ['SIGTERM','SIGINT'])process.once(signal,()=>{void app.close().then(()=>db.close());});
await app.listen({port:Number(process.env.PORT??8080),host:'0.0.0.0'});
