import { Type as T, type Static } from '@sinclair/typebox';
import { Value } from '@sinclair/typebox/value';
import { randomUUID } from 'node:crypto';
import { ApiError } from '../errors.js';
import { Search, Fare, Warning, id } from '../contracts.js';
import type { Store } from '../store.js';

const hosts = {
  route: 'navitime-route-totalnavi.p.rapidapi.com',
  transport: 'navitime-transport.p.rapidapi.com'
} as const;
export type NavitimeService = keyof typeof hosts;
export const EstimateSearch = T.Object({
  ...Search.properties,
  searchType: T.Union([T.Literal('departure'), T.Literal('arrival')])
}, { additionalProperties: false });
export type EstimateQuery = Static<typeof EstimateSearch>;
export const Estimate = T.Object({
  id, fromStationId: id, toStationId: id, timeBasis: T.Literal('average'),
  durationMinutes: T.Number({ minimum: 0 }), transferCount: T.Integer({ minimum: 0 }),
  fare: Fare,
  segments: T.Array(T.Object({
    mode: id, durationMinutes: T.Number({ minimum: 0 }),
    lineName: T.Optional(id), fromName: T.Optional(id), toName: T.Optional(id)
  }), { minItems: 1 }),
  warnings: T.Array(Warning)
});
export type EstimateModel = Static<typeof Estimate>;
const Amount = T.Number({ minimum: 0 });
const RawMove = T.Object({ time: Amount, transit_count: T.Integer({ minimum: 0 }), fare: T.Optional(T.Record(T.String(), T.Unknown())) });
const RawPoint = T.Object({type:T.Literal('point'),name:T.Optional(T.String()),node_id:T.Optional(T.String())});
const RawSegment = T.Object({type:T.Literal('move'),move:T.String(),time:Amount,line_name:T.Optional(T.String()),transport:T.Optional(T.Object({name:T.Optional(T.String())}))});
const RawRoute = T.Object({summary:T.Object({move:RawMove}),sections:T.Array(T.Union([RawPoint,RawSegment]),{minItems:1})});
const RawStation = T.Object({id:T.String({minLength:1,maxLength:200}),name:T.String({minLength:1,maxLength:200}),coord:T.Optional(T.Object({lat:T.Number({minimum:-90,maximum:90}),lon:T.Number({minimum:-180,maximum:180})}))});
const rail = new Set(['local_train','rapid_train','superexpress_train','sleeper_ultraexpress','ultraexpress_train','express_train','semiexpress_train']);
const paid = new Set(['sleeper_ultraexpress','ultraexpress_train','express_train','semiexpress_train']);
export function japanTime(value:string){
  if(!Number.isFinite(Date.parse(value)))throw new ApiError('INVALID_REQUEST');
  return new Date(Date.parse(value)+9*3600_000).toISOString().slice(0,19);
}
export interface RapidOptions {
  key:string;
  reserve:(service:NavitimeService)=>Promise<void>;
  fetch?:typeof fetch;
  timeoutMs?:number;
}
/** Fixed HTTPS destinations; credentials never enter query strings or errors. No retries. */
export class RapidNavitimeClient {
  private fetcher:typeof fetch;
  constructor(private options:RapidOptions){
    if(!options.key.trim())throw new Error('RAPIDAPI_KEY is required');
    this.fetcher=options.fetch??fetch;
  }
  private async get(service:NavitimeService,path:string,params:URLSearchParams,signal?:AbortSignal):Promise<unknown>{
    const abort=AbortSignal.any([AbortSignal.timeout(this.options.timeoutMs??4500),...(signal?[signal]:[])]);
    abort.throwIfAborted();
    await this.options.reserve(service);
    try{
      const response=await this.fetcher(`https://${hosts[service]}${path}?${params}`,{
        method:'GET',headers:{'X-RapidAPI-Key':this.options.key,'X-RapidAPI-Host':hosts[service],Accept:'application/json'},
        redirect:'error',signal:abort
      });
      if(response.status===429){await response.body?.cancel();throw new ApiError('PROVIDER_QUOTA_EXCEEDED');}
      if(!response.ok){await response.body?.cancel();throw new ApiError('PROVIDER_UNAVAILABLE');}
      if(!response.body)throw new ApiError('PROVIDER_UNAVAILABLE');
      const reader=response.body.getReader(),chunks:Uint8Array[]=[];let bytes=0;
      try{while(true){const next=await reader.read();if(next.done)break;bytes+=next.value.byteLength;if(bytes>2_000_000){await reader.cancel();throw new ApiError('PROVIDER_UNAVAILABLE');}chunks.push(next.value);}}finally{reader.releaseLock();}
      return JSON.parse(Buffer.concat(chunks).toString('utf8'));
    }catch(error){if(error instanceof ApiError)throw error;throw new ApiError('PROVIDER_UNAVAILABLE');}
  }
  async stations(word:string,signal?:AbortSignal){
    if(!word.trim()||word.length>50)throw new ApiError('INVALID_REQUEST');
    const raw=await this.get('transport','/transport_node',new URLSearchParams({word,type:'station',datum:'wgs84',coord_unit:'degree'}),signal);
    const schema=T.Object({items:T.Array(RawStation)});
    if(!Value.Check(schema,raw))throw new ApiError('PROVIDER_UNAVAILABLE');
    // Provider IDs are exposed only to the operator CLI for deliberate canonical mapping.
    return raw.items.map(s=>({providerStationId:s.id,name:s.name,...(s.coord?{latitude:s.coord.lat,longitude:s.coord.lon}:{})}));
  }
  async estimates(query:EstimateQuery,stationIds:string[],signal?:AbortSignal){
    if(!Value.Check(EstimateSearch,query)||stationIds.length!==2+(query.viaStationIds?.length??0)||stationIds.some(id=>!id))throw new ApiError('INVALID_REQUEST');
    const excluded=['domestic_flight','shuttle_bus','highway_bus','local_bus','ferry'];
    if(!query.useShinkansen)excluded.push('superexpress_train');
    if(!query.usePaidExpress)excluded.push(...paid);
    const params=new URLSearchParams({start:stationIds[0]!,goal:stationIds.at(-1)!,
      [query.searchType==='arrival'?'goal_time':'start_time']:japanTime(query.dateTime),
      order:{fastest:'time',fewestTransfers:'transit',cheapest:'fare'}[query.sort]!,
      limit:String(query.maxResults??10),unuse:excluded.join('.'),datum:'wgs84',coord_unit:'degree'});
    if(stationIds.length>2)params.set('via',JSON.stringify(stationIds.slice(1,-1).map(node=>({node}))));
    const raw=await this.get('route','/route_transit',params,signal);
    if(!raw||typeof raw!=='object'||!Array.isArray((raw as any).items))throw new ApiError('PROVIDER_UNAVAILABLE');
    const items=(raw as {items:unknown[]}).items,results:EstimateModel[]=[];let dropped=0;
    for(const item of items){
      if(!Value.Check(RawRoute,item)){dropped++;continue;}
      const segments:EstimateModel['segments']=[];let invalid=false;
      for(const [i,section] of item.sections.entries()){
        if(section.type!=='move')continue;
        if(section.move!=='walk'&&!rail.has(section.move)||!query.useShinkansen&&section.move==='superexpress_train'||!query.usePaidExpress&&paid.has(section.move)){invalid=true;break;}
        const from=item.sections[i-1],to=item.sections[i+1];
        const lineName=section.line_name||section.transport?.name;
        segments.push({mode:section.move,durationMinutes:section.time,...(lineName?{lineName}:{}),...(from?.type==='point'&&from.name?{fromName:from.name}:{}),...(to?.type==='point'&&to.name?{toName:to.name}:{})});
      }
      if(invalid||!segments.length){dropped++;continue;}
      const amount=item.summary.move.fare?.unit_0;
      // unit_0 does not establish an IC/ticket distinction. Never label it as either.
      const fare=typeof amount==='number'&&Number.isInteger(amount)&&amount>=0?{fareType:'estimated' as const,estimatedTotal:amount}:{fareType:'unavailable' as const};
      results.push({id:randomUUID(),fromStationId:query.fromStationId,toStationId:query.toStationId,timeBasis:'average',durationMinutes:item.summary.move.time,transferCount:item.summary.move.transit_count,fare,segments,warnings:[{code:'AVERAGE_TIME',message:'平均所要時間による参考経路です。実際の発車・到着時刻や接続を保証しません'}]});
    }
    if(!results.length)throw new ApiError(dropped?'PROVIDER_UNAVAILABLE':'ROUTE_NOT_FOUND');
    return {routes:results.slice(0,query.maxResults??10),partialResult:dropped>0};
  }
}
export class NavitimeEstimateService {
  constructor(private store:Store,private client:RapidNavitimeClient,public attribution:{provider:string;displayText:string;licenseUrl?:string},private now:()=>number=Date.now){}
  async search(query:EstimateQuery){
    if(query.fromStationId===query.toStationId)throw new ApiError('INVALID_REQUEST');
    const ids=[];
    for(const id of [query.fromStationId,...query.viaStationIds??[],query.toStationId]){
      if(!await this.store.entity('stations',id))throw new ApiError('STATION_NOT_FOUND');
      const rows=(await this.store.db.query("SELECT provider_id FROM provider_mappings WHERE provider='navitime' AND entity='stations' AND canonical_id=$1",[id])).rows;
      if(rows.length!==1)throw new ApiError('FEATURE_UNAVAILABLE');ids.push(rows[0]!.provider_id as string);
    }
    const result=await this.client.estimates(query,ids);
    return {meta:{asOf:new Date(this.now()).toISOString(),isStale:false,partialResult:result.partialResult,sources:['navitime-rapidapi'],attributions:[this.attribution]},data:result.routes};
  }
}
export function rapidClient(store:Store,env:NodeJS.ProcessEnv=process.env){
  const key=env.RAPIDAPI_KEY;
  if(!key)throw new Error('RAPIDAPI_KEY is required');
  const budget=Number(env.NAVITIME_REQUEST_BUDGET??450);
  if(!Number.isInteger(budget)||budget<1||budget>500)throw new Error('NAVITIME_REQUEST_BUDGET must be 1..500');
  return new RapidNavitimeClient({key,reserve:async service=>{
    // Lifetime cap per service, shared by API and CLI. No automatic billing-cycle reset.
    const rows=(await store.db.query(`INSERT INTO provider_usage(provider,requests) VALUES($1,1)
      ON CONFLICT(provider) DO UPDATE SET requests=provider_usage.requests+1 WHERE provider_usage.requests<$2 RETURNING requests`,[`navitime-rapidapi:${service}`,budget])).rows;
    if(!rows.length)throw new ApiError('PROVIDER_QUOTA_EXCEEDED');
  }});
}
