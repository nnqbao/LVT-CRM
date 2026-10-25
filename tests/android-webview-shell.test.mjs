import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (file) => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
const src = (file) => read(`android-app/app/src/main/java/lvt/crm/${file}`);

test('Android 3.0: after the native sign-in the app shows the web app in a WebView', () => {
  const gradle = read('android-app/app/build.gradle.kts');
  assert.match(gradle, /val lvtVersionCode = 54\nval lvtVersionName = "3\.0\.0"/);
  assert.match(gradle, /buildConfigField\("boolean", "WEB_SHELL", "true"\)/);
  assert.match(gradle, /implementation\("androidx\.webkit:webkit:1\.12\.1"\)/);
  const root = src('ui/LvtRoot.kt');
  assert.match(root, /if \(BuildConfig\.WEB_SHELL\) \{\n\s+val context = LocalContext\.current\n\s+WebAppShell\(/);
  assert.match(root, /AuthState\.Offline -> OfflineStartScreen\(/);
  assert.match(src('ui/profile/AppChangelog.kt'), /entries: List<AppChangelogEntry> = listOf\(\s*AppChangelogEntry\(\s*"3\.0\.0"/);
});

test('Android WebView shell: origin-restricted bridge, separate session, nothing left after sign-out', () => {
  const shell = src('ui/web/WebAppShell.kt');
  assert.match(shell, /WebViewCompat\.addWebMessageListener\(this, WebShellRules\.BRIDGE_NAME, setOf\(origin\)\)/);
  assert.match(shell, /if \(isMainFrame\) message\.data\?\.let/);
  assert.match(shell, /container\.convex\.action\("appHandoff:issue", JSONObject\(\)\)/);
  assert.doesNotMatch(shell, /accessToken|refreshToken|tokenStore/, 'the WebView never gets the app tokens');
  assert.match(shell, /settings\.allowFileAccess = false/);
  assert.match(shell, /settings\.allowContentAccess = false/);
  assert.match(shell, /MIXED_CONTENT_NEVER_ALLOW/);
  assert.match(shell, /WebView\.setWebContentsDebuggingEnabled\(BuildConfig\.DEBUG\)/);
  assert.match(shell, /layoutParams = ViewGroup\.LayoutParams\(ViewGroup\.LayoutParams\.MATCH_PARENT, ViewGroup\.LayoutParams\.MATCH_PARENT\)/, '100dvh is 0 otherwise');
  // Another account's leftover web session is signed out, never shown.
  assert.match(shell, /if \(webUserId\.isNotBlank\(\) && webUserId != session\.userId\) \{\n\s+post\(proxy, JSONObject\(\)\.put\("type", "sign-out"\)\.toString\(\)\)/);
  assert.match(shell, /runCatching \{ WebStorage\.getInstance\(\)\.deleteAllData\(\) \}/);
  assert.match(shell, /runCatching \{ WebView\(context\)\.apply \{ clearCache\(true\) \}\.destroy\(\) \}/);
  const root = src('ui/LvtRoot.kt');
  assert.match(root, /LaunchedEffect\(Unit\) \{ if \(BuildConfig\.WEB_SHELL\) WebShellStorage\.clear\(context\) \}/);
  assert.match(root, /onSignOut = \{\n\s+WebShellStorage\.clear\(context\)/);
});

test('Android: network trouble at start keeps the sign-in and shows Không có kết nối', () => {
  assert.match(src('data/auth/AuthModels.kt'), /data object Offline : AuthState/);
  const repo = src('data/auth/AuthRepository.kt');
  assert.match(repo, /_state\.value = if \(isConnectivityFailure\(e\)\) AuthState\.Offline else AuthState\.SignedOut/, 'only real connectivity failures');
  assert.match(repo, /error is java\.io\.IOException \|\| \(error is ConvexException && error\.code\.startsWith\("HTTP_"\)\)/);
  // The offline start screen retries only when the network comes back (never in a loop).
  assert.match(src('ui/web/WebAppShell.kt'), /val cameBack = !wasOnline\n\s+wasOnline = true\n\s+if \(cameBack\) scope\.launch \{ onRetry\(\) \}/);
  assert.match(src('ui/web/WebAppShell.kt'), /title = "Không có kết nối",/);
  assert.match(read('android-app/app/src/main/AndroidManifest.xml'), /android\.permission\.ACCESS_NETWORK_STATE/);
  assert.match(read('android-app/app/src/main/res/xml/file_paths.xml'), /<cache-path name="web_files" path="web-files\/" \/>/);
});
