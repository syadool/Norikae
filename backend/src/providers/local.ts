import { randomUUID } from 'node:crypto';
import type { Static } from '@sinclair/typebox';
import { TrainRun,type RouteModel,type SearchQuery } from '../contracts.js';
import type { RouteProvider } from '../routes.js';
import {Store} from '../store.js';

/** Searches published full-stop schedules. Direct trains only; never invents transfers. */
export class LocalScheduleProvider implements RouteProvider {
  id='local-schedule';
  constructor(private store:Store,private now:()=>number=Date.now){}
  supports(q:SearchQuery){return !(q.viaStationIds?.length)&&['departure','arrival'].includes(q.searchType);}
  async search(q:SearchQuery,signal:AbortSignal){
    const docs=await this.store.documents('trainRun');const routes:RouteModel[]=[];
    const sources=new Set<string>();const attrs=new Map();let asOf=this.now();
    for(const doc of docs){
      signal.throwIfAborted();if(new Date(doc.valid_until).getTime()<=this.now())continue;
      const run=doc.value as Static<typeof TrainRun>;
      const fromIndex=run.stops.findIndex(s=>s.stationId===q.fromStationId),toIndex=run.stops.findIndex((s,i)=>i>fromIndex&&s.stationId===q.toStationId);
      if(fromIndex<0||toIndex<0)continue;
      const from=run.stops[fromIndex]!,to=run.stops[toIndex]!;
      const dep=Date.parse(from.scheduledTime),arr=Date.parse(to.scheduledTime),pivot=Date.parse(q.dateTime);
      if(q.searchType==='departure'?(dep<pivot||dep>pivot+86400_000):(arr>pivot||arr<pivot-86400_000))continue;
      const type=await this.store.entity('trainTypes',run.trainTypeId);
      if(!type||!q.useShinkansen&&type.isShinkansen||!q.usePaidExpress&&type.isPaidExpress)continue;
      const status=await this.store.document('status',run.lineId);
      const disruption=status&&new Date(status.valid_until).getTime()>this.now()?status.value:undefined;
      if(disruption?.status==='suspended')continue;
      asOf=Math.min(asOf,new Date(doc.as_of).getTime());doc.sources.forEach(s=>sources.add(s));doc.attributions.forEach(a=>attrs.set(JSON.stringify(a),a));
      routes.push({id:randomUUID(),departureTime:from.scheduledTime,arrivalTime:to.scheduledTime,durationMinutes:Math.ceil((arr-dep)/60000),transferCount:0,fare:{fareType:'unavailable'},legs:[{type:'train',lineId:run.lineId,trainTypeId:run.trainTypeId,trainRunId:run.id,destinationName:run.destinationName,from,to,stopCount:toIndex-fromIndex-1,...(disruption?{disruption:{status:disruption.status,summary:disruption.summary}}:{})}],hasServiceDisruption:!!disruption&&disruption.status!=='normal'&&disruption.status!=='unknown',availability:'partial',warnings:[{code:'PARTIAL_DATA',message:'運賃・リアルタイム予測は提供されていません'}],routeContext:'pending'});
    }
    routes.sort((a,b)=>q.searchType==='arrival'?Date.parse(b.arrivalTime)-Date.parse(a.arrivalTime):Date.parse(a.departureTime)-Date.parse(b.departureTime));
    return {routes:routes.slice(0,10),asOf:new Date(asOf).toISOString(),attributions:[...attrs.values()],partialResult:true};
  }
  async previous(q:SearchQuery,departureTime:string,signal:AbortSignal){
    // Enumerate all direct services in the preceding service window, then choose by departure.
    const pivot=Date.parse(departureTime);
    const docs=await this.store.documents('trainRun');
    const departures=docs.flatMap(d=>(d.value as Static<typeof TrainRun>).stops.filter(s=>s.stationId===q.fromStationId).map(s=>Date.parse(s.scheduledTime))).filter(t=>t<pivot&&t>=pivot-86400_000).sort((a,b)=>b-a);
    for(const departure of departures){const result=await this.search({...q,searchType:'departure',dateTime:new Date(departure).toISOString()},signal);const routes=result.routes.filter(r=>Date.parse(r.departureTime)<pivot);if(routes.length)return {...result,routes};}
    return {routes:[],asOf:new Date(this.now()).toISOString(),attributions:[]};
  }
}
