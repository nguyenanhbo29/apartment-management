const ROLES = Object.freeze({
  RESIDENT: 'resident',
  STAFF: 'staff',
  MANAGER: 'manager',
  ACCOUNTANT: 'accountant',
});

// Bộ phận của Staff
const DEPARTMENTS = Object.freeze({
  RECEPTION: 'reception',
  SECURITY: 'security',
  TECHNICAL: 'technical',
  FACILITY: 'facility',
});

const USER_STATUS = Object.freeze({ ACTIVE: 'active', INACTIVE: 'inactive' });

const APARTMENT_STATUS = Object.freeze({ VACANT: 'vacant', OCCUPIED: 'occupied' });

const RESIDENT_RELATION =Object.freeze({ OWNER: 'owner', MEMBER: 'member', TENANT: 'tenant' });
const RESIDENT_STATUS = Object.freeze({
  PENDING: 'pending',
  ACTIVE: 'active',
  REJECTED: 'rejected',
  ENDED: 'ended',
});

const VEHICLE_TYPE = Object.freeze({ MOTORBIKE: 'motorbike', CAR: 'car' });
const VEHICLE_STATUS = Object.freeze({
  PENDING: 'pending',
  APPROVED: 'approved',
  REJECTED: 'rejected',
  INACTIVE: 'inactive',
});

module.exports = {
  ROLES,
  DEPARTMENTS,
  USER_STATUS,
  APARTMENT_STATUS,
  RESIDENT_RELATION,
  RESIDENT_STATUS,
  VEHICLE_TYPE,
  VEHICLE_STATUS,
};
