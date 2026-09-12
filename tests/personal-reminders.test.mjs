import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  canEnableDutyPersonalReminder,
  canEnableWorkPersonalReminder,
  dutyAllowsPersonalReminder,
  workCompletionBlocksReminder,
} from '../convex/personalReminderPolicy.ts';
import {
  cleanPersonalReminderMilestones,
  createMilestones,
  HOUR_MS,
  mergeMilestoneItems,
} from '../convex/notificationSettings.ts';
import { workReminderSourceType, workTabAllowsPersonalReminder, WORK_LIST_TAB_COMPLETED, WORK_LIST_TAB_OVERDUE, WORK_LIST_TAB_PENDING, WORK_LIST_TAB_TODO } from '../src/work/workDisplay.js';
import { personalReminderQueryBoundaryState } from '../src/notifications/personalReminderQuery.js';

test('nhắc cá nhân chỉ cho công tác chưa kết thúc của chính mình', () => {
  assert.equal(dutyAllowsPersonalReminder({ isOverdue: false }), true);
  assert.equal(dutyAllowsPersonalReminder({ isOverdue: true }), false);
  assert.equal(
    canEnableDutyPersonalReminder({
      user: { _id: 'u1' },
      duty: { active: true },
      isParticipant: true,
      isOverdue: false,
    }),
    null,
  );
  assert.equal(
    canEnableDutyPersonalReminder({
      user: { _id: 'u1' },
      duty: { active: true },
      isParticipant: false,
      isOverdue: false,
    }),
    'PERSONAL_REMINDER_FORBIDDEN',
  );
  assert.equal(
    canEnableDutyPersonalReminder({
      user: { _id: 'u1' },
      duty: { active: true },
      isParticipant: true,
      isOverdue: true,
    }),
    'DUTY_ALREADY_PAST',
  );
});

test('nhắc công việc bị chặn khi đã nộp/hoàn thành, không chặn khi bị trả về', () => {
  assert.equal(
    workCompletionBlocksReminder({
      userId: 'u1',
      completions: [{ userId: 'u1', status: 'pending_approval' }],
    }),
    true,
  );
  assert.equal(
    workCompletionBlocksReminder({
      userId: 'u1',
      completions: [{ userId: 'u1', status: 'rejected' }],
    }),
    false,
  );
  assert.equal(
    canEnableWorkPersonalReminder({ found: true, isAssignee: false, blockedByCompletion: false }),
    'PERSONAL_REMINDER_FORBIDDEN',
  );
  assert.equal(
    canEnableWorkPersonalReminder({ found: true, isAssignee: true, blockedByCompletion: true }),
    'WORK_ALREADY_COMPLETED',
  );
});

test('mốc nhắc cá nhân được để trống; trùng giờ với Admin chỉ hiện một thẻ', () => {
  assert.deepEqual(cleanPersonalReminderMilestones([]), []);
  assert.deepEqual(cleanPersonalReminderMilestones([24, 6]), [24, 6]);
  const now = 1_700_000_000_000;
  const dueAt = now + 5 * HOUR_MS;
  const source = {
    kind: 'duty',
    sourceType: 'duty',
    sourceId: 'd1',
    title: 'Họp',
    dueAt,
  };
  const adminOffPersonalOn = mergeMilestoneItems([
    createMilestones([source], [], now),
    createMilestones([source], [24], now),
  ]);
  assert.deepEqual(adminOffPersonalOn.map((item) => item.milestoneHours), [24]);
  const bothHave24 = mergeMilestoneItems([
    createMilestones([source], [48, 24], now),
    createMilestones([source], [24, 6], now),
  ]);
  assert.deepEqual(
    bothHave24.map((item) => item.milestoneHours).sort((a, b) => b - a),
    [48, 24, 6],
  );
});

test('công việc chỉ nhắc ở tab Việc cần làm và Quá hạn', () => {
  assert.equal(workTabAllowsPersonalReminder(WORK_LIST_TAB_TODO), true);
  assert.equal(workTabAllowsPersonalReminder(WORK_LIST_TAB_OVERDUE), true);
  assert.equal(workTabAllowsPersonalReminder(WORK_LIST_TAB_PENDING), false);
  assert.equal(workTabAllowsPersonalReminder(WORK_LIST_TAB_COMPLETED), false);
  assert.equal(workReminderSourceType({ type: 'department' }), 'department_work');
  assert.equal(workReminderSourceType({ type: 'individual' }), 'personal_task');
});

test('lỗi query nhắc nhở không được làm trắng trang, trừ lỗi auth', () => {
  assert.deepEqual(
    personalReminderQueryBoundaryState(new Error('[CONVEX Q(personalReminders:listMine)] Server Error')),
    { failed: true },
  );
  assert.throws(
    () => personalReminderQueryBoundaryState(new Error('PASSWORD_CHANGE_REQUIRED')),
    /PASSWORD_CHANGE_REQUIRED/,
  );
});

test('list công tác/công việc gắn panel nhắc cá nhân và xếp 1 cột', () => {
  const dutyView = readFileSync(new URL('../src/reports/DutyReportsView.jsx', import.meta.url), 'utf8');
  const workView = readFileSync(new URL('../src/work/WorkViews.jsx', import.meta.url), 'utf8');
  const css = readFileSync(new URL('../src/duties/duties.css', import.meta.url), 'utf8');
  assert.match(dutyView, /PersonalReminderPanel/);
  assert.match(dutyView, /PersonalReminderQueryBoundary/);
  assert.match(dutyView, /isSelectedSelf/);
  assert.match(dutyView, /const showDutyReminders = Boolean\(data\?\.isSelectedSelf\)/);
  assert.doesNotMatch(dutyView, /showDutyReminders = !reminderFailed/);
  assert.match(workView, /PersonalReminderPanel/);
  assert.match(workView, /PersonalReminderQueryBoundary/);
  assert.match(workView, /workTabAllowsPersonalReminder/);
  assert.doesNotMatch(workView, /showWorkReminders = !reminderFailed/);
  assert.match(css, /grid-template-columns: minmax\(0, 1fr\);/);
  assert.match(css, /\.duty-card-layout/);
});
