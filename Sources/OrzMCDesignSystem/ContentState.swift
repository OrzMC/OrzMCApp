import SwiftUI

public struct ContentState: Equatable, Sendable {
    public let title: String
    public let message: String?
    public let systemImage: String

    public init(title: String, message: String? = nil, systemImage: String) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }
}

public struct EmptyContentView: View {
    private let state: ContentState

    public init(_ state: ContentState) {
        self.state = state
    }

    public var body: some View {
        ContentUnavailableView(
            state.title,
            systemImage: state.systemImage,
            description: state.message.map(Text.init)
        )
    }
}

public enum OrzMCContentStates {
    public static let noVersionSelected = ContentState(
        title: String(localized: "Select a Minecraft version"),
        message: String(localized: "Choose a version from the sidebar to view details."),
        systemImage: "cube.box"
    )
}
