import Foundation
import XcodeInventoryCore

let scanner = XcodeInventoryScanner()
let snapshot = scanner.scan()

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601

let data = try encoder.encode(snapshot)
if let output = String(data: data, encoding: .utf8) {
    print(output)
}
