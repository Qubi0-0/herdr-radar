'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { formatAge, nextAgeChange } = require('../lib/state');

const MIN = 60000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

test('each unit takes over at its own boundary, rounded down', () => {
  assert.equal(formatAge(0), '0m');
  assert.equal(formatAge(MIN - 1), '0m');
  assert.equal(formatAge(59 * MIN + 59999), '59m');
  assert.equal(formatAge(HOUR), '1h');
  assert.equal(formatAge(23 * HOUR + 59 * MIN), '23h');
  assert.equal(formatAge(DAY), '1d');
  assert.equal(formatAge(17 * DAY + 5 * HOUR), '17d');
});

test('a stamp from the future reads as just now', () => {
  assert.equal(formatAge(-5 * MIN), '0m');
});

test('the next change lands where the text changes', () => {
  const at = 1_000_000;
  assert.equal(nextAgeChange(at, at), at + MIN);
  assert.equal(nextAgeChange(at, at + 7 * MIN + 30000), at + 8 * MIN);
  assert.equal(nextAgeChange(at, at + 59 * MIN), at + HOUR);
  assert.equal(nextAgeChange(at, at + 3 * HOUR + 10 * MIN), at + 4 * HOUR);
  assert.equal(nextAgeChange(at, at + 2 * DAY), at + 3 * DAY);
  for (const elapsed of [0, 30000, 59 * MIN, 5 * HOUR, 3 * DAY + 1]) {
    const next = nextAgeChange(at, at + elapsed);
    assert.notEqual(formatAge(next - at), formatAge(elapsed));
    assert.equal(formatAge(next - 1 - at), formatAge(elapsed));
  }
});
