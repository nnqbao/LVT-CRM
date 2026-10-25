import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (file) => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
const ios = (file) => read(`ios-uikit-lvt/LvtCrmUIKit/${file}`);

test('iOS 4.0 (branch only): after the native sign-in the app shows the web app in a WKWebView', () => {
  const pbx = read('ios-uikit-lvt/LvtCrmUIKit.xcodeproj/project.pbxproj');
  assert.equal((pbx.match(/MARKETING_VERSION = 4\.0\.0;/g) || []).length, 2);
  assert.equal((pbx.match(/CURRENT_PROJECT_VERSION = 43;/g) || []).length, 2);
  for (const file of ['WebShellRules.swift', 'WebAppViewController.swift', 'QuickSignInViewController.swift']) {
    assert.equal((pbx.match(new RegExp(`/\\* ${file.replace('.', '\\.')} in Sources \\*/,`, 'g')) || []).length, 1, file);
  }
  assert.match(ios('ConvexConfig.swift'), /enum AppFeatures \{\n\s+static let webShell = true/);
  const coordinator = ios('AuthFlowCoordinator.swift');
  assert.match(coordinator, /case \.signedIn\(let session\) where AppFeatures\.webShell:/);
  assert.match(coordinator, /case \.offline:\n\s+root = OfflineStartViewController/);
  assert.match(coordinator, /if AppFeatures\.webShell \{ WebShellStorage\.clear\(\) \}/);
  assert.match(ios('AppChangelog.swift'), /static let entries: \[AppChangelogEntry\] = \[\s*AppChangelogEntry\(\s*version: "4\.0\.0"/);
  const plist = read('ios-uikit-lvt/LvtCrmUIKit/Info.plist');
  assert.match(plist, /<key>WKAppBoundDomains<\/key>\s*<array>\s*<string>lvt\.vscgroup\.io\.vn<\/string>/);
  assert.match(plist, /<key>LVTConvexURL<\/key>\s*<string>\$\(LVT_CONVEX_URL\)<\/string>/);
  assert.match(pbx, /LVT_CONVEX_URL = "https:\/\/confident-guanaco-953\.convex\.cloud";/, 'release builds default to prod');
  assert.match(pbx, /LVT_WEB_URL = "https:\/\/lvt\.vscgroup\.io\.vn";/);
});

test('iOS WebView shell: origin-checked bridge, separate session, nothing left after sign-out', () => {
  const shell = ios('WebAppViewController.swift');
  assert.match(shell, /guard message\.frameInfo\.isMainFrame,\n\s+WebShellRules\.origin\(scheme: origin\.protocol, host: origin\.host, port: origin\.port\) == WebShellRules\.origin\(webURL\)/);
  assert.match(shell, /guard let url = webView\.url, WebShellRules\.isWebAppURL\(url, webURL: webURL\) else \{ return \}/, 'replies only to the web app');
  assert.match(shell, /try await convex\.action\("appHandoff:issue"\)/);
  assert.doesNotMatch(shell, /accessToken|refreshToken|tokenStore/, 'the WebView never gets the app tokens');
  assert.match(shell, /configuration\.limitsNavigationsToAppBoundDomains = true/);
  assert.match(shell, /if userId != nil|userId != session\.userId/);
  assert.match(shell, /WKWebsiteDataStore\.default\(\)\.removeData\(\n\s+ofTypes: WKWebsiteDataStore\.allWebsiteDataTypes\(\)/);
  assert.match(shell, /try data\.write\(to: url, options: \[\.atomic, \.completeFileProtection\]\)/);
  // Debug-only simulator automation never ships.
  assert.match(shell, /#if DEBUG\n\/\/\/ Simulator end-to-end checks only/);
});
