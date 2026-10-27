import Foundation

/// Visual meaning of a chip or stat tile; mapped to DESIGN.md status colors in the UI layer.
enum HomeroomTone: Equatable, Sendable { case success, warning, danger, neutral, info }

struct HomeroomChip: Equatable, Sendable {
    let text: String
    let tone: HomeroomTone
}

struct HomeroomStat: Equatable, Sendable {
    let value: String
    let label: String
    let tone: HomeroomTone
}

/// Teacher-facing wording and status summaries for Lớp chủ nhiệm (Foundation only, so it is checkable offline).
enum HomeroomPresentation {
    private static let absentStatuses: Set<String> = ["absent_pending", "absent_excused", "absent_unexcused"]
    private static let vietnamese = Locale(identifier: "vi_VN")

    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = vietnamese
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func classTitle(_ row: HomeroomClassSummary) -> String {
        row.name.isEmpty ? "Lớp \(row.code)" : row.name
    }

    static func classSubtitle(_ row: HomeroomClassSummary) -> String {
        "\(row.rosterCount) HS · \(row.teacherName.isEmpty ? "Chưa có GVCN" : row.teacherName)"
    }

    /// One main status chip plus a pending chip; no chips on days that need no attendance.
    static func classChips(_ row: HomeroomClassSummary, schoolDay: Bool) -> [HomeroomChip] {
        guard schoolDay else { return [] }
        guard row.published else { return [HomeroomChip(text: "Chưa điểm danh", tone: .neutral)] }
        let counts = row.counts
        let main: HomeroomChip
        if counts.absent > 0 {
            main = HomeroomChip(text: "\(counts.absent) vắng", tone: .danger)
        } else if counts.late > 0 {
            main = HomeroomChip(text: "\(counts.late) trễ", tone: .warning)
        } else if counts.noData > 0 {
            main = HomeroomChip(text: "\(counts.noData) chưa có", tone: .neutral)
        } else {
            main = HomeroomChip(text: "Đủ \(counts.present + counts.exempt)/\(row.rosterCount)", tone: .success)
        }
        return row.pendingTotal > 0 ? [main, HomeroomChip(text: "\(row.pendingTotal) chờ", tone: .warning)] : [main]
    }

    static func overviewStats(_ counts: AttendanceCounts) -> [HomeroomStat] {
        [
            HomeroomStat(value: number(counts.present), label: "Có mặt", tone: .success),
            HomeroomStat(value: number(counts.late), label: "Trễ", tone: .warning),
            HomeroomStat(value: number(counts.absent), label: "Vắng", tone: .danger),
            HomeroomStat(value: number(counts.noData), label: "Chưa có", tone: .neutral),
        ]
    }

    static func overviewSummary(studentCount: Int, classCount: Int, attendanceRate: Double, ratedRows: Int) -> String {
        let base = "\(number(classCount)) lớp · \(number(studentCount)) học sinh"
        guard ratedRows > 0 else { return base }
        let rate = String(format: "%.1f", attendanceRate * 100).replacingOccurrences(of: ".", with: ",")
        return "Chuyên cần \(rate)% · \(base)"
    }

    /// "Thứ Sáu, 09/10" for a YYYY-MM-DD date; falls back to the raw value when it does not parse.
    static func dayTitle(_ isoDate: String) -> String {
        guard let date = VietnamDate.date(from: isoDate) else { return isoDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = VietnamDate.timeZone
        let parts = calendar.dateComponents([.weekday, .day, .month], from: date)
        let names = ["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"]
        let weekday = names[max(0, min(6, (parts.weekday ?? 1) - 1))]
        return String(format: "%@, %02d/%02d", weekday, parts.day ?? 0, parts.month ?? 0)
    }

    static func shiftDay(_ isoDate: String, by days: Int) -> String {
        guard let date = VietnamDate.date(from: isoDate) else { return isoDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = VietnamDate.timeZone
        guard let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return isoDate }
        return VietnamDate.string(from: shifted)
    }

    /// Web `STATUS_LABELS` (src/homeroom/homeroomLabels.js). Đi trễ / Vắng chờ xử lý are legacy (camera era) but still render.
    static let statusLabels: [String: String] = [
        "present": "Có mặt", "late": "Đi trễ", "absent_excused": "Vắng có phép", "absent_unexcused": "Vắng không phép",
        "absent_pending": "Vắng chờ xử lý", "no_data": "Chưa có dữ liệu", "exempt": "Miễn điểm danh",
    ]

    /// One chip per student with the full status wording (never colour only). Tones follow the --hr-* palette:
    /// excused = blue (info), unexcused = coral (danger), legacy pending/late = gold (warning).
    static func studentChip(status: String, observedTime: String?) -> HomeroomChip {
        switch status {
        case "present": return HomeroomChip(text: "Có mặt", tone: .success)
        case "late": return HomeroomChip(text: observedTime.map { "Đi trễ \($0)" } ?? "Đi trễ", tone: .warning)
        case "absent_excused": return HomeroomChip(text: "Vắng có phép", tone: .info)
        case "absent_unexcused": return HomeroomChip(text: "Vắng không phép", tone: .danger)
        case "absent_pending": return HomeroomChip(text: "Vắng chờ xử lý", tone: .warning)
        case "exempt": return HomeroomChip(text: "Miễn", tone: .info)
        default: return HomeroomChip(text: "Chưa có", tone: .neutral)
        }
    }

    /// Có mặt (incl. legacy Đi trễ) / Vắng có phép / Vắng không phép tiles; legacy Vắng chờ xử lý and Chưa có
    /// only appear when some rows have them (web `hr-att-summary`).
    static func dailyStats(_ statuses: [String]) -> [HomeroomStat] {
        func count(_ keys: Set<String>) -> Int { statuses.filter { keys.contains($0) }.count }
        var tiles = [
            HomeroomStat(value: number(count(["present", "late"])), label: "Có mặt", tone: .success),
            HomeroomStat(value: number(count(["absent_excused"])), label: "Vắng có phép", tone: .info),
            HomeroomStat(value: number(count(["absent_unexcused"])), label: "Vắng không phép", tone: .danger),
        ]
        let pending = count(["absent_pending"])
        if pending > 0 { tiles.append(HomeroomStat(value: number(pending), label: "Vắng chờ xử lý", tone: .warning)) }
        let noData = count(["no_data"])
        if noData > 0 { tiles.append(HomeroomStat(value: number(noData), label: "Chưa có", tone: .neutral)) }
        return tiles
    }

    /// Web `isAbsentRow`: raw absent, or any absent effective status (legacy rows included).
    static func isAbsent(_ day: AttendanceRecord?) -> Bool {
        guard let day else { return false }
        return day.rawObservation == "absent" || absentStatuses.contains(day.effectiveStatus)
    }

    /// Absent students first (roster order kept), then everybody else.
    static func splitAttendance(_ rows: [DailyRow]) -> (absent: [DailyRow], others: [DailyRow]) {
        (rows.filter { isAbsent($0.day) }, rows.filter { !isAbsent($0.day) })
    }

    /// "Vắng không phép" toggle: on = unexcused; off = excused (legacy pending reads as off).
    static func isUnexcused(_ day: AttendanceRecord?) -> Bool { day?.disposition == "unexcused" }
    static func nextDisposition(unexcused: Bool) -> String { unexcused ? "unexcused" : "excused" }

    /// Neither a Giám thị save marker nor any day row: the class has not been marked yet.
    static func classNotMarked(_ daily: ClassDaily) -> Bool { daily.classSaved == nil && !daily.published }

    static func notMarkedMessage(date: String, today: String) -> String {
        date == today
            ? "Giám thị chưa điểm danh lớp này hôm nay."
            : "Giám thị chưa điểm danh lớp này ngày \(VietnamDate.display(date))."
    }

    /// "Giám thị lưu lúc 07:42 · Nguyễn Văn A".
    static func savedByText(_ saved: ClassDaily.ClassSaved) -> String {
        "Giám thị lưu lúc \(clock(saved.savedAt))" + (saved.savedByName.isEmpty ? "" : " · \(saved.savedByName)")
    }

    static func clock(_ milliseconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = VietnamDate.timeZone
        formatter.locale = vietnamese
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
    }
}
