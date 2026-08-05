import { initializeApp } from 'firebase/app';
import { getToken, initializeAppCheck, ReCaptchaV3Provider } from 'firebase/app-check';
import { connectAuthEmulator, getAuth } from 'firebase/auth';
import { connectFirestoreEmulator, getFirestore } from 'firebase/firestore';
import { connectFunctionsEmulator, getFunctions } from 'firebase/functions';
import { connectStorageEmulator, getStorage } from 'firebase/storage';

// Firebase web configuration is an application identifier, not a server secret.
export const isFirebaseEmulator =
  import.meta.env.VITE_USE_FIREBASE_EMULATORS === 'true';
const projectId = isFirebaseEmulator ? 'demo-voltrike' : 'voltrike-v2';
export const app = initializeApp(isFirebaseEmulator ? {
  apiKey: 'demo-voltrike-api-key',
  authDomain: `${projectId}.firebaseapp.com`,
  projectId,
  storageBucket: `${projectId}.appspot.com`,
  messagingSenderId: '000000000000',
  appId: '1:000000000000:web:demo-voltrike',
} : {
  apiKey: 'AIzaSyCruee8iglatJcElwDJl9aBuPD19XaPwDw',
  authDomain: 'voltrike-v2.firebaseapp.com',
  projectId: 'voltrike-v2',
  storageBucket: 'voltrike-v2.firebasestorage.app',
  messagingSenderId: '327670792817',
  appId: '1:327670792817:web:d694dafb0cfcce03c5d1d0',
});

export const auth = getAuth(app);
export const db = getFirestore(app);
export const functions = getFunctions(app, 'asia-southeast1');
export const storage = getStorage(app);

const appCheckSiteKey = String(
  import.meta.env.VITE_FIREBASE_APP_CHECK_SITE_KEY || '',
).trim();
const appCheck = appCheckSiteKey
  ? initializeAppCheck(app, {
    provider: new ReCaptchaV3Provider(appCheckSiteKey),
    isTokenAutoRefreshEnabled: true,
  })
  : null;

export async function firebaseAppCheckToken(): Promise<string | null> {
  if (!appCheck) return null;
  const result = await getToken(appCheck, false);
  return result.token || null;
}

if (isFirebaseEmulator) {
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', {
    disableWarnings: true,
  });
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  connectStorageEmulator(storage, '127.0.0.1', 9199);
}
