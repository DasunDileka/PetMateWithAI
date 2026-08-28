# PetMate — AI-Powered Smart Pet Care Companion

**CMP 7003 — Emerging Mobile Applications · PRAC1 Practical Project**

PetMate is an AI-driven smart lifestyle companion for pet owners. It tracks a
pet's daily care — feeding, exercise, medication, vaccination, grooming and
veterinary visits — and layers on statistical analysis and a natural-language
assistant that explains what the records actually show.

The design principle throughout: **the AI explains numbers, it never invents
them.** Every figure the assistant states is computed on-device first, then
handed to the model as fact.

---

## 1. Quick start

### Prerequisites

| Requirement | Version used |
|---|---|
| Flutter SDK | 3.47.0 (stable) |
| Dart | 3.13.0 |
| Android SDK | API 36 |
| JDK | 17+ (Android Studio JBR) |
| Emulator | Pixel 7, API 36, `google_apis` x86_64 |

### Configure secrets

No credentials live in source. Copy the template and fill it in:

```bash
cp dart_defines.example.json dart_defines.json
```

`dart_defines.json` is git-ignored. It supplies:

| Key | Purpose |
|---|---|
| `GEMINI_API_KEY` | Primary AI provider |
| `OPENROUTER_API_KEY` | Fallback provider (free models only) |
| `AI_GATEWAY_URL` | Optional Cloudflare Worker endpoint — see §6 |

Firebase configuration comes from `android/app/google-services.json`, which is
also git-ignored and injected at build time by the `google-services` Gradle
plugin. No Firebase identifiers appear in Dart source.

### Run

```bash
flutter pub get
```

```bash
flutter run --dart-define-from-file=dart_defines.json
```

### Test

```bash
flutter test
```

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Presentation        screens/ + shared/widgets/          │
│                      Material 3, one shared theme        │
├──────────────────────────────────────────────────────────┤
│  State               ChangeNotifier controllers          │
│                      AuthController · PetController      │
│                      CareController (9 live listeners)   │
├──────────────────────────────────────────────────────────┤
│  Domain              CareAnalytics  (pure Dart, tested)  │
│                      AiSafety       (pure Dart, tested)  │
│                      PetContextBuilder                   │
├──────────────────────────────────────────────────────────┤
│  Data                Repositories → Refs (path registry) │
│                      Models (Firebase-free, mappable)    │
├──────────────────────────────────────────────────────────┤
│  Services            Firebase Auth · Firestore · Storage │
│                      Notifications · Location · Photos   │
│                      AiClient → Gateway/Gemini/OpenRouter│
└──────────────────────────────────────────────────────────┘
```

### Directory layout

```
lib/
├── core/
│   ├── config/        AppConfig — build-time configuration
│   ├── services/      auth, firestore refs, notifications, location, photos
│   ├── theme/         AppColors (sampled from the logo), AppTheme
│   └── utils/         field mappers, validators
├── features/
│   ├── ai/            transports, safety, prompts, context builder, chat
│   ├── analytics/     CareAnalytics + charts
│   ├── auth/          controller + login/register/reset screens
│   ├── calendar/      unified care calendar
│   ├── care/          feeding, exercise, medicine, vaccination, grooming
│   ├── dashboard/     home screen, AI insight card, pet switcher
│   ├── history/       unified care history
│   ├── pets/          pet CRUD + active-pet selection
│   ├── profile/       settings, privacy, diagnostics, demo data
│   ├── shell/         splash + bottom-navigation shell
│   └── veterinary/    vets, appointments, medical record, map
└── shared/
    ├── models/        pure-Dart domain models
    └── widgets/       brand, state views, UI kit
```

### Why the models are Firebase-free

`shared/models/` imports no Firebase package. Reads go through
`core/utils/field_mapper.dart`, which duck-types Firestore's `Timestamp` via
`dynamic`. Consequently the whole domain layer — including `CareAnalytics` —
is unit-testable with no emulator, no mocks and no Firebase harness.

---

## 3. Data model

```
users/{uid}
├── displayName, email, activePetId, createdAt
├── pets/{petId}
│   ├── feedingSchedules/{id}     the plan
│   ├── feedingRecords/{id}       the actuals   (dayKey denormalised)
│   ├── exerciseRecords/{id}      + GPS route
│   ├── medicines/{id}            the course
│   ├── medicineDoses/{id}        per-dose outcome
│   ├── vaccinations/{id}
│   ├── groomingRecords/{id}
│   ├── appointments/{id}
│   ├── medicalHistory/{id}       unified clinical timeline
│   └── aiInsights/{kind}         cached AI output + fingerprint
├── veterinarians/{id}            user-level: one clinic serves all pets
└── chatSessions/{id}/messages/{id}
```

**Plan / actuals split.** Feeding schedules and medicine courses are stored
separately from their per-occurrence records. That is what makes "12 of 14
scheduled feedings completed" a *measurement* rather than an estimate — the
denominator comes from the plan, so a feeding the owner never logged still
counts as missed.

**Denormalised `dayKey`.** Same-day lookups use a `yyyy-MM-dd` equality filter
instead of a timestamp range, keeping them to a single index seek and avoiding
composite indexes entirely.

---

## 4. The AI layer

```
User question
   │
   ▼
AiSafety.assess()  ─── blocked ──▶  deterministic local response
   │                                (never reaches a model)
   ▼ allow / cautious
PetContextBuilder  ──▶  facts computed by CareAnalytics
   │
   ▼
AiClient  ──▶  Gateway  ──▶  Gemini 2.5 Flash  ──▶  OpenRouter (free)
   │              (first configured transport wins; failures fall through)
   ▼
AiResult → cached in aiInsights/{kind} keyed by context fingerprint
```

### Grounding

`CareAnalytics` computes completion rates, averages, trend direction (least
squares over a zero-filled daily series), and anomaly flags (z-score plus
percentage drop against the pet's *own* baseline). Those numbers go into the
prompt; the system prompt instructs the model to quote them exactly and
forbids recalculation.

### Caching

Generated insights are stored with a SHA-256 fingerprint of the context they
came from. Reopening the dashboard reuses the cached text; a new model call
happens only when the underlying data actually changed, or on explicit refresh.
Opening a screen never costs an API call.

### Safety

Two layers:

1. **Deterministic pre-check** (`ai_safety.dart`) — requests for a diagnosis,
   a prescription, or a dose change are answered locally and never sent. A
   request that is never sent cannot produce an unsafe answer.
2. **System prompt** — governs everything that does reach the model.

The filter is deliberately narrow: 25 unit tests assert both that clinical
requests are blocked *and* that ordinary care questions still get through.

### Degradation

With no network or no configured provider, `AiService.offlineDailyBrief()`
produces a genuine data-driven summary from `CareAnalytics` alone. The
intelligence features never go blank.

---

## 5. Security

| Control | Implementation |
|---|---|
| Authentication | Firebase Auth, email/password, persistent session |
| Authorisation | Firestore rules — every document under `users/{uid}`, ownership checked per request |
| Default deny | `match /{document=**} { allow read, write: if false; }` |
| Field validation | Rules validate types, non-empty names, weight bounds, chat roles, message length |
| Immutable fields | Email set from the auth token and cannot be changed by a client write |
| Account enumeration | Password reset returns success even for unknown addresses |
| Error messages | Firebase codes mapped to neutral copy; raw exceptions never rendered |
| Secrets | `--dart-define-from-file`, git-ignored; `google-services.json` git-ignored |
| Storage | Images only, own prefix only, 5 MB cap |
| AI privacy | Only pet-care facts leave the device. Never name, email, uid or document ids |
| Prompt bounds | Context capped at 4,500 characters; history capped at 6 turns |

Rules live in [`firestore.rules`](firestore.rules) and
[`storage.rules`](storage.rules).

### Honest limitation

In the default build the API keys are compiled into the APK. `--dart-define`
keeps them out of *source control*, but a key inside an installed APK is
extractable. The production answer is §6.

---

## 6. Cloudflare AI Gateway (written, not deployed)

`cloudflare/ai-gateway/` contains a deployable Worker that removes the
limitation above:

- Verifies the caller's **Firebase ID token** (RS256, Google JWKS, full claim
  checks) before spending any AI quota
- Holds `GEMINI_API_KEY` / `OPENROUTER_API_KEY` as encrypted Worker secrets —
  the device never sees them
- Per-user rate limiting via KV
- Gemini primary, OpenRouter free-tier fallback

Deploy, then set `AI_GATEWAY_URL` in `dart_defines.json`. The app switches
transport automatically — `AiClient` prefers the gateway whenever it is
configured. **No application code changes.**

---

## 7. Performance

| Concern | Approach |
|---|---|
| Query cost | Every query scoped to one pet, bounded by date range or `limit` |
| Index cost | Range filter and `orderBy` always on the same field — no composite indexes needed |
| Listener count | Nine listeners opened once per pet, above the tab bar, shared by all tabs |
| Recomputation | Analytics recompute debounced 120 ms — one user action triggers one recalculation |
| AI cost | Fingerprint-keyed caching; 6-hour TTL |
| History | Day-grouped with incremental "show earlier"; filters applied in memory |
| Route data | GPS tracks downsampled to 200 points before write |
| Images | Downscaled to 1024 px / 80% quality on-device before upload |
| Tab state | `IndexedStack` preserves scroll position without re-subscribing |

---

## 8. Learning outcome coverage

| LO | Evidence |
|---|---|
| **LO1** — UI design, GUI principles | Material 3, single shared theme, consistent loading/empty/error states, 48 dp targets, clamped text scaling, semantic labels |
| **LO2** — SDK proficiency: geolocation, mapping, multimedia, persistent storage | GPS walk tracking with haversine distance; OpenStreetMap clinic map; camera/gallery pet photos via Cloud Storage; Firestore + SharedPreferences persistence |
| **LO3** — Design patterns, technical solutions | Repository pattern, strategy pattern for AI transports, provider-based DI, path registry, plan/actuals separation |
| **LO4** — Critical evaluation: performance, security, scalability | §5, §7; documented limitations and the gateway migration path |
| **LO5** — Advanced coding | Statistical engine (regression, z-score anomaly detection), nine-stream reactive aggregation, deterministic safety classifier, 45 unit tests |

---

## 9. Testing

```bash
flutter test
```

45 unit tests, all passing:

- **`care_analytics_test.dart`** (20) — zero-filling, trend direction,
  completion measured against the plan, adherence, anomaly detection with and
  without a baseline, and an assertion that anomaly wording never contains
  diagnostic language.
- **`ai_safety_test.dart`** (25) — clinical requests blocked, emergencies
  flagged, symptom mentions handled cautiously, and ordinary care questions
  still allowed (guarding against over-blocking).

Static analysis: `flutter analyze` → **no issues**.

---

## 10. Demonstration

Load the sample dataset from **Profile → Sample data**. It seeds two
deliberately contrasting pets so personalisation is observable:

- **Bruno** — Labrador, 3 years, 18 kg. Declining activity (30 → 12 min over
  five days), two missed feedings, vaccination due in 5 days, vet appointment
  tomorrow at 10:30.
- **Luna** — British Shorthair, 9 years, 4.6 kg. Steady routine, daily joint
  supplement with one missed dose, nail trim overdue.

Asking the same question about each pet produces visibly different answers
grounded in different numbers.

---

## 11. Known limitations

- API keys are extractable from the APK unless the Cloudflare gateway is
  deployed (§6).
- Nearby-clinic search plots *saved* vets only; there is no third-party clinic
  directory integration.
- Notifications are local, not push — reminders derive from on-device data, so
  a server round-trip would add cost and a privacy surface for no benefit.
- Reminders use inexact alarms, so delivery can be delayed by Doze on a real
  device.
- Anomaly detection needs roughly a week of history before it will report
  anything; this is deliberate, to avoid flagging noise as signal.
