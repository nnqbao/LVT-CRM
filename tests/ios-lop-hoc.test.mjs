import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL(`../ios-uikit-lvt/${path}`, import.meta.url), 'utf8');
const root = read('LvtCrmUIKit/RootTabBarController.swift');
const hub = read('LvtCrmUIKit/ClassesHubViewController.swift');
const detail = read('LvtCrmUIKit/HomeroomDetailViewController.swift');
const auth = read('LvtCrmUIKit/AuthRepository.swift');
const quick = read('LvtCrmUIKit/QuickSignInService.swift');
const login = read('LvtCrmUIKit/LoginViewController.swift');
const profile = read('LvtCrmUIKit/ProfileViewController.swift');
const boarding = read('LvtCrmUIKit/Boarding.swift');
const pbx = read('LvtCrmUIKit.xcodeproj/project.pbxproj');
const changelog = read('LvtCrmUIKit/AppChangelog.swift');
const infoPlist = read('LvtCrmUIKit/Info.plist');

test('iOS tab is named Lớp học and keeps the tab order', () => {
  assert.match(root, /viewControllers = \[overview\] \+ makeStudentTabs\(\) \+ \[chat, duties, work\]/);
  assert.match(root, /navigationController\(title: "Lớp học", systemImage: "person\.3"/);
  assert.doesNotMatch(root, /title: "Lớp chủ nhiệm"/);
  assert.match(root, /ClassesHubViewController\(session: session/);
});

test('Lớp học hub has the five sections and class detail has Sổ đầu bài', () => {
  for (const label of ['Tổng quan', 'Chủ nhiệm', 'Giảng dạy', 'Lịch dạy', 'Học bạ']) {
    assert.match(hub, new RegExp(`return "${label}"`));
  }
  assert.match(hub, /HomeroomViewController\(repository: homeroomRepository, session: session\)/);
  assert.match(detail, /\["Điểm danh", "Danh sách lớp", "Sổ đầu bài"\]/);
  assert.match(read('LvtCrmUIKit/HomeroomRepository.swift'), /lessonLogs:listForClass/);
});

test('teaching repository calls the contract functions', () => {
  const teaching = read('LvtCrmUIKit/Teaching.swift');
  for (const path of [
    'lessonLogs:myTeaching',
    'teachingCatalog:catalog',
    'lessonLogs:myLogsFor',
    'lessonLogs:save',
    'teachers:schedule',
    'gradebook:myClasses',
    'gradebook:classStudents',
    'gradebook:studentRecord',
    'gradebook:addEntry',
    'gradebook:updateEntry',
    'gradebook:removeEntry',
    'homeroomReports:overview',
  ]) {
    assert.ok(teaching.includes(`"${path}"`), path);
  }
});

test('device-key and passkey sign-in reuse the password sign-in path', () => {
  assert.match(auth, /private func signIn\(provider: String, params: \[String: Any\]\)/);
  assert.match(auth, /provider: "password"/);
  assert.match(auth, /provider: "device-key"/);
  assert.match(auth, /provider: "passkey"/);
  assert.match(auth, /args: \["provider": provider, "params": params\]/);
  assert.match(quick, /deviceAuth:deviceLoginChallenge", authenticated: false/);
  assert.match(quick, /deviceAuth:passkeyLoginOptions", authenticated: false/);
  assert.match(quick, /kSecAttrTokenIDSecureEnclave/);
  assert.match(quick, /\.biometryCurrentSet/);
  assert.match(quick, /kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly/);
  assert.match(quick, /presentationContextProvider = self/);
});

test('login and profile expose the quick sign-in controls', () => {
  assert.match(login, /Đăng nhập bằng passkey/);
  assert.match(login, /biometricButton, passkeyButton, modeButton/);
  assert.match(login, /authRepository\.bootstrapError/);
  assert.match(profile, /UISwitch\(\)/);
  assert.match(profile, /Tạo passkey/);
  assert.doesNotMatch(profile, /accessibilityLabel = "Vai trò, \(session/);
  assert.doesNotMatch(profile, /accessibilityLabel = "\(values/);
});

test('Bán trú follows the boarding menu', () => {
  assert.match(boarding, /menuAccess\["boarding"\]/);
  assert.doesNotMatch(boarding, /menuAccess\["reports"\]/);
});

test('entitlements, Face ID usage text, version and changelog', () => {
  for (const name of ['LvtCrmUIKit.entitlements', 'LvtCrmUIKitRelease.entitlements']) {
    const plist = read(`LvtCrmUIKit/${name}`);
    assert.match(plist, /com\.apple\.developer\.associated-domains/);
    assert.match(plist, /webcredentials:lvt\.vscgroup\.io\.vn/);
  }
  assert.match(infoPlist, /NSFaceIDUsageDescription/);
  // Lớp học / Face ID / passkey shipped in 3.1.0 (39); later builds must stay at or above it.
  const versions = [...pbx.matchAll(/MARKETING_VERSION = (\d+)\.(\d+)\.(\d+);/g)].map((m) => m.slice(1).map(Number));
  assert.equal(versions.length, 2);
  for (const [major, minor] of versions) assert.ok(major > 3 || (major === 3 && minor >= 1));
  const builds = [...pbx.matchAll(/CURRENT_PROJECT_VERSION = (\d+);/g)].map((m) => Number(m[1]));
  assert.ok(builds.length === 2 && builds.every((build) => build >= 39));
  for (const file of [
    'Teaching.swift',
    'QuickSignIn.swift',
    'QuickSignInService.swift',
    'ClassesHubViewController.swift',
    'TeachingViewControllers.swift',
    'TeachingScheduleViewController.swift',
    'GradebookViewControllers.swift',
  ]) {
    assert.equal(pbx.match(new RegExp(`/\\* ${file.replace('.', '\\.')} in Sources \\*/`, 'g'))?.length, 2, file);
  }
  assert.match(changelog, /version: "3\.1\.0"/);
  assert.match(changelog, /Face ID \/ Touch ID/);
  assert.match(changelog, /passkey/);
});
