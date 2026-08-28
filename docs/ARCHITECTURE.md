# PetMate — Architecture Reference

Diagrams and models for the CMP 7003 PRAC1 report. All diagrams are Mermaid and
render on GitHub, in VS Code, and in most Markdown-to-PDF pipelines.

---

## 1. System architecture

```mermaid
flowchart TB
    subgraph Device["📱 Android Device"]
        UI["Presentation Layer<br/>Material 3 screens + shared widgets"]
        STATE["State Layer<br/>AuthController · PetController · CareController"]
        DOMAIN["Domain Layer<br/>CareAnalytics · AiSafety · PetContextBuilder"]
        DATA["Data Layer<br/>Repositories · Models · Refs"]
        LOCAL["On-device<br/>Local notifications · GPS · Camera · Prefs"]
    end

    subgraph Firebase["☁️ Firebase"]
        AUTH["Firebase Authentication"]
        FS[("Cloud Firestore<br/>real-time listeners")]
        ST[("Cloud Storage<br/>pet photos")]
        RULES{{"Security Rules<br/>ownership + validation"}}
    end

    subgraph AI["🤖 AI Providers"]
        GW["Cloudflare Worker<br/>AI Gateway"]
        GEM["Gemini 2.5 Flash"]
        OR["OpenRouter<br/>free models"]
    end

    OSM["🗺️ OpenStreetMap tiles"]

    UI <--> STATE
    STATE <--> DOMAIN
    STATE <--> DATA
    DATA <--> FS
    DATA <--> ST
    STATE <--> AUTH
    DOMAIN --> GW
    GW --> GEM
    GW -.fallback.-> OR
    DOMAIN -.direct mode.-> GEM
    DOMAIN -.direct fallback.-> OR
    FS --- RULES
    ST --- RULES
    AUTH --> RULES
    UI --> LOCAL
    UI --> OSM
```

---

## 2. AI request flow

The critical path. Note that blocked requests terminate **before** any network
call.

```mermaid
flowchart TD
    Q["User asks a question"] --> S{"AiSafety.assess()"}

    S -->|blocked / emergency| LOCAL["Deterministic local response<br/>❌ no model call"]
    S -->|cautious| CTX["Build pet context<br/>+ extra safety instruction"]
    S -->|allow| CTX

    CTX --> AN["CareAnalytics computes<br/>completion · averages · trend · anomalies"]
    AN --> FP["SHA-256 fingerprint of context"]

    FP --> CACHE{"Cached insight<br/>matches fingerprint<br/>and within TTL?"}
    CACHE -->|yes| HIT["Return cached text<br/>❌ no model call"]
    CACHE -->|no| CLIENT["AiClient"]

    CLIENT --> T1{"Gateway configured?"}
    T1 -->|yes| GW["Cloudflare Worker<br/>verifies Firebase ID token"]
    T1 -->|no| T2{"Gemini key present?"}
    GW -->|success| OUT
    GW -->|failure| T2
    T2 -->|yes| GEM["Gemini 2.5 Flash"]
    T2 -->|no| T3
    GEM -->|success| OUT
    GEM -->|failure| T3{"OpenRouter free model"}
    T3 -->|success| OUT["AiResult"]
    T3 -->|failure| DEGRADE["offlineDailyBrief()<br/>on-device statistics only"]

    OUT --> STORE["Cache with fingerprint"]
    STORE --> SHOW["Render to user"]
    LOCAL --> SHOW
    HIT --> SHOW
    DEGRADE --> SHOW
```

---

## 3. Real-time synchronisation

What happens when the user records an exercise session.

```mermaid
sequenceDiagram
    participant U as User
    participant S as ExerciseScreen
    participant R as CareRepository
    participant F as Cloud Firestore
    participant C as CareController
    participant D as Dashboard
    participant A as AI Insight Card

    U->>S: Record 20-minute walk
    S->>R: addExercise(record)
    R->>F: add() to exerciseRecords
    F-->>C: snapshot listener fires
    Note over C: debounce 120 ms
    C->>C: PetContextBuilder.build()
    C->>C: CareAnalytics recomputes<br/>series · trend · anomalies
    C-->>D: notifyListeners()
    C-->>A: notifyListeners()
    D->>D: Today's exercise updates
    D->>D: Chart redraws
    A->>A: Fingerprint changed → regenerate
    A->>A: New insight reflects the walk
```

---

## 4. Use cases

```mermaid
flowchart LR
    Owner(["🧑 Pet Owner"])

    subgraph Account
        UC1["Register / sign in"]
        UC2["Reset password"]
        UC3["Manage profile"]
    end

    subgraph Pets
        UC4["Add / edit / delete pet"]
        UC5["Select active pet"]
        UC6["Upload pet photo"]
    end

    subgraph Care
        UC7["Schedule feeding"]
        UC8["Record exercise"]
        UC9["Track walk with GPS"]
        UC10["Manage medication"]
        UC11["Record vaccination"]
        UC12["Manage grooming"]
    end

    subgraph Veterinary
        UC13["Save veterinarian"]
        UC14["Book appointment"]
        UC15["View medical record"]
        UC16["Find clinics on map"]
    end

    subgraph Intelligence
        UC17["View daily AI insight"]
        UC18["Ask the AI assistant"]
        UC19["View activity trend"]
        UC20["Review pattern alerts"]
        UC21["Generate vet summary"]
    end

    Owner --> UC1 & UC2 & UC3
    Owner --> UC4 & UC5 & UC6
    Owner --> UC7 & UC8 & UC9 & UC10 & UC11 & UC12
    Owner --> UC13 & UC14 & UC15 & UC16
    Owner --> UC17 & UC18 & UC19 & UC20 & UC21
```

---

## 5. Firestore data model

```mermaid
erDiagram
    USER ||--o{ PET : owns
    USER ||--o{ VETERINARIAN : saves
    USER ||--o{ CHAT_SESSION : has
    CHAT_SESSION ||--o{ CHAT_MESSAGE : contains

    PET ||--o{ FEEDING_SCHEDULE : "plan"
    PET ||--o{ FEEDING_RECORD : "actual"
    PET ||--o{ EXERCISE_RECORD : logs
    PET ||--o{ MEDICINE : "course"
    PET ||--o{ MEDICINE_DOSE : "actual"
    PET ||--o{ VACCINATION : records
    PET ||--o{ GROOMING_RECORD : schedules
    PET ||--o{ APPOINTMENT : books
    PET ||--o{ MEDICAL_HISTORY : accumulates
    PET ||--o{ AI_INSIGHT : caches

    FEEDING_SCHEDULE ||--o{ FEEDING_RECORD : "generates"
    MEDICINE ||--o{ MEDICINE_DOSE : "generates"
    VETERINARIAN ||--o{ APPOINTMENT : "attends"

    USER {
        string uid PK
        string displayName
        string email "immutable, from auth token"
        string activePetId
    }
    PET {
        string id PK
        string name
        string species
        string breed
        date dateOfBirth "age derived, never stored"
        number weightKg
    }
    FEEDING_SCHEDULE {
        string id PK
        string label
        int hour
        int minute
        bool active
    }
    FEEDING_RECORD {
        string id PK "scheduleId_dayKey — idempotent"
        timestamp scheduledAt
        string status
        string dayKey "denormalised"
    }
    EXERCISE_RECORD {
        string id PK
        string type
        int durationMinutes
        number distanceKm
        array route "GPS, downsampled to 200"
    }
    AI_INSIGHT {
        string id PK "= kind"
        string text
        string contextFingerprint "cache key"
        string provider
    }
```

---

## 6. Navigation

```mermaid
flowchart TD
    SPLASH["Splash"] --> GATE{"Auth state"}
    GATE -->|no session| LOGIN["Login"]
    GATE -->|session| SHELL

    LOGIN <--> REG["Register"]
    LOGIN --> FORGOT["Reset password"]

    SHELL{"Has pets?"} -->|no| ONBOARD["Add first pet"]
    SHELL -->|yes| NAV

    NAV["Bottom navigation"] --> HOME["🏠 Home"]
    NAV --> PETS["🐾 Pets"]
    NAV --> CARE["❤️ Care"]
    NAV --> VET["🏥 Vet"]
    NAV --> AI["✨ AI"]

    HOME --> PROFILE["Profile & settings"]
    HOME --> ANALYTICS["Analytics"]
    PROFILE --> DEMO["Sample data"]

    PETS --> PETFORM["Add / edit pet"]

    CARE --> FEED["Feeding"]
    CARE --> EX["Exercise"]
    EX --> WALK["GPS walk tracker"]
    CARE --> MED["Medicine"]
    CARE --> VAC["Vaccination"]
    CARE --> GROOM["Grooming"]
    CARE --> CAL["Calendar"]
    CARE --> HIST["Care history"]

    VET --> APPT["Appointments"]
    VET --> VETS["Saved vets"]
    VET --> MEDREC["Medical record"]
    VET --> MAP["Clinic map"]

    AI --> CHAT["Chat history"]
    AI --> SUMMARY["Vet visit summary"]
```

---

## 7. Security architecture

```mermaid
flowchart TB
    subgraph Client
        APP["PetMate app"]
        VAL["Client validation<br/>(usability, not security)"]
    end

    subgraph Transport
        TLS["TLS 1.3 — all traffic"]
    end

    subgraph Identity
        FA["Firebase Auth"]
        TOK["ID token (RS256, ~1h)"]
    end

    subgraph Authorisation
        RULES["Firestore Security Rules"]
        R1["isOwner(uid) on every path"]
        R2["Field type + range validation"]
        R3["Email immutable after creation"]
        R4["Default deny outside /users"]
    end

    subgraph Secrets
        DD["--dart-define-from-file<br/>(git-ignored)"]
        WS["Worker secrets<br/>(encrypted, server-side)"]
    end

    APP --> VAL --> TLS --> FA --> TOK --> RULES
    RULES --> R1 & R2 & R3 & R4
    APP -.direct mode.-> DD
    APP -.gateway mode.-> WS

    style WS fill:#d4edda
    style DD fill:#fff3cd
```

**Reading the colours:** gateway mode (green) keeps provider keys server-side.
Direct mode (amber) keeps them out of version control but not out of the APK —
the documented trade-off, with a one-line migration path.

---

## 8. Layered dependency rule

```mermaid
flowchart LR
    P["Presentation"] --> S["State"]
    S --> D["Domain"]
    S --> R["Data"]
    R --> F["Firebase SDK"]
    D -.->|"no dependency"| F

    style D fill:#d4edda
    style F fill:#f8d7da
```

The domain layer has **no** Firebase dependency. `CareAnalytics`, `AiSafety`
and every model are pure Dart, which is why 45 unit tests run in ~3 seconds
with no emulator.
