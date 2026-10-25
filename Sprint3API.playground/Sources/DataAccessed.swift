import Foundation

// MARK: - Data accessed (READ)
//
// What each hi-fi screen reads: the "Data accessed" lines on the Figma
// data-stream panels, with the same struct names. Each one is built only from
// the decoded Firestore models, so the app can reuse them with data from the
// Firebase SDK. Printing one shows what the screen would display.

extension Int {
    /// 1 member, 2 members, 1 Person, 20 People
    func counted(_ singular: String, _ plural: String? = nil) -> String {
        "\(self) \(self == 1 ? singular : (plural ?? singular + "s"))"
    }
}

public enum TimeText {
    /// "45 min", "1 hour", "16 hours", "3 days"
    public static func until(_ date: Date, from now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "now" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(max(minutes, 1)) min" }
        let hours = Int((seconds / 3600).rounded())
        if hours < 48 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(Int((seconds / 86_400).rounded())) days"
    }

    /// "45 min", "1 hr", "16 hr", "3 days" (notifications)
    public static func short(_ date: Date, from now: Date) -> String {
        until(date, from: now).replacingOccurrences(of: " hours", with: " hr").replacingOccurrences(of: " hour", with: " hr")
    }
}

/// A person as the screens show them: avatar (photo or initial) and name.
public struct MemberSummary: Hashable, Sendable {
    public var userId: String
    public var displayName: String
    public var initials: String
    public var profilePhoto: String?

    public init(userId: String, users: [String: UserProfile]) {
        let profile = users[userId]
        self.userId = userId
        self.displayName = profile?.displayName ?? userId
        self.initials = profile?.initials ?? "?"
        self.profilePhoto = profile?.profilePhoto
    }

    var label: String { "[\(initials)] \(displayName)" }
}

/// Group name, icon and counts, used by Photos Ready and the archive cards.
public struct GroupSummary: Hashable, Sendable {
    public var groupId: String
    public var groupName: String
    public var groupIcon: String?
    public var initials: String
    public var memberCount: Int
    public var photoCount: Int

    public init(_ group: GroupRecord) {
        self.groupId = group.id ?? ""
        self.groupName = group.groupName
        self.groupIcon = group.groupIcon
        self.initials = group.initials
        self.memberCount = group.memberIds.count
        self.photoCount = group.photoCount
    }

    var iconText: String { groupIcon ?? "initials \(initials)" }
}

// MARK: Onboarding · OnboardingContent

public struct OnboardingContent: CustomStringConvertible, Sendable {
    public var introductorySteps: [String]          // introductory_steps (bundled with the app, not in Firebase)

    public init(introductorySteps: [String]) { self.introductorySteps = introductorySteps }

    public static let standard = OnboardingContent(introductorySteps: [
        "Take photos in your group based on given prompts",
        "View all of your photos after your event!",
    ])

    public var description: String {
        (["ONBOARDING · OnboardingContent (bundled)"]
            + introductorySteps.enumerated().map { "  Step \($0.offset + 1): \($0.element)" }).joined(separator: "\n")
    }
}

// MARK: Onboarding 2 / Sign In · AuthenticationResult

public struct AuthenticationResult: CustomStringConvertible, Sendable {
    public var userId: String                       // authentication_result: the Firebase Auth user
    public var provider: String                     // "google.com", "apple.com", "password"; "anonymous" here
    public var userProfile: UserProfile?            // user_profile (Sign In): nil until AccountRegistration is saved
    public var isNewUser: Bool { userProfile == nil }

    public init(userId: String, provider: String, userProfile: UserProfile?) {
        self.userId = userId
        self.provider = provider
        self.userProfile = userProfile
    }

    public var description: String {
        "SIGN IN · AuthenticationResult\n  user \(userId) via \(provider) · "
            + (userProfile.map { "profile: \($0.displayName)" } ?? "new user → Onboarding 2 saves an AccountRegistration")
    }
}

// MARK: Home · HomeData

public struct HomeData: CustomStringConvertible, Sendable {
    public struct InvitationCard: Hashable, Sendable {
        public var invitationId: String
        public var groupId: String
        public var inviterInitials: String
        public var text: String                     // "Steph is inviting you to join Party Animals"
    }

    /// Where the capture button sends photos. Not on the Home panel yet.
    public struct ActiveGroup: Hashable, Sendable {
        public var groupId: String
        public var groupName: String
        public var currentQuestPrompt: String?
        public var questTimeLeft: String?
        public var revealIn: String
    }

    public var displayName: String                          // display_name
    public var profilePhoto: String?                        // profile_photo
    public var initials: String
    public var pendingGroupInvitations: [InvitationCard]    // pending_group_invitations
    public var activeGroups: [ActiveGroup]                  // capture button

    public var greeting: String { "Ready to Snap a Memory, \(displayName)?" }

    public init(me: UserProfile, invitations: [GroupInvitation], groups: [GroupRecord],
                questsByGroup: [String: [Quest]], users: [String: UserProfile], now: Date) {
        displayName = me.displayName
        profilePhoto = me.profilePhoto
        initials = me.initials
        pendingGroupInvitations = invitations
            .filter { $0.recipientId == me.id && $0.inviteStatus == .pending }
            .sorted { $0.createdAt > $1.createdAt }
            .map { invitation in
                InvitationCard(invitationId: invitation.id ?? "", groupId: invitation.groupId,
                               inviterInitials: users[invitation.inviterId]?.initials ?? String(invitation.inviterName.prefix(1)),
                               text: "\(invitation.inviterName) is inviting you to join \(invitation.groupName)")
            }
        activeGroups = groups
            .filter { !$0.isRevealed(at: now) }
            .sorted { $0.eventEndAt < $1.eventEndAt }
            .map { group in
                let quest = Quest.current(in: questsByGroup[group.id ?? ""] ?? [], at: now)
                return ActiveGroup(groupId: group.id ?? "", groupName: group.groupName,
                                   currentQuestPrompt: quest?.prompt,
                                   questTimeLeft: quest.map { TimeText.until($0.endsAt, from: now) },
                                   revealIn: TimeText.until(group.eventEndAt, from: now))
            }
    }

    public var description: String {
        var lines = ["HOME · HomeData", "  \(greeting)   [\(profilePhoto ?? initials)]"]
        for card in pendingGroupInvitations { lines.append("  Invitation: [\(card.inviterInitials)] \(card.text)  →") }
        for group in activeGroups {
            let quest = group.currentQuestPrompt.map { "quest \"\($0)\" (\(group.questTimeLeft ?? "") left)" } ?? "no quest right now"
            lines.append("  Capture button → \(group.groupName): \(quest); photos reveal in \(group.revealIn)")
        }
        lines.append("  Buttons: Create a group · Join a group · View Archive")
        return lines.joined(separator: "\n")
    }
}

// MARK: Create Group · GroupCreationContext

public struct GroupCreationContext: Sendable {
    public var currentUser: UserProfile             // current_user → creator_id and the first member

    public init(currentUser: UserProfile) { self.currentUser = currentUser }
}

// MARK: Join Group · GroupInvitationLookup

public struct GroupInvitationLookup: CustomStringConvertible, Sendable {
    public var inviteCode: String                   // invite_code    the 6 digits typed in
    public var groupDetails: GroupRecord?           // group_details  nil = no group uses this code
    public var alreadyMember: Bool

    public init(inviteCode: String, groupDetails: GroupRecord?, userId: String) {
        self.inviteCode = inviteCode
        self.groupDetails = groupDetails
        self.alreadyMember = groupDetails?.memberIds.contains(userId) ?? false
    }

    public var description: String {
        guard let group = groupDetails else {
            return "JOIN GROUP · GroupInvitationLookup\n  \(inviteCode) → no group uses that code"
        }
        let action = alreadyMember ? "already a member" : "Join Group saves a GroupMembership"
        return "JOIN GROUP · GroupInvitationLookup\n  \(inviteCode) → \(group.groupName) (\(group.memberIds.count.counted("member"))) · \(action)"
    }
}

// MARK: Add Friends · FriendDiscoveryData

public struct FriendDiscoveryData: CustomStringConvertible, Sendable {
    public enum Action: String, Sendable {
        case add = "Add", requested = "Requested", accept = "Accept", friends = "Friends"
    }

    public struct Person: Hashable, Sendable {
        public var userId: String
        public var displayName: String
        public var username: String
        public var initials: String
        public var action: Action                   // the button next to the name
        public var detail: String?                  // "2 groups in common"
    }

    public var userSearchResults: [Person]          // user_search_results  usernames that start with the search text
    public var suggestedPeople: [Person]            // suggested_people     "People You Know": share a group, not friends yet
    public var contactMatches: [Person]             // contact_matches      "From Your Contacts" (with contact access)
    public var incomingRequests: [Person]           // requests waiting for you to accept (needs a spot on the screen)

    public init(meId: String, users: [String: UserProfile], friendships: [Friendship], requests: [FriendRequest],
                groups: [GroupRecord], contactPhoneHashes: Set<String>, searchText: String = "") {
        let friends = Set(friendships.filter { $0.friendshipStatus == .friends }.map(\.friendId))
        let incoming = requests.filter { $0.recipientId == meId && $0.requestStatus == .pending }
        let incomingIds = Set(incoming.map(\.senderId))
        let outgoingIds = Set(requests.filter { $0.senderId == meId && $0.requestStatus == .pending }.map(\.recipientId))

        func person(_ userId: String, detail: String? = nil) -> Person? {
            guard let profile = users[userId] else { return nil }
            let action: Action = friends.contains(userId) ? .friends
                : incomingIds.contains(userId) ? .accept
                : outgoingIds.contains(userId) ? .requested : .add
            return Person(userId: userId, displayName: profile.displayName, username: profile.username,
                          initials: profile.initials, action: action, detail: detail)
        }

        incomingRequests = incoming.sorted { $0.createdAt > $1.createdAt }.compactMap { person($0.senderId) }

        var shared: [String: Int] = [:]
        for group in groups where group.memberIds.contains(meId) {
            for userId in group.memberIds where userId != meId && !friends.contains(userId) && !incomingIds.contains(userId) {
                shared[userId, default: 0] += 1
            }
        }
        suggestedPeople = shared
            .sorted { $0.value != $1.value ? $0.value > $1.value : (users[$0.key]?.displayName ?? "") < (users[$1.key]?.displayName ?? "") }
            .compactMap { person($0.key, detail: "\($0.value.counted("group")) in common") }

        let alreadyShown = friends.union(incomingIds).union(shared.keys).union([meId])
        contactMatches = users.values
            .filter { profile in
                guard let id = profile.id, let hash = profile.phoneHash else { return false }
                return contactPhoneHashes.contains(hash) && !alreadyShown.contains(id)
            }
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap { $0.id.flatMap { person($0) } }

        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        userSearchResults = query.isEmpty ? [] : users.values
            .filter { $0.id != meId && $0.username.hasPrefix(query) }
            .sorted { $0.username < $1.username }
            .compactMap { $0.id.flatMap { person($0) } }
    }

    public var description: String {
        func row(_ people: [Person]) -> String {
            people.map { "[\($0.initials)] \($0.displayName) (\($0.action.rawValue))" }.joined(separator: ", ")
        }
        var lines = ["ADD FRIENDS · FriendDiscoveryData"]
        if !incomingRequests.isEmpty { lines.append("  Friend requests: \(row(incomingRequests))") }
        lines.append("  People You Know: \(row(suggestedPeople))")
        lines.append("  From Your Contacts: \(row(contactMatches))")
        if !userSearchResults.isEmpty { lines.append("  Search results: \(row(userSearchResults))") }
        return lines.joined(separator: "\n")
    }
}

// MARK: Group Page / Group Page - Options · GroupOverview

public struct GroupOverview: CustomStringConvertible, Sendable {
    public var groupDetails: GroupRecord            // group_details
    public var members: [MemberSummary]             // members
    public var photoCount: Int                      // photo_count
    public var eventEndAt: Date                     // event_end_at
    public var revealText: String                   // "Photos will reveal in 16 hours"

    public init(group: GroupRecord, users: [String: UserProfile], now: Date) {
        groupDetails = group
        members = group.memberIds.map { MemberSummary(userId: $0, users: users) }
        photoCount = group.photoCount
        eventEndAt = group.eventEndAt
        revealText = group.isRevealed(at: now)
            ? "Your photos are ready!"
            : "Photos will reveal in \(TimeText.until(group.eventEndAt, from: now))"
    }

    public var description: String {
        """
        GROUP PAGE · GroupOverview
          \(groupDetails.groupName)   icon: \(groupDetails.groupIcon ?? "initials \(groupDetails.initials)")
          \(members.count.counted("member")) · \(photoCount.counted("photo"))
          "\(groupDetails.description)"
          Members: \(members.map(\.label).joined(separator: "  "))
          \(revealText)
        """
    }
}

// MARK: Group Page - Invite · GroupInvitationData

public struct GroupInvitationData: CustomStringConvertible, Sendable {
    public var friendList: [MemberSummary]          // friend_list        your friends who aren't in the group yet
    public var groupInviteCode: String              // group_invite_code  Copy writes only to the clipboard
    public var groupDetails: GroupRecord            // group_details

    public init(group: GroupRecord, myFriendships: [Friendship], users: [String: UserProfile]) {
        groupDetails = group
        groupInviteCode = group.inviteCode
        friendList = myFriendships
            .filter { $0.friendshipStatus == .friends && !group.memberIds.contains($0.friendId) }
            .map { MemberSummary(userId: $0.friendId, users: users) }
            .sorted { $0.displayName < $1.displayName }
    }

    public var description: String {
        """
        GROUP PAGE - INVITE · GroupInvitationData
          Group invite code: \(groupInviteCode.map(String.init).joined(separator: " "))   [Copy]
          Invite friends (\(friendList.count)): \(friendList.prefix(8).map(\.displayName).joined(separator: ", "))\(friendList.count > 8 ? ", …" : "")
        """
    }
}

// MARK: Camera · CameraContext

public struct CameraContext: CustomStringConvertible, Sendable {
    public var groupId: String                      // group_id
    public var groupName: String
    public var currentQuestPrompt: String?          // current_quest_prompt  nil = no quest right now
    public var questTimeLeft: String?
    // camera_preview is the live camera feed from AVFoundation on the phone, not data from Firebase.

    public init(group: GroupRecord, quests: [Quest], now: Date) {
        groupId = group.id ?? ""
        groupName = group.groupName
        let quest = Quest.current(in: quests, at: now)
        currentQuestPrompt = quest?.prompt
        questTimeLeft = quest.map { TimeText.until($0.endsAt, from: now) }
    }

    public var description: String {
        let prompt = currentQuestPrompt.map { "\"\($0)\"" } ?? "No quest right now. Snap anything!"
        return "CAMERA · CameraContext\n  \(groupName): \(prompt)\(questTimeLeft.map { "   (\($0) remaining)" } ?? "")"
    }
}

// MARK: Photos Ready · AlbumAvailability

public struct AlbumAvailability: CustomStringConvertible, Sendable {
    public var groupSummary: GroupSummary           // group_summary
    public var albumAvailability: Bool              // album_availability  true once event_end_at has passed
    public var photoCount: Int                      // photo_count

    public init(group: GroupRecord, now: Date) {
        groupSummary = GroupSummary(group)
        albumAvailability = group.isRevealed(at: now)
        photoCount = group.photoCount
    }

    public var description: String {
        let headline = albumAvailability ? "Your photos are ready!" : "Photos are still locked"
        let buttons = albumAvailability ? "   [Reveal Album] [Guess the Photo Takers]" : ""
        return """
        PHOTOS READY · AlbumAvailability
          \(groupSummary.groupName) · \(photoCount.counted("photo"))
          \(headline)\(buttons)
        """
    }
}

// MARK: Album Revealed · RevealedAlbum

public struct RevealedAlbum: CustomStringConvertible, Sendable {
    public struct AlbumPhoto: Hashable, Sendable {
        public var photoId: String
        public var photoAsset: String
        public var photographerName: String?        // nil until a guessing game has finished
        public var questBadge: String?              // "✓ Take a photo of a statue"
    }

    public var groupDetails: GroupRecord            // group_details
    public var members: [MemberSummary]             // members
    public var albumPhotos: [AlbumPhoto]            // album_photos
    public var questsCompleted: Int

    public init(group: GroupRecord, photos: [GroupPhoto], quests: [Quest], gameSessions: [GameSession],
                users: [String: UserProfile]) {
        groupDetails = group
        members = group.memberIds.map { MemberSummary(userId: $0, users: users) }
        let gamePlayed = gameSessions.contains { $0.gameStatus == .finished }
        let checkable = Dictionary(uniqueKeysWithValues: quests.compactMap { quest in quest.id.map { ($0, quest.checkable) } })
        var completed = 0
        albumPhotos = photos.sorted { $0.capturedAt < $1.capturedAt }.map { photo in
            var badge: String?
            if let questId = photo.questId, let prompt = photo.questPrompt {
                // Creative quests pass automatically; checkable ones use Gemini's verdict.
                let done = checkable[questId] == false || photo.questCheck?.completed == true
                if done { completed += 1 }
                badge = "\(done ? "✓" : "✗") \(prompt)"
            }
            return AlbumPhoto(photoId: photo.id ?? "", photoAsset: photo.photoAsset,
                              photographerName: gamePlayed ? (users[photo.photographerId]?.displayName ?? photo.photographerId) : nil,
                              questBadge: badge)
        }
        questsCompleted = completed
    }

    public var description: String {
        var lines = ["ALBUM REVEALED · RevealedAlbum",
                     "  \(groupDetails.groupName) · \(members.count.counted("member")) · \(albumPhotos.count.counted("photo")) · \(questsCompleted.counted("quest")) completed",
                     "  Members: \(members.map(\.label).joined(separator: "  "))",
                     "  Menu: Edit Group | Invite People | Guess the Photo Takers | Save All Photos | Leave Group"]
        for photo in albumPhotos.prefix(6) {
            let taker = photo.photographerName.map { "by \($0)" } ?? "photographer hidden"
            lines.append("  ▢ \(photo.photoAsset)  \(taker)\(photo.questBadge.map { "  \($0)" } ?? "")")
        }
        if albumPhotos.count > 6 { lines.append("  … \(albumPhotos.count - 6) more photos") }
        return lines.joined(separator: "\n")
    }
}

// MARK: Album Revealed - Invite · AlbumInvitationData

public struct AlbumInvitationData: Sendable {
    public var friendList: [MemberSummary]          // friend_list
    public var groupInviteCode: String              // group_invite_code
    public var albumPhotos: [RevealedAlbum.AlbumPhoto]  // album_photos (behind the popup)

    public init(album: RevealedAlbum, myFriendships: [Friendship], users: [String: UserProfile]) {
        let invite = GroupInvitationData(group: album.groupDetails, myFriendships: myFriendships, users: users)
        friendList = invite.friendList
        groupInviteCode = invite.groupInviteCode
        albumPhotos = album.albumPhotos
    }
}

// MARK: Settings · SettingsOverview

public struct SettingsOverview: CustomStringConvertible, Sendable {
    public var profilePhoto: String?                // profile_photo
    public var initials: String
    public var accountSummary: String               // account_summary  "Anabella · @anabellaaaaaa"

    public init(me: UserProfile) {
        profilePhoto = me.profilePhoto
        initials = me.initials
        accountSummary = "\(me.displayName) · @\(me.username)"
    }

    public var description: String {
        """
        SETTINGS · SettingsOverview
          [\(profilePhoto ?? initials)] \(accountSummary)
          My Account · Friends List · Browse Archive · Notification Preferences · Delete Account
        """
    }
}

// MARK: Account Settings · UserProfile

extension UserProfile {
    /// Account Settings shows the profile; the password is never read, only reset.
    public var accountSettingsText: String {
        """
        ACCOUNT SETTINGS · UserProfile
          [\(profilePhoto ?? initials)] Email: \(email ?? "(from Firebase Auth)") · Display Name: \(displayName) · Username: \(username) · Password: ********
        """
    }
}

// MARK: Friends List · FriendsListData

public struct FriendsListData: CustomStringConvertible, Sendable {
    public var friends: [MemberSummary]             // friends       friendship_status == friends
    public var searchQuery: String                  // search_query
    public var visibleFriends: [MemberSummary] {
        let query = searchQuery.lowercased()
        return query.isEmpty ? friends : friends.filter { $0.displayName.lowercased().contains(query) }
    }

    public init(friendships: [Friendship], users: [String: UserProfile], searchQuery: String = "") {
        friends = friendships
            .filter { $0.friendshipStatus == .friends }
            .map { MemberSummary(userId: $0.friendId, users: users) }
            .sorted { $0.displayName < $1.displayName }
        self.searchQuery = searchQuery
    }

    public var countText: String { friends.count.counted("Person", "People") }

    public var description: String {
        """
        FRIENDS LIST · FriendsListData
          \(countText)\(searchQuery.isEmpty ? "" : " · search \"\(searchQuery)\"")
          \(visibleFriends.map { "\($0.displayName) ✕" }.joined(separator: ", "))
        """
    }
}

// MARK: Archive · ArchiveData

public struct ArchiveData: CustomStringConvertible, Sendable {
    public struct ArchiveCard: Hashable, Sendable {
        public var groupId: String
        public var eventTitle: String               // event_titles
        public var photoCount: Int                  // photo_counts
        public var memberCount: Int                 // member_counts
        public var coverPhoto: String?
        public var trashDeletesForEveryone: Bool    // you created it: trash deletes it; otherwise you leave it

        public var photosText: String { photoCount.counted("Photo") }                    // "126 Photos"
        public var friendsText: String { max(memberCount - 1, 0).counted("Friend") }     // "10 Friends"
    }

    public var anniversaryEvents: [ArchiveCard]     // anniversary_events  ended one year ago today
    public var archivedEvents: [ArchiveCard]        // archived_events     the other past events, oldest first

    public init(myGroups: [GroupRecord], meId: String, now: Date, calendar: Calendar = .current) {
        let past = myGroups.filter { $0.isRevealed(at: now) }.sorted { $0.eventEndAt < $1.eventEndAt }
        func card(_ group: GroupRecord) -> ArchiveCard {
            ArchiveCard(groupId: group.id ?? "", eventTitle: group.groupName, photoCount: group.photoCount,
                        memberCount: group.memberIds.count, coverPhoto: group.coverPhoto,
                        trashDeletesForEveryone: group.creatorId == meId)
        }
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let isAnniversary = { (group: GroupRecord) in calendar.isDate(group.eventEndAt, inSameDayAs: oneYearAgo) }
        anniversaryEvents = past.filter(isAnniversary).map(card)
        archivedEvents = past.filter { !isAnniversary($0) }.map(card)
    }

    public var description: String {
        var lines = ["ARCHIVE · ArchiveData"]
        for card in anniversaryEvents { lines.append("  1 year ago today: \(card.eventTitle) · \(card.photosText) · \(card.friendsText)  →") }
        for card in archivedEvents { lines.append("  \(card.eventTitle) · \(card.photosText) · \(card.friendsText)  →") }
        return lines.joined(separator: "\n")
    }
}

// MARK: Account Preferences · NotificationPreferences

extension NotificationPreferences {
    public var toggles: [(label: String, isOn: Bool)] {
        [("Quests", questNotificationsEnabled),
         ("New Group Invite", groupInviteNotificationsEnabled),
         ("Photos Available", photosAvailableNotificationsEnabled)]
    }

    public var accountPreferencesText: String {
        "ACCOUNT PREFERENCES · NotificationPreferences\n  "
            + toggles.map { "\($0.label) \($0.isOn ? "on" : "off")" }.joined(separator: " · ")
    }
}

// MARK: Game Prep · GamePreparationData

public struct GamePreparationData: CustomStringConvertible, Sendable {
    public struct Participant: Hashable, Sendable {
        public var userId: String
        public var displayName: String
        public var initials: String
        public var isReady: Bool                    // check mark
    }

    public var groupName: String                    // group_name
    public var gameParticipants: [Participant]      // game_participants

    public init(group: GroupRecord, session: GameSession, users: [String: UserProfile]) {
        groupName = group.groupName
        gameParticipants = session.participantIds.map { userId in
            Participant(userId: userId, displayName: users[userId]?.displayName ?? userId,
                        initials: users[userId]?.initials ?? "?", isReady: session.readyIds.contains(userId))
        }
    }

    /// "Ready to Guess The Axolotls’ Photos?"
    public var title: String {
        let base = groupName.trimmingCharacters(in: CharacterSet.letters.inverted)
        return "Ready to Guess \(base)\(base.hasSuffix("s") ? "’" : "’s") Photos?"
    }

    public var description: String {
        let ready = gameParticipants.filter(\.isReady).count
        return """
        GAME PREP · GamePreparationData
          \(title)
          \(gameParticipants.map { "[\($0.initials)] \($0.displayName)\($0.isReady ? " ✓" : "")" }.joined(separator: "  "))
          \(ready) of \(gameParticipants.count) ready   [Start]
        """
    }
}

// MARK: Game · GuessRoundData

public struct GuessRoundData: CustomStringConvertible, Sendable {
    public var round: Int
    public var roundCount: Int
    public var roundPhoto: String                   // round_photo             photo_asset of this round's photo
    public var candidateParticipants: [MemberSummary]  // candidate_participants

    public init?(session: GameSession, round: Int, photos: [String: GroupPhoto], users: [String: UserProfile]) {
        guard session.rounds.indices.contains(round) else { return nil }
        let current = session.rounds[round]
        self.round = round
        roundCount = session.rounds.count
        roundPhoto = photos[current.photoId]?.photoAsset ?? current.photoId
        candidateParticipants = current.candidateIds.map { MemberSummary(userId: $0, users: users) }
    }

    public var description: String {
        """
        GAME · GuessRoundData (round \(round + 1) of \(roundCount))
          Who took this photo?  ▢ \(roundPhoto)
          \(candidateParticipants.map(\.label).joined(separator: "  "))
        """
    }
}

// MARK: Leaderboard · GameLeaderboard

public struct GameLeaderboard: CustomStringConvertible, Sendable {
    public struct Ranking: Hashable, Sendable {
        public var rank: Int
        public var userId: String
        public var playerName: String               // player_names
        public var playerAvatar: String             // player_avatars  profile_photo, or the initial
        public var correctGuesses: Int
        public var rounds: Int
    }

    public var rankings: [Ranking]                  // rankings
    public var title: String { "Winner, Winner!" }

    public init(session: GameSession, guesses: [PhotoGuess], users: [String: UserProfile]) {
        let byPlayer = Dictionary(grouping: guesses, by: \.userId)
        let scored = session.participantIds.map { userId -> (userId: String, correct: Int, last: Date) in
            let mine = byPlayer[userId] ?? []
            return (userId, mine.filter(\.isCorrect).count, mine.map(\.answeredAt).max() ?? .distantFuture)
        }
        .sorted { $0.correct != $1.correct ? $0.correct > $1.correct : $0.last < $1.last }   // ties: faster wins
        rankings = scored.enumerated().map { index, entry in
            Ranking(rank: index + 1, userId: entry.userId, playerName: users[entry.userId]?.displayName ?? entry.userId,
                    playerAvatar: users[entry.userId]?.profilePhoto ?? users[entry.userId]?.initials ?? "?",
                    correctGuesses: entry.correct, rounds: session.rounds.count)
        }
    }

    public var description: String {
        var lines = ["LEADERBOARD · GameLeaderboard", "  \(title)"]
        for row in rankings {
            lines.append("  #\(row.rank)  [\(row.playerAvatar)] \(row.playerName)  \(row.correctGuesses)/\(row.rounds) correct")
        }
        lines.append("  [Play Again]")
        return lines.joined(separator: "\n")
    }
}

// MARK: Notification · QuestNotification

public struct QuestNotification: CustomStringConvertible, Sendable {
    public var groupName: String                    // group_name
    public var questPrompt: String                  // quest_prompt
    public var questDeadline: Date                  // quest_deadline  the quest's ends_at
    public var timeRemaining: String                // "1 hr remaining!"

    /// The notification for the quest running now, or nil when there isn't one.
    public init?(group: GroupRecord, quests: [Quest], now: Date) {
        guard let quest = Quest.current(in: quests, at: now) else { return nil }
        groupName = group.groupName
        questPrompt = quest.prompt
        questDeadline = quest.endsAt
        timeRemaining = "\(TimeText.short(quest.endsAt, from: now)) remaining!"
    }

    public var description: String {
        "NOTIFICATION · QuestNotification\n  \(groupName)\n  Current Quest: \(questPrompt)!   \(timeRemaining)"
    }
}
