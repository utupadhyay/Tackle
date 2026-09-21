# Tackle — Build Plan

Three parts. Each ends with something that runs. Don't start the next until the current one works.

**Read first:** [`ARCHITECTURE.md`](ARCHITECTURE.md) · [`SCREENS.md`](SCREENS.md)

**Then the part you are on:** [`PART1.md`](PART1.md) · [`PART2.md`](PART2.md) ·
[`PART3.md`](PART3.md) — each has its own spec, checklist and prompt.
[`FIREBASE.md`](FIREBASE.md) is the Firebase reference used by Part 2.

---

## Ground truth

- **App name:** Tackle. The Xcode project already exists — iOS App template, SwiftUI, Swift
  Testing, Core Data included, with `Tackle`, `TackleTests` and `TackleUITests` targets. Do not
  create a new one, and do not add or remove targets. `PART1.md §0` is the scaffolding step that
  turns the template into the structure in `ARCHITECTURE.md §10`.
- **Stack:** SwiftUI, Core Data, Firebase (Firestore + Auth), iOS 17+, Xcode 16+, Swift Testing.
- **Only dependency:** the Firebase SDK. Nothing else.
- **Core Data is the source of truth.** Firestore is a sync target.
- **Firestore's own offline persistence is OFF.** Our outbox is the only offline queue.

### Do not reintroduce these

Each was considered and cut. Your instincts will want several back.

| Don't | Because |
|---|---|
| Loading screen or skeleton | Core Data answers instantly; the state can't occur |
| Full-screen error when Firestore is unreachable | Hides work the user already has |
| Retry button | Sync retries itself on the next trigger |
| Red or amber for sync state | Waiting isn't broken. Red is for Delete only |
| Tick on synced rows | Silence means synced |
| Stored `isSynced` field | Derived from the outbox; storing it creates a race |
| Operation kinds / payloads / coalescer | Firestore upserts make them unnecessary |
| Coordinator hierarchies | One `Router` + a `Route` enum is the whole abstraction |
| Polling / `lastSyncedAt` | A snapshot listener replaces both |
| Firestore offline persistence | Two offline queues conflict |
| `Task` as a model name | Collides with Swift Concurrency. It's `TaskItem` |
| `isDeleted` as a Core Data attribute | Shadows `NSManagedObject.isDeleted`. It's `deletedFlag` |
| `description` as a field name | Collides with `NSObject`. It's `details` |

---

## Part 1 — UI on local data

**Goal:** a complete, usable app with no Firebase at all. Everything persists in Core Data.

**Full spec: [`PART1.md`](PART1.md).** The summary below is the shape; that file is the detail.

Build:

- **Scaffolding first** (`PART1.md §0`) — strip the template boilerplate, create the groups,
  keep `TackleUITests` untouched, note the bundle ID for Part 2. Commit before any feature code.
- `TaskItem`, `TaskStatus`, `PendingPush`, `SortIndex` (pure, tested)
- The three protocols
- `Tackle.xcdatamodeld` — replace the template `Item` entity with `CDTask` + `CDPendingPush`
- `CoreDataStack` (single writer context), `CoreDataStore`
- `Route` + `Router` (`ARCHITECTURE.md §3`) — the editor is presented through it
- `TaskRepository` — local only; `sync()` is an empty stub
- `Theme` from `SCREENS.md §4` — exact hex values, light and dark
- `BoardView` + `BoardViewModel`, `TaskEditorView` + `TaskEditorViewModel`
- `AppContainer`

Working at the end of Part 1:

- Create, edit, delete, move between sections, reorder — all persisted across relaunch
- Sectioned list with stage-coloured rails
- Floating tinted **+** bottom right; empty state; task editor sheet
- Every row shows as synced (no outbox rows yet — correct, not a stub)

**Stop and run it in the simulator before Part 2.**

---

## Part 2 — Firebase

**Goal:** real sync, correct offline behaviour, no data loss.

**Full spec: [`PART2.md`](PART2.md)** — build order, the `SyncService` in full, verification.

Console setup first (`FIREBASE.md §1`), then:

- `FirebaseBootstrap` — configure, **disable Firestore persistence**, anonymous sign-in
- `FirestoreStore` conforming to `RemoteStoreProtocol` — `push` and `remoteChanges()`
  (an `addSnapshotListener` wrapped in an `AsyncStream`, **not** a polling query)
- Outbox writes: `CoreDataStore.save` now queues a `PendingPush` in the same transaction
- `isSynced` derived from the outbox
- `SyncService` — a push loop with an `isPushing` guard, plus a task consuming
  `remoteChanges()` and merging each snapshot
- `NetworkMonitor` — triggers a pass when connectivity returns
- Status capsule wired to real state; rails go translucent when waiting

The four rules that matter (`ARCHITECTURE.md §7`):

1. One push loop at a time — an explicit flag, not actor isolation
2. Skip merging any task that has an outbox row (this is what makes listener timing irrelevant)
3. Clear an outbox row only if `updatedAt` is unchanged since the push started
4. The listener's echo of our own write is ignored automatically — it fails the `updatedAt >` test

**Verify with the checklist in `FIREBASE.md §8` before Part 3.** Airplane mode is the real test.

---

## Part 3 — Tests and final build

**Goal:** prove the sync layer, then ship.

**Full spec: [`PART3.md`](PART3.md)** — thirteen tests, end-to-end runs, README completion.

Unit tests (Swift Testing, `@Suite(.serialized)` on sync suites):

- `SortIndex.between` — empty, top, bottom, middle
- Merge rule — remote newer wins; remote older ignored; task with an outbox row untouched
- Two concurrent push loops — each task pushed exactly once (`confirmation(expectedCount:)`)
- A listener snapshot arriving mid-push leaves the local edit intact
- Edit during an in-flight push — task still waiting afterwards
- Push failure — outbox row survives, nothing lost
- Repository — create/update/delete write locally and queue exactly one push

End-to-end by hand, on device or simulator:

- Airplane mode → full CRUD → back online → everything lands in the Firestore console
- Edit a document in the console → it appears in the running app within a second
- Force-quit mid-sync → relaunch → no duplicates, nothing lost
- Delete and reinstall the app → tasks return from Firestore

Then finish the README: time spent, test count, and verify the AI-disclosure section.

---

## Prompts

### Part 1

> Read `ARCHITECTURE.md`, `FIREBASE.md`, `SCREENS.md` and `BUILD-PLAN.md` in this folder, in that
> order, before writing anything. Then tell me: which files you found, whether an Xcode project
> exists, whether git is initialised, and anything you think is ambiguous. Wait for my reply.
>
> Then do the scaffolding in `PART1.md §0` — the Xcode project already exists, so clear the
> template boilerplate, create the groups, leave `TackleUITests` alone, and commit. Show me the
> project tree before writing feature code.
>
> Then build **Part 1 only** from `BUILD-PLAN.md`: the full UI on Core Data, no Firebase, no sync
> service, no network monitor. `TaskRepository.sync()` is an empty stub in this pass.
>
> Rules: use the exact protocol signatures from `ARCHITECTURE.md §6` and the Router from §3; use the exact colours from
> `SCREENS.md §4` and the exact strings from `SCREENS.md §8` — write no new user-facing copy; the
> model type is `TaskItem`, never `Task`; the Core Data attribute is `deletedFlag`, never
> `isDeleted`. Honour the "do not reintroduce" table in `BUILD-PLAN.md`.
>
> Stop when it builds and runs in the simulator. Report what works and what fought you. Small
> commits with meaningful messages.

### Part 2

> Part 1 is working. Now build **Part 2** from `BUILD-PLAN.md`, following `FIREBASE.md` exactly.
>
> Non-negotiable: Firestore's offline persistence is **disabled** — our Core Data outbox is the
> only offline queue. Inbound is a **snapshot listener** (`addSnapshotListener` wrapped in an
> `AsyncStream`), not a polling query — there is no `lastSyncedAt`. One push loop at a time,
> enforced by an explicit flag and not by actor isolation alone. Skip merging any task that has an
> outbox row. Clear an outbox row only if the task's `updatedAt` is unchanged since the push began.
>
> `FirestoreStore` is the only file that imports Firebase. Everything above it uses
> `RemoteStoreProtocol`.
>
> Stop when the `FIREBASE.md §8` checklist passes, including the airplane-mode run.

### Part 3

> Parts 1 and 2 are working. Build **Part 3**: the unit tests listed in `BUILD-PLAN.md`, using
> Swift Testing with `@Suite(.serialized)` on the sync suites and a `FakeRemoteStore` — no
> emulator, no network.
>
> Then run the end-to-end checks by hand and report the results, and tell me the final test count
> so I can fill in the README.

---

## Open question

Still unanswered by the assignment author: **is there a specific API they expected?** If not,
Firebase is the answer and this plan stands. It's the only question that could force rework, and
it's contained to `FirestoreStore`.

---

*Tackle Build Plan · September 2026*
