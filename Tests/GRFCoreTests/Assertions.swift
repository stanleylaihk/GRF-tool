import Testing

// Keep fixture-oriented tests readable without depending on the Xcode-only XCTest overlay.
func expectEqual<T: Equatable>(_ value: @autoclosure () throws -> T,
                                  _ expected: @autoclosure () throws -> T,
                                  _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    do {
        let actual = try value(), target = try expected()
        #expect(actual == target, Comment(rawValue: message), sourceLocation: sourceLocation)
    } catch { Issue.record(error, sourceLocation: sourceLocation) }
}
func expectTrue(_ value: @autoclosure () throws -> Bool,
                   _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    do {
        let result = try value()
        #expect(result, Comment(rawValue: message), sourceLocation: sourceLocation)
    } catch { Issue.record(error, sourceLocation: sourceLocation) }
}
func expectFalse(_ value: @autoclosure () throws -> Bool,
                    _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    do {
        let result = try value()
        #expect(!result, Comment(rawValue: message), sourceLocation: sourceLocation)
    } catch { Issue.record(error, sourceLocation: sourceLocation) }
}
func expectGreaterThanOrEqual<T: Comparable>(_ value: T, _ expected: T,
                                               sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value >= expected, sourceLocation: sourceLocation)
}
func expectThrowsError<T>(_ value: @autoclosure () throws -> T, _ message: String = "",
                            sourceLocation: SourceLocation = #_sourceLocation, _ inspect: (Error) -> Void = { _ in }) {
    do {
        _ = try value()
        Issue.record(Comment(rawValue: "Expected an error. " + message), sourceLocation: sourceLocation)
    } catch { inspect(error) }
}
func requireValue<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T {
    try #require(value, sourceLocation: sourceLocation)
}
func recordFailure(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
    Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
}
