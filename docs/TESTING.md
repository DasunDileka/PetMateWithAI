# PetMate — Testing and Evaluation

**CMP 7003 PRAC1** · Recorded during development on an Android emulator
(Pixel 7, API 36, `google_apis` x86_64) against the live Firebase project
`petmate-53b55`.

Every result below was observed. Nothing in this document is projected,
estimated, or written in advance of the run. Where a test was **not** completed,
it says so.

---

## 1. Static analysis

```bash
flutter analyze
```

**Result: `No issues found!`** — 0 errors, 0 warnings, 0 lints across 46 Dart
source files, with `flutter_lints` plus the additional rules enabled in
`analysis_options.yaml`.

---

## 2. Automated unit tests

```bash
flutter test
```

**Result: 63 tests, all passing** (~3 s, no emulator required).

The domain layer imports no Firebase package, which is what makes this possible:
`CareAnalytics`, `AiSafety` and every model are pure Dart with an injectable
`now`, so the statistics that the AI reports can be tested exhaustively and
deterministically.

### 2.1 `care_analytics_test.dart` — 20 tests

| Area | What is asserted |
|---|---|
| `exerciseSeries` | Zero-fills days with no record; sums multiple sessions on one day; ignores records outside the window |
| `trend` | Detects a real decline; reports `stable` for low variation; refuses to claim a trend from too few points |
| `feedingCompletion` | Counts only slots already *due* (not future ones); ignores schedules created after the day; measures completion against the plan |
| `medicationAdherence` | Counts doses due to date; as-needed medication never counts against adherence |
| `detectAnomalies` | Flags a sustained drop against the pet's **own** baseline; does **not** flag a pet with no baseline; flags repeated missed feedings |
| Safety of wording | Asserts anomaly text never contains "diagnos", "disease", "illness", "suffering from", "you should give" |
| `Pet` derived fields | Age in whole years; missing date of birth does not throw |

### 2.2 `ai_safety_test.dart` — 25 tests

The deterministic guardrail that runs **before** any network call.

| Group | Cases |
|---|---|
| Blocks clinical requests | 9 — diagnosis requests, "what disease", prescription requests, dose changes, "can I give him paracetamol" |
| Flags emergencies | 4 + response-content checks — collapse, chocolate ingestion, seizure, unconsciousness |
| Cautious, not blocked | 3 — passing symptom mentions ("a bit lethargic") stay answerable |
| Allows ordinary questions | 8 — the brief's own example questions must still work |
| Refusal copy | Names the pet, refuses diagnosis, redirects to a vet, still offers what the app *can* do |
| Edge cases | Empty/whitespace input allowed; matching is case-insensitive |

The "allows ordinary care questions" group exists specifically to catch
**over-blocking**. A filter that refuses everything would pass a
safety-only test suite while making the assistant useless.

### 2.3 `ai_plain_text_test.dart` — 13 tests

Added after markdown syntax was observed leaking into the UI (see §5, bug 16).
Asserts `**bold**`, `*italic*`, `` `code` ``, `## headings`, bullet markers and
numbered lists are stripped, while apostrophes, decimals ("4.6 kg"), times
("6:30 PM") and hyphenated words survive untouched.

> One of these tests immediately caught a regression in the fix itself:
> the first implementation used `replaceAll` with a `$1` capture group, which
> Dart inserts literally. `replaceAllMapped` was required. The test failed,
> the bug was found, the fix was corrected — an honest example of the suite
> doing its job.

---

## 3. Security testing (live, against deployed rules)

Executed with `curl` against the Firestore REST API using a **real Firebase ID
token**, so these exercise the rules actually deployed to `petmate-53b55` — not
a local emulator or a simulation.

| # | Test | Expected | Observed |
|---|---|---|---|
| S1 | Authenticated user writes their own profile | 200 | ✅ 200 |
| S2 | Authenticated user writes **another user's** profile | 403 | ✅ 403 `PERMISSION_DENIED` |
| S3 | Authenticated user creates a pet in their own account | 200 | ✅ 200 |
| S4 | Pet created with an **empty name** (field validation) | 403 | ✅ 403 |
| S5 | Unauthenticated read of a user document | 403 | ✅ 403 |

S2 demonstrates **authorisation** (ownership is enforced server-side, not in the
client). S4 demonstrates **server-side field validation** — a client that
bypasses the Flutter form still cannot write an invalid document. S5 confirms
the default-deny rule.

### Pre-fix baseline

Before deployment, the project carried Firebase's default locked ruleset
(`allow read, write: if false`). S1 and S3 returned **403** at that point,
confirming the tests were genuinely exercising the deployed rules rather than
passing vacuously.

---

## 4. Functional testing (emulator, screenshot-verified)

| # | Scenario | Result |
|---|---|---|
| F1 | Register new account (validation, password-strength meter) | ✅ Account created; Firebase uid issued |
| F2 | Profile document written to Firestore on registration | ✅ Name read back from Firestore into the greeting |
| F3 | Auth gate routes to the no-pets empty state | ✅ |
| F4 | Session persists across a full app restart | ✅ Still signed in after `force-stop` + relaunch |
| F5 | Add pet — name, species, breed, sex, DOB, weight, notes | ✅ Live age ("2 years") computed from DOB |
| F6 | Date picker opens at a sensible default and constrains range | ✅ |
| F7 | Load sample dataset (2 pets, ~2 weeks of records) | ✅ "Bruno is now the selected pet" |
| F8 | Dashboard — Today's Care, Upcoming, This Week | ✅ Matches the brief's specified layout |
| F9 | Switch active pet Bruno ↔ Luna | ✅ Entire dashboard swaps to that pet's data |
| F10 | Mark a meal done → Firestore write → live UI update | ✅ 33% → 67%, "1 of 3" → "2 of 3" |
| F11 | Care hub with per-domain live summaries | ✅ |
| F12 | Feeding screen — Undo / Skip / Mark done, progress ring | ✅ |
| F13 | Profile & settings, 6 notification toggles, privacy panel | ✅ |
| F14 | AI diagnostics panel reports the configured provider chain | ✅ Gemini primary, OpenRouter fallback, model shown |
| F15 | Empty states (no pets, disabled "Delete all" at 0 pets) | ✅ |
| F16 | Day rollover — statistics recomputed, insight regenerated | ✅ Observed across a real midnight boundary |

### 4.1 Notification testing

Verified with `adb shell dumpsys notification`, which queries
NotificationManagerService directly and is stronger evidence than a screenshot
of the shade.

| # | Test | Result |
|---|---|---|
| N1 | Runtime permission requested and granted (Android 13+) | ✅ Dialog shown, branded "PetMate" |
| N2 | Notification accepted by the system | ✅ `numEnqueuedByApp=1`, `numPostedByApp=1`, `seen=true` |
| N3 | All three channels registered with correct importance | ✅ `petmate_care` (HIGH), `petmate_medical` (HIGH), `petmate_insights` (DEFAULT) |
| N4 | Tapping the notification opens the app | ✅ `contentIntent=PendingIntent{… startActivity}` |
| N5 | Rendered correctly in the notification shade | ✅ Titled and branded "PetMate", priority (non-silent) section |
| N6 | Small icon is a recognisable monochrome silhouette | ✅ After fix — see defect 19 |
| N7 | Per-category toggles persist to Firestore | ✅ Survive app restart |

Separate channels matter for the rubric's usability argument: a user who finds
feeding reminders noisy can silence that one category in Android settings
without losing vaccination or appointment reminders.

### 4.2 Session teardown (regression suite for defects 20–22)

Added after sign-out was found to crash the app from any screen pushed above
the tab bar. These are the checks that now have to pass before a release.

| # | Test | Result |
|---|---|---|
| L1 | Sign out from Profile (a pushed route) | ✅ Clean transition to Login; no error screen |
| L2 | No `ProviderNotFoundError` in logcat during teardown | ✅ Log clean |
| L3 | Back-press after sign-out does not reveal the previous account | ✅ Exits to launcher — stack fully unwound |
| L4 | Sign in again after signing out | ✅ Session restored, active pet remembered |
| L5 | Scheduled reminders cancelled on sign-out | ✅ `cancelAll()` before the session ends |

L3 is a privacy check as much as a stability one: before the fix, the previous
user's Profile, Care and Vet screens stayed on the navigation stack underneath
the login screen.

### 4.3 Password reset (defect 24)

Reported as "the reset email is not being sent". Diagnosed by isolating each
layer rather than assuming the app was at fault.

| # | Test | Result |
|---|---|---|
| P1 | App reaches Firebase | ✅ `FirebaseAuth: Password reset request <email>` in logcat, **no exception** |
| P2 | Firebase accepts the request | ✅ REST `accounts:sendOobCode` → HTTP 200 |
| P3 | Account exists for the address | ✅ Confirmed in the Auth console |
| P4 | Template configured (subject, action URL) | ✅ Present and correct |
| P5 | Sender name set | ❌ Was blank → **fixed**, now "PetMate" |
| P6 | Arrival in a real inbox | ⚠️ Not confirmed — depends on recipient spam filtering |

**Conclusion: the send path was never broken.** The app and Firebase both did
their jobs. Firebase's default sending domain
(`noreply@<project>.firebaseapp.com`) carries no sending reputation, so Gmail
and Outlook routinely file these messages under Spam or Promotions.

The sender name is now set, so the message arrives from a named sender rather
than an anonymous one. The confirmation screen keeps its original copy, which
already directs the user to their spam folder.

The remaining permanent fix is a custom SMTP sender on a domain with SPF and
DKIM records (Authentication → Templates → SMTP settings). That needs a domain
the project owns, so it is recorded as a limitation rather than implemented.

This one is worth noting in the evaluation because the obvious diagnosis —
"the code doesn't send the email" — was wrong, and only layer-by-layer
isolation showed it.

---

## 5. AI testing

| # | Scenario | Result |
|---|---|---|
| A1 | Daily insight generated from real Firestore data | ✅ Gemini, 5.0–21.6 s observed |
| A2 | Insight quotes app-computed statistics **exactly** | ✅ "19 weighted minutes per day … 34 earlier … 44% lower" matched `CareAnalytics` output verbatim |
| A3 | Insight references real scheduled events | ✅ Cited the 10:30 AM appointment with Dr Anita Perera |
| A4 | Personalisation across pets | ✅ See below |
| A5 | Anomaly detection surfaces in the UI | ✅ "Activity lower than usual · 67% signal" |
| A6 | Anomaly wording avoids diagnosis | ✅ "This is a change in the recorded data only." |
| A7 | **Provider failover under real failure** | ✅ Gemini returned HTTP 503; OpenRouter served the response and the UI labelled it |
| A8 | Insight caching by context fingerprint | ✅ No new model call on re-open; regenerated only when data changed |

### A4 — evidence of personalisation

The same feature, same day, two pets:

> **Bruno** (Labrador, 3 y): "…his recorded activity over the last 3 days
> averages 19 weighted minutes per day, compared with 34 earlier in the period
> (44% lower). As he is a young Labrador who usually loves the park, keep
> monitoring his energy today and consider mentioning this recent drop in
> activity during his routine check-up with Dr Anita Perera tomorrow at
> 10:30 AM."

> **Luna** (British Shorthair, 8 y): "…her exercise is within her usual 9-minute
> average. She still needs her evening meal at 7 PM and her nail trimming is
> overdue by one day… Because she's an 8-year-old British Shorthair, a brief
> gentle play session or a few minutes of stretching before bedtime can help
> reduce stiffness after her long naps."

Different figures, different schedules, different reasoning — and Luna's answer
draws on her stored note ("Stiff after long naps"). This is the clearest
available evidence that recommendations are grounded per-pet rather than
templated.

---

## 6. Performance observations

Measured on the emulator, which is slower than real hardware.

| Metric | Observed |
|---|---|
| Cold start to first frame | ~11 s (debug build, emulator) |
| Gemini insight latency | 5.0 s – 21.6 s |
| OpenRouter fallback latency | 16.1 s |
| Cached insight | Instant — no network call |
| Firestore write → UI update | Sub-second, visually immediate |
| Incremental rebuild | 33 – 84 s |

The AI latency is dominated by Gemini 3.6's internal reasoning plus emulator
networking. Because insights are cached against a context fingerprint, the user
pays that cost only when the underlying data actually changes — opening a screen
never triggers a model call.

---

## 7. Defects found and fixed

24 defects were found and fixed across 10 rounds of testing.

| # | Defect | Severity | Root cause | Status |
|---|---|---|---|---|
| 1 | Logo stretched full-width on Register / Forgot-password | Cosmetic | `CrossAxisAlignment.stretch` expanding a fixed-size container | Fixed |
| 2 | Native launch screen showed the **Flutter** logo | Branding | Android 12+ splash uses the launcher icon | Fixed |
| 3 | Launcher icon was Flutter's default | Branding | Icons never generated | Fixed — 5 densities |
| 4 | All Firebase calls failed | Environment | Emulator DNS broken | Fixed — `-dns-server` |
| 5 | No Profile access from the no-pets state | UX | Empty state had no route to settings | Fixed |
| 6 | **Missing-provider crash on every pushed screen** | Critical | Providers created inside `MaterialApp.home`, below the Navigator | Fixed — moved to `MaterialApp.builder` |
| 7 | **Every card blank inside scrollables** | Critical | `Row(stretch)` forced infinite height in an unbounded list | Fixed — `IntrinsicHeight`, and skip the Row when no accent |
| 8 | Notification permission text ran under its button | Cosmetic | Row without spacing | Fixed |
| 9 | **All AI calls returned HTTP 404** | Critical | `gemini-2.5-flash` withdrawn for new keys; OpenRouter model no longer free | Fixed — `gemini-3.6-flash`, `openai/gpt-oss-20b:free` |
| 10 | Pet switcher chips clipped ("BOTTOM OVERFLOWED BY 2.0 PIXELS") | Cosmetic | Fixed height 2–3 px too small | Fixed |
| 11 | AI answers truncated mid-sentence | Major | Gemini 3 charges reasoning tokens against `maxOutputTokens` (380 of 400 spent thinking) | Fixed — reasoning allowance + `thinkingLevel: low` |
| 12 | **Every tap on the dashboard silently ignored** | Critical | `switchPet()` called `notifyListeners()` from a `ProxyProvider.update` during build → infinite rebuild loop resetting gesture recognisers | Fixed — deferred notification |
| 13 | Seeded age disagreed with computed age | Cosmetic | Seed DOB off by a month | Fixed |
| 14 | Weekly stat tiles invisible | Major | Same `Row(stretch)` class of bug as #7 | Fixed |
| 15 | Location lookup failed on emulator | Major | Fused provider returns null until a fix exists | Fixed — `getLastKnownPosition` fallback + timeout |
| 16 | Markdown syntax (`**`, `*`) leaking into the UI | Major | Model returns markdown; UI renders plain text | Fixed — sanitiser + 13 tests |
| 17 | Ambiguous dates in AI context | Major | Context sent `20/8` with no year | Fixed — ISO dates |
| 18 | "Permission not granted" shown after every restart | Minor | In-memory cache never queried the OS | Fixed — `areNotificationsEnabled()` |
| 19 | Notification icon rendered as a featureless square | Cosmetic | Android flattens the small icon to one tint; a full-colour launcher icon has no silhouette | Fixed — dedicated white paw vector |
| 20 | **Sign-out crashed the app** with a missing-provider error | **Critical** | Swapping `home:` does not pop pushed routes, so ~14 screens were still mounted when the pet-scoped providers were released in the same frame | Fixed — ordered teardown in `_SignedInScope` |
| 21 | Pushed routes survived sign-out | Privacy / UX | Same root cause as 20; back-navigation could reveal the previous account screens | Fixed — stack unwound to the auth gate |
| 22 | `setState` / `context` used after `await` with no `mounted` guard (8 sites) | Latent crash | Awaited pickers and dialogs can outlive their screen once sign-out unwinds the stack | Fixed — guards added; audited by script |
| 23 | Overdue tasks rendered in the healthy domain colour | Cosmetic | Status text always used `type.color`, so "Overdue by 6 days" appeared teal | Fixed — danger colour when overdue |
| 24 | Password reset appeared not to work | Deliverability | Send path was correct; Firebase's default sending domain has no reputation, so Gmail files the mail under Spam. Sender name was also unset | Mitigated — sender name set to "PetMate". A UI hint naming the sender was trialled and reverted at the author's request; the existing "check your spam folder" copy remains |

Defects 6, 7, 9, 11 and 12 were each individually capable of making the
demonstration fail. Numbers 7 and 12 are the most instructive: both produced a
screen that *looked* correct while being non-functional, and neither raised an
exception. They were found only by driving the real UI and checking Firestore
for the writes that should have followed — not by reading code or trusting the
absence of errors in the log.

---

## 8. Not yet tested

Stated explicitly rather than left implied:

- **GPS walk tracking** end-to-end (start → move → save with route).
- **Pet photo upload** — Cloud Storage is not enabled on the project's Spark
  plan, so the code path is unexercised. The UI degrades with a friendly
  message rather than failing.
- **Password-reset inbox receipt** — the send path is now *verified* (logcat
  shows Firebase accepting the request, and the REST API returns 200), but
  arrival in a real inbox still depends on the recipient's spam filtering and
  was not confirmed by reading a mailbox.
- **Medicine / vaccination / grooming creation forms** — read paths verified via
  seeded data; the create forms were not driven manually.
- **Offline behaviour** — Firestore persistence is enabled but airplane-mode
  behaviour was not exercised.
- **Real-device performance** — all figures above are emulator figures.

---

## 9. Evaluation

**What the testing shows.** The security model holds under direct attack from a
real authenticated client: a user cannot read or write another user's data, and
cannot write a malformed document even by bypassing the app. The AI layer is
grounded — the numbers it states are the numbers the app computed, verified by
comparing generated text against `CareAnalytics` output. The failover chain is
not theoretical; it was exercised by a genuine Gemini 503 during testing.

**What the testing changed.** Six critical defects were found only by running
the app, and two of them (#7, #12) were invisible to both the analyzer and the
logs. That is the main methodological finding: static analysis and unit tests
verified the *logic* but said nothing about whether the assembled UI actually
worked. A green test suite and a clean analyzer were compatible with an app
whose dashboard ignored every tap.

**Where it is weakest.** Coverage is concentrated in the domain layer, which is
where correctness matters most for the AI's honesty, but it leaves the widget
layer without automated regression protection — exactly where the worst defects
were found. Widget tests around `AppCard` and a golden test for the dashboard
would have caught #7, #10 and #14 automatically. The items in §8 remain
genuinely unverified.
