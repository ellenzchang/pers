import Foundation

struct Worktree: Identifiable, Hashable {
    var path: String
    var branch: String?
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

enum DiffBase {
    case unstaged, main

    var toggled: DiffBase { self == .unstaged ? .main : .unstaged }
    var label: String { self == .unstaged ? "unstaged" : "vs main" }
}

struct DiffRow: Equatable {
    enum Kind { case context, added, removed, modified, hunk }
    struct Removal: Equatable {
        var offset: Int
        var text: String
    }
    var kind: Kind
    var oldNumber: Int?
    var newNumber: Int?
    var text: String
    var changed: [Range<Int>] = []
    var removals: [Removal] = []
    var highlighted: AttributedString?
}

struct FileDiff: Identifiable, Equatable {
    var path: String
    var lines: [DiffRow]
    var id: String { path }
    var added: Int { lines.filter { $0.kind == .added || $0.kind == .modified }.count }
    var removed: Int { lines.filter { $0.kind == .removed || $0.kind == .modified }.count }

    func reference(to row: DiffRow) -> String? {
        switch row.kind {
        case .hunk: nil
        case .removed: row.oldNumber.map { "\(path):\($0) (removed)" }
        case .added, .modified, .context: row.newNumber.map { "\(path):\($0)" }
        }
    }
}

struct Commit: Identifiable, Equatable {
    var id: String
    var hash: String
    var subject: String
    var author: String
    var age: String
}

struct GitInfo: Equatable {
    var branch: String
    var changedFiles: Int
    var staged: Int
    var unstaged: Int
    var untracked: Int
    var ahead: Int
    var behind: Int
    var root: String
    var worktrees: [Worktree]

    /// The main checkout, which every worktree of the repo shares.
    var repoPath: String { worktrees.first?.path ?? root }
}

enum Git {
    static func info(at directory: String) -> GitInfo? {
        guard let root = run(["rev-parse", "--show-toplevel"], in: directory)?.trimmed else { return nil }
        let status = run(["status", "--porcelain=v1", "--branch"], in: directory) ?? ""
        let lines = status.split(separator: "\n").map(String.init)
        let header = lines.first ?? ""
        let files = lines.dropFirst()
        return GitInfo(
            branch: run(["branch", "--show-current"], in: directory)?.trimmed.nilIfEmpty ?? "detached",
            changedFiles: max(lines.count - 1, 0),
            staged: files.filter { !" ?".contains($0.first ?? " ") }.count,
            unstaged: files.filter { $0.first != "?" && $0.dropFirst().first != " " }.count,
            untracked: files.filter { $0.hasPrefix("??") }.count,
            ahead: count(of: "ahead", in: header),
            behind: count(of: "behind", in: header),
            root: root,
            worktrees: worktrees(at: directory)
        )
    }

    static func diff(_ base: DiffBase, at directory: String) async -> [FileDiff] {
        let ref = base == .main ? [run(["merge-base", "main", "HEAD"], in: directory)?.trimmed ?? "main"] : []
        return await diff(against: ref, at: directory)
    }

    static func diff(of commit: Commit, at directory: String) async -> [FileDiff] {
        await diff(against: ["\(commit.id)^!"], at: directory)
    }

    private static func diff(against ref: [String], at directory: String) async -> [FileDiff] {
        let paths = (run(["diff"] + ref + ["--name-only", "-z"], in: directory) ?? "")
            .split(separator: "\0").map(String.init)
        return await withTaskGroup(of: (Int, FileDiff).self) { group in
            for (index, path) in paths.enumerated() {
                group.addTask {
                    let output = execute(["diff"] + ref + ["--no-color", "--no-ext-diff", "--", path], in: directory).stdout
                    return (index, FileDiff(path: path, lines: parse(output)))
                }
            }
            var results: [(Int, FileDiff)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func log(at directory: String) -> [Commit] {
        let output = run(["log", "-200", "--format=%h%x1f%H%x1f%s%x1f%an%x1f%cr"], in: directory) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let fields = line.components(separatedBy: "\u{1F}")
            return fields.count == 5 ? Commit(id: fields[0], hash: fields[1], subject: fields[2], author: fields[3], age: fields[4]) : nil
        }
    }

    private static func parse(_ output: String) -> [DiffRow] {
        var rows: [DiffRow] = []
        var old = 0, new = 0
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line.dropFirst())
            if line.hasPrefix("@@") {
                let fields = line.split(separator: " ")
                old = startLine(fields[1])
                new = startLine(fields[2])
                rows.append(DiffRow(kind: .hunk, text: String(line)))
            } else if rows.isEmpty {
                continue
            } else if line.hasPrefix("+") {
                rows.append(DiffRow(kind: .added, newNumber: new, text: text))
                new += 1
            } else if line.hasPrefix("-") {
                rows.append(DiffRow(kind: .removed, oldNumber: old, text: text))
                old += 1
            } else if line.hasPrefix(" ") {
                rows.append(DiffRow(kind: .context, oldNumber: old, newNumber: new, text: text))
                old += 1
                new += 1
            }
        }
        markWordChanges(in: &rows)
        highlight(&rows)
        return rows.isEmpty ? [DiffRow(kind: .hunk, text: "No textual changes")] : rows
    }

    /// Highlights each side of the diff as one document so multi-line comments and strings keep their color.
    private static func highlight(_ rows: inout [DiffRow]) {
        for side in [DiffRow.Kind.removed, .added] {
            let indices = rows.indices.filter { [side, .context, .modified].contains(rows[$0].kind) }
            let highlighted = SyntaxHighlighter.highlight(lines: indices.map { rows[$0].text })
            for (index, line) in zip(indices, highlighted) where rows[index].kind == side || side == .added {
                rows[index].highlighted = line
            }
        }
    }

    private static func startLine(_ range: Substring) -> Int {
        Int(range.dropFirst().prefix { $0.isNumber }) ?? 0
    }

    /// Builds diff rows from raw old and new text, as shown inline under Edit and Write tool rows in the chat.
    static func rows(replacing old: String, with new: String) -> [DiffRow] {
        func lines(_ text: String) -> [Substring] { text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false) }
        var rows = lines(old).map { DiffRow(kind: .removed, text: String($0)) } + lines(new).map { DiffRow(kind: .added, text: String($0)) }
        markWordChanges(in: &rows)
        return rows
    }

    /// Merges each removed line with the added line at the same position in its block into one row, like GitHub's inline highlights.
    private static func markWordChanges(in rows: inout [DiffRow]) {
        var merged: [DiffRow] = []
        var index = 0
        while index < rows.count {
            guard rows[index].kind == .removed else { merged.append(rows[index]); index += 1; continue }
            let removedEnd = rows[index...].firstIndex { $0.kind != .removed } ?? rows.count
            let addedEnd = rows[removedEnd...].firstIndex { $0.kind != .added } ?? rows.count
            let removed = rows[index..<removedEnd], added = rows[removedEnd..<addedEnd]
            for (old, new) in zip(removed, added) {
                merged += merge(old, new).map { [$0] } ?? [old, new]
            }
            merged += removed.dropFirst(added.count) + added.dropFirst(removed.count)
            index = addedEnd
        }
        rows = merged
    }

    private static func merge(_ removed: DiffRow, _ added: DiffRow) -> DiffRow? {
        let old = Array(removed.text), new = Array(added.text)
        let (oldChanges, newChanges) = changedRanges(old, new)
        let changedCount = oldChanges.reduce(0) { $0 + $1.count }
        // Lines that barely resemble each other read better as separate removed and added rows.
        guard changedCount * 2 <= max(old.count, new.count) else { return nil }
        var shift = 0
        let removals = oldChanges.map { range in
            defer { shift += range.count }
            return DiffRow.Removal(offset: offset(ofUnchanged: range.lowerBound - shift, in: newChanges), text: String(old[range]))
        }
        return DiffRow(kind: .modified, oldNumber: removed.oldNumber, newNumber: added.newNumber, text: added.text, changed: newChanges, removals: removals)
    }

    /// The index in the new text where removed text following `unchanged` unchanged characters belongs.
    private static func offset(ofUnchanged unchanged: Int, in changes: [Range<Int>]) -> Int {
        var shift = 0
        for change in changes {
            if change.lowerBound - shift >= unchanged { break }
            shift += change.count
        }
        return unchanged + shift
    }

    private static func changedRanges(_ old: [Character], _ new: [Character]) -> (old: [Range<Int>], new: [Range<Int>]) {
        let oldTokens = tokenRanges(old), newTokens = tokenRanges(new)
        let x = oldTokens.map { String(old[$0]) }, y = newTokens.map { String(new[$0]) }
        var lcs = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in stride(from: x.count - 1, through: 0, by: -1) {
            for j in stride(from: y.count - 1, through: 0, by: -1) {
                lcs[i][j] = x[i] == y[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var keptOld = Set<Int>(), keptNew = Set<Int>()
        var matches: [(old: Int, new: Int)] = []
        var i = 0, j = 0
        while i < x.count && j < y.count {
            if x[i] == y[j] {
                keptOld.insert(i)
                keptNew.insert(j)
                matches.append((i, j))
                i += 1
                j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        // Dropped from both sides, so the unchanged text still lines up when placing removals in the new line.
        let joining = matches.filter {
            isLoneSpace($0.old, in: oldTokens, kept: keptOld, text: old) || isLoneSpace($0.new, in: newTokens, kept: keptNew, text: new)
        }
        for match in joining {
            keptOld.remove(match.old)
            keptNew.remove(match.new)
        }
        return (highlights(oldTokens, kept: keptOld), highlights(newTokens, kept: keptNew))
    }

    /// A kept space between two changes, which reads better as part of one change.
    private static func isLoneSpace(_ index: Int, in tokens: [Range<Int>], kept: Set<Int>, text: [Character]) -> Bool {
        let isSpace = text[tokens[index]].allSatisfy(\.isWhitespace)
        return isSpace && index > 0 && index < tokens.count - 1 && !kept.contains(index - 1) && !kept.contains(index + 1)
    }

    private static func tokenGroup(_ character: Character) -> Int? {
        if character.isLetter || character.isNumber || character == "_" { return 0 }
        return character.isWhitespace ? 1 : nil
    }

    private static func tokenRanges(_ text: [Character]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        while start < text.count {
            var end = start + 1
            if let group = tokenGroup(text[start]) {
                while end < text.count, tokenGroup(text[end]) == group { end += 1 }
            }
            ranges.append(start..<end)
            start = end
        }
        return ranges
    }

    /// Merges changed tokens into ranges.
    private static func highlights(_ tokens: [Range<Int>], kept: Set<Int>) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for (index, token) in tokens.enumerated() where !kept.contains(index) {
            if let last = ranges.last, last.upperBound == token.lowerBound {
                ranges[ranges.count - 1] = last.lowerBound..<token.upperBound
            } else {
                ranges.append(token)
            }
        }
        return ranges
    }

    static func worktrees(at directory: String) -> [Worktree] {
        guard let output = run(["worktree", "list", "--porcelain"], in: directory) else { return [] }
        return output.components(separatedBy: "\n\n").compactMap { block in
            var path: String?
            var branch: String?
            for line in block.split(separator: "\n") {
                if line.hasPrefix("worktree ") { path = String(line.dropFirst(9)) }
                if line.hasPrefix("branch ") { branch = String(line.dropFirst(7)).replacingOccurrences(of: "refs/heads/", with: "") }
            }
            return path.map { Worktree(path: $0, branch: branch) }
        }
    }

    /// Creates `<repo>/.claude/worktrees/<name>` inside the main repo on a new branch `<name>`.
    static func addWorktree(named name: String, from directory: String) throws -> String {
        guard let root = worktrees(at: directory).first?.path else {
            throw GitError("Not a git repository")
        }
        let path = (root as NSString).appendingPathComponent(".claude/worktrees/\(name)")
        let result = execute(["worktree", "add", "-b", name, path], in: directory)
        guard result.status == 0 else { throw GitError(result.stderr.trimmed) }
        return path
    }

    /// Commits reachable from HEAD that no remote has, whether or not the branch tracks an upstream.
    static func unpushedCommits(at directory: String) -> Int {
        Int(run(["rev-list", "--count", "HEAD", "--not", "--remotes"], in: directory)?.trimmed ?? "") ?? 0
    }

    static func removeWorktree(_ worktree: Worktree, from directory: String) throws {
        let result = execute(["worktree", "remove", "--force", worktree.path], in: directory)
        guard result.status == 0 else { throw GitError(result.stderr.trimmed) }
    }

    private static func count(of key: String, in header: String) -> Int {
        guard let range = header.range(of: "\(key) ") else { return 0 }
        return Int(header[range.upperBound...].prefix { $0.isNumber }) ?? 0
    }

    private static func run(_ args: [String], in directory: String) -> String? {
        let result = execute(args, in: directory)
        return result.status == 0 ? result.stdout : nil
    }

    private static func execute(_ args: [String], in directory: String, executable: String = "/usr/bin/git") -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return (-1, "", error.localizedDescription) }
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self))
    }
}

struct GitError: LocalizedError {
    var errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
