package lvt.crm.data.teaching

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale

/**
 * Học bạ rules mirrored from convex/teachingPolicy.ts (averages) and src/lib/teachingSchedule.js
 * (score input / display). The server stays authoritative; the app only previews and validates input.
 */
object GradeMath {
    private val vietnamese: Locale = Locale.forLanguageTag("vi-VN")

    /**
     * Parses a typed score: comma or dot decimal separator, 0–10, at most 2 decimals ("8,5", "10", "7.25").
     * Returns null when the text is not a valid score.
     */
    fun parseScore(text: String): Double? {
        val normalized = text.trim().replace(',', '.')
        if (normalized.isEmpty() || !normalized.matches(Regex("\\d*\\.?\\d*")) || normalized == ".") return null
        val value = normalized.toBigDecimalOrNull() ?: return null
        if (value < BigDecimal.ZERO || value > BigDecimal.TEN) return null
        if (value.stripTrailingZeros().scale() > 2) return null
        return value.setScale(2, RoundingMode.UNNECESSARY).toDouble()
    }

    /** "8,1", "7,5", "8,25", "10,0"; null → "—" (vi-VN, 1–2 decimals like the web). */
    fun formatScore(value: Double?): String {
        if (value == null || value.isNaN()) return "—"
        val format = DecimalFormat("#,##0.0#", DecimalFormatSymbols.getInstance(vietnamese))
        format.roundingMode = RoundingMode.HALF_UP
        return format.format(value)
    }

    /** Text shown in the score field when editing an existing entry ("8,5"). */
    fun editableScore(value: Double): String =
        BigDecimal.valueOf(value).stripTrailingZeros().toPlainString().replace('.', ',')

    /** Điểm trung bình làm tròn 1 chữ số thập phân (8,25 → 8,3). */
    fun roundAverage(value: Double): Double = Math.round((value + Math.ulp(1.0)) * 10).toDouble() / 10

    /** ĐTB môn học kỳ = Σ(điểm × hệ số) / Σ hệ số. */
    fun semesterAverage(entries: List<Pair<Double, Int>>): Double? {
        var weighted = 0.0
        var weights = 0
        for ((score, coefficient) in entries) {
            weighted += score * coefficient
            weights += coefficient
        }
        return if (weights > 0) roundAverage(weighted / weights) else null
    }

    /** ĐTB cả năm = (HK I + 2 × HK II) / 3, only when both semesters have an average. */
    fun yearAverage(semester1: Double?, semester2: Double?): Double? {
        if (semester1 == null || semester2 == null) return null
        return roundAverage((semester1 + 2 * semester2) / 3)
    }

    /** ĐTB các môn = trung bình cộng ĐTB các môn đã có điểm. */
    fun overallAverage(values: List<Double?>): Double? {
        val present = values.filterNotNull()
        if (present.isEmpty()) return null
        return roundAverage(present.sum() / present.size)
    }
}
