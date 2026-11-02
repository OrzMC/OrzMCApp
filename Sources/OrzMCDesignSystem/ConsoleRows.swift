import ConsoleUI
import SwiftUI

/// Shared console row layout used by all app console presentations.
public typealias OrzMCConsoleRows<Data: RandomAccessCollection, ID: Hashable, Row: View, Empty: View> = ConsoleRows<Data, ID, Row, Empty>
