import { httpsCallable } from 'firebase/functions';
import { collection, doc, getDoc, getDocs, limit, orderBy, query, where } from 'firebase/firestore';
import { db, functions } from './firebase';
import { getDownloadURL, ref, uploadBytes } from 'firebase/storage';
import { storage } from './firebase';
import type { AdminMetrics, BookingOperation, Driver, DriverRatingRecord, FareConfig, PageResult, Report, RouteRestriction, SafetyIncident, Toda, ZoneRequest } from './types';

async function call<T>(name: string, data: Record<string, unknown>): Promise<T> {
  return (await httpsCallable<Record<string, unknown>, T>(functions, name)(data)).data;
}

const mapDocument = <T>(id: string, value: unknown) => ({ id, ...(value as object) }) as T;

export const adminApi = {
  metrics: () => call<AdminMetrics>('adminGetMetrics', {}),
  bootstrap: (code: string) => call<{ role: string }>('bootstrapDeveloperAdmin', { code }),
  registerToda: (data: Record<string, unknown>) => call<{ todaId: string }>('registerToda', data),
  createToda: (data: Record<string, unknown>) => call<{ todaId: string }>('adminCreateToda', data),
  reviewTodaRegistration: (todaId: string, status: 'approved' | 'declined') => call<{ updated: boolean }>('adminReviewTodaRegistration', { todaId, status }),
  assignTodaAdmin: (uid: string, todaId: string) => call<{ assigned: boolean }>('adminAssignTodaAdmin', { uid, todaId }),
  setTodaStatus: (todaId: string, isActive: boolean) => call<{ updated: boolean }>('adminSetTodaStatus', { todaId, isActive }),
  attachTodaDocuments: (todaId: string, documents: Record<string, string>) => call<{ updated: boolean }>('adminAttachTodaDocuments', { todaId, documents }),
  attachTodaRegistrationDocuments: (todaId: string, documents: Record<string, string>) => call<{ updated: boolean }>('attachTodaRegistrationDocuments', { todaId, documents }),
  updateFare: (fare: FareConfig) => call<{ updated: boolean }>('adminUpdateFare', { fare }),
  setDriverStatus: (uid: string, status: string) => call<{ updated: boolean }>('adminSetDriverStatus', { uid, status }),
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
  safetyIncidents: () =>
    call<PageResult<SafetyIncident>>('adminListSafetyIncidents', {
      pageSize: 100,
    }),
  async zones(todaId?: string): Promise<ZoneRequest[]> {
    const source = collection(db, 'zoneRequests');
    const snapshot = await getDocs(todaId ? query(source, where('todaId', '==', todaId), limit(100)) : query(source, limit(100)));
    return snapshot.docs.map((entry) => mapDocument<ZoneRequest>(entry.id, entry.data()));
  },
  async routeRestrictions(): Promise<RouteRestriction[]> {
    const snapshot = await getDocs(query(collection(db, 'routeRestrictions'), limit(200)));
    return snapshot.docs.map((entry) => mapDocument<RouteRestriction>(entry.id, entry.data()));
  },
  async fare(): Promise<FareConfig> {
    const snapshot = await getDoc(doc(db, 'settings', 'fare_config'));
    return (snapshot.exists() ? snapshot.data() : {
      baseFare: 20, includedMeters: 1000, distanceStepMeters: 500,
      distanceStepPrice: 5, additionalPassengerFee: 40, baggageFee: 20,
      outsideTodaSurcharge: 20,
    }) as FareConfig;
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
