import assert from 'node:assert/strict';
import test from 'node:test';
import {
  ONEOFF_WIPE_TABLES,
  buildTeacherImportPlan,
  classCodeFromHomeroom,
  classCodePrefixForYear,
  isOneoffWipeTable,
  normalizeTeacherEmail,
  normalizeTeacherName,
} from '../convex/oneoffTeacherImportPlan.ts';

const year = { _id: 'y2627', name: '2026-2027' };
const classes = [
  { _id: 'c61', code: '2627-6-1', schoolYearId: 'y2627', status: 'active' },
  { _id: 'c86', code: '2627-8-6', schoolYearId: 'y2627', status: 'active' },
  { _id: 'c89', code: '2627-8-9', schoolYearId: 'y2627', status: 'active' },
  { _id: 'old', code: '2526-6-1', schoolYearId: 'y2526', status: 'active' },
];
const departments = [
  { _id: 'dVAN', code: 'VAN', active: true },
  { _id: 'dTOAN', code: 'TOAN', active: true },
  { _id: 'dVP', code: 'VP', active: true },
  { _id: 'dTIN', code: 'TIN-CN', active: true },
];
const positions = [{ _id: 'pGV', code: 'GV', active: true }];
const permissionGroups = [
  { _id: 'gTTNV', code: 'TTNV', active: true },
  { _id: 'gBC', code: 'BC', active: false },
];
const baseUsers = [
  { _id: 'uBob', email: 'bob@example.com', role: 'admin', status: 'active' },
  { _id: 'uOldTuan', email: 'old.tuan@example.com', role: 'admin', status: 'active', departmentId: 'dVP' },
  { _id: 'uDummy', email: 'dummy@example.com', role: 'user', status: 'active' },
];
const teachers = [
  { name: ' Trần Mỹ Hạnh ', email: 'Hanh@Example.com ', department: 'Ngữ văn', homeroom: '8/6' },
  { name: 'Nguyễn Phan Tuấn', email: 'new.tuan@example.com', department: 'Toán', homeroom: '8/9' },
  { name: 'GV Tin', email: 'tin@example.com', department: 'Tin học', homeroom: '6/1' },
];

function plan(overrides = {}) {
  return buildTeacherImportPlan({
    teachers,
    legacyAccounts: [{ newEmail: 'new.tuan@example.com', oldEmail: 'old.tuan@example.com' }],
    deleteEmails: ['old.tuan@example.com', 'DUMMY@example.com', 'missing@example.com'],
    actorEmail: 'bob@example.com',
    users: baseUsers,
    departments,
    positions,
    permissionGroups,
    schoolYear: year,
    classes,
    assignments: [],
    ...overrides,
  });
}

test('wipe table allow-list never includes kept tables', () => {
  for (const kept of ['users', 'students', 'classEnrollments', 'homeroomClasses', 'schoolYears', 'auditLogs',
    'departments', 'positions', 'permissionGroups', 'locations', 'documentTypes', 'systemSettings', 'homeroomAssignments']) {
    assert.equal(isOneoffWipeTable(kept), false, kept);
  }
  assert.ok(ONEOFF_WIPE_TABLES.includes('boardingPeriods'));
  assert.equal(isOneoffWipeTable('duties'), true);
});

test('normalizers trim names and lowercase emails', () => {
  assert.equal(normalizeTeacherName(' Trần  Mỹ Hạnh '), 'Trần Mỹ Hạnh');
  assert.equal(normalizeTeacherEmail(' Ngl6u26@Gmail.com '), 'ngl6u26@gmail.com');
});

test('class codes map G/N to the active-year code', () => {
  assert.equal(classCodePrefixForYear('2026-2027'), '2627');
  assert.equal(classCodePrefixForYear('bad'), null);
  assert.equal(classCodeFromHomeroom('8/6', '2627'), '2627-8-6');
  assert.equal(classCodeFromHomeroom(' 9/14 ', '2627'), '2627-9-14');
  assert.equal(classCodeFromHomeroom('x', '2627'), null);
});

test('default teachers get role user, TTNV, GV and mapped department', () => {
  const result = plan();
  assert.deepEqual(result.errors, []);
  const hanh = result.teachers.find((t) => t.email === 'hanh@example.com');
  assert.equal(hanh.name, 'Trần Mỹ Hạnh');
  assert.equal(hanh.role, 'user');
  assert.equal(hanh.permissionGroupId, 'gTTNV');
  assert.equal(hanh.positionId, 'pGV');
  assert.equal(hanh.departmentId, 'dVAN');
  assert.equal(hanh.classId, 'c86');
  assert.equal(hanh.action, 'create');
  assert.equal(result.teachers.find((t) => t.email === 'tin@example.com').departmentId, 'dTIN');
});

test('legacy teacher copies the old account access instead of defaults', () => {
  const tuan = plan().teachers.find((t) => t.email === 'new.tuan@example.com');
  assert.equal(tuan.source, 'legacy');
  assert.equal(tuan.role, 'admin');
  assert.equal(tuan.departmentId, 'dVP');
  assert.equal(tuan.permissionGroupId, undefined);
  assert.equal(tuan.positionId, undefined);
  assert.equal(tuan.classId, 'c89');
});

test('delete list resolves users and reports missing emails', () => {
  const result = plan();
  assert.deepEqual(result.deleteUsers.map((u) => u.email).sort(), ['dummy@example.com', 'old.tuan@example.com']);
  assert.deepEqual(result.missingDeleteEmails, ['missing@example.com']);
  assert.equal(result.assignments.filter((a) => a.action === 'create').length, 3);
});

test('re-run is idempotent: existing accounts and assignments are skipped', () => {
  const users = [
    { _id: 'uBob', email: 'bob@example.com', role: 'admin', status: 'active' },
    { _id: 'uHanh', email: 'hanh@example.com', role: 'user', status: 'active' },
    { _id: 'uNewTuan', email: 'new.tuan@example.com', role: 'admin', status: 'active', departmentId: 'dVP' },
  ];
  const result = plan({
    users,
    assignments: [{ _id: 'a1', classId: 'c86', userId: 'uHanh', assignmentType: 'homeroom_teacher', active: true }],
  });
  assert.deepEqual(result.errors, []);
  assert.equal(result.teachers.find((t) => t.email === 'hanh@example.com').action, 'exists');
  assert.equal(result.teachers.find((t) => t.email === 'new.tuan@example.com').action, 'exists');
  assert.equal(result.assignments.find((a) => a.classId === 'c86').action, 'exists');
  assert.equal(result.assignments.find((a) => a.classId === 'c89').action, 'create');
  assert.equal(result.deleteUsers.length, 0);
});

test('blocking errors: unknown class, unknown department, duplicate, actor deletion, occupied class', () => {
  const bad = plan({
    teachers: [
      ...teachers,
      { name: 'X', email: 'x@example.com', department: 'Âm nhạc', homeroom: '6/1' },
      { name: 'Y', email: 'hanh@example.com', department: 'Toán', homeroom: '7/99' },
    ],
    deleteEmails: ['bob@example.com', 'old.tuan@example.com'],
  });
  const joined = bad.errors.join('\n');
  assert.match(joined, /DEPARTMENT_NOT_FOUND:Âm nhạc/);
  assert.match(joined, /DUPLICATE_CLASS:2627-6-1/);
  assert.match(joined, /DUPLICATE_EMAIL:hanh@example.com/);
  assert.match(joined, /CLASS_NOT_FOUND:7\/99/);
  assert.match(joined, /ACTOR_IN_DELETE_LIST/);

  const occupied = plan({
    assignments: [{ _id: 'a1', classId: 'c86', userId: 'someoneElse', assignmentType: 'homeroom_teacher', active: true }],
  });
  assert.match(occupied.errors.join('\n'), /CLASS_HAS_OTHER_HOMEROOM_TEACHER:2627-8-6/);
});

test('legacy pair requires old account in delete list and present unless new exists', () => {
  const result = plan({ deleteEmails: ['dummy@example.com'] });
  assert.match(result.errors.join('\n'), /LEGACY_OLD_ACCOUNT_NOT_IN_DELETE_LIST/);
  const gone = plan({ users: baseUsers.filter((u) => u._id !== 'uOldTuan') });
  assert.match(gone.errors.join('\n'), /LEGACY_ACCOUNT_NOT_FOUND:old.tuan@example.com/);
});

test('inactive default permission group is not used', () => {
  const result = plan({ defaults: { permissionGroupCode: 'BC' } });
  assert.match(result.errors.join('\n'), /PERMISSION_GROUP_NOT_FOUND:BC/);
});
