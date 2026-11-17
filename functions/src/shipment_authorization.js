function buildAuthorizedUserUids({
  verifiedCreatorUid,
  verifiedWarehouseOwnerUid,
  verifiedCustomerUid,
  verifiedReceiverUid,
  verifiedTruckOwnerUid,
  verifiedDriverUid,
  additionalVerifiedUids = [],
}) {
  const candidates = [
    verifiedCreatorUid,
    verifiedWarehouseOwnerUid,
    verifiedCustomerUid,
    verifiedReceiverUid,
    verifiedTruckOwnerUid,
    verifiedDriverUid,
    ...(Array.isArray(additionalVerifiedUids) ? additionalVerifiedUids : []),
  ];

  return [
    ...new Set(
      candidates
        .filter((uid) => typeof uid === 'string' && uid.trim().length > 0)
        .map((uid) => uid.trim()),
    ),
  ];
}

module.exports = {
  buildAuthorizedUserUids,
};
