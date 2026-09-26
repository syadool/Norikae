export const errors = {
  INVALID_REQUEST:[400,false,'入力内容を確認してください'], STATION_NOT_FOUND:[404,false,'指定された駅が見つかりません'],
  ROUTE_NOT_FOUND:[404,false,'条件に合う経路が見つかりません'], FEATURE_UNAVAILABLE:[422,false,'この区間・条件には対応していません'],
  ROUTE_CONTEXT_EXPIRED:[410,false,'経路の有効期限が切れました'], ROUTE_CONTEXT_MISMATCH:[409,false,'経路の登録内容が一致しません'],
  AUTHENTICATION_REQUIRED:[401,true,'認証情報を更新してください'], ATTESTATION_FAILED:[403,false,'通信できませんでした'],
  RATE_LIMITED:[429,true,'しばらく待ってから再試行してください'], PROVIDER_QUOTA_EXCEEDED:[503,true,'データ提供元の利用上限に達しました'],
  PROVIDER_UNAVAILABLE:[503,true,'交通情報を取得できませんでした'], INTERNAL_ERROR:[500,true,'処理に失敗しました']
} as const;
export type ErrorCode = keyof typeof errors;
export class ApiError extends Error {
  constructor(public code:ErrorCode) {super(errors[code][2]);}
  get status(){return errors[this.code][0];}
  get body(){return {error:{code:this.code,message:this.message,retryable:errors[this.code][1]}};}
}
