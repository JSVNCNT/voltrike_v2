# MORNING HANDOFF
- STATUS: Overnight code pass complete; unbuilt; untested; undeployed.
- DEVICES: Phone untouched; emulator untouched; accounts preserved.
- DEMO: Jung's Townhouse -> Estefania.

# FIRST VALIDATION
1. Resolve Flutter dependencies.
2. Format changed Dart sources.
3. Run Flutter analyze and tests.
4. Run Functions tests and syntax checks.
5. Run admin TypeScript build.
6. Fix all compile and critical test failures.

# DEPLOYMENT
1. Deploy Functions.
2. Deploy Firestore rules and indexes.
3. Deploy Realtime Database rules.
4. Deploy Storage rules.
5. Build/install fresh debug APKs.
6. Open Settings -> System diagnostics on both devices.

# TWO-ROLE DEFENSE RUN
1. Driver online; confirm foreground location notification.
2. Passenger requests Jung's Townhouse -> Estefania.
3. Driver accepts; both restart into active tracking.
4. Verify moving marker, route refresh, ETA, call, chat.
5. Test Google Maps/Waze handoff and VolTrike restoration.
6. Driver marks arrival, starts ride, confirms cash/drop-off.
7. Verify driver earnings receipt; return home once.
8. Verify passenger rating -> receipt -> home once.
9. Verify history identity, receipt, report submission.
10. Verify incoming call accept, decline, timeout, end.
11. Verify TODA admin metrics, approvals, reports.
12. Verify developer metrics, suspension, safety oversight.

# HIGH-RISK CHECKS
- Driver tracking route remains available after app backgrounding.
- Passenger completion coordinator does not reopen rating repeatedly.
- Driver clear-booking listener opens receipt, not home.
- Cash completion remains idempotent on repeated tap.
- Call Firestore read rules expose participants only.
- Aggregate queries require no unexpected indexes.
- Android background-location permission flow is acceptable.
- Waze missing-app failure remains user-safe.

# RELEASE EXCLUSIONS
- Polygon redesign/testing remains deferred.
- Store release hardening remains deferred.
- No production-release claim until M14 passes.
