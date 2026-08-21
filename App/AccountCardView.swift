import SwiftUI

// MARK: - Karta pojedynczego konta

struct AccountCardView: View {
    @Binding var account: Account
    @Environment(AccountStore.self) private var store

    @State private var isEditingName = false
    @State private var showingEntry = false
    @State private var showingWeeklyEntry = false
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        // The whole card refreshes natively once a second — which also lets it
        // flip to "done" exactly when the reset moment arrives.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = account.status(now: context.date)
            VStack(alignment: .leading, spacing: 6) {
                if confirmingDelete {
                    deleteConfirmation
                } else {
                    nameRow
                    countdownSection(now: context.date, status: status)
                    weeklySection(now: context.date)
                }
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(confirmingDelete ? Color.red.opacity(0.14)
                          : status == .done ? Color.green.opacity(0.18)
                                            : Color.secondary.opacity(0.12))
            }
            .overlay {
                if confirmingDelete {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red, lineWidth: 1.5)
                } else if status == .done {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green, lineWidth: 1.5)
                }
            }
            .shadow(color: status == .done && !confirmingDelete ? Color.green.opacity(0.55) : .clear,
                    radius: 8)
        }
        .popover(isPresented: $showingEntry, arrowEdge: .bottom) {
            DurationEntry { interval in
                account.windowHours = interval / 3600
                account.resetDate = Date().addingTimeInterval(interval)
                showingEntry = false
            }
        }
        .popover(isPresented: $showingWeeklyEntry, arrowEdge: .bottom) {
            WeeklyResetEntry(current: account.weeklyReset) { weekly in
                account.weeklyReset = weekly
                showingWeeklyEntry = false
            }
        }
    }

    // MARK: Potwierdzenie usunięcia

    /// The confirmation lives **inside the card**, not in a `confirmationDialog`.
    ///
    /// A dialog is a window of its own, and the menu bar panel closes the moment
    /// another window takes key focus. So the panel — with this card and the
    /// dialog's own buttons inside it — was torn down as the dialog appeared:
    /// neither button ever ran its action, and from the outside the whole app
    /// window simply vanished instead of deleting anything. Anything the user has
    /// to click therefore has to stay within the panel.
    private var deleteConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.t("Usunąć konto „\(account.name)”?", "Delete the account “\(account.name)”?"))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(loc.t("Tej operacji nie można cofnąć.", "This cannot be undone."))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(loc.t("Anuluj", "Cancel")) { confirmingDelete = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button(loc.t("Usuń konto", "Delete account")) { confirmDelete() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Removes the account one turn of the run loop later.
    ///
    /// The button sits in the card that is about to disappear, and the `ForEach`
    /// above still reads `$store.accounts` while this action returns — removing the
    /// element right here means reading an index that is already gone. The same
    /// reason `resetAndEnterNew()` defers its popover.
    private func confirmDelete() {
        let id = account.id
        confirmingDelete = false
        Task { @MainActor in store.remove(id: id) }
    }

    // MARK: Nazwa

    private var nameRow: some View {
        HStack {
            if isEditingName {
                TextField("Nazwa konta", text: $account.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit { isEditingName = false }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { isEditingName = false }
                    }
            } else {
                Text(account.name)
                    .font(.headline)
                    .onTapGesture(count: 2) { beginEditingName() }
                Button {
                    beginEditingName()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(loc.t("Zmień nazwę", "Rename"))
                .accessibilityLabel(loc.t("Zmień nazwę konta \(account.name)", "Rename account \(account.name)"))
            }
            Spacer()
            computerToggles
            if account.resetDate != nil {
                Button {
                    store.clearReset(id: account.id)
                } label: {
                    Image(systemName: "clock.badge.xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Anuluj odliczanie")
                .accessibilityLabel("Anuluj odliczanie konta \(account.name)")
            }
            Button {
                confirmingDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(loc.t("Usuń konto", "Delete account"))
            .accessibilityLabel(loc.t("Usuń konto \(account.name)", "Delete account \(account.name)"))
        }
    }

    private func beginEditingName() {
        isEditingName = true
        nameFocused = true
    }

    // MARK: Macs (where this profile is signed in)

    /// Checkboxes with Mac icons, left to right, next to the button that cancels
    /// the countdown. Toggling does not affect the clock — it changes
    /// tylko `account.computers`.
    @ViewBuilder
    private var computerToggles: some View {
        let enabled = Computer.allCases.filter { store.enabledComputers.contains($0) }
        if !enabled.isEmpty {
            HStack(spacing: 4) {
                ForEach(enabled) { computer in
                    let isOn = account.computers.contains(computer)
                    Button {
                        toggleComputer(computer)
                    } label: {
                        Image(systemName: computer.systemImage)
                            .imageScale(.small)
                            .foregroundStyle(isOn ? Color.accentColor : .secondary)
                            .frame(width: 22, height: 22)
                            .background {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isOn ? Color.accentColor.opacity(0.18)
                                               : Color.secondary.opacity(0.12))
                            }
                    }
                    .buttonStyle(.borderless)
                    .help("\(computer.displayName): \(isOn ? "zalogowany" : "niezalogowany")")
                    .accessibilityLabel("\(computer.displayName), konto \(account.name)")
                    .accessibilityValue(isOn ? "zalogowany" : "niezalogowany")
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
        }
    }

    private func toggleComputer(_ computer: Computer) {
        if account.computers.contains(computer) {
            account.computers.remove(computer)
        } else {
            account.computers.insert(computer)
        }
    }

    // MARK: Odliczanie

    @ViewBuilder
    private func countdownSection(now: Date, status: ResetStatus) -> some View {
        if let reset = account.resetDate, reset > now {
            // Licznik biegnie — przycisk Reset po lewej od zegara, pasek pod spodem
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(timerInterval: now...reset, countsDown: true)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(status.color)
                    Spacer()
                    weeklyButton()
                    resetButton()
                }
                progressBar(now: now, reset: reset, status: status)
            }
        } else if account.resetDate != nil {
            // The "done" state — waiting for a click on Reset
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Gotowe — kliknij Reset")
            }
            .font(.title3.bold())
            .foregroundStyle(.green)
            Button {
                resetAndEnterNew()
            } label: {
                Label("Reset", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
        } else {
            // Brak licznika — bez tekstu statusu, tylko przyciski
            HStack(spacing: 8) {
                weeklyButton()
                resetButton()
            }
        }
    }

    /// A progress bar with the reset time centred directly on it.
    /// White text with a shadow — readable over both the filled and empty parts.
    ///
    /// Narrower than it used to be (18 → 12 pt): the weekly bar now sits underneath,
    /// and two bars of the old height turned the card into a pair of stripes.
    private func progressBar(now: Date, reset: Date, status: ResetStatus) -> some View {
        bar(fraction: account.progress(now: now),
            color: status.color,
            caption: reset.formatted(date: .omitted, time: .shortened))
    }

    /// One bar: track, fill, and a caption centred on top of it.
    /// Shared by the session and weekly rows so the two cannot drift apart in style.
    private func bar(fraction: Double, color: Color, caption: String) -> some View {
        GeometryReader { geo in
            ZStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * fraction))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 1)
            }
        }
        .frame(height: 12)
    }

    // MARK: Weekly limit

    /// The weekly bar, in indigo — a colour the session states never use, so a glance
    /// tells the two apart even when both are running.
    @ViewBuilder
    private func weeklySection(now: Date) -> some View {
        if let weekly = account.weeklyReset {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(loc.t("Tydzień", "Weekly"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(weekly.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.indigo)
                    Spacer()
                }
                // The countdown rides on the bar itself, the way the session bar carries
                // its reset time — one glance gives both how far along and how long left.
                bar(fraction: weekly.progress(from: now),
                    color: .indigo,
                    caption: WeeklyReset.countdownText(weekly.remaining(from: now) ?? 0))
            }
        }
    }

    private func resetButton() -> some View {
        Button {
            showingEntry = true
        } label: {
            Label("Reset", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Sets the weekly limit reset. Sits next to "Reset", because both buttons answer
    /// the same question — when does this account come back — only on different clocks.
    private func weeklyButton() -> some View {
        Button {
            showingWeeklyEntry = true
        } label: {
            Image(systemName: account.weeklyReset == nil
                  ? "calendar.badge.plus" : "calendar.badge.clock")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .foregroundStyle(account.weeklyReset == nil ? Color.secondary : Color.indigo)
        .help(loc.t("Reset tygodniowego limitu", "Weekly limit reset"))
        .accessibilityLabel(
            loc.t("Reset tygodniowego limitu konta \(account.name)",
                  "Weekly limit reset for account \(account.name)"))
    }

    /// Clears the countdown and immediately opens the field for a new duration.
    ///
    /// Clearing `resetDate` rebuilds the card (the green button goes, the height
    /// changes). Opening the popover in that same layout pass could crash AppKit
    /// ("done → Reset" quit the app), so presenting it is deferred to the next turn
    /// of the run loop, once the layout has settled.
    private func resetAndEnterNew() {
        account.resetDate = nil
        Task { @MainActor in
            showingEntry = true
        }
    }
}

// MARK: - Wpisywanie czasu (popover z jednym polem)

private struct DurationEntry: View {
    let onCommit: (TimeInterval) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = DurationParser.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            Text("Za ile reset?")
                .font(.headline)
            TextField("np. 3:30 albo 2:45", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .frame(width: 200)
                .onSubmit { commit(parsed) }
            hint(parsed: parsed)
                .font(.caption)
            HStack {
                Spacer()
                Button("Ustaw") { commit(parsed) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsed == nil)
            }
        }
        .padding(14)
        .onAppear { focused = true }
    }

    @ViewBuilder
    private func hint(parsed: TimeInterval?) -> some View {
        if text.isEmpty {
            Text("Format: H:MM, np. 3:30")
                .foregroundStyle(.secondary)
        } else if let parsed {
            Text("→ reset o \(preview(parsed))")
                .foregroundStyle(.green)
        } else {
            Text(loc.t("Nieprawidłowy format", "Invalid format"))
                .foregroundStyle(.red)
        }
    }

    private func preview(_ interval: TimeInterval) -> String {
        let date = Date().addingTimeInterval(interval)
        if interval >= 86_400 {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func commit(_ parsed: TimeInterval?) {
        guard let parsed else { return }
        onCommit(parsed)
    }
}

// MARK: - Weekly reset entry (one field, Anthropic's own wording)

/// Takes the reset exactly as Anthropic states it — `Sat 12 AM` — so there is nothing
/// to convert in one's head. A picker for day + hour + AM/PM would be three controls
/// for what the user already has on screen as one line of text.
private struct WeeklyResetEntry: View {
    let current: WeeklyReset?
    let onCommit: (WeeklyReset?) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = WeeklyReset.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            Text(loc.t("Kiedy reset tygodniowego limitu?", "When does the weekly limit reset?"))
                .font(.headline)
            TextField("Sat 12 AM", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .frame(width: 200)
                .onSubmit { commit(parsed) }
            hint(parsed: parsed)
                .font(.caption)
            HStack {
                if current != nil {
                    Button(loc.t("Wyczyść", "Clear")) { onCommit(nil) }
                }
                Spacer()
                Button(loc.t("Ustaw", "Set")) { commit(parsed) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsed == nil)
            }
        }
        .padding(14)
        .onAppear {
            text = current?.label ?? ""
            focused = true
        }
    }

    @ViewBuilder
    private func hint(parsed: WeeklyReset?) -> some View {
        if text.isEmpty {
            Text(loc.t("Format jak w Anthropic: Sat 12 AM", "Anthropic's own format: Sat 12 AM"))
                .foregroundStyle(.secondary)
        } else if let parsed, let next = parsed.nextDate(after: Date()) {
            Text(loc.t("→ najbliższy: \(next.formatted(date: .abbreviated, time: .shortened))",
                       "→ next: \(next.formatted(date: .abbreviated, time: .shortened))"))
                .foregroundStyle(.green)
        } else {
            Text(loc.t("Nieprawidłowy format", "Invalid format"))
                .foregroundStyle(.red)
        }
    }

    private func commit(_ parsed: WeeklyReset?) {
        guard let parsed else { return }
        onCommit(parsed)
    }
}

// MARK: - Parser czasu trwania

enum DurationParser {
    /// Parsuje format zegarowy "H:MM", np. "3:30", "2:45", "0:30".
    /// A bare "3" (no colon) means 3 hours. Returns nil for a malformed value.
    static func parse(_ input: String) -> TimeInterval? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        let parts = text.split(separator: ":", omittingEmptySubsequences: false)

        switch parts.count {
        case 1:
            // Same godziny
            guard let hours = Int(parts[0]), hours >= 0 else { return nil }
            let total = TimeInterval(hours) * 3600
            return total > 0 ? total : nil
        case 2:
            let minutesText = parts[1]
            guard let hours = Int(parts[0]), hours >= 0,
                  (1...2).contains(minutesText.count),
                  let minutes = Int(minutesText), (0..<60).contains(minutes)
            else { return nil }
            let total = TimeInterval(hours) * 3600 + TimeInterval(minutes) * 60
            return total > 0 ? total : nil
        default:
            return nil
        }
    }
}
