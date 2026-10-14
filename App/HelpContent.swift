import Foundation

/// What the Help window says: each section is a picture of the app with numbered points and the same
/// numbers in the steps next to it. Polish and English side by side, like the rest of TokenTime (`loc.t`).
nonisolated enum HelpContent {
    /// One text in both languages.
    struct Text: Hashable {
        let pl: String
        let en: String
        @MainActor var current: String { loc.t(pl, en) }
    }

    /// Which picture stands next to the section; drawn by the app itself in HelpWindow.swift.
    enum Picture: CaseIterable { case label, panel, card, entry, states, weekly, macs }

    struct Section {
        let title: Text
        let lead: Text
        /// Numbered like the points on the picture: the first step is point 1.
        let steps: [Text]
        /// The longer description, folded under "More".
        let more: Text?
        let picture: Picture
    }

    struct Card {
        let symbol: String
        let title: Text
        let text: Text
    }

    private static func t(_ pl: String, _ en: String) -> Text { Text(pl: pl, en: en) }

    static let buttonHelp = t("Pomoc TokenTime", "TokenTime Help")
    static let windowTitle = t("TokenTime — Pomoc", "TokenTime — Help")
    static let title = t("Pierwsze kroki z TokenTime", "Getting started with TokenTime")
    static let intro = t("Kiedy znowu otworzy się okno tokenów Claude'a — na każdym koncie i na każdym Twoim Macu. Odpowiedź siedzi w pasku menu, wystarczy zerknąć.",
                         "When your Claude token window opens again — on every account and every Mac of yours. The answer sits in the menu bar; a glance is enough.")

    static let sections: [Section] = [
        Section(title: t("Ikona w pasku menu", "The menu bar icon"),
                lead: t("TokenTime mieszka w pasku menu, bez ikony w Docku.",
                        "TokenTime lives in the menu bar, with no icon in the Dock."),
                steps: [t("Kliknij ikonę — otworzy się panel z kontami.", "Click the icon to open the panel with your accounts."),
                        t("Obok ikony: ile zostało do najbliższego resetu ze wszystkich kont.",
                          "Next to it: the time left to the soonest reset across all accounts.")],
                more: t("Licznik w pasku odświeża się co pół minuty, a w otwartym panelu co sekundę. Gdy żadne konto nie odlicza, w pasku zostaje sama ikona.",
                        "The count in the menu bar refreshes every half minute, and every second in the open panel. With no account counting down, only the icon stays in the bar."),
                picture: .label),
        Section(title: t("Panel", "The panel"),
                lead: t("Wszystkie konta jedno pod drugim, każde z własnym odliczaniem.",
                        "All your accounts one under another, each with its own countdown."),
                steps: [t("Dodaj konto.", "Add an account."),
                        t("Pomoc i Ustawienia.", "Help and Settings."),
                        t("Karty kont — o nich niżej.", "The account cards — more on them below."),
                        t("Uruchamiaj TokenTime razem z Makiem.", "Start TokenTime together with your Mac.")],
                more: t("Znaczek chmurki przy nazwie programu mówi, jak idzie synchronizacja przez iCloud Drive: ✓ zsynchronizowane, strzałka w dół — pobieranie, pomarańczowy — dane tylko na tym Macu. Dopóki program nie wie, co jest w chmurze, panel nie przyjmuje zmian, żeby nie nadpisać kont z innego Maca.",
                        "The cloud mark next to the app's name tells how the iCloud Drive sync is going: ✓ in sync, a down arrow means downloading, orange means the data is on this Mac only. Until the app knows what is in the cloud, the panel takes no changes, so accounts from another Mac are not overwritten."),
                picture: .panel),
        Section(title: t("Karta konta", "An account card"),
                lead: t("Jedna karta to jedno konto Claude'a: nazwa, na których Macach jest zalogowane i ile zostało do resetu.",
                        "One card is one Claude account: its name, which Macs it is signed in on, and the time left to its reset."),
                steps: [t("Nazwa — kliknij dwa razy albo ołówek, żeby ją zmienić.", "The name — double-click it or click the pencil to change it."),
                        t("Maki, na których to konto jest zalogowane — kliknięcie przełącza.", "The Macs this account is signed in on — a click switches one."),
                        t("Usuń konto (z potwierdzeniem na karcie).", "Delete the account (confirmed on the card)."),
                        t("Odliczanie do resetu i pasek: pełny w chwili resetu, z godziną resetu na środku.",
                          "The countdown and its bar: full at the reset, with the reset time in the middle.")],
                more: t("Zegar z krzyżykiem obok kosza anuluje odliczanie, gdy wpisany czas okazał się zły — konto zostaje.",
                        "The clock with a cross next to the bin cancels the countdown when the time typed turned out wrong — the account stays."),
                picture: .card),
        Section(title: t("Ustaw reset", "Set the reset"),
                lead: t("Jedno pole: wpisz, za ile okno się otworzy — tak, jak podaje to Claude.",
                        "One field: type how long until the window opens — the way Claude tells you."),
                steps: [t("Przycisk Reset na karcie otwiera pole.", "The Reset button on the card opens the field."),
                        t("Godziny i minuty: 3:30 to trzy i pół godziny; sama liczba to godziny (do 168).",
                          "Hours and minutes: 3:30 is three and a half hours; a bare number is hours (up to 168)."),
                        t("Podgląd: o której będzie reset.", "The preview: when the reset will be."),
                        t("Ustaw albo Return.", "Set, or Return.")],
                more: t("Inne zapisy („4h”, „90m”) program odrzuca, zamiast zgadywać. Pasek na karcie obejmuje dokładnie wpisany czas, więc zaczyna pusty i dochodzi do końca w chwili resetu.",
                        "Other forms (“4h”, “90m”) are refused rather than guessed. The bar on the card spans exactly the time typed, so it starts empty and reaches the end at the reset."),
                picture: .entry),
        Section(title: t("Kolory", "Colours"),
                lead: t("Kolor karty i paska mówi, w jakim stanie jest konto.",
                        "The colour of the card and its bar says what state the account is in."),
                steps: [t("Niebieski — do resetu ponad godzina.", "Blue — more than an hour to the reset."),
                        t("Bursztynowy — mniej niż godzina.", "Amber — less than an hour."),
                        t("Zielony — okno już się otworzyło: Reset czyści licznik i od razu pyta o następny.",
                          "Green — the window is open again: Reset clears the count and asks for the next one at once.")],
                more: nil,
                picture: .states),
        Section(title: t("Limit tygodniowy", "The weekly limit"),
                lead: t("Obok okna sesji konto ma limit tygodniowy. Wpisujesz go raz — wraca co tydzień sam.",
                        "Besides the session window an account has a weekly limit. You type it once — it comes back every week by itself."),
                steps: [t("Przycisk z kalendarzem na karcie.", "The calendar button on the card."),
                        t("Wpisz tak, jak pokazuje Anthropic, np. Sat 12 AM.", "Type it the way Anthropic shows it, such as Sat 12 AM."),
                        t("Podgląd najbliższego resetu; Wyczyść usuwa limit.", "A preview of the next reset; Clear removes the limit.")],
                more: t("Limit tygodniowy ma na karcie własny, fioletowy pasek z odliczaniem — kolor, którego okno sesji nigdy nie używa, więc oba paski łatwo odróżnić.",
                        "The weekly limit has its own purple bar with a countdown on the card — a colour the session window never uses, so the two bars are easy to tell apart."),
                picture: .weekly),
        Section(title: t("Twoje Maki", "Your Macs"),
                lead: t("W Ustawieniach (⚙) zaznaczasz komputery, których używasz.",
                        "In Settings (⚙) you tick the computers you use."),
                steps: [t("Zaznaczone pojawiają się jako przełączniki na każdej karcie.", "The ticked ones show up as toggles on every card.")],
                more: t("Tu też zmienisz język (polski albo angielski, od razu, bez restartu) i włączysz albo wyłączysz sprawdzanie aktualizacji.",
                        "This is also where you change the language (Polish or English, at once, without a restart) and turn update checks on or off."),
                picture: .macs),
    ]

    static let goodToKnow = t("Dobrze wiedzieć", "Good to know")
    static let cards: [Card] = [
        Card(symbol: "icloud", title: t("Wszystkie Twoje Maki", "All your Macs"),
             text: t("Konta jadą przez iCloud Drive: zmiana na jednym Macu po chwili jest na drugim. Zmiany z dwóch Maków łączą się konto po koncie.",
                     "Accounts travel through iCloud Drive: a change on one Mac shows on the other moments later. Changes from two Macs are merged account by account.")),
        Card(symbol: "globe", title: t("Język", "Language"),
             text: t("Polski albo angielski, przełączany w Ustawieniach bez restartu.",
                     "Polish or English, switched in Settings without a restart.")),
        Card(symbol: "power", title: t("Przy starcie", "At login"),
             text: t("„Uruchom przy starcie” na dole panelu dodaje TokenTime do elementów logowania macOS.",
                     "“Start at login” at the bottom of the panel adds TokenTime to the macOS login items.")),
        Card(symbol: "arrow.down.circle", title: t("Aktualizacje", "Updates"),
             text: t("Raz w miesiącu program pyta fractal8.eu o numer najnowszej wersji i nic więcej nie wysyła. Instaluje dopiero po kliknięciu „Zainstaluj”.",
                     "Once a month the app asks fractal8.eu for the newest version number and sends nothing else. It installs only when you click Install.")),
    ]

    static let more = t("Więcej", "More")
    static let less = t("Mniej", "Less")
    /// The line under the Fractal 8 Dev signature — the same as under the title on fractal8.eu.
    static let signatureLine = t("Natywne programy dla macOS, budowane według jednego wzoru.",
                                 "Native macOS software, built to a single pattern.")

    /// Every text of the window, for the check that none is missing a language.
    static var allTexts: [Text] {
        var all = [buttonHelp, windowTitle, title, intro, goodToKnow, more, less, signatureLine]
        for s in sections { all += [s.title, s.lead] + s.steps + (s.more.map { [$0] } ?? []) }
        for c in cards { all += [c.title, c.text] }
        return all
    }
}
