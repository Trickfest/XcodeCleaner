import Foundation
import XcodeInventoryCore

enum CLIProgressMode: Equatable {
    case none
    case bar
    case lines
}

final class CLIProgressRenderer {
    private let mode: CLIProgressMode
    private let terminalColumnsProvider: () -> Int?
    private let writeToStandardError: (String) -> Void

    private var lastPercent: Int = -1
    private var lastPhase: ScanPhase?
    private var lastMessage: String = ""
    private var previousLineLength = 0
    private var completed = false

    init(
        suppressProgress: Bool,
        stderrIsTTY: Bool,
        terminalColumnsProvider: @escaping () -> Int?,
        environment: [String: String],
        writeToStandardError: @escaping (String) -> Void
    ) {
        self.mode = CLIProgressRenderer.selectMode(
            suppressProgress: suppressProgress,
            stderrIsTTY: stderrIsTTY,
            environment: environment
        )
        self.terminalColumnsProvider = terminalColumnsProvider
        self.writeToStandardError = writeToStandardError
    }

    func handle(progress: ScanProgress) {
        if completed || mode == .none {
            return
        }

        let percent = Int((progress.fractionCompleted * 100).rounded())
        guard percent != lastPercent || progress.phase != lastPhase || progress.message != lastMessage else {
            return
        }

        lastPercent = percent
        lastPhase = progress.phase
        lastMessage = progress.message

        switch mode {
        case .none:
            return
        case .lines:
            writeToStandardError(lineFormat(percent: percent, progress: progress))
        case .bar:
            writeToStandardError(barFormat(percent: percent, progress: progress))
        }

        if percent >= 100 {
            finish()
        }
    }

    func finish() {
        guard !completed else {
            return
        }
        completed = true

        if mode == .bar {
            if previousLineLength > 0 {
                writeToStandardError("\n")
            }
            previousLineLength = 0
        }
    }

    private func lineFormat(percent: Int, progress: ScanProgress) -> String {
        String(format: "[%3d%%] %@ - %@\n", percent, progress.phase.title, progress.message)
    }

    private func barFormat(percent: Int, progress: ScanProgress) -> String {
        let columns = max(60, terminalColumnsProvider() ?? 80)
        let prefix = String(format: "%3d%% ", percent)
        let minimumSuffix = " \(progress.phase.title)"

        let fullWidthBar = max(12, columns - prefix.count - minimumSuffix.count - 6)
        let maxBarWidth = max(10, fullWidthBar / 2)
        let filledWidth = Int((Double(maxBarWidth) * progress.fractionCompleted).rounded(.down))
        let barBody: String
        if filledWidth >= maxBarWidth {
            barBody = String(repeating: "=", count: maxBarWidth)
        } else {
            let head = max(0, filledWidth - 1)
            let tail = max(0, maxBarWidth - filledWidth)
            barBody = String(repeating: "=", count: head) + ">" + String(repeating: "-", count: tail)
        }

        let base = "\(prefix)[\(barBody)]"
        let phaseAndMessage = "\(progress.phase.title): \(progress.message)"
        let maxSuffixLength = max(10, columns - base.count - 1)
        let suffix = truncate(phaseAndMessage, maxLength: maxSuffixLength)
        let line = "\(base) \(suffix)"
        let padded = line + String(repeating: " ", count: max(0, previousLineLength - line.count))
        previousLineLength = line.count
        return "\r\(padded)"
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else {
            return text
        }
        guard maxLength > 3 else {
            return String(text.prefix(maxLength))
        }
        return String(text.prefix(maxLength - 3)) + "..."
    }

    private static func selectMode(
        suppressProgress: Bool,
        stderrIsTTY: Bool,
        environment: [String: String]
    ) -> CLIProgressMode {
        if suppressProgress {
            return .none
        }

        if stderrIsTTY {
            let term = (environment["TERM"] ?? "").lowercased()
            if term == "dumb" {
                return .lines
            }
            return .bar
        }
        return .lines
    }
}
