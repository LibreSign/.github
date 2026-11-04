// SPDX-FileCopyrightText: 2026 LibreSign contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const GHSA_PATTERN = /^GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}$/;
const OPEN_STATES = new Set(['draft', 'triage']);

export function validatePolicy(raw, allowedRepository = 'LibreSign/libresign') {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new Error('Invalid security access policy');
  }
  const keys = Object.keys(raw).sort();
  if (JSON.stringify(keys) !== JSON.stringify(['created_after', 'repository', 'schema_version', 'team'].sort()) ||
      raw.schema_version !== 1 || raw.repository !== allowedRepository ||
      typeof raw.team !== 'string' || !/^[a-z0-9][a-z0-9-]{1,38}$/.test(raw.team) ||
      typeof raw.created_after !== 'string' ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(raw.created_after) ||
      !Number.isFinite(Date.parse(raw.created_after))) {
    throw new Error('Invalid or unexpected security access policy');
  }
  return Object.freeze({
    repository: raw.repository,
    team: raw.team,
    createdAfter: Date.parse(raw.created_after),
  });
}

function collaboratorLogins(advisory) {
  if (!Array.isArray(advisory.collaborating_users) ||
      !advisory.collaborating_users.every((user) => typeof user?.login === 'string')) {
    throw new Error('Cannot verify existing advisory collaborators');
  }
  return advisory.collaborating_users.map((user) => user.login).sort();
}

function teamSlugs(advisory) {
  if (!Array.isArray(advisory.collaborating_teams) ||
      !advisory.collaborating_teams.every((team) => typeof team?.slug === 'string')) {
    throw new Error('Cannot verify advisory team membership');
  }
  return advisory.collaborating_teams.map((team) => team.slug);
}

function eligible(advisory, policy) {
  if (!OPEN_STATES.has(advisory.state) || advisory.published_at !== null ||
      typeof advisory.created_at !== 'string' ||
      !Number.isFinite(Date.parse(advisory.created_at))) return false;
  return Date.parse(advisory.created_at) >= policy.createdAfter;
}

function equalSets(left, right) {
  return JSON.stringify([...new Set(left)].sort()) === JSON.stringify([...new Set(right)].sort());
}

export async function reconcileAdvisoryAccess({ policy, token, apply = false, fetchImpl = fetch, baseUrl = 'https://api.github.com' }) {
  if (typeof token !== 'string' || token.length < 8 || !/^https:\/\//.test(baseUrl)) {
    throw new Error('Missing advisory access credentials');
  }
  const prefix = `/repos/${policy.repository.split('/').map(encodeURIComponent).join('/')}/security-advisories`;
  async function api(method, path, body) {
    const response = await fetchImpl(`${baseUrl}${path}`, {
      method,
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: `Bearer ${token}`,
        'X-GitHub-Api-Version': '2022-11-28',
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error('GitHub advisory access API request failed');
    return response.json();
  }

  const report = { checked: 0, alreadyGranted: 0, wouldGrant: 0, granted: 0 };
  for (let page = 1; page <= 20; page++) {
    // Do not set state=all: GitHub treats it as a literal state and returns no advisories.
    const batch = await api('GET', `${prefix}?per_page=100&page=${page}`);
    if (!Array.isArray(batch)) throw new Error('Unexpected security advisory listing');
    for (const item of batch) {
      if (!eligible(item, policy)) continue;
      if (typeof item.ghsa_id !== 'string' || !GHSA_PATTERN.test(item.ghsa_id)) {
        throw new Error('Unexpected advisory identifier');
      }
      const path = `${prefix}/${encodeURIComponent(item.ghsa_id)}`;
      const advisory = await api('GET', path);
      if (!eligible(advisory, policy) || advisory.ghsa_id !== item.ghsa_id) continue;
      const existingTeams = teamSlugs(advisory);
      const existingUsers = collaboratorLogins(advisory);
      report.checked++;
      if (existingTeams.includes(policy.team)) {
        report.alreadyGranted++;
        continue;
      }
      report.wouldGrant++;
      if (!apply) continue;
      // This is the ONLY mutation. Never send state, credits, collaborating_users,
      // summary, vulnerabilities, private_fork, or any embargoed metadata.
      await api('PATCH', path, { collaborating_teams: [...new Set([...existingTeams, policy.team])] });
      const verified = await api('GET', path);
      if (verified.state !== advisory.state || verified.published_at !== null ||
          !teamSlugs(verified).includes(policy.team) ||
          !existingTeams.every((slug) => teamSlugs(verified).includes(slug)) ||
          !equalSets(existingUsers, collaboratorLogins(verified))) {
        throw new Error('Advisory access postcondition could not be verified');
      }
      report.granted++;
    }
    if (batch.length < 100) return report;
  }
  throw new Error('Advisory listing exceeds reviewable limit');
}

async function main() {
  const config = JSON.parse(await readFile(resolve('security-advisory-access.config.json'), 'utf8'));
  const allowedRepository = process.env.ADVISORY_ALLOWED_REPOSITORY;
  const expectedTeam = process.env.ADVISORY_ALLOWED_TEAM;
  const policy = validatePolicy(config, allowedRepository);
  if (expectedTeam !== policy.team) throw new Error('Expected team does not match policy');
  const apply = process.env.ADVISORY_ACCESS_APPLY === 'true';
  await reconcileAdvisoryAccess({ policy, token: process.env.ADVISORY_ACCESS_TOKEN, apply });
  // Never log advisory identifiers, names, fork information, or aggregate counts.
  process.stdout.write('Security advisory access reconciliation finished.\n');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => {
    process.stderr.write('Security advisory access reconciliation could not be verified.\n');
    process.exitCode = 1;
  });
}
