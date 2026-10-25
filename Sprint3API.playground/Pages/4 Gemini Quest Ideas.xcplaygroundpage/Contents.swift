//: # 4 · Gemini quest ideas (Create Group screen)
//: When someone taps "Create Group", the app asks Gemini to write quests that
//: fit the group's mode and description, then saves the GroupRecord, the
//: creator's GroupMembership, the invite code and the quests in one batch.
//:
//: Change the inputs below and run again to get different quests.
import Foundation
import PlaygroundSupport

PlaygroundPage.current.needsIndefiniteExecution = true

// What the person filled in on the Create Group screen
let groupName = "Pittsburgh Weekend"
let groupDescription = "Showing friends around Pittsburgh: inclines, pierogies and the Strip District."
let mode = GroupMode.travel
let eventEndAt = Date().addingTimeInterval(2 * 24 * 3600)   // "When will this event end?"
let questCount = 6
let creator = "u_michael"
let groupID = "g_pittsburgh_demo"

Task { @MainActor in
    do {
        let gemini = GeminiClient()

        Console.step(1, "Ask Gemini (\(gemini.model)) for \(questCount) \(mode.rawValue) quests")
        let reply = try await gemini.questIdeas(name: groupName, description: groupDescription,
                                                mode: mode, count: questCount)
        Console.info("The JSON Gemini wrote (from candidates[0].content.parts[0].text):")
        print(reply.jsonText)
        Console.info("Tokens used: \(reply.usage?.totalTokenCount ?? 0)")

        Console.step(2, "Decoded into QuestIdeas")
        for (index, idea) in reply.value.quests.enumerated() {
            Console.info("\(index + 1). \(idea.prompt)   \(idea.checkable ? "[checked by Gemini]" : "[creative: auto-pass]")")
        }

        Console.step(3, "Create the group in Firestore (GroupRecord + members + invite code + quests)")
        let session = try await AuthenticationSession.signInAnonymously()
        let db = Firestore(session: session)
        let context = GroupCreationContext(currentUser: try await db.get(UserProfile.self, "users/\(creator)"))
        let code: String
        if let existing = try await db.getIfExists(GroupRecord.self, "groups/\(groupID)") {
            code = existing.inviteCode                          // running again: keep the same code
        } else {
            code = try await GroupCreation.uniqueInviteCode(in: db)
        }
        let group = GroupRecord(groupName: groupName, description: groupDescription, mode: mode,
                                creatorId: context.currentUser.id ?? creator, memberIds: [creator],
                                inviteCode: code, eventEndAt: eventEndAt)
        let quests = GroupCreation.scheduleQuests(reply.value.quests, from: Date(), to: eventEndAt)
        let saved = try await db.commit(GroupCreation.writes(for: group, groupId: groupID, quests: quests))
        Console.ok("Saved \(saved) documents: groups/\(groupID), its members/\(creator), invite_codes/\(code), \(quests.count) quests")

        Console.step(4, "Read it back: the new Group Page")
        let created = try await db.get(GroupRecord.self, "groups/\(groupID)")
        print(GroupOverview(group: created, users: [creator: context.currentUser], now: Date()))
        let savedQuests = try await db.list(Quest.self, "groups/\(groupID)/quests").sorted { $0.order < $1.order }
        for quest in savedQuests {
            Console.info("\(quest.id ?? "")  \(JSONCoding.formatISO8601(quest.startsAt))  \(quest.prompt)")
        }
    } catch {
        Console.fail(error)
    }
    PlaygroundPage.current.finishExecution()
}
