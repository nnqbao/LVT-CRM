import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  assignmentRecipientLabel,
  assignmentsFromDocument,
  buildWorkCreatePreview,
  emptyWorkAssignment,
  emptyWorkSearch,
  filterWorksBySearch,
  filterWorksByTab,
  formatWorkDate,
  isWorkCompleted,
  isWorkPast,
  pendingReviewForMember,
  pendingReviewsForDocument,
  workAssignmentPayload,
  workContentSummary,
  workDeadlineKey,
  workListTabCounts,
  WORK_LIST_TAB_COMPLETED,
  WORK_LIST_TAB_OVERDUE,
  WORK_LIST_TAB_PENDING,
  WORK_LIST_TAB_TODO,
  workListTitle,
} from '../src/work/workDisplay.js';

test('format và row phân công công việc', () => {
  assert.equal(formatWorkDate('2026-08-18'), '18/08/2026');
  assert.equal(formatWorkDate(''), '—');
  const row = emptyWorkAssignment('individual');
  assert.equal(row.type, 'individual');
  assert.deepEqual(row.userIds, []);
  assert.equal(emptyWorkAssignment('department').type, 'department');
});

test('sửa công việc tách cá nhân thành một người mỗi row', () => {
  const rows = assignmentsFromDocument({
    assignments: [
      { type: 'department', departmentId: 'd1', content: 'Báo cáo', deadline: '2026-08-20' },
      { type: 'individual', userIds: ['u1', 'u2'], content: 'Soạn', deadline: '2026-08-21' },
    ],
  });
  assert.equal(rows.length, 3);
  assert.deepEqual(rows[1].userIds, ['u1']);
  assert.deepEqual(rows[2].userIds, ['u2']);
  assert.deepEqual(workAssignmentPayload(rows)[0], {
    type: 'department',
    departmentId: 'd1',
    content: 'Báo cáo',
    deadline: '2026-08-20',
  });
});

test('bốn tab Công việc tách việc cần làm, chờ duyệt, quá hạn và đã duyệt', () => {
  const today = '2026-08-17';
  const upcoming = {
    _id: 'a',
    title: 'Sắp tới',
    deadline: '2026-08-20',
    status: 'in_progress',
  };
  const overdue = { _id: 'b', title: 'Hết hạn', deadline: '2026-08-10', status: 'overdue' };
  const done = { _id: 'c', title: 'Xong', deadline: '2026-08-30', workStatus: 'completed' };
  const waiting = { _id: 'e', title: 'Chờ duyệt', deadline: '2026-08-10', status: 'pending_completion' };
  const later = {
    _id: 'd',
    title: 'Nhiều hạn',
    assignments: [
      { deadline: '2026-08-25' },
      { deadline: '2026-08-19' },
    ],
    status: 'in_progress',
  };
  assert.equal(isWorkPast(overdue, today), true);
  assert.equal(isWorkPast(done, today), true);
  assert.equal(isWorkPast(upcoming, today), false);
  assert.equal(isWorkCompleted(overdue), false);
  assert.equal(isWorkCompleted(done), true);
  assert.equal(workDeadlineKey(later), '2026-08-19');
  const list = [later, overdue, done, upcoming, waiting];
  assert.deepEqual(filterWorksByTab(list, WORK_LIST_TAB_TODO, today).map((item) => item._id), ['d', 'a']);
  assert.deepEqual(filterWorksByTab(list, WORK_LIST_TAB_PENDING, today).map((item) => item._id), ['e']);
  assert.deepEqual(filterWorksByTab(list, WORK_LIST_TAB_OVERDUE, today).map((item) => item._id), ['b']);
  assert.deepEqual(filterWorksByTab(list, WORK_LIST_TAB_COMPLETED, today).map((item) => item._id), ['c']);
  assert.deepEqual(workListTabCounts(list, today), {
    [WORK_LIST_TAB_TODO]: 2,
    [WORK_LIST_TAB_PENDING]: 1,
    [WORK_LIST_TAB_OVERDUE]: 1,
    [WORK_LIST_TAB_COMPLETED]: 1,
  });
  const createdWaiting = {
    _id: 'f',
    title: 'Công việc tôi tạo',
    status: 'approved',
    assignments: [
      { deadline: '2026-08-10', status: 'pending_completion' },
    ],
  };
  assert.deepEqual(filterWorksByTab([createdWaiting], WORK_LIST_TAB_PENDING, today).map((item) => item._id), ['f']);
  assert.deepEqual(filterWorksByTab([createdWaiting], WORK_LIST_TAB_OVERDUE, today).map((item) => item._id), []);
});

test('preview tạo công việc gom nhãn đối tượng', () => {
  const preview = buildWorkCreatePreview(
    {
      title: 'Họp tổ',
      fileName: 'ke-hoach.pdf',
      assignments: [
        { type: 'department', departmentId: 'd1', content: 'Chuẩn bị', deadline: '2026-08-18' },
        { type: 'individual', userIds: ['u2'], content: '', deadline: '2026-08-19' },
      ],
    },
    {
      departments: [{ _id: 'd1', name: 'Tổ Toán' }],
      users: [{ _id: 'u2', name: 'Bình' }],
    },
  );
  assert.equal(preview.title, 'Họp tổ');
  assert.equal(preview.fileName, 'ke-hoach.pdf');
  assert.equal(preview.rows[0].recipient, 'Tổ Toán');
  assert.equal(preview.rows[0].deadline, '18/08/2026');
  assert.equal(preview.rows[1].recipient, 'Bình');
  assert.equal(preview.rows[1].content, '—');
  assert.equal(assignmentRecipientLabel({ type: 'individual', userIds: [] }), 'Chưa chọn người');
  assert.equal(workListTitle({ fileName: 'a.pdf' }), 'a.pdf');
  assert.equal(workContentSummary({ assignments: [{ content: 'Một' }, { content: 'Hai' }] }), 'Một (+1)');
});

test('tìm kiếm realtime theo tên hoặc nội dung công việc, không dấu', () => {
  const mine = {
    _id: 'a',
    documentTitle: 'Họp tổ chuyên môn',
    content: 'Soạn báo cáo tuần',
    departmentName: 'Tổ Toán',
    deadline: '2026-08-20',
    members: [{ name: 'Trần Anh Vũ' }],
  };
  const created = {
    _id: 'b',
    title: 'Đi thực tế',
    content: 'Chuẩn bị hồ sơ',
    assignments: [
      {
        type: 'department',
        departmentName: 'Phòng Tổ chức',
        content: 'Chuẩn bị hồ sơ',
        deadline: '2026-08-22',
        members: [{ name: 'Admin' }],
      },
    ],
  };
  assert.deepEqual(filterWorksBySearch([mine, created], { ...emptyWorkSearch(), query: 'hop to' }).map((item) => item._id), ['a']);
  assert.deepEqual(filterWorksBySearch([mine, created], { ...emptyWorkSearch(), query: 'bao cao' }).map((item) => item._id), ['a']);
  assert.deepEqual(filterWorksBySearch([mine, created], { ...emptyWorkSearch(), query: 'thực tế' }).map((item) => item._id), ['b']);
});

test('tìm kiếm nâng cao công việc theo phòng ban, cá nhân và hạn chót', () => {
  const mine = {
    _id: 'a',
    documentTitle: 'Họp tổ',
    content: 'Soạn báo cáo',
    departmentName: 'Tổ Toán',
    deadline: '2026-08-20',
    members: [{ name: 'Trần Anh Vũ' }],
  };
  const created = {
    _id: 'b',
    title: 'Đi thực tế',
    assignments: [
      {
        type: 'department',
        departmentName: 'Phòng Tổ chức',
        content: 'Chuẩn bị',
        deadline: '2026-08-22',
        members: [{ name: 'Admin' }],
      },
    ],
  };
  const base = emptyWorkSearch();
  assert.deepEqual(filterWorksBySearch([mine, created], { ...base, department: 'to toan' }).map((item) => item._id), ['a']);
  assert.deepEqual(filterWorksBySearch([mine, created], { ...base, person: 'anh vu' }).map((item) => item._id), ['a']);
  assert.deepEqual(filterWorksBySearch([mine, created], { ...base, dateFrom: '2026-08-22', dateTo: '2026-08-22' }).map((item) => item._id), ['b']);
  assert.deepEqual(filterWorksBySearch([mine, created], { ...base, query: 'hop', department: 'to chuc' }).map((item) => item._id), []);
});

test('mỗi tab Công việc hiện badge số việc', () => {
  const source = readFileSync(new URL('../src/work/WorkListFilters.jsx', import.meta.url), 'utf8');
  assert.match(source, /counts/);
  assert.match(source, /nav-badge duty-list-tab-badge/);
  assert.match(source, /formatWorkTabCount/);
  assert.match(source, /Việc cần làm/);
  assert.match(source, /Đang chờ duyệt/);
  assert.match(source, /Quá hạn/);
  assert.match(source, /Đã duyệt hoàn thành/);
});

test('query work.badge cộng chờ duyệt với hai tab chưa hoàn thành', () => {
  const source = readFileSync(new URL('../convex/work.ts', import.meta.url), 'utf8');
  assert.match(source, /incompleteCreatedCount/);
  assert.match(source, /workMenuBadgeCount/);
  assert.match(source, /documentId: document\._id/);
});

test('thẻ việc tôi tạo ghép được task chờ duyệt theo documentId hoặc thành viên', () => {
  const document = {
    _id: 'doc-1',
    assignments: [
      {
        _id: 'item-1',
        content: 'việc cho Ngân',
        deadline: '2026-08-16',
        type: 'individual',
        departmentName: 'Cá nhân',
        members: [{ _id: 'u1', name: 'Ngân Lâm', status: 'pending_completion' }],
      },
    ],
  };
  const byDocument = pendingReviewsForDocument(
    [{ kind: 'work_item', workItemId: 'other-item', documentId: 'doc-1', userId: 'u1' }],
    document,
  );
  assert.equal(byDocument.length, 1);
  assert.equal(byDocument[0].userId, 'u1');

  const synthesized = pendingReviewsForDocument([], document);
  assert.equal(synthesized.length, 1);
  assert.equal(synthesized[0].workItemId, 'item-1');

  const memberReview = pendingReviewForMember([], document.assignments[0], document.assignments[0].members[0], document);
  assert.equal(memberReview.userId, 'u1');
});

test('Việc tôi tạo hiện nút duyệt hoàn thành trên thẻ đã nộp', () => {
  const source = readFileSync(new URL('../src/work/WorkViews.jsx', import.meta.url), 'utf8');
  const managementStart = source.indexOf('export function WorkManagement(');
  const userStart = source.indexOf('export function WorkUserView(');
  const management = source.slice(managementStart, userStart);
  const userView = source.slice(userStart);
  assert.match(management, /pendingReviewsForDocument/);
  assert.match(management, /pendingReviewForMember/);
  assert.match(management, /Duyệt \/ Chưa duyệt/);
  assert.doesNotMatch(userView, /hideCompletionQueue/);
  assert.match(userView, /WorkManagement allowCreate focusTarget=\{focusTarget\}/);
  assert.match(userView, /!\(data\?\.canCreate && isAdminMod\)/);
});
