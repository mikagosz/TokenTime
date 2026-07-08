# TokenTime

Aplikacja menu bar dla macOS (SwiftUI, `MenuBarExtra`) do śledzenia czasu resetu
tokenów na dowolnej liczbie kont Anthropic. Klik w ikonę w pasku → okno z listą kont
i odliczaniem.

## Funkcje

- Lista kont z edytowalną nazwą (dwuklik lub ołówek), dodawanie i usuwanie
- Ustawianie resetu przez popover z jednym polem tekstowym: `4h`, `1h30m`,
  `90m`, `45s` (samo `4` = 4 godziny), z podglądem godziny i walidacją formatu
- Natywne odliczanie (`Text(timerInterval:)`), bez ręcznych timerów w oknie
- Kolory statusu: niebieski (biegnie, > 1h), bursztyn (< 1h),
  **zielony = gotowe** (po resecie karta świeci się na zielono, czeka na Reset)
- Kliknięcie „Reset” czyści licznik i od razu otwiera pole na nowy czas
- Pasek postępu zsynchronizowany ze statusem
- Etykieta w pasku menu pokazuje najkrótszy aktywny countdown (odświeżana co 30 s)
- Opcja „Uruchom przy starcie” (`SMAppService`, macOS 13+)
- Dane trzymane lokalnie w `UserDefaults` (JSON), przeżywają restart

## Uwagi techniczne

- Aplikacja **nie jest sandboksowana** i nie jest przeznaczona do App Store.
- Ikona nie pojawia się w Docku — `setActivationPolicy(.accessory)` w `AppDelegate`,
  więc nie jest potrzebna edycja `Info.plist`.
- Stan zarządzany makrem `@Observable` (bez frameworka Combine).

## Struktura

| Plik | Rola |
|------|------|
| `ContentView.swift` | `@main` App z `MenuBarExtra` + `AppDelegate` |
| `Account.swift` | model konta, status i wielkości pochodne |
| `AccountStore.swift` | przechowywanie kont + autozapis |
| `MenuBarView.swift` | główny panel |
| `AccountCardView.swift` | karta pojedynczego konta |
| `MenuBarLabel.swift` | etykieta w pasku menu |
| `LaunchAtLogin.swift` | uruchamianie przy logowaniu |
