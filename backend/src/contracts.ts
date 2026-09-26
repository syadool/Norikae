import { Type as T, FormatRegistry, type Static } from '@sinclair/typebox';
FormatRegistry.Set('date',v=>/^\d{4}-\d{2}-\d{2}$/.test(v)&&Number.isFinite(Date.parse(v))&&new Date(v).toISOString().slice(0,10)===v);
FormatRegistry.Set('date-time',v=>/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/.test(v)&&Number.isFinite(Date.parse(v))&&FormatRegistry.Get('date')!(v.slice(0,10)));
FormatRegistry.Set('uri',v=>{try{const u=new URL(v);return ['https:','http:'].includes(u.protocol);}catch{return false;}});

export const id = T.String({ minLength: 1, maxLength: 200 });
export const dateTime = T.String({ format: 'date-time', pattern: '(Z|[+-][0-9]{2}:[0-9]{2})$' });
export const date = T.String({ format: 'date' });
const integer = T.Integer({ minimum: 0 });
const text = T.String({ minLength: 1, maxLength: 2000 });
const opt = <S extends Parameters<typeof T.Optional>[0]>(s: S) => T.Optional(s);
export const Availability = T.Union(['available','partial','stale','unavailable'].map(x => T.Literal(x)));
export const Region = T.Union([T.Literal('kanto'), T.Literal('kansai')]);
export const Attribution = T.Object({ provider: id, displayText: text, licenseUrl: opt(T.String({ format: 'uri' })) });
export const Meta = T.Object({ asOf: dateTime, partialResult: T.Boolean(), isStale: T.Boolean(), sources: T.Array(id), attributions: T.Array(Attribution) });
export const Stop = T.Object({ stationId: id, scheduledTime: dateTime, serviceDate: date, estimatedTime: opt(dateTime), platform: opt(text) }, { additionalProperties: false });
export const MonitorLeg = T.Object({ lineId: id, trainRunId: opt(id), serviceDate: date, from: T.Object({stationId:id,scheduledTime:dateTime},{additionalProperties:false}), to:T.Object({stationId:id,scheduledTime:dateTime},{additionalProperties:false}) }, { additionalProperties: false });
export const StatusKind = T.Union(['normal','delayed','suspended','partial','other','unknown'].map(x=>T.Literal(x)));
export const Disruption = T.Object({ status:StatusKind, summary:text, delayMinutes:opt(integer) });
export const TrainLeg = T.Object({ type:T.Literal('train'), lineId:id, trainTypeId:id, trainRunId:opt(id), destinationName:text, from:Stop, to:Stop, stopCount:integer, boardingPosition:opt(T.Object({carNumber:T.Integer({minimum:1}),carCount:opt(T.Integer({minimum:1})),purpose:T.Union([T.Literal('transfer'),T.Literal('exit')]),note:opt(text)})), disruption:opt(Disruption) },{additionalProperties:false});
export const WalkLeg = T.Object({type:T.Literal('walk'),fromStationId:id,toStationId:id,durationMinutes:integer},{additionalProperties:false});
export const Leg = T.Union([TrainLeg,WalkLeg]);
export const Warning = T.Object({code:id,message:text,legIndex:opt(integer)});
export const Fare = T.Union([
  T.Object({fareType:T.Literal('unavailable')},{additionalProperties:false}),
  T.Object({fareType:T.Literal('estimated'),estimatedTotal:integer},{additionalProperties:false}),
  T.Object({fareType:T.Literal('exact'),icTotal:opt(integer),ticketTotal:opt(integer),expressTotal:opt(integer)},{additionalProperties:false,anyOf:[{required:['icTotal']},{required:['ticketTotal']}]})
]);
export const Route = T.Object({id,departureTime:dateTime,arrivalTime:dateTime,durationMinutes:integer,transferCount:integer,fare:Fare,legs:T.Array(Leg,{minItems:1,maxItems:20}),hasServiceDisruption:T.Boolean(),availability:Availability,warnings:T.Array(Warning),routeContext:T.String({minLength:1,maxLength:32000})});
export const Search = T.Object({fromStationId:id,toStationId:id,viaStationIds:opt(T.Array(id,{maxItems:3,uniqueItems:true})),dateTime,searchType:T.Union(['departure','arrival','firstTrain','lastTrain'].map(x=>T.Literal(x))),useShinkansen:T.Boolean(),usePaidExpress:T.Boolean(),sort:T.Union(['fastest','fewestTransfers','cheapest'].map(x=>T.Literal(x))),maxResults:opt(T.Integer({minimum:1,maximum:10}))},{additionalProperties:false});
export type SearchQuery = Static<typeof Search>;
export type RouteModel = Static<typeof Route>;
export type MonitoredLeg = Static<typeof MonitorLeg>;
export type AttributionModel = Static<typeof Attribution>;
export const Registration = T.Object({pushToken:T.String({pattern:'^(?:[0-9a-fA-F]{2}){16,256}$'}),routeContext:T.String({minLength:1,maxLength:32000}),legs:T.Array(MonitorLeg,{minItems:1,maxItems:20}),expiresAt:dateTime},{additionalProperties:false});
export type RegistrationModel = Static<typeof Registration>;
export const Station = T.Object({id,name:text,reading:text,prefecture:text,region:Region,lineIds:T.Array(id),stationCodes:opt(T.Array(id)),latitude:T.Number({minimum:-90,maximum:90}),longitude:T.Number({minimum:-180,maximum:180})});
export const Line = T.Object({id,operatorId:id,name:text,symbol:opt(T.Union([text,T.Null()])),displayCode:opt(text),color:opt(T.Union([T.String({pattern:'^#[0-9a-fA-F]{6}$'}),T.Null()])),region:Region});
export const Operator = T.Object({id,name:text,region:T.Array(Region)});
export const TrainType = T.Object({id,name:text,shortName:text,color:opt(text),isPaidExpress:T.Boolean(),isShinkansen:T.Boolean()});
export const TrainRun = T.Object({id,lineId:id,trainTypeId:id,destinationName:text,stops:T.Array(Stop)});
export const Direction = T.Object({lineId:id,directionId:id,directionName:text});
export const DayType = T.Union(['weekday','saturday','holiday'].map(x=>T.Literal(x)));
export const Timetable = T.Object({stationId:id,lineId:id,directionId:id,directionName:text,dayType:DayType,asOf:dateTime,departures:T.Array(T.Object({departureTime:dateTime,trainTypeId:id,destinationName:text,platform:opt(text),isOriginStation:T.Boolean(),trainRunId:id}))});
export const Status = T.Object({lineId:id,status:StatusKind,summary:text,asOf:dateTime,cause:opt(text),occurredAt:opt(dateTime),outlook:opt(text),hasTransferTransport:opt(T.Boolean())});
export const featureNames = ['routeSearch','timetable','stopList','fare','operationAlerts','tripUpdates','vehiclePositions','platform','boardingPosition'] as const;
export const Capability = T.Object({lineId:id,asOf:dateTime,features:T.Object(Object.fromEntries(featureNames.map(n=>[n,Availability])))});
export const Capabilities = T.Object({lines:T.Array(Capability),regions:T.Array(T.Object({region:Region,features:T.Object({viaStations:Availability,firstLastTrain:Availability})}))});
export const ErrorBody = T.Object({error:T.Object({code:id,message:text,retryable:T.Boolean()})});
export const Tokens = T.Object({installationId:id,accessToken:text,refreshToken:text,expiresIn:integer,tokenType:T.Literal('Bearer')});
export const MasterData = T.Object({version:integer,stations:T.Array(Station),lines:T.Array(Line),operators:T.Array(Operator),trainTypes:T.Array(TrainType)});
export const Changes = T.Object({version:integer,changes:T.Array(T.Object({version:integer,entity:T.Union(['stations','lines','operators','trainTypes'].map(x=>T.Literal(x))),id,operation:T.Union([T.Literal('upsert'),T.Literal('delete')]),value:opt(T.Union([Station,Line,Operator,TrainType])),replacedById:opt(id)}))});
export const envelope = <S extends Parameters<typeof T.Object>[0][string]>(s:S) => T.Object({meta:Meta,data:s});
export function monitorLegs(route:RouteModel):MonitoredLeg[] {
  return route.legs.filter(l=>l.type==='train').map(l=>({lineId:l.lineId,...(l.trainRunId?{trainRunId:l.trainRunId}:{}),serviceDate:l.from.serviceDate,from:{stationId:l.from.stationId,scheduledTime:l.from.scheduledTime},to:{stationId:l.to.stationId,scheduledTime:l.to.scheduledTime}}));
}
