import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL(`../ios-uikit-lvt/${path}`, import.meta.url), 'utf8');

test('iOS IconTabBar: equal-width items, icon over a wrapping label, badges, accessible', () => {
  const bar = read('LvtCrmUIKit/IconTabBar.swift');
  assert.match(bar, /distribution = \.fillEqually/);
  assert.match(bar, /imagePlacement = \.top/);
  assert.match(bar, /titleLineBreakMode = \.byWordWrapping/);
  assert.match(bar, /maximumPointSize: 15/);
  assert.match(bar, /count > 99 \? "99\+"/);
  assert.match(bar, /\[\.button, \.selected\]/);
  assert.match(read('LvtCrmUIKit.xcodeproj/project.pbxproj'), /IconTabBar\.swift in Sources/);
});

test('iOS: Lớp học, Trao đổi, Lịch công tác and Công việc use the icon tab bar', () => {
  assert.match(read('LvtCrmUIKit/ClassesHubViewController.swift'), /IconTabBar\(items: Section\.allCases/);
  assert.match(read('LvtCrmUIKit/ChatHubViewController.swift'), /private let filters = IconTabBar\(items:/);
  assert.match(read('LvtCrmUIKit/DutiesViewController.swift'), /IconTabBar\(\s*items: DutyListTab\.allCases/);
  assert.match(read('LvtCrmUIKit/WorkHubViewController.swift'), /private let control = IconTabBar\(items:/);
  const work = read('LvtCrmUIKit/WorkViewController.swift');
  assert.match(work, /IconTabBar\(items: WorkListTab\.allCases/);
  assert.match(work, /control\.setBadge\(counts\[item\] \?\? 0, at: index\)/);
  assert.doesNotMatch(work, /systemFont\(ofSize: 10/, 'no more 10 pt tab text');
  for (const file of ['ClassesHubViewController', 'ChatHubViewController', 'WorkHubViewController']) {
    assert.doesNotMatch(read(`LvtCrmUIKit/${file}.swift`), /UISegmentedControl\(items/);
  }
});
