import Testing
import Foundation
@testable import ChelkaCore

@Test func prettifiesAndMinifiesJson() {
    let pretty = try! #require(Transformations.apply(.jsonPretty, to: #"{"b":1,"a":[1,2]}"#))
    #expect(pretty.contains("\n"))
    let minified = try! #require(Transformations.apply(.jsonMinify, to: pretty))
    #expect(!minified.contains("\n"))
    #expect(minified.contains("\"a\""))
}

@Test func jsonTransformsRejectNonJson() {
    #expect(Transformations.apply(.jsonPretty, to: "просто текст") == nil)
    #expect(Transformations.apply(.jsonMinify, to: "{битый") == nil)
}

@Test func base64RoundTripsCyrillic() {
    let encoded = try! #require(Transformations.apply(.base64Encode, to: "привет"))
    #expect(encoded == "0L/RgNC40LLQtdGC")
    #expect(Transformations.apply(.base64Decode, to: encoded) == "привет")
}

@Test func base64DecodeRejectsGarbage() {
    #expect(Transformations.apply(.base64Decode, to: "не base64!!!") == nil)
}

@Test func urlEncodeAndDecode() {
    let encoded = try! #require(Transformations.apply(.urlEncode, to: "a b&c=д"))
    #expect(encoded == "a%20b%26c%3D%D0%B4")
    #expect(Transformations.apply(.urlDecode, to: encoded) == "a b&c=д")
}

@Test func decodesJwtPayload() {
    // {"sub":"1234","name":"Иван"} без подписи — нам нужна только полезная нагрузка.
    let token = "eyJhbGciOiJIUzI1NiJ9."
        + "eyJzdWIiOiIxMjM0IiwibmFtZSI6ItCY0LLQsNC9In0"
        + ".signature"
    let decoded = try! #require(Transformations.apply(.jwtDecode, to: token))
    #expect(decoded.contains("1234"))
    #expect(decoded.contains("Иван"))
}

@Test func jwtDecodeRejectsWrongShape() {
    #expect(Transformations.apply(.jwtDecode, to: "одна.часть") == nil)
    #expect(Transformations.apply(.jwtDecode, to: "a.b.c") == nil)
}

@Test func convertsUnixSecondsAndMilliseconds() {
    #expect(Transformations.apply(.timestampToDate, to: "0")?.hasPrefix("1970-01-01") == true)
    // 13 знаков трактуем как миллисекунды, иначе получим 55-й век.
    #expect(Transformations.apply(.timestampToDate, to: "1755777600000")?.hasPrefix("2025-") == true)
}

@Test func timestampRejectsNonNumeric() {
    #expect(Transformations.apply(.timestampToDate, to: "вчера") == nil)
}

@Test func offersOnlyApplicableTransformations() {
    #expect(Transformations.available(for: #"{"a":1}"#).contains(.jsonPretty))
    #expect(!Transformations.available(for: "обычный текст").contains(.jsonPretty))
    #expect(Transformations.available(for: "1755777600").contains(.timestampToDate))
    #expect(Transformations.available(for: "обычный текст").contains(.base64Encode))
}

@Test func doesNotOfferTransformationsThatChangeNothing() {
    // Пункт, который ничего не меняет, в меню не нужен: экранирование URL
    // «успешно» применяется к простому слову и возвращает его же.
    let plain = Transformations.available(for: "simpleword")
    #expect(!plain.contains(.urlEncode))
    #expect(!plain.contains(.urlDecode))
    // А там, где менять есть что, пункт остаётся.
    #expect(Transformations.available(for: "a b&c").contains(.urlEncode))
    #expect(Transformations.available(for: "a%20b").contains(.urlDecode))
}

@Test func stripFormattingKeepsPlainCharacters() {
    let rtf = try! NSAttributedString(string: "жирный текст")
        .data(from: NSRange(location: 0, length: 12),
              documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    #expect(PlainText.strip(rtf, fallback: "запас") == "жирный текст")
}

@Test func stripFormattingFallsBackWhenDataIsUnusable() {
    #expect(PlainText.strip(nil, fallback: "запас") == "запас")
    #expect(PlainText.strip(Data([0xFF, 0xFE]), fallback: "запас") == "запас")
}
