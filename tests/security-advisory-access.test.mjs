// SPDX-FileCopyrightText: 2026 LibreSign contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { reconcileAdvisoryAccess, validatePolicy } from '../scripts/reconcile-security-advisory-access.mjs';

const id = 'GHSA-2345-6789-cfgh';
const repository = 'LibreSign/libresign';
const data = {
  ghsa_id: id, state: 'draft', created_at: '2026-12-01T00:00:00Z',
  published_at: null, collaborating_teams: [],
  collaborating_users: [{ login: 'independent-reporter' }],
};
const policy = validatePolicy({
  schema_version: 1, repository, team: 'security-response',
  created_after: '2026-11-04T15:00:00Z',
});

function fakeGithub(initial = [data], status = 200) {
  const records = new Map(initial.map((item) => [item.ghsa_id, structuredClone(item)]));
  const writes = [];
  const calls = [];
  const fetchImpl = async (url, options) => {
    const target = new URL(url);
    const path = target.pathname;
    calls.push({ method: options.method, path, query: target.search });
    if (status !== 200) return new Response('{}', { status });
    if (path.endsWith('/security-advisories')) {
      return Response.json([...records.values()]);
    }
    const actualId = path.split('/').at(-1);
    const current = records.get(actualId);
    if (!current) return new Response('{}', { status: 404 });
    if (options.method === 'PATCH') {
      const update = JSON.parse(options.body);
      writes.push(update);
      if (Object.keys(update).join(',') !== 'collaborating_teams') {
        throw new Error('Forbidden advisory field mutation');
      }
      current.collaborating_teams = update.collaborating_teams.map((slug) => ({ slug }));
      records.set(actualId, current);
    }
    return Response.json(current);
  };
  return { records, writes, calls, fetchImpl };
}
const run = (github, apply = false, currentPolicy = policy) => reconcileAdvisoryAccess({
  policy: currentPolicy, token: 'synthetic-token', apply, fetchImpl: github.fetchImpl,
});

test('accepts only exact repository, constrained team and explicit adoption time', () => {
  assert.equal(policy.repository, repository);
  assert.throws(() => validatePolicy({ schema_version: 1, repository: 'LibreSign/unrelated', team: 'security-response', created_after: '2026-12-01T00:00:00Z' }));
  assert.throws(() => validatePolicy({ schema_version: 1, repository, team: '../invalid', created_after: '2026-12-01T00:00:00Z' }));
  assert.throws(() => validatePolicy({ schema_version: 1, repository, team: 'security-response', created_after: 'not-a-date' }));
  assert.throws(() => validatePolicy({ schema_version: 1, repository, team: 'security-response', created_after: '2026-12-01T00:00:00Z', secret: 'unexpected' }));
});

test('dry run never patches the private advisory', async () => {
  const github = fakeGithub();
  const report = await run(github);
  assert.deepEqual(report, { checked: 1, alreadyGranted: 0, wouldGrant: 1, granted: 0 });
  assert.deepEqual(github.writes, []);
  assert.ok(github.calls.every(({ method }) => method === 'GET'));
});

test('apply changes only team membership, preserving reporter and other teams', async () => {
  const github = fakeGithub([{ ...data, collaborating_teams: [{ slug: 'trusted-researchers' }] }]);
  const report = await run(github, true);
  assert.equal(report.granted, 1);
  assert.deepEqual(github.writes, [{ collaborating_teams: ['trusted-researchers', 'security-response'] }]);
  const record = github.records.get(id);
  assert.deepEqual(record.collaborating_users, [{ login: 'independent-reporter' }]);
  assert.equal(record.state, 'draft');
  assert.equal(record.published_at, null);
  assert.ok(github.calls.every(({ path }) => path.includes('/LibreSign/libresign/security-advisories')));
});

test('idempotent replay does not write again', async () => {
  const github = fakeGithub();
  await run(github, true);
  const second = await run(github, true);
  assert.equal(second.alreadyGranted, 1);
  assert.equal(github.writes.length, 1);
});

test('ignores older, published, and closed advisories without touching them', async () => {
  const github = fakeGithub([
    { ...data, created_at: '2026-01-01T00:00:00Z' },
    { ...data, ghsa_id: 'GHSA-2345-6789-cfg2', state: 'published', published_at: '2026-12-02T00:00:00Z' },
    { ...data, ghsa_id: 'GHSA-2345-6789-cfg3', state: 'closed' },
  ]);
  const result = await run(github, true);
  assert.equal(result.checked, 0);
  assert.equal(github.writes.length, 0);
});

test('supports a privately reported advisory in triage without changing its state', async () => {
  const github = fakeGithub([{ ...data, state: 'triage' }]);
  assert.equal((await run(github, true)).granted, 1);
  assert.equal(github.records.get(id).state, 'triage');
});

test('fails closed if collaborator metadata is missing', async () => {
  const github = fakeGithub([{ ...data, collaborating_users: undefined }]);
  await assert.rejects(run(github, true), /existing advisory collaborators/);
  assert.equal(github.writes.length, 0);
});

test('fails closed when GitHub denies access', async () => {
  const github = fakeGithub([data], 403);
  await assert.rejects(run(github, true), /GitHub advisory access API request failed/);
  assert.equal(github.writes.length, 0);
});

test('fails closed on invalid GHSA identifiers', async () => {
  const github = fakeGithub([{ ...data, ghsa_id: '../../another-resource' }]);
  await assert.rejects(run(github, true), /Unexpected advisory identifier/);
  assert.equal(github.writes.length, 0);
});

test('does not accept unusable credentials', async () => {
  await assert.rejects(reconcileAdvisoryAccess({ policy, token: '' }), /Missing advisory access credentials/);
});
