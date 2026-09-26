import { Value } from '@sinclair/typebox/value';
import { Route,monitorLegs,type SearchQuery,type RouteModel,type MonitoredLeg,type AttributionModel } from './contracts.js';
import { ApiError } from './errors.js';
import { Vault,hash } from './security.js';
import {Store} from './store.js';

export interface ProviderResult {routes:RouteModel[];asOf:string;attributions:AttributionModel[];isStale?:boolean;partialResult?:boolean;}
export interface RouteProvider {
  id:string;
  supports(query:SearchQuery):boolean;
  search(query:SearchQuery,signal:AbortSignal):Promise<ProviderResult>;
  previous?(query:SearchQuery,departureTime:string,signal:AbortSignal):Promise<ProviderResult>;
}
interface Context {owner:string;exp:number;query:SearchQuery;departureTime:string;arrivalTime:string;legs:MonitoredLeg[];}
export class RouteService {
  constructor(private store:Store,private vault:Vault,private providers:RouteProvider[],private now:()=>number,private timeoutMs=4800){}
  context(token:string,owner:string){
    let c:Context;try{c=this.vault.open<Context>(token,'route');}catch{throw new ApiError('ROUTE_CONTEXT_MISMATCH');}
    if(c.owner!==owner)throw new ApiError('ROUTE_CONTEXT_MISMATCH');
    if(c.exp<=this.now())throw new ApiError('ROUTE_CONTEXT_EXPIRED');return c;
  }
  async search(query:SearchQuery,owner:string){
    if(query.fromStationId===query.toStationId)throw new ApiError('INVALID_REQUEST');
    for(const id of [query.fromStationId,...query.viaStationIds??[],query.toStationId])if(!await this.store.entity('stations',id))throw new ApiError('STATION_NOT_FOUND');
    const eligible=this.providers.filter(p=>p.supports(query));
    if(!eligible.length)throw new ApiError('FEATURE_UNAVAILABLE');
    const controller=new AbortController();
    let timer:ReturnType<typeof setTimeout>;
    const deadline=new Promise<never>((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(new ApiError('PROVIDER_UNAVAILABLE'));},this.timeoutMs);});
    const results=await Promise.allSettled(eligible.map(p=>Promise.race([p.search(query,controller.signal),deadline])));
    clearTimeout(timer!);
    const successes=results.flatMap((r,i)=>r.status==='fulfilled'?[{...r.value,source:eligible[i]!.id}]:[]);
    if(!successes.length){if(results.some(r=>r.status==='rejected'&&r.reason instanceof ApiError&&r.reason.code==='PROVIDER_QUOTA_EXCEEDED'))throw new ApiError('PROVIDER_QUOTA_EXCEEDED');throw new ApiError('PROVIDER_UNAVAILABLE');}
    const unique=new Map<string,RouteModel>();let rejected=0;
    for(const result of successes)for(const candidate of result.routes){
      const route=structuredClone(candidate);
      if(!Value.Check(Route,route)||!await this.valid(route,query)){rejected++;continue;}
      const key=hash(JSON.stringify(route.legs));
      if(!unique.has(key)){
        route.routeContext=this.vault.seal({owner,exp:this.now()+30*60_000,query,departureTime:route.departureTime,arrivalTime:route.arrivalTime,legs:monitorLegs(route)},'route');
        unique.set(key,route);
      }
    }
    if(!unique.size)throw new ApiError(rejected?'PROVIDER_UNAVAILABLE':'ROUTE_NOT_FOUND');
    return {meta:{asOf:successes.map(s=>s.asOf).sort((a,b)=>Date.parse(a)-Date.parse(b))[0]!,partialResult:rejected>0||successes.length<eligible.length||successes.some(s=>s.partialResult),isStale:successes.some(s=>s.isStale),sources:successes.map(s=>s.source),attributions:successes.flatMap(s=>s.attributions)},data:[...unique.values()].slice(0,query.maxResults??10)};
  }
  private async valid(route:RouteModel,q:SearchQuery){
    const start=Date.parse(route.departureTime),end=Date.parse(route.arrivalTime);
    if(!Number.isFinite(start)||!Number.isFinite(end)||end<start||route.durationMinutes!==Math.ceil((end-start)/60000))return false;
    if(q.searchType==='departure'&&start<Date.parse(q.dateTime)||q.searchType==='arrival'&&end>Date.parse(q.dateTime))return false;
    let station=q.fromStationId,previous=start,trains=0;const visited=[station];
    for(const leg of route.legs){
      if(leg.type==='walk'){if(leg.fromStationId!==station)return false;station=leg.toStationId;previous+=leg.durationMinutes*60_000;}
      else{
        const type=await this.store.entity('trainTypes',leg.trainTypeId);
        if(!type||!await this.store.entity('lines',leg.lineId)||(!q.useShinkansen&&type.isShinkansen)||(!q.usePaidExpress&&type.isPaidExpress)||leg.disruption?.status==='suspended')return false;
        if(leg.from.stationId!==station)return false;
        const dep=Date.parse(leg.from.scheduledTime),arr=Date.parse(leg.to.scheduledTime);
        if(route.legs[0]===leg&&dep!==start)return false;
        const transfer=trains?await this.store.document<{minutes:number}>('transfer',`${station}:${leg.lineId}`):undefined;
        // Unknown transfer minima cannot be certified; provider must supply a transfer rule.
        if(trains&&!transfer)return false;
        if(dep<previous+(transfer?.value.minutes??0)*60_000||arr<dep)return false;
        previous=arr;station=leg.to.stationId;trains++;
      }
      if(!await this.store.entity('stations',station))return false;visited.push(station);
    }
    let cursor=0;for(const via of q.viaStationIds??[]){const i=visited.indexOf(via,cursor);if(i<0)return false;cursor=i+1;}
    return station===q.toStationId&&previous===end&&route.transferCount===Math.max(0,trains-1);
  }
  async adjacent(token:string,direction:'previous'|'next',owner:string){
    const c=this.context(token,owner),pivot=Date.parse(c.departureTime);
    if(direction==='previous'){
      const capable=this.providers.filter(p=>p.previous&&p.supports(c.query));
      if(!capable.length)throw new ApiError('FEATURE_UNAVAILABLE');
      const adapted=capable.map(p=>({id:p.id,supports:()=>true,search:(q:SearchQuery,s:AbortSignal)=>p.previous!(q,c.departureTime,s)}));
      const service=new RouteService(this.store,this.vault,adapted,this.now,this.timeoutMs);
      const result=await service.search({...c.query,searchType:'departure',dateTime:new Date(pivot-86400_000).toISOString()},owner);
      const route=result.data.filter(r=>Date.parse(r.departureTime)<pivot).sort((a,b)=>Date.parse(b.departureTime)-Date.parse(a.departureTime))[0];
      if(!route)throw new ApiError('ROUTE_NOT_FOUND');
      route.warnings.push({code:'ADJACENT_APPROXIMATE',message:'対応データの範囲で直前の経路を再検索しました'});
      return {...result,data:route};
    }
    const result=await this.search({...c.query,searchType:'departure',dateTime:new Date(pivot+1000).toISOString()},owner);
    const route=result.data.sort((a,b)=>Date.parse(a.departureTime)-Date.parse(b.departureTime))[0]!;
    route.warnings.push({code:'ADJACENT_APPROXIMATE',message:'直後の経路を再検索しました。厳密な隣接候補ではない場合があります'});
    return {...result,data:route};
  }
}
