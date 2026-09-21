# Tackle

An offline-first iOS task board. Tasks move through To Do → In Progress → Done, every edit works
without a network, and changes sync to Firebase when connectivity returns.

Built for the *Offline-First Task Board* assignment.

---

## Requirements

| | |
|---|---|
| **Xcode** | 16 or later (tests use Swift Testing) |
| **iOS** | 17.0+ |
| **Dependencies** | Firebase iOS SDK — `FirebaseFirestore` and `FirebaseAuth` only |
| **Configuration** | None. `GoogleService-Info.plist` is committed; anonymous auth signs in silently |

## Running it

```
open Tackle.xcodeproj
```

Resolve packages (first time is slow), pick any iOS 17+ simulator, run. Tests: **⌘U**.

To see the offline behaviour: turn on airplane mode, create and edit tasks, turn it off, watch
them settle.

---

## What it does

- Board with To Do, In Progress and Done sections
- Create, edit, delete, move between sections, reorder
- Full use of the app with no network
- Local persistence across close, relaunch and connectivity loss
- Syncs with Firebase Firestore — outbound push queue, inbound real-time listener
- Per-task indication of whether a change has synced

---

## Architecture

```
SwiftUI Views → TaskRepository → ┬→ Core Data (tasks + outbox)  ← source of truth
     ↕                                └→ SyncService ⇄ Firestore
  Router                                   push loop + snapshot listener
```

**Core Data is the source of truth. The UI reads only from it. Firebase never blocks the screen.**

Three layers, three protocols. Full detail in [`ARCHITECTURE.md`](ARCHITECTURE.md), Firebase
specifics in [`FIREBASE.md`](FIREBASE.md).

---

## Technical decisions

**Core Data is authoritative; Firestore is a sync target.** Taking "remain usable when
connectivity is unavailable" literally removes three things most apps ship: no loading state (the
database answers immediately), no error screen when Firestore is unreachable (cached work stays on
screen), and no Retry button (sync retries itself).

**Firestore's own offline persistence is disabled.** It ships with a local cache and write queue.
Combined with our outbox that's two offline systems queuing the same writes — a write can succeed
into Firestore's cache while our outbox still thinks it's pending, and the sync indicator starts
lying. One offline system, and it's ours.

**The outbox is just a list of task IDs.** Firestore writes are upserts of a whole document, so
create, update and delete are the same remote call: push this task's current state, with delete as
a `deleted: true` flag. That removes operation kinds, stored payloads, coalescing rules, replay
ordering and duplicate-create risk in one go. Editing a task five times offline leaves one row.

**Sync state is derived, not stored.** A task is waiting if the outbox references it. Storing the
flag invites a real bug: the engine marks a task syncing, awaits the network, the user edits during
that window, the write succeeds, and the app marks a task synced that carries an unsent edit.
Deriving it makes that unrepresentable.

**Client-generated UUIDs are the Firestore document IDs.** An offline create needs no round-trip
for an id, and a retried push overwrites itself instead of duplicating.

**Soft delete.** Deleted tasks keep a `deleted: true` document. Without it, a pull would have to
infer "absent from the remote set means deleted" — the rule most likely to destroy an unsent local
create.

**Push before pull.** The fetch runs only after the outbox drains, and skips any task with a
pending push. Pulling first lets stale server data overwrite queued local edits.

**Firebase is confined to one file.** `FirestoreStore` is the only type that imports it; everything
above uses `RemoteStoreProtocol`, so tests run against a fake with no emulator.

Race conditions and their mitigations are tabulated in [`ARCHITECTURE.md §7`](ARCHITECTURE.md).

---

## Testing

Swift Testing. Sync suites are `@Suite(.serialized)` because Swift Testing parallelises by default
and these share an in-memory store.

Coverage is targeted at the sync layer, where the design could actually be wrong: sort-index maths,
the merge rule, two concurrent sync passes pushing each task exactly once, an edit arriving during
an in-flight push, and a failed push leaving its outbox row intact.

`FirestoreStore` itself isn't unit-tested — it's thin mapping code, verified by running the app
against a real project.

<!-- FILL IN: total test count -->

---

## Known limitations

- **Sort index precision.** Fractional indexing keeps reorder O(1), but doubles exhaust after
  roughly 50 splits between the same two rows. Renormalisation isn't implemented.
- **Last-write-wins.** With a second device, the earlier edit is silently lost.
- **Soft-deleted documents are never purged** from Firestore.
- **Single anonymous user.** No sign-in UI, no account recovery; reinstalling gets a new uid and
  therefore an empty board.
- **`FirestoreStore` has no automated tests.**

---

## What I'd add with more time

1. Field-level conflict resolution rather than last-write-wins.
2. Sort-index renormalisation.
3. Background sync via `BGTaskScheduler`.
4. Search, filtering, and undo for deletes.
5. Real sign-in so a board survives reinstalling.

---

## Assumptions

- No specific backend was named in the brief, so I chose Firebase Firestore.
- Task order is part of the synced model, not a local-only concern.
- Single user; anonymous auth is enough, no account system implied.
- The board is a native sectioned list; moving between sections is an explicit action rather than a
  cross-column drag.
- `GoogleService-Info.plist` belongs in the repo, since the brief requires the project to build
  without undisclosed configuration. Security comes from the Firestore rules, which are scoped to
  `users/{uid}` and included in [`FIREBASE.md §5`](FIREBASE.md).

---

## Time spent

<!-- FILL IN: approximate hours, split across design / implementation / tests -->

---

## AI tools used

<!-- VERIFY THIS MATCHES YOUR OWN ACCOUNT BEFORE SUBMITTING -->

I used Claude throughout — for analysing the brief, designing the architecture, writing the UI
specification against Apple's Human Interface Guidelines, and producing the implementation.

The design decisions were mine, and several came from rejecting its first proposals. It initially
specified a full-screen error when the remote fetch fails, a loading skeleton, and a per-row Retry
button; I rejected all three as contradicting the offline-first requirement, which is why the app
has none of them. I asked for the create action to sit within thumb reach, which produced the
floating button. I also chose Firebase over the mock backend it proposed, which simplified the sync
design considerably once we recognised that Firestore upserts make the outbox a plain list of IDs.

I have reviewed the architecture and can explain any decision in it.

---

## Documents

| | |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Layers, models, protocols, sync pass, race conditions |
| [`FIREBASE.md`](FIREBASE.md) | Console setup, data model, security rules, offline behaviour |
| [`SCREENS.md`](SCREENS.md) | UI spec, palette with contrast ratios, every user-facing string |
| [`BUILD-PLAN.md`](BUILD-PLAN.md) | The three build parts |
| [`PART1.md`](PART1.md) | Part 1: entities, repository semantics, screens, checklist |
| [`PART2.md`](PART2.md) | Part 2: Firebase wiring, the sync service, verification |
| [`PART3.md`](PART3.md) | Part 3: the test suite and end-to-end runs |
