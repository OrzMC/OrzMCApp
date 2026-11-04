import ConsoleUI
import SwiftUI

/// Shared console row layout used by all app console presentations.
public typealias OrzMCConsoleRows<Data: RandomAccessCollection, ID: Hashable, Row: View, Empty: View> = ConsoleRows<Data, ID, Row, Empty>

/// Shared display controls; filtering text remains local to each console.
public struct OrzMCConsoleControls: View {
    @Binding private var search: String
    #if os(macOS)
    @AppStorage("console.fontSize") private var fontSize: Double = 14
    #endif
    @AppStorage("console.wrapLines") private var wrapLines = false

    public init(search: Binding<String>) { self._search = search }

    public var body: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            TextField("Search log", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("console.search")
            #if os(macOS)
            Button("Decrease font size", systemImage: "textformat.size.smaller") {
                fontSize = max(10, fontSize - 1)
            }
            .labelStyle(.iconOnly)
            .help("Decrease font size")
            .disabled(fontSize <= 10)
            Button("Increase font size", systemImage: "textformat.size.larger") {
                fontSize = min(28, fontSize + 1)
            }
            .labelStyle(.iconOnly)
            .help("Increase font size")
            .disabled(fontSize >= 28)
            #endif
            Toggle(isOn: $wrapLines) {
                Label("Wrap lines", systemImage: "text.alignleft")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .help("Wrap lines")
            .accessibilityIdentifier("console.wrapLines")
        }
    }
}

/// Pinch the log without interfering with its scrolling; VoiceOver can adjust it too.
private struct ConsoleMagnification: ViewModifier {
    @AppStorage("console.fontSize") private var fontSize: Double = 14
    @State private var startingSize: Double?

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let initial = startingSize ?? fontSize
                        if startingSize == nil { startingSize = initial }
                        fontSize = min(28, max(10, initial * value.magnification))
                    }
                    .onEnded { _ in startingSize = nil }
            )
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: fontSize = min(28, fontSize + 1)
                case .decrement: fontSize = max(10, fontSize - 1)
                @unknown default: break
                }
            }
    }
}

public extension View {
    func consoleMagnification() -> some View { modifier(ConsoleMagnification()) }
}
