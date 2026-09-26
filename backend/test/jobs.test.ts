import {test} from 'node:test';
import assert from 'node:assert/strict';
import {database,seed,bundle,now,key} from './helpers.js';
import {publish} from '../src/ingestion.js';
import {Store} from '../src/store.js';
import {Vault,hash} from '../src/security.js';
import {monitor,payload,type LiveUpdate} from '../src/live.js';
import {ingestRealtime,resolveUpdate} from '../src/realtime.js';

test('atomic feed publication, references, monotonic times and master deletions',async()=>{
  const db=await database();await seed(db);const store=new Store(db);
  try{
    const invalid=bundle();invalid.master.lines[0]!.operatorId='missing';
    await assert.rejects(publish(db,invalid),/Unmapped/);assert.equal((await store.snapshot()).version,1);
    const malformed=bundle();(malformed.documents[0]!.value as any).stops[1].scheduledTime='2026-09-25T23:00:00Z';
    await assert.rejects(publish(db,malformed),/Non-monotonic/);
    const deletion=bundle();deletion.master.stations=deletion.master.stations.filter(s=>s.id!=='b');deletion.documents=[];deletion.deletions=[{entity:'stations',id:'b',replacedById:'a'}];
    await publish(db,deletion);const diff=await store.changes(1);
    assert.equal(diff.version,2);assert.equal(diff.changes.find(c=>c.operation==='delete')?.replacedById,'a');
  }finally{await db.close();}
});

test('opaque context purpose separation, tampering and expiry',()=>{
  const vault=new Vault(key),sealed=vault.seal({secret:'value'},'route');
  assert.ok(!sealed.includes('value'));assert.deepEqual(vault.open(sealed,'route'),{secret:'value'});
  assert.throws(()=>vault.open(sealed,'push'));assert.throws(()=>vault.open('x'+sealed.slice(1),'route'));
  const access=vault.token('owner',now);assert.equal(vault.authenticate(access,now),'owner');assert.throws(()=>vault.authenticate(access,now+900_000));
});

test('Live Activity end-to-end: deduplicate, coalesce, urgent change, retry and cleanup',async()=>{
  const db=await database(),store=new Store(db),vault=new Vault(key);
  try{
    const auth=await store.register(vault,now),token='aa'.repeat(32);
    const legs=[{lineId:'line',serviceDate:'2026-09-26',from:{stationId:'a',scheduledTime:new Date(now).toISOString()},to:{stationId:'b',scheduledTime:new Date(now+600_000).toISOString()}}];
    await store.mutateActivity(auth.installationId,'act','k',hash('k'),now,{token:vault.seal(token,'push'),legs,expiresAt:new Date(now+3600_000).toISOString()});
    const seconds=now/1000;
    const update:LiveUpdate={state:{legs:[{index:0,scheduledDeparture:seconds,scheduledArrival:seconds+600,estimatedArrival:seconds+660,isCancelled:false}],updatedAt:seconds},asOf:seconds,staleAt:seconds+300,urgent:false};
    let calls=0;let outcome:'sent'|'invalid-token'|'retry'='sent';
    const push={async send(received:string,body:any){assert.equal(received,token);assert.equal(body.aps['content-state'].legs.length,1);assert.equal(body.aps.alert,undefined);calls++;return outcome;}};
    const resolve=async()=>update;
    assert.equal((await monitor(store,vault,push,resolve,now)).sent,1);
    update.state.updatedAt++;assert.equal((await monitor(store,vault,push,resolve,now+1000)).skipped,1);assert.equal(calls,1);
    update.state.legs[0]!.estimatedArrival!+=60;
    assert.equal((await monitor(store,vault,push,resolve,now+2000)).skipped,1);
    update.urgent=true;assert.equal((await monitor(store,vault,push,resolve,now+3000)).sent,1);
    update.state.legs[0]!.isCancelled=true;outcome='retry';assert.equal((await monitor(store,vault,push,resolve,now+4000)).retry,1);
    outcome='invalid-token';assert.equal((await monitor(store,vault,push,resolve,now+5000)).removed,1);
    assert.equal((await db.query('SELECT * FROM live_activity_sessions')).rows.length,0);
    assert.throws(()=>payload({...update,state:{...update.state,disruptionSummary:'長'.repeat(4000)}}),/4KB/);
    await store.cleanup(now+31*86400_000);assert.equal((await db.query('SELECT * FROM installations')).rows.length,0);
  }finally{await db.close();}
});

test('realtime imports reject unknown trips and ignore older updates',async()=>{
  const db=await database();await seed(db);const store=new Store(db);
  try{
    const run=(await store.document('trainRun','run0:2026-09-26'))!.value;
    const update={trainRunId:'run0',serviceDate:'2026-09-26',asOf:new Date(now).toISOString(),validUntil:new Date(now+300_000).toISOString(),isCancelled:false,stops:run.stops.map((s:any)=>({...s,estimatedTime:new Date(Date.parse(s.scheduledTime)+60_000).toISOString()}))};
    await ingestRealtime(store,'test-fixture',[update],now);
    await assert.rejects(ingestRealtime(store,'test-fixture',[{...update,trainRunId:'missing'}],now),/Unmapped/);
    await ingestRealtime(store,'test-fixture',[{...update,asOf:new Date(now-60000).toISOString(),isCancelled:true}],now);
    assert.equal((await store.document('tripUpdate','run0:2026-09-26'))!.value.isCancelled,false);
    const session:any={legs:[{lineId:'line',trainRunId:'run0',serviceDate:'2026-09-26',from:run.stops[0],to:run.stops[2]}]};
    const resolved=await resolveUpdate(store,session,now);assert.equal(resolved!.state.legs[0]!.estimatedArrival,Date.parse(run.stops[2].scheduledTime)/1000+60);
    assert.equal(await resolveUpdate(store,session,now+300_000),undefined);
  }finally{await db.close();}
});
