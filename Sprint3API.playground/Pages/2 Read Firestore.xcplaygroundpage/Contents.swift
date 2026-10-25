//: # 2 · Read Firestore → Swift structs → screen data
//: Reads the seeded data back and shows each step:
//: 1. the raw JSON Firestore sends for one document
//: 2. that document decoded into a struct
//: 3. the data each hi-fi screen reads, using the struct names from the
//:    "Data accessed" lines on the Figma data-stream panels
//:
//: We view the app as Anabella, the user on the Figma screens. Run page 1 first.
import Foundation
import PlaygroundSupport

PlaygroundPage.current.needsIndefiniteExecution = true

let me = "u_anabella"
// Phone numbers in Anabella's contacts. The app hashes them on the phone and
// compares hashes, so nobody's number is stored or sent in plain text.
let myContacts = ["+14125550101", "+14125550102", "+14125550103", "+14125550104", "+14125550199"]

Task { @MainActor in
    do {
        let session = try await AuthenticationSession.signInAnonymously()
        let db = Firestore(session: session)
        let now = Date()

        Console.step(1, "Raw JSON from Firestore: groups/g_axolotls")
        print(try await db.rawDocument("groups/g_axolotls").prettyPrinted(maxLines: 60))

        Console.step(2, "The same document decoded into GroupRecord")
        let axolotls = try await db.get(GroupRecord.self, "groups/g_axolotls")
        dump(axolotls)

        Console.step(3, "Load what the screens need")
        let users = Dictionary(uniqueKeysWithValues: try await db.list(UserProfile.self, "users").compactMap { user in
            user.id.map { ($0, user) }
        })
        guard let anabella = users[me] else { throw DemoError.notReady("users/\(me) is missing. Run page 1 first.") }
        let myGroups = try await db.query(GroupRecord.self, collection: "groups", field: "member_ids", .arrayContains, .string(me))
        let invitations = try await db.query(GroupInvitation.self, collection: "group_invitations",
                                             field: "recipient_id", .equal, .string(me))
        let friendships = try await db.list(Friendship.self, "users/\(me)/friends")
        let requestsToMe = try await db.query(FriendRequest.self, collection: "friend_requests",
                                              field: "recipient_id", .equal, .string(me))
        let requestsFromMe = try await db.query(FriendRequest.self, collection: "friend_requests",
                                                field: "sender_id", .equal, .string(me))
        let requests = requestsToMe + requestsFromMe
        var questsByGroup: [String: [Quest]] = [:]
        for group in myGroups where !group.isRevealed(at: now) {
            if let id = group.id { questsByGroup[id] = try await db.list(Quest.self, "groups/\(id)/quests") }
        }
        let code = try await db.get(InviteCode.self, "invite_codes/123456")
        let italy = try await db.get(GroupRecord.self, "groups/g_italy")
        let italyPhotos = try await db.list(GroupPhoto.self, "groups/g_italy/photos")
        let italyQuests = try await db.list(Quest.self, "groups/g_italy/quests")
        let games = try await db.list(GameSession.self, "groups/g_italy/game_sessions")
        Console.ok("\(users.count) profiles · \(myGroups.count) of Anabella's groups · \(friendships.count) friendships · "
                   + "\(requests.count) friend requests · \(invitations.count) group invitation(s) · \(italyPhotos.count) Italy photos")

        Console.step(4, "Screen data (Figma hi-fi, struct names from the data-stream panels)")
        func show(_ screen: any CustomStringConvertible) { print(screen); print() }
        show(HomeData(me: anabella, invitations: invitations, groups: myGroups, questsByGroup: questsByGroup,
                      users: users, now: now))
        show(GroupInvitationLookup(inviteCode: code.id ?? "", groupDetails: try await db.get(GroupRecord.self, "groups/\(code.groupId)"),
                                   userId: me))
        show(GroupOverview(group: axolotls, users: users, now: now))
        show(GroupInvitationData(group: axolotls, myFriendships: friendships, users: users))
        show(CameraContext(group: axolotls, quests: questsByGroup["g_axolotls"] ?? [], now: now))
        if let notification = QuestNotification(group: axolotls, quests: questsByGroup["g_axolotls"] ?? [], now: now) {
            show(notification)
        }
        show(AlbumAvailability(group: italy, now: now))
        show(RevealedAlbum(group: italy, photos: italyPhotos, quests: italyQuests, gameSessions: games, users: users))

        let photosByID = Dictionary(uniqueKeysWithValues: italyPhotos.compactMap { photo in photo.id.map { ($0, photo) } })
        if let lobby = games.first(where: { $0.gameStatus == .lobby }) {
            show(GamePreparationData(group: italy, session: lobby, users: users))
        }
        if let finished = games.first(where: { $0.gameStatus == .finished }), let gameID = finished.id {
            if let round = GuessRoundData(session: finished, round: 0, photos: photosByID, users: users) { show(round) }
            let guesses = try await db.list(PhotoGuess.self, "groups/g_italy/game_sessions/\(gameID)/guesses")
            show(GameLeaderboard(session: finished, guesses: guesses, users: users))

            let photoID = finished.rounds[0].photoId
            let comments = try await db.list(PhotoComment.self, "groups/g_italy/photos/\(photoID)/comments")
            print("COMMENTS · PhotoComment  (groups/g_italy/photos/\(photoID)/comments)")
            for comment in comments.sorted(by: { $0.createdAt < $1.createdAt }) {
                print("  \(comment.authorName): \(comment.text)")
            }
            print()
        }
        show(ArchiveData(myGroups: myGroups, meId: me, now: now))
        show(FriendsListData(friendships: friendships, users: users))
        show(FriendDiscoveryData(meId: me, users: users, friendships: friendships, requests: requests, groups: myGroups,
                                 contactPhoneHashes: Set(myContacts.map(PhoneHash.sha256))))
        show(SettingsOverview(me: anabella))
        print(anabella.accountSettingsText)
        print()
        print(anabella.notificationPreferences.accountPreferencesText)
    } catch {
        Console.fail(error)
    }
    PlaygroundPage.current.finishExecution()
}
