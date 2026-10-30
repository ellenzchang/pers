import Foundation

enum ClaudeModel: String, CaseIterable, Codable, Identifiable {
    case opus, sonnet, haiku, fable
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum PermissionMode: String, CaseIterable, Codable, Identifiable {
    case manual, acceptEdits, plan, auto, dontAsk, bypassPermissions
    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "MANUAL"
        case .acceptEdits: "ACCEPT EDITS"
        case .plan: "PLAN"
        case .auto: "AUTO"
        case .dontAsk: "DON'T ASK"
        case .bypassPermissions: "BYPASS"
        }
    }
}

enum Effort: String, CaseIterable, Codable, Identifiable {
    case low, medium, high, xhigh, max
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum Speaker: String, Codable {
    case user, claude, tool, system
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var speaker: Speaker
    var text: String
}

struct SessionSnapshot: Codable {
    var id: UUID
    var directory: String
    var sessionId: String?
    var model: ClaudeModel
    var mode: PermissionMode
    var effort: Effort?
    var cost: Double
    var messages: [ChatMessage]
    var outfit: Int?
}
