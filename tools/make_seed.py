#!/usr/bin/env python3
"""Generate seed.json for the Sprint 3 Firestore demo.

Struct and field names follow the "Data Streams" panels on the hi-fi Figma
screens: snake_case field names in Firestore, "quest" wording throughout.
People, groups and counts come from the same screens (Anabella's Home, The
Axolotls, the Archive cards, the Leaderboard, Add Friends, Friends List).

All timestamps are written relative to REFERENCE_NOW. The playground shifts
every timestamp by (actual now - REFERENCE_NOW) before writing to Firestore,
so "Photos will reveal in 16 hours" and "1 year ago today" stay true whenever
the seed is run.

Usage: python3 tools/make_seed.py seed.json
"""
import hashlib
import json
import random
import sys
from datetime import datetime, timedelta, timezone
from itertools import combinations

REF = datetime(2026, 10, 20, 16, 0, 0, tzinfo=timezone.utc)  # 12:00 EDT
MODEL = "gemini-3.5-flash-lite"
random.seed(67443)


def ts(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse(text: str) -> datetime:
    return datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def rel(**kw) -> datetime:
    return REF + timedelta(**kw)


def phone_hash(e164: str) -> str:
    return hashlib.sha256(e164.encode()).hexdigest()


collections = []  # (collection path, {document ID: fields}), written in this order

# ---------------------------------------------------------------- users/{userId}  (UserProfile)
# (id, display_name, username, account created (days before now), phone or None)
PEOPLE = [
    ("u_anabella", "Anabella", "anabellaaaaaa", -420, None),
    ("u_steph", "Steph", "steph", -425, None),
    ("u_lily", "Lily", "lilyyy", -418, None),
    ("u_michael", "Michael", "michael", -421, None),
    ("u_streak", "Streak", "streak", -400, None),
    # Friends List screen
    ("u_amanda", "Amanda", "amanda", -410, None),
    ("u_brittney", "Brittney", "brittney", -405, None),
    ("u_diego", "Diego", "diego", -400, None),
    ("u_fred", "Fred", "fred", -395, None),
    ("u_greg", "Greg", "greg", -390, None),
    ("u_haley", "Haley", "haley", -388, None),
    ("u_paaramita", "Paaramita", "paaramita", -385, None),
    ("u_rachel", "Rachel", "rachel", -380, None),
    ("u_sammy", "Sammy", "sammy", -378, None),
    ("u_ted", "Ted", "ted", -376, None),
    ("u_umed", "Umed", "umed", -374, None),
    ("u_jade", "Jade", "jade", -372, None),
    ("u_riley", "Riley", "riley", -300, None),
    ("u_sophia", "Sophia", "sophia", -250, None),
    ("u_tim", "Tim", "tim", -200, None),
    ("u_aaron", "Aaron", "aaron", -150, None),
    # share groups with Anabella but aren't her friends -> Add Friends: suggested_people / requests
    ("u_jen", "Jen", "jen", -390, None),
    ("u_kyle", "Kyle", "kyle", -386, None),
    ("u_sharon", "Sharon", "sharon", -380, None),
    # in Anabella's phone contacts -> Add Friends: contact_matches ("From Your Contacts")
    ("u_jimmy", "Jimmy S", "jimmy.s", -200, "+14125550101"),
    ("u_helen", "Helen", "helen", -150, "+14125550102"),
    ("u_abigail", "Abigail L", "abigail.l", -100, "+14125550103"),
    ("u_kate", "Kate", "kate", -40, "+14125550104"),
]
NAME = {p[0]: p[1] for p in PEOPLE}
CREATED = {}

users, usernames = {}, {}
for uid, name, handle, days, phone in PEOPLE:
    CREATED[uid] = rel(days=days, hours=random.randint(-6, 6))
    doc = {"display_name": name, "username": handle}
    if uid == "u_steph":
        doc["profile_photo"] = "users/u_steph/profile.jpg"
    if phone:
        doc["phone_hash"] = phone_hash(phone)
    doc["notification_preferences"] = {
        "quest_notifications_enabled": True,
        "group_invite_notifications_enabled": True,
        "photos_available_notifications_enabled": uid != "u_streak",
    }
    doc["created_at"] = ts(CREATED[uid])
    users[uid] = doc
    usernames[handle] = {"user_id": uid}

# ---------------------------------------------------------------- friends  (Friendship, FriendRequest)
ANABELLA_FRIENDS = [
    "u_steph", "u_lily", "u_michael", "u_streak", "u_amanda", "u_brittney",
    "u_diego", "u_fred", "u_greg", "u_haley", "u_paaramita", "u_rachel",
    "u_sammy", "u_ted", "u_umed", "u_jade", "u_riley", "u_sophia", "u_tim",
    "u_aaron",
]  # 20 people, as on the Friends List screen
TEAM = ["u_anabella", "u_steph", "u_lily", "u_michael", "u_streak"]
OTHER_FRIENDS = [f for f in ANABELLA_FRIENDS if f not in TEAM]

edges = {}  # (a, b) sorted -> (friendship_status, created_at)


def befriend(a, b, since=None, status="friends"):
    key = tuple(sorted((a, b)))
    if since is None:
        since = max(CREATED[a], CREATED[b]) + timedelta(days=random.randint(1, 30), hours=random.randint(0, 12))
    edges[key] = (status, since)


for friend in ANABELLA_FRIENDS:
    befriend("u_anabella", friend)
for a, b in combinations(TEAM, 2):
    befriend(a, b)
for member in TEAM[1:]:
    for friend in random.sample(OTHER_FRIENDS, 3):
        befriend(member, friend)
befriend("u_steph", "u_jen")
befriend("u_steph", "u_kyle")
befriend("u_abigail", "u_michael")
# Anabella removed Jimmy S as a friend; he still shows up in "From Your Contacts"
befriend("u_anabella", "u_jimmy", status="removed")

friend_requests = {
    # waiting for Anabella to accept or decline
    "u_jen_u_anabella": {"sender_id": "u_jen", "recipient_id": "u_anabella",
                         "request_status": "pending", "created_at": ts(rel(hours=-3))},
    # Anabella tapped Add on Kyle (People You Know); he hasn't answered yet
    "u_anabella_u_kyle": {"sender_id": "u_anabella", "recipient_id": "u_kyle",
                          "request_status": "pending", "created_at": ts(rel(days=-1, hours=-2))},
    "u_sharon_u_lily": {"sender_id": "u_sharon", "recipient_id": "u_lily",
                        "request_status": "accepted", "created_at": ts(rel(days=-200)),
                        "responded_at": ts(rel(days=-199, hours=-20))},
    "u_kate_u_michael": {"sender_id": "u_kate", "recipient_id": "u_michael",
                         "request_status": "declined", "created_at": ts(rel(days=-20)),
                         "responded_at": ts(rel(days=-19))},
}
befriend("u_sharon", "u_lily", since=parse(friend_requests["u_sharon_u_lily"]["responded_at"]))

friends_by_user = {}
for (a, b), (status, since) in sorted(edges.items()):
    for me, other in ((a, b), (b, a)):
        friends_by_user.setdefault(me, {})[other] = {
            "user_id": me,
            "friend_id": other,
            "friendship_status": status,
            "created_at": ts(since),
        }

# ---------------------------------------------------------------- quest bank
BANK = [
    ("Take a photo with the tallest person in the room", ["party"], True),
    ("Take a photo of something blue", ["party", "travel"], True),
    ("Take a photo of a statue", ["travel"], True),
    ("Take a photo of the best view you can find", ["travel"], True),
    ("Take a group selfie with everyone in it", ["party", "travel"], True),
    ("Take a photo of someone mid-laugh", ["party", "travel"], False),
    ("Take a photo of a dog (ask the owner first!)", ["party", "travel"], True),
    ("Take a photo of the snack table", ["party"], True),
    ("Take a photo of matching outfits", ["party"], True),
    ("Take the most dramatic photo you can", ["party"], False),
    ("Take a photo of a street sign in another language", ["travel"], True),
    ("Take a photo of the best food you've had today", ["travel"], True),
    ("Take a photo of a hidden detail most people miss", ["travel"], False),
    ("Take a photo of someone dancing", ["party"], True),
    ("Take a photo that sums up today", ["party", "travel"], False),
    ("Take a photo with a sunset in it", ["travel"], True),
]
quest_bank = {
    f"qb_{i:02d}": {"prompt": p, "modes": m, "checkable": c}
    for i, (p, m, c) in enumerate(BANK, start=1)
}

# ---------------------------------------------------------------- helpers for groups
VERDICTS = {
    "Take a photo with the tallest person in the room": [
        (True, 0.88, "A much taller person stands at the center of the group.", ["people", "indoors", "group photo"]),
        (True, 0.81, "One person clearly towers over everyone else in the frame.", ["people", "party", "indoors"]),
        (False, 0.72, "Everyone in the photo looks about the same height.", ["people", "selfie", "indoors"]),
    ],
    "Take a photo of something blue": [
        (True, 0.97, "A bright blue mug fills most of the frame.", ["blue", "mug", "table"]),
        (True, 0.93, "The blue door is the clear subject of the photo.", ["blue", "door", "street"]),
        (False, 0.84, "The main subject is green, not blue.", ["plant", "green", "window"]),
    ],
    "Take a photo of a statue": [
        (True, 0.95, "A bronze statue is the main subject of the photo.", ["statue", "bronze", "park"]),
        (True, 0.9, "A marble statue is visible behind the group.", ["statue", "marble", "people"]),
    ],
    "Take a photo of the best gelato you can find": [
        (True, 0.96, "Two scoops of gelato are front and center.", ["gelato", "dessert", "cone"]),
        (True, 0.89, "A gelato display case fills the frame.", ["gelato", "shop", "display"]),
    ],
    "Take a photo of a dog (ask the owner first!)": [
        (True, 0.98, "A small terrier is looking straight at the camera.", ["dog", "terrier", "sidewalk"]),
        (False, 0.83, "There's a cat in the photo, not a dog.", ["cat", "window", "street"]),
    ],
    "Take a photo of the snack table": [
        (True, 0.92, "A table full of snacks and drinks is the main subject.", ["food", "table", "party"]),
    ],
    "Take a photo of something orange": [
        (True, 0.91, "A pile of orange pumpkins fills the frame.", ["orange", "pumpkin", "autumn"]),
        (True, 0.86, "An orange sweater is the brightest thing in the photo.", ["orange", "sweater", "people"]),
    ],
    "Take a photo with a sunset in it": [
        (True, 0.94, "The sun is setting over the water behind the group.", ["sunset", "beach", "people"]),
        (False, 0.77, "The photo was taken in full daylight with no sunset visible.", ["beach", "sand", "daytime"]),
    ],
}


def verdict_for(prompt: str, k: int):
    options = VERDICTS[prompt]
    return options[k % len(options)]


def make_quests(prompts_and_windows, source):
    quests = {}
    for i, (prompt, checkable, starts, ends) in enumerate(prompts_and_windows, start=1):
        quests[f"q_{i:02d}"] = {
            "prompt": prompt,
            "checkable": checkable,
            "order": i,
            "starts_at": ts(starts),
            "ends_at": ts(ends),
            "source": source,
        }
    return quests


def make_photos(gid, photographers, start, end, count, quests):
    """Spread `count` photos between start and end. Photos taken while a quest
    is running answer it about 75% of the time; checkable quests get a verdict."""
    photos = {}
    span = (end - start).total_seconds()
    checks_so_far = {}
    for i in range(count):
        taken = start + timedelta(seconds=span * (i + 0.5) / count + random.randint(-240, 240))
        pid = f"p_{i + 1:03d}"
        doc = {
            "photo_asset": f"groups/{gid}/photos/{pid}.jpg",
            "group_id": gid,
            "photographer_id": photographers[i % len(photographers)],
            "captured_at": ts(taken),
        }
        for qid, quest in quests.items():
            if parse(quest["starts_at"]) <= taken <= parse(quest["ends_at"]) and random.random() < 0.75:
                doc["quest_id"] = qid
                doc["quest_prompt"] = quest["prompt"]
                if quest["checkable"]:
                    k = checks_so_far.get(qid, 0)
                    checks_so_far[qid] = k + 1
                    done, confidence, reason, tags = verdict_for(quest["prompt"], k)
                    doc["quest_check"] = {
                        "completed": done,
                        "confidence": confidence,
                        "reason": reason,
                        "tags": tags,
                        "model": MODEL,
                        "checked_at": ts(taken + timedelta(seconds=4)),
                    }
                break
        photos[pid] = doc
    return photos


def make_members(gid, member_ids, created, creator, joined_late=None, left=None):
    """groups/{gid}/members/{userId}: everyone joins within the first hour;
    `left` maps user -> (joined_at, left_at) for people who left the group."""
    members = {}
    for i, uid in enumerate(member_ids):
        joined = created if uid == creator else created + timedelta(minutes=6 + 7 * i)
        if joined_late and uid in joined_late:
            joined = joined_late[uid]
        members[uid] = {"group_id": gid, "user_id": uid, "membership_status": "active", "joined_at": ts(joined)}
    for uid, (joined, left_at) in (left or {}).items():
        members[uid] = {"group_id": gid, "user_id": uid, "membership_status": "left",
                        "joined_at": ts(joined), "left_at": ts(left_at)}
    return dict(sorted(members.items()))


groups = {}
subcollections = []  # (path, docs) under groups/


def add_group(gid, doc, members, quests, photos):
    doc["photo_count"] = len(photos)
    groups[gid] = doc
    subcollections.append((f"groups/{gid}/members", members))
    subcollections.append((f"groups/{gid}/quests", quests))
    if photos:
        subcollections.append((f"groups/{gid}/photos", photos))


# ---------------------------------------------------------------- The Axolotls (active, photos locked)
ax_members = ["u_steph", "u_lily", "u_anabella", "u_michael", "u_streak"]
ax_created = rel(hours=-8)
ax_quests = make_quests([
    ("Take a photo with the tallest person in the room", True, rel(hours=-7), rel(hours=-5)),
    ("Take a photo of something blue", True, rel(hours=-4), rel(hours=-2)),
    ("Take a photo of a statue", True, rel(hours=-1), rel(hours=1)),       # current: "1 hr remaining!"
    ("Take a photo of the best view you can find", True, rel(hours=3), rel(hours=5)),
    ("Take a group selfie with everyone in it", True, rel(hours=8), rel(hours=10)),
], source="bank")
ax_photos = make_photos("g_axolotls", ax_members, ax_created + timedelta(minutes=10), rel(minutes=-5), 30, ax_quests)
add_group("g_axolotls", {
    "group_name": "The Axolotls",
    "description": "The best group of people ever.",
    "mode": "travel",
    "group_icon": "groups/g_axolotls/icon.png",
    "creator_id": "u_steph",
    "member_ids": ax_members,
    "invite_code": "123456",
    "created_at": ts(ax_created),
    "event_end_at": ts(rel(hours=16)),  # "Photos will reveal in 16 hours"
}, make_members("g_axolotls", ax_members, ax_created, "u_steph",
                joined_late={"u_lily": ax_created + timedelta(minutes=12)}),
    ax_quests, ax_photos)

# ---------------------------------------------------------------- Party Animals (active, Anabella has a pending invitation)
pa_members = ["u_steph", "u_jen", "u_kyle"]
pa_created = rel(hours=-2)
pa_quests = make_quests([
    ("Take a photo of the snack table", True, rel(hours=-1), rel(hours=1)),
    ("Take the most dramatic photo you can", False, rel(hours=2), rel(hours=4)),
    ("Take a photo of someone dancing", True, rel(hours=5), rel(hours=7)),
], source="gemini")
add_group("g_party_animals", {
    "group_name": "Party Animals",
    "description": "Steph's birthday party! Dress code: animal print.",
    "mode": "party",
    "creator_id": "u_steph",
    "member_ids": pa_members,
    "invite_code": "482913",
    "created_at": ts(pa_created),
    "event_end_at": ts(rel(hours=10)),
}, make_members("g_party_animals", pa_members, pa_created, "u_steph"), pa_quests, {})

# ---------------------------------------------------------------- Italy Pals!! (archived, revealed, guessing game played)
it_members = ["u_anabella", "u_steph", "u_lily", "u_michael", "u_streak",
              "u_amanda", "u_diego", "u_greg", "u_haley", "u_jen", "u_sharon"]  # Anabella + 10 friends
it_end = datetime(2026, 6, 21, 2, 0, tzinfo=timezone.utc)
it_start = it_end - timedelta(days=6)
it_quests = make_quests([
    ("Take a photo of a statue", True, it_start + timedelta(days=1, hours=2), it_start + timedelta(days=1, hours=6)),
    ("Take a photo of the best gelato you can find", True, it_start + timedelta(days=2, hours=4), it_start + timedelta(days=2, hours=8)),
    ("Take a photo of a dog (ask the owner first!)", True, it_start + timedelta(days=3, hours=1), it_start + timedelta(days=3, hours=5)),
    ("Take a photo of someone mid-laugh", False, it_start + timedelta(days=4, hours=3), it_start + timedelta(days=4, hours=7)),
], source="gemini")
it_photos = make_photos("g_italy", it_members, it_start + timedelta(hours=6), it_end - timedelta(hours=2), 126, it_quests)
add_group("g_italy", {
    "group_name": "Italy Pals!!",
    "description": "Rome → Florence → Venice. Six days, eleven people, one group chat.",
    "mode": "travel",
    "creator_id": "u_anabella",
    "member_ids": it_members,
    "invite_code": "305117",
    "created_at": ts(it_start - timedelta(days=2)),
    "event_end_at": ts(it_end),
    "cover_photo": "groups/g_italy/photos/p_001.jpg",
}, make_members("g_italy", it_members, it_start - timedelta(days=2), "u_anabella"), it_quests, it_photos)

# Guessing game. Players guess who took photos shot by members who aren't playing.
players = ["u_anabella", "u_steph", "u_lily", "u_michael", "u_streak"]
not_playing = [pid for pid, p in it_photos.items() if p["photographer_id"] not in players]
# prefer photos that answered a quest (they make better rounds)
quest_shots = [pid for pid in not_playing if "quest_id" in it_photos[pid]]
round_pool = quest_shots + [pid for pid in not_playing if pid not in quest_shots]


def make_rounds(photo_ids):
    rounds = []
    for pid in photo_ids:
        taker = it_photos[pid]["photographer_id"]
        decoys = random.sample([m for m in it_members if m != taker], 3)
        candidates = decoys + [taker]
        random.shuffle(candidates)
        rounds.append({"photo_id": pid, "candidate_ids": candidates})
    return rounds


game1_rounds = make_rounds(sorted(round_pool[:5]))
game2_rounds = make_rounds(sorted(round_pool[5:10]))
game_start = it_end + timedelta(hours=15)  # the next morning
correct_needed = {"u_anabella": 5, "u_steph": 4, "u_lily": 3, "u_michael": 2, "u_streak": 1}  # Leaderboard order
guesses = {}
for r, rnd in enumerate(game1_rounds):
    taker = it_photos[rnd["photo_id"]]["photographer_id"]
    for j, uid in enumerate(players):
        correct = r < correct_needed[uid]
        pick = taker if correct else next(c for c in rnd["candidate_ids"] if c not in (taker, uid))
        guesses[f"{r}_{uid}"] = {
            "game_session_id": "game_1",
            "user_id": uid,
            "round": r,
            "photo_id": rnd["photo_id"],
            "selected_user_id": pick,
            "is_correct": pick == taker,
            "answered_at": ts(game_start + timedelta(seconds=40 + r * 45 + j * 3)),
        }
game_sessions = {
    "game_1": {
        "group_id": "g_italy",
        "host_id": "u_anabella",
        "participant_ids": players,
        "ready_ids": players,
        "game_status": "finished",
        "rounds": game1_rounds,
        "current_round": len(game1_rounds) - 1,
        "created_at": ts(game_start),
        "started_at": ts(game_start + timedelta(seconds=30)),
        "finished_at": ts(game_start + timedelta(seconds=40 + len(game1_rounds) * 45)),
    },
    # "Play Again" from the Leaderboard: waiting in Game Prep, 2 of 5 players ready
    "game_2": {
        "group_id": "g_italy",
        "host_id": "u_anabella",
        "participant_ids": players,
        "ready_ids": ["u_anabella", "u_steph"],
        "game_status": "lobby",
        "rounds": game2_rounds,
        "current_round": 0,
        "created_at": ts(rel(minutes=-10)),
    },
}
first, second = game1_rounds[0]["photo_id"], game1_rounds[1]["photo_id"]
first_taker = NAME[it_photos[first]["photographer_id"]]
comments = {
    f"groups/g_italy/photos/{first}/comments": {
        "c_01": {"author_id": "u_michael", "author_name": "Michael", "text": "Golden hour in Rome!!",
                 "created_at": ts(game_start + timedelta(minutes=20))},
        "c_02": {"author_id": "u_anabella", "author_name": "Anabella",
                 "text": f"I knew this was {first_taker}'s the second I saw it",
                 "created_at": ts(game_start + timedelta(minutes=21))},
    },
    f"groups/g_italy/photos/{second}/comments": {
        "c_01": {"author_id": "u_lily", "author_name": "Lily", "text": "Best day of the whole trip",
                 "created_at": ts(game_start + timedelta(minutes=12))},
        "c_02": {"author_id": "u_steph", "author_name": "Steph", "text": "We got lost for an hour finding this place",
                 "created_at": ts(game_start + timedelta(minutes=14))},
    },
}

# ---------------------------------------------------------------- Friendsgiving (archived; Jade left the group)
fg_members = ["u_anabella", "u_steph", "u_lily", "u_michael", "u_brittney", "u_fred", "u_paaramita", "u_rachel", "u_kyle"]
fg_end = datetime(2025, 11, 28, 5, 0, tzinfo=timezone.utc)
fg_start = fg_end - timedelta(hours=9)
fg_created = fg_start - timedelta(days=3)
fg_quests = make_quests([
    ("Take a photo of the snack table", True, fg_start + timedelta(hours=1), fg_start + timedelta(hours=3)),
    ("Take a photo of something orange", True, fg_start + timedelta(hours=4), fg_start + timedelta(hours=6)),
    ("Take the most dramatic photo you can", False, fg_start + timedelta(hours=6, minutes=30), fg_start + timedelta(hours=8)),
], source="bank")
fg_photos = make_photos("g_friendsgiving", fg_members, fg_start + timedelta(minutes=20), fg_end - timedelta(minutes=30), 69, fg_quests)
add_group("g_friendsgiving", {
    "group_name": "Friendsgiving",
    "description": "Potluck at Lily's. Bring a dish and a container for leftovers.",
    "mode": "party",
    "creator_id": "u_lily",
    "member_ids": fg_members,
    "invite_code": "771204",
    "created_at": ts(fg_created),
    "event_end_at": ts(fg_end),
    "cover_photo": "groups/g_friendsgiving/photos/p_001.jpg",
}, make_members("g_friendsgiving", fg_members, fg_created, "u_lily",
                left={"u_jade": (fg_created + timedelta(hours=2), fg_end + timedelta(days=30))}),
    fg_quests, fg_photos)

# ---------------------------------------------------------------- Beach Day (archived, "1 year ago today")
bd_members = ["u_anabella", "u_steph", "u_lily", "u_sammy", "u_ted", "u_umed", "u_haley"]
bd_end = REF - timedelta(days=365)  # exactly one year before "now" -> "1 year ago today"
bd_start = bd_end - timedelta(hours=8)
bd_created = bd_start - timedelta(days=1)
bd_quests = make_quests([
    ("Take a photo of something blue", True, bd_start + timedelta(hours=1), bd_start + timedelta(hours=3)),
    ("Take a photo of a dog (ask the owner first!)", True, bd_start + timedelta(hours=3, minutes=30), bd_start + timedelta(hours=5)),
    ("Take a photo with a sunset in it", True, bd_start + timedelta(hours=6), bd_start + timedelta(hours=8)),
], source="bank")
bd_photos = make_photos("g_beach", bd_members, bd_start + timedelta(minutes=15), bd_end - timedelta(minutes=10), 54, bd_quests)
add_group("g_beach", {
    "group_name": "Beach Day",
    "description": "Presque Isle trip before it gets cold.",
    "mode": "travel",
    "creator_id": "u_anabella",
    "member_ids": bd_members,
    "invite_code": "640028",
    "created_at": ts(bd_created),
    "event_end_at": ts(bd_end),
    "cover_photo": "groups/g_beach/photos/p_001.jpg",
}, make_members("g_beach", bd_members, bd_created, "u_anabella"), bd_quests, bd_photos)

# ---------------------------------------------------------------- group_invitations, invite_codes
group_invitations = {
    # Home: "Steph is inviting you to join Party Animals"
    "g_party_animals_u_anabella": {
        "group_id": "g_party_animals", "group_name": "Party Animals",
        "inviter_id": "u_steph", "inviter_name": "Steph",
        "recipient_id": "u_anabella", "invite_status": "pending",
        "created_at": ts(rel(hours=-1, minutes=-30)),
    },
    "g_party_animals_u_michael": {
        "group_id": "g_party_animals", "group_name": "Party Animals",
        "inviter_id": "u_kyle", "inviter_name": "Kyle",
        "recipient_id": "u_michael", "invite_status": "declined",
        "created_at": ts(rel(hours=-1, minutes=-20)),
    },
    "g_axolotls_u_lily": {
        "group_id": "g_axolotls", "group_name": "The Axolotls",
        "inviter_id": "u_steph", "inviter_name": "Steph",
        "recipient_id": "u_lily", "invite_status": "accepted",
        "created_at": ts(ax_created + timedelta(minutes=5)),
    },
}
invite_codes = {g["invite_code"]: {"group_id": gid, "created_at": g["created_at"]} for gid, g in groups.items()}

# ---------------------------------------------------------------- assemble
collections.append(("users", users))
for uid in sorted(friends_by_user):
    collections.append((f"users/{uid}/friends", dict(sorted(friends_by_user[uid].items()))))
collections.append(("usernames", dict(sorted(usernames.items()))))
collections.append(("friend_requests", friend_requests))
collections.append(("groups", groups))
collections.extend(subcollections)
for path, docs in comments.items():
    collections.append((path, docs))
collections.append(("groups/g_italy/game_sessions", game_sessions))
collections.append(("groups/g_italy/game_sessions/game_1/guesses", guesses))
collections.append(("group_invitations", group_invitations))
collections.append(("invite_codes", invite_codes))
collections.append(("quest_bank", quest_bank))

seed = {
    "referenceNow": ts(REF),
    "collections": [{"path": p, "documents": d} for p, d in collections],
}

out = sys.argv[1] if len(sys.argv) > 1 else "seed.json"
with open(out, "w", encoding="utf-8") as f:
    json.dump(seed, f, indent=2, ensure_ascii=False)
    f.write("\n")

# summary by collection (subcollections of different parents counted together)
summary = {}
for path, docs in collections:
    parts = path.split("/")
    template = "/".join("*" if i % 2 else part for i, part in enumerate(parts))
    paths, count = summary.get(template, (0, 0))
    summary[template] = (paths + 1, count + len(docs))
total = sum(len(d) for _, d in collections)
print(f"wrote {out}: {len(collections)} collection paths, {total} documents")
for template, (paths, count) in summary.items():
    print(f"  {template}: {count}" + (f" (in {paths} collections)" if paths > 1 else ""))
print("game_1 rounds:", [r["photo_id"] for r in game1_rounds], "comments on", first, second)
