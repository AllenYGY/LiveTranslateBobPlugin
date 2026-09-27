import Foundation

@main
struct AssemblerTests {
    static func main() {
        var assembler = LiveUtteranceAssembler()
        let first = assembler.consume(TranscriptResult(transcript: "Hello", translatedText: nil, isFinal: false))
        precondition(first.displayText == "Hello")
        precondition(first.committedText == nil)
        let stable = assembler.consume(TranscriptResult(transcript: "Hello", translatedText: nil, isFinal: true))
        precondition(stable.displayText == "Hello")
        let final = assembler.consume(TranscriptResult(transcript: "class.", translatedText: nil, isFinal: true, speechFinal: true))
        precondition(final.committedText == "Hello class.")
        let next = assembler.consume(TranscriptResult(transcript: "Next topic", translatedText: nil, isFinal: false))
        precondition(next.startedNewUtterance)
        _ = assembler.consume(TranscriptResult(transcript: "Next topic", translatedText: nil, isFinal: true))
        precondition(assembler.flush() == "Next topic")
        print("Assembler tests passed")
    }
}
