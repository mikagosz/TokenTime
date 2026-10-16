import Foundation
import Testing
@testable import TokenTime

// MARK: - Adres tokentime://
//
// The only way to set a reset without the panel. What matters: the same duration
// rules as the field on the card, and nothing done on a malformed address.

@Suite("URLCommand")
struct URLCommandTests {

    private func parse(_ text: String) -> Result<URLCommand, URLCommand.ParseError> {
        URLCommand.parse(URL(string: text)!)
    }

    @Test("Reset: konto i czas H:MM")
    func reset() {
        #expect(parse("tokentime://reset?konto=praca&za=2:44") == .success(.reset(account: "praca", interval: 2 * 3600 + 44 * 60)))
        #expect(parse("tokentime://reset?account=Praca&in=3") == .success(.reset(account: "Praca", interval: 3 * 3600)))
        #expect(parse("TOKENTIME://RESET?KONTO=dom&ZA=0:30") == .success(.reset(account: "dom", interval: 30 * 60)))
        #expect(parse("tokentime:reset?konto=Nowe%20konto&za=1:05") == .success(.reset(account: "Nowe konto", interval: 3900)))
    }

    @Test("Zły czas, brak konta, obcy schemat albo nieznane polecenie — nic")
    func rejected() {
        #expect(parse("tokentime://reset?konto=praca&za=2h44m") == .failure(.badDuration("2h44m")))
        #expect(parse("tokentime://reset?konto=praca&za=0:00") == .failure(.badDuration("0:00")))
        #expect(parse("tokentime://reset?konto=praca&za=999:00") == .failure(.badDuration("999:00")))
        #expect(parse("tokentime://reset?konto=praca") == .failure(.badDuration("")))
        #expect(parse("tokentime://reset?za=2:44") == .failure(.missingAccount))
        #expect(parse("tokentime://reset?konto=%20&za=2:44") == .failure(.missingAccount))
        #expect(parse("https://reset?konto=praca&za=2:44") == .failure(.notTokenTime))
        #expect(parse("tokentime://delete?konto=praca") == .failure(.unknownCommand("delete")))
    }
}
