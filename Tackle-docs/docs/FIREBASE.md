# Tackle — Firebase Integration

Everything Firebase-specific, in the order you'll do it.

Read [`ARCHITECTURE.md §6–7`](ARCHITECTURE.md) first — this document is the *how*; that one is the
*why*.

---

## 1. Console setup (do this once, before writing code)

1. <https://console.firebase.google.com> → **Add project** → name it `tackle` → you can turn
   Google Analytics off.
2. **Add app → iOS.** Bundle ID must match your Xcode target exactly (e.g.
   `com.utkarsh.Tackle`).
3. Download **`GoogleService-Info.plist`** and drag it into the Xcode project root, target
   membership ticked.
4. **Build → Firestore Database → Create database → Production mode**, pick a region near you.
   If you started in test mode, publish the rules in §5 before going any further.
5. **Build → Authentication → Get started → Sign-in method → Anonymous → Enable.** Skipping this
   fails with `CONFIGURATION_NOT_FOUND`, which the app swallows silently — writes simply queue
   forever.

> **Commit the plist.** The brief requires the project to build with no undisclosed configuration,
> so the reviewer must have it. iOS Firebase config values are client identifiers, not secrets —
> the security boundary is the rules in §5, not the file.

**Package:** Xcode → File → Add Package Dependencies →
`https://github.com/firebase/firebase-ios-sdk` → add **only** `FirebaseFirestore` and
`FirebaseAuth`. Nothing else. It resolves slowly the first time; that's normal.

---

## 2. Bootstrap — and the one setting that matters

Configuration and sign-in are deliberately separate calls, because only one of them needs the
network:

```swift
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

enum FirebaseBootstrap {
    /// Touches no network, so it is safe on a first launch in airplane mode.
    static func configure() {
        FirebaseApp.configure()

        // CRITICAL: Firestore ships with its own offline cache and write queue.
        // We already have Core Data + an outbox. Two offline systems would fight:
        // a write could succeed into Firestore's cache while our outbox still thinks
        // it is pending, and sync state would start lying. Turn it off.
        let settings = Firestore.firestore().settings
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
    }

    static func signIn() async throws {
        if Auth.auth().currentUser != nil { return }
        _ = try await Auth.auth().signInAnonymously()
    }
}
```

Anonymous sign-in is silent — no login screen, no user-visible step. The credential persists in
the keychain, so this reaches the network once per install and never again.

**Retry sign-in on reconnect.** A very first launch in airplane mode has no cached credential, so
`signIn()` throws. Giving up there is a real bug: sync would stay detached for the whole session
and the outbox would sit untouched even after the network came back, until the user force-quit
the app. The caller retries on each connectivity change and only wires up `SyncService` once
sign-in succeeds.

---

## 3. Firestore data model

```
tasks/{taskId}
```

**One shared board.** There are no per-user boards: every install reads and writes the same
top-level `tasks` collection, which is what makes the real-time behaviour demonstrable — two
simulators side by side show the same tasks. The anonymous uid is never part of the path; it
exists only so the rules in §5 can demand an authenticated caller rather than leaving the
database open to the world.

`taskId` is our client-generated `UUID().uuidString`. That is what makes every write idempotent.

| Field | Type | Notes |
|---|---|---|
| `title` | String | |
| `details` | String | |
| `status` | String | `"todo"` / `"inProgress"` / `"done"` |
| `sortIndex` | Double | |
| `createdAt` | Timestamp | |
| `updatedAt` | Timestamp | written by the client, drives last-write-wins |
| `deleted` | Bool | soft delete |

**Why `updatedAt` is client-written, not `FieldValue.serverTimestamp()`:** a server timestamp comes
back `nil` until the write round-trips, which would break offline ordering and the incremental
pull. Client time is good enough for one user and keeps the value available immediately.

**Why soft delete:** the listener can then report removals as ordinary document changes. Without
it we'd have to infer "absent from the remote set means deleted", which is the rule most likely to
eat an unsent local create.

---

## 4. The store

```swift
actor FirestoreStore: RemoteStoreProtocol {
    /// One shared board: every install reads and writes the same collection.
    private nonisolated var collection: CollectionReference {
        Firestore.firestore().collection("tasks")
    }

    /// Create, update and delete are all this one call.
    func push(_ task: TaskItem) async throws {
        try await collection.document(task.id.uuidString).setData([
            "title":      task.title,
            "details":    task.details,
            "status":     task.status.rawValue,
            "sortIndex":  task.sortIndex,
            "createdAt":  Timestamp(date: task.createdAt),
            "updatedAt":  Timestamp(date: task.updatedAt),
            "deleted":    task.isDeleted
        ], merge: true)
    }

    /// Live stream. First value is the full collection, then one per remote change.
    /// This IS the fetch — there is no separate pull and no lastSyncedAt.
    nonisolated func remoteChanges() -> AsyncStream<[TaskItem]> {
        AsyncStream { continuation in
            let registration = collection.addSnapshotListener { snapshot, error in
                guard let snapshot else {
                    // Offline or transient. Stay attached; Firestore reconnects itself.
                    print("listener error:", error?.localizedDescription ?? "unknown")
                    return
                }
                continuation.yield(snapshot.documents.compactMap(TaskItem.init(document:)))
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }
}
```

Decoding is hand-written (`init?(document:)`), not `Codable`. It's about fifteen lines, and a
malformed document returns `nil` and is skipped rather than failing the whole pull.

---

## 5. Security rules

Firestore console → Rules. **Do not ship the default test rules** — a public repo with an open
database gets found by scrapers within days.

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /tasks/{taskId} {
      allow read, write: if request.auth != null;
    }
  }
}
```

Because the board is shared, the rule cannot scope by uid — the boundary it enforces is
"authenticated caller only".

**Be honest about how weak that is.** Anonymous sign-in means anyone can obtain a credential with
one unauthenticated request, and the API key needed to do it ships in the committed plist. In a
public repository that means any reader can read, overwrite or delete every task without ever
launching the app. The rule stops scrapers that don't authenticate; it does not protect the data.
Say exactly that in the README rather than implying stronger isolation than exists, and treat the
Firebase project as disposable.

Verify it rather than trusting the console: an unauthenticated read should be refused.

```sh
curl -s -o /dev/null -w '%{http_code}\n' \
  "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/tasks"
```

`403` means the rules are live. `200` means you are still on test-mode rules, which also expire
on a timer and will silently break sync when they do.

---

## 6. How offline actually behaves

Firestore's own offline support is **off** (§2), so with no network its calls simply throw and the
listener stops delivering. That is the intended design: neither reaches the UI.

| Situation | What happens |
|---|---|
| Edit while offline | Saved to Core Data, id queued in the outbox, row shows the waiting glyph. UI never waits. |
| Sync runs offline | `push` throws, the outbox row stays, the pass ends quietly. Nothing is lost. |
| Connectivity returns | `NetworkMonitor` triggers the push loop; pushes land and rails go solid. The listener reconnects on its own and re-delivers anything it missed. |
| App killed mid-push | The outbox row was never cleared, so it pushes again. The write is idempotent, so no duplicate. |
| Edited during its own push | On success the row clears **only if `updatedAt` is unchanged**; otherwise it stays queued for the next pass. |
| First ever launch offline | No cached credential, so sign-in fails and sync stays detached — but only until connectivity returns, when it retries and attaches (§2). |

---

## 7. Testing without hitting Firestore

`FirestoreStore` is the only type that imports Firebase. Everything above it depends on
`RemoteStoreProtocol`, so tests use `FakeRemoteStore` — an in-memory dictionary that can be told to
throw. No emulator, no network, no credentials in CI.

`FirestoreStore` itself is not unit-tested; it's thin mapping code, verified by running the app.
Say so in the README rather than leaving it unexplained.

---

## 8. Checklist before you call this done

- [ ] `GoogleService-Info.plist` committed, bundle ID matches
- [ ] Only `FirebaseFirestore` and `FirebaseAuth` added
- [ ] Firestore in-memory cache set (persistence off)
- [ ] Anonymous auth enabled in console and signing in at launch
- [ ] Security rules published, not left in test mode
- [ ] Edit a document in the Firestore console — it appears in the running app within a second
- [ ] Airplane mode: create, edit, delete, reorder all work
- [ ] Airplane mode off: everything lands in the console within a few seconds
- [ ] Force-quit mid-sync, relaunch: no duplicates, nothing lost
- [ ] Delete the app, reinstall: tasks come back from Firestore

---

*Tackle Firebase · September 2026*
