import Foundation

struct Worktree: Identifiable, Hashable {
    var path: String
    var branch: String?
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

struct GitInfo: Equatable {
    var branch: String
    var changedFiles: Int
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
            ahead: count(of: "ahead", in: header),
            behind: count(of: "behind", in: header),
            root: root,
            worktrees: worktrees(at: directory)
        )
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

    /// Creates `<repo>-<name>` next to the main repo on a new branch `<name>`.
    static func addWorktree(named name: String, from directory: String) throws -> String {
        guard let root = run(["rev-parse", "--show-toplevel"], in: directory)?.trimmed else {
            throw GitError("Not a git repository")
        }
        let parent = (root as NSString).deletingLastPathComponent
        let path = (parent as NSString).appendingPathComponent("\((root as NSString).lastPathComponent)-\(name)")
        let result = execute(["worktree", "add", "-b", name, path], in: directory)
        guard result.status == 0 else { throw GitError(result.stderr.trimmed) }
        return path
    }

    private static func count(of key: String, in header: String) -> Int {
        guard let range = header.range(of: "\(key) ") else { return 0 }
        return Int(header[range.upperBound...].prefix { $0.isNumber }) ?? 0
    }

    private static func run(_ args: [String], in directory: String) -> String? {
        let result = execute(args, in: directory)
        return result.status == 0 ? result.stdout : nil
    }

    private static func execute(_ args: [String], in directory: String) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
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
