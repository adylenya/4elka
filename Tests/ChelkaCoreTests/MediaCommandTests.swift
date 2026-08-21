import Testing
import Foundation
@testable import ChelkaCore

@Test func commandCodesMatchAdapterTable() {
    #expect(MediaCommand.play.rawValue == 0)
    #expect(MediaCommand.pause.rawValue == 1)
    #expect(MediaCommand.toggle.rawValue == 2)
    #expect(MediaCommand.next.rawValue == 4)
    #expect(MediaCommand.previous.rawValue == 5)
}

@Test func lineBufferSplitsChunksIntoWholeLines() {
    var buffer = LineBuffer()
    #expect(buffer.appending(Data("{\"a\":1}\n{\"b\"".utf8)) == ["{\"a\":1}"])
    #expect(buffer.appending(Data(":2}\n".utf8)) == ["{\"b\":2}"])
}

@Test func lineBufferHoldsIncompleteLine() {
    var buffer = LineBuffer()
    #expect(buffer.appending(Data("частичная".utf8)).isEmpty)
}

@Test func lineBufferSkipsEmptyLines() {
    var buffer = LineBuffer()
    #expect(buffer.appending(Data("\n\nx\n".utf8)) == ["x"])
}
