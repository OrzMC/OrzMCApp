import OrzMCFoundation

public enum RemoteServerState: String, Equatable, Sendable {
    case online
    case offline
    case starting
    case stopping
    case restarting
    case unknown
}

public struct RemoteServerIdentifier: Hashable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

public struct RemoteServerSummary: Equatable, Sendable, Identifiable {
    public let id: RemoteServerIdentifier
    public let name: String
    public let address: String?
    public let state: RemoteServerState

    public init(
        id: RemoteServerIdentifier,
        name: String,
        address: String?,
        state: RemoteServerState
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.state = state
    }
}

public enum RemoteServerAction: Equatable, Sendable {
    case start
    case stop
    case restart
}

public protocol RemoteServerHosting: Sendable {
    func servers() async throws -> [RemoteServerSummary]
    func perform(_ action: RemoteServerAction, on serverId: RemoteServerIdentifier) async throws
}

public struct RemoteServerListPolicy: Sendable {
    public init() {}

    public func visibleServers(
        from servers: [RemoteServerSummary],
        searchText: String
    ) -> [RemoteServerSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return servers
        }
        return servers.filter { server in
            server.name.localizedCaseInsensitiveContains(query)
                || server.address?.localizedCaseInsensitiveContains(query) == true
        }
    }

    public func canPerform(_ action: RemoteServerAction, on state: RemoteServerState) -> Bool {
        switch (action, state) {
        case (.start, .offline), (.restart, .online):
            return true
        case (.stop, .online), (.stop, .starting), (.stop, .stopping), (.stop, .restarting):
            // 「启动中」也允许停止：手滑点了启动不该只能干等（exaroton 侧接受该请求）。
            return true
        default:
            return false
        }
    }
}
