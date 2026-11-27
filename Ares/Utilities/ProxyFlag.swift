import Foundation

nonisolated enum ProxyFlag {
    enum Segment: Equatable {
        case text(String)
        case flag(String)
    }

    private static let subdivisions: [Character: String] = [
        "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}": "GB-ENG",
        "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}": "GB-SCT",
        "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}": "GB-WLS"
    ]

    static func regionCode(for character: Character) -> String? {
        let scalars = character.unicodeScalars
        guard scalars.count == 2, scalars.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) }) else { return nil }
        return String(decoding: scalars.map { UInt8($0.value - 0x1F1E6 + 65) }, as: UTF8.self)
    }

    static func segments(in name: String) -> [Segment] {
        var result: [Segment] = []
        var text = ""
        for character in name {
            guard let code = regionCode(for: character) ?? subdivisions[character] else {
                text.append(character)
                continue
            }
            if !text.isEmpty { result.append(.text(text)); text = "" }
            result.append(.flag(code))
        }
        if !text.isEmpty { result.append(.text(text)) }
        return result
    }

    static func plainName(_ name: String) -> String {
        segments(in: name).map { segment in
            switch segment {
            case .text(let text): text
            case .flag(let code): "[\(code)]"
            }
        }.joined()
    }
}
