# Tackle

An offline-first iOS task board. Tasks move through To Do → In Progress → Done, every edit works
without a network, and changes sync to Firebase when connectivity returns.

Built for the *Offline-First Task Board* assignment.

**Full dark mode. Portrait and landscape, iPhone and iPad. 78 tests, 97.7% of the business logic
covered.**

---

## Requirements

| | |
|---|---|
| **Xcode** | 16 or later (tests use Swift Testing) |
| **iOS** | 18.0+  |
| **Dependencies** | Firebase iOS SDK — `FirebaseFirestore` and `FirebaseAuth` only |
| **Configuration** | None. `GoogleService-Info.plist` is committed; anonymous auth signs in silently |

## Running it

```
open Tackle.xcodeproj
```

Resolve packages (first time is slow), pick any iOS 18+ simulator, run. Tests: **⌘U**.

To see the offline behaviour: turn on airplane mode, create and edit tasks, turn it off, watch
them settle.

---

## What it does

- Board with To Do, In Progress and Done sections
- Create, edit, delete, reorder, and drag between sections in any direction
- Full use of the app with no network
- Local persistence across close, relaunch and connectivity loss
- Syncs with Firebase Firestore — outbound push queue, inbound real-time listener
- Per-task indication of whether a change has synced
- **Light and dark appearance**, each with its own palette rather than one set of colours inverted
- **Portrait and landscape, on iPhone and iPad** — the board is a single adaptive list with no
  fixed widths, so it reflows rather than being letterboxed

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

**A status change lands at the top of its new section — unless the user named a position.**
Sending a task to the bottom of a long backlog hides it at the moment the user most needs to see
where it went, so the `Move` swipe action and the editor's status picker both put it on top. That
rule lives in `TaskRepository`, not at its call sites, so they cannot drift apart. A drag is the
exception in the other direction: it *is* a position, so it is honoured exactly, and crossing a
section is the same write as reordering within one. New tasks append to the bottom, because
creating several in a row is building a queue.

**The board is one flat `ForEach` of headings and tasks, moved with `.onMove`.** The obvious
structure — a `Section` per stage — cannot support cross-section drag at all: a `List` treats a
drag as a reorder session owned by the `ForEach` it began in, so a drop into a different section
is never delivered. Neither is the modern alternative; `.draggable`/`.dropDestination` on a row
inside a `List` never receives a drop, which instrumenting every handler confirmed — the lift
fired every time and no drop handler ever did. Flattening puts every row in one session, at the
cost of owning the index arithmetic that maps a flat drop position back onto a stage. The first
heading sits outside the `ForEach` so nothing can be dropped above it.

**A drag is landed locally before the write is acknowledged.** `onMove` returns control expecting
the data to have already changed, but the write is a round trip through Core Data — so the list
reverts to the old arrangement and re-animates when the stream catches up, on every single move.
The view model resolves the same neighbours and the same sort index the repository will, so the
stream's answer agrees with what is already on screen and nothing moves twice.

**Dark mode is a second palette, not the first one inverted.** Every colour is declared as a
light/dark pair resolved through `UITraitCollection`, so the app switches with the system rather
than being tinted at the edges. Inverting a light palette is what produces dark screens with
grey-on-grey secondary text and stage colours that have lost their distinctness, so the dark
values are re-picked against a dark ground and every text colour clears 4.5:1 on both. They live
in one `Theme` enum, which is also what stops a stray `.gray` reaching a view.

**Landscape falls out of the layout rather than being handled.** The board is a single adaptive
`List` with no fixed widths and no hard-coded geometry, so rotating it reflows the rows instead
of letterboxing them, and the same code covers iPad. Nothing in the app reads the orientation.

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

**One shared board, and anonymous auth exists only to close the door.** The brief asks for no
user accounts, so every install works against the same top-level `tasks` collection — which is
also what makes the real-time behaviour visible, since two simulators show the same board. The
silent anonymous sign-in carries no data and appears nowhere in the document path; its only job
is to let the rules demand `request.auth != null` instead of leaving the database world-readable.
The trade-off is explicit: authenticated-only, not per-user isolation.

Race conditions and their mitigations are tabulated in [`ARCHITECTURE.md §7`](ARCHITECTURE.md).

---

## Testing

**Business logic: 97.7% covered. The whole app including every view: 82.4%.**

Swift Testing — 78 tests in ten suites, run with **⌘U**. No UI tests: everything here is logic
that can be wrong without anyone noticing, which is not true of a button that fails to appear.
The views are the whole of the difference between the two figures.

| Suite | What it pins down |
|---|---|
| `SortIndex` | The fractional index maths, including that repeated splits between one pair stay ordered |
| `Reordering` | The off-by-one in `onMove`, which numbers the drop against the list that still contains the row |
| `Dragging across stages` | Translating a flat drop index back into a stage and a pair of neighbours |
| `Status changes` | The top-landing rule, including empty sections, soft-deleted rows and no-op changes |
| `Core Data store` | Outbox coalescing, soft delete, `isSynced`, and the newer-wins merge rule |
| `Sync service` | The push loop, a failed push, an edit arriving mid-push, and two passes at once |
| `Task repository` | New tasks appending, delete meaning soft delete, and what a drag resolves to |
| `Task editor` | What counts as saveable, trimming, and create versus update |
| `Board actions` | Deletion, the Move destinations, and a failed write surfacing as an alert |
| `Status capsule` | The four things the capsule can say, including that synced says nothing |

The store, repository and sync suites run against a real Core Data stack on an in-memory store,
because the outbox rules *are* the behaviour and a fake of them would only test the fake. The
server and the network are fakes, so no Firebase project is involved and no simulator state
carries between runs.

The 97.7% covers the models, the store, the repository, the sync engine and the view models, and
it comes with one caveat worth stating: tests run inside a host app, so launching the app marks
lines executed that nothing asserts. Running a single trivial suite gives that baseline, and the
figure above was taken net of it rather than read straight off the report.

**Three things are still verified by hand.** `FirestoreStore` and `FirebaseBootstrap` are the
Firebase edge, and `NetworkMonitor` wraps `NWPathMonitor`; all three were checked against a real
project — airplane mode, force-quit mid-push, reinstall, and two clients on one board. Counting
them as untested, coverage across all non-UI code is 78%.

---

## Known limitations

- **Sort index precision.** Fractional indexing keeps reorder O(1), but doubles exhaust after
  roughly 50 splits between the same two rows. Renormalisation isn't implemented.
- **Last-write-wins.** With a second device, the earlier edit is silently lost.
- **Soft-deleted documents are never purged** from Firestore.
- **One shared board, and "authenticated" does not mean "trusted".** Every install reads and
  writes the same collection, so the rules can only require `request.auth != null` — they cannot
  isolate one person's data from another's. Because anonymous sign-in is enabled and the API key
  ships in the committed plist, anyone with this repository can mint a credential in a single
  request and then read, overwrite or delete any task, without running the app. The rules stop
  unauthenticated scrapers and nothing more. That is an accepted consequence of a shared board
  with no accounts; a real deployment would need per-user scoping, App Check, or both.
- **The Firebase edge has no automated tests.** `FirestoreStore`, `FirebaseBootstrap` and
  `NetworkMonitor` are verified by hand against a real project. The sync logic above them is
  covered.

---

## What I'd add with more time

1. **Real sign-in**, so each person gets their own board instead of the single shared one, and a
   board survives reinstalling.
2. **Search and filtering** across titles and descriptions.
3. **Priority as a colour**, so P0, P1 and P2 are readable at a glance without opening a task.
4. **Folders**, so tasks can be grouped by project rather than living in one flat board.
5. **Background sync** via `BGTaskScheduler`, so a queued change can drain without the app being
   opened.
6. Tests for the Firebase edge itself — `FirestoreStore`'s mapping and `NetworkMonitor` — which
   need either an emulator or a seam below `RemoteStoreProtocol`.
7. Field-level conflict resolution rather than last-write-wins, and sort-index renormalisation.

---

## Assumptions

- Task order is part of the synced model, not a local-only concern.
- No user accounts were asked for, so there is one shared board and anonymous auth is used purely
  to keep the database from being open to anyone.
- The board is a native vertical list rather than a horizontal Kanban. Tasks move between sections
  by dragging, by swipe, or from the editor; a drag keeps the position it was dropped at, and the
  other two land the task on top.
- `GoogleService-Info.plist` belongs in the repo, since the brief requires the project to build
  without undisclosed configuration. The Firestore rules require an authenticated caller and are
  included in [`FIREBASE.md §5`](FIREBASE.md); their limits are spelled out under Known
  limitations, and the Firebase project behind them is disposable.

---

## Documents

| | |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Layers, models, protocols, sync pass, race conditions |
| [`FIREBASE.md`](FIREBASE.md) | Console setup, data model, security rules, offline behaviour |
| [`SCREENS.md`](SCREENS.md) | UI spec, palette with contrast ratios, every user-facing string |
| [`BUILD-PLAN.md`](BUILD-PLAN.md) | The three build parts |
