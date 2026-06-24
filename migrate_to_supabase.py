#!/usr/bin/env python3
"""
Runa App - Migration: Firebase Firestore → Supabase
Menggunakan Python stdlib saja (urllib), tanpa subprocess.
"""

import urllib.request
import urllib.error
import json
import time
import ssl

FIREBASE_PROJECT = "runaapp-cca6a"
FIRESTORE_BASE = f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT}/databases/(default)/documents"
SUPABASE_URL = "https://supabase.vantageos.my.id"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzQ5NjAwMDAwLCJleHAiOjE5MDczNjY0MDB9.mynZR8Jfv04jvitbB4MDFmN41j9kFsIw_xhjWBwIqNk"

CTX = ssl.create_default_context()

COMMON_HEADERS = {
    "apikey": SUPABASE_ANON_KEY,
    "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
    "Content-Type": "application/json",
    "User-Agent": "curl/7.88.1",
    "Accept": "*/*",
}

def fb_get(path, page_size=300):
    url = f"{FIRESTORE_BASE}/{path}?pageSize={page_size}"
    req = urllib.request.Request(url, headers={"User-Agent": "curl/7.88.1"})
    try:
        with urllib.request.urlopen(req, timeout=30, context=CTX) as r:
            return json.loads(r.read().decode())
    except Exception as e:
        return {}

def sb_get(endpoint):
    url = f"{SUPABASE_URL}/rest/v1/{endpoint}"
    req = urllib.request.Request(url, headers=COMMON_HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=30, context=CTX) as r:
            return json.loads(r.read().decode())
    except Exception as e:
        print(f"  [sb_get error] {endpoint}: {e}")
        return []

def sb_request(method, endpoint, data=None, extra_prefer=None):
    url = f"{SUPABASE_URL}/rest/v1/{endpoint}"
    body = json.dumps(data).encode() if data else None
    headers = dict(COMMON_HEADERS)
    prefer = "resolution=merge-duplicates,return=representation"
    if extra_prefer:
        prefer = extra_prefer
    headers["Prefer"] = prefer
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30, context=CTX) as r:
            resp = r.read().decode()
            return True, json.loads(resp) if resp else {}
    except urllib.error.HTTPError as e:
        return False, e.read().decode()
    except Exception as e:
        return False, str(e)

def get_str(fields, key):
    val = fields.get(key, {})
    for t in ["stringValue", "integerValue", "timestampValue"]:
        if t in val:
            return str(val[t])
    return ""

def fetch_all(collection):
    docs, page_size = [], 300
    url = f"{FIRESTORE_BASE}/{collection}?pageSize={page_size}"
    while url:
        req = urllib.request.Request(url, headers={"User-Agent": "curl/7.88.1"})
        try:
            with urllib.request.urlopen(req, timeout=30, context=CTX) as r:
                data = json.loads(r.read().decode())
        except Exception as e:
            print(f"  [ERROR fetch] {collection}: {e}")
            break
        docs.extend(data.get("documents", []))
        token = data.get("nextPageToken")
        url = f"{FIRESTORE_BASE}/{collection}?pageSize={page_size}&pageToken={token}" if token else None
    return docs

# ── MIGRATE USERS ──────────────────────────────────────

def migrate_users():
    print("\n" + "="*55)
    print("📋 MIGRASI PROFIL  (Firebase → Supabase)")
    print("="*55)

    docs = fetch_all("users")
    print(f"  Firebase : {len(docs)} users")

    existing = sb_get("users?select=uid,email")
    by_email = {u["email"]: u["uid"] for u in existing if u.get("email")}
    print(f"  Supabase : {len(existing)} users sudah ada")

    # hapus data test
    sb_request("DELETE", "users?uid=eq.test_123", extra_prefer="")

    ok = skip = fail = 0
    seen = set()

    for doc in docs:
        f = doc.get("fields", {})
        firebase_uid = doc.get("name", "").split("/")[-1]
        email      = get_str(f, "email")
        username   = get_str(f, "username") or (email.split("@")[0] if email else "")
        photo_url  = get_str(f, "photoUrl") or get_str(f, "photo_url") or ""
        bio        = get_str(f, "bio") or "Available"

        if not email:
            print(f"  [SKIP] {firebase_uid} — no email"); skip += 1; continue
        if email in seen:
            print(f"  [SKIP] {username} ({email}) — duplikat"); skip += 1; continue
        seen.add(email)

        if email in by_email:
            uid = by_email[email]
            ok2, res = sb_request("PATCH", f"users?uid=eq.{uid}", {
                "photo_url": photo_url, "bio": bio, "username": username
            })
            tag = "UPDATE"
        else:
            ok2, res = sb_request("POST", "users", {
                "uid": firebase_uid, "email": email,
                "username": username, "photo_url": photo_url,
                "bio": bio, "presence_status": "offline",
            })
            tag = "INSERT"

        if ok2:
            print(f"  ✅ [{tag}] {username} ({email})")
            ok += 1
        else:
            print(f"  ❌ [FAIL] {username}: {str(res)[:80]}")
            fail += 1

        time.sleep(0.1)

    print(f"\n  ✅ Berhasil: {ok}  ⏭️  Skip: {skip}  ❌ Gagal: {fail}")
    return ok

# ── MIGRATE FRIENDS ────────────────────────────────────

def migrate_friends():
    print("\n" + "="*55)
    print("👥 MIGRASI FRIENDS  (Firebase → Supabase)")
    print("="*55)

    # Ambil peta firebase_uid → supabase_uid dari Supabase
    sb_users = sb_get("users?select=uid,email")
    # Juga ambil semua user Firebase agar kita tahu firebase_uid → email
    fb_docs = fetch_all("users")
    fb_uid_to_email = {}
    for d in fb_docs:
        fuid = d.get("name","").split("/")[-1]
        email = get_str(d.get("fields", {}), "email")
        fb_uid_to_email[fuid] = email

    email_to_sb_uid = {u["email"]: u["uid"] for u in sb_users if u.get("email")}

    ok = skip = fail = 0

    for d in fb_docs:
        fuid = d.get("name","").split("/")[-1]
        owner_email = fb_uid_to_email.get(fuid, "")
        owner_sb_uid = email_to_sb_uid.get(owner_email)
        if not owner_sb_uid:
            continue

        friends_data = fb_get(f"users/{fuid}/friends", page_size=100)
        friend_docs = friends_data.get("documents", [])
        if not friend_docs:
            continue

        for fdoc in friend_docs:
            friend_fuid = fdoc.get("name","").split("/")[-1]
            friend_email = fb_uid_to_email.get(friend_fuid, "")
            friend_sb_uid = email_to_sb_uid.get(friend_email)
            if not friend_sb_uid:
                skip += 1; continue

            ff = fdoc.get("fields", {})
            status = get_str(ff, "status") or "accepted"

            # Cek apakah relasi sudah ada
            existing_rel = sb_get(f"friends?select=id&user_id=eq.{owner_sb_uid}&friend_id=eq.{friend_sb_uid}")
            if existing_rel:
                skip += 1; continue

            ok2, res = sb_request("POST", "friends", {
                "user_id": owner_sb_uid,
                "friend_id": friend_sb_uid,
                "status": status,
            })
            if ok2:
                ok += 1
            else:
                fail += 1

        time.sleep(0.05)

    print(f"  ✅ Berhasil: {ok}  ⏭️  Skip: {skip}  ❌ Gagal: {fail}")
    return ok

# ── MAIN ──────────────────────────────────────────────

if __name__ == "__main__":
    print("🚀 RUNA APP — MIGRASI FIREBASE → SUPABASE")
    print("="*55)

    u_count = migrate_users()
    f_count = migrate_friends()

    print("\n" + "="*55)
    print(f"🎉 SELESAI!")
    print(f"   Profil   : {u_count} berhasil")
    print(f"   Teman    : {f_count} relasi berhasil")
    print("="*55)
