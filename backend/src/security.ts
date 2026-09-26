import { createCipheriv,createDecipheriv,createHash,randomBytes } from 'node:crypto';
import { ApiError } from './errors.js';
export const hash = (s:string) => createHash('sha256').update(s).digest('hex');
export const secret = () => randomBytes(32).toString('base64url');
// Authenticated encryption keeps the route context opaque as well as tamper-proof.
export class Vault {
  private key:Buffer;
  constructor(key:string){this.key=Buffer.from(key,'base64');if(this.key.length!==32)throw new Error('ENCRYPTION_KEY must be 32 base64-encoded bytes');}
  seal(value:unknown,purpose:string):string {
    const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',this.key,iv);
    cipher.setAAD(Buffer.from(purpose));
    const encrypted=Buffer.concat([cipher.update(JSON.stringify(value),'utf8'),cipher.final()]);
    return Buffer.concat([iv,cipher.getAuthTag(),encrypted]).toString('base64url');
  }
  open<T>(value:string,purpose:string):T {
    const b=Buffer.from(value,'base64url');if(b.length<29)throw new Error('Invalid sealed value');
    const decipher=createDecipheriv('aes-256-gcm',this.key,b.subarray(0,12));
    decipher.setAAD(Buffer.from(purpose));decipher.setAuthTag(b.subarray(12,28));
    return JSON.parse(Buffer.concat([decipher.update(b.subarray(28)),decipher.final()]).toString('utf8')) as T;
  }
  token(owner:string,now:number){return this.seal({owner,exp:now+900_000},'access');}
  authenticate(token:string,now:number):string {
    try{const p=this.open<{owner:string;exp:number}>(token,'access');if(p.exp<=now||!p.owner)throw new Error();return p.owner;}
    catch{throw new ApiError('AUTHENTICATION_REQUIRED');}
  }
}
