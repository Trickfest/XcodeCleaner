enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case cleanup
    case automation
    case reports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .cleanup:
            return "Cleanup"
        case .automation:
            return "Automation"
        case .reports:
            return "Reports"
        }
    }

    var symbol: String {
        switch self {
        case .overview:
            return "gauge.with.dots.needle.50percent"
        case .cleanup:
            return "trash"
        case .automation:
            return "clock.arrow.circlepath"
        case .reports:
            return "doc.text"
        }
    }
}
