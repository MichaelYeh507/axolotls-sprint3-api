# Sprint 3 · API & JSON (The Axolotls)

This folder holds the app's data layer and the Sprint 3 demo. It covers the
data our app needs, where that data lives, and working code that reads and
writes it. Struct and field names match the "Data Streams" panels on the hi-fi
Figma screens, with "quest" wherever a panel says "challenge".

| What | Where |
|---|---|
| Firestore structs, one per collection (copy into the app) | `Sprint3API.playground/Sources/Models.swift` |
| "Data stored" structs and the Firestore writes behind each button | `Sprint3API.playground/Sources/DataStored.swift` |
| "Data accessed" structs: what each hi-fi screen reads, built from the models | `Sprint3API.playground/Sources/DataAccessed.swift` |
| "User input" enums, one per panel | `Sprint3API.playground/Sources/UserInput.swift` |
| Gemini API request/response structs and prompts | `Sprint3API.playground/Sources/Gemini.swift` |
| Sample data for every collection (539 documents) | `Sprint3API.playground/Resources/seed.json` |
| Demo pages: seed → read → Gemini quest check → Gemini quest ideas | `Sprint3API.playground/Pages/` |
| Firestore and Storage security rules for the demo | `firebase/` |
| Script that generates `seed.json` (edit it, run `python3 tools/make_seed.py seed.json`, copy the result into Resources) | `tools/make_seed.py` |

**Rubric coverage**

| Rubric item | How we cover it |
|---|---|
| Firebase structure established | Data structure doc (JSON of all 14 collections), page 1 seeds Firestore, console screenshots |
| Data needs mapped to the wireframes | Anabella's data-stream panels; every struct on them exists in `Sources` with the same name |
| External API data parsed | Pages 3–4 call the Gemini API and decode its JSON into structs in `Gemini.swift` |
| Structs for the app's data | `Models.swift` (stored documents), `DataStored.swift`, `DataAccessed.swift`, `UserInput.swift` |
| Internal API | Not applicable: Firebase is our backend, so there's no server of our own |
| SwiftData | Not applicable: Firestore's built-in offline cache keeps data on the device |

Playgrounds can't load the Firebase SDK, so the pages call the same REST
endpoints the SDK uses under the hood. That's also what lets the demo show
the raw JSON before it's decoded.

---

## One-time setup (about 15 minutes)

Our project, `axolotls-d0d4f`, already has steps 1 and 2 done: Firestore (nam5, US) with
the demo rules published, and Anonymous sign-in on. Storage (step 3) is off. To run the
demo, do step 4 (paste the two keys) and step 5. The steps are here for anyone setting up
their own project.

### 1. Create the Firebase project
1. Go to [console.firebase.google.com](https://console.firebase.google.com) → **Create a project**.
2. Name it (for example `axolotls`). Google Analytics can stay off.

### 2. Turn on Firestore and Authentication
1. **Build → Firestore Database → Create database.** Pick a US location and start in **production mode**.
2. Open the **Rules** tab, replace everything with `firebase/firestore.rules`, and click **Publish**.
3. **Build → Authentication → Get started → Sign-in method → Anonymous → Enable → Save.**
   The playground signs in anonymously so the rules know a signed-in user is asking.

### 3. Storage for photos (optional for the demo, needed for the app)
Cloud Storage now requires the **Blaze** (pay-as-you-go) plan, even though our usage
stays inside the free allowance.
1. Click **Upgrade** → Blaze and attach a billing account. Set a budget alert (for example $1) when asked.
2. **Build → Storage → Get started.** Choose a US region (`us-central1`, `us-east1` or `us-west1` keep the no-cost tier).
3. Open **Rules**, paste `firebase/storage.rules`, and **Publish**.

To skip Storage for now, set `storageBucket: ""` in step 4. Page 3 will then skip the upload.

### 4. Fill in `Sources/Secrets.swift`
| Value | Where to find it |
|---|---|
| `projectID` | Firebase console → ⚙️ Project settings → General → **Project ID** (already filled in: `axolotls-d0d4f`) |
| `webAPIKey` | Same page → **Your apps** → the web app (ours is "Sprint3 playground") → SDK setup and configuration → `apiKey`. No app yet? Click **Add app** → Web (`</>`), register it without Hosting, and the key appears in its config. |
| `storageBucket` | `""` skips uploads. With Storage on, the Storage page header shows `gs://<something>.firebasestorage.app`; use the part after `gs://` |
| `geminiAPIKey` | [aistudio.google.com](https://aistudio.google.com) → **Get API key** → Create API key. No billing needed. |

### 5. Run it
Use Xcode 26.0 or later, not a beta: the 26 betas had a bug compiling playgrounds that have a `Sources` folder.

1. Double-click `Sprint3API.playground` to open it in Xcode. It's set to run only when you press Run, so typing your keys won't fire any API calls.
2. Show the navigator (⌘1). The four pages are listed under the playground; `Sources` and `Resources` are below them.
3. Open a page and press **Run** (▶︎ at the bottom of the editor, or ⇧⌘↩). Output appears in the debug area (⇧⌘Y).

Run the pages in order:

| Page | What it does | What you'll see |
|---|---|---|
| **1 Seed Firestore** | Checks all 539 sample documents against the structs, then writes them | Each collection with its struct (`users → 28 × UserProfile`, ...), then "Firestore saved 539 documents" |
| **2 Read Firestore** | Reads the data back as Anabella (the user on the Figma screens) | Raw Firestore JSON → `GroupRecord` → the "Data accessed" struct for 18 panels: `HomeData`, `GroupOverview`, `CameraContext`, `QuestNotification`, `ArchiveData`, `GameLeaderboard`, `FriendDiscoveryData`, ... |
| **3 Gemini Quest Check** | Sends `quest-photo.jpg` and the current quest to Gemini, saves the verdict on a new photo | `CameraContext` → raw Gemini JSON → `QuestVerdict` → Storage upload → `GroupPhoto` |
| **4 Gemini Quest Ideas** | Has Gemini write quests for a new travel group, then creates the group | Gemini's JSON → `QuestIdeas` → `GroupRecord`, the creator's membership, invite code and quests saved |

Times in the sample data are set relative to when page 1 runs: The Axolotls' photos
reveal 16 hours later, and its statue quest has 1 hour left. Run page 1 again
any time to reset them.

To test your own picture, replace `Resources/quest-photo.jpg` (keep the name). The
default photo is a drawing of a blue mug, so the statue quest should fail and
"something blue" should pass.

---

## Recording the demo (two short clips)

The TA's example is a 20-second silent clip: the code on the left, the result on
the right. Ours follow the same format, one clip per rubric item.

**Before you record**
- Run each page once as a warm-up. The first run compiles everything and is slow.
- Make the Xcode font bigger (⌘+), hide the navigator (⌘0) and the inspector (⌥⌘0), and drag the debug area up so the output fills the bottom half.
- Put Xcode on the left half of the screen and a browser with the Firebase console on the right half.
- Record with ⌘⇧5 → Record Entire Screen. Stop with the ⏹ button in the menu bar.

**Clip 1 · JSON → Firebase (about 30 seconds)**
1. Page 1 → Run. Let the collection list and "Firestore saved 539 documents" show.
2. In the browser: Firestore Database → Data → `users/u_anabella`, then `groups/g_axolotls`.
3. Page 2 → Run. Scroll slowly from the raw JSON to `HomeData`, `GroupOverview` and `ArchiveData`.

**Clip 2 · Gemini API → structs (about 30 seconds)**
1. Page 3 → Run. Stop on Gemini's raw JSON, then on the decoded `QuestVerdict`.
2. In the browser: `groups/g_axolotls/photos/p_demo` with `quest_check` open, then Storage → `p_demo.jpg`.
3. Page 4 → Run. Show the six quests and the new `groups/g_pittsburgh_demo` in the console.

## Screenshots for the report
1. Firestore **Data** tab showing the root collections: users, usernames, friend_requests, groups, group_invitations, invite_codes, quest_bank
2. `users/u_anabella` and its `friends` subcollection
3. `friend_requests/u_jen_u_anabella`
4. `groups/g_axolotls` and `groups/g_axolotls/members/u_lily`
5. `groups/g_axolotls/quests/q_03`
6. `groups/g_axolotls/photos/p_demo` with `quest_check` expanded
7. `groups/g_italy/game_sessions/game_1` and one document in its `guesses`
8. `group_invitations/g_party_animals_u_anabella` and `invite_codes/123456`
9. Storage: `groups/g_axolotls/photos/` showing `p_demo.jpg`
10. Authentication → **Users** (the anonymous accounts the playground created)

---

## Using this in the app (Sprint 4)
1. Add Firebase with Swift Package Manager (Firebase 12.5 or later): `FirebaseAuth`, `FirebaseFirestore`, `FirebaseStorage`, `FirebaseAILogic`.
2. Copy `Models.swift`, `DataAccessed.swift` and `UserInput.swift` into the app target; they depend on nothing else. From `Gemini.swift`, copy `QuestVerdict`, `QuestIdeas`, `QuestIdea` and `GeminiPrompts`.
3. Read and write with the SDK. `DataStored.swift` uses the playground's REST helpers, so treat it as the spec: each of its write lists (same paths, same fields) becomes one `WriteBatch` in the app.
   ```swift
   var group = try snapshot.data(as: GroupRecord.self)
   group.id = snapshot.documentID                     // the ID isn't stored as a field
   try db.collection("groups").document(groupID).setData(from: group)
   ```
4. Call Gemini through Firebase AI Logic, so the API key never ships inside the app.
   It's the same setup as the TA's example, which used the older module name
   (`import FirebaseAI`, renamed in Firebase 12.5). Use the same prompt and the
   same `QuestVerdict` struct as the playground:
   ```swift
   import FirebaseAILogic

   let model = FirebaseAI.firebaseAI(backend: .googleAI()).generativeModel(
       modelName: "gemini-3.5-flash-lite",
       generationConfig: GenerationConfig(
           responseMIMEType: "application/json",
           responseSchema: .object(properties: [
               "completed": .boolean(),
               "confidence": .double(),
               "reason": .string(),
               "tags": .array(items: .string()),
           ])
       )
   )
   let response = try await model.generateContent(photo, GeminiPrompts.questCheck(quest.prompt))  // photo: UIImage
   let verdict = try JSONDecoder().decode(QuestVerdict.self, from: Data((response.text ?? "").utf8))
   ```
   The response schema is why we don't need "Return ONLY the JSON" in the prompt:
   Gemini's reply has to match the struct.

**Before real users**
- Replace the demo security rules: only group members should read a group, and photos should stay locked until `event_end_at`.
- Gemini's free tier may use what you send to improve Google's products. Use the paid tier (it's on Blaze already for Storage) before real people's photos go through it.

## Keeping keys out of GitHub
After filling in `Secrets.swift`, run this once so git ignores your local edits:
```
git update-index --skip-worktree Sprint3API.playground/Sources/Secrets.swift
```
The rubric says the playground should come "with API keys, as needed". Send your TA a
key privately, restricted to the Generative Language API (Google Cloud console → APIs &
Services → Credentials), or have them paste their own. Delete it after grading.

## Troubleshooting
Every error prints a hint. The common ones:

| Message | Fix |
|---|---|
| `Fill in ... in Sources/Secrets.swift first` | Step 4 |
| `Firebase Auth error 400: ADMIN_ONLY_OPERATION` or `OPERATION_NOT_ALLOWED` | Enable Anonymous sign-in (step 2.3) |
| `Firestore error 404 ... database (default) does not exist` | Create the Firestore database (step 2.1) |
| `Firestore error 403: Missing or insufficient permissions` | Publish `firebase/firestore.rules` (step 2.2) |
| `Cloud Storage error 402/403/404` | Finish step 3, or set `storageBucket` to `""` |
| `Gemini API error 400: API key not valid` | Check `geminiAPIKey` |
| `Gemini API error 429` | Free-tier rate limit; wait a minute |
| `Gemini API error 404` | The model name changed; pick a current one in AI Studio and update `geminiModel` |
