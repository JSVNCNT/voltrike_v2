import { initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth } from 'firebase/auth';
import { connectFirestoreEmulator, getFirestore } from 'firebase/firestore';
import { connectStorageEmulator, getStorage } from 'firebase/storage';

// Firebase web configuration is an application identifier, not a server secret.
export const isFirebaseEmulator =
  import.meta.env.VITE_USE_FIREBASE_EMULATORS === 'true';
const projectId = isFirebaseEmulator
  ? 'demo-voltrike'
  : String(import.meta.env.VITE_FIREBASE_PROJECT_ID || 'voltrike-v2');
export const app = initializeApp(isFirebaseEmulator ? {
  apiKey: 'demo-voltrike-api-key',
  authDomain: `${projectId}.firebaseapp.com`,
  projectId,
  storageBucket: `${projectId}.appspot.com`,
  messagingSenderId: '000000000000',
  appId: '1:000000000000:web:demo-voltrike',
} : {
  apiKey: String(import.meta.env.VITE_FIREBASE_API_KEY || 'AIzaSyCruee8iglatJcElwDJl9aBuPD19XaPwDw'),
  authDomain: String(import.meta.env.VITE_FIREBASE_AUTH_DOMAIN || `${projectId}.firebaseapp.com`),
  projectId,
  storageBucket: String(import.meta.env.VITE_FIREBASE_STORAGE_BUCKET || 'voltrike-v2.firebasestorage.app'),
  messagingSenderId: String(import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID || '327670792817'),
  appId: String(import.meta.env.VITE_FIREBASE_APP_ID || '1:327670792817:web:d694dafb0cfcce03c5d1d0'),
});

export const auth = getAuth(app);
export const db = getFirestore(app);
export const storage = getStorage(app);

export async function firebaseAppCheckToken(): Promise<string | null> {
  // App Check is disabled for this private deployment and Quick Share builds.
  return null;
}

if (isFirebaseEmulator) {
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', {
    disableWarnings: true,
  });
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  connectStorageEmulator(storage, '127.0.0.1', 9199);
}
