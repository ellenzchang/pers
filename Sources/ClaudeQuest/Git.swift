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
    enum Kind { case context, added, removed, hunk }
    var kind: Kind
    var oldNumber: Int?
    var newNumber: Int?
    var text: String
    var changed: Range<Int>?
}

struct FileDiff: Identifiable, Equatable {
    var path: String
    var lines: [DiffRow]
    var id: String { path }
}

struct GitInfo: Equatable {
    var branch: String
    var changedFiles: Int
    var unstaged: Int
    var ahead: Int
    var behind: Int
    var root: String
    var worktrees: [Worktree]
}

enum Git {
    static func info(at directory: String) -> GitInfo? {
        guard let root = run(["rev-parse", "--show-toplevel"], in: directory)?.trimmed else { return nil }
        let status = run(["status", "--porcelain=v1", "--branch"], in: directory) ?? ""
        let lines = status.split(separator: "\n").map(String.init)
        let header = lines.first ?? ""
        return GitInfo(
            branch: run(["branch", "--show-current"], in: directory)?.trimmed.nilIfEmpty ?? "detached",
            changedFiles: max(lines.count - 1, 0),
            unstaged: lines.dropFirst().filter { $0.dropFirst().first != " " }.count,
            ahead: count(of: "ahead", in: header),
            behind: count(of: "behind", in: header),
            root: root,
            worktrees: worktrees(at: directory)
        )
    }

    static func diff(_ base: DiffBase, at directory: String) async -> [FileDiff] {
        let ref = base == .main ? [run(["merge-base", "main", "HEAD"], in: directory)?.trimmed ?? "main"] : []
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
        return rows.isEmpty ? [DiffRow(kind: .hunk, text: "No textual changes")] : rows
    }

    private static func startLine(_ range: Substring) -> Int {
        Int(range.dropFirst().prefix { $0.isNumber }) ?? 0
    }

    /// Pairs each removed line with the added line at the same position in its block, like GitHub's inline highlights.
    private static func markWordChanges(in rows: inout [DiffRow]) {
        var index = 0
        while index < rows.count {
            guard rows[index].kind == .removed else { index += 1; continue }
            let removedEnd = rows[index...].firstIndex { $0.kind != .removed } ?? rows.count
            let addedEnd = rows[removedEnd...].firstIndex { $0.kind != .added } ?? rows.count
            for offset in 0..<min(removedEnd - index, addedEnd - removedEnd) {
                let removed = Array(rows[index + offset].text), added = Array(rows[removedEnd + offset].text)
                let prefix = zip(removed, added).prefix { $0 == $1 }.count
                let suffix = zip(removed.dropFirst(prefix).reversed(), added.dropFirst(prefix).reversed()).prefix { $0 == $1 }.count
                rows[index + offset].changed = prefix..<(removed.count - suffix)
                rows[removedEnd + offset].changed = prefix..<(added.count - suffix)
            }
            index = addedEnd
        }
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
