import Foundation

// MARK: - Data stored (WRITE)
//
// What each screen saves: the "Data stored" lines on the Figma data-stream
// panels. Documents that are created whole (UserProfile, GroupRecord,
// GroupMembership, FriendRequest, GroupInvitation, GroupPhoto, GameSession,
// PhotoGuess) are in Models.swift. This file holds the structs for changes to
// existing documents (GroupUpdate, AccountUpdate, FriendshipUpdate, ...) and
// the exact Firestore writes behind each button.
//
// The playground sends these writes over REST. In the app each list becomes
// one Firebase SDK batch with the same paths and fields, for example Join Group:
//   let batch = db.batch()
//   try batch.setData(from: membership, forDocument: db.document("groups/\(groupId)/members/\(uid)"))
//   batch.updateData(["member_ids": FieldValue.arrayUnion([uid])], forDocument: db.document("groups/\(groupId)"))
//   try await batch.commit()

// MARK: Onboarding 2 · AccountRegistration

/// Onboarding 2 · AccountRegistration (user_profile, authentication_session).
/// Firebase Auth creates the account and its AuthenticationSession; then the
/// profile and the username claim are saved together.
public struct AccountRegistration: Sendable {
    public var userProfile: UserProfile
    public var authenticationSession: AuthenticationSession

    public init(userProfile: UserProfile, authenticationSession: AuthenticationSession) {
        self.userProfile = userProfile
        self.authenticationSession = authenticationSession
    }

    /// users/{userId} and usernames/{username}.
    public func writes() throws -> [FirestoreWrite] {
        let userId = authenticationSession.userId
        return [try .set(userProfile, at: "users/\(userId)"),
                try .set(UsernameClaim(userId: userId), at: "usernames/\(userProfile.username.lowercased())")]
    }
}

// MARK: Create Group · GroupRecord

public enum GroupCreation {
    /// A random 6-digit code that no other group is using.
    public static func uniqueInviteCode(in db: Firestore) async throws -> String {
        for _ in 0..<10 {
            let code = String(format: "%06d", Int.random(in: 0...999_999))
            if try await db.getIfExists(InviteCode.self, "invite_codes/\(code)") == nil { return code }
        }
        throw DemoError.notReady("Couldn't find a free invite code. Try again.")
    }

    /// Spreads the quests evenly over the event, each lasting up to an hour.
    public static func scheduleQuests(_ ideas: [QuestIdea], from start: Date, to end: Date,
                                      source: QuestSource = .gemini) -> [Quest] {
        guard !ideas.isEmpty, end > start else { return [] }
        let slot = end.timeIntervalSince(start) / Double(ideas.count)
        let length = min(3600, slot)
        return ideas.enumerated().map { index, idea in
            let begins = start.addingTimeInterval(Double(index) * slot)
            return Quest(id: String(format: "q_%02d", index + 1), prompt: idea.prompt, checkable: idea.checkable,
                         order: index + 1, startsAt: begins, endsAt: begins.addingTimeInterval(length), source: source)
        }
    }

    /// Create Group: groups/{groupId}, the creator's membership, invite_codes/{code}
    /// and groups/{groupId}/quests/*, in one batch.
    public static func writes(for group: GroupRecord, groupId: String, quests: [Quest]) throws -> [FirestoreWrite] {
        var writes = [
            try FirestoreWrite.set(group, at: "groups/\(groupId)"),
            try FirestoreWrite.set(GroupMembership(groupId: groupId, userId: group.creatorId, joinedAt: group.createdAt),
                                   at: "groups/\(groupId)/members/\(group.creatorId)"),
            try FirestoreWrite.set(InviteCode(groupId: groupId, createdAt: group.createdAt),
                                   at: "invite_codes/\(group.inviteCode)"),
        ]
        for quest in quests {
            writes.append(try .set(quest, at: "groups/\(groupId)/quests/\(quest.id ?? UUID().uuidString)"))
        }
        return writes
    }
}

// MARK: Join Group · GroupMembership

extension GroupMembership {
    /// Join Group: once invite_codes/{code} points to a group (GroupInvitationLookup),
    /// the member document and the member_ids entry are added together.
    public static func joinWrites(groupId: String, userId: String, at date: Date = Date()) throws -> [FirestoreWrite] {
        [try .set(GroupMembership(groupId: groupId, userId: userId, joinedAt: date), at: "groups/\(groupId)/members/\(userId)"),
         .arrayUnion(path: "groups/\(groupId)", field: "member_ids", values: [.string(userId)])]
    }
}

// MARK: Add Friends · FriendRequest

extension FriendRequest {
    public var documentPath: String { "friend_requests/\(id ?? FriendRequest.documentID(from: senderId, to: recipientId))" }

    /// Add Friends → add_friend_button.
    public static func sendWrites(from senderId: String, to recipientId: String, at date: Date = Date()) throws -> [FirestoreWrite] {
        let request = FriendRequest(senderId: senderId, recipientId: recipientId, createdAt: date)
        return [try .set(request, at: request.documentPath)]
    }

    /// Accept: the request is marked accepted and both sides of the friendship are created.
    public func acceptWrites(at date: Date = Date()) throws -> [FirestoreWrite] {
        var answered = self
        answered.requestStatus = .accepted
        answered.respondedAt = date
        return [try .update(answered, at: documentPath, mask: ["request_status", "responded_at"]),
                try .set(Friendship(userId: senderId, friendId: recipientId, createdAt: date),
                         at: "users/\(senderId)/friends/\(recipientId)"),
                try .set(Friendship(userId: recipientId, friendId: senderId, createdAt: date),
                         at: "users/\(recipientId)/friends/\(senderId)")]
    }

    public func declineWrites(at date: Date = Date()) throws -> [FirestoreWrite] {
        var answered = self
        answered.requestStatus = .declined
        answered.respondedAt = date
        return [try .update(answered, at: documentPath, mask: ["request_status", "responded_at"])]
    }
}

// MARK: Friends List · FriendshipUpdate

/// Friends List · FriendshipUpdate (user_id, friend_id, friendship_status).
/// Removing a friend marks both sides "removed".
public struct FriendshipUpdate: Codable, Hashable, Sendable {
    public var userId: String                       // user_id
    public var friendId: String                     // friend_id
    public var friendshipStatus: FriendshipStatus   // friendship_status

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", friendId = "friend_id", friendshipStatus = "friendship_status"
    }

    public init(userId: String, friendId: String, friendshipStatus: FriendshipStatus = .removed) {
        self.userId = userId
        self.friendId = friendId
        self.friendshipStatus = friendshipStatus
    }

    public func writes() throws -> [FirestoreWrite] {
        [try .update(self, at: "users/\(userId)/friends/\(friendId)", mask: ["friendship_status"]),
         try .update(self, at: "users/\(friendId)/friends/\(userId)", mask: ["friendship_status"])]
    }
}

// MARK: Edit Group · GroupUpdate

/// Edit Group · GroupUpdate (group_name, description, event_end_at, mode, group_icon).
/// The screen loads the GroupRecord into the controls, then saves only these fields.
public struct GroupUpdate: Codable, Hashable, Sendable {
    public var groupName: String            // group_name
    public var description: String          // description
    public var eventEndAt: Date             // event_end_at
    public var mode: GroupMode              // mode
    public var groupIcon: String?           // group_icon  nil removes the icon

    enum CodingKeys: String, CodingKey {
        case groupName = "group_name", description, eventEndAt = "event_end_at", mode, groupIcon = "group_icon"
    }

    public static let fieldNames = ["group_name", "description", "event_end_at", "mode", "group_icon"]

    public init(groupName: String, description: String, eventEndAt: Date, mode: GroupMode, groupIcon: String? = nil) {
        self.groupName = groupName
        self.description = description
        self.eventEndAt = eventEndAt
        self.mode = mode
        self.groupIcon = groupIcon
    }

    /// Edit Group starts from the saved group.
    public init(editing group: GroupRecord) {
        self.init(groupName: group.groupName, description: group.description, eventEndAt: group.eventEndAt,
                  mode: group.mode, groupIcon: group.groupIcon)
    }

    public func writes(groupId: String) throws -> [FirestoreWrite] {
        [try .update(self, at: "groups/\(groupId)", mask: Self.fieldNames)]
    }
}

// MARK: Group Page - Invite / Album Revealed - Invite · GroupInvitation

extension GroupInvitation {
    public var documentPath: String {
        "group_invitations/\(id ?? GroupInvitation.documentID(groupId: groupId, recipientId: recipientId))"
    }

    /// Send Invites: one invitation per selected friend (recipient_id), so each
    /// person accepts or declines their own. Copy Code only touches the clipboard.
    public static func sendWrites(groupId: String, groupName: String, inviterId: String, inviterName: String,
                                  recipientIds: [String], at date: Date = Date()) throws -> [FirestoreWrite] {
        try recipientIds.map { recipientId in
            let invitation = GroupInvitation(groupId: groupId, groupName: groupName, inviterId: inviterId,
                                             inviterName: inviterName, recipientId: recipientId, createdAt: date)
            return try .set(invitation, at: invitation.documentPath)
        }
    }

    /// Home → group_invite_selection → join: the invitation is accepted and the person joins the group.
    public func acceptWrites(at date: Date = Date()) throws -> [FirestoreWrite] {
        var accepted = self
        accepted.inviteStatus = .accepted
        return [try .update(accepted, at: documentPath, mask: ["invite_status"])]
            + (try GroupMembership.joinWrites(groupId: groupId, userId: recipientId, at: date))
    }

    public func declineWrites() throws -> [FirestoreWrite] {
        var declined = self
        declined.inviteStatus = .declined
        return [try .update(declined, at: documentPath, mask: ["invite_status"])]
    }
}

// MARK: Camera · GroupPhoto

extension GroupPhoto {
    /// Camera: the image goes to Cloud Storage at photo_asset first. Then the
    /// photo document and +1 on the group's photo_count are written together.
    /// `isNew` is false when the same photo is saved again.
    public func saveWrites(photoId: String, isNew: Bool = true) throws -> [FirestoreWrite] {
        var writes = [try FirestoreWrite.set(self, at: "groups/\(groupId)/photos/\(photoId)")]
        if isNew { writes.append(.increment(path: "groups/\(groupId)", field: "photo_count", by: 1)) }
        return writes
    }
}

// MARK: Album Revealed · DevicePhotoExport

/// Album Revealed · DevicePhotoExport (exported_photo_assets). Saves photos to
/// the phone's Photos library (PHPhotoLibrary); nothing is written to Firebase.
public struct DevicePhotoExport: Hashable, Sendable {
    public var exportedPhotoAssets: [String]        // Storage paths to download, then save on the device

    public init(photos: [GroupPhoto]) { exportedPhotoAssets = photos.map(\.photoAsset) }
}

// MARK: Album Revealed - Options · AlbumActionResult

/// Album Revealed - Options · AlbumActionResult (membership_status, exported_photo_assets).
public struct AlbumActionResult: Hashable, Sendable {
    public var membershipStatus: MembershipStatus?  // .left after Leave Group
    public var exportedPhotoAssets: [String]        // after Save All Photos (see DevicePhotoExport)

    public init(membershipStatus: MembershipStatus? = nil, exportedPhotoAssets: [String] = []) {
        self.membershipStatus = membershipStatus
        self.exportedPhotoAssets = exportedPhotoAssets
    }

    /// Leave Group: the membership is marked "left" and the person comes off
    /// member_ids, so the group drops out of their Home and Archive. Their photos stay.
    public static func leaveGroupWrites(groupId: String, userId: String, at date: Date = Date()) throws -> [FirestoreWrite] {
        let left = GroupMembership(groupId: groupId, userId: userId, membershipStatus: .left, joinedAt: date, leftAt: date)
        return [try .update(left, at: "groups/\(groupId)/members/\(userId)", mask: ["membership_status", "left_at"]),
                .arrayRemove(path: "groups/\(groupId)", field: "member_ids", values: [.string(userId)])]
    }
}

// MARK: Archive · ArchivedGroupDeletion

/// Archive · ArchivedGroupDeletion (the trash button on an archive card).
/// The group's creator deletes it for everyone. Anyone else leaves it, which
/// removes it from their own archive only.
public struct ArchivedGroupDeletion: Hashable, Sendable {
    public var groupId: String
    public var userId: String                       // who tapped the trash button
    public var creatorId: String
    public var inviteCode: String

    public init(group: GroupRecord, groupId: String, userId: String) {
        self.groupId = groupId
        self.userId = userId
        self.creatorId = group.creatorId
        self.inviteCode = group.inviteCode
    }

    public var deletesForEveryone: Bool { userId == creatorId }

    /// `childDocuments` are the document paths under groups/{groupId} (members,
    /// quests, photos, comments, game sessions, guesses). Firestore doesn't
    /// delete subcollections with their parent, so the creator's phone lists and
    /// deletes them too. The images in Cloud Storage are deleted separately.
    public func writes(childDocuments: [String] = []) throws -> [FirestoreWrite] {
        guard deletesForEveryone else {
            return try AlbumActionResult.leaveGroupWrites(groupId: groupId, userId: userId)
        }
        return childDocuments.map { FirestoreWrite.delete(path: $0) }
            + [.delete(path: "groups/\(groupId)"), .delete(path: "invite_codes/\(inviteCode)")]
    }
}

// MARK: Account Settings · AccountUpdate

/// Account Settings · AccountUpdate (email, username, display_name, profile_photo,
/// password_reset_request). Email and password go to Firebase Auth; the rest to Firestore.
public struct AccountUpdate: Hashable, Sendable {
    public var email: String?                       // Auth: sendEmailVerification(beforeUpdatingEmail:)
    public var username: String?                    // users/{uid}.username, and the usernames/ claim moves
    public var displayName: String?                 // users/{uid}.display_name
    public var profilePhoto: String?                // users/{uid}.profile_photo (upload to Storage first)
    public var passwordResetRequest: Bool           // Auth: sendPasswordReset(withEmail:); never stored

    public init(email: String? = nil, username: String? = nil, displayName: String? = nil,
                profilePhoto: String? = nil, passwordResetRequest: Bool = false) {
        self.email = email
        self.username = username
        self.displayName = displayName
        self.profilePhoto = profilePhoto
        self.passwordResetRequest = passwordResetRequest
    }

    /// The Firestore part of the update.
    public func firestoreWrites(userId: String, currentUsername: String) throws -> [FirestoreWrite] {
        var fields: [String: JSONValue] = [:]
        var mask: [String] = []
        var writes: [FirestoreWrite] = []
        if let displayName {
            fields["display_name"] = FirestoreValue.encode(.string(displayName))
            mask.append("display_name")
        }
        if let profilePhoto {
            fields["profile_photo"] = FirestoreValue.encode(.string(profilePhoto))
            mask.append("profile_photo")
        }
        if let username, username.lowercased() != currentUsername.lowercased() {
            let newName = username.lowercased()
            fields["username"] = FirestoreValue.encode(.string(newName))
            mask.append("username")
            writes.append(try .set(UsernameClaim(userId: userId), at: "usernames/\(newName)"))
            writes.append(.delete(path: "usernames/\(currentUsername.lowercased())"))
        }
        if !mask.isEmpty { writes.insert(.update(path: "users/\(userId)", fields: fields, mask: mask), at: 0) }
        return writes
    }
}

// MARK: Account Preferences · NotificationPreferences

extension NotificationPreferences {
    /// Account Preferences: save the three toggles.
    public func saveWrites(userId: String) throws -> [FirestoreWrite] {
        [.update(path: "users/\(userId)",
                 fields: try FirestoreValue.fields(encoding: ["notification_preferences": self]),
                 mask: ["notification_preferences"])]
    }
}

// MARK: Game Prep / Leaderboard · GameSession

extension GameSession {
    func documentPath() throws -> String {
        guard let id else { throw DemoError.notReady("GameSession needs an id (the game_session_id).") }
        return "groups/\(groupId)/game_sessions/\(id)"
    }

    /// Game Prep (or Leaderboard → Play Again): the session starts in the lobby.
    public func createWrites() throws -> [FirestoreWrite] {
        [try .set(self, at: try documentPath())]
    }

    /// Game Prep → start_button: this player is ready (a check mark appears).
    public func readyWrites(userId: String) throws -> [FirestoreWrite] {
        [.arrayUnion(path: try documentPath(), field: "ready_ids", values: [.string(userId)])]
    }

    /// The host's phone starts the game once everyone is ready.
    public func startWrites(at date: Date = Date()) throws -> [FirestoreWrite] {
        var started = self
        started.gameStatus = .playing
        started.startedAt = date
        started.currentRound = 0
        return [try .update(started, at: try documentPath(), mask: ["game_status", "started_at", "current_round"])]
    }
}

// MARK: Game · PhotoGuess

extension PhotoGuess {
    /// Game → photo_taker_selection. Correct when the pick is the photo's photographer.
    public static func make(session: GameSession, round: Int, userId: String, selectedUserId: String,
                            photographerId: String, at date: Date = Date()) -> PhotoGuess {
        PhotoGuess(gameSessionId: session.id ?? "", userId: userId, round: round,
                   photoId: session.rounds[round].photoId, selectedUserId: selectedUserId,
                   isCorrect: selectedUserId == photographerId, answeredAt: date)
    }

    public func writes(groupId: String) throws -> [FirestoreWrite] {
        [try .set(self, at: "groups/\(groupId)/game_sessions/\(gameSessionId)/guesses/\(id ?? "\(round)_\(userId)")")]
    }
}
