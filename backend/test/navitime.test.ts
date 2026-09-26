import {test} from 'node:test';
import assert from 'node:assert/strict';
import {RapidNavitimeClient,NavitimeEstimateService,japanTime,rapidClient} from '../src/providers/navitime.js';
import {ApiError} from '../src/errors.js';
import {database,seed,now,key} from './helpers.js';
import {Store} from '../src/store.js';
import {buildApp} from '../src/app.js';

const query={fromStationId:'a',toStationId:'c',searchType:'departure' as const,dateTime:'2026-09-26T23:30:00Z',useShinkansen:false,usePaidExpress:false,sort:'fastest' as const};
// Synthetic provider-shaped fixture. No real timetable or fare assertion.
const fixture=()=>({items:[{summary:{move:{time:12,transit_count:0,from_time:'2026-09-27T08:30:00+09:00',to_time:'2026-09-27T08:42:00+09:00',fare:{unit_0:200}}},sections:[{type:'point',name:'テスト出発',node_id:'external-a'},{type:'move',move:'local_train',time:12,line_name:'テスト線',from_time:'2026-09-27T08:30:00+09:00',to_time:'2026-09-27T08:42:00+09:00',transport:{links:[{is_timetable:'false'}]}},{type:'point',name:'テスト到着',node_id:'external-c'}]}]});
test('RapidAPI request mapping and average-time semantics',async()=>{
  let calls=0;
  const client=new RapidNavitimeClient({key:'test-secret',reserve:async()=>{calls++;},fetch:async(input,options)=>{
    const url=new URL(String(input));assert.equal(url.host,'navitime-route-totalnavi.p.rapidapi.com');assert.equal(url.pathname,'/route_transit');
    assert.equal(url.searchParams.get('start_time'),'2026-09-27T08:30:00');assert.equal(url.searchParams.get('via'),'[{"node":"external-b"}]');
    assert.equal(url.searchParams.get('order'),'transit');assert.ok(url.searchParams.get('unuse')!.includes('superexpress_train'));
    assert.equal(options!.redirect,'error');assert.equal(new Headers(options!.headers).get('X-RapidAPI-Key'),'test-secret');assert.ok(!String(input).includes('test-secret'));
    return Response.json(fixture());
  }});
  const result=await client.estimates({...query,viaStationIds:['b'],sort:'fewestTransfers'},['external-a','external-b','external-c']);
  assert.equal(calls,1);assert.equal(result.routes[0]!.timeBasis,'average');assert.equal(result.routes[0]!.fare.fareType,'estimated');
  const json=JSON.stringify(result);for(const forbidden of ['scheduledTime','departureTime','arrivalTime','routeContext','from_time','external-a','test-secret'])assert.ok(!json.includes(forbidden));
  assert.equal(japanTime('2026-09-27T08:30:00+09:00'),'2026-09-27T08:30:00');
});
test('upstream errors, response validation and no retry',async()=>{
  for(const status of [401,403,429,500]){
    let calls=0;const client=new RapidNavitimeClient({key:'secret',reserve:async()=>{},fetch:async()=>{calls++;return new Response('secret upstream text',{status});}});
    await assert.rejects(client.estimates(query,['a','c']),(e:any)=>e instanceof ApiError&&e.code===(status===429?'PROVIDER_QUOTA_EXCEEDED':'PROVIDER_UNAVAILABLE')&&!e.message.includes('secret'));assert.equal(calls,1);
  }
  const client=new RapidNavitimeClient({key:'secret',reserve:async()=>{},fetch:async()=>Response.json({items:[{summary:'invalid'}]})});
  await assert.rejects(client.estimates(query,['a','c']),{code:'PROVIDER_UNAVAILABLE'});
  const noResults=new RapidNavitimeClient({key:'secret',reserve:async()=>{},fetch:async()=>Response.json({items:[]})});
  await assert.rejects(noResults.estimates(query,['a','c']),{code:'ROUTE_NOT_FOUND'});
  const forbidden=new RapidNavitimeClient({key:'secret',reserve:async()=>{},fetch:async()=>{const data=fixture();data.items[0]!.sections[1]!.move='superexpress_train';return Response.json(data);}});
  await assert.rejects(forbidden.estimates(query,['a','c']),{code:'PROVIDER_UNAVAILABLE'});
});
test('station lookup returns candidates without silently selecting the first',async()=>{
  const client=new RapidNavitimeClient({key:'secret',reserve:async service=>{assert.equal(service,'transport');},fetch:async input=>{
    const url=new URL(String(input));assert.equal(url.host,'navitime-transport.p.rapidapi.com');assert.equal(url.searchParams.get('word'),'梅田');assert.equal(url.searchParams.get('type'),'station');
    return Response.json({items:[{id:'1',name:'梅田'},{id:'2',name:'大阪梅田'}]});
  }});
  assert.equal((await client.stations('梅田')).length,2);
});
test('HTTP estimate endpoint is authenticated, uses canonical mappings and cannot supply Live Activity context',async()=>{
  const db=await database();await seed(db);const store=new Store(db);let calls=0;
  const client=new RapidNavitimeClient({key:'secret',reserve:async()=>{},fetch:async()=>{calls++;return Response.json(fixture());}});
  const service=new NavitimeEstimateService(store,client,{provider:'navitime-rapidapi',displayText:'テスト用出典'},()=>now);
  const app=await buildApp({db,encryptionKey:key,navitime:service,now:()=>now});
  try{
    assert.equal((await app.inject({method:'POST',url:'/v1/route-estimates/search',payload:query})).statusCode,401);
    const access=(await app.inject({method:'POST',url:'/v1/installations'})).json().accessToken,headers={authorization:`Bearer ${access}`};
    assert.equal((await app.inject({method:'POST',url:'/v1/route-estimates/search',payload:query,headers})).statusCode,422);assert.equal(calls,0);
    for(const id of ['a','c'])await db.query("INSERT INTO provider_mappings(provider,entity,provider_id,canonical_id) VALUES('navitime','stations',$1,$2)",['external-'+id,id]);
    const response=await app.inject({method:'POST',url:'/v1/route-estimates/search',payload:query,headers});assert.equal(response.statusCode,200,response.body);assert.equal(response.json().data[0].timeBasis,'average');assert.equal(response.json().data[0].routeContext,undefined);
    assert.equal((await app.inject({method:'POST',url:'/v1/route-estimates/search',payload:{...query,searchType:'firstTrain'},headers})).statusCode,400);
    assert.equal((await app.inject({url:'/v1/attributions',headers})).json().data.at(-1).provider,'navitime-rapidapi');
    const ctx=JSON.stringify(await db.query('SELECT * FROM live_activity_sessions'));assert.ok(!ctx.includes('external-a'));
  }finally{await app.close();await db.close();}
});
test('persistent request budget denies before external fetch across client instances',async()=>{
  const db=await database(),store=new Store(db);
  try{
    await db.query("INSERT INTO provider_usage(provider,requests) VALUES('navitime-rapidapi:route',450)");
    for(let i=0;i<2;i++)await assert.rejects(rapidClient(store,{RAPIDAPI_KEY:'not-a-real-key'}).estimates(query,['a','c']),{code:'PROVIDER_QUOTA_EXCEEDED'});
    assert.equal((await db.query('SELECT requests FROM provider_usage')).rows[0]!.requests,450);
  }finally{await db.close();}
});
