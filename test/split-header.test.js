'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { splitHeads } = require('../lib/state');

const entry = (pane, tab) => ({ pane, tab, workspace: 'w1' });

test('a named tab with two or more panes is headed by its first pane in display order', () => {
  const entries = [entry('p3', 't1'), entry('p1', 't1'), entry('p2', 't1')];
  const { heads, tabs } = splitHeads(entries, new Map([['t1', 'SDP-7814 review']]));
  assert.deepEqual([...heads], [['p3', 'SDP-7814 review']]);
  assert.deepEqual([...tabs], ['t1']);
});

test('a lone pane is no split and gets no header', () => {
  const { heads, tabs } = splitHeads([entry('p1', 't1')], new Map([['t1', 'review']]));
  assert.equal(heads.size, 0);
  assert.equal(tabs.size, 0);
});

test('an unnamed tab has only its number, so its panes stay plain rows', () => {
  const entries = [entry('p1', 't1'), entry('p2', 't1')];
  for (const name of ['3', '  ', undefined]) {
    const labels = name === undefined ? new Map() : new Map([['t1', name]]);
    assert.equal(splitHeads(entries, labels).tabs.size, 0, `label ${JSON.stringify(name)}`);
  }
});

test('each split screen is headed on its own and a pane with no tab is skipped', () => {
  const entries = [entry('p1', 't1'), entry('p2', 't2'), entry('p3', 't1'), entry('p4', 't2'), { pane: 'p5' }];
  const { heads } = splitHeads(
    entries,
    new Map([
      ['t1', ' architecture '],
      ['t2', 'nightly'],
    ]),
  );
  assert.deepEqual(
    [...heads],
    [
      ['p1', 'architecture'],
      ['p2', 'nightly'],
    ],
  );
});
