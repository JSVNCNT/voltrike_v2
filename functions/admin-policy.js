'use strict';

function adminIdentityMatches(profile, claims) {
  if (!profile || profile.isActive === false) return false;
  if (!['developer_admin', 'toda_admin'].includes(profile.role)) return false;
  if (claims?.adminRole !== profile.role) return false;
  return profile.role !== 'toda_admin' || claims?.todaId === profile.todaId;
}

function canManageToda(profile, todaId) {
  if (profile?.role === 'developer_admin') return true;
  return profile?.role === 'toda_admin' &&
    typeof todaId === 'string' &&
    profile.todaId === todaId;
}

module.exports = {
  adminIdentityMatches,
  canManageToda,
};
