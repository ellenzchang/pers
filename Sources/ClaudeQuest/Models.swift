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
    case user, claude, tool, shell, system
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
    var draft: String?
}

struct PermissionPrompt {
    var requestId: String
    var tool: String
    var detail: String
    var input: [String: Any]
    var suggestions: [[String: Any]]
    var questions: [Question]
    var answers: [String: String] = [:]

    /// The first question still waiting for an answer, when the prompt is an AskUserQuestion call.
    var question: Question? { questions.first { answers[$0.text] == nil } }
    var step: String { "\(requestId)/\(answers.count)" }

    struct Question {
        var text: String
        var header: String
        var options: [(label: String, description: String)]

        init(json: [String: Any]) {
            text = json["question"] as? String ?? ""
            header = json["header"] as? String ?? ""
            options = (json["options"] as? [[String: Any]] ?? []).map {
                ($0["label"] as? String ?? "", $0["description"] as? String ?? "")
            }
        }
    }
}
