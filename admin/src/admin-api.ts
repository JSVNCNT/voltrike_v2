import { httpsCallable } from 'firebase/functions';
import { collection, doc, getDoc, getDocs, limit, orderBy, query, where } from 'firebase/firestore';
import { db, functions } from './firebase';
import { getDownloadURL, ref, uploadBytes } from 'firebase/storage';
import { storage } from './firebase';
import type { Driver, FareConfig, Report, Toda, ZoneRequest } from './types';

async function call<T>(name: string, data: Record<string, unknown>): Promise<T> {
  return (await httpsCallable<Record<string, unknown>, T>(functions, name)(data)).data;
}

const mapDocument = <T>(id: string, value: unknown) => ({ id, ...(value as object) }) as T;

export const adminApi = {
  bootstrap: (code: string) => call<{ role: string }>('bootstrapDeveloperAdmin', { code }),
  registerToda: (data: Record<string, unknown>) => call<{ todaId: string }>('registerToda', data),
  createToda: (data: Record<string, unknown>) => call<{ todaId: string }>('adminCreateToda', data),
  reviewTodaRegistration: (todaId: string, status: 'approved' | 'declined') => call<{ updated: boolean }>('adminReviewTodaRegistration', { todaId, status }),
  assignTodaAdmin: (uid: string, todaId: string) => call<{ assigned: boolean }>('adminAssignTodaAdmin', { uid, todaId }),
  setTodaStatus: (todaId: string, isActive: boolean) => call<{ updated: boolean }>('adminSetTodaStatus', { todaId, isActive }),
  attachTodaDocuments: (todaId: string, documents: Record<string, string>) => call<{ updated: boolean }>('adminAttachTodaDocuments', { todaId, documents }),
  updateFare: (fare: FareConfig) => call<{ updated: boolean }>('adminUpdateFare', { fare }),
  setDriverStatus: (uid: string, status: string) => call<{ updated: boolean }>('adminSetDriverStatus', { uid, status }),
  setUserStatus: (uid: string, isActive: boolean) => call<{ updated: boolean }>('adminSetUserStatus', { uid, isActive }),
  resolveReport: (reportId: string, status: string, action: string) => call<{ updated: boolean }>('adminResolveReport', { reportId, status, action }),
  submitZone: (todaId: string, polygon: [number, number][], notes: string) => call<{ zoneRequestId: string }>('adminSubmitZoneRequest', { todaId, polygon, notes }),
  reviewZone: (zoneRequestId: string, status: string) => call<{ updated: boolean }>('adminReviewZoneRequest', { zoneRequestId, status }),
  updateZone: (zoneRequestId: string, polygon: [number, number][], notes: string) => call<{ updated: boolean }>('adminUpdateZoneRequest', { zoneRequestId, polygon, notes }),
  async todas(): Promise<Toda[]> {
    const snapshot = await getDocs(query(collection(db, 'todas'), orderBy('name')));
    return snapshot.docs.map((entry) => mapDocument<Toda>(entry.id, entry.data()));
  },
  async drivers(todaId?: string): Promise<Driver[]> {
    const source = collection(db, 'drivers');
    const snapshot = await getDocs(todaId ? query(source, where('todaId', '==', todaId), limit(200)) : query(source, limit(200)));
    return snapshot.docs.map((entry) => mapDocument<Driver>(entry.id, entry.data()));
  },
  async reports(todaId?: string): Promise<Report[]> {
    const source = collection(db, 'reports');
    const snapshot = await getDocs(todaId ? query(source, where('todaId', '==', todaId), limit(200)) : query(source, limit(200)));
    return snapshot.docs.map((entry) => mapDocument<Report>(entry.id, entry.data()));
  },
  async zones(todaId?: string): Promise<ZoneRequest[]> {
    const source = collection(db, 'zoneRequests');
    const snapshot = await getDocs(todaId ? query(source, where('todaId', '==', todaId), limit(100)) : query(source, limit(100)));
    return snapshot.docs.map((entry) => mapDocument<ZoneRequest>(entry.id, entry.data()));
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
};
