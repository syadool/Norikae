import pg from 'pg';
import type { Database, Sql } from './store.js';
export function postgres(url:string):Database {
  const pool=new pg.Pool({connectionString:url,max:5,connectionTimeoutMillis:5000,statement_timeout:10000});
  return {
    query:((sql:string,params?:any[])=>pool.query(sql,params)) as Sql['query'],
    async transaction(fn,isolation='REPEATABLE READ'){const client=await pool.connect();try{await client.query(isolation==='READ COMMITTED'?'BEGIN ISOLATION LEVEL READ COMMITTED':'BEGIN ISOLATION LEVEL REPEATABLE READ');const result=await fn(client);await client.query('COMMIT');return result;}catch(e){await client.query('ROLLBACK');throw e;}finally{client.release();}},
    async close(){await pool.end();}
  };
}
