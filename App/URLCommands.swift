import Foundation
import AppKit
import os

// MARK: - Polecenia z adresu tokentime://
//
// A way in without the panel (2026-10-16): a reset can be set from Shortcuts,
// a script or the Terminal, without opening the menu bar panel:
//
//   open "tokentime://reset?konto=praca&za=2:44"
//
// `za` is read by the same `DurationParser` as the field on the card (H:MM or a bare
// hour count, up to `maxHours`). The account is matched by name, case-insensitively;
// an unknown or ambiguous name changes nothing. Every command goes to the log:
// `log stream --predicate 'subsystem == "com.mikagosz.tokentime" && category == "url"'`

enum URLCommand: Equatable, Sendable {
    case reset(account: String, interval: TimeInterval)

    static let scheme = "tokentime"

    enum ParseError: Error, Equatable {
        case notTokenTime, unknownCommand(String), missingAccount, badDuration(String)
    }

    static func parse(_ url: URL) -> Result<URLCommand, ParseError> {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return .failure(.notTokenTime) }
        // tokentime://reset?… — the command sits in the host; tokentime:reset?… lands in the path.
        let command = (components.host ?? components.path).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let items = components.queryItems ?? []
        func value(_ names: String...) -> String? {
            items.first { names.contains($0.name.lowercased()) }?.value?
                .trimmingCharacters(in: .whitespaces)
        }
        switch command {
        case "reset":
            guard let account = value("konto", "account"), !account.isEmpty else { return .failure(.missingAccount) }
            let text = value("za", "in") ?? ""
            guard let interval = DurationParser.parse(text) else { return .failure(.badDuration(text)) }
            return .success(.reset(account: account, interval: interval))
        default:
            return .failure(.unknownCommand(command))
        }
    }
}

/// Carries commands from `AppDelegate` to the store. The store lives in the SwiftUI
/// scene, so it registers itself from the menu bar label — the only view that exists
/// from launch. A URL that opens the app arrives before that, so it waits here.
@MainActor
final class URLCommandRouter {
    static let shared = URLCommandRouter()
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mikagosz.tokentime", category: "url")

    private var store: AccountStore?
    private var pending: [URL] = []

    func attach(_ store: AccountStore) {
        guard self.store == nil else { return }
        self.store = store
        let waiting = pending
        pending = []
        waiting.forEach(handle)
    }

    func handle(_ url: URL) {
        guard let store else { pending.append(url); return }
        switch URLCommand.parse(url) {
        case .failure(let error):
            Self.log.error("Odrzucone polecenie \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
        case .success(let command):
            Task { await self.run(command, on: store) }
        }
    }

    /// Until the cloud state is known the panel is read-only (`canEdit`), and so is
    /// this way in — a blind write used to overwrite the other Macs. Wait up to a minute.
    private func run(_ command: URLCommand, on store: AccountStore) async {
        for _ in 0..<60 where !store.canEdit { try? await Task.sleep(for: .seconds(1)) }
        guard store.canEdit else {
            Self.log.error("Polecenie nie wykonane: synchronizacja nie skończyła się w ciągu minuty")
            return
        }
        switch command {
        case let .reset(name, interval):
            let matches = store.accounts.filter { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
            guard matches.count == 1, let account = matches.first else {
                Self.log.error("Reset nie ustawiony: konto „\(name, privacy: .public)” — trafień \(matches.count)")
                return
            }
            let date = Date().addingTimeInterval(interval)
            store.setReset(id: account.id, date: date)
            Self.log.notice("Reset konta „\(account.name, privacy: .public)” ustawiony na \(date.formatted(date: .abbreviated, time: .shortened), privacy: .public)")
        }
    }
}
