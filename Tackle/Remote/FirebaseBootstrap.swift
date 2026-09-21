//
//  FirebaseBootstrap.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

enum FirebaseBootstrap {
    /// Touches no network, so it is safe on a first launch in airplane mode.
    static func configure() {
        FirebaseApp.configure()

        // CRITICAL: Firestore ships with its own offline cache and write queue. We already have
        // Core Data plus an outbox. Two offline systems would fight: a write could succeed into
        // Firestore's cache while our outbox still thinks it is pending, and sync state would
        // start lying. Turn it off.
        let settings = Firestore.firestore().settings
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
    }

    /// Signs in silently. There is no login screen and no per-user data — the anonymous
    /// credential exists only so the security rules can require `request.auth != null`.
    /// Firebase persists the credential, so this only reaches the network once per install.
    static func signIn() async throws {
        if Auth.auth().currentUser != nil { return }
        _ = try await Auth.auth().signInAnonymously()
    }
}
