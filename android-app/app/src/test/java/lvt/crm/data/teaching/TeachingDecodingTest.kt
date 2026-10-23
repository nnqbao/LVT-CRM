package lvt.crm.data.teaching

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TeachingDecodingTest {
    @Test
    fun decodesMyTeaching() {
        val value = JSONObject(
            """{"year":{"_id":"y1","name":"2026-2027","startDate":"2026-09-05","endDate":"2027-05-31","semester2StartDate":"2027-01-11","locked":false},
            "today":"2026-10-21","holidays":["2026-11-20"],
            "slots":[{"_id":"s1","classId":"c1","weekday":3,"session":"morning","period":2,"teacherId":"t1","subjectId":"toan","effectiveFrom":"2026-09-05"},
                     {"_id":"s2","classId":"c2","weekday":5,"session":"afternoon","period":1,"teacherId":"t1","subjectId":"toan","effectiveFrom":"2026-09-05","effectiveTo":"2026-12-31"}],
            "classes":[{"_id":"c1","name":"6A1","gradeLevel":6,"status":"active"}],
            "todayLogs":[{"_id":"l1","classId":"c1","date":"2026-10-21","session":"morning","period":2,"rating":4,"comment":"Tốt"}]}""",
        )
        val data = decodeMyTeaching(value)
        assertEquals("2027-01-11", data.year.semester2StartDate)
        assertEquals(setOf("2026-11-20"), data.holidays)
        assertNull(data.slots[0].effectiveTo)
        assertEquals("2026-12-31", data.slots[1].effectiveTo)
        assertEquals(6, data.classes.single().gradeLevel)
        assertEquals(4, data.todayLogs.single().rating)
    }

    @Test
    fun decodesStudentRecordWithNullAverages() {
        val value = JSONObject(
            """{"student":{"_id":"st1","fullName":"Nguyễn Văn A","studentCode":"HS01","dateOfBirth":null},
            "years":[{"_id":"y1","name":"2026-2027","startDate":"2026-09-05","endDate":"2027-05-31","semester2StartDate":"","locked":true,"classId":"c1","className":"6A1","gradeLevel":6}],
            "yearSummaries":[{"schoolYearId":"y1","semester1":8.1,"semester2":8.1,"year":8.1},{"schoolYearId":"y0","semester1":null,"semester2":null,"year":null}],
            "selectedYearId":"y1","selectedClassId":"c1","fullView":false,
            "subjects":[{"_id":"toan","name":"Toán","active":true}],
            "testTypes":[{"_id":"m","name":"Miệng","coefficient":1}],
            "subjectIds":["toan"],"writableSubjectIds":["toan"],
            "summary":{"subjects":[{"subjectId":"toan","semester1":8.1,"semester2":null,"year":null}],"semester1":8.1,"semester2":null,"year":null},
            "entries":[{"_id":"g1","subjectId":"toan","semester":1,"testTypeId":"m","testTypeName":"Miệng","coefficient":1,"score":8,"createdAt":1,"updatedAt":2,"enteredByName":"Cô B","canEdit":true}]}""",
        )
        val record = decodeStudentRecord(value)
        assertNull(record.student.dateOfBirth)
        assertEquals(8.1, record.yearAverages.getValue("y1")!!, 1e-9)
        assertNull(record.yearAverages.getValue("y0"))
        assertNull(record.yearAverage)
        assertNull(record.summaryFor("toan")?.semester2)
        assertEquals("Toán", record.subjectName("toan"))
        assertTrue(record.entriesFor("toan", 1).single().canEdit)
        assertFalse(record.fullView)
        assertFalse("locked year: no Thêm điểm", record.canAdd)
    }
}
