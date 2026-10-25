import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (file) => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
const android = (file) => read(`android-app/app/src/main/java/lvt/crm/${file}`);
const ios = (file) => read(`ios-uikit-lvt/LvtCrmUIKit/${file}`);

test('apps: assigned work is "Việc được giao"; "Việc của tôi" stays the personal to-do tab', () => {
  const work = android('ui/work/WorkScreen.kt');
  assert.equal((work.match(/title = "Việc được giao",/g) || []).length, 2);
  assert.match(work, /title = if \(created\) "Việc tôi tạo" else "Việc được giao",/);
  assert.doesNotMatch(work, /title = "Việc của tôi"/);
  assert.match(android('ui/work/WorkHubScreen.kt'), /IconTabItem\("Việc của tôi", Icons\.Outlined\.Checklist\)/);
  const iosWork = ios('WorkViewController.swift');
  assert.match(iosWork, /title: "Việc được giao",/);
  assert.match(iosWork, /emptyCell\(indexPath, "Việc được giao", detail\)/);
  assert.doesNotMatch(iosWork, /"Việc của tôi"/);
  assert.match(ios('WorkHubViewController.swift'), /IconTabBar\.Item\(title: "Việc của tôi", systemImage: "checklist"\)/);
});

test('apps: no English "task" in work error messages (same wording as the web)', () => {
  assert.match(android('data/convex/WorkErrorMessages.kt'), /"WORK_EXECUTOR_REQUIRED" to "Chỉ người được giao mới được hoàn thành việc này\."/);
  assert.match(ios('ConvexHttpClient.swift'), /case "WORK_COMPLETION_NOT_PENDING": return "Việc này không còn ở trạng thái chờ duyệt hoàn thành\."/);
  for (const source of [android('data/convex/WorkErrorMessages.kt'), ios('ConvexHttpClient.swift')]) {
    assert.doesNotMatch(source, /(?:\bto|\breturn) "[^"\n]*\b[Tt]ask\b/, 'no message says "task"');
  }
});

test('apps: Ghi nhận lỗi / Đánh giá nhân sự notifications are labelled and open their web page', () => {
  const destination = android('push/NotificationDestination.kt');
  assert.match(destination, /val opensWeb: Boolean\n\s+get\(\) = kind == "people"/);
  assert.match(destination, /return if \(target == "staff-faults"\) "\/ghi-nhan-loi" else "\/danh-gia-nhan-su"/);
  assert.match(android('data/notifications/NotificationsRepository.kt'), /menu = item\.optString\("menu"\),/);
  assert.match(android('push/NotificationCenter.kt'), /putExtra\(NotificationDestination\.EXTRA_MENU, item\.menu\)/);
  const root = android('ui/LvtRoot.kt');
  assert.equal((root.match(/WebPage\.open\(context, WebPage\.url\(destination\.webPath\)\)/g) || []).length, 2, 'bell tap and push tap');
  const presentation = android('push/NotificationPresentation.kt');
  assert.match(presentation, /kind == "people" -> peopleLabel\(sourceType\)/);
  assert.match(presentation, /fun peopleLabel\(sourceType: String\) = if \(sourceType == STAFF_FAULT\) "Ghi nhận lỗi" else "Đánh giá nhân sự"/);

  const models = ios('NotificationModels.swift');
  assert.match(models, /var opensWeb: Bool \{ kind == "people" \}/);
  assert.match(models, /return target == "staff-faults" \? "\/ghi-nhan-loi" : "\/danh-gia-nhan-su"/);
  assert.match(models, /sourceType == "staff_fault" \? "Ghi nhận lỗi" : "Đánh giá nhân sự"/);
  assert.match(ios('NotificationsRepository.swift'), /menu: \(item\["menu"\] as\? String\) \?\? ""/);
  assert.match(ios('NotificationCenterService.swift'), /"menu": item\.menu,/);
  const tabs = ios('RootTabBarController.swift');
  assert.match(tabs, /if destination\.opensWeb \{[\s\S]*?presentWebPage\(url\)[\s\S]*?markRead\(destination, markNotificationRead\)\n\s+return\n\s+\}/);
  assert.match(ios('NotificationsViewController.swift'), /if item\.kind == "people" \{ return NotificationPeople\.label\(sourceType: item\.sourceType\) \}/);
  // Same routes as the web menus (src/navigationRoutes.js).
  const routes = read('src/navigationRoutes.js');
  assert.match(routes, /'people-review': '\/danh-gia-nhan-su'/);
  assert.match(routes, /'staff-faults': '\/ghi-nhan-loi'/);
});

test('apps: Android 2.1.2 (53) and iOS 3.1.3 (42) with changelog entries', () => {
  const gradle = read('android-app/app/build.gradle.kts');
  assert.match(gradle, /val lvtVersionCode = 53\nval lvtVersionName = "2\.1\.2"/);
  assert.match(android('ui/profile/AppChangelog.kt'), /entries: List<AppChangelogEntry> = listOf\(\s*AppChangelogEntry\(\s*"2\.1\.2",[\s\S]*?Việc được giao[\s\S]*?Ghi nhận lỗi/);
  const pbx = read('ios-uikit-lvt/LvtCrmUIKit.xcodeproj/project.pbxproj');
  assert.equal((pbx.match(/MARKETING_VERSION = 3\.1\.3;/g) || []).length, 2);
  assert.equal((pbx.match(/CURRENT_PROJECT_VERSION = 42;/g) || []).length, 2);
  assert.match(ios('AppChangelog.swift'), /static let entries: \[AppChangelogEntry\] = \[\s*AppChangelogEntry\(\s*version: "3\.1\.3",[\s\S]*?Việc được giao[\s\S]*?Ghi nhận lỗi/);
});
