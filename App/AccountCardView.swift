import SwiftUI

// MARK: - Karta pojedynczego konta

struct AccountCardView: View {
    @Binding var account: Account
    @Environment(AccountStore.self) private var store

    @State private var isEditingName = false
    @State private var showingEntry = false
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        // Cała karta odświeżana natywnie co sekundę — pozwala też przejść
        // w stan „gotowe” dokładnie w chwili osiągnięcia resetu.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = account.status(now: context.date)
            VStack(alignment: .leading, spacing: 6) {
                nameRow
                countdownSection(now: context.date, status: status)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(status == .done ? Color.green.opacity(0.18)
                                          : Color.secondary.opacity(0.12))
            }
            .overlay {
                if status == .done {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green, lineWidth: 1.5)
                }
            }
            .shadow(color: status == .done ? Color.green.opacity(0.55) : .clear,
                    radius: 8)
        }
        .popover(isPresented: $showingEntry, arrowEdge: .bottom) {
            DurationEntry { interval in
                account.windowHours = interval / 3600
                account.resetDate = Date().addingTimeInterval(interval)
                showingEntry = false
            }
        }
        .confirmationDialog(
            "Usunąć konto „\(account.name)”?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Usuń konto", role: .destructive) { store.remove(id: account.id) }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Tej operacji nie można cofnąć.")
        }
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
            }
            Button {
                confirmingDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Usuń konto")
        }
    }

    private func beginEditingName() {
        isEditingName = true
        nameFocused = true
    }

    // MARK: Komputery (na którym profil jest zalogowany)

    /// Checkboxy z ikonami komputerów, od lewej do prawej, przy przycisku
    /// anulowania odliczania. Przełączanie nie wpływa na zegar — zmienia
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
                    resetButton()
                }
                progressBar(now: now, reset: reset, status: status)
            }
        } else if account.resetDate != nil {
            // Stan „gotowe” — czeka na kliknięcie Reset
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
            // Brak licznika — bez tekstu statusu, tylko przycisk
            resetButton()
        }
    }

    /// Pasek postępu z godziną resetu wyśrodkowaną bezpośrednio na nim.
    /// Biały tekst z cieniem — czytelny nad wypełnioną i pustą częścią paska.
    private func progressBar(now: Date, reset: Date, status: ResetStatus) -> some View {
        let fraction = account.progress(now: now)
        return GeometryReader { geo in
            ZStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(status.color)
                    .frame(width: max(0, geo.size.width * fraction))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(reset.formatted(date: .omitted, time: .shortened))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 1)
            }
        }
        .frame(height: 18)
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

    /// Czyści licznik i od razu otwiera pole na nowy czas.
    ///
    /// Wyczyszczenie `resetDate` przebudowuje kartę (znika zielony przycisk,
    /// zmienia się jej wysokość). Otwarcie popovera w tym samym cyklu układu
    /// potrafiło wywalać AppKit („gotowe → Reset” zamykało apkę). Prezentację
    /// popovera odkładamy więc na kolejny obrót pętli, gdy układ się ustali.
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
            Text("Nieprawidłowy format")
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

// MARK: - Parser czasu trwania

enum DurationParser {
    /// Parsuje format zegarowy "H:MM", np. "3:30", "2:45", "0:30".
    /// Samo "3" (bez dwukropka) = 3 godziny. Zwraca nil dla błędnego formatu.
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
