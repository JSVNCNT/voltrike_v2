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
  ratingCount?: number;
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

export interface DriverRatingRecord {
  id: string;
  ratingId?: string;
  bookingId: string;
  driverId: string;
  passengerId: string;
  todaId?: string | null;
  todaName?: string | null;
  driverName?: string | null;
  passengerName?: string | null;
  rating: number;
  comment: string;
  createdAt?: string | null;
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
  isActive?: boolean;
}

export interface Report {
  id: string;
  bookingId: string;
  reporterId: string;
  reportedUserId: string;
  todaId?: string;
  reporterRole?: 'passenger' | 'driver';
  reportedRole?: 'passenger' | 'driver';
  reviewAudience?: ('developer_admin' | 'toda_admin')[];
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

export interface TodaCommission {
  percent: number;
  recommendedPercent: number;
  maximumPercent: number;
  updatedAt?: string | null;
}

export interface TodaCommissionReportSummary {
  grossFare: number;
  commissionAmount: number;
  driverNetEarnings: number;
  completedRides: number;
  pendingSettlements: number;
  settledSettlements: number;
  disputedSettlements: number;
}

export interface TodaCommissionReportItem {
  bookingId: string;
  receiptNumber?: string | null;
  driverId: string;
  driverName: string;
  completedAt: string | null;
  grossFare: number;
  commissionPercent: number;
  commissionAmount: number;
  driverNetEarnings: number;
  settlementStatus: string;
  adjustmentStatus?: string | null;
  disputeReason?: string | null;
}

export interface TodaCommissionReport {
  summary: TodaCommissionReportSummary;
  items: TodaCommissionReportItem[];
  nextCursor: string | null;
}

export interface TodaCommissionReportOptions {
  cursor?: string | null;
  summaryOnly?: boolean;
}

export interface LiveDriver {
  uid: string;
  name: string;
  todaId: string;
  latitude: number;
  longitude: number;
  accuracy: number;
  timestamp: number;
  bookingId?: string | null;
  bookingStatus: string;
  vehicleType?: string | null;
  plateNumber?: string | null;
}

export interface PageResult<T> {
  items: T[];
  nextCursor: string | null;
}

export interface AdminMetrics {
  drivers: number;
  reports: number;
  zones: number;
  trips: number;
  bookings: number;
  safetyIncidents: number;
  scope: string;
}

export interface BookingOperation {
  bookingId: string;
  schemaVersion: number;
  status: string;
  acknowledgement?: 'accidental' | 'needs_review';
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
  schemaVersion?: number;
  bookingId: string;
  category: string;
  reporterRole: string;
  passengerId: string;
  passengerName?: string | null;
  driverId?: string | null;
  driverName?: string | null;
  todaId?: string | null;
  todaName?: string | null;
  bookingStatus: string;
  pickupAddress?: string | null;
  destinationAddress?: string | null;
  driverLocation?: {
    latitude: number;
    longitude: number;
    accuracy?: number;
    bearing?: number;
    speed?: number;
    timestamp?: number;
    online?: boolean;
  } | null;
  status: string;
  responseStatus?: 'reported' | 'acknowledged' | 'responding' | 'resolved';
  deliveryStatus?: 'pending' | 'delivered' | 'delivery_failed' | 'no_registered_admin_device' | 'not_required' | null;
  deliveryRecipientCount?: number;
  deliveryAttemptCount?: number;
  deliverySuccessCount?: number;
  escalationLevel?: number;
  bookingCancelledForSafety?: boolean;
  bookingSafetyAction?: string | null;
  locationSource?: 'live_driver_location' | 'sos_snapshot';
  emergencyDispatch: string;
  requiresManualEmergencyContact: boolean;
  createdAt?: string | null;
  updatedAt?: string | null;
  deliveredAt?: string | null;
  acknowledgedAt?: string | null;
  respondingAt?: string | null;
  resolvedAt?: string | null;
  escalatedAt?: string | null;
  lastResponseNote?: string | null;
  resolutionNote?: string | null;
}

export interface ZoneRequest {
  id: string;
  todaId: string;
  polygon: Point[];
  areas?: Point[][];
  geometryVersion?: number;
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
  geometryVersion?: number;
  bufferMeters?: number;
  minimumAlignedTravelMeters?: number;
  notes?: string;
  isActive: boolean;
}

export type DriverViolationStatus =
  | 'open'
  | 'acknowledged'
  | 'responding'
  | 'resolved'
  | 'dismissed';

export type DriverViolationEventClass =
  | 'restricted_area_approach'
  | 'restricted_area_entry'
  | 'restricted_area_route'
  | 'highway_advisory'
  | 'highway_travel'
  | string;

export interface ViolationLocation {
  latitude: number;
  longitude: number;
  accuracy?: number | null;
  bearing?: number | null;
  speed?: number | null;
  timestamp?: number | null;
  observedAt?: number | null;
}

export interface ViolationRestrictionSnapshot {
  id?: string | null;
  name: string;
  type?: RouteRestriction['type'] | string | null;
  revision?: number | null;
  geometryVersion?: number | null;
  polygon?: Point[];
  areas?: Point[][];
}

export interface ViolationDelivery {
  status?: string | null;
  recipientCount?: number;
  attemptedCount?: number;
  successCount?: number;
  lastAttemptAt?: string | null;
}

export interface DriverViolation {
  id: string;
  schemaVersion?: number;
  eventClass: DriverViolationEventClass;
  status: DriverViolationStatus;
  severity?: 'advisory' | 'warning' | 'critical' | string;
  driverId: string;
  driverName?: string | null;
  ownerTodaId?: string | null;
  ownerTodaName?: string | null;
  bookingId?: string | null;
  bookingStatus?: string | null;
  context?: 'idle' | 'to_pickup' | 'on_trip' | 'unknown' | string;
  restriction?: ViolationRestrictionSnapshot | null;
  eventLocation: ViolationLocation;
  evidence?: Record<string, unknown> | null;
  source?: string | null;
  confidence?: string | number | null;
  routeAdvisory?: string | null;
  enteredAt?: string | null;
  exitedAt?: string | null;
  occurredAt?: string | null;
  createdAt?: string | null;
  updatedAt?: string | null;
  acknowledgedAt?: string | null;
  resolvedAt?: string | null;
  delivery?: ViolationDelivery | null;
  driverDelivery?: ViolationDelivery | null;
  resolutionNote?: string | null;
  latestAdminNote?: string | null;
  unreadMessageCount?: number;
  messageCount?: number;
  lastMessage?: string | null;
  lastMessageAt?: string | null;
}

export interface ViolationMessage {
  id: string;
  violationId: string;
  senderId: string;
  senderName: string;
  senderRole: 'driver' | 'toda_admin' | 'developer_admin' | string;
  text: string;
  createdAt?: string | null;
  readBy?: string[];
}

export interface ViolationFilters {
  status?: DriverViolationStatus | '';
  eventClass?: string;
  search?: string;
}
