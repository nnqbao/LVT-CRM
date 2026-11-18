import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { sortUsersBy } from '../src/lib/userSort.js';

const departments = [
  { _id: 'd-toan', name: 'Toán' },
  { _id: 'd-anh', name: 'Anh văn' },
];
const positions = [
  { _id: 'p-gv', name: 'Giáo viên', level: 1 },
  { _id: 'p-tt', name: 'Tổ trưởng', level: 3 },
  { _id: 'p-ht', name: 'Hiệu trưởng', level: 5 },
];
const users = [
  { _id: '1', name: 'Bình', departmentId: 'd-toan', positionId: 'p-gv' },
  { _id: '2', name: 'An', departmentId: 'd-anh', positionId: 'p-gv' },
  { _id: '3', name: 'Chi', departmentId: 'd-toan', positionId: 'p-tt' },
  { _id: '4', name: 'Dũng', positionId: 'p-ht' },
  { _id: '5', name: 'Em', departmentId: 'd-anh' },
];
const ids = (list) => list.map((u) => u._id).join(',');

test('sort users: default keeps the server order and never mutates the list', () => {
  assert.equal(sortUsersBy(users, 'default', departments, positions), users);
  sortUsersBy(users, 'position', departments, positions);
  assert.equal(ids(users), '1,2,3,4,5');
});

test('sort users by name, by tổ chuyên môn and by chức vụ (highest level first)', () => {
  assert.equal(ids(sortUsersBy(users, 'name', departments, positions)), '2,1,3,4,5');
  // Tổ A→Z (Anh văn, Toán), inside a tổ the higher chức vụ first; no tổ last.
  assert.equal(ids(sortUsersBy(users, 'department', departments, positions)), '2,5,3,1,4');
  // Chức vụ 5★ → 3★ → 1★ (same level by tổ, then name); no chức vụ last.
  assert.equal(ids(sortUsersBy(users, 'position', departments, positions)), '4,3,2,1,5');
});

test('Thiết lập người dùng: row actions open popups in place instead of the form at the top', () => {
  const main = readFileSync(new URL('../src/main.jsx', import.meta.url), 'utf8');
  const start = main.indexOf('function UserManagement()');
  const view = main.slice(start, main.indexOf('\nfunction ', start + 30));
  for (const kind of ['edit', 'reset', 'status', 'delete']) {
    assert.match(view, new RegExp(`openDialog\\('${kind}', item\\)`), `${kind} opens a popup from the row`);
    assert.match(view, new RegExp(`dialog\\?\\.kind === '${kind}'`), `${kind} popup is rendered`);
  }
  assert.doesNotMatch(view, /window\.confirm\(/, 'no browser confirm box');
  assert.doesNotMatch(view, /startEdit\(|setResetting\(/, 'the old top-of-page edit/reset forms are gone');
  assert.match(view, /<form className="admin-form" onSubmit=\{submitCreate\}>/, 'the top form only creates accounts');
  assert.match(view, /className=\{`users-toast \$\{toast\.type\}`\}/, 'row results show as a toast');
  assert.match(view, /aria-label="Sắp xếp người dùng"/);
  assert.match(view, /sortedUsers\.map\(\(item\) =>/);
  assert.match(main, /function UserDialog\([\s\S]*?event\.key === 'Escape' && !busy/, 'popup closes with Esc');
});
