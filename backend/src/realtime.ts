import {Type as T,type Static} from '@sinclair/typebox';
import {Value} from '@sinclair/typebox/value';
import {dateTime,id} from './contracts.js';
import type {Store,Session} from './store.js';
import type {LiveUpdate,DynamicLeg} from './live.js';
export const TripUpdate=T.Object({trainRunId:id,serviceDate:T.String({format:'date'}),asOf:dateTime,validUntil:dateTime,isCancelled:T.Boolean(),summary:T.Optional(id),stops:T.Array(T.Object({stationId:id,scheduledTime:dateTime,estimatedTime:T.Optional(dateTime),platform:T.Optional(id),delayMinutes:T.Optional(T.Integer({minimum:0}))}))},{additionalProperties:false});
export type TripUpdateModel=Static<typeof TripUpdate>;
export async function ingestRealtime(store:Store,provider:string,updates:TripUpdateModel[],now=Date.now()){
  const source=(await store.db.query('SELECT * FROM feed_states WHERE id=$1',[provider])).rows[0];
  if(!source)throw new Error('Realtime source requires a reviewed license record');
  for(const update of updates){
    if(!Value.Check(TripUpdate,update)||Date.parse(update.asOf)>now+60_000||Date.parse(update.validUntil)<=now||Date.parse(update.validUntil)<=Date.parse(update.asOf))throw new Error('Invalid realtime update');
    const run=await store.document('trainRun',`${update.trainRunId}:${update.serviceDate}`);
    if(!run||update.stops.some(stop=>!run.value.stops.some((s:any)=>s.stationId===stop.stationId&&Date.parse(s.scheduledTime)===Date.parse(stop.scheduledTime))))throw new Error('Unmapped trip update');
  }
  await store.db.transaction(async sql=>{
    for(const update of updates)await sql.query(`INSERT INTO transport_documents(kind,id,value,as_of,valid_until,sources,attributions) VALUES('tripUpdate',$1,$2,$3,$4,$5,$6)
      ON CONFLICT(kind,id) DO UPDATE SET value=EXCLUDED.value,as_of=EXCLUDED.as_of,valid_until=EXCLUDED.valid_until,sources=EXCLUDED.sources,attributions=EXCLUDED.attributions
      WHERE transport_documents.as_of<=EXCLUDED.as_of`,[`${update.trainRunId}:${update.serviceDate}`,JSON.stringify(update),new Date(update.asOf),new Date(update.validUntil),JSON.stringify([provider]),JSON.stringify([{provider,displayText:source.display_text,licenseUrl:source.license_url}])]);
  });
}
export async function resolveUpdate(store:Store,session:Session,now=Date.now()):Promise<LiveUpdate|undefined>{
  const legs:DynamicLeg[]=[];let asOf=now,staleAt=Infinity,urgent=false;const summaries=new Set<string>();
  for(const [index,leg] of session.legs.entries()){
    if(!leg.trainRunId)return undefined;
    const doc=await store.document<TripUpdateModel>('tripUpdate',`${leg.trainRunId}:${leg.serviceDate}`);
    // Never erase previously known real-time fields with fabricated defaults.
    if(!doc||new Date(doc.valid_until).getTime()<=now)return undefined;
    const u=doc.value,from=u.stops.find(s=>s.stationId===leg.from.stationId&&Date.parse(s.scheduledTime)===Date.parse(leg.from.scheduledTime)),to=u.stops.find(s=>s.stationId===leg.to.stationId&&Date.parse(s.scheduledTime)===Date.parse(leg.to.scheduledTime));
    if(!from||!to)return undefined;
    const unix=(v:string)=>Math.floor(Date.parse(v)/1000);
    legs.push({index,scheduledDeparture:unix(leg.from.scheduledTime),scheduledArrival:unix(leg.to.scheduledTime),isCancelled:u.isCancelled,...(from.estimatedTime?{estimatedDeparture:unix(from.estimatedTime)}:{}),...(to.estimatedTime?{estimatedArrival:unix(to.estimatedTime)}:{}),...(from.platform?{platform:from.platform}:{}),...(from.delayMinutes!==undefined?{delayMinutes:from.delayMinutes}:{})});
    asOf=Math.min(asOf,Date.parse(u.asOf));staleAt=Math.min(staleAt,Date.parse(u.validUntil));urgent||=u.isCancelled;
    if(u.summary)summaries.add(u.summary);
  }
  return {state:{legs,updatedAt:Math.floor(asOf/1000),...(summaries.size?{disruptionSummary:[...summaries].join(' / ')}:{})},asOf:Math.floor(asOf/1000),staleAt:Math.floor(staleAt/1000),urgent};
}
