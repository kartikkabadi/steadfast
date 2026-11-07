import Foundation
import SteadfastCore

/// Everything the Progress page, the block page and the menu bar say about
/// block coverage, computed once from the commitments Steadfast already keeps.
struct ProgressFacts {
    /// Hours with blocks for every day of this year; nil for days still ahead.
    let year: [Double?]
    /// Blocks touching each day of this year.
    let blocks: [Int]
    let today: Int
    let yearStart: Date
    let yearHours: Double
    let weekHours: Double
    /// Index of the aim's deadline when it falls in this year.
    let deadline: Int?
    let calendar: Calendar

    var coveredDays: Int { year.compactMap { $0 }.filter { $0 > 0 }.count }

    var daysLeft: Int { max(0, year.count - today - 1) }
    var hasAny: Bool { yearHours > 0 || blocks.contains { $0 > 0 } }

    func date(ofDay index: Int) -> Date {
        calendar.date(byAdding: .day, value: index, to: yearStart) ?? yearStart
    }

    init(commitments: [Commitment], aim: Aim?, now: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        let start = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
        let count = calendar.range(of: .day, in: .year, for: now)?.count ?? 365
        year = (0..<count).map { index in
            guard let day = calendar.date(byAdding: .day, value: index, to: start),
                  let end = calendar.date(byAdding: .day, value: 1, to: day),
                  day <= now else { return nil }
            return Ledger.coverageHours(commitments, from: day, to: end, now: now)
        }
        blocks = Ledger.blockCounts(commitments, now: now, calendar: calendar)
        today = Ledger.dayIndex(now, calendar: calendar)
        yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
        yearHours = year.compactMap { $0 }.reduce(0, +)
        weekHours = ProgressFacts.week(commitments, now: now, calendar: calendar)
        if let end = aim?.deadline, calendar.isDate(end, equalTo: now, toGranularity: .year) {
            deadline = Ledger.dayIndex(end, calendar: calendar)
        } else {
            deadline = nil
        }
    }

    /// Hours with blocks over the past seven days, today included.
    static func week(_ commitments: [Commitment], now: Date, calendar: Calendar = .current) -> Double {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        return Ledger.coverageHours(commitments, from: start, to: now, now: now)
    }
}

extension Model {
    /// Finished and running blocks with known coverage; browser checks are diagnostics.
    var coverageCommitments: [Commitment] {
        (history + active).filter { !isBrowserCheck($0) }
    }

    var progressFacts: ProgressFacts {
        ProgressFacts(commitments: coverageCommitments, aim: outcomes.aim, now: currentTime)
    }

    var weekCoverageHours: Double {
        ProgressFacts.week(coverageCommitments, now: currentTime)
    }

    /// The earliest running block supplies the purpose for the active view.
    var holdingBlock: Commitment? {
        active.filter { !isBrowserCheck($0) }.min { $0.createdAt < $1.createdAt }
    }
}
