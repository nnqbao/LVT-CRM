import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const auth = readFileSync(new URL('../ios-uikit-lvt/LvtCrmUIKit/AuthRepository.swift', import.meta.url), 'utf8');
const coordinator = readFileSync(new URL('../ios-uikit-lvt/LvtCrmUIKit/AuthFlowCoordinator.swift', import.meta.url), 'utf8');
const login = readFileSync(new URL('../ios-uikit-lvt/LvtCrmUIKit/LoginViewController.swift', import.meta.url), 'utf8');
const changelog = readFileSync(new URL('../ios-uikit-lvt/LvtCrmUIKit/AppChangelog.swift', import.meta.url), 'utf8');

test('iOS cold-start restore never retries forever: no network → Không có kết nối, other failures → login', () => {
  assert.doesNotMatch(auth, /scheduleRestoreRetry/);
  assert.doesNotMatch(auth, /restoreRetryScheduled/);
  assert.match(auth, /if Self\.isConnectivityFailure\(error\) \{\s*state = \.offline\s*\} else \{\s*bootstrapError =/s);
  assert.match(auth, /state = \.signedOut/);
  assert.match(auth, /guard let credentials else \{\s*if authGeneration == generation \{ state = \.signedOut \}/s);
  // Offline retries only on "Thử lại" or when the network comes back (never on the first path update).
  assert.match(auth, /func retryRestore\(\) async \{\s*guard case \.offline = state else \{ return \}/s);
  const web = readFileSync(new URL('../ios-uikit-lvt/LvtCrmUIKit/WebAppViewController.swift', import.meta.url), 'utf8');
  assert.match(web, /guard online, wasOnline == false else \{ return \}/);
});

test('iOS session fetch timeout does not hop back onto MainActor via self.loadSessionContext', () => {
  assert.doesNotMatch(auth, /self\.loadSessionContext/);
  assert.match(auth, /client\.query\("users:sessionContext"\)/);
  assert.match(auth, /UserSession\(sessionContext: result\)/);
  assert.match(auth, /fetchSession\(timeoutSeconds: 12\)/);
  assert.match(auth, /SESSION_TIMEOUT/);
});

test('iOS restore reads the keychain from a child task with a timeout', () => {
  assert.match(auth, /private func readStoredCredentials\(\) async -> CredentialSnapshot\?/);
  assert.match(auth, /store\.snapshot\(\)/);
  assert.match(auth, /Task\.sleep\(for: \.seconds\(5\)\)/);
});

test('auth flow leaves the loading spinner after a watchdog timeout', () => {
  assert.match(coordinator, /failOpenIfStillLoading\(\)/);
  assert.match(coordinator, /Task\.sleep\(for: \.seconds\(15\)\)/);
  assert.match(coordinator, /LoginViewController/);
  assert.match(login, /authRepository\.bootstrapError/);
});

test('iOS 1.8.4 records the splash hang fix', () => {
  assert.match(changelog, /version: "1\.8\.4"/);
  assert.match(changelog, /treo màn hình tải/);
});

test('iOS changelog still records the 1.9.0 header-cluster change', () => {
  assert.match(changelog, /version: "1\.9\.0"/);
  assert.match(changelog, /Đổi ảnh đại diện/);
});
