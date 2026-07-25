import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getFunctions } from 'firebase/functions';
import { getStorage } from 'firebase/storage';

// Firebase web configuration is an application identifier, not a server secret.
const app = initializeApp({
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
