import { randomUUID } from 'node:crypto';
import { ApiError } from './errors.js';
import { hash, secret, Vault } from './security.js';
import type { MonitoredLeg, AttributionModel } from './contracts.js';

export interface Sql {
  query<T extends Record<string,any> = Record<string,any>>(sql:string,params?:any[]):Promise<{rows:T[];rowCount?:number|null}>;
}
export type IsolationLevel = 'READ COMMITTED' | 'REPEATABLE READ';
export interface Database extends Sql { transaction<T>(fn:(sql:Sql)=>Promise<T>,isolation?:IsolationLevel):Promise<T>; close():Promise<void>; }
export interface Document<T=any> {value:T;as_of:Date|string;valid_until:Date|string;sources:string[];attributions:AttributionModel[];}
export interface Session {installation_id:string;activity_id:string;encrypted_token:string;legs:MonitoredLeg[];expires_at:Date;created_at:Date;last_state_hash:string|null;last_sent_at:Date|null;last_state?:{legs:{platform?:string}[]}|null;}
export class Store {
  constructor(public db:Database){}
  async register(vault:Vault,now:number){
    const id=randomUUID(),refresh=secret();
    await this.db.query('INSERT INTO installations(id,refresh_hash,refresh_expires_at) VALUES($1,$2,$3)',[id,hash(refresh),new Date(now+30*86400_000)]);
    return {installationId:id,accessToken:vault.token(id,now),refreshToken:refresh,expiresIn:900,tokenType:'Bearer' as const};
  }
  async refresh(token:string,vault:Vault,now:number){
    const refresh=secret();
    const {rows}=await this.db.query('UPDATE installations SET refresh_hash=$1,refresh_expires_at=$2 WHERE refresh_hash=$3 AND refresh_expires_at>$4 RETURNING id',[hash(refresh),new Date(now+30*86400_000),hash(token),new Date(now)]);
    if(!rows[0])throw new ApiError('AUTHENTICATION_REQUIRED');
    return {installationId:rows[0].id,accessToken:vault.token(rows[0].id,now),refreshToken:refresh,expiresIn:900,tokenType:'Bearer' as const};
  }
  async exists(owner:string){return (await this.db.query('SELECT id FROM installations WHERE id=$1',[owner])).rows.length>0;}
  async limit(key:string,max:number,now:number){
    const bucket=Math.floor(now/60_000);
    const {rows}=await this.db.query('INSERT INTO rate_limits(key,count,expires_at) VALUES($1,1,$2) ON CONFLICT(key) DO UPDATE SET count=rate_limits.count+1 RETURNING count',[`${key}:${bucket}`,new Date((bucket+2)*60_000)]);
    if(rows[0]!.count>max)throw new ApiError('RATE_LIMITED');
  }
  async entity(kind:string,id:string){return (await this.db.query('SELECT value FROM master_entities WHERE entity=$1 AND id=$2',[kind,id])).rows[0]?.value;}
  async entities(kind:string){return (await this.db.query('SELECT value FROM master_entities WHERE entity=$1 ORDER BY id',[kind])).rows.map(r=>r.value);}
  async snapshot(){
    return this.db.transaction(async sql=>{
      const version=Number((await sql.query('SELECT max(version) AS version FROM master_versions')).rows[0]?.version??0);
      const rows=(await sql.query('SELECT entity,value FROM master_entities ORDER BY id')).rows;
      return {version,stations:rows.filter(r=>r.entity==='stations').map(r=>r.value),lines:rows.filter(r=>r.entity==='lines').map(r=>r.value),operators:rows.filter(r=>r.entity==='operators').map(r=>r.value),trainTypes:rows.filter(r=>r.entity==='trainTypes').map(r=>r.value)};
    });
  }
  async changes(since:number){
    return this.db.transaction(async sql=>{
      const version=Number((await sql.query('SELECT max(version) AS version FROM master_versions')).rows[0]?.version??0);
      if(since>version)throw new ApiError('INVALID_REQUEST');
      const rows=(await sql.query('SELECT * FROM master_changes WHERE version>$1 AND version<=$2 ORDER BY version,entity,id',[since,version])).rows;
      return {version,changes:rows.map(r=>({version:Number(r.version),entity:r.entity,id:r.id,operation:r.operation,...(r.value?{value:r.value}:{}),...(r.replaced_by_id?{replacedById:r.replaced_by_id}:{})}))};
    });
  }
  async document<T=any>(kind:string,id:string):Promise<Document<T>|undefined>{return (await this.db.query('SELECT * FROM transport_documents WHERE kind=$1 AND id=$2',[kind,id])).rows[0] as Document<T>|undefined;}
  async documents(kind:string):Promise<Document[]>{return (await this.db.query('SELECT * FROM transport_documents WHERE kind=$1 ORDER BY id',[kind])).rows as Document[];}
  async mutateActivity(owner:string,id:string,key:string,requestHash:string,now:number,record?:{token:string;legs:MonitoredLeg[];expiresAt:string}){
    return this.db.transaction(async sql=>{
      // Lock the installation so retries and token rotation are serialized across instances.
      await sql.query('SELECT id FROM installations WHERE id=$1 FOR UPDATE',[owner]);
      const previous=(await sql.query('SELECT request_hash FROM idempotency_keys WHERE installation_id=$1 AND key=$2 AND expires_at>$3',[owner,key,new Date(now)])).rows[0];
      if(previous){if(previous.request_hash!==requestHash)throw new ApiError('ROUTE_CONTEXT_MISMATCH');return;}
      if(record){
        await sql.query(`INSERT INTO live_activity_sessions(installation_id,activity_id,encrypted_token,legs,expires_at,created_at)
          VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(installation_id,activity_id) DO UPDATE SET
          encrypted_token=EXCLUDED.encrypted_token,legs=EXCLUDED.legs,
          expires_at=LEAST(EXCLUDED.expires_at,live_activity_sessions.created_at+interval '24 hours'),last_state_hash=NULL,last_sent_at=NULL,last_state=NULL`,[owner,id,record.token,JSON.stringify(record.legs),new Date(record.expiresAt),new Date(now)]);
      }else await sql.query('DELETE FROM live_activity_sessions WHERE installation_id=$1 AND activity_id=$2',[owner,id]);
      await sql.query(`INSERT INTO idempotency_keys(installation_id,key,request_hash,expires_at) VALUES($1,$2,$3,$4)
        ON CONFLICT(installation_id,key) DO UPDATE SET request_hash=EXCLUDED.request_hash,expires_at=EXCLUDED.expires_at`,[owner,key,requestHash,new Date(now+86400_000)]);
    },'READ COMMITTED');
  }
  async cleanup(now:number){
    await this.db.transaction(async sql=>{
      for(const table of ['live_activity_sessions','idempotency_keys','rate_limits'])await sql.query(`DELETE FROM ${table} WHERE expires_at<=$1`,[new Date(now)]);
      await sql.query('DELETE FROM installations WHERE refresh_expires_at<=$1',[new Date(now)]);
      await sql.query("DELETE FROM push_delivery_attempts WHERE attempted_at<$1",[new Date(now-30*86400_000)]);
    });
  }
}
