import {connect,type ClientHttp2Session} from 'node:http2';
import {createPrivateKey,sign} from 'node:crypto';
import {hash,Vault} from './security.js';
import type {Store,Session} from './store.js';
export interface DynamicLeg {index:number;scheduledDeparture:number;scheduledArrival:number;estimatedDeparture?:number;estimatedArrival?:number;platform?:string;delayMinutes?:number;isCancelled:boolean;}
export interface ContentState {legs:DynamicLeg[];disruptionSummary?:string;updatedAt:number;}
export interface LiveUpdate {state:ContentState;asOf:number;staleAt:number;urgent:boolean;}
export interface PushAdapter {send(token:string,payload:unknown,urgent:boolean):Promise<'sent'|'invalid-token'|'retry'>;}
export function payload(update:LiveUpdate){
  const result={aps:{timestamp:update.asOf,event:'update','stale-date':update.staleAt,'content-state':update.state}};
  if(Buffer.byteLength(JSON.stringify(result))>4096)throw new Error('APNs payload exceeds 4KB');return result;
}
export class ApnsAdapter implements PushAdapter {
  private jwt?:{value:string;issuedAt:number};
  private client?:ClientHttp2Session;
  constructor(private config:{teamId:string;keyId:string;privateKey:string;bundleId:string;environment:'sandbox'|'production'},private transport:{connect:typeof connect;now:()=>number}={connect,now:Date.now}){}
  private authorization(){
    const now=this.transport.now();
    if(this.jwt&&now>=this.jwt.issuedAt&&now-this.jwt.issuedAt<30*60_000)return this.jwt.value;
    const c=this.config,header=Buffer.from(JSON.stringify({alg:'ES256',kid:c.keyId})).toString('base64url');
    const claims=Buffer.from(JSON.stringify({iss:c.teamId,iat:Math.floor(now/1000)})).toString('base64url');
    const input=`${header}.${claims}`,signature=sign('sha256',Buffer.from(input),{key:createPrivateKey(c.privateKey),dsaEncoding:'ieee-p1363'}).toString('base64url');
    this.jwt={value:`bearer ${input}.${signature}`,issuedAt:now};return this.jwt.value;
  }
  private connection(){
    if(this.client&&!this.client.closed&&!this.client.destroyed)return this.client;
    const client=this.transport.connect(`https://api.${this.config.environment==='sandbox'?'sandbox.':''}push.apple.com`);
    this.client=client;
    const retire=()=>{if(this.client===client)this.client=undefined;};
    client.on('error',()=>{retire();client.destroy();});
    client.on('goaway',()=>{retire();client.close();});
    client.on('close',retire);
    return client;
  }
  close(){this.client?.destroy();this.client=undefined;}
  async send(token:string,body:unknown,urgent:boolean):Promise<'sent'|'invalid-token'|'retry'>{
    const authorization=this.authorization(),encoded=JSON.stringify(body),client=this.connection();
    return new Promise(resolve=>{
      let done=false;
      const finish=(value:'sent'|'invalid-token'|'retry')=>{if(done)return;done=true;clearTimeout(timer);resolve(value);};
      const timer=setTimeout(()=>{finish('retry');req?.close();},5000);
      let req:ReturnType<ClientHttp2Session['request']>|undefined;
      try{
        req=client.request({':method':'POST',':path':`/3/device/${token}`,authorization,'apns-topic':`${this.config.bundleId}.push-type.liveactivity`,'apns-push-type':'liveactivity','apns-priority':urgent?'10':'5','apns-expiration':'0'});
        let status=0,response='';req.on('response',h=>{status=Number(h[':status']);});req.on('data',b=>{if(response.length<4096)response+=b.toString();});
        req.on('error',()=>finish('retry'));req.on('close',()=>finish('retry'));
        req.on('end',()=>{let reason='';try{reason=JSON.parse(response).reason;}catch{}finish(status===200?'sent':status===410||reason==='BadDeviceToken'||reason==='DeviceTokenNotForTopic'?'invalid-token':'retry');});
        req.end(encoded);
      }catch{finish('retry');}
    });
  }
}
export async function monitor(store:Store,vault:Vault,push:PushAdapter,resolve:(session:Session)=>Promise<LiveUpdate|undefined>,now=Date.now()){
  await store.cleanup(now);
  const sessions=(await store.db.query<Session>('SELECT * FROM live_activity_sessions WHERE expires_at>$1',[new Date(now)])).rows;
  const outcomes={sent:0,skipped:0,retry:0,removed:0};
  for(const session of sessions){
    try{
      const update=await resolve(session);if(!update||update.staleAt*1000<=now){outcomes.skipped++;continue;}
      if(update.state.legs.length!==session.legs.length||update.state.legs.some((l,i)=>l.index!==i))throw new Error('ContentState must contain all train legs in order');
      const digest=hash(JSON.stringify({legs:update.state.legs,disruptionSummary:update.state.disruptionSummary}));
      const outcome=await store.db.transaction(async sql=>{
        // Lock across workers. A successful send is recorded before the lock is released.
        const current=(await sql.query<Session>('SELECT * FROM live_activity_sessions WHERE installation_id=$1 AND activity_id=$2 FOR UPDATE',[session.installation_id,session.activity_id])).rows[0];
        const platformChanged=current?.last_state?.legs.some((l,i)=>l.platform!==undefined&&update.state.legs[i]?.platform!==undefined&&l.platform!==update.state.legs[i]?.platform)??false;
        const urgent=update.urgent||platformChanged;
        if(!current||new Date(current.expires_at).getTime()<=now||current.encrypted_token!==session.encrypted_token||JSON.stringify(current.legs)!==JSON.stringify(session.legs)||current.last_state_hash===digest||!urgent&&current.last_sent_at&&now-new Date(current.last_sent_at).getTime()<45_000){return 'skipped' as const;}
        const result=await push.send(vault.open<string>(current.encrypted_token,'push'),payload(update),urgent);
        await sql.query('INSERT INTO push_delivery_attempts(outcome) VALUES($1)',[result]);
        if(result==='sent'){await sql.query('UPDATE live_activity_sessions SET last_state_hash=$1,last_sent_at=$2,last_state=$5 WHERE installation_id=$3 AND activity_id=$4',[digest,new Date(now),current.installation_id,current.activity_id,JSON.stringify(update.state)]);return 'sent' as const;}
        else if(result==='invalid-token'){await sql.query('DELETE FROM live_activity_sessions WHERE installation_id=$1 AND activity_id=$2',[current.installation_id,current.activity_id]);return 'removed' as const;}
        else return 'retry' as const;
      },'READ COMMITTED');
      outcomes[outcome]++;
    }catch{outcomes.retry++;}
  }
  return outcomes;
}
