package lvt.crm.ui.profile

data class AppChangelogEntry(
    val version: String,
    val highlights: List<String>,
)

object AppChangelog {
    val entries: List<AppChangelogEntry> = listOf(
        AppChangelogEntry(
            "2.0.0",
            listOf(
                "Công việc do Văn thư/Quản trị tạo phải chọn Người duyệt (Ban giám hiệu) và bấm Gửi duyệt. Người nhận chỉ thấy việc sau khi đủ người duyệt.",
                "Ban giám hiệu có mục Chờ tôi duyệt: bấm Duyệt hoặc Trả lại (bắt buộc ghi lý do). Sau lần duyệt đầu tiên công việc không sửa hoặc xóa được nữa.",
                "Người tạo thấy trạng thái Chờ duyệt / Đã duyệt / Bị trả lại, tiến độ duyệt và lý do trả lại; sửa xong bấm Lưu và gửi duyệt lại.",
                "Ban giám hiệu được tạo công việc cho cấp dưới ở mọi phòng ban và giao cho cả phòng ban. Thông báo Công việc chờ duyệt, đã duyệt, bị trả lại mở đúng công việc.",
                "Mục Bán trú (mở từ Tổng quan): xem danh sách giáo viên tham gia theo kỳ; Văn thư/Quản trị thêm, sửa, xóa kỳ bán trú.",
                "Nút ? trên các màn hình chính mở đúng phần Hướng dẫn sử dụng.",
            ),
        ),
        AppChangelogEntry(
            "1.0.0",
            listOf(
                "Mục mới Điểm danh cho Giám thị: chọn khối Lớp 6–9, mở lớp, tick \"Vắng\" rồi bấm Lưu lớp. Mặc định cả lớp có mặt; nhập bằng Excel dùng bản web.",
                "Lớp chủ nhiệm: GVCN xem cả lớp, học sinh vắng ở đầu danh sách. Vắng mặc định là có phép; tick \"Vắng không phép\" khi cần, không bắt buộc ghi lý do.",
                "Việc của tôi (trong Công việc): ghi việc riêng có hạn chót và giờ nhắc, đánh dấu xong hoặc xóa. Thông báo nhắc việc mở đúng danh sách.",
                "Bỏ chức năng nhập file điểm danh camera và danh sách vắng chờ xử lý.",
            ),
        ),
        AppChangelogEntry(
            "0.24.0",
            listOf(
                "Lịch công tác chung xem theo tuần ngay trên app, mỗi ngày một danh sách. Giáo viên chỉ thấy lịch đã được Ban Giám hiệu duyệt.",
                "Ban Giám hiệu duyệt hoặc trả lại lịch tuần (kèm lý do) trên app; văn thư sửa công tác và nộp duyệt. Bấm thông báo mở đúng tuần.",
            ),
        ),
        AppChangelogEntry(
            "0.23.0",
            listOf(
                "Lớp chủ nhiệm gọn và dễ đọc hơn: ô số Có mặt / Trễ / Vắng / Chưa có, mỗi lớp còn 2 dòng kèm trạng thái màu (\"Đủ 41/41\", \"3 vắng\", \"Chưa điểm danh\").",
                "Chọn ngày bằng nút ‹ ›, ngày nghỉ chỉ hiện một thông báo. Chi tiết lớp mở thẳng phần điểm danh, mỗi học sinh một dòng.",
            ),
        ),
        AppChangelogEntry(
            "0.22.0",
            listOf(
                "Mục Lớp chủ nhiệm (theo nhóm quyền): tổng quan lớp theo ngày, vắng chờ xử lý, danh sách lớp và hồ sơ học sinh.",
            ),
        ),
        AppChangelogEntry(
            "0.21.0",
            listOf(
                "Mục Trao đổi: mọi cuộc trò chuyện Công tác, Công việc và nhóm, theo hoạt động mới nhất.",
                "Tạo nhóm, thêm hoặc xóa thành viên, đổi tên, rời nhóm và giải tán nhóm.",
                "Chuông thông báo trao đổi mở đúng cuộc trò chuyện. Số chưa đọc hiện trên mục Trao đổi.",
            ),
        ),
        AppChangelogEntry(
            "0.19.0",
            listOf(
                "Trao đổi trên công tác và công việc: gửi in đậm, in nghiêng, gạch chân và thu hồi trong 15 phút.",
                "Chuông thông báo trao đổi mở đúng cuộc hội thoại.",
            ),
        ),
        AppChangelogEntry(
            "0.18.0",
            listOf(
                "Sau khi chọn ảnh đại diện, cắt khung 1:1 rồi lưu WebP (nhẹ hơn JPEG).",
            ),
        ),
        AppChangelogEntry(
            "0.17.0",
            listOf(
                "Thông báo và Cá nhân chuyển lên góc phải (chuông + ảnh đại diện); thanh dưới còn Tổng quan, Lịch CT và Công việc.",
                "Đổi ảnh đại diện ngay trên Cá nhân; ảnh hiện ở góc phải và đồng bộ với web.",
            ),
        ),
        AppChangelogEntry(
            "0.16.3",
            listOf(
                "Chuyển kết nối backend sang Convex Cloud (ổn định hơn bản self-hosted).",
                "Giữ webURL production https://lvt.vscgroup.io.vn.",
            ),
        ),
        AppChangelogEntry(
            "0.16.2",
            listOf("Tải được lịch công tác chung trên Android."),
        ),
        AppChangelogEntry(
            "0.16.1",
            listOf("Màn Lịch CT hiện đủ hai nút lịch cá nhân và lịch chung."),
        ),
        AppChangelogEntry(
            "0.16.0",
            listOf("Tab Lịch CT: chọn lịch cá nhân hoặc xem PDF lịch công tác chung giống trên máy tính."),
        ),
        AppChangelogEntry(
            "0.15.0",
            listOf("Chi tiết công tác hiện Thành phần khác."),
        ),
        AppChangelogEntry(
            "0.14.1",
            listOf("Danh sách Công việc tự cập nhật ngay sau khi nộp bằng chứng hoàn thành."),
        ),
        AppChangelogEntry(
            "0.14.0",
            listOf("Khi đính kèm file công việc hoặc nộp bằng chứng, chọn Loại văn bản (Kế hoạch, Biên bản, Báo cáo)."),
        ),
        AppChangelogEntry(
            "0.13.3",
            listOf("Xem trước tệp đính kèm trong ứng dụng, tải xuống khi cần, và mở lại nhanh trong 24 giờ."),
        ),
        AppChangelogEntry(
            "0.13.2",
            listOf("Chi tiết nhiệm vụ Công việc hiện tệp đính kèm và cho phép mở tệp."),
        ),
        AppChangelogEntry(
            "0.13.1",
            listOf("Danh sách Công việc hiện tên công việc, không lấy tên file hay chữ Công văn."),
        ),
        AppChangelogEntry(
            "0.13.0",
            listOf("Tạo công việc ngay trên ứng dụng, giống trên web."),
        ),
        AppChangelogEntry(
            "0.12.0",
            listOf("Thêm mục Lịch sử thay đổi trong tab Cá nhân."),
        ),
        AppChangelogEntry(
            "0.11.0",
            listOf("Mở ứng dụng sẽ yêu cầu cập nhật khi Play có bản mới hơn."),
        ),
        AppChangelogEntry(
            "0.10.0",
            listOf("Công việc: tab Việc cần làm, Đang chờ duyệt, Quá hạn và Đã duyệt hoàn thành."),
        ),
        AppChangelogEntry(
            "0.9.0",
            listOf("Công việc thêm tab Chưa đến hạn và Đã quá hạn."),
        ),
        AppChangelogEntry(
            "0.8.2",
            listOf("Hiện số việc chưa xong trên các tab Công việc."),
        ),
        AppChangelogEntry(
            "0.8.1",
            listOf("Danh sách Công việc chia theo trạng thái hoàn thành."),
        ),
        AppChangelogEntry(
            "0.8.0",
            listOf("Có thể gửi ghi chú khi nộp hoàn thành công việc."),
        ),
    )

    fun visibleEntries(currentVersion: String): List<AppChangelogEntry> =
        entries.filter { compareVersions(it.version, currentVersion) <= 0 }
}

fun compareVersions(left: String, right: String): Int {
    val leftParts = versionParts(left)
    val rightParts = versionParts(right)
    val size = maxOf(leftParts.size, rightParts.size)
    for (index in 0 until size) {
        val delta = leftParts.getOrElse(index) { 0 }.compareTo(rightParts.getOrElse(index) { 0 })
        if (delta != 0) return delta
    }
    return 0
}

private fun versionParts(version: String): List<Int> =
    version.split('.').map { it.toIntOrNull() ?: 0 }
