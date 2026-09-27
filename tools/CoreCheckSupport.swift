#if CORE_CHECKS
import Foundation

// Portable adapters for the assertions used by our XCTest files. Every comparison
// is evaluated, failures retain file/line, and any failure exits the runner nonzero.
// This is not XCTest and does not test the app bundle or XCTest discovery.
class XCTestCase {}
enum CoreChecks {
    static var assertions = 0
    static var failures = 0
    static var tests = 0
    static func fail(_ message: String, file: StaticString, line: UInt) {
        failures += 1
        print("FAIL \(file):\(line): \(message)")
    }
    static func run(_ name: String, _ body: () throws -> Void) {
        let before = start()
        do { try body() } catch { fail("\(name) threw \(error)",file:#filePath,line:#line) }
        report(name, since: before)
    }
    static func runAsync(_ name: String, _ body: () async throws -> Void) async {
        let before = start()
        do { try await body() } catch { fail("\(name) threw \(error)",file:#filePath,line:#line) }
        report(name, since: before)
    }
    private static func start() -> Int { tests += 1; return failures }
    private static func report(_ name: String, since before: Int) { print("\(before == failures ? "PASS" : "FAIL") \(name)") }
    /// One assertion: counts it, and fails with the problem `body` names, or with what it threw.
    static func check(_ message: String, file: StaticString, line: UInt, _ body: () throws -> String?) {
        assertions += 1
        do { if let problem = try body() { fail("\(message) \(problem)",file:file,line:line) } }
        catch { fail("\(message) threw \(error)",file:file,line:line) }
    }
    static func finish() -> Never {
        print("\(tests) test bodies, \(assertions) assertions, \(failures) failures (portable Core runner; not XCTest).")
        exit(failures == 0 ? 0 : 1)
    }
}
func XCTFail(_ message: @autoclosure () -> String = "Failed", file: StaticString = #filePath, line: UInt = #line) { CoreChecks.fail(message(),file:file,line:line) }
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CoreChecks.check(message(),file:file,line:line) { let lhs=try a(), rhs=try b(); return lhs != rhs ? "expected \(rhs), got \(lhs)" : nil }
}
func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CoreChecks.check(message(),file:file,line:line) { try a() == b() ? "values unexpectedly equal" : nil }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CoreChecks.check(message(),file:file,line:line) { try value() ? nil : "expected true" }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(try !value(),message(),file:file,line:line) }
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(try value() == nil,message(),file:file,line:line) }
func XCTAssertNotNil<T>(_ value: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(try value() != nil,message(),file:file,line:line) }
func XCTAssertLessThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(try a() < b(),message(),file:file,line:line) }
func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(try a() > b(),message(),file:file,line:line) }
func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(try a() <= b(),message(),file:file,line:line) }
func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(try a() >= b(),message(),file:file,line:line) }
func XCTAssertEqual<T: FloatingPoint>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, accuracy: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CoreChecks.check(message(),file:file,line:line) { let lhs=try a(), rhs=try b(); return abs(lhs - rhs) <= accuracy ? nil : "expected \(rhs) ± \(accuracy), got \(lhs)" }
}
struct CoreUnwrapError: Error {}
/// The portable runner's stand-in for XCTest's skip. It runs on the host, where every file a
/// test might pin against is readable, so nothing here should ever throw it — but the type has
/// to exist for the test bodies to compile.
struct XCTSkip: Error, CustomStringConvertible {
    let description: String
    init(_ message: String = "") { description = message }
}

func XCTUnwrap<T>(_ value: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    CoreChecks.assertions += 1
    guard let result = try value() else { XCTFail("\(message()) unexpected nil",file:file,line:line); throw CoreUnwrapError() }
    return result
}
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) {
    CoreChecks.assertions += 1
    do { _ = try value(); XCTFail("\(message()) expected an error",file:file,line:line) } catch { handler(error) }
}
#endif
