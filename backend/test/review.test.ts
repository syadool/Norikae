import {test} from 'node:test';
import assert from 'node:assert/strict';
import {connect,createServer,type ClientHttp2Session} from 'node:http2';
import {generateKeyPairSync} from 'node:crypto';
import {once} from 'node:events';
import {database,seed,bundle,now,key} from './helpers.js';
import {Store,type IsolationLevel} from '../src/store.js';
import {Vault} from '../src/security.js';
import {ApnsAdapter,monitor,type LiveUpdate} from '../src/live.js';
import {publish} from '../src/ingestion.js';
import {buildApp} from '../src/app.js';

test('publication preserves realtime but replaces schedule documents',async()=>{
  const db=await database();
  try{
    await seed(db);
    await db.query("INSERT INTO transport_documents(kind,id,value,as_of,valid_until,sources,attributions) SELECT 'tripUpdate',id,value,as_of,valid_until,sources,attributions FROM transport_documents WHERE kind='trainRun'");
    const next=bundle();next.documents=[];await publish(db,next);
    assert.equal((await new Store(db).documents('tripUpdate')).length,3);
    assert.equal((await new Store(db).documents('trainRun')).length,0);
  }finally{await db.close();}
});

test('monitor isolates resolver, payload, decryption and commit failures and continues',async()=>{
  const db=await database(),store=new Store(db),vault=new Vault(key);
  const original=db.transaction.bind(db),levels:(IsolationLevel|undefined)[]=[];
  let failCommit=false;
  db.transaction=(fn,level)=>{levels.push(level);return original(async sql=>{const result=await fn(sql);if(failCommit&&level==='READ COMMITTED'){failCommit=false;throw new Error('commit failed');}return result;},level);};
  try{
    const auth=await store.register(vault,now);
    const legs=[{lineId:'line',serviceDate:'2026-09-26',from:{stationId:'a',scheduledTime:new Date(now).toISOString()},to:{stationId:'b',scheduledTime:new Date(now+600_000).toISOString()}}];
    for(const id of ['resolver','payload','decrypt','commit','healthy'])await store.mutateActivity(auth.installationId,id,id,id,now,{token:id==='decrypt'?'bad':vault.seal('token','push'),legs,expiresAt:new Date(now+3600_000).toISOString()});
    assert.deepEqual(levels,Array(5).fill('READ COMMITTED'));
    const seconds=now/1000,update:LiveUpdate={state:{legs:[{index:0,scheduledDeparture:seconds,scheduledArrival:seconds+600,isCancelled:false}],updatedAt:seconds},asOf:seconds,staleAt:seconds+300,urgent:false};
    const outcomes=await monitor(store,vault,{send:async()=> 'sent'},async session=>{
      if(session.activity_id==='resolver')throw new Error('resolver failed');
      if(session.activity_id==='payload')return {...update,state:{...update.state,disruptionSummary:'x'.repeat(5000)}};
      if(session.activity_id==='commit')failCommit=true;
      return update;
    },now);
    assert.deepEqual(outcomes,{sent:1,retry:4,skipped:0,removed:0});
    const rows=(await db.query('SELECT activity_id FROM live_activity_sessions WHERE last_sent_at IS NOT NULL')).rows;
    assert.deepEqual(rows.map(r=>r.activity_id),['healthy']);
  }finally{await db.close();}
});

test('APNs caches JWT, reuses HTTP/2, refreshes after 30 minutes and reconnects after GOAWAY',async()=>{
  const server=createServer(),headers:string[]=[],clients:ClientHttp2Session[]=[];
  server.on('stream',(stream,h)=>{headers.push(String(h.authorization));stream.respond({':status':200});stream.end();});
  server.listen(0,'127.0.0.1');await once(server,'listening');
  const port=(server.address() as {port:number}).port;let clock=now;
  const privateKey=generateKeyPairSync('ec',{namedCurve:'prime256v1'}).privateKey.export({type:'pkcs8',format:'pem'}).toString();
  const push=new ApnsAdapter({teamId:'team',keyId:'key',privateKey,bundleId:'test',environment:'sandbox'},{now:()=>clock,connect:(()=>{const client=connect(`http://127.0.0.1:${port}`);clients.push(client);return client;}) as typeof connect});
  try{
    assert.equal(await push.send('token',{},false),'sent');clock+=29*60_000;
    assert.equal(await push.send('token',{},false),'sent');assert.equal(headers[0],headers[1]);assert.equal(clients.length,1);
    clock+=60_000;await push.send('token',{},true);assert.notEqual(headers[1],headers[2]);assert.equal(clients.length,1);
    clients[0]!.emit('goaway',0,0,Buffer.alloc(0));
    assert.equal(await push.send('token',{},false),'sent');assert.equal(clients.length,2);assert.equal(headers[2],headers[3]);
  }finally{push.close();for(const client of clients)client.destroy();await new Promise<void>(resolve=>server.close(()=>resolve()));}
});

test('rate limits distinguish forwarded clients only behind explicitly trusted proxies',async()=>{
  for(const trusted of [false,true]){
    const db=await database(),app=await buildApp({db,encryptionKey:key,now:()=>now,rateLimit:1,...(trusted?{trustProxy:['127.0.0.1']}:{})});
    try{
      const request=(ip:string,remoteAddress='127.0.0.1')=>app.inject({method:'POST',url:'/v1/installations',remoteAddress,headers:{'x-forwarded-for':ip}});
      assert.equal((await request('192.0.2.1')).statusCode,200);
      assert.equal((await request('192.0.2.2')).statusCode,trusted?200:429);
      assert.equal((await request('192.0.2.3','198.51.100.1')).statusCode,200);
      assert.equal((await request('192.0.2.4','198.51.100.1')).statusCode,429);
    }finally{await app.close();await db.close();}
  }
});
