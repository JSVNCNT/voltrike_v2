export type AdminRole = 'developer_admin' | 'toda_admin';
export type Point = [number, number];

export interface AdminSession {
  uid: string;
  email: string | null;
  role: AdminRole;
  todaId: string | null;
  displayName: string;
}

export interface Toda {
  id: string;
  name: string;
  barangayCode: string;
  isActive: boolean;
  adminUid?: string | null;
  registration?: TodaRegistration;
  documents?: Record<string, string>;
}

export interface TodaRegistration {
  secCertificateNumber: string;
  spResolutionNumber: string;
  mayorsPermitNumber: string;
  barangayClearanceNumber: string;
  presidentName: string;
  presidentLicenseNumber: string;
  presidentTin: string;
}

export interface Driver {
  uid: string;
  todaId: string;
  driverStatus: 'pending' | 'approved' | 'rejected' | 'suspended';
  isOnline: boolean;
  rating: number;
  completedTrips: number;
  totalEarnings: number;
  licenseNumber?: string;
}

export interface Report {
  id: string;
  bookingId: string;
  reporterId: string;
  reportedUserId: string;
  todaId?: string;
  category: string;
  details: string;
  status: 'open' | 'resolved' | 'dismissed';
  action?: string;
}

export interface FareConfig {
  baseFare: number;
  includedMeters: number;
  distanceStepMeters: number;
  distanceStepPrice: number;
  additionalPassengerFee: number;
  baggageFee: number;
  outsideTodaSurcharge: number;
}

export interface ZoneRequest {
  id: string;
  todaId: string;
  polygon: Point[];
  status: 'pending' | 'approved' | 'declined';
  notes?: string;
}
