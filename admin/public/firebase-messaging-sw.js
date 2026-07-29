/* global firebase */

// Register notification-click handling before importing Firebase Messaging so
// VolTrike's violation deep link wins when the SDK displays a background
// notification from a notification + data payload.
self.addEventListener('notificationclick', (event) => {
  const notificationData = event.notification?.data || {};
  const firebaseMessage = notificationData.FCM_MSG || {};
  const messageData = firebaseMessage.data || notificationData.data || notificationData;
  const violationId = messageData.violationId || null;
  if (!violationId) return;

  event.stopImmediatePropagation();
  event.notification.close();
  const target = new URL(
    `/?page=violations&case=${encodeURIComponent(violationId)}`,
    self.location.origin,
  ).href;
  event.waitUntil(self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  }).then(async (clients) => {
    const existing = clients.find((client) =>
      new URL(client.url).origin === self.location.origin);
    if (existing) {
      await existing.navigate(target);
      return existing.focus();
    }
    return self.clients.openWindow(target);
  }));
});

importScripts('https://www.gstatic.com/firebasejs/11.0.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.0.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCruee8iglatJcElwDJl9aBuPD19XaPwDw',
  authDomain: 'voltrike-v2.firebaseapp.com',
  projectId: 'voltrike-v2',
  storageBucket: 'voltrike-v2.firebasestorage.app',
  messagingSenderId: '327670792817',
  appId: '1:327670792817:web:d694dafb0cfcce03c5d1d0',
});

const messaging = firebase.messaging();
messaging.onBackgroundMessage((payload) => {
  // FCM automatically displays notification payloads. Only data-only messages
  // need a custom notification here, which prevents duplicate alerts.
  if (payload.notification) return;
  const violationId = payload.data?.violationId || null;
  const title = payload.data?.title || 'VolTrike violation-case alert';
  const body = payload.data?.body || 'A violation case update is available.';
  self.registration.showNotification(title, {
    body,
    tag: violationId
      ? `driver-violation-${violationId}`
      : 'voltrike-admin-alert',
    requireInteraction: payload.data?.type === 'driver_violation',
    data: {
      data: payload.data || {},
      violationId,
    },
  });
});
