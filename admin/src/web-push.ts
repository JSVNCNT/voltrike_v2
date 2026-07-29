import { httpsCallable } from 'firebase/functions';
import {
  deleteToken,
  getMessaging,
  getToken,
  isSupported,
  onMessage,
  type MessagePayload,
} from 'firebase/messaging';
import { app, functions } from './firebase';

const storedDeviceKey = 'voltrike_admin_web_push_device';

interface StoredWebDevice {
  uid: string;
  documentId: string;
  token: string;
}

interface RegisterWebPushResult {
  registered?: boolean;
  deviceId?: string;
}

interface UnregisterWebPushResult {
  unregistered?: boolean;
  deviceId?: string;
}

export interface WebPushResult {
  enabled: boolean;
  mode: 'fcm' | 'local_only' | 'unavailable';
  message: string;
}

export interface AdminPushAlert {
  title: string;
  body: string;
  violationId: string | null;
  messageId: string | null;
  type: string | null;
}

function vapidKey(): string {
  return (import.meta.env.VITE_FIREBASE_VAPID_KEY || '').trim();
}

function configuredVapidKey(): string | null {
  const value = vapidKey();
  if (!value || value === 'INSERT_FIREBASE_WEB_PUSH_VAPID_KEY_HERE') {
    return null;
  }
  return value;
}

function readStoredDevice(): StoredWebDevice | null {
  try {
    const raw = window.localStorage.getItem(storedDeviceKey);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<StoredWebDevice>;
    return typeof parsed.uid === 'string' &&
      typeof parsed.documentId === 'string' &&
      typeof parsed.token === 'string'
      ? parsed as StoredWebDevice
      : null;
  } catch {
    return null;
  }
}

async function tokenDocumentId(token: string): Promise<string> {
  const bytes = new TextEncoder().encode(token);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');
}

async function firebaseMessagingSupported(): Promise<boolean> {
  return typeof window !== 'undefined' &&
    'Notification' in window &&
    'serviceWorker' in navigator &&
    await isSupported();
}

export function webPushSetupMessage(): string {
  if (!configuredVapidKey()) {
    return 'Violation-case web push is not configured. Set VITE_FIREBASE_VAPID_KEY to the Firebase Web Push certificate public key, rebuild Admin, and deploy firebase-messaging-sw.js over HTTPS. Five-second in-app violation monitoring remains available while this page is open.';
  }
  if (typeof Notification === 'undefined') {
    return 'This browser does not support violation-case web notifications. Five-second in-app violation monitoring remains available while this page is open.';
  }
  if (Notification.permission === 'granted') {
    return 'Violation-case notification permission is granted. VolTrike will keep this browser token registered while this administrator is signed in.';
  }
  if (Notification.permission === 'denied') {
    return 'Violation-case browser notifications are blocked in browser settings. Five-second in-app violation monitoring remains available while this page is open.';
  }
  return 'Violation-case web push is available but not enabled. Permission is requested only when an administrator selects Enable violation-case web push.';
}

export async function enableAdminWebPush(
  uid: string,
  requestPermission = true,
): Promise<WebPushResult> {
  const key = configuredVapidKey();
  if (!key) {
    if (requestPermission && typeof Notification !== 'undefined' &&
        Notification.permission === 'default') {
      await Notification.requestPermission();
    }
    return {
      enabled: false,
      mode: 'local_only',
      message: webPushSetupMessage(),
    };
  }
  if (!await firebaseMessagingSupported()) {
    return {
      enabled: false,
      mode: 'unavailable',
      message: webPushSetupMessage(),
    };
  }
  if (requestPermission && Notification.permission === 'default') {
    await Notification.requestPermission();
  }
  if (Notification.permission !== 'granted') {
    return {
      enabled: false,
      mode: 'local_only',
      message: webPushSetupMessage(),
    };
  }

  const registration = await navigator.serviceWorker.register(
    '/firebase-messaging-sw.js',
    { scope: '/' },
  );
  await navigator.serviceWorker.ready;
  const messaging = getMessaging(app);
  const token = await getToken(messaging, {
    vapidKey: key,
    serviceWorkerRegistration: registration,
  });
  if (!token) {
    return {
      enabled: false,
      mode: 'unavailable',
      message: 'Firebase did not issue a violation-case web push token. Confirm the Web Push certificate, HTTPS deployment, and notification permission.',
    };
  }

  const fallbackDocumentId = await tokenDocumentId(token);
  const previous = readStoredDevice();
  const registrationResult = await httpsCallable<
    {
      token: string;
      previousUid?: string;
      previousDeviceId?: string;
    },
    RegisterWebPushResult
  >(functions, 'registerAdminWebPushToken')({
    token,
    ...(previous?.uid ? { previousUid: previous.uid } : {}),
    ...(previous?.documentId
      ? { previousDeviceId: previous.documentId }
      : {}),
  });
  if (registrationResult.data.registered !== true) {
    throw new Error(
      'The server did not confirm violation-case web push registration.',
    );
  }
  const documentId = typeof registrationResult.data.deviceId === 'string' &&
      registrationResult.data.deviceId
    ? registrationResult.data.deviceId
    : fallbackDocumentId;
  window.localStorage.setItem(storedDeviceKey, JSON.stringify({
    uid,
    documentId,
    token,
  } satisfies StoredWebDevice));
  return {
    enabled: true,
    mode: 'fcm',
    message: 'Firebase web push is enabled for violation-case alerts on this browser.',
  };
}

export async function syncAdminWebPush(uid: string): Promise<WebPushResult> {
  if (typeof Notification === 'undefined' ||
      Notification.permission !== 'granted') {
    return {
      enabled: false,
      mode: 'local_only',
      message: webPushSetupMessage(),
    };
  }
  return enableAdminWebPush(uid, false);
}

export async function removeAdminWebPush(uid: string): Promise<void> {
  const stored = readStoredDevice();
  if (stored?.uid === uid) {
    await httpsCallable<
      { token: string; deviceId?: string },
      UnregisterWebPushResult
    >(functions, 'unregisterAdminWebPushToken')({
      token: stored.token,
      ...(stored.documentId ? { deviceId: stored.documentId } : {}),
    }).catch(() => undefined);
    window.localStorage.removeItem(storedDeviceKey);
  }
  if (await firebaseMessagingSupported()) {
    await deleteToken(getMessaging(app)).catch(() => false);
  }
}

function adminAlert(payload: MessagePayload): AdminPushAlert {
  return {
    title: payload.notification?.title || 'VolTrike violation-case alert',
    body: payload.notification?.body || 'A violation case update is available.',
    violationId: payload.data?.violationId || null,
    messageId: payload.data?.messageId || null,
    type: payload.data?.type || null,
  };
}

export async function listenForAdminPush(
  onAlert: (alert: AdminPushAlert) => void,
): Promise<() => void> {
  if (!await firebaseMessagingSupported()) return () => undefined;
  return onMessage(getMessaging(app), (payload) => onAlert(adminAlert(payload)));
}
