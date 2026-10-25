//: # 1 · Seed Firestore
//: Writes the sample data in `Resources/seed.json` to your Firestore database:
//: profiles, friendships, friend requests, groups, members, quests, photos, a
//: finished guessing game, invitations and more, based on the hi-fi Figma screens.
//: Struct and field names match the data-stream panels on those screens.
//:
//: Each document is decoded into its struct from `Sources/Models.swift` before
//: it's written, so this page also proves the structs match the data.
//: Running it again resets the sample data and its times.
//:
//: **Before running:** fill in `Sources/Secrets.swift` (README steps 1–4).
import Foundation
import PlaygroundSupport

PlaygroundPage.current.needsIndefiniteExecution = true

Task { @MainActor in
    do {
        Console.step(1, "Sign in with Firebase Auth (anonymous)")
        let session = try await AuthenticationSession.signInAnonymously()
        Console.ok("Signed in as user \(session.userId)")

        Console.step(2, "Load seed.json and check every document against its struct")
        let seed = try SeedFile.load()
        let plan = try Seeder.plan(seed)
        let width = plan.summary.map(\.collection.count).max() ?? 0
        for row in plan.summary {
            let padded = row.collection.padding(toLength: width, withPad: " ", startingAt: 0)
            Console.info("\(padded)  →  \(row.documents) × \(row.model)" + (row.paths > 1 ? "  (in \(row.paths) collections)" : ""))
        }
        for warning in plan.warnings { Console.warn(warning) }
        Console.ok("All \(plan.writes.count) documents decode into their structs")

        Console.step(3, "Write them to Firestore")
        let saved = try await Firestore(session: session).commit(plan.writes)
        Console.ok("Firestore saved \(saved) documents.")
        Console.info("Open the Firebase console → Firestore Database to see them.")
    } catch {
        Console.fail(error)
    }
    PlaygroundPage.current.finishExecution()
}
