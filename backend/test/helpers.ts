import { PGlite } from '@electric-sql/pglite';
import type {Database,Sql} from '../src/store.js';
import {migrate} from '../src/migrate.js';
import {publish,type Bundle} from '../src/ingestion.js';
import {featureNames} from '../src/contracts.js';
export const now=Date.parse('2026-09-26T00:00:00Z');
export const key=Buffer.alloc(32,7).toString('base64');
export async function database(){
  const pg=new PGlite();
  const query=(client:any)=>async(sql:string,params?:any[])=>sql.includes(';')&&!params?{rows:await client.exec(sql)}:client.query(sql,params);
  const db:Database={query:query(pg) as Sql['query'],transaction:fn=>pg.transaction(tx=>fn({query:query(tx) as Sql['query']})),close:()=>pg.close()};
  await migrate(db);return db;
}
export function bundle():Bundle {
  return {provider:'test-fixture',version:'1',licenseUrl:'https://example.com/test-only',displayText:'架空のテストデータ（実運行ではありません）',reviewedForPublication:true,asOf:new Date(now).toISOString(),validUntil:new Date(now+86400_000).toISOString(),master:{
    operators:[{id:'op',name:'テスト事業者',region:['kanto']}],lines:[{id:'line',operatorId:'op',name:'テスト路線',region:'kanto',symbol:null,color:null}],trainTypes:[{id:'local',name:'普通',shortName:'普',isPaidExpress:false,isShinkansen:false}],
    stations:['a','b','c'].map((id,i)=>({id,name:`テスト駅${id}`,reading:'てすと',prefecture:'東京都',region:'kanto' as const,lineIds:['line'],latitude:35+i/100,longitude:139}))
  },documents:[
    ...[10,20,30].map((minutes,i)=>({kind:'trainRun' as const,id:`run${i}:2026-09-26`,value:{id:`run${i}`,lineId:'line',trainTypeId:'local',destinationName:'テスト駅c',stops:['a','b','c'].map((stationId,j)=>({stationId,serviceDate:'2026-09-26',scheduledTime:new Date(now+(minutes+j*5)*60000).toISOString()}))}})),
    {kind:'capability',id:'line',value:{lineId:'line',asOf:new Date(now).toISOString(),features:Object.fromEntries(featureNames.map(f=>[f,['routeSearch','stopList','tripUpdates'].includes(f)?'available':'unavailable']))}}
  ]};
}
export async function seed(db:Database){await publish(db,bundle());}
