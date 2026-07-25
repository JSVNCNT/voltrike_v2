import { httpsCallable } from 'firebase/functions';
import { collection, doc, getDoc, getDocs, limit, orderBy, query, where } from 'firebase/firestore';
import { db, functions } from './firebase';
import { getDownloadURL, ref, uploadBytes } from 'firebase/storage';
import { storage } from './firebase';
import type { Driver, FareConfig, Report, RouteRestriction, Toda, ZoneRequest } from './types';

async function call<T>(name: string, data: Record<string, unknown>): Promise<T> {
  return (await httpsCallable<Record<string, unknown>, T>(functions, name)(data)).data;
}

const mapDocument = <T>(id: string, value: unknown) => ({ id, ...(value as object) }) as T;

async function profileForAdminReview(uid: string) {
  try {
    const profile = await getDoc(doc(db, 'users', uid));
    return profile.exists() ? profile.data() : undefined;
  } catch {
    // TODA admins are deliberately not allowed to read unrelated passenger
    // profiles. The report remains usable without exposing that identity.
    return undefined;
  }
}

export const adminApi = {
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
  setUserStatus: (uid: string, isActive: boolean) => call<{ updated: boolean }>('adminSetUserStatus', { uid, isActive }),
  resolveReport: (reportId: string, status: string, action: string) => call<{ updated: boolean }>('adminResolveReport', { reportId, status, action }),
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
  async drivers(todaId?: string): Promise<Driver[]> {
    const source = collection(db, 'drivers');
    const snapshot = await getDocs(todaId ? query(source, where('todaId', '==', todaId), limit(200)) : query(source, limit(200)));
    const drivers = snapshot.docs.map((entry) => mapDocument<Driver>(entry.id, entry.data()));
    // Driver operational data and account identity are intentionally stored in
    // separate documents. Join them only for authorized admin review.
    return Promise.all(drivers.map(async (driver) => {
      const profile = await profileForAdminReview(driver.uid);
      return {
        ...driver,
        applicant: profile,
      };
    }));
  },
  async reports(todaId?: string): Promise<Report[]> {
    const source = collection(db, 'reports');
    const snapshot = await getDocs(todaId ? query(source, where('todaId', '==', todaId), limit(200)) : query(source, limit(200)));
    const reports = snapshot.docs.map((entry) => mapDocument<Report>(entry.id, entry.data()));
    return Promise.all(reports.map(async (report) => {
      const [reporter, reportedUser] = await Promise.all([
        profileForAdminReview(report.reporterId),
        profileForAdminReview(report.reportedUserId),
      ]);
      return { ...report, reporter, reportedUser };
    }));
  },
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
