import Foundation

/// Offline checks for Lớp học (3.1.0): timetable expansion and slot coverage (mirror of src/lib/teachingSchedule.js),
/// next lesson per class, Sổ đầu bài defaults, score parsing / formatting and ĐTB, Lịch dạy ranges, Học bạ grouping,
/// decoders, payloads and Vietnamese error wording. Injected fixtures only: no network, credentials or app launch.
@main
struct TeachingChecks {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) { checks += 1; precondition(condition, message) }
        func rejects(_ operation: () throws -> Void, _ message: String) {
            do { try operation(); check(false, message) } catch { check(true, message) }
        }

        // Calendar helpers (UTC, YYYY-MM-DD).
        check(TeachingSchedule.isoWeekday("2026-10-19") == 1 && TeachingSchedule.isoWeekday("2026-10-24") == 6 && TeachingSchedule.isoWeekday("2026-10-25") == 7, "ISO weekday")
        check(TeachingSchedule.addDays("2026-10-30", 3) == "2026-11-02" && TeachingSchedule.addDays("2027-01-01", -1) == "2026-12-31", "addDays")
        check(TeachingSchedule.weekStart("2026-10-28") == "2026-10-26" && TeachingSchedule.weekStart("2026-10-25") == "2026-10-19", "weekStart (Sunday belongs to the week before)")
        check(TeachingSchedule.monthEnd("2027-02-10") == "2027-02-28" && TeachingSchedule.monthEnd("2028-02-01") == "2028-02-29", "monthEnd")
        check(TeachingSchedule.addMonths("2026-12-15", 1) == "2027-01-01" && TeachingSchedule.addMonths("2026-01-31", -1) == "2025-12-01", "addMonths")
        check(TeachingSchedule.displayDate("2026-10-05") == "05/10/2026" && TeachingSchedule.monthTitle("2026-10-05") == "Tháng 10/2026", "Display")

        // Labels and period times (45-minute periods).
        check(TeachingSchedule.periodLabel(session: "morning", period: 3) == "Tiết 3 sáng", "Tiết 3 sáng")
        check(TeachingSchedule.periodLabel(session: "afternoon", period: 1) == "Tiết 1 chiều", "Tiết 1 chiều")
        check(TeachingSchedule.weekdayLabel("2026-10-19") == "Thứ 2" && TeachingSchedule.weekdayLabel("2026-10-23") == "Thứ 6", "Weekday labels")
        check(TeachingSchedule.lessonStartTime(session: "morning", period: 1) == "07:00" && TeachingSchedule.lessonStartTime(session: "afternoon", period: 3) == "15:20", "Start times")
        check(TeachingSchedule.lessonEndTime(session: "morning", period: 5) == "11:15" && TeachingSchedule.lessonEndTime(session: "afternoon", period: 5) == "17:45", "End times")

        // Slot coverage: effectiveFrom ≤ date ≤ effectiveTo (inclusive), open-ended without effectiveTo.
        let year = TeachingYear(id: "y", name: "2026-2027", startDate: "2026-09-05", endDate: "2027-05-31", semester2StartDate: "2027-01-18", locked: false)
        func slot(_ id: String, _ classId: String, _ weekday: Int, _ session: String, _ period: Int, from: String, to: String? = nil, subject: String = "math") -> TimetableSlot {
            TimetableSlot(id: id, classId: classId, weekday: weekday, session: session, period: period, teacherId: "t", subjectId: subject, effectiveFrom: from, effectiveTo: to)
        }
        let s1 = slot("s1", "A", 1, "morning", 1, from: "2026-09-05")
        let s2 = slot("s2", "A", 2, "afternoon", 2, from: "2026-10-01", to: "2026-10-20")
        let s3 = slot("s3", "B", 2, "morning", 3, from: "2026-10-21", subject: "lit")
        check(TeachingSchedule.slotCovers(s2, date: "2026-10-01") && TeachingSchedule.slotCovers(s2, date: "2026-10-20"), "Inclusive bounds")
        check(!TeachingSchedule.slotCovers(s2, date: "2026-09-30") && !TeachingSchedule.slotCovers(s2, date: "2026-10-21"), "Outside bounds")
        check(TeachingSchedule.slotCovers(s1, date: "2027-05-31"), "Open-ended slot")
        let holidays: Set<String> = ["2026-10-27"]
        check(!TeachingSchedule.isTimetableDay("2026-10-27", year: year, holidays: holidays), "Holiday")
        check(!TeachingSchedule.isTimetableDay("2026-10-24", year: year, holidays: holidays), "Weekend")
        check(!TeachingSchedule.isTimetableDay("2026-09-04", year: year, holidays: holidays) && !TeachingSchedule.isTimetableDay("2027-06-01", year: year, holidays: holidays), "Outside the year")

        let lessons = TeachingSchedule.expandLessons([s1, s2, s3], from: "2026-10-19", to: "2026-10-30", year: year, holidays: holidays)
        check(lessons.map { "\($0.date) \($0.classId) \($0.session) \($0.period)" } == [
            "2026-10-19 A morning 1",
            "2026-10-20 A afternoon 2",
            "2026-10-26 A morning 1",
        ], "Expansion skips weekends, the holiday and slots not in effect")
        check(TeachingSchedule.expandLessons([s1], from: "2026-08-01", to: "2026-09-08", year: year, holidays: []).map(\.date) == ["2026-09-07"], "Clipped to the school year")
        check(TeachingSchedule.expandLessons([s1], from: "2026-10-20", to: "2026-10-19", year: year, holidays: []).isEmpty, "Empty range")
        let dayLessons = TeachingSchedule.expandLessons([
            slot("x1", "A", 3, "afternoon", 1, from: "2026-09-05"),
            slot("x2", "B", 3, "morning", 4, from: "2026-09-05"),
            slot("x3", "A", 3, "morning", 2, from: "2026-09-05"),
        ], from: "2026-10-21", to: "2026-10-21", year: year, holidays: [])
        check(dayLessons.map(\.cellKey) == ["morning-2", "morning-4", "afternoon-1"], "Lessons sorted by start time")

        // Next lesson per class: a lesson of today counts until it ends, otherwise the first later day.
        let upcoming = TeachingSchedule.expandLessons([s1, s3], from: "2026-10-26", to: TeachingSchedule.addDays("2026-10-26", 35), year: year, holidays: holidays)
        var next = TeachingSchedule.nextLessonByClass(upcoming, date: "2026-10-26", time: "07:30")
        check(next["A"]?.date == "2026-10-26", "Ongoing lesson stays first")
        next = TeachingSchedule.nextLessonByClass(upcoming, date: "2026-10-26", time: "07:50")
        check(next["A"]?.date == "2026-11-02", "Ended lesson moves to next week")
        check(next["B"]?.date == "2026-11-03", "Holiday on Tue 27/10 skipped for class B")

        let classes = [
            TeachingClass(id: "C", name: "9A10", gradeLevel: 9, status: "active"),
            TeachingClass(id: "B", name: "7A2", gradeLevel: 7, status: "active"),
            TeachingClass(id: "A", name: "6A1", gradeLevel: 6, status: "active"),
            TeachingClass(id: "D", name: "9A2", gradeLevel: 9, status: "active"),
        ]
        let teaching = MyTeaching(year: year, today: "2026-10-26", holidays: holidays, slots: [s1, s3], classes: classes, todayLogs: [])
        let rows = TeachingSchedule.teachingClassRows(teaching, now: (date: "2026-10-26", time: "07:50"))
        check(rows.map(\.teachingClass.id) == ["A", "B", "D", "C"], "Nearest next lesson first, then classes by natural name")
        check(rows[0].subjectIds == ["math"] && rows[2].next == nil, "Subjects and no next lesson")
        check(TeachingSchedule.nextLessonText(rows[2].next, today: "2026-10-26") == "Không còn tiết nào trong 5 tuần tới", "No lesson text")
        check(TeachingSchedule.nextLessonText(upcoming[0], today: "2026-10-26") == "Hôm nay · Tiết 1 sáng · 07:00", "Today text")
        check(TeachingSchedule.nextLessonText(rows[0].next, today: "2026-10-26") == "Thứ 2, 02/11/2026 · Tiết 1 sáng · 07:00", "Later day text")

        // Sổ đầu bài sheet defaults.
        check(TeachingSchedule.defaultLesson(dayLessons, date: "2026-10-21", now: (date: "2026-10-21", time: "09:00"))?.cellKey == "morning-2", "Latest started lesson")
        check(TeachingSchedule.defaultLesson(dayLessons, date: "2026-10-21", now: (date: "2026-10-21", time: "06:30"))?.cellKey == "morning-2", "Before school: first lesson")
        check(TeachingSchedule.defaultLesson(dayLessons, date: "2026-10-21", now: (date: "2026-10-22", time: "06:30"))?.cellKey == "afternoon-1", "Past date: last lesson")
        check(TeachingSchedule.defaultLesson([], date: "2026-10-21", now: (date: "2026-10-21", time: "09:00")) == nil, "No lesson")
        check(TeachingSchedule.lessons(classId: "A", date: "2026-10-26", data: teaching).count == 1 && TeachingSchedule.lessons(classId: "B", date: "2026-10-26", data: teaching).isEmpty, "Lessons of one class on one date")
        check(TeachingSchedule.latestLogDate(today: "2027-07-01", year: year) == "2027-05-31" && TeachingSchedule.latestLogDate(today: "2026-10-26", year: year) == "2026-10-26", "Ngày dạy ≤ today, inside the year")
        check(TeachingSchedule.clamp("2026-08-01", to: year) == "2026-09-05", "Clamp")

        // Học kỳ default from semester2StartDate.
        check(TeachingSchedule.semesterForDate("2027-01-17", semester2StartDate: "2027-01-18") == 1, "HK I before semester 2")
        check(TeachingSchedule.semesterForDate("2027-01-18", semester2StartDate: "2027-01-18") == 2, "HK II from its start")
        check(TeachingSchedule.semesterForDate("2027-03-01", semester2StartDate: "") == 1, "No semester 2 date → HK I")

        // Scores: 0–10, ≤ 2 decimals, comma or dot.
        check(GradeMath.parseScore("8,5") == 8.5 && GradeMath.parseScore("8.25") == 8.25 && GradeMath.parseScore(" 10 ") == 10 && GradeMath.parseScore("0") == 0, "Valid scores")
        for bad in ["10,5", "8,123", "-1", "abc", "", "8,", ",5", "1e1", "100"] {
            check(GradeMath.parseScore(bad) == nil, "Invalid score \(bad)")
        }
        check(GradeMath.formatScore(8) == "8,0" && GradeMath.formatScore(8.1) == "8,1" && GradeMath.formatScore(8.25) == "8,25" && GradeMath.formatScore(nil) == "—", "vi-VN score format")
        check(GradeMath.editText(8.5) == "8,5" && GradeMath.editText(9) == "9" && GradeMath.editText(7.25) == "7,25", "Edit text")

        // ĐTB example: (8 + 7,5 + 9 + 2 × 8) / 5 = 8,1.
        let semester = GradeMath.semesterAverage([(8, 1), (7.5, 1), (9, 1), (8, 2)])
        check(semester == 8.1 && GradeMath.formatScore(semester) == "8,1", "ĐTB (8+7,5+9+16)/5 = 8,1")
        check(GradeMath.semesterAverage([]) == nil, "No score → no ĐTB")
        check(GradeMath.yearAverage(8.1, 8.4) == 8.3 && GradeMath.yearAverage(8.1, nil) == nil, "Cả năm = (HK I + 2 × HK II) / 3")
        check(GradeMath.overallAverage([8.1, nil, 7.0]) == 7.6 && GradeMath.overallAverage([nil]) == nil, "ĐTB các môn")
        check(GradeMath.roundAverage(8.25) == 8.3 && GradeMath.roundAverage(8.249) == 8.2, "Round half up to 1 decimal")

        // Lịch dạy ranges.
        let week = ScheduleMode.week.range(anchor: "2026-10-28")
        check(week.from == "2026-10-26" && week.to == "2026-10-30" && week.label == "Tuần 26/10/2026 – 30/10/2026", "Week range")
        let month = ScheduleMode.month.range(anchor: "2026-10-28")
        check(month.from == "2026-10-01" && month.to == "2026-10-31" && month.label == "Tháng 10/2026", "Month range")
        check(ScheduleMode.list.range(anchor: "2026-10-28") == month, "List shows a month")
        check(ScheduleMode.week.shift("2026-10-28", by: -1) == "2026-10-21" && ScheduleMode.month.shift("2026-10-28", by: 1) == "2026-11-01", "Shift")
        let grid = TeachingSchedule.monthGridDates("2026-10-15")
        check(grid.first == "2026-09-28" && grid.last == "2026-10-30" && grid.count % 5 == 0 && !grid.contains("2026-10-03"), "Month grid: Thứ 2–6, padded from Monday")

        // Học bạ grouping and labels.
        let gradebookRows = [
            GradebookClassRow(id: "1", name: "9A10", gradeLevel: 9, rosterCount: 40, isHomeroom: false, subjectIds: ["math"]),
            GradebookClassRow(id: "2", name: "9A2", gradeLevel: 9, rosterCount: 38, isHomeroom: true, subjectIds: []),
            GradebookClassRow(id: "3", name: "6A1", gradeLevel: 6, rosterCount: 41, isHomeroom: true, subjectIds: ["math", "lit"]),
            GradebookClassRow(id: "4", name: "9A5", gradeLevel: 9, rosterCount: 39, isHomeroom: false, subjectIds: []),
        ]
        let groups = GradebookLayout.groups(gradebookRows)
        check(groups.map(\.grade) == [6, 7, 8, 9] && groups[1].classes.isEmpty, "Khối 6–9 always listed")
        check(groups[3].classes.map(\.name) == ["9A2", "9A5", "9A10"], "Natural class order")
        let names = ["math": "Toán", "lit": "Ngữ văn"]
        check(GradebookLayout.classMeta(gradebookRows[2]) { names[$0] ?? "Môn" } == "Chủ nhiệm · Toán, Ngữ văn", "Meta homeroom + subjects")
        check(GradebookLayout.classMeta(gradebookRows[3]) { names[$0] ?? "Môn" } == "39 HS", "Meta roster")
        check(LessonLogSummary.averageRating([4, 5]) == "4,5" && LessonLogSummary.averageRating([]) == nil, "Weekly average")
        check(TeachingSchedule.stars(3) == "★★★☆☆", "Stars")

        // Decoders.
        do {
            let decoded = try TeachingDecoder.myTeaching([
                "year": ["_id": "y", "name": "2026-2027", "startDate": "2026-09-05", "endDate": "2027-05-31", "semester2StartDate": "2027-01-18", "locked": false],
                "today": "2026-10-26",
                "holidays": ["2026-10-27"],
                "slots": [["_id": "s1", "classId": "A", "weekday": 1, "session": "morning", "period": 1, "teacherId": "t", "subjectId": "math", "effectiveFrom": "2026-09-05"]],
                "classes": [["_id": "A", "name": "6A1", "gradeLevel": 6, "status": "active"]],
                "todayLogs": [["_id": "l1", "classId": "A", "date": "2026-10-26", "session": "morning", "period": 1, "rating": 4, "comment": "Tốt"]],
            ])
            check(decoded.slots.first?.effectiveTo == nil && decoded.holidays == ["2026-10-27"] && decoded.className("A") == "6A1", "myTeaching")
            check(decoded.todayLogs.first?.rating == 4 && decoded.year.semester2StartDate == "2027-01-18", "Today logs")
        } catch { check(false, "myTeaching decodes: \(error)") }
        rejects({ _ = try TeachingDecoder.myTeaching(["year": ["_id": "y"], "slots": [["classId": "A", "weekday": 6, "session": "morning", "period": 1, "effectiveFrom": "2026-09-05"]]]) }, "Saturday slot rejected")
        rejects({ _ = try TeachingDecoder.myTeaching(["slots": []]) }, "Missing year rejected")
        do {
            let logs = try TeachingDecoder.classLogs(["items": [["_id": "1", "date": "2026-10-26", "session": "afternoon", "period": 2, "teacherName": "Cô Lan", "subjectName": "Toán", "rating": 5, "comment": "", "createdAt": 1, "updatedAt": 2]]])
            check(logs.count == 1 && logs[0].teacherName == "Cô Lan" && logs[0].updatedAt == 2, "listForClass")
        } catch { check(false, "classLogs decodes") }
        do {
            let overview = try TeachingDecoder.absenceOverview([
                "date": "2026-10-26", "mode": "assigned",
                "classes": [
                    ["_id": "A", "code": "6A1", "name": "6A1", "rosterCount": 41, "saved": true, "counts": ["absent_excused": 2, "absent_unexcused": 1, "absent_pending": 0]],
                    ["_id": "B", "code": "7A2", "name": "", "rosterCount": 38, "saved": false, "counts": [:]],
                ],
                "summary": ["counts": ["absent_excused": 2, "absent_unexcused": 1, "absent_pending": 0]],
            ])
            check(!overview.schoolWide && overview.classes[0].absent == 3 && overview.classes[1].name == "7A2" && !overview.classes[1].saved, "Absence overview")
        } catch { check(false, "absenceOverview decodes") }
        let recordValue: [String: Any] = [
            "student": ["_id": "st", "fullName": "Nguyễn An", "studentCode": "HS01", "dateOfBirth": "2014-03-02"],
            "years": [
                ["_id": "y0", "name": "2025-2026", "semester2StartDate": "", "locked": true, "classId": "c0", "className": "6A1", "gradeLevel": 6],
                ["_id": "y", "name": "2026-2027", "semester2StartDate": "2027-01-18", "locked": false, "classId": "c1", "className": "7A1", "gradeLevel": 7],
            ],
            "yearSummaries": [["schoolYearId": "y0", "semester1": 8.0, "semester2": 8.5, "year": 8.3], ["schoolYearId": "y", "semester1": 8.1, "semester2": NSNull(), "year": NSNull()]],
            "selectedYearId": "y", "selectedClassId": "c1", "fullView": false,
            "subjects": [["_id": "math", "name": "Toán", "active": true], ["_id": "lit", "name": "Ngữ văn", "active": true]],
            "testTypes": [["_id": "tx", "name": "Thường xuyên", "coefficient": 1], ["_id": "gk", "name": "Giữa kỳ", "coefficient": 2]],
            "subjectIds": ["math"], "writableSubjectIds": ["math"],
            "summary": ["subjects": [["subjectId": "math", "semester1": 8.1, "semester2": NSNull(), "year": NSNull()]], "semester1": 8.1, "semester2": NSNull(), "year": NSNull()],
            "entries": [
                ["_id": "e1", "subjectId": "math", "semester": 1, "testTypeId": "tx", "testTypeName": "Thường xuyên", "coefficient": 1, "score": 8, "createdAt": 1, "updatedAt": 1, "enteredByName": "Cô Lan", "canEdit": true],
                ["_id": "e2", "subjectId": "math", "semester": 1, "testTypeId": "gk", "testTypeName": "Giữa kỳ", "coefficient": 2, "score": 8, "createdAt": 2, "updatedAt": 2, "enteredByName": "Thầy Minh", "canEdit": false],
            ],
        ]
        do {
            let record = try TeachingDecoder.studentRecord(recordValue)
            check(record.selectedYear?.className == "7A1" && record.yearSummaries["y0"]?.year == 8.3 && record.yearSummaries["y"]?.year == nil, "Year chips and ĐTB năm")
            check(record.subjectSummaries["math"]?.semester1 == 8.1 && record.summary.semester2 == nil, "Subject summary, null averages")
            check(record.entries(subjectId: "math", semester: 1).count == 2 && record.entries(subjectId: "math", semester: 2).isEmpty, "Entries per semester")
            check(GradebookLayout.scoresText(record.entries(subjectId: "math", semester: 1)) == "8,0 Thường xuyên · 8,0 Giữa kỳ", "Scores text")
            check(record.canAddScore && !record.fullView, "Thêm điểm when writable subjects exist")

            // Payloads.
            let add = try TeachingPayload.addScore(record: record, subjectId: "math", semester: 2, testTypeId: "gk", scoreText: "8,5")
            check(add["classId"] as? String == "c1" && add["score"] as? Double == 8.5 && add["semester"] as? Int == 2 && add["studentId"] as? String == "st", "addEntry payload")
            rejects({ _ = try TeachingPayload.addScore(record: record, subjectId: "lit", semester: 1, testTypeId: "gk", scoreText: "8") }, "Only writable subjects")
            rejects({ _ = try TeachingPayload.addScore(record: record, subjectId: "math", semester: 1, testTypeId: "gk", scoreText: "11") }, "Score above 10")
            let update = try TeachingPayload.updateScore(entry: record.entries[0], semester: 1, testTypeId: "", scoreText: "9.25")
            check(update["testTypeId"] as? String == "tx" && update["score"] as? Double == 9.25 && update["id"] as? String == "e1", "updateEntry keeps a removed test type")
        } catch { check(false, "studentRecord decodes: \(error)") }
        do {
            let students = try TeachingDecoder.classStudents([
                "class": ["_id": "c1", "name": "7A1", "gradeLevel": 7], "year": ["name": "2026-2027"],
                "students": [["_id": "s1", "fullName": "An", "studentCode": "HS01", "dateOfBirth": "", "rosterNumber": NSNull()], ["_id": "s2", "fullName": "Bình", "studentCode": "HS02", "dateOfBirth": "2014-01-01", "rosterNumber": 2]],
            ])
            check(students.students[0].rosterNumber == nil && students.students[1].rosterNumber == 2 && students.yearName == "2026-2027", "classStudents")
        } catch { check(false, "classStudents decodes") }

        let lesson = dayLessons[0]
        rejects({ _ = try TeachingPayload.lessonLog(classId: "A", date: "2026-10-21", lesson: lesson, rating: 0, comment: "") }, "Rating required")
        rejects({ _ = try TeachingPayload.lessonLog(classId: "A", date: "2026-10-21", lesson: lesson, rating: 4, comment: String(repeating: "a", count: 1001)) }, "Comment ≤ 1000")
        if let payload = try? TeachingPayload.lessonLog(classId: "A", date: "2026-10-21", lesson: lesson, rating: 5, comment: "  Lớp sôi nổi  ") {
            check(payload["session"] as? String == "morning" && payload["period"] as? Int == 2 && payload["comment"] as? String == "Lớp sôi nổi", "lessonLogs:save payload")
        } else { check(false, "Valid lesson log payload") }

        // Vietnamese wording (spec §4); never the login "Email hoặc mật khẩu" message.
        let wording: [(String, String)] = [
            ("CHALLENGE_INVALID", "Phiên xác thực đã hết hạn. Vui lòng thử lại."),
            ("DEVICE_CREDENTIAL_INVALID", "Vân tay / Face ID hoặc passkey trên máy này không còn hiệu lực. Đăng nhập bằng mật khẩu rồi bật lại."),
            ("DEVICE_SIGNATURE_INVALID", "Không xác thực được thiết bị."),
            ("PASSKEY_VERIFICATION_FAILED", "Không xác thực được passkey."),
            ("DEVICE_CREDENTIAL_LIMIT", "Tài khoản đã có tối đa 10 thiết bị đăng nhập nhanh."),
            ("LESSON_NOT_SCHEDULED", "Bạn không có tiết này ở lớp vào ngày đã chọn."),
            ("LESSON_IN_FUTURE", "Chưa thể ghi Sổ đầu bài cho tiết chưa diễn ra."),
            ("INVALID_RATING", "Chọn từ 1 đến 5 sao."),
            ("INVALID_SCORE", "Điểm từ 0 đến 10, tối đa 2 chữ số thập phân."),
            ("GRADE_SUBJECT_FORBIDDEN", "Bạn chỉ nhập điểm môn mình dạy ở lớp này."),
            ("GRADEBOOK_FORBIDDEN", "Bạn không phụ trách lớp của học sinh này."),
            ("SCHOOL_YEAR_LOCKED", "Năm học đã khóa."),
            ("TEST_TYPE_NOT_FOUND", "Loại kiểm tra không còn."),
            ("SUBJECT_NOT_FOUND", "Môn học không còn."),
        ]
        for (code, message) in wording {
            let raw = "[Request ID: 1] Server Error\nUncaught Error: \(code)\n    at handler"
            check(ConvexHttpClient.extractCode(raw) == code, "Code \(code)")
            check(ConvexHttpClient.humanize(raw) == message, "Wording \(code)")
            check(ConvexException(code: code).message == message, "Exception wording \(code)")
        }
        check(ConvexHttpClient.humanize("Uncaught Error: INVALID_CREDENTIALS") == "Email hoặc mật khẩu không đúng.", "Password wording unchanged")

        print("TeachingChecks: \(checks) checks passed")
    }
}
