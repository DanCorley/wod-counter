import Foundation
import SwiftData

@Model final class Movement {
    @Attribute(.unique) var name: String
    var equipment: String?
    var category: String?
    var iconName: String?

    init(name: String, equipment: String? = nil, category: String? = nil, iconName: String? = nil) {
        self.name = name
        self.equipment = equipment
        self.category = category
        self.iconName = iconName
    }
}
