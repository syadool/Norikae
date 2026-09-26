import {readFile} from 'node:fs/promises';
import {Value} from '@sinclair/typebox/value';
import {Type as T} from '@sinclair/typebox';
import {postgres} from '../src/postgres.js';
import {Store} from '../src/store.js';
import {ApiError} from '../src/errors.js';
import {Station,id} from '../src/contracts.js';
import {EstimateSearch,rapidClient} from '../src/providers/navitime.js';

const url=process.env.DATABASE_URL;
if(!url)throw new Error('DATABASE_URL required; run from backend with .env configured');
const db=postgres(url),store=new Store(db);
try{
  const [command,...args]=process.argv.slice(2);
  if(command==='stations'&&args.length===1){
    console.log(JSON.stringify(await rapidClient(store).stations(args[0]!),null,2));
  }else if(command==='probe'&&args.length===3){
    const [from,to,dateTime]=args as [string,string,string];
    const query={fromStationId:'evaluation-origin',toStationId:'evaluation-destination',dateTime,searchType:'departure' as const,useShinkansen:false,usePaidExpress:false,sort:'fastest' as const,maxResults:3};
    if(!Value.Check(EstimateSearch,query))throw new ApiError('INVALID_REQUEST');
    const result=await rapidClient(store).estimates(query,[from,to]);
    console.log(JSON.stringify({notice:'平均時間の接続確認。駅IDはCLI入力専用。実ダイヤの検証結果ではありません。',...result},null,2));
  }else if(command==='usage'&&args.length===0){
    console.log(JSON.stringify((await db.query("SELECT provider,requests FROM provider_usage WHERE provider LIKE 'navitime-rapidapi:%' ORDER BY provider")).rows,null,2));
  }else if(command==='import-stations'&&args.length===1){
    const stations:unknown=JSON.parse(await readFile(args[0]!,'utf8'));
    const schema=T.Array(T.Object({station:Station,providerStationId:id},{additionalProperties:false}),{minItems:1,maxItems:100});
    if(!Value.Check(schema,stations))throw new ApiError('INVALID_REQUEST');
    if(new Set(stations.map(s=>s.station.id)).size!==stations.length||new Set(stations.map(s=>s.providerStationId)).size!==stations.length)throw new ApiError('INVALID_REQUEST');
    await db.transaction(async sql=>{
      await sql.query('LOCK TABLE master_versions IN EXCLUSIVE MODE');
      const version=Number((await sql.query('SELECT max(version) AS v FROM master_versions')).rows[0]?.v??0)+1;
      await sql.query('INSERT INTO master_versions(version,published_at) VALUES($1,$2)',[version,new Date()]);
      for(const entry of stations){
        for(const lineId of entry.station.lineIds)if(!(await sql.query("SELECT id FROM master_entities WHERE entity='lines' AND id=$1",[lineId])).rows.length)throw new ApiError('INVALID_REQUEST');
        const conflicts=(await sql.query("SELECT * FROM provider_mappings WHERE provider='navitime' AND entity='stations' AND (canonical_id=$1 OR provider_id=$2)",[entry.station.id,entry.providerStationId])).rows;
        if(conflicts.some(r=>r.canonical_id!==entry.station.id||r.provider_id!==entry.providerStationId))throw new ApiError('ROUTE_CONTEXT_MISMATCH');
        await sql.query("INSERT INTO master_entities(entity,id,value) VALUES('stations',$1,$2) ON CONFLICT(entity,id) DO UPDATE SET value=EXCLUDED.value",[entry.station.id,JSON.stringify(entry.station)]);
        await sql.query("INSERT INTO master_changes(version,entity,id,operation,value) VALUES($1,'stations',$2,'upsert',$3)",[version,entry.station.id,JSON.stringify(entry.station)]);
        await sql.query("INSERT INTO provider_mappings(provider,entity,provider_id,canonical_id) VALUES('navitime','stations',$1,$2) ON CONFLICT DO NOTHING",[entry.providerStationId,entry.station.id]);
      }
    });
    console.log(`Imported ${stations.length} reviewed stations`);
  }else throw new Error('Usage: navitime stations <name> | probe <provider-from-id> <provider-to-id> <ISO-datetime> | usage | import-stations <reviewed.json>');
}catch(error){
  // CLI never prints upstream errors, responses, URLs or credential-bearing stacks.
  console.error(error instanceof ApiError?`${error.code}: ${error.message}`:'設定・入力を確認してください。DATABASE_URL、RAPIDAPI_KEY、マイグレーション、コマンド引数が必要です。');
  process.exitCode=1;
}finally{await db.close();}
