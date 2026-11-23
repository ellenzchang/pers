import Foundation

/// A pull request Claude opened, with its state and checks as `gh` last reported them.
struct PullRequest: Identifiable, Equatable {
    let url: String
    var title: String?
    var state: State?
    var checks: Checks?
    var baseBranch: String?
    var mergedAt: Date?
    /// Push workflows on the base branch for the merge commit.
    var mergeChecks: Checks?

    var id: String { url }
    /// The PR's checks, or the base branch's workflows once it's merged.
    var status: Checks? { state == .merged ? mergeChecks : checks }

    enum State: String { case draft, open, merged, closed }

    enum Checks {
        case passing, running, failing

        private static let failures: Set = ["failure", "error", "timed_out", "cancelled", "action_required", "startup_failure"]

        /// Takes check runs, status contexts or workflow runs. A failure shows even while other checks still run.
        init?(_ items: [[String: Any]]) {
            guard !items.isEmpty else { return nil }
            let outcomes = items.map { ($0["conclusion"] as? String ?? $0["state"] as? String ?? "").lowercased() }
            let finished = zip(items, outcomes).map { item, outcome in
                (item["status"] as? String).map { $0.lowercased() == "completed" } ?? !["pending", "expected"].contains(outcome)
            }
            if outcomes.contains(where: Self.failures.contains) { self = .failing }
            else if finished.contains(false) { self = .running }
            else { self = .passing }
        }
    }

    /// `https:`, host, owner, repo, `pull`, number; `urls(in:)` only matches that shape.
    private var parts: [String] { url.split(separator: "/").map(String.init) }
    var repo: String { parts[3] }
    var number: String { parts[5] }
    var label: String { "\(repo)#\(number)" }

    /// Workflows can start a little after the merge, so a merged PR is watched for a while even when none show yet.
    var isSettled: Bool {
        switch state {
        case .closed: true
        case .merged: mergeChecks != .running && (mergedAt ?? .distantPast) < Date().addingTimeInterval(-600)
        default: false
        }
    }

    nonisolated func refreshed() -> PullRequest {
        var pr = self
        let fields = "title,state,isDraft,baseRefName,mergedAt,mergeCommit,statusCheckRollup"
        guard let info = Self.gh(["pr", "view", url, "--json", fields]) as? [String: Any] else { return pr }
        pr.title = info["title"] as? String
        pr.baseBranch = info["baseRefName"] as? String
        pr.checks = Checks(info["statusCheckRollup"] as? [[String: Any]] ?? [])
        pr.mergedAt = (info["mergedAt"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
        switch info["state"] as? String {
        case "MERGED": pr.state = .merged
        case "CLOSED": pr.state = .closed
        default: pr.state = info["isDraft"] as? Bool == true ? .draft : .open
        }
        if pr.state == .merged, let commit = (info["mergeCommit"] as? [String: Any])?["oid"] as? String {
            // Scheduled runs are listed against the branch's latest commit too, so only push runs count.
            let repo = parts[1...3].joined(separator: "/")
            let runs = Self.gh(["run", "list", "-R", repo, "--commit", commit, "--event", "push", "--json", "status,conclusion"])
            pr.mergeChecks = (runs as? [[String: Any]]).flatMap(Checks.init)
        }
        return pr
    }

    /// Through a login shell, since a Finder-launched app's PATH doesn't include Homebrew.
    private nonisolated static func gh(_ args: [String]) -> Any? {
        let result = Git.execute(["-lc", "exec gh \"$@\"", "gh"] + args, in: NSHomeDirectory(), executable: "/bin/zsh")
        guard result.status == 0 else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
    }

    private static let pattern = try! NSRegularExpression(pattern: #"https://[\w.-]+/[\w.-]+/[\w.-]+/pull/\d+"#)

    static func urls(in text: String) -> [String] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
}

/// Finds the pull requests `gh pr create` opened, in stream-json events or transcript lines, which share a shape.
struct PullRequestDetector {
    private var creates: Set<String> = []

    mutating func urls(in event: [String: Any]) -> [String] {
        let blocks = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        switch event["type"] as? String {
        case "assistant":
            for block in blocks where block["type"] as? String == "tool_use" {
                let command = (block["input"] as? [String: Any])?["command"] as? String ?? ""
                if command.contains("gh pr create"), let id = block["id"] as? String { creates.insert(id) }
            }
            return []
        case "user":
            return blocks.filter { creates.contains($0["tool_use_id"] as? String ?? "") }.flatMap { PullRequest.urls(in: Self.text(of: $0)) }
        default:
            return []
        }
    }

    private static func text(of result: [String: Any]) -> String {
        if let text = result["content"] as? String { return text }
        return (result["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
}
