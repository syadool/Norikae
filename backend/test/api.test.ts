import {test} from 'node:test';
import assert from 'node:assert/strict';
import {buildApp} from '../src/app.js';
import {Store} from '../src/store.js';
import {LocalScheduleProvider} from '../src/providers/local.js';
import {monitorLegs} from '../src/contracts.js';
import * as C from '../src/contracts.js';
import {Value} from '@sinclair/typebox/value';
import {Type as T} from '@sinclair/typebox';
import {database,seed,now,key} from './helpers.js';

test('authentication, search, contract, adjacent, activity ownership and expiry',async()=>{
  const db=await database();await seed(db);let clock=now;
  const app=await buildApp({db,encryptionKey:key,now:()=>clock,providers:[new LocalScheduleProvider(new Store(db),()=>clock)],rateLimit:1000});
  try{
    assert.equal((await app.inject('/v1/capabilities')).statusCode,401);
    const registration=await app.inject({method:'POST',url:'/v1/installations'});assert.equal(registration.statusCode,200);
    const tokens=registration.json(),headers={authorization:`Bearer ${tokens.accessToken}`};
    assert.ok(registration.headers['x-request-id']);
    const request={fromStationId:'a',toStationId:'c',dateTime:new Date(now).toISOString(),searchType:'departure',useShinkansen:false,usePaidExpress:false,sort:'fastest'};
    const search=await app.inject({method:'POST',url:'/v1/routes/search',headers,payload:request});
    assert.equal(search.statusCode,200,search.body);assert.ok(Value.Check(C.envelope(T.Array(C.Route)),search.json()));const routes=search.json().data;assert.equal(routes.length,3);assert.equal(routes[0].fare.fareType,'unavailable');assert.equal(routes[0].legs[0].from.estimatedTime,undefined);
    for(const direction of ['next','previous']){
      const adjacent=await app.inject({method:'POST',url:'/v1/routes/adjacent',headers,payload:{routeContext:routes[1].routeContext,direction}});
      assert.equal(adjacent.statusCode,200,adjacent.body);assert.equal(adjacent.json().data.departureTime,routes[direction==='next'?2:0].departureTime);
    }
    const invalid=await app.inject({method:'POST',url:'/v1/routes/search',headers,payload:{...request,viaStationIds:['a','b','c','d']}});assert.equal(invalid.statusCode,400);
    assert.equal((await app.inject({method:'POST',url:'/v1/routes/search',headers,payload:{...request,secret:'unexpected'}})).statusCode,400);
    assert.equal((await app.inject({method:'POST',url:'/v1/routes/search',headers,payload:{...request,fromStationId:'missing'}})).json().error.code,'STATION_NOT_FOUND');
    assert.equal((await app.inject({method:'POST',url:'/v1/routes/search',headers,payload:{...request,searchType:'firstTrain'}})).json().error.code,'FEATURE_UNAVAILABLE');
    const activity={pushToken:'ab'.repeat(32),routeContext:routes[0].routeContext,legs:monitorLegs(routes[0]),expiresAt:new Date(now+3600_000).toISOString()};
    const put=()=>app.inject({method:'PUT',url:'/v1/live-activities/activity',headers:{...headers,'idempotency-key':'register'},payload:activity});
    assert.equal((await put()).statusCode,204);assert.equal((await put()).statusCode,204);
    const stored=(await db.query('SELECT * FROM live_activity_sessions')).rows;assert.equal(stored.length,1);assert.notEqual(stored[0]!.encrypted_token,activity.pushToken);
    const second=(await app.inject({method:'POST',url:'/v1/installations'})).json();
    const otherHeaders={authorization:`Bearer ${second.accessToken}`,'idempotency-key':'other'};
    assert.equal((await app.inject({method:'PUT',url:'/v1/live-activities/activity',headers:otherHeaders,payload:activity})).statusCode,409);
    assert.equal((await app.inject({method:'DELETE',url:'/v1/live-activities/activity',headers:otherHeaders})).statusCode,204);
    assert.equal((await db.query('SELECT * FROM live_activity_sessions')).rows.length,1);
    assert.equal((await app.inject({method:'PUT',url:'/v1/live-activities/activity',headers:{...headers,'idempotency-key':'register'},payload:{...activity,pushToken:'cd'.repeat(32)}})).statusCode,409);
    const status=(await app.inject({url:'/v1/operation-statuses/line',headers})).json();assert.equal(status.data.status,'unknown');assert.equal(status.meta.partialResult,true);
    const master=(await app.inject({url:'/v1/master-data/snapshot',headers})).json();assert.equal(master.data.stations.length,3);
    assert.equal((await app.inject({url:'/v1/master-data/changes?sinceVersion=999',headers})).statusCode,400);
    const capabilities=(await app.inject({url:'/v1/capabilities',headers})).json();assert.equal(capabilities.data.regions[0].features.firstLastTrain,'unavailable');assert.ok('stopList' in capabilities.data.lines[0].features);
    assert.equal((await app.inject({url:'/v1/train-runs/run0?serviceDate=2026-09-26',headers})).json().data.stops.length,3);
    const refresh=await app.inject({method:'POST',url:'/v1/auth/refresh',payload:{refreshToken:tokens.refreshToken}});assert.equal(refresh.statusCode,200);
    assert.equal((await app.inject({method:'POST',url:'/v1/auth/refresh',payload:{refreshToken:tokens.refreshToken}})).statusCode,401);
    clock+=31*60_000;
    const fresh=(await app.inject({method:'POST',url:'/v1/auth/refresh',payload:{refreshToken:refresh.json().refreshToken}})).json();
    assert.equal((await app.inject({method:'POST',url:'/v1/routes/adjacent',headers:{authorization:`Bearer ${fresh.accessToken}`},payload:{routeContext:routes[0].routeContext,direction:'next'}})).statusCode,410);
    const openapi=(await app.inject('/openapi.json')).json();assert.ok(openapi.paths['/v1/routes/search']);assert.ok(openapi.paths['/v1/live-activities/{activityId}']);
  }finally{await app.close();await db.close();}
});

test('rate limits and provider deadline are explicit errors',async()=>{
  const db=await database();await seed(db);
  const app=await buildApp({db,encryptionKey:key,now:()=>now,providerTimeoutMs:20,providers:[{id:'hung',supports:()=>true,search:()=>new Promise(()=>{})}],rateLimit:3});
  try{
    const token=(await app.inject({method:'POST',url:'/v1/installations'})).json().accessToken;const headers={authorization:`Bearer ${token}`};
    const response=await app.inject({method:'POST',url:'/v1/routes/search',headers,payload:{fromStationId:'a',toStationId:'b',dateTime:new Date(now).toISOString(),searchType:'departure',useShinkansen:false,usePaidExpress:false,sort:'fastest'}});
    assert.equal(response.statusCode,503);assert.equal(response.json().error.code,'PROVIDER_UNAVAILABLE');
    await app.inject({url:'/v1/capabilities',headers});assert.equal((await app.inject({url:'/v1/capabilities',headers})).statusCode,429);
  }finally{await app.close();await db.close();}
});
