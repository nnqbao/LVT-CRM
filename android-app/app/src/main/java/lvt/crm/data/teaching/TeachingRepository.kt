package lvt.crm.data.teaching

import lvt.crm.data.convex.ConvexHttpClient
import lvt.crm.data.homeroom.HomeroomOverview
import lvt.crm.data.homeroom.HomeroomRepository
import lvt.crm.data.homeroom.SchoolYear
import org.json.JSONArray
import org.json.JSONObject

data class TeachingYear(
    val id: String,
    val name: String,
    val startDate: String,
    val endDate: String,
    val semester2StartDate: String,
    val locked: Boolean,
) {
    val window: YearWindow get() = YearWindow(startDate, endDate)
}

data class TeachingClass(val id: String, val name: String, val gradeLevel: Int?, val status: String = "active")

data class TodayLessonLog(
    val id: String,
    val classId: String,
    val date: String,
    val session: String,
    val period: Int,
    val rating: Int,
    val comment: String,
)

/** `lessonLogs:myTeaching`: own timetable of the year + holidays + own Sổ đầu bài of today. */
data class MyTeaching(
    val year: TeachingYear,
    val today: String,
    val holidays: Set<String>,
    val slots: List<TimetableSlot>,
    val classes: List<TeachingClass>,
    val todayLogs: List<TodayLessonLog>,
)

data class Subject(val id: String, val name: String, val code: String = "", val active: Boolean = true)

data class TestType(val id: String, val name: String, val coefficient: Int, val active: Boolean = true)

data class TeachingCatalog(val subjects: List<Subject>, val testTypes: List<TestType>) {
    fun subjectName(id: String): String = subjects.firstOrNull { it.id == id }?.name ?: "Môn học"
}

data class MyLessonLog(
    val id: String,
    val session: String,
    val period: Int,
    val rating: Int,
    val comment: String,
    val updatedAt: Double,
)

data class ClassLessonLog(
    val id: String,
    val date: String,
    val session: String,
    val period: Int,
    val teacherName: String,
    val subjectName: String,
    val rating: Int,
    val comment: String,
    val createdAt: Double,
    val updatedAt: Double,
)

/** `teachers:schedule` for the signed-in teacher. */
data class TeacherSchedule(
    val year: TeachingYear,
    val teacherName: String,
    val holidays: Set<String>,
    val slots: List<TimetableSlot>,
    val classes: List<TeachingClass>,
)

data class GradebookClass(
    val id: String,
    val name: String,
    val gradeLevel: Int?,
    val rosterCount: Int,
    val isHomeroom: Boolean,
    val subjectIds: List<String>,
)

data class GradebookClasses(val year: TeachingYear, val classes: List<GradebookClass>)

data class GradebookStudent(
    val id: String,
    val fullName: String,
    val studentCode: String,
    val dateOfBirth: String?,
    val rosterNumber: Int?,
)

data class ClassStudents(
    val classId: String,
    val className: String,
    val gradeLevel: Int?,
    val yearName: String,
    val students: List<GradebookStudent>,
)

data class RecordYear(
    val id: String,
    val name: String,
    val startDate: String,
    val endDate: String,
    val semester2StartDate: String,
    val locked: Boolean,
    val classId: String,
    val className: String,
    val gradeLevel: Int?,
)

data class GradeSummary(val subjectId: String, val semester1: Double?, val semester2: Double?, val year: Double?)

data class GradeEntry(
    val id: String,
    val subjectId: String,
    val semester: Int,
    val testTypeId: String,
    val testTypeName: String,
    val coefficient: Int,
    val score: Double,
    val createdAt: Double,
    val updatedAt: Double,
    val enteredByName: String,
    val canEdit: Boolean,
)

/** `gradebook:studentRecord`. Averages may be null. */
data class StudentRecord(
    val student: GradebookStudent,
    val years: List<RecordYear>,
    /** schoolYearId → ĐTB năm (all subjects) for the year chips. */
    val yearAverages: Map<String, Double?>,
    val selectedYearId: String,
    val selectedClassId: String,
    val fullView: Boolean,
    val subjects: List<Subject>,
    val testTypes: List<TestType>,
    val subjectIds: List<String>,
    val writableSubjectIds: List<String>,
    val subjectSummaries: List<GradeSummary>,
    val semester1: Double?,
    val semester2: Double?,
    val yearAverage: Double?,
    val entries: List<GradeEntry>,
) {
    val selectedYear: RecordYear? get() = years.firstOrNull { it.id == selectedYearId }
    fun subjectName(id: String): String = subjects.firstOrNull { it.id == id }?.name ?: "Môn học"
    fun summaryFor(subjectId: String): GradeSummary? = subjectSummaries.firstOrNull { it.subjectId == subjectId }
    fun entriesFor(subjectId: String, semester: Int): List<GradeEntry> =
        entries.filter { it.subjectId == subjectId && it.semester == semester }
    val canAdd: Boolean get() = writableSubjectIds.isNotEmpty() && testTypes.isNotEmpty() && selectedYear?.locked != true
}

interface TeachingOperations {
    suspend fun schoolYears(): List<SchoolYear>
    suspend fun myTeaching(schoolYearId: String): MyTeaching
    suspend fun catalog(): TeachingCatalog
    suspend fun homeroomOverview(schoolYearId: String, date: String): HomeroomOverview
    suspend fun myLogsFor(classId: String, date: String): List<MyLessonLog>
    suspend fun saveLessonLog(classId: String, date: String, session: String, period: Int, rating: Int, comment: String)
    suspend fun classLogs(classId: String, from: String, to: String): List<ClassLessonLog>
    suspend fun schedule(schoolYearId: String): TeacherSchedule
    suspend fun gradebookClasses(schoolYearId: String): GradebookClasses
    suspend fun classStudents(classId: String): ClassStudents
    suspend fun studentRecord(studentId: String, schoolYearId: String?): StudentRecord
    suspend fun addGrade(studentId: String, classId: String, subjectId: String, semester: Int, testTypeId: String, score: Double)
    suspend fun updateGrade(id: String, semester: Int, testTypeId: String, score: Double)
    suspend fun removeGrade(id: String)
}

/** Lớp học (Lớp giảng dạy, Sổ đầu bài, Lịch dạy, Học bạ) over the raw Convex HTTP API. */
class TeachingRepository(
    private val convex: ConvexHttpClient,
    private val homeroom: HomeroomRepository,
) : TeachingOperations {
    override suspend fun schoolYears(): List<SchoolYear> = homeroom.listSchoolYears()

    override suspend fun myTeaching(schoolYearId: String): MyTeaching =
        decodeMyTeaching(convex.query("lessonLogs:myTeaching", JSONObject().put("schoolYearId", schoolYearId)))

    override suspend fun catalog(): TeachingCatalog = decodeCatalog(convex.query("teachingCatalog:catalog"))

    override suspend fun homeroomOverview(schoolYearId: String, date: String): HomeroomOverview =
        homeroom.overview(schoolYearId, date)

    override suspend fun myLogsFor(classId: String, date: String): List<MyLessonLog> =
        decodeMyLogs(
            convex.query("lessonLogs:myLogsFor", JSONObject().put("classId", classId).put("date", date))
                .optJSONArray("items"),
        )

    override suspend fun saveLessonLog(classId: String, date: String, session: String, period: Int, rating: Int, comment: String) {
        convex.mutation(
            "lessonLogs:save",
            JSONObject()
                .put("classId", classId)
                .put("date", date)
                .put("session", session)
                .put("period", period)
                .put("rating", rating)
                .put("comment", comment),
        )
    }

    override suspend fun classLogs(classId: String, from: String, to: String): List<ClassLessonLog> =
        decodeClassLogs(
            convex.query("lessonLogs:listForClass", JSONObject().put("classId", classId).put("from", from).put("to", to))
                .optJSONArray("items"),
        )

    override suspend fun schedule(schoolYearId: String): TeacherSchedule =
        decodeSchedule(convex.query("teachers:schedule", JSONObject().put("schoolYearId", schoolYearId)))

    override suspend fun gradebookClasses(schoolYearId: String): GradebookClasses =
        decodeGradebookClasses(convex.query("gradebook:myClasses", JSONObject().put("schoolYearId", schoolYearId)))

    override suspend fun classStudents(classId: String): ClassStudents =
        decodeClassStudents(convex.query("gradebook:classStudents", JSONObject().put("classId", classId)))

    override suspend fun studentRecord(studentId: String, schoolYearId: String?): StudentRecord {
        val args = JSONObject().put("studentId", studentId)
        if (!schoolYearId.isNullOrBlank()) args.put("schoolYearId", schoolYearId)
        return decodeStudentRecord(convex.query("gradebook:studentRecord", args))
    }

    override suspend fun addGrade(studentId: String, classId: String, subjectId: String, semester: Int, testTypeId: String, score: Double) {
        convex.mutation(
            "gradebook:addEntry",
            JSONObject()
                .put("studentId", studentId)
                .put("classId", classId)
                .put("subjectId", subjectId)
                .put("semester", semester)
                .put("testTypeId", testTypeId)
                .put("score", score),
        )
    }

    override suspend fun updateGrade(id: String, semester: Int, testTypeId: String, score: Double) {
        convex.mutation(
            "gradebook:updateEntry",
            JSONObject().put("id", id).put("semester", semester).put("testTypeId", testTypeId).put("score", score),
        )
    }

    override suspend fun removeGrade(id: String) {
        convex.mutation("gradebook:removeEntry", JSONObject().put("id", id))
    }
}

// ---------------------------------------------------------------- decoding (org.json, by hand)

internal fun decodeTeachingYear(value: JSONObject?): TeachingYear {
    val year = requireNotNull(value) { "Thiếu năm học." }
    val id = year.getString("_id")
    require(id.isNotBlank()) { "Năm học không hợp lệ." }
    return TeachingYear(
        id = id,
        name = year.optString("name"),
        startDate = year.getString("startDate"),
        endDate = year.getString("endDate"),
        semester2StartDate = year.optStringOrNull("semester2StartDate").orEmpty(),
        locked = year.optBoolean("locked", false),
    )
}

internal fun decodeSlot(row: JSONObject): TimetableSlot = TimetableSlot(
    id = row.optString("_id"),
    classId = row.getString("classId"),
    weekday = row.getInt("weekday"),
    session = row.getString("session"),
    period = row.getInt("period"),
    teacherId = row.optString("teacherId"),
    subjectId = row.optString("subjectId"),
    effectiveFrom = row.getString("effectiveFrom"),
    effectiveTo = row.optStringOrNull("effectiveTo"),
)

internal fun decodeTeachingClass(row: JSONObject): TeachingClass = TeachingClass(
    id = row.getString("_id"),
    name = row.optString("name"),
    gradeLevel = row.optNullableInt("gradeLevel"),
    status = row.optString("status", "active"),
)

internal fun decodeMyTeaching(value: JSONObject): MyTeaching = MyTeaching(
    year = decodeTeachingYear(value.optJSONObject("year")),
    today = value.optString("today"),
    holidays = value.optJSONArray("holidays").strings().toSet(),
    slots = value.optJSONArray("slots").objects().map(::decodeSlot),
    classes = value.optJSONArray("classes").objects().map(::decodeTeachingClass),
    todayLogs = value.optJSONArray("todayLogs").objects().map { row ->
        TodayLessonLog(
            id = row.optString("_id"),
            classId = row.optString("classId"),
            date = row.optString("date"),
            session = row.optString("session"),
            period = row.optInt("period"),
            rating = row.optInt("rating"),
            comment = row.optString("comment"),
        )
    },
)

internal fun decodeCatalog(value: JSONObject): TeachingCatalog = TeachingCatalog(
    subjects = value.optJSONArray("subjects").objects().map(::decodeSubject),
    testTypes = value.optJSONArray("testTypes").objects().map(::decodeTestType),
)

private fun decodeSubject(row: JSONObject) = Subject(
    id = row.getString("_id"),
    name = row.optString("name"),
    code = row.optString("code"),
    active = row.optBoolean("active", true),
)

private fun decodeTestType(row: JSONObject) = TestType(
    id = row.getString("_id"),
    name = row.optString("name"),
    coefficient = row.optInt("coefficient", 1),
    active = row.optBoolean("active", true),
)

internal fun decodeMyLogs(array: JSONArray?): List<MyLessonLog> =
    requireNotNull(array) { "Phản hồi Sổ đầu bài không hợp lệ." }.objects().map { row ->
        MyLessonLog(
            id = row.optString("_id"),
            session = row.getString("session"),
            period = row.getInt("period"),
            rating = row.optInt("rating"),
            comment = row.optString("comment"),
            updatedAt = row.optDouble("updatedAt", 0.0),
        )
    }

internal fun decodeClassLogs(array: JSONArray?): List<ClassLessonLog> =
    requireNotNull(array) { "Phản hồi Sổ đầu bài không hợp lệ." }.objects().map { row ->
        ClassLessonLog(
            id = row.optString("_id"),
            date = row.getString("date"),
            session = row.getString("session"),
            period = row.getInt("period"),
            teacherName = row.optString("teacherName"),
            subjectName = row.optString("subjectName"),
            rating = row.optInt("rating"),
            comment = row.optString("comment"),
            createdAt = row.optDouble("createdAt", 0.0),
            updatedAt = row.optDouble("updatedAt", 0.0),
        )
    }

internal fun decodeSchedule(value: JSONObject): TeacherSchedule = TeacherSchedule(
    year = decodeTeachingYear(value.optJSONObject("year")),
    teacherName = value.optJSONObject("teacher")?.optString("name").orEmpty(),
    holidays = value.optJSONArray("holidays").strings().toSet(),
    slots = value.optJSONArray("slots").objects().map(::decodeSlot),
    classes = value.optJSONArray("classes").objects().map(::decodeTeachingClass),
)

internal fun decodeGradebookClasses(value: JSONObject): GradebookClasses = GradebookClasses(
    year = decodeTeachingYear(value.optJSONObject("year")),
    classes = value.optJSONArray("classes").objects().map { row ->
        GradebookClass(
            id = row.getString("_id"),
            name = row.optString("name"),
            gradeLevel = row.optNullableInt("gradeLevel"),
            rosterCount = row.optInt("rosterCount"),
            isHomeroom = row.optBoolean("isHomeroom", false),
            subjectIds = row.optJSONArray("subjectIds").strings(),
        )
    },
)

private fun decodeStudent(row: JSONObject) = GradebookStudent(
    id = row.getString("_id"),
    fullName = row.optString("fullName"),
    studentCode = row.optString("studentCode"),
    dateOfBirth = row.optStringOrNull("dateOfBirth"),
    rosterNumber = row.optNullableInt("rosterNumber"),
)

internal fun decodeClassStudents(value: JSONObject): ClassStudents {
    val klass = value.getJSONObject("class")
    return ClassStudents(
        classId = klass.getString("_id"),
        className = klass.optString("name"),
        gradeLevel = klass.optNullableInt("gradeLevel"),
        yearName = value.optJSONObject("year")?.optString("name").orEmpty(),
        students = value.optJSONArray("students").objects().map(::decodeStudent),
    )
}

internal fun decodeStudentRecord(value: JSONObject): StudentRecord {
    val summary = value.optJSONObject("summary") ?: JSONObject()
    return StudentRecord(
        student = decodeStudent(value.getJSONObject("student")),
        years = value.optJSONArray("years").objects().map { row ->
            RecordYear(
                id = row.getString("_id"),
                name = row.optString("name"),
                startDate = row.optString("startDate"),
                endDate = row.optString("endDate"),
                semester2StartDate = row.optStringOrNull("semester2StartDate").orEmpty(),
                locked = row.optBoolean("locked", false),
                classId = row.optString("classId"),
                className = row.optString("className"),
                gradeLevel = row.optNullableInt("gradeLevel"),
            )
        },
        yearAverages = value.optJSONArray("yearSummaries").objects().associate { row ->
            row.optString("schoolYearId") to row.optNullableDouble("year")
        },
        selectedYearId = value.optString("selectedYearId"),
        selectedClassId = value.optString("selectedClassId"),
        fullView = value.optBoolean("fullView", false),
        subjects = value.optJSONArray("subjects").objects().map(::decodeSubject),
        testTypes = value.optJSONArray("testTypes").objects().map(::decodeTestType),
        subjectIds = value.optJSONArray("subjectIds").strings(),
        writableSubjectIds = value.optJSONArray("writableSubjectIds").strings(),
        subjectSummaries = summary.optJSONArray("subjects").objects().map { row ->
            GradeSummary(
                subjectId = row.optString("subjectId"),
                semester1 = row.optNullableDouble("semester1"),
                semester2 = row.optNullableDouble("semester2"),
                year = row.optNullableDouble("year"),
            )
        },
        semester1 = summary.optNullableDouble("semester1"),
        semester2 = summary.optNullableDouble("semester2"),
        yearAverage = summary.optNullableDouble("year"),
        entries = value.optJSONArray("entries").objects().map { row ->
            GradeEntry(
                id = row.getString("_id"),
                subjectId = row.optString("subjectId"),
                semester = row.optInt("semester", 1),
                testTypeId = row.optString("testTypeId"),
                testTypeName = row.optString("testTypeName"),
                coefficient = row.optInt("coefficient", 1),
                score = row.getDouble("score"),
                createdAt = row.optDouble("createdAt", 0.0),
                updatedAt = row.optDouble("updatedAt", 0.0),
                enteredByName = row.optString("enteredByName"),
                canEdit = row.optBoolean("canEdit", false),
            )
        },
    )
}

private fun JSONObject.optStringOrNull(name: String): String? =
    if (!has(name) || isNull(name)) null else optString(name).takeIf { it.isNotBlank() }

private fun JSONObject.optNullableInt(name: String): Int? =
    if (!has(name) || isNull(name)) null else optInt(name)

private fun JSONObject.optNullableDouble(name: String): Double? =
    if (!has(name) || isNull(name)) null else optDouble(name).takeIf { !it.isNaN() }

private fun JSONArray?.objects(): List<JSONObject> = buildList {
    val array = this@objects ?: return@buildList
    for (index in 0 until array.length()) add(array.getJSONObject(index))
}

private fun JSONArray?.strings(): List<String> = buildList {
    val array = this@strings ?: return@buildList
    for (index in 0 until array.length()) array.optString(index).takeIf { it.isNotBlank() }?.let(::add)
}
