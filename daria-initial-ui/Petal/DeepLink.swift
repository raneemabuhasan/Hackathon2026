import Foundation

/// Links into the app, e.g. from the home screen widget. Compiled into the app and the widget.
enum DeepLink: Equatable {
    /// Today's log sheet.
    case log

    static let scheme = "petal"

    var url: URL {
        switch self {
        case .log: URL(string: "\(Self.scheme)://log")!
        }
    }

    init?(_ url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host {
        case "log": self = .log
        default: return nil
        }
    }
}
