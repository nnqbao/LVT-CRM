import assert from 'node:assert/strict';
import test from 'node:test';

import { convexErrorText, messageFor } from '../src/lib/appErrorMessage.js';

test('convexErrorText không để object data che mất mã lỗi', () => {
  assert.equal(
    convexErrorText({ data: { extraField: 'title' }, message: 'ArgumentValidationError: extra field `title`' }).includes(
      'ArgumentValidationError',
    ),
    true,
  );
  assert.match(
    convexErrorText({ data: { code: 'INVALID_TIME' } }),
    /INVALID_TIME/,
  );
  assert.match(
    convexErrorText({ data: {}, message: '[CONVEX M(duties:create)] Uncaught Error: INVALID_DEPARTMENT' }),
    /INVALID_DEPARTMENT/,
  );
});

test('messageFor đọc được lỗi Convex bị bọc trong data object', () => {
  assert.equal(
    messageFor({ data: { code: 'INVALID_TIME' } }),
    'Giờ không hợp lệ.',
  );
  assert.equal(
    messageFor({
      data: { extraField: 'title' },
      message: 'ArgumentValidationError: extra field `title` that is not in the validator',
    }),
    'Máy chủ chưa nhận cấu hình mới. Vui lòng tải lại trang sau khi hệ thống cập nhật, rồi thử lại.',
  );
  assert.equal(
    messageFor({ data: {}, message: '[Request ID: abc] Server Error\nUncaught Error: DUTY_PARTICIPANTS_REQUIRED' }),
    'Vui lòng chọn ít nhất một người tham gia.',
  );
  assert.equal(
    messageFor({ message: 'WORK_COMPLETION_REVIEWER_REQUIRED' }),
    'Người tạo hoặc quản trị viên mới được đánh dấu hoàn thành hoặc trả về.',
  );
  assert.equal(
    messageFor({
      message: '[CONVEX Q(peopleReview:staffFaultLog)] [Request ID: abc] Server Error\nCould not find public function',
    }),
    'Máy chủ chưa cập nhật chức năng Ghi nhận lỗi. Vui lòng tải lại trang sau khi hệ thống cập nhật, rồi thử lại.',
  );
});
