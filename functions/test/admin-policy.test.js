'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { adminIdentityMatches, canManageToda } = require('../admin-policy');

test('developer admin requires matching active claim and profile', () => {
  const profile = { role: 'developer_admin', isActive: true };
  assert.equal(adminIdentityMatches(profile, { adminRole: 'developer_admin' }), true);
  assert.equal(adminIdentityMatches(profile, { adminRole: 'toda_admin' }), false);
  assert.equal(adminIdentityMatches({ ...profile, isActive: false }, {
    adminRole: 'developer_admin',
  }), false);
});

test('TODA admin claim and profile must name the same TODA', () => {
  const profile = { role: 'toda_admin', todaId: 'toda-a', isActive: true };
  assert.equal(adminIdentityMatches(profile, {
    adminRole: 'toda_admin',
    todaId: 'toda-a',
  }), true);
  assert.equal(adminIdentityMatches(profile, {
    adminRole: 'toda_admin',
    todaId: 'toda-b',
  }), false);
});

test('TODA scope never expands to another TODA', () => {
  assert.equal(canManageToda({ role: 'developer_admin' }, 'toda-b'), true);
  assert.equal(canManageToda({ role: 'toda_admin', todaId: 'toda-a' }, 'toda-a'), true);
  assert.equal(canManageToda({ role: 'toda_admin', todaId: 'toda-a' }, 'toda-b'), false);
});
