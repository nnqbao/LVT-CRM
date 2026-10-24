import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (path) => readFileSync(new URL(`../android-app/app/${path}`, import.meta.url), 'utf8');
const src = (path) => read(`src/main/java/lvt/crm/${path}`);

test('Android: shared IconTabBar is an equal-width, accessible icon + label switcher', () => {
  const bar = src('ui/components/IconTabBar.kt');
  assert.match(bar, /fun IconTabBar\(/);
  assert.match(bar, /\.selectableGroup\(\)/);
  assert.match(bar, /role = Role\.Tab/);
  assert.match(bar, /Modifier\.weight\(1f\)/);
  assert.match(bar, /heightIn\(min = 56\.dp\)/);
  assert.match(bar, /MaterialTheme\.typography\.labelMedium/);
  assert.match(bar, /maxLines = 2/);
  assert.match(bar, /"99\+"/);
  assert.doesNotMatch(bar, /Color\(0x/, 'colors come from MaterialTheme only');
  assert.doesNotMatch(bar, /\d+\.sp\b/, 'no hard-coded font sizes');
});

test('Android: Lớp học, Trao đổi, Lịch công tác and Công việc use IconTabBar', () => {
  const screens = {
    'ui/teaching/ClassesHubScreen.kt': ['Tổng quan', 'Chủ nhiệm', 'Giảng dạy', 'Lịch dạy', 'Học bạ'],
    'ui/chat/ChatHubScreen.kt': ['Tất cả', 'Công tác', 'Công việc', 'Nhóm'],
    'ui/duties/DutiesScreen.kt': [],
    'ui/work/WorkHubScreen.kt': ['Công việc', 'Việc của tôi'],
    'ui/work/WorkScreen.kt': [],
  };
  for (const [path, labels] of Object.entries(screens)) {
    const code = src(path);
    assert.match(code, /IconTabBar\(/, path);
    assert.doesNotMatch(code, /ScrollableTabRow|PrimaryTabRow/, path);
    for (const label of labels) assert.match(code, new RegExp(`"${label}"`), `${path}: ${label}`);
  }
  const dutyTabs = src('ui/duties/DutyListRules.kt');
  for (const label of ['Sắp diễn ra', 'Đang diễn ra', 'Đã diễn ra']) assert.match(dutyTabs, new RegExp(`"${label}"`));
  const workTabs = src('ui/work/WorkListRules.kt');
  for (const label of ['Việc cần làm', 'Đang chờ duyệt', 'Quá hạn', 'Đã duyệt hoàn thành']) {
    assert.match(workTabs, new RegExp(`"${label}"`));
  }
  // Work list counts live in the IconTabBar badge, not in the title.
  assert.match(src('ui/work/WorkScreen.kt'), /IconTabItem\(it\.title, it\.icon, counts\[it\] \?: 0\)/);
  // The personal / shared schedule hub buttons are unchanged.
  assert.doesNotMatch(src('ui/duties/DutiesTabHost.kt'), /IconTabBar/);
});

test('Android: 2.1.1 (52) version bump with icon-tab changelog entry', () => {
  const gradle = read('build.gradle.kts');
  assert.match(gradle, /val lvtVersionCode = 52/);
  assert.match(gradle, /val lvtVersionName = "2\.1\.1"/);
  const changelog = src('ui/profile/AppChangelog.kt');
  assert.match(changelog, /entries: List<AppChangelogEntry> = listOf\(\s*AppChangelogEntry\(\s*"2\.1\.1"/, '2.1.1 is the newest entry');
  assert.match(changelog, /Thanh tab có biểu tượng kèm chữ ở Lớp học, Trao đổi, Lịch công tác, Công việc; không còn tab bị che/);
});
