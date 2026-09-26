import { Type as T,type Static } from '@sinclair/typebox';
import {Value} from '@sinclair/typebox/value';
import * as C from './contracts.js';
import type {Database} from './store.js';

const Entity=T.Union([T.Literal('stations'),T.Literal('lines'),T.Literal('operators'),T.Literal('trainTypes')]);
export const FeedBundle=T.Object({
  provider:C.id,version:C.id,licenseUrl:T.String({format:'uri'}),displayText:C.id,reviewedForPublication:T.Literal(true),
  asOf:C.dateTime,validUntil:C.dateTime,master:T.Omit(C.MasterData,['version']),
  documents:T.Array(T.Object({kind:T.Union(['trainRun','directions','timetable','status','capability','regionCapability','transfer'].map(v=>T.Literal(v))),id:C.id,value:T.Unknown()})),
  deletions:T.Optional(T.Array(T.Object({entity:Entity,id:C.id,replacedById:T.Optional(C.id)})))
},{additionalProperties:false});
export type Bundle=Static<typeof FeedBundle>;
const schemas:Record<string,any>={trainRun:C.TrainRun,directions:T.Array(C.Direction),timetable:C.Timetable,status:C.Status,capability:C.Capability,regionCapability:T.Object({region:C.Region,features:T.Object({viaStations:C.Availability,firstLastTrain:C.Availability})}),transfer:T.Object({minutes:T.Integer({minimum:0,maximum:120})})};
// Validation precedes a single atomic publication; failure leaves the previous version intact.
export async function publish(db:Database,bundle:Bundle){
  if(!Value.Check(FeedBundle,bundle)||Date.parse(bundle.validUntil)<=Date.parse(bundle.asOf))throw new Error('Invalid feed bundle');
  const seen=new Set<string>();
  for(const [entity,items] of Object.entries(bundle.master))for(const item of items){const key=`${entity}:${item.id}`;if(seen.has(key))throw new Error('Duplicate canonical ID');seen.add(key);}
  const docKeys=new Set<string>();
  for(const d of bundle.documents){
    if(docKeys.has(`${d.kind}:${d.id}`)||!Value.Check(schemas[d.kind],d.value))throw new Error('Invalid transport document');docKeys.add(`${d.kind}:${d.id}`);
    if(d.kind==='trainRun'){
      const run=d.value as Static<typeof C.TrainRun>;let previous=-Infinity;
      if(run.stops.length<2)throw new Error('Train run requires two stops');
      for(const stop of run.stops){const time=Date.parse(stop.scheduledTime);if(time<previous)throw new Error('Non-monotonic stop times');previous=time;}
      if(d.id!==`${run.id}:${run.stops[0]!.serviceDate}`)throw new Error('Train run document ID mismatch');
    }
  }
  return db.transaction(async sql=>{
    await sql.query('LOCK TABLE master_versions IN EXCLUSIVE MODE');
    const existing=(await sql.query('SELECT entity,id,value FROM master_entities')).rows;
    const all=new Map(existing.map(r=>[`${r.entity}:${r.id}`,r.value]));
    for(const [entity,items] of Object.entries(bundle.master))for(const item of items)all.set(`${entity}:${item.id}`,item);
    for(const deletion of bundle.deletions??[])all.delete(`${deletion.entity}:${deletion.id}`);
    const requireId=(kind:string,id:string)=>{if(!all.has(`${kind}:${id}`))throw new Error(`Unmapped ${kind} reference`);};
    for(const [key,value] of all){
      if(key.startsWith('lines:'))requireId('operators',value.operatorId);
      if(key.startsWith('stations:'))for(const id of value.lineIds)requireId('lines',id);
    }
    for(const d of bundle.documents){
      const v=d.value as any;
      if(v.lineId)requireId('lines',v.lineId);if(v.stationId)requireId('stations',v.stationId);if(v.trainTypeId)requireId('trainTypes',v.trainTypeId);
      if(d.kind==='trainRun')for(const stop of v.stops)requireId('stations',stop.stationId);
      if(d.kind==='directions')for(const direction of v)requireId('lines',direction.lineId);
    }
    for(const deletion of bundle.deletions??[])if(deletion.replacedById)requireId(deletion.entity,deletion.replacedById);
    if(existing.length>10&&(bundle.deletions?.length??0)>existing.length*0.2)throw new Error('Excessive deletion: manual migration required');
    const version=Number((await sql.query('SELECT max(version) AS v FROM master_versions')).rows[0]?.v??0)+1;
    await sql.query('INSERT INTO master_versions(version,published_at) VALUES($1,$2)',[version,new Date(bundle.asOf)]);
    for(const [entity,items] of Object.entries(bundle.master))for(const item of items){
      await sql.query('INSERT INTO master_entities(entity,id,value) VALUES($1,$2,$3) ON CONFLICT(entity,id) DO UPDATE SET value=EXCLUDED.value',[entity,item.id,JSON.stringify(item)]);
      await sql.query("INSERT INTO master_changes(version,entity,id,operation,value) VALUES($1,$2,$3,'upsert',$4)",[version,entity,item.id,JSON.stringify(item)]);
    }
    for(const d of bundle.deletions??[]){await sql.query('DELETE FROM master_entities WHERE entity=$1 AND id=$2',[d.entity,d.id]);await sql.query("INSERT INTO master_changes(version,entity,id,operation,replaced_by_id) VALUES($1,$2,$3,'delete',$4)",[version,d.entity,d.id,d.replacedById??null]);}
    // Replace the schedule snapshot while preserving independently ingested realtime updates.
    await sql.query("DELETE FROM transport_documents WHERE sources @> $1::jsonb AND kind <> 'tripUpdate'",[JSON.stringify([bundle.provider])]);
    const attrs=[{provider:bundle.provider,displayText:bundle.displayText,licenseUrl:bundle.licenseUrl}];
    for(const d of bundle.documents)await sql.query(`INSERT INTO transport_documents(kind,id,value,as_of,valid_until,sources,attributions) VALUES($1,$2,$3,$4,$5,$6,$7)
      ON CONFLICT(kind,id) DO UPDATE SET value=EXCLUDED.value,as_of=EXCLUDED.as_of,valid_until=EXCLUDED.valid_until,sources=EXCLUDED.sources,attributions=EXCLUDED.attributions`,[d.kind,d.id,JSON.stringify(d.value),new Date(bundle.asOf),new Date(bundle.validUntil),JSON.stringify([bundle.provider]),JSON.stringify(attrs)]);
    await sql.query('INSERT INTO feed_states(id,published_at,version,license_url,display_text) VALUES($1,$2,$3,$4,$5) ON CONFLICT(id) DO UPDATE SET published_at=EXCLUDED.published_at,version=EXCLUDED.version,license_url=EXCLUDED.license_url,display_text=EXCLUDED.display_text',[bundle.provider,new Date(bundle.asOf),bundle.version,bundle.licenseUrl,bundle.displayText]);
    return version;
  });
}
