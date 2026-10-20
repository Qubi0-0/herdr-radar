'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const config = require('../lib/config');
const managed = require('../lib/managed-config');
const { terminalLines, TERMINAL_TOKENS } = require('../lib/state');

const pane = (id, ws, tab, extra = {}) => ({ pane_id: id, workspace_id: ws, tab_id: tab, agent: null, ...extra });

test('only panes without an agent are listed, named by their tab', () => {
  const lines = terminalLines(
    [
      pane('w1:p1', 'w1', 't1'),
      pane('w1:p2', 'w1', 't2', { agent: 'claude' }),
      pane('w2:p1', 'w2', 't3', { agent: 'codex' }),
    ],
    new Map([
      ['t1', 'logs'],
      ['t2', 'review'],
      ['t3', 'build'],
    ]),
  );
  assert.deepEqual([...lines], [['w1', ['▸ logs']]]);
});

test('an unnamed tab falls back to the terminal title, then the pane id', () => {
  const lines = terminalLines(
    [pane('w1:p1', 'w1', 't1', { terminal_title_stripped: 'htop' }), pane('w1:p2', 'w1', 't2')],
    new Map([
      ['t1', '3'],
      ['t2', ''],
    ]),
  );
  assert.deepEqual(lines.get('w1'), ['▸ htop', '▸ w1:p2']);
});

test('past the line budget the last line counts the rest', () => {
  const panes = Array.from({ length: 7 }, (_, i) => pane(`w1:p${i}`, 'w1', `t${i}`));
  const tabs = new Map(panes.map((p, i) => [p.tab_id, `term${i}`]));
  assert.deepEqual(terminalLines(panes, tabs, 4).get('w1'), ['▸ term0', '▸ term1', '▸ term2', '+4']);
  assert.equal(terminalLines(panes, tabs, 7).get('w1').length, 7);
});

test('a workspace with only agents has no entry', () => {
  assert.equal(terminalLines([pane('w1:p1', 'w1', 't1', { agent: 'claude' })], new Map()).size, 0);
});

test('the terminals block hides empty entries and stays within the row limit', (t) => {
  const before = config.spacesMode;
  t.after(() => {
    config.spacesMode = before;
  });
  config.spacesMode = 'terminals';
  const spaces = managed.sidebarBlock('dark').split('[ui.sidebar.spaces]')[1];
  assert.match(spaces, /^hide_empty = true$/m);
  const rows = spaces.match(/^ {2}\[/gm) ?? [];
  assert.equal(rows.length, 1 + TERMINAL_TOKENS.length);
  assert.ok(rows.length <= 16);
  for (const name of TERMINAL_TOKENS) assert.ok(spaces.includes(`$${name}`));

  config.spacesMode = 'agents';
  assert.doesNotMatch(managed.sidebarBlock('dark'), /hide_empty/);
});
