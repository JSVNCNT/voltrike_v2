# VolTrike data retention

VolTrike keeps operational data only as long as it remains useful for ride
coordination, support, or safety review.

| Data | Retention | Mechanism |
| --- | --- | --- |
| Trip chat photos | 48 hours from upload | Cloud Storage lifecycle for `final/chat/` plus `mediaExpiresAt` in the message |
| Reported chat photo evidence | Until resolved, with a 180-day maximum | Private evidence copy deleted on resolution plus Storage lifecycle fallback |
| Normal trip chat and conversation metadata | 30 days | Firestore TTL field `purgeAt` |
| LiveKit audio | Not recorded or stored by VolTrike | Voice-only real-time transport |
| Call signalling documents | 7 days | Firestore TTL field `purgeAt`; credentials expire much sooner |
| Typing indicators | 24 hours | Firestore TTL field `purgeAt` |
| Chat moderation incidents | 180 days | Firestore TTL field `purgeAt` for accountable human review |

Firestore TTL policies must be enabled for the `purgeAt` field on the
`messages`, `typing`, `bookingCalls`, `chat`, and `chatModerationIncidents`
collection groups. Storage lifecycle configuration is in
`storage.lifecycle.json`. After authenticating `gcloud`, apply both policies
from the repository root with:

```powershell
.\scripts\configure-chat-retention.ps1
```

## Chat moderation matching

System Admin rules are evaluated by the Go API before a message is saved.
Whole-word matching is the safe default. Contains matching is available for
compound slang, stretched-spelling tolerance handles repeated letters, and
each rule may define up to 25 explicit shorthand aliases. Explicit aliases are
preferred over general fuzzy matching because fuzzy matching can censor
unrelated names and abbreviations.

Reported driver chat evidence is available to the driver's TODA and System
Admin. Passenger chat evidence is System Admin-only. The original expiring
chat photo remains inaccessible after 48 hours; administrators review a
separate protected evidence copy through a five-minute signed URL.
