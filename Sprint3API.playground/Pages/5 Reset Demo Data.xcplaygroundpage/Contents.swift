//: # 5 · Reset demo data (run before recording)
//: Deletes what the demo pages wrote, so a recording can start from an empty
//: database and show the data arrive: the 539 sample documents from page 1,
//: the photos page 3 added to The Axolotls, and the group page 4 created.
//: Nothing else in the project is touched. Run page 1 afterwards to load the
//: sample data again.
import Foundation
import PlaygroundSupport

PlaygroundPage.current.needsIndefiniteExecution = true

let page4Group = "g_pittsburgh_demo"

Task { @MainActor in
    do {
        let session = try await AuthenticationSession.signInAnonymously()
        let db = Firestore(session: session)

        Console.step(1, "Find what the demo pages wrote")
        let seeded = try Seeder.plan(try SeedFile.load()).writes.map(\.path)
        let seededSet = Set(seeded)
        var extra: [String] = []
        // page 3: photos in The Axolotls that aren't sample data (p_demo, ...)
        for photo in try await db.list(GroupPhoto.self, "groups/g_axolotls/photos") {
            let path = "groups/g_axolotls/photos/\(photo.id ?? "")"
            if !seededSet.contains(path) { extra.append(path) }
        }
        // page 4: the new group, its members, quests and invite code
        if let group = try await db.getIfExists(GroupRecord.self, "groups/\(page4Group)") {
            extra.append("invite_codes/\(group.inviteCode)")
        }
        for member in try await db.list(GroupMembership.self, "groups/\(page4Group)/members") {
            extra.append("groups/\(page4Group)/members/\(member.id ?? "")")
        }
        for quest in try await db.list(Quest.self, "groups/\(page4Group)/quests") {
            extra.append("groups/\(page4Group)/quests/\(quest.id ?? "")")
        }
        extra.append("groups/\(page4Group)")
        Console.info("\(seeded.count) sample documents + \(extra.count) written by pages 3 and 4")

        Console.step(2, "Delete them")
        let deleted = try await db.commit((seeded + extra).map { FirestoreWrite.delete(path: $0) })
        Console.ok("Deleted \(deleted) documents. Firestore is back to empty for the demo.")
        Console.info("Run page 1 to load the sample data again.")
    } catch {
        Console.fail(error)
    }
    PlaygroundPage.current.finishExecution()
}
