import Foundation

/// A commit on `main` that the installed build doesn't have yet.
struct UpdateCommit: Equatable, Sendable, Identifiable {
    let sha: String
    let title: String
    var id: String { sha }
    var shortSHA: String { String(sha.prefix(7)) }
}

/// What GitHub says about the installed build.
struct UpdateInfo: Equatable, Sendable {
    let latestSHA: String
    /// Newest first.
    let commits: [UpdateCommit]
    let aheadBy: Int
}

/// Reads NotchGate's `main` branch from the GitHub REST API.
enum UpdateSource {
    static let repository = "PrajsRamteke/NotchGate"
    static let branch = "main"
    static let installerURL = "https://raw.githubusercontent.com/\(repository)/\(branch)/install.sh"

    enum Failure: LocalizedError, Equatable {
        case offline
        case rateLimited
        /// The installed commit isn't on GitHub (a local, unpushed build).
        case unknownBuild
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .offline: return "Couldn't reach GitHub. Check your connection."
            case .rateLimited: return "GitHub is rate-limiting update checks. Try again later."
            case .unknownBuild: return "This build isn't on GitHub, so it can't be compared."
            case .badResponse(let code): return "GitHub answered with an error (\(code))."
            }
        }
    }

    /// Commits on `main` that `installedSHA` doesn't contain (empty = up to date).
    static func compare(installedSHA: String) async throws -> UpdateInfo {
        info(fromCompare: try await fetch("compare/\(installedSHA)...\(branch)"), installedSHA: installedSHA)
    }

    /// Parses GitHub's compare response (commits arrive oldest first).
    static func info(fromCompare json: [String: Any], installedSHA: String) -> UpdateInfo {
        let commits = Array(((json["commits"] as? [[String: Any]]) ?? []).compactMap(commit(from:)).reversed())
        let aheadBy = json["ahead_by"] as? Int ?? 0
        return UpdateInfo(latestSHA: commits.first?.sha ?? installedSHA, commits: commits, aheadBy: aheadBy)
    }

    private static func commit(from json: [String: Any]) -> UpdateCommit? {
        guard let sha = json["sha"] as? String,
              let message = (json["commit"] as? [String: Any])?["message"] as? String else { return nil }
        let title = message.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? message
        return UpdateCommit(sha: sha, title: title)
    }

    private static func fetch(_ path: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/\(path)") else {
            throw Failure.badResponse(0)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchGate-Updater", forHTTPHeaderField: "User-Agent")

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 404: throw Failure.unknownBuild
        case 403, 429: throw Failure.rateLimited
        default: throw Failure.badResponse(status)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.badResponse(status)
        }
        return object
    }
}
