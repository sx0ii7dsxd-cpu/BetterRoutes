async function setAdminClaim({ auth, targetUid, enabled }) {
  const user = await auth.getUser(targetUid);
  const claims = { ...(user.customClaims || {}) };
  if (enabled) {
    claims.admin = true;
  } else {
    delete claims.admin;
    delete claims.role;
    delete claims.roles;
  }
  await auth.setCustomUserClaims(targetUid, claims);
  // Claim changes are only present in newly issued tokens; revoke refresh
  // tokens so a removed administrator cannot refresh an old claim.
  await auth.revokeRefreshTokens(targetUid);
  return { targetUid, status: enabled ? 'admin' : 'revoked', tokenRefreshRequired: true };
}

module.exports = { setAdminClaim };
