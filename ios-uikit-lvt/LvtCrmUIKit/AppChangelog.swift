import Foundation

struct AppChangelogEntry: Equatable {
    let version: String
    let highlights: [String]
}

enum AppChangelog {
    static let entries: [AppChangelogEntry] = [
        AppChangelogEntry(
            version: "3.1.1",
            highlights: [
                "Thanh tab có biểu tượng kèm chữ ở Lớp học, Trao đổi, Lịch công tác và Công việc; các ô chia đều nên không còn tab bị che hay phải vuốt ngang.",
                "Số việc của từng tab Công việc hiện thành chấm số trên biểu tượng.",
            ]
        ),
        AppChangelogEntry(
            version: "3.1.0",
            highlights: [
                "Menu Lớp chủ nhiệm đổi tên thành Lớp học, gồm Tổng quan, Chủ nhiệm, Giảng dạy, Lịch dạy và Học bạ. Tổng quan hiện tiết dạy hôm nay (Đã ghi sổ / Chưa ghi sổ) và học sinh vắng của lớp chủ nhiệm.",
                "Lớp giảng dạy xếp theo tiết sắp dạy gần nhất; bấm lớp để ghi Sổ đầu bài (ngày dạy, tiết, 1–5 sao, nhận xét). Trang lớp chủ nhiệm có thêm tab Sổ đầu bài theo tuần.",
                "Lịch dạy xem dạng Danh sách, Tuần (Thứ 2–6 × 10 tiết) và Tháng. Học bạ: chọn lớp theo khối, học sinh, xem điểm từng môn, ĐTB học kỳ và cả năm; thêm, sửa, xóa điểm môn mình dạy.",
                "Đăng nhập bằng Face ID / Touch ID: bật tại Cá nhân › Bảo mật, lần sau bấm nút trên màn hình đăng nhập. Ứng dụng không lưu mật khẩu.",
                "Tạo passkey tại Cá nhân › Bảo mật và “Đăng nhập bằng passkey” trên màn hình đăng nhập.",
                "Báo cáo › Bán trú hiện theo quyền Bán trú của nhóm quyền.",
            ]
        ),
        AppChangelogEntry(
            version: "3.0.0",
            highlights: [
                "Công việc do Văn thư/Quản trị giao cho người khác cần Ban giám hiệu duyệt: chọn người duyệt rồi bấm “Gửi duyệt”. Người tạo thấy Chờ duyệt x/y, Đã duyệt hoặc Bị trả lại kèm lý do, sửa rồi “Lưu và gửi duyệt lại”.",
                "Ban giám hiệu có mục “Chờ tôi duyệt”: Duyệt (có xác nhận) hoặc Trả lại kèm lý do. Sau lượt duyệt đầu tiên, công việc không còn sửa/xóa được (trừ khi máy chủ cho phép quản trị sửa và gửi duyệt lại).",
                "Ban giám hiệu và tổ trưởng/tổ phó tạo công việc theo quyền máy chủ cấp; phân công chưa được duyệt hiện “Chờ duyệt (chưa giao)”. Thông báo chờ duyệt, đã duyệt, bị trả lại mở đúng công việc.",
                "Mục mới Báo cáo › Bán trú trên Tổng quan: danh sách giáo viên tham gia theo “Học kỳ · Năm học” (phòng ban mình hoặc toàn trường theo quyền Báo cáo); quản trị viên thêm, sửa, xóa Kỳ bán trú.",
                "Nút “?” trên các màn hình chính mở hướng dẫn sử dụng đúng chủ đề.",
            ]
        ),
        AppChangelogEntry(
            version: "2.0.0",
            highlights: [
                "Mục mới Điểm danh cho Giám thị (và quản trị viên): chọn Lớp 6–9, mở lớp, đánh dấu học sinh Vắng rồi Lưu lớp. Mặc định cả lớp có mặt; nhập bằng Excel dùng bản web.",
                "Lớp chủ nhiệm: học sinh vắng hiện đầu danh sách với Vắng có phép / Vắng không phép; GVCN bật “Vắng không phép” ngay trên dòng, không cần ghi lý do. Lớp chưa được Giám thị điểm danh sẽ hiện thông báo.",
                "Việc của tôi trong Công việc: thêm việc riêng với hạn chót và giờ nhắc, đánh dấu hoàn thành, sửa, xóa. Bấm thông báo nhắc việc mở đúng danh sách.",
                "Bỏ nhập điểm danh camera và mục Vắng chờ xử lý theo bản web mới.",
            ]
        ),
        AppChangelogEntry(
            version: "1.16.0",
            highlights: [
                "Lịch công tác chung xem theo tuần ngay trên app, mỗi ngày một danh sách. Giáo viên chỉ thấy lịch đã được Ban Giám hiệu duyệt.",
                "Ban Giám hiệu duyệt hoặc trả lại lịch tuần (kèm lý do) trên app; văn thư sửa công tác và nộp duyệt. Bấm thông báo mở đúng tuần.",
            ]
        ),
        AppChangelogEntry(
            version: "1.15.0",
            highlights: [
                "Lớp chủ nhiệm gọn và dễ đọc hơn: ô số Có mặt / Trễ / Vắng / Chưa có, mỗi lớp còn 2 dòng kèm trạng thái màu (\"Đủ 41/41\", \"3 vắng\", \"Chưa điểm danh\").",
                "Chọn ngày bằng nút ‹ ›, ngày nghỉ chỉ hiện một thông báo. Chi tiết lớp mở thẳng phần điểm danh, mỗi học sinh một dòng.",
            ]
        ),
        AppChangelogEntry(
            version: "1.14.1",
            highlights: [
                "Mục Lớp chủ nhiệm (theo nhóm quyền): tổng quan lớp theo ngày, vắng chờ xử lý, danh sách lớp và hồ sơ học sinh.",
                "Sửa lỗi danh sách lớp trống khi chưa nhập tìm kiếm; lớp chưa có GVCN hiện “Chưa phân công”.",
            ]
        ),
        AppChangelogEntry(
            version: "1.13.0",
            highlights: [
                "Mục Trao đổi: mọi cuộc trò chuyện Công tác, Công việc và nhóm, theo hoạt động mới nhất.",
                "Tạo nhóm, thêm hoặc xóa thành viên, đổi tên, rời nhóm và giải tán nhóm.",
                "Chuông thông báo trao đổi mở đúng cuộc trò chuyện. Số chưa đọc hiện trên mục Trao đổi.",
            ]
        ),
        AppChangelogEntry(
            version: "1.11.0",
            highlights: [
                "Trao đổi trên công tác và công việc: gửi in đậm, in nghiêng, gạch chân và thu hồi trong 15 phút.",
                "Chuông thông báo trao đổi mở đúng cuộc hội thoại.",
            ]
        ),
        AppChangelogEntry(
            version: "1.10.0",
            highlights: [
                "Sau khi chọn ảnh đại diện, cắt khung 1:1 rồi lưu WebP (nhẹ hơn JPEG).",
            ]
        ),
        AppChangelogEntry(
            version: "1.9.0",
            highlights: [
                "Thông báo và Cá nhân chuyển lên góc phải (chuông + ảnh đại diện); thanh dưới còn Tổng quan, Lịch CT và Công việc.",
                "Đổi ảnh đại diện ngay trên Cá nhân; ảnh hiện ở góc phải và đồng bộ với web.",
            ]
        ),
        AppChangelogEntry(
            version: "1.8.4",
            highlights: [
                "Hết treo màn hình tải khi mở app lần đầu; nếu máy chủ không trả lời thì hiện đăng nhập để thử lại.",
            ]
        ),
        AppChangelogEntry(
            version: "1.8.3",
            highlights: [
                "Bắt buộc cập nhật khi App Store có bản mới hơn (giống Android).",
            ]
        ),
        AppChangelogEntry(
            version: "1.8.2",
            highlights: [
                "Chuyển kết nối backend sang Convex Cloud (ổn định hơn bản self-hosted).",
                "Giữ webURL production https://lvt.vscgroup.io.vn.",
            ]
        ),
        AppChangelogEntry(
            version: "1.8.1",
            highlights: ["Màn Lịch CT hiện đủ hai nút lịch cá nhân và lịch chung."]
        ),
        AppChangelogEntry(
            version: "1.8.0",
            highlights: ["Tab Lịch CT: chọn lịch cá nhân hoặc xem PDF lịch công tác chung giống trên máy tính."]
        ),
        AppChangelogEntry(
            version: "1.7.0",
            highlights: ["Chi tiết công tác hiện Thành phần khác."]
        ),
        AppChangelogEntry(
            version: "1.6.1",
            highlights: [
                "Nộp được bằng chứng hoàn thành sau khi chọn ảnh hoặc tệp.",
                "Hết treo màn hình trắng khi mở lại app sau một thời gian.",
            ]
        ),
        AppChangelogEntry(
            version: "1.6.0",
            highlights: ["Khi đính kèm file công việc hoặc nộp bằng chứng, chọn Loại văn bản (Kế hoạch, Biên bản, Báo cáo)."]
        ),
        AppChangelogEntry(
            version: "1.5.3",
            highlights: ["Xem trước tệp đính kèm trong ứng dụng, tải xuống khi cần, và mở lại nhanh trong 24 giờ."]
        ),
        AppChangelogEntry(
            version: "1.5.2",
            highlights: ["Chi tiết nhiệm vụ Công việc hiện tệp đính kèm và cho phép mở tệp."]
        ),
        AppChangelogEntry(
            version: "1.5.1",
            highlights: ["Danh sách Công việc hiện tên công việc, không lấy tên file hay chữ Công văn."]
        ),
        AppChangelogEntry(
            version: "1.5.0",
            highlights: ["Tạo công việc ngay trên ứng dụng, giống trên web."]
        ),
        AppChangelogEntry(
            version: "1.4.0",
            highlights: ["Thêm mục Lịch sử thay đổi trong tab Cá nhân."]
        ),
        AppChangelogEntry(
            version: "1.3.0",
            highlights: ["Công việc: tab Việc cần làm, Đang chờ duyệt, Quá hạn và Đã duyệt hoàn thành."]
        ),
        AppChangelogEntry(
            version: "1.2.0",
            highlights: ["Công việc thêm tab Chưa đến hạn và Đã quá hạn."]
        ),
        AppChangelogEntry(
            version: "1.1.2",
            highlights: ["Hiện số việc chưa xong trên các tab Công việc."]
        ),
        AppChangelogEntry(
            version: "1.1.1",
            highlights: ["Danh sách Công việc chia theo trạng thái hoàn thành."]
        ),
        AppChangelogEntry(
            version: "1.1.0",
            highlights: ["Có thể gửi ghi chú khi nộp hoàn thành công việc."]
        ),
        AppChangelogEntry(
            version: "1.0",
            highlights: ["Bản đầu trên App Store: đăng nhập, công tác, công việc và thông báo."]
        ),
    ]

    static func visibleEntries(currentVersion: String) -> [AppChangelogEntry] {
        entries.filter { compareVersions($0.version, currentVersion) <= 0 }
    }
}

func compareVersions(_ left: String, _ right: String) -> Int {
    let leftParts = versionParts(left)
    let rightParts = versionParts(right)
    let size = max(leftParts.count, rightParts.count)
    for index in 0..<size {
        let leftValue = index < leftParts.count ? leftParts[index] : 0
        let rightValue = index < rightParts.count ? rightParts[index] : 0
        if leftValue != rightValue { return leftValue < rightValue ? -1 : 1 }
    }
    return 0
}

private func versionParts(_ version: String) -> [Int] {
    version.split(separator: ".").map { Int($0) ?? 0 }
}
