import { httpsCallable } from 'firebase/functions';
import { collection, doc, getDoc, getDocs, limit, orderBy, query, where } from 'firebase/firestore';
import { db, functions } from './firebase';
import { getDownloadURL, ref, uploadBytes } from 'firebase/storage';
import { storage } from './firebase';
import type { AdminMetrics, BookingOperation, Driver, DriverRatingRecord, FareConfig, LiveDriver, PageResult, Point, Report, RouteRestriction, SafetyIncident, Toda, TodaCommission, ZoneRequest } from './types';

async function call<T>(name: string, data: Record<string, unknown>): Promise<T> {
  try {
    return (await httpsCallable<Record<string, unknown>, T>(functions, name)(data)).data;
  } catch (error) {
    throw new Error(callableErrorMessage(name, error));
  }
}

const mapDocument = <T>(id: string, value: unknown) => ({ id, ...(value as object) }) as T;

type UnknownRecord = Record<string, unknown>;

function asRecord(value: unknown): UnknownRecord {
  return value !== null && typeof value === 'object' ? value as UnknownRecord : {};
}

function finiteNumber(value: unknown): number | null {
  if (typeof value !== 'number' && (typeof value !== 'string' || !value.trim())) {
    return null;
  }
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function decodePoint(value: unknown): Point | null {
  if (Array.isArray(value)) {
    const longitude = finiteNumber(value[0]);
    const latitude = finiteNumber(value[1]);
    if (longitude === null || latitude === null) return null;
    if (Math.abs(longitude) > 180 || Math.abs(latitude) > 90) return null;
    return [longitude, latitude];
  }

  const source = asRecord(value);
  const longitude = finiteNumber(source.longitude ?? source.lng);
  const latitude = finiteNumber(source.latitude ?? source.lat);
  if (longitude === null || latitude === null) return null;
  if (Math.abs(longitude) > 180 || Math.abs(latitude) > 90) return null;
  return [longitude, latitude];
}

function decodeArea(value: unknown): Point[] {
  const source = asRecord(value);
  const rawPoints = Array.isArray(value)
    ? value
    : source.points ?? source.coordinates ?? source.vertices ?? source.polygon;
  if (!Array.isArray(rawPoints)) return [];
  return rawPoints.map(decodePoint).filter((point): point is Point => point !== null);
}

function decodeAreas(value: unknown): Point[][] {
  const source = asRecord(value);
  const rawAreas = Array.isArray(value) ? value : source.areas;
  if (!Array.isArray(rawAreas)) return [];
  return rawAreas.map(decodeArea).filter((area) => area.length > 0);
}

function normalizeZoneRequest(id: string, value: unknown): ZoneRequest {
  const source = asRecord(value);
  const decodedPolygon = decodeArea(source.polygon);
  const decodedAreas = decodeAreas(source.areas);
  const areas = decodedAreas.length > 0
    ? decodedAreas
    : decodedPolygon.length > 0 ? [decodedPolygon] : [];
  const polygon = decodedPolygon.length > 0 ? decodedPolygon : areas[0] ?? [];
  const status = source.status === 'approved' || source.status === 'declined'
    ? source.status
    : 'pending';

  return {
    ...source,
    id,
    todaId: typeof source.todaId === 'string' ? source.todaId : '',
    polygon,
    areas,
    status,
    notes: typeof source.notes === 'string' ? source.notes : '',
    geometryVersion: finiteNumber(source.geometryVersion) ?? undefined,
  };
}

function normalizeRouteRestriction(id: string, value: unknown): RouteRestriction {
  const source = asRecord(value);
  const type: RouteRestriction['type'] =
    source.type === 'no_service_area' || source.type === 'restricted_crossing'
      ? source.type
      : 'prohibited_highway';
  const geometryType: NonNullable<RouteRestriction['geometryType']> =
    source.geometryType === 'polygon' || source.geometryType === 'corridor'
      ? source.geometryType
      : type === 'prohibited_highway' ? 'corridor' : 'polygon';
  const decodedCoordinates = decodeArea(source.coordinates);
  const decodedPolygon = decodeArea(source.polygon);
  const decodedAreas = decodeAreas(source.areas);
  const polygon = decodedCoordinates.length > 0
    ? decodedCoordinates
    : decodedPolygon.length > 0 ? decodedPolygon : decodedAreas[0] ?? [];
  const areas = decodedAreas.length > 0
    ? decodedAreas
    : geometryType === 'polygon' && polygon.length > 0 ? [polygon] : [];

  return {
    ...source,
    id,
    name: typeof source.name === 'string' ? source.name : 'Unnamed restriction',
    type,
    geometryType,
    polygon,
    areas,
    bufferMeters: finiteNumber(source.bufferMeters) ?? 0,
    notes: typeof source.notes === 'string' ? source.notes : '',
    isActive: source.isActive !== false,
    geometryVersion: finiteNumber(source.geometryVersion) ?? undefined,
  };
}

function callableErrorMessage(name: string, error: unknown): string {
  const source = asRecord(error);
  const code = typeof source.code === 'string' ? source.code : '';
  const rawMessage = error instanceof Error
    ? error.message
    : typeof source.message === 'string' ? source.message : '';
  const usefulMessage = rawMessage.trim()
    && !/^(internal|internal error|unknown|an unknown error occurred)[.:]?$/i.test(rawMessage.trim())
    && !/functions\/internal/i.test(rawMessage);

  if (code.includes('unauthenticated')) {
    return 'Your administrator session expired. Sign in again and retry.';
  }
  if (code.includes('permission-denied')) {
    return 'Your current administrator account cannot perform this action. Sign in again if its permissions recently changed.';
  }
  if (usefulMessage) return rawMessage;
  if (name === 'adminSubmitZoneRequest' || name === 'adminUpdateZoneRequest') {
    return 'The server could not save the coverage geometry. Refresh and try again; if it repeats, verify that the deployed admin Functions support geometry version 2.';
  }
  if (name === 'adminReviewZoneRequest') {
    return 'The server could not review this coverage request. Refresh the request list and try again.';
  }
  if (name === 'adminCreateRouteRestriction') {
    return 'The server could not save the route restriction. Refresh and try again; if it repeats, verify that the deployed admin Functions support geometry version 2.';
  }
  if (name === 'adminSetRouteRestrictionStatus') {
    return 'The server could not change this route restriction status. Refresh the restriction list and try again.';
  }
  return 'The server could not complete this administrator action. Refresh and try again.';
}

export const adminApi = {
  metrics: () => call<AdminMetrics>('adminGetMetrics', {}),
  bootstrap: (code: string) => call<{ role: string }>('bootstrapDeveloperAdmin', { code }),
  requestBrandedVerificationEmail: () =>
    call<{ sent: boolean; alreadyVerified: boolean }>(
      'requestBrandedVerificationEmail',
      {},
    ),
  registerToda: (data: Record<string, unknown>) => call<{ todaId: string }>('registerToda', data),
  createToda: (data: Record<string, unknown>) => call<{ todaId: string }>('adminCreateToda', data),
  reviewTodaRegistration: (todaId: string, status: 'approved' | 'declined') => call<{ updated: boolean }>('adminReviewTodaRegistration', { todaId, status }),
  assignTodaAdmin: (uid: string, todaId: string) => call<{ assigned: boolean }>('adminAssignTodaAdmin', { uid, todaId }),
  setTodaStatus: (todaId: string, isActive: boolean) => call<{ updated: boolean }>('adminSetTodaStatus', { todaId, isActive }),
  attachTodaDocuments: (todaId: string, documents: Record<string, string>) => call<{ updated: boolean }>('adminAttachTodaDocuments', { todaId, documents }),
  attachTodaRegistrationDocuments: (todaId: string, documents: Record<string, string>) => call<{ updated: boolean }>('attachTodaRegistrationDocuments', { todaId, documents }),
  updateFare: (fare: FareConfig) => call<{ updated: boolean }>('adminUpdateFare', { fare }),
  setDriverStatus: (uid: string, status: string, license?: { number: string; expiry: string }) =>
    call<{ updated: boolean }>('adminSetDriverStatus', {
      uid,
      status,
      licenseNumber: license?.number || '',
      licenseExpiry: license?.expiry || '',
    }),
  setVehicleVerification: (driverId: string, isVerified: boolean) => call<{ updated: boolean }>('adminSetVehicleVerification', { driverId, isVerified }),
  setUserStatus: (uid: string, isActive: boolean, sourceReportId = '') => call<{ updated: boolean }>('adminSetUserStatus', { uid, isActive, sourceReportId }),
  resolveReport: (reportId: string, status: string, action: string) => call<{ updated: boolean }>('adminResolveReport', { reportId, status, action }),
  resolveSettlementDispute: (bookingId: string, resolution: string) => call<{ updated: boolean }>('adminResolveSettlementDispute', { bookingId, resolution }),
  submitZone: (todaId: string, polygon: [number, number][], notes: string, areas?: [number, number][][]) => call<{ zoneRequestId: string }>('adminSubmitZoneRequest', { todaId, polygon, notes, areas }),
  reviewZone: (zoneRequestId: string, status: string) => call<{ updated: boolean }>('adminReviewZoneRequest', { zoneRequestId, status }),
  updateZone: (zoneRequestId: string, polygon: [number, number][], notes: string, areas?: [number, number][][]) => call<{ updated: boolean }>('adminUpdateZoneRequest', { zoneRequestId, polygon, notes, areas }),
  createRouteRestriction: (name: string, type: RouteRestriction['type'], geometryType: 'polygon' | 'corridor', polygon: [number, number][], bufferMeters: number, notes: string, areas?: [number, number][][]) => call<{ restrictionId: string }>('adminCreateRouteRestriction', { name, type, geometryType, polygon, bufferMeters, notes, areas }),
  setRouteRestrictionStatus: (restrictionId: string, isActive: boolean) => call<{ updated: boolean }>('adminSetRouteRestrictionStatus', { restrictionId, isActive }),
  async todas(): Promise<Toda[]> {
    const snapshot = await getDocs(query(collection(db, 'todas'), orderBy('name')));
    const todas = snapshot.docs.map((entry) => mapDocument<Toda>(entry.id, entry.data()));
    return Promise.all(todas.map(async (toda) => {
      try {
        const application = await getDoc(doc(db, 'todaApplications', toda.id));
        return application.exists() ? { ...toda, ...application.data() } as Toda : toda;
      } catch {
        // TODA administrators can load the public TODA list but cannot read
        // legal applications belonging to any TODA.
        return toda;
      }
    }));
  },
  driverPage: (cursor?: string | null, search = '') =>
    call<PageResult<Driver>>('adminListDrivers', {
      cursor: cursor || '',
      search,
      pageSize: 25,
    }),
  async drivers(_todaId?: string): Promise<Driver[]> {
    return (await adminApi.driverPage()).items;
  },
  ratingPage: (cursor?: string | null) =>
    call<PageResult<DriverRatingRecord>>('adminListRatings', {
      cursor: cursor || '',
      pageSize: 50,
    }),
  async ratings(): Promise<DriverRatingRecord[]> {
    return (await adminApi.ratingPage()).items;
  },
  reportPage: (cursor?: string | null, search = '') =>
    call<PageResult<Report>>('adminListReports', {
      cursor: cursor || '',
      search,
      pageSize: 25,
    }),
  async reports(_todaId?: string): Promise<Report[]> {
    return (await adminApi.reportPage()).items;
  },
  bookingPage: (cursor?: string | null, search = '') =>
    call<PageResult<BookingOperation>>('adminListBookings', {
      cursor: cursor || '',
      search,
      pageSize: 25,
    }),
  safetyIncidentPage: (cursor?: string | null) =>
    call<PageResult<SafetyIncident>>('adminListSafetyIncidents', {
      cursor: cursor || '',
      pageSize: 50,
    }),
  liveDrivers: () => call<{ items: LiveDriver[] }>('adminListLiveDrivers', {}).then((result) => result.items),
  todaCommission: () => call<TodaCommission>('adminGetTodaCommission', {}),
  setTodaCommission: (percent: number) =>
    call<TodaCommission>('adminSetTodaCommission', { percent }),
  cancelBookingForSafety: (incidentId: string) =>
    call<{ cancelled: boolean }>('adminCancelBookingForSafety', { incidentId }),
  updateSafetyIncidentResponse: (
    incidentId: string,
    action: 'acknowledge' | 'responding' | 'resolve',
    note = '',
  ) => call<{ responseStatus: SafetyIncident['responseStatus'] }>(
    'adminUpdateSafetyIncidentResponse',
    { incidentId, action, note },
  ),
  async zones(todaId?: string): Promise<ZoneRequest[]> {
    const source = collection(db, 'zoneRequests');
    const snapshot = await getDocs(
      todaId
        ? query(source, where('todaId', '==', todaId), limit(500))
        : query(source, limit(500)),
    );
    return snapshot.docs
      .map((entry) => normalizeZoneRequest(entry.id, entry.data()))
      .sort((left, right) => {
        if (left.status === 'pending' && right.status !== 'pending') return -1;
        if (right.status === 'pending' && left.status !== 'pending') return 1;
        return left.todaId.localeCompare(right.todaId);
      });
  },
  async routeRestrictions(): Promise<RouteRestriction[]> {
    const snapshot = await getDocs(query(collection(db, 'routeRestrictions'), limit(200)));
    return snapshot.docs
      .map((entry) => normalizeRouteRestriction(entry.id, entry.data()))
      .sort((left, right) => Number(right.isActive) - Number(left.isActive) || left.name.localeCompare(right.name));
  },
  async fare(): Promise<FareConfig> {
    const snapshot = await getDoc(doc(db, 'settings', 'fare_config'));
    const source = snapshot.exists() ? snapshot.data() : {
      baseFare: 20, includedMeters: 1000, distanceStepMeters: 500,
      distanceStepPrice: 5, additionalPassengerFee: 40, baggageFee: 20,
      outsideTodaSurcharge: 20,
    };
    return {
      baseFare: Number(source.baseFare ?? 20),
      includedMeters: Number(source.includedMeters ?? 1000),
      distanceStepMeters: Number(source.distanceStepMeters ?? 500),
      distanceStepPrice: Number(source.distanceStepPrice ?? 5),
      additionalPassengerFee: Number(source.additionalPassengerFee ?? 40),
      baggageFee: Number(source.baggageFee ?? 20),
      outsideTodaSurcharge: Number(source.outsideTodaSurcharge ?? 20),
    };
  },
  async uploadTodaDocuments(todaId: string, files: Record<string, File>): Promise<void> {
    const documents = await Promise.all(Object.entries(files).map(async ([key, file]) => {
      const extension = file.name.includes('.') ? file.name.split('.').pop() : 'bin';
      const object = ref(storage, `toda_documents/${todaId}/${key}.${extension}`);
      await uploadBytes(object, file, { contentType: file.type });
      return [key, await getDownloadURL(object)] as const;
    }));
    await call<{ updated: boolean }>('adminAttachTodaDocuments', {
      todaId,
      documents: Object.fromEntries(documents),
    });
  },
  async uploadTodaRegistrationDocuments(todaId: string, files: Record<string, File>): Promise<void> {
    const documents = await Promise.all(Object.entries(files).map(async ([key, file]) => {
      const extension = file.name.includes('.') ? file.name.split('.').pop() : 'bin';
      const object = ref(storage, `toda_documents/${todaId}/${key}.${extension}`);
      await uploadBytes(object, file, { contentType: file.type });
      return [key, await getDownloadURL(object)] as const;
    }));
    await adminApi.attachTodaRegistrationDocuments(todaId, Object.fromEntries(documents));
  },
};
