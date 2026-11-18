package lvt.crm.ui.homeroom

import java.text.NumberFormat
import java.time.DayOfWeek
import java.time.LocalDate
import java.util.Locale
import lvt.crm.data.homeroom.AttendanceCounts
import lvt.crm.data.homeroom.HomeroomClassSummary

/** Visual meaning of a chip or stat tile; mapped to DESIGN.md status colors in the UI layer. */
enum class HomeroomTone { Success, Warning, Danger, Neutral, Info }

data class HomeroomChip(val text: String, val tone: HomeroomTone)

data class HomeroomStat(val value: String, val label: String, val tone: HomeroomTone)

/** Teacher-facing wording and status summaries for Lớp chủ nhiệm. Pure Kotlin so it is unit-testable. */
object HomeroomPresentation {
    private val vietnamese = Locale.forLanguageTag("vi-VN")
    private val absentStatuses = setOf("absent_pending", "absent_excused", "absent_unexcused")

    fun number(value: Int): String = NumberFormat.getIntegerInstance(vietnamese).format(value)

    fun classTitle(row: HomeroomClassSummary): String = row.name.ifBlank { "Lớp ${row.code}" }

    fun classSubtitle(row: HomeroomClassSummary): String =
        "${row.rosterCount} HS · ${row.teacherName.ifBlank { "Chưa có GVCN" }}"

    /** One main status chip; no chips on days that need no attendance. */
    fun classChips(row: HomeroomClassSummary, schoolDay: Boolean): List<HomeroomChip> {
        if (!schoolDay) return emptyList()
        if (!row.saved && !row.published) return listOf(HomeroomChip("Chưa điểm danh", HomeroomTone.Warning))
        val counts = row.counts
        val main = when {
            counts.absent > 0 -> HomeroomChip("${counts.absent} vắng", HomeroomTone.Danger)
            counts.late > 0 -> HomeroomChip("${counts.late} trễ", HomeroomTone.Warning)
            counts.noData > 0 -> HomeroomChip("${counts.noData} chưa có", HomeroomTone.Neutral)
            else -> HomeroomChip("Đủ ${counts.present + counts.exempt}/${row.rosterCount}", HomeroomTone.Success)
        }
        return listOf(main)
    }

    fun overviewStats(counts: AttendanceCounts): List<HomeroomStat> = listOf(
        HomeroomStat(number(counts.present), "Có mặt", HomeroomTone.Success),
        HomeroomStat(number(counts.late), "Trễ", HomeroomTone.Warning),
        HomeroomStat(number(counts.absent), "Vắng", HomeroomTone.Danger),
        HomeroomStat(number(counts.noData), "Chưa có", HomeroomTone.Neutral),
    )

    fun overviewSummary(studentCount: Int, classCount: Int, attendanceRate: Double, ratedRows: Int): String {
        val base = "${number(classCount)} lớp · ${number(studentCount)} học sinh"
        if (ratedRows <= 0) return base
        val rate = String.format(vietnamese, "%.1f", attendanceRate * 100)
        return "Chuyên cần $rate% · $base"
    }

    /** "Thứ Sáu, 09/10" for an ISO date; falls back to the raw value when it does not parse. */
    fun dayTitle(isoDate: String): String = runCatching {
        val date = LocalDate.parse(isoDate)
        val weekday = when (date.dayOfWeek) {
            DayOfWeek.MONDAY -> "Thứ Hai"
            DayOfWeek.TUESDAY -> "Thứ Ba"
            DayOfWeek.WEDNESDAY -> "Thứ Tư"
            DayOfWeek.THURSDAY -> "Thứ Năm"
            DayOfWeek.FRIDAY -> "Thứ Sáu"
            DayOfWeek.SATURDAY -> "Thứ Bảy"
            else -> "Chủ Nhật"
        }
        "%s, %02d/%02d".format(weekday, date.dayOfMonth, date.monthValue)
    }.getOrDefault(isoDate)

    fun shiftDay(isoDate: String, days: Long): String =
        runCatching { LocalDate.parse(isoDate).plusDays(days).toString() }.getOrDefault(isoDate)

    /** Full Vietnamese label of an effective status (legacy Đi trễ / Vắng chờ xử lý still render). */
    fun statusLabel(status: String): String = when (status) {
        "present" -> "Có mặt"
        "late" -> "Đi trễ"
        "absent_excused" -> "Vắng có phép"
        "absent_unexcused" -> "Vắng không phép"
        "absent_pending" -> "Vắng chờ xử lý"
        "exempt" -> "Miễn điểm danh"
        else -> "Chưa có dữ liệu"
    }

    fun isAbsentStatus(status: String): Boolean = status in absentStatuses

    fun studentChip(status: String, observedTime: String?): HomeroomChip = when {
        status == "present" -> HomeroomChip("Có mặt", HomeroomTone.Success)
        status == "late" -> HomeroomChip(observedTime?.let { "Đi trễ $it" } ?: "Đi trễ", HomeroomTone.Warning)
        status == "absent_excused" -> HomeroomChip("Vắng có phép", HomeroomTone.Info)
        status == "absent_unexcused" -> HomeroomChip("Vắng không phép", HomeroomTone.Danger)
        status == "absent_pending" -> HomeroomChip("Vắng chờ xử lý", HomeroomTone.Warning)
        status == "exempt" -> HomeroomChip("Miễn", HomeroomTone.Info)
        else -> HomeroomChip("Chưa có", HomeroomTone.Neutral)
    }

    /** Có mặt (incl. late) / Có phép / Không phép tiles; Chờ xử lý / Chưa có only when present in the day. */
    fun dailyStats(statuses: List<String>): List<HomeroomStat> {
        val pending = statuses.count { it == "absent_pending" }
        val noData = statuses.count { it == "no_data" }
        return buildList {
            add(HomeroomStat(number(statuses.count { it == "present" || it == "late" }), "Có mặt", HomeroomTone.Success))
            add(HomeroomStat(number(statuses.count { it == "absent_excused" }), "Có phép", HomeroomTone.Info))
            add(HomeroomStat(number(statuses.count { it == "absent_unexcused" }), "Không phép", HomeroomTone.Danger))
            if (pending > 0) add(HomeroomStat(number(pending), "Chờ xử lý", HomeroomTone.Warning))
            if (noData > 0) add(HomeroomStat(number(noData), "Chưa có", HomeroomTone.Neutral))
        }
    }

    /** Absent students first (roster order kept), then everybody else. Mirrors web attendanceDay.js. */
    fun <T> splitAbsentFirst(rows: List<T>, raw: (T) -> String?, status: (T) -> String?): Pair<List<T>, List<T>> =
        rows.partition { raw(it) == "absent" || (status(it) ?: "") in absentStatuses }

    /** Checkbox "Vắng không phép": checked → unexcused; unchecked → excused (legacy pending too). */
    fun nextDispositionForToggle(checked: Boolean): String = if (checked) "unexcused" else "excused"

    /** Neither a saved marker nor any day row: Giám thị has not marked this class yet. */
    fun classNotMarked(classSaved: Boolean, published: Boolean): Boolean = !classSaved && !published

    fun notMarkedMessage(date: String, today: String): String =
        if (date == today) "Giám thị chưa điểm danh lớp này hôm nay."
        else "Giám thị chưa điểm danh lớp này ngày ${formatDate(date)}."
}
