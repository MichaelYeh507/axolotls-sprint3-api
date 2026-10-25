import Foundation

// MARK: - Firestore documents
//
// One struct per Firestore collection. Struct and field names match the
// "Data Streams" panels on the hi-fi Figma screens: Firestore stores the
// snake_case names from the panels (display_name, event_end_at, ...), and
// CodingKeys map them to camelCase Swift properties.
//
// The same file works in the playground (data comes from the Firestore REST
// API) and in the iOS app (data comes from the Firebase SDK), so the app team
// can copy it into the Xcode project as is.
//
// Every model has an optional `id` that holds the document ID. The ID is not a
// field inside the document, so it's left out of CodingKeys:
//   • App:        var group = try snapshot.data(as: GroupRecord.self); group.id = snapshot.documentID
//   • Playground: Firestore.get / list fill it in from the REST document name.
//
// Collection tree:
//   users/{userId}                                UserProfile
//       friends/{friendId}                        Friendship
//   usernames/{username}                          UsernameClaim
//   friend_requests/{senderId}_{recipientId}      FriendRequest
//   groups/{groupId}                              GroupRecord
//       members/{userId}                          GroupMembership
//       quests/{questId}                          Quest
//       photos/{photoId}                          GroupPhoto
//           comments/{commentId}                  PhotoComment
//       game_sessions/{gameSessionId}             GameSession
//           guesses/{round}_{userId}              PhotoGuess
//   group_invitations/{groupId}_{recipientId}     GroupInvitation
//   invite_codes/{code}                           InviteCode
//   quest_bank/{questId}                          BankQuest

public protocol FirestoreDocument: Codable, Sendable {
    /// The document ID. Not stored as a field.
    var id: String? { get set }
}

// MARK: users/{userId}

/// A person's profile: avatars, Home greeting, Account Settings, friend search.
///
/// `email` is on the Account Settings panel but isn't stored in Firestore.
/// Every signed-in user can read profiles (friend search needs that), so the
/// email stays in Firebase Auth and the app fills it in for the signed-in user:
/// `profile.email = Auth.auth().currentUser?.email`.
public struct UserProfile: FirestoreDocument, Identifiable, Hashable {
    public var id: String?
    public var displayName: String                              // display_name  "Anabella"
    public var username: String                                 // username      "anabellaaaaaa" (unique, lowercase)
    public var profilePhoto: String?                            // profile_photo Storage path; nil = show initials
    public var phoneHash: String?                               // phone_hash    SHA-256 of the E.164 number (contact matches)
    public var notificationPreferences: NotificationPreferences // notification_preferences
    public var createdAt: Date                                  // created_at
    public var email: String?                                   // from Firebase Auth, not Firestore

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name", username, profilePhoto = "profile_photo", phoneHash = "phone_hash",
             notificationPreferences = "notification_preferences", createdAt = "created_at"
    }

    public init(id: String? = nil, displayName: String, username: String, profilePhoto: String? = nil,
                phoneHash: String? = nil, notificationPreferences: NotificationPreferences = NotificationPreferences(),
                createdAt: Date = Date(), email: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.profilePhoto = profilePhoto
        self.phoneHash = phoneHash
        self.notificationPreferences = notificationPreferences
        self.createdAt = createdAt
        self.email = email
    }

    /// Single-letter avatar used across the hi-fi screens ("A", "S", ...).
    public var initials: String { String(displayName.prefix(1)).uppercased() }
}

/// Account Preferences → Notifications toggles (Quests, New Group Invite, Photos Available).
/// Stored as a map inside users/{userId}.
public struct NotificationPreferences: Codable, Hashable, Sendable {
    public var questNotificationsEnabled: Bool             // quest_notifications_enabled
    public var groupInviteNotificationsEnabled: Bool       // group_invite_notifications_enabled
    public var photosAvailableNotificationsEnabled: Bool   // photos_available_notifications_enabled

    enum CodingKeys: String, CodingKey {
        case questNotificationsEnabled = "quest_notifications_enabled"
        case groupInviteNotificationsEnabled = "group_invite_notifications_enabled"
        case photosAvailableNotificationsEnabled = "photos_available_notifications_enabled"
    }

    public init(questNotificationsEnabled: Bool = true, groupInviteNotificationsEnabled: Bool = true,
                photosAvailableNotificationsEnabled: Bool = true) {
        self.questNotificationsEnabled = questNotificationsEnabled
        self.groupInviteNotificationsEnabled = groupInviteNotificationsEnabled
        self.photosAvailableNotificationsEnabled = photosAvailableNotificationsEnabled
    }
}

// MARK: users/{userId}/friends/{friendId}

public enum FriendshipStatus: String, Codable, Sendable {
    case friends
    case removed    // Friends List → remove friend
}

/// One side of a friendship. Accepting a friend request writes both sides,
/// users/{a}/friends/{b} and users/{b}/friends/{a}, so each person can list
/// their own friends without a query.
public struct Friendship: FirestoreDocument, Identifiable, Hashable {
    public var id: String?                          // the friend's user ID
    public var userId: String                       // user_id
    public var friendId: String                     // friend_id
    public var friendshipStatus: FriendshipStatus   // friendship_status
    public var createdAt: Date                      // created_at  (when the request was accepted)

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", friendId = "friend_id", friendshipStatus = "friendship_status", createdAt = "created_at"
    }

    public init(id: String? = nil, userId: String, friendId: String, friendshipStatus: FriendshipStatus = .friends,
                createdAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.friendId = friendId
        self.friendshipStatus = friendshipStatus
        self.createdAt = createdAt
    }
}

// MARK: usernames/{username}

/// Claims a username so no two people can pick the same one. The document ID
/// is the lowercase username; written in the same batch as the profile.
public struct UsernameClaim: FirestoreDocument, Identifiable, Hashable {
    public var id: String?                          // the username
    public var userId: String                       // user_id

    enum CodingKeys: String, CodingKey { case userId = "user_id" }

    public init(id: String? = nil, userId: String) {
        self.id = id
        self.userId = userId
    }
}

// MARK: friend_requests/{senderId}_{recipientId}

public enum RequestStatus: String, Codable, Sendable {
    case pending, accepted, declined
}

/// Add Friends → add_friend_button. The person asked accepts or declines it;
/// accepting creates the two Friendship documents. The ID "{sender}_{recipient}"
/// stops the same request from being sent twice.
public struct FriendRequest: FirestoreDocument, Identifiable, Hashable {
    public var id: String?
    public var senderId: String                     // sender_id
    public var recipientId: String                  // recipient_id
    public var requestStatus: RequestStatus         // request_status
    public var createdAt: Date                      // created_at
    public var respondedAt: Date?                   // responded_at

    enum CodingKeys: String, CodingKey {
        case senderId = "sender_id", recipientId = "recipient_id", requestStatus = "request_status",
             createdAt = "created_at", respondedAt = "responded_at"
    }

    public init(id: String? = nil, senderId: String, recipientId: String, requestStatus: RequestStatus = .pending,
                createdAt: Date = Date(), respondedAt: Date? = nil) {
        self.id = id ?? FriendRequest.documentID(from: senderId, to: recipientId)
        self.senderId = senderId
        self.recipientId = recipientId
        self.requestStatus = requestStatus
        self.createdAt = createdAt
        self.respondedAt = respondedAt
    }

    public static func documentID(from senderId: String, to recipientId: String) -> String {
        "\(senderId)_\(recipientId)"
    }
}

// MARK: groups/{groupId}

public enum GroupMode: String, Codable, Sendable, CaseIterable {
    case party, travel
}

/// A group made for one event ("The Axolotls"). Create Group writes it; Edit
/// Group changes it with a GroupUpdate.
public struct GroupRecord: FirestoreDocument, Identifiable, Hashable {
    public var id: String?
    public var groupName: String            // group_name     "The Axolotls"
    public var description: String          // description    "The best group of people ever."
    public var mode: GroupMode              // mode           Travel / Party
    public var groupIcon: String?           // group_icon     Storage path; nil = initials
    public var creatorId: String            // creator_id     only the creator can delete the group
    public var memberIds: [String]          // member_ids     active members, kept in sync with members/
    public var inviteCode: String           // invite_code    6 digits, shown in the invite popup
    public var createdAt: Date              // created_at
    public var eventEndAt: Date             // event_end_at   "When will this event end?" = when photos reveal
    public var photoCount: Int              // photo_count    "30 photos"; +1 on every upload
    public var coverPhoto: String?          // cover_photo    Archive card background, set after the reveal

    enum CodingKeys: String, CodingKey {
        case groupName = "group_name", description, mode, groupIcon = "group_icon", creatorId = "creator_id",
             memberIds = "member_ids", inviteCode = "invite_code", createdAt = "created_at",
             eventEndAt = "event_end_at", photoCount = "photo_count", coverPhoto = "cover_photo"
    }

    public init(id: String? = nil, groupName: String, description: String, mode: GroupMode, groupIcon: String? = nil,
                creatorId: String, memberIds: [String], inviteCode: String, createdAt: Date = Date(),
                eventEndAt: Date, photoCount: Int = 0, coverPhoto: String? = nil) {
        self.id = id
        self.groupName = groupName
        self.description = description
        self.mode = mode
        self.groupIcon = groupIcon
        self.creatorId = creatorId
        self.memberIds = memberIds
        self.inviteCode = inviteCode
        self.createdAt = createdAt
        self.eventEndAt = eventEndAt
        self.photoCount = photoCount
        self.coverPhoto = coverPhoto
    }

    /// Photos stay locked until the event ends.
    public func isRevealed(at now: Date = Date()) -> Bool { now >= eventEndAt }
    public var initials: String { String(groupName.drop(while: { !$0.isLetter }).prefix(1)).uppercased() }
}

// MARK: groups/{groupId}/members/{userId}

public enum MembershipStatus: String, Codable, Sendable {
    case active
    case left       // Album Revealed - Options → leave_group_button
}

/// Join Group writes one when the 6-digit code checks out. Leaving the group
/// sets membership_status to "left" and removes the person from member_ids.
public struct GroupMembership: FirestoreDocument, Identifiable, Hashable {
    public var id: String?                          // the member's user ID
    public var groupId: String                      // group_id
    public var userId: String                       // user_id
    public var membershipStatus: MembershipStatus   // membership_status
    public var joinedAt: Date                       // joined_at
    public var leftAt: Date?                        // left_at

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id", userId = "user_id", membershipStatus = "membership_status",
             joinedAt = "joined_at", leftAt = "left_at"
    }

    public init(id: String? = nil, groupId: String, userId: String, membershipStatus: MembershipStatus = .active,
                joinedAt: Date = Date(), leftAt: Date? = nil) {
        self.id = id ?? userId
        self.groupId = groupId
        self.userId = userId
        self.membershipStatus = membershipStatus
        self.joinedAt = joinedAt
        self.leftAt = leftAt
    }
}

// MARK: groups/{groupId}/quests/{questId}

public enum QuestSource: String, Codable, Sendable {
    case bank       // picked from quest_bank
    case gemini     // written by the Gemini API for this group
}

/// A timed photo quest for one group ("Take a photo of a statue", 1 hr remaining).
/// Quests are scheduled when the group is created, so every phone can schedule
/// its own local notifications without a server.
public struct Quest: FirestoreDocument, Identifiable, Hashable {
    public var id: String?
    public var prompt: String               // prompt      shown on Camera and in the quest notification
    public var checkable: Bool              // checkable   true = Gemini checks photos; false = creative, auto-pass
    public var order: Int                   // order
    public var startsAt: Date               // starts_at
    public var endsAt: Date                 // ends_at     the quest's deadline ("1 hr remaining!")
    public var source: QuestSource          // source

    enum CodingKeys: String, CodingKey {
        case prompt, checkable, order, startsAt = "starts_at", endsAt = "ends_at", source
    }

    public init(id: String? = nil, prompt: String, checkable: Bool, order: Int,
                startsAt: Date, endsAt: Date, source: QuestSource) {
        self.id = id
        self.prompt = prompt
        self.checkable = checkable
        self.order = order
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.source = source
    }

    public func isActive(at now: Date) -> Bool { startsAt <= now && now < endsAt }

    /// The quest running right now, if any.
    public static func current(in quests: [Quest], at now: Date) -> Quest? {
        quests.filter { $0.isActive(at: now) }.min { $0.order < $1.order }
    }
}

// MARK: groups/{groupId}/photos/{photoId}

/// One photo from the Camera screen. The image itself is in Cloud Storage at `photoAsset`.
public struct GroupPhoto: FirestoreDocument, Identifiable, Hashable {
    public var id: String?
    public var photoAsset: String           // photo_asset      Storage path "groups/g_axolotls/photos/p_001.jpg"
    public var groupId: String              // group_id
    public var photographerId: String       // photographer_id  hidden in the album until a game is played
    public var capturedAt: Date             // captured_at
    public var questId: String?             // quest_id         nil = taken without a quest
    public var questPrompt: String?         // quest_prompt     copied from the quest for display
    public var questCheck: QuestCheck?      // quest_check      Gemini's verdict (checkable quests only)

    enum CodingKeys: String, CodingKey {
        case photoAsset = "photo_asset", groupId = "group_id", photographerId = "photographer_id",
             capturedAt = "captured_at", questId = "quest_id", questPrompt = "quest_prompt", questCheck = "quest_check"
    }

    public init(id: String? = nil, photoAsset: String, groupId: String, photographerId: String,
                capturedAt: Date = Date(), questId: String? = nil, questPrompt: String? = nil,
                questCheck: QuestCheck? = nil) {
        self.id = id
        self.photoAsset = photoAsset
        self.groupId = groupId
        self.photographerId = photographerId
        self.capturedAt = capturedAt
        self.questId = questId
        self.questPrompt = questPrompt
        self.questCheck = questCheck
    }
}

/// Stored on a photo after the Gemini quest check (see Gemini.swift).
public struct QuestCheck: Codable, Hashable, Sendable {
    public var completed: Bool
    public var confidence: Double           // 0...1
    public var reason: String               // shown to the player
    public var tags: [String]               // what Gemini saw
    public var model: String                // "gemini-3.5-flash-lite"
    public var checkedAt: Date              // checked_at

    enum CodingKeys: String, CodingKey {
        case completed, confidence, reason, tags, model, checkedAt = "checked_at"
    }

    public init(completed: Bool, confidence: Double, reason: String, tags: [String],
                model: String, checkedAt: Date = Date()) {
        self.completed = completed
        self.confidence = confidence
        self.reason = reason
        self.tags = tags
        self.model = model
        self.checkedAt = checkedAt
    }
}

// MARK: groups/{groupId}/photos/{photoId}/comments/{commentId}

/// Album comments (Gallery → Comments on the feature list; no screen yet).
public struct PhotoComment: FirestoreDocument, Identifiable, Hashable {
    public var id: String?
    public var authorId: String             // author_id
    public var authorName: String           // author_name
    public var text: String
    public var createdAt: Date              // created_at

    enum CodingKeys: String, CodingKey {
        case authorId = "author_id", authorName = "author_name", text, createdAt = "created_at"
    }

    public init(id: String? = nil, authorId: String, authorName: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.text = text
        self.createdAt = createdAt
    }
}

// MARK: groups/{groupId}/game_sessions/{gameSessionId}

public enum GameStatus: String, Codable, Sendable {
    case lobby      // Game Prep: waiting for players to tap Start
    case playing    // Game: "Who took this photo?"
    case finished   // Leaderboard
}

/// One round of "Who took this photo?": the photo and the people to pick from.
public struct GameRound: Codable, Hashable, Sendable {
    public var photoId: String              // photo_id
    public var candidateIds: [String]       // candidate_ids  includes the real photographer

    enum CodingKeys: String, CodingKey { case photoId = "photo_id", candidateIds = "candidate_ids" }

    public init(photoId: String, candidateIds: [String]) {
        self.photoId = photoId
        self.candidateIds = candidateIds
    }
}

/// A live guessing game. The document ID is the game_session_id. Players tap
/// Start on Game Prep (ready_ids); the host's phone moves `currentRound` on
/// once everyone has guessed.
public struct GameSession: FirestoreDocument, Identifiable, Hashable {
    public var id: String?                  // game_session_id
    public var groupId: String              // group_id
    public var hostId: String               // host_id
    public var participantIds: [String]     // participant_ids
    public var readyIds: [String]           // ready_ids        check marks on Game Prep
    public var gameStatus: GameStatus       // game_status
    public var rounds: [GameRound]
    public var currentRound: Int            // current_round    index into rounds
    public var createdAt: Date              // created_at
    public var startedAt: Date?             // started_at
    public var finishedAt: Date?            // finished_at

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id", hostId = "host_id", participantIds = "participant_ids", readyIds = "ready_ids",
             gameStatus = "game_status", rounds, currentRound = "current_round", createdAt = "created_at",
             startedAt = "started_at", finishedAt = "finished_at"
    }

    public init(id: String? = nil, groupId: String, hostId: String, participantIds: [String], readyIds: [String] = [],
                gameStatus: GameStatus = .lobby, rounds: [GameRound], currentRound: Int = 0,
                createdAt: Date = Date(), startedAt: Date? = nil, finishedAt: Date? = nil) {
        self.id = id
        self.groupId = groupId
        self.hostId = hostId
        self.participantIds = participantIds
        self.readyIds = readyIds
        self.gameStatus = gameStatus
        self.rounds = rounds
        self.currentRound = currentRound
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

// MARK: groups/{groupId}/game_sessions/{gameSessionId}/guesses/{round}_{userId}

/// One player's pick for one round. The ID "{round}_{userId}" means each
/// player can only guess once per round.
public struct PhotoGuess: FirestoreDocument, Identifiable, Hashable {
    public var id: String?
    public var gameSessionId: String        // game_session_id
    public var userId: String               // user_id           who guessed
    public var round: Int
    public var photoId: String              // photo_id
    public var selectedUserId: String       // selected_user_id  who they think took it
    public var isCorrect: Bool              // is_correct
    public var answeredAt: Date             // answered_at

    enum CodingKeys: String, CodingKey {
        case gameSessionId = "game_session_id", userId = "user_id", round, photoId = "photo_id",
             selectedUserId = "selected_user_id", isCorrect = "is_correct", answeredAt = "answered_at"
    }

    public init(id: String? = nil, gameSessionId: String, userId: String, round: Int, photoId: String,
                selectedUserId: String, isCorrect: Bool, answeredAt: Date = Date()) {
        self.id = id ?? "\(round)_\(userId)"
        self.gameSessionId = gameSessionId
        self.userId = userId
        self.round = round
        self.photoId = photoId
        self.selectedUserId = selectedUserId
        self.isCorrect = isCorrect
        self.answeredAt = answeredAt
    }
}

// MARK: group_invitations/{groupId}_{recipientId}

public enum InviteStatus: String, Codable, Sendable {
    case pending, accepted, declined
}

/// "Steph is inviting you to join Party Animals". Send Invites writes one per
/// selected friend, so each person accepts or declines their own. Top-level so
/// the person invited finds it with one query on recipient_id. The group and
/// inviter names are copied in because the invitee can't read the group yet.
public struct GroupInvitation: FirestoreDocument, Identifiable, Hashable {
    public var id: String?
    public var groupId: String              // group_id
    public var groupName: String            // group_name
    public var inviterId: String            // inviter_id
    public var inviterName: String          // inviter_name
    public var recipientId: String          // recipient_id
    public var inviteStatus: InviteStatus   // invite_status
    public var createdAt: Date              // created_at

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id", groupName = "group_name", inviterId = "inviter_id", inviterName = "inviter_name",
             recipientId = "recipient_id", inviteStatus = "invite_status", createdAt = "created_at"
    }

    public init(id: String? = nil, groupId: String, groupName: String, inviterId: String, inviterName: String,
                recipientId: String, inviteStatus: InviteStatus = .pending, createdAt: Date = Date()) {
        self.id = id ?? GroupInvitation.documentID(groupId: groupId, recipientId: recipientId)
        self.groupId = groupId
        self.groupName = groupName
        self.inviterId = inviterId
        self.inviterName = inviterName
        self.recipientId = recipientId
        self.inviteStatus = inviteStatus
        self.createdAt = createdAt
    }

    public static func documentID(groupId: String, recipientId: String) -> String { "\(groupId)_\(recipientId)" }
}

// MARK: invite_codes/{code}

/// Maps a 6-digit code to its group (Join Group). Using the code as the
/// document ID keeps codes unique and lets someone outside the group look one up.
public struct InviteCode: FirestoreDocument, Identifiable, Hashable {
    public var id: String?                  // the 6-digit code
    public var groupId: String              // group_id
    public var createdAt: Date              // created_at

    enum CodingKeys: String, CodingKey { case groupId = "group_id", createdAt = "created_at" }

    public init(id: String? = nil, groupId: String, createdAt: Date = Date()) {
        self.id = id
        self.groupId = groupId
        self.createdAt = createdAt
    }
}

// MARK: quest_bank/{questId}

/// Ready-made quests, used when Gemini isn't available.
public struct BankQuest: FirestoreDocument, Identifiable, Hashable {
    public var id: String?
    public var prompt: String
    public var modes: [GroupMode]
    public var checkable: Bool

    enum CodingKeys: String, CodingKey { case prompt, modes, checkable }

    public init(id: String? = nil, prompt: String, modes: [GroupMode], checkable: Bool) {
        self.id = id
        self.prompt = prompt
        self.modes = modes
        self.checkable = checkable
    }
}

// MARK: - Collection names

/// The last component of a collection path, mapped to its model type.
public enum CollectionID: String, CaseIterable, Sendable {
    case users, friends, usernames, groups, members, quests, photos, comments, guesses
    case friendRequests = "friend_requests"
    case gameSessions = "game_sessions"
    case groupInvitations = "group_invitations"
    case inviteCodes = "invite_codes"
    case questBank = "quest_bank"

    public var modelType: any FirestoreDocument.Type {
        switch self {
        case .users: return UserProfile.self
        case .friends: return Friendship.self
        case .usernames: return UsernameClaim.self
        case .friendRequests: return FriendRequest.self
        case .groups: return GroupRecord.self
        case .members: return GroupMembership.self
        case .quests: return Quest.self
        case .photos: return GroupPhoto.self
        case .comments: return PhotoComment.self
        case .gameSessions: return GameSession.self
        case .guesses: return PhotoGuess.self
        case .groupInvitations: return GroupInvitation.self
        case .inviteCodes: return InviteCode.self
        case .questBank: return BankQuest.self
        }
    }

    /// "groups/g_axolotls/photos" -> .photos
    public init?(path: String) {
        guard let last = path.split(separator: "/").last else { return nil }
        self.init(rawValue: String(last))
    }
}
