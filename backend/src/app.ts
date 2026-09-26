import Fastify, {LogController,type FastifyServerOptions} from 'fastify';
import swagger from '@fastify/swagger';
import compress from '@fastify/compress';
import { Type as T, type Static } from '@sinclair/typebox';
import { isDeepStrictEqual } from 'node:util';
import * as C from './contracts.js';
import { ApiError } from './errors.js';
import { hash,Vault } from './security.js';
import { Store,type Database,type Document } from './store.js';
import { RouteService,type RouteProvider } from './routes.js';
import {Estimate,EstimateSearch,type EstimateQuery,type NavitimeEstimateService} from './providers/navitime.js';

declare module 'fastify' {interface FastifyRequest {owner:string;}}
export interface AppOptions {trustProxy?:FastifyServerOptions['trustProxy'];db:Database;encryptionKey:string;providers?:RouteProvider[];navitime?:NavitimeEstimateService;now?:()=>number;logger?:boolean;rateLimit?:number;providerTimeoutMs?:number;}
export async function buildApp(options:AppOptions){
  const now=options.now??Date.now,store=new Store(options.db),vault=new Vault(options.encryptionKey);
  const routes=new RouteService(store,vault,options.providers??[],now,options.providerTimeoutMs);
  const app=Fastify({trustProxy:options.trustProxy??false,logger:options.logger?{redact:['req.headers.authorization','req.headers["idempotency-key"]']}:false,logController:new LogController({disableRequestLogging:true}),bodyLimit:65536,requestTimeout:10000,ajv:{customOptions:{removeAdditional:false,coerceTypes:'array'}}});
  app.decorateRequest('owner','');
  await app.register(swagger,{openapi:{info:{title:'Norikae Backend API',version:'0.1.0'},components:{securitySchemes:{bearerAuth:{type:'http',scheme:'bearer'}}}}});
  await app.register(compress);
  app.addHook('onRequest',async(req,reply)=>{
    reply.header('X-Request-Id',req.id).header('Cache-Control','no-store');
    if(!req.url.startsWith('/v1/'))return;
    await store.limit(`ip:${hash(req.ip)}`,options.rateLimit??120,now());
    if(req.routeOptions.url==='/v1/installations'||req.routeOptions.url==='/v1/auth/refresh'){
      await store.limit(`auth:${hash(req.ip)}`,20,now());return;
    }
    req.owner=vault.authenticate(req.headers.authorization?.replace(/^Bearer /,'')??'',now());
    if(!await store.exists(req.owner))throw new ApiError('AUTHENTICATION_REQUIRED');
    await store.limit(`device:${req.owner}`,options.rateLimit??60,now());
  });
  app.setErrorHandler((error,req,reply)=>{
    const e=error instanceof ApiError?error:new ApiError((error as any).validation||[400,413,415].includes((error as any).statusCode)?'INVALID_REQUEST':'INTERNAL_ERROR');
    if(e.status===429)reply.header('Retry-After','60');
    // No URLs, request bodies, raw provider errors or secrets in logs.
    req.log.warn({requestId:req.id,route:req.routeOptions.url,code:e.code},'API error');
    reply.code(e.status).send(e.body);
  });
  app.setNotFoundHandler((_req,reply)=>reply.code(404).send({error:{code:'NOT_FOUND',message:'API が見つかりません',retryable:false}}));
  const errors=Object.fromEntries([400,401,403,404,409,410,422,429,500,503].map(s=>[s,C.ErrorBody]));
  const schema=(response:any,extra:any={},publicRoute=false)=>({security:publicRoute?[]:[{bearerAuth:[]}],...extra,response:{200:response,...errors}});
  const meta=(docs:Document[]=[])=>({asOf:docs.length?new Date(Math.min(...docs.map(d=>new Date(d.as_of).getTime()))).toISOString():new Date(now()).toISOString(),partialResult:false,isStale:docs.some(d=>new Date(d.valid_until).getTime()<=now()),sources:[...new Set(docs.flatMap(d=>d.sources))],attributions:docs.flatMap(d=>d.attributions)});
  const wrapped=(data:unknown,docs:Document[]=[])=>({meta:meta(docs),data});
  const getDocument=async(kind:string,id:string)=>{const d=await store.document(kind,id);if(!d)throw new ApiError('FEATURE_UNAVAILABLE');return wrapped(d.value,[d]);};
  app.get('/healthz',{schema:schema(T.Object({status:T.Literal('ok')}),{},true)},async()=>({status:'ok'}));
  app.get('/readyz',{schema:schema(T.Object({status:T.Literal('ok')}),{},true)},async()=>{await options.db.query('SELECT 1');return {status:'ok'};});
  app.post('/v1/installations',{schema:schema(C.Tokens,{},true)},async()=>store.register(vault,now()));
  app.post<{Body:{refreshToken:string}}>('/v1/auth/refresh',{schema:schema(C.Tokens,{body:T.Object({refreshToken:T.String({minLength:32,maxLength:200})},{additionalProperties:false})},true)},async req=>store.refresh(req.body.refreshToken,vault,now()));
  app.post<{Body:C.SearchQuery}>('/v1/routes/search',{schema:schema(C.envelope(T.Array(C.Route)),{body:C.Search})},async req=>routes.search(req.body,req.owner));
  app.post<{Body:EstimateQuery}>('/v1/route-estimates/search',{schema:schema(C.envelope(T.Array(Estimate)),{body:EstimateSearch,description:'平均所要時間による参考経路。予定発着時刻・routeContext・Live Activity登録は提供しない。'})},async req=>{
    if(!options.navitime)throw new ApiError('FEATURE_UNAVAILABLE');return options.navitime.search(req.body);
  });
  app.post<{Body:{routeContext:string;direction:'previous'|'next'}}>('/v1/routes/adjacent',{schema:schema(C.envelope(C.Route),{body:T.Object({routeContext:T.String({minLength:1,maxLength:32000}),direction:T.Union([T.Literal('previous'),T.Literal('next')])},{additionalProperties:false})})},async req=>routes.adjacent(req.body.routeContext,req.body.direction,req.owner));
  app.get<{Params:{trainRunId:string};Querystring:{serviceDate:string}}>('/v1/train-runs/:trainRunId',{schema:schema(C.envelope(C.TrainRun),{params:T.Object({trainRunId:C.id}),querystring:T.Object({serviceDate:C.date},{additionalProperties:false})})},async req=>getDocument('trainRun',`${req.params.trainRunId}:${req.query.serviceDate}`));
  app.get<{Params:{stationId:string}}>('/v1/stations/:stationId/directions',{schema:schema(C.envelope(T.Array(C.Direction)),{params:T.Object({stationId:C.id})})},async req=>{
    if(!await store.entity('stations',req.params.stationId))throw new ApiError('STATION_NOT_FOUND');return getDocument('directions',req.params.stationId);
  });
  app.get<{Querystring:{stationId:string;lineId:string;directionId:string;dayType:string}}>('/v1/timetables',{schema:schema(C.envelope(C.Timetable),{querystring:T.Object({stationId:C.id,lineId:C.id,directionId:C.id,dayType:C.DayType},{additionalProperties:false})})},async req=>{
    if(!await store.entity('stations',req.query.stationId))throw new ApiError('STATION_NOT_FOUND');
    return getDocument('timetable',[req.query.stationId,req.query.lineId,req.query.directionId,req.query.dayType].join(':'));
  });
  const status=async(lineId:string)=>{
    const d=await store.document('status',lineId);
    if(!d||new Date(d.valid_until).getTime()<=now())return {value:{lineId,status:'unknown',summary:'運行情報を確認できません',asOf:d?new Date(d.as_of).toISOString():new Date(now()).toISOString()},docs:d?[d]:[],missing:true};
    return {value:d.value,docs:[d],missing:false};
  };
  app.get<{Querystring:{region:string}}>('/v1/operation-statuses',{schema:schema(C.envelope(T.Array(C.Status)),{querystring:T.Object({region:C.Region},{additionalProperties:false})})},async req=>{
    const lines=(await store.entities('lines')).filter(l=>l.region===req.query.region),statuses=await Promise.all(lines.map(l=>status(l.id)));
    const result=wrapped(statuses.map(s=>s.value),statuses.flatMap(s=>s.docs));result.meta.partialResult=statuses.some(s=>s.missing);return result;
  });
  app.get<{Params:{lineId:string}}>('/v1/operation-statuses/:lineId',{schema:schema(C.envelope(C.Status),{params:T.Object({lineId:C.id})})},async req=>{
    if(!await store.entity('lines',req.params.lineId))throw new ApiError('FEATURE_UNAVAILABLE');
    const s=await status(req.params.lineId),result=wrapped(s.value,s.docs);result.meta.partialResult=s.missing;return result;
  });
  app.get<{Querystring:{sinceVersion?:number}}>('/v1/master-data/changes',{schema:schema(C.envelope(C.Changes),{querystring:T.Object({sinceVersion:T.Optional(T.Integer({minimum:0,maximum:Number.MAX_SAFE_INTEGER}))},{additionalProperties:false})})},async req=>wrapped(await store.changes(req.query.sinceVersion??0)));
  app.get('/v1/master-data/snapshot',{schema:schema(C.envelope(C.MasterData))},async()=>wrapped(await store.snapshot()));
  app.get('/v1/capabilities',{schema:schema(C.envelope(C.Capabilities))},async()=>{
    const lines=await store.entities('lines'),docs=await store.documents('capability');
    const result=lines.map(line=>{
      const d=docs.find(d=>d.value.lineId===line.id);
      return d&&new Date(d.valid_until).getTime()>now()?d.value:{lineId:line.id,features:Object.fromEntries(C.featureNames.map(f=>[f,'unavailable'])),asOf:new Date(now()).toISOString()};
    });
    const regions=await Promise.all(['kanto','kansai'].map(async region=>{
      const d=await store.document('regionCapability',region);return d&&new Date(d.valid_until).getTime()>now()?d.value:{region,features:{viaStations:'unavailable',firstLastTrain:'unavailable'}};
    }));
    return wrapped({lines:result,regions},docs);
  });
  app.get('/v1/attributions',{schema:schema(C.envelope(T.Array(C.Attribution)))},async()=>{
    const rows=(await options.db.query('SELECT id,license_url,display_text FROM feed_states ORDER BY id')).rows;
    return wrapped([...rows.map(r=>({provider:r.id,displayText:r.display_text,licenseUrl:r.license_url})),...(options.navitime?[options.navitime.attribution]:[])]);
  });
  const activityHeaders=T.Object({'idempotency-key':T.String({minLength:1,maxLength:128})},{additionalProperties:true});
  const activitySchema=(body?:any)=>({security:[{bearerAuth:[]}],params:T.Object({activityId:C.id}),headers:activityHeaders,...(body?{body}:{}),response:{204:T.Null(),...errors}});
  app.put<{Params:{activityId:string};Body:C.RegistrationModel}>('/v1/live-activities/:activityId',{schema:activitySchema(C.Registration)},async(req,reply)=>{
    const context=routes.context(req.body.routeContext,req.owner);
    if(!isDeepStrictEqual(context.legs,req.body.legs))throw new ApiError('ROUTE_CONTEXT_MISMATCH');
    const expiry=Date.parse(req.body.expiresAt);
    if(expiry<=now()||expiry>Date.parse(context.arrivalTime)+3600_000||expiry>now()+86400_000)throw new ApiError('INVALID_REQUEST');
    for(const leg of req.body.legs){const cap=await store.document('capability',leg.lineId);if(!cap||new Date(cap.valid_until).getTime()<=now()||cap.value.features.tripUpdates!=='available')throw new ApiError('FEATURE_UNAVAILABLE');}
    await store.mutateActivity(req.owner,req.params.activityId,req.headers['idempotency-key'] as string,hash(JSON.stringify(['PUT',req.params.activityId,req.body])),now(),{token:vault.seal(req.body.pushToken,'push'),legs:req.body.legs,expiresAt:req.body.expiresAt});
    return reply.code(204).send();
  });
  app.delete<{Params:{activityId:string}}>('/v1/live-activities/:activityId',{schema:activitySchema()},async(req,reply)=>{
    await store.mutateActivity(req.owner,req.params.activityId,req.headers['idempotency-key'] as string,hash(JSON.stringify(['DELETE',req.params.activityId])),now());return reply.code(204).send();
  });
  app.get('/openapi.json',{schema:{hide:true}},async()=>app.swagger());
  await app.ready();return app;
}
