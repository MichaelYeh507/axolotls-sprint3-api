import Foundation

// MARK: - User input / interaction
//
// The "User input" lines on each Figma data-stream panel, as Swift enums with
// the same names. Each case is one control; text fields and pickers carry the
// value the person entered. A SwiftUI view sends these to its view model,
// which turns them into the "Data stored" writes in DataStored.swift.

public enum OnboardingInteraction: Sendable {
    case getStartedButton
}

public enum SignUpInteraction: Sendable {
    case googleSignUpButton, appleSignUpButton, emailSignUpButton
}

public enum SignInInteraction: Sendable {
    case googleSignInButton, appleSignInButton, emailSignInButton
}

public enum HomeInteraction: Sendable {
    case createGroupButton
    case joinGroupButton
    case groupInviteSelection(invitationId: String)
    case viewArchiveButton
    case profileButton
    case cameraCaptureButton(groupId: String)           // capture button (Group 8 note: CameraInteraction)
}

public enum GroupCreationInteraction: Sendable {
    case groupNameField(String)
    case descriptionField(String)
    case eventDatePicker(Date)
    case eventTimePicker(Date)
    case modeSelector(GroupMode)
    case groupIconSelector(imageData: Data?)
    case createGroupButton                              // saves a GroupRecord (GroupCreation.writes)
}

public enum JoinGroupInteraction: Sendable {
    case joinGroupCodeField(String)                     // 6 digits
    case joinGroupButton                                // GroupInvitationLookup, then GroupMembership.joinWrites
}

public enum FriendInteraction: Sendable {
    case friendSearchField(String)
    case addFriendButton(userId: String)                // FriendRequest.sendWrites
    case acceptRequestButton(requestId: String)         // not on the panel yet: FriendRequest.acceptWrites
    case declineRequestButton(requestId: String)        // not on the panel yet: FriendRequest.declineWrites
}

public enum GroupInteraction: Sendable {
    case invitePeopleButton, groupOptionsButton, cameraButton
}

public enum GroupOptionsInteraction: Sendable {
    case groupOptionsButton, editGroupButton, invitePeopleButton
}

public enum GroupEditInteraction: Sendable {
    case groupNameField(String)
    case descriptionField(String)
    case eventDatePicker(Date)
    case eventTimePicker(Date)
    case modeSelector(GroupMode)
    case groupIconSelector(imageData: Data?)
    case saveChangesButton                              // GroupUpdate.writes
}

public enum GroupInvitationInteraction: Sendable {
    case friendSearchField(String)
    case friendSelection(userId: String)
    case inviteCodeCopyButton                           // clipboard only
    case cancelButton
    case sendInvitesButton                              // GroupInvitation.sendWrites, one per selected friend
}

public enum CameraInteraction: Sendable {
    case cameraCaptureButton
    case cameraPermissionPrompt(granted: Bool)          // Group 8 note
    case photoCaptureAction(jpeg: Data)                 // Storage upload, Gemini quest check, GroupPhoto.saveWrites
}

public enum PhotoRevealInteraction: Sendable {
    case revealAlbumButton, guessPhotoTakersButton
}

public enum AlbumInteraction: Sendable {
    case photoSelection(photoId: String)
    case saveAllPhotosButton                            // DevicePhotoExport
    case invitePeopleButton
    case guessPhotoTakersButton
    case albumMenuButton
}

public enum AlbumOptionsInteraction: Sendable {
    case editGroupButton
    case invitePeopleButton
    case guessPhotoTakersButton
    case saveAllPhotosButton
    case leaveGroupButton                               // AlbumActionResult.leaveGroupWrites
}

public enum SettingsInteraction: Sendable {
    case accountSettingsSelection, friendsListSelection, archiveSelection, accountPreferencesSelection, deleteAccountButton
}

public enum AccountSettingsInteraction: Sendable {
    case emailUpdateField(String)
    case usernameUpdateField(String)
    case displayNameUpdateField(String)
    case passwordResetButton
    case profilePhotoUpdate(imageData: Data)            // all become one AccountUpdate
}

public enum FriendsListInteraction: Sendable {
    case friendSearchField(String)
    case removeFriendButton(userId: String)             // FriendshipUpdate.writes
}

public enum ArchiveInteraction: Sendable {
    case archiveCardSelection(groupId: String)
    case deleteArchivedGroupButton(groupId: String)     // ArchivedGroupDeletion.writes
}

public enum NotificationSettingsInteraction: Sendable {
    case questsToggle(Bool)
    case newGroupInviteToggle(Bool)
    case photosAvailableToggle(Bool)
    case deleteAccountButton
}

public enum GamePreparationInteraction: Sendable {
    case startButton                                    // GameSession.readyWrites
}

public enum PhotoGuessInteraction: Sendable {
    case photoTakerSelection(userId: String)            // PhotoGuess.writes
}

public enum LeaderboardInteraction: Sendable {
    case playAgainButton                                // a new GameSession
}

public enum QuestNotificationInteraction: Sendable {
    case questNotificationTap(groupId: String)          // opens Camera for that group
}
