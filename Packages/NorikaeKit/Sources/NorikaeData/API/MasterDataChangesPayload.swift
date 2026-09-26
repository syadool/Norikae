import Domain
import Foundation

/// `GET /v1/master-data/changes` の `data`（openapi.json）
///
/// ```
/// { version, changes: [{ version, entity: stations|lines|operators|trainTypes, id, operation: upsert|delete, value?, replacedById? }] }
/// ```
/// を、アプリで扱う `MasterDataChanges` に変換する。
struct MasterDataChangesPayload: Decodable, Sendable {
    struct Change: Decodable, Sendable {
        enum Entity: String, Decodable, Sendable {
            case stations, lines, operators, trainTypes
        }

        enum Operation: String, Decodable, Sendable {
            case upsert, delete
        }

        enum Value: Sendable {
            case station(Station)
            case line(Line)
            case `operator`(Operator)
            case trainType(TrainType)
        }

        var entity: Entity
        var id: String
        var operation: Operation
        var value: Value?
        var replacedById: String?

        private enum CodingKeys: String, CodingKey {
            case entity, id, operation, value, replacedById
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entity = try container.decode(Entity.self, forKey: .entity)
            id = try container.decode(String.self, forKey: .id)
            operation = try container.decode(Operation.self, forKey: .operation)
            replacedById = try container.decodeIfPresent(String.self, forKey: .replacedById)
            guard container.contains(.value), try !container.decodeNil(forKey: .value) else {
                value = nil
                return
            }
            switch entity {
            case .stations: value = .station(try container.decode(Station.self, forKey: .value))
            case .lines: value = .line(try container.decode(Line.self, forKey: .value))
            case .operators: value = .operator(try container.decode(Operator.self, forKey: .value))
            case .trainTypes: value = .trainType(try container.decode(TrainType.self, forKey: .value))
            }
        }
    }

    var version: Int
    var changes: [Change]

    /// アプリで扱う形に変換する
    var asChanges: MasterDataChanges {
        var result = MasterDataChanges(version: version, stations: [], lines: [], operators: [], trainTypes: [], removed: [])
        for change in changes {
            switch (change.operation, change.value) {
            case (.upsert, .station(let station)?): result.stations?.append(station)
            case (.upsert, .line(let line)?): result.lines?.append(line)
            case (.upsert, .operator(let op)?): result.operators?.append(op)
            case (.upsert, .trainType(let type)?): result.trainTypes?.append(type)
            case (.delete, _):
                let kind: MasterDataChanges.Removal.Kind
                switch change.entity {
                case .stations: kind = .station
                case .lines: kind = .line
                case .operators: kind = .operator
                case .trainTypes: kind = .trainType
                }
                result.removed?.append(.init(kind: kind, id: change.id, replacedById: change.replacedById))
            case (.upsert, nil):
                // 値のない upsert は読み飛ばす（推測で埋めない）
                continue
            }
        }
        return result
    }
}
