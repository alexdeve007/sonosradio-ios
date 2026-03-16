import Foundation
import SwiftData

@Model
final class GroupPreset {
    var id: UUID
    var name: String
    var coordinatorId: String
    var memberIds: [String]
    var dateCreated: Date

    init(name: String, coordinatorId: String, memberIds: [String]) {
        self.id = UUID()
        self.name = name
        self.coordinatorId = coordinatorId
        self.memberIds = memberIds
        self.dateCreated = Date()
    }
}
