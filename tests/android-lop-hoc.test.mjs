import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (path) => readFileSync(new URL(`../android-app/app/${path}`, import.meta.url), 'utf8');
const src = (path) => read(`src/main/java/lvt/crm/${path}`);

test('Android: Lớp học menu replaces Lớp chủ nhiệm with five sections', () => {
  const strings = read('src/main/res/values/strings.xml');
  assert.match(strings, /<string name="nav_homeroom">Lớp học<\/string>/);
  const hub = src('ui/teaching/ClassesHubScreen.kt');
  for (const label of ['Tổng quan', 'Lớp chủ nhiệm', 'Lớp giảng dạy', 'Lịch dạy', 'Học bạ']) {
    assert.match(hub, new RegExp(`"${label}"`));
  }
  assert.match(src('ui/homeroom/HomeroomScreen.kt'), /title = "Lớp học"/);
  assert.match(src('ui/homeroom/HomeroomDetailScreen.kt'), /LessonLogs\("Sổ đầu bài"\)/);
  const repo = src('data/teaching/TeachingRepository.kt');
  for (const path of [
    'lessonLogs:myTeaching',
    'teachingCatalog:catalog',
    'lessonLogs:myLogsFor',
    'lessonLogs:save',
    'lessonLogs:listForClass',
    'teachers:schedule',
    'gradebook:myClasses',
    'gradebook:classStudents',
    'gradebook:studentRecord',
    'gradebook:addEntry',
    'gradebook:updateEntry',
    'gradebook:removeEntry',
  ]) {
    assert.ok(repo.includes(`"${path}"`), path);
  }
});

test('Android: Bán trú follows menuAccess.boarding', () => {
  const models = src('data/auth/AuthModels.kt');
  assert.match(models, /menuAccess\["boarding"\]/);
  assert.match(models, /canSeeBoarding: Boolean\s*\n\s*get\(\) = canUseApp && \(isOperationalManager \|\| boardingAccess != MenuAccess\.Hidden\)/);
});

test('Android: fingerprint and passkey sign-in reuse the password sign-in path', () => {
  const auth = src('data/auth/AuthRepository.kt');
  assert.match(auth, /QUICK_SIGN_IN_PROVIDERS = setOf\("device-key", "passkey"\)/);
  assert.match(auth, /return completeSignIn\(\s*"password"/);
  const device = src('data/auth/DeviceAuthRepository.kt');
  assert.match(device, /"lvt-crm:\$purpose:\$challengeId:\$challenge"/);
  assert.match(device, /auth\.signInWithProvider\(\s*"device-key"/);
  assert.match(device, /auth\.signInWithProvider\(\s*"passkey"/);
  assert.match(device, /deviceAuth:deviceLoginChallenge", JSONObject\(\), false/);
  const keys = src('data/auth/AndroidDeviceKeys.kt');
  assert.match(keys, /setUserAuthenticationParameters\(0, KeyProperties\.AUTH_BIOMETRIC_STRONG\)/);
  assert.match(keys, /setInvalidatedByBiometricEnrollment\(true\)/);
  assert.match(keys, /"lvt_crm_device_auth"/);
  assert.doesNotMatch(keys, /password/i);
  assert.match(src('MainActivity.kt'), /class MainActivity : FragmentActivity\(\)/);
  assert.match(src('ui/profile/ProfileScreen.kt'), /Đăng nhập bằng vân tay/);
  assert.match(src('ui/profile/ProfileScreen.kt'), /Tạo passkey/);
  assert.match(src('ui/auth/LoginScreen.kt'), /Đăng nhập bằng passkey/);
});

test('Android: 2.1.0 (51) version bump with changelog entry', () => {
  const gradle = read('build.gradle.kts');
  assert.match(gradle, /val lvtVersionCode = 51/);
  assert.match(gradle, /val lvtVersionName = "2\.1\.0"/);
  const changelog = src('ui/profile/AppChangelog.kt');
  assert.match(changelog, /entries: List<AppChangelogEntry> = listOf\(\s*AppChangelogEntry\(\s*"2\.1\.0"/, '2.1.0 is the newest entry');
  assert.match(changelog, /Lớp học/);
  assert.match(changelog, /vân tay/);
  assert.match(changelog, /Passkey/);
});
