# VolTrike V2 contracts

`openapi.yaml` is the transport source of truth. All protected requests carry
a Firebase ID token in `Authorization: Bearer <token>` and, outside the local
demo project, a Firebase App Check token in `X-Firebase-AppCheck`.

Commands use a caller-generated `commandId`. Aggregate mutations also carry
`expectedRevision`. Replaying the same command with the same authenticated
owner returns its recorded result; reusing it for another owner or payload is
rejected. A stale revision returns HTTP 412 and must be reconciled by reading
the current projection rather than retried in a loop.

Successful responses are JSON projections. Errors use this stable envelope:

```json
{"error":{"code":"failed_precondition","message":"safe user-facing detail","requestId":"optional trace id"}}
```

The fixtures directory freezes cross-language booking states, allowed
transitions, and representative policy/settlement inputs. Go owns the final
decision; Dart, TypeScript, Node, and Rust may use the fixtures for parity but
must not become authoritative writers.

## V2 Firebase layout

- `bookings/{bookingId}`: authoritative aggregate projection with `revision`.
- `command_receipts/{commandId}`: durable idempotency receipt and result.
- `quote_receipts/{tokenHash}`: one-time quote consumption record.
- `driver_sessions/{sessionId}`: driver/device lease and monotonic sequence.
- `driver_profiles/{driverId}.activeSessionId`: current lease pointer.
- `outbox/{eventId}`: post-commit integration event.
- RTDB `driverLocations/{driverId}/{sessionId}`: session-scoped telemetry.
- RTDB `driverPresence/{driverId}/{sessionId}`: scoped presence projection.

Clients may listen to approved projections. They do not directly mutate these
authoritative documents.
