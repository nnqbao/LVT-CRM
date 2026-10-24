package lvt.crm.ui.teaching

import lvt.crm.data.homeroom.HomeroomOverview
import lvt.crm.data.homeroom.SchoolYear
import lvt.crm.data.homeroom.decodeOverview
import lvt.crm.data.teaching.ClassLessonLog
import lvt.crm.data.teaching.ClassStudents
import lvt.crm.data.teaching.GradebookClasses
import lvt.crm.data.teaching.MyLessonLog
import lvt.crm.data.teaching.MyTeaching
import lvt.crm.data.teaching.StudentRecord
import lvt.crm.data.teaching.Subject
import lvt.crm.data.teaching.TeacherSchedule
import lvt.crm.data.teaching.TeachingCatalog
import lvt.crm.data.teaching.TeachingClass
import lvt.crm.data.teaching.TeachingOperations
import lvt.crm.data.teaching.TeachingYear
import lvt.crm.data.teaching.TestType
import lvt.crm.data.teaching.TimetableSlot
import lvt.crm.data.teaching.decodeStudentRecord
import org.json.JSONObject

internal val testYear = TeachingYear("y1", "2026-2027", "2026-09-05", "2027-05-31", "2027-01-11", locked = false)

internal fun testSlot(classId: String, weekday: Int, session: String, period: Int, subjectId: String = "toan") =
    TimetableSlot("$classId-$weekday-$session-$period", classId, weekday, session, period, "t1", subjectId, "2026-09-05")

internal fun testTeaching(todayLogs: List<lvt.crm.data.teaching.TodayLessonLog> = emptyList()) = MyTeaching(
    year = testYear,
    today = "2026-10-21",
    holidays = emptySet(),
    slots = listOf(
        testSlot("c1", 3, "morning", 1),
        testSlot("c1", 3, "morning", 4),
        testSlot("c2", 5, "morning", 2, subjectId = "van"),
        testSlot("c3", 3, "afternoon", 1),
    ),
    classes = listOf(
        TeachingClass("c1", "6A1", 6),
        TeachingClass("c2", "7A2", 7),
        TeachingClass("c3", "8A3", 8),
        TeachingClass("c4", "9A1", 9),
    ),
    todayLogs = todayLogs,
)

internal val testCatalog = TeachingCatalog(
    subjects = listOf(Subject("toan", "Toán"), Subject("van", "Ngữ văn")),
    testTypes = listOf(TestType("m", "Miệng", 1), TestType("gk", "Giữa kỳ", 2)),
)

internal class FakeTeachingOperations : TeachingOperations {
    var teaching = testTeaching()
    val myLogs = mutableMapOf<Pair<String, String>, List<MyLessonLog>>()
    val saved = mutableListOf<List<Any>>()
    val added = mutableListOf<List<Any>>()
    val updated = mutableListOf<List<Any>>()
    val removed = mutableListOf<String>()
    var saveError: Exception? = null
    var recordJson: String = defaultRecordJson

    override suspend fun schoolYears(): List<SchoolYear> = listOf(SchoolYear("y1", "2026-2027", "2026-09-05", "2027-05-31", true))
    override suspend fun myTeaching(schoolYearId: String): MyTeaching = teaching
    override suspend fun catalog(): TeachingCatalog = testCatalog
    override suspend fun homeroomOverview(schoolYearId: String, date: String): HomeroomOverview = decodeOverview(
        JSONObject(
            """{"date":"$date","today":"$date","mode":"teacher","schoolYear":{"_id":"$schoolYearId","name":"2026-2027"},
            "classes":[{"_id":"c1","code":"6A1","name":"6A1","rosterCount":40,"saved":true,"counts":{"present":38,"late":0,"absent_excused":1,"absent_unexcused":1,"no_data":0,"absent_pending":0,"exempt":0}}],
            "schoolDay":{"isSchoolDay":true},"missingUpload":{},
            "summary":{"counts":{"present":38,"late":0,"absent_excused":1,"absent_unexcused":1,"no_data":0,"absent_pending":0,"exempt":0}}}""",
        ),
    )
    override suspend fun myLogsFor(classId: String, date: String): List<MyLessonLog> = myLogs[classId to date].orEmpty()
    override suspend fun saveLessonLog(classId: String, date: String, session: String, period: Int, rating: Int, comment: String) {
        saveError?.let { throw it }
        saved += listOf(classId, date, session, period, rating, comment)
    }
    override suspend fun classLogs(classId: String, from: String, to: String): List<ClassLessonLog> = emptyList()
    override suspend fun schedule(schoolYearId: String): TeacherSchedule =
        TeacherSchedule(testYear, "Cô A", emptySet(), teaching.slots, teaching.classes)
    override suspend fun gradebookClasses(schoolYearId: String): GradebookClasses = GradebookClasses(testYear, emptyList())
    override suspend fun classStudents(classId: String): ClassStudents = ClassStudents(classId, "6A1", 6, "2026-2027", emptyList())
    override suspend fun studentRecord(studentId: String, schoolYearId: String?): StudentRecord = decodeStudentRecord(JSONObject(recordJson))
    override suspend fun addGrade(studentId: String, classId: String, subjectId: String, semester: Int, testTypeId: String, score: Double) {
        added += listOf(studentId, classId, subjectId, semester, testTypeId, score)
    }
    override suspend fun updateGrade(id: String, semester: Int, testTypeId: String, score: Double) {
        updated += listOf(id, semester, testTypeId, score)
    }
    override suspend fun removeGrade(id: String) {
        removed += id
    }

    companion object {
        val defaultRecordJson = """{"student":{"_id":"st1","fullName":"Nguyễn Văn A","studentCode":"HS01"},
            "years":[{"_id":"y1","name":"2026-2027","startDate":"2026-09-05","endDate":"2027-05-31","semester2StartDate":"2027-01-11","locked":false,"classId":"c1","className":"6A1","gradeLevel":6}],
            "yearSummaries":[],"selectedYearId":"y1","selectedClassId":"c1","fullView":true,
            "subjects":[{"_id":"toan","name":"Toán"},{"_id":"van","name":"Ngữ văn"}],
            "testTypes":[{"_id":"m","name":"Miệng","coefficient":1},{"_id":"gk","name":"Giữa kỳ","coefficient":2}],
            "subjectIds":["toan","van"],"writableSubjectIds":["toan"],
            "summary":{"subjects":[],"semester1":null,"semester2":null,"year":null},
            "entries":[{"_id":"g1","subjectId":"toan","semester":1,"testTypeId":"removed","testTypeName":"Cũ","coefficient":1,"score":7.5,"canEdit":true},
                       {"_id":"g2","subjectId":"van","semester":1,"testTypeId":"m","testTypeName":"Miệng","coefficient":1,"score":9,"canEdit":false}]}"""
    }
}
