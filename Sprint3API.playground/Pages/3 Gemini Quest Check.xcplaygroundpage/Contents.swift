//: # 3 · Gemini quest check (Camera screen)
//: What happens when someone snaps a photo for a quest:
//: 1. read the group's current quest from Firestore (CameraContext)
//: 2. send the photo and the quest to the Gemini API, which answers in JSON
//: 3. decode that JSON into `QuestVerdict`
//: 4. upload the photo to Cloud Storage and save a `GroupPhoto` with the verdict
//:
//: To test your own picture, replace `Resources/quest-photo.jpg` (keep the file name).
//: Run page 1 first.
import Foundation
import PlaygroundSupport

PlaygroundPage.current.needsIndefiniteExecution = true

let groupID = "g_axolotls"
let photographer = "u_michael"
let otherQuest = "Take a photo of something blue"   // a second quest, to compare verdicts
let photoID = "p_demo"

Task { @MainActor in
    do {
        let session = try await AuthenticationSession.signInAnonymously()
        let db = Firestore(session: session)
        let gemini = GeminiClient()

        Console.step(1, "Camera screen: the current quest for \(groupID)")
        let group = try await db.get(GroupRecord.self, "groups/\(groupID)")
        let quests = try await db.list(Quest.self, "groups/\(groupID)/quests")
        let now = Date()
        guard let quest = Quest.current(in: quests, at: now)
                ?? quests.filter({ $0.startsAt <= now }).max(by: { $0.startsAt < $1.startsAt }) else {
            throw DemoError.notReady("No quests found for \(groupID). Run page 1 first.")
        }
        print(CameraContext(group: group, quests: quests, now: now))
        Console.ok("Quest \(quest.id ?? "?"): \"\(quest.prompt)\" (checkable: \(quest.checkable))")

        Console.step(2, "Send the photo + quest to Gemini (\(gemini.model))")
        let jpeg = try QuestPhoto.loadJPEG(named: "quest-photo.jpg")
        Console.info("quest-photo.jpg · \(jpeg.count / 1024) KB")
        let reply = try await gemini.checkQuest(quest.prompt, jpeg: jpeg)
        Console.info("Raw response from the Gemini API:")
        print(reply.rawResponse.prettyPrinted(maxLines: 45))

        Console.step(3, "Gemini's JSON decoded into QuestVerdict")
        dump(reply.value)

        Console.step(4, "Same photo, different quest: \"\(otherQuest)\"")
        let second = try await gemini.checkQuest(otherQuest, jpeg: jpeg)
        Console.info("completed: \(second.value.completed) · confidence: \(second.value.confidence)")
        Console.info("reason: \(second.value.reason)")

        Console.step(5, "Save it the way the app will (GroupPhoto)")
        let storagePath = "groups/\(groupID)/photos/\(photoID).jpg"
        if session.config.hasStorage {
            let object = try await session.upload(jpeg, to: storagePath)
            Console.ok("Uploaded to Cloud Storage: \(object.name) · \(object.size ?? "?") bytes · \(object.contentType ?? "?")")
        } else {
            Console.warn("storageBucket isn't set in Secrets.swift, so the upload is skipped.")
        }
        let photo = GroupPhoto(photoAsset: storagePath, groupId: groupID, photographerId: photographer,
                               questId: quest.id, questPrompt: quest.prompt,
                               questCheck: QuestCheck(reply.value, model: reply.modelVersion ?? gemini.model))
        let photoPath = "groups/\(groupID)/photos/\(photoID)"
        let isNew = try await db.getIfExists(GroupPhoto.self, photoPath) == nil
        try await db.commit(photo.saveWrites(photoId: photoID, isNew: isNew))
        Console.ok("Saved \(photoPath)" + (isNew ? " and added 1 to the group's photo_count" : ""))

        Console.step(6, "Read the photo back from Firestore")
        dump(try await db.get(GroupPhoto.self, photoPath))
    } catch {
        Console.fail(error)
    }
    PlaygroundPage.current.finishExecution()
}
