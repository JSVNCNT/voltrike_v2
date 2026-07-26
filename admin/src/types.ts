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
  barangayName?: string;
  cityCode?: string;
  cityName?: string;
  regionCode?: string;
  regionName?: string;
  isActive: boolean;
  status?: 'pending' | 'approved' | 'declined';
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
  licenseExpiry?: string;
  profilePhotoUrl?: string;
  driverLicenseFrontUrl?: string;
  driverLicenseBackUrl?: string;
  governmentIdUrl?: string;
  orDocumentUrl?: string;
  crDocumentUrl?: string;
  vehiclePhotoUrl?: string;
  applicant?: DriverApplicant;
  vehicleId?: string;
  vehicle?: {
    id: string;
    isVerified?: boolean;
    vehicleNumber?: string;
    plateNumber?: string;
    model?: string;
  } | null;
}

export interface DriverApplicant {
  firstName?: string;
  middleName?: string;
  lastName?: string;
  email?: string;
  phoneNumber?: string;
  dateOfBirth?: string;
  profileImage?: string;
}

export interface AdminPerson {
  firstName?: string;
  middleName?: string;
  lastName?: string;
  email?: string;
  phoneNumber?: string;
  role?: string;
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
  reporter?: AdminPerson;
  reportedUser?: AdminPerson;
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

export interface PageResult<T> {
  items: T[];
  nextCursor: string | null;
}

export interface BookingOperation {
  bookingId: string;
  schemaVersion: number;
  status: string;
  passengerName: string;
  driverName?: string | null;
  driverId?: string | null;
  plateNumber?: string | null;
  todaId?: string | null;
  todaName?: string | null;
  pickupAddress: string;
  destinationAddress: string;
  amountDue: number;
  paymentMethod: string;
  settlementStatus: string;
  adjustmentStatus: string;
  disputeReason?: string | null;
  receiptNumber?: string | null;
  cancellationCode?: string | null;
  createdAt?: string | null;
  updatedAt?: string | null;
}

export interface SafetyIncident {
  id: string;
  bookingId: string;
  category: string;
  reporterRole: string;
  passengerId: string;
  driverId?: string | null;
  todaId?: string | null;
  bookingStatus: string;
  status: string;
  emergencyDispatch: string;
  requiresManualEmergencyContact: boolean;
  createdAt?: string | null;
}

export interface ZoneRequest {
  id: string;
  todaId: string;
  polygon: Point[];
  areas?: Point[][];
  status: 'pending' | 'approved' | 'declined';
  notes?: string;
}

export interface RouteRestriction {
  id: string;
  name: string;
  type: 'prohibited_highway' | 'no_service_area' | 'restricted_crossing';
  geometryType?: 'polygon' | 'corridor';
  polygon: Point[];
  areas?: Point[][];
  bufferMeters?: number;
  notes?: string;
  isActive: boolean;
}
