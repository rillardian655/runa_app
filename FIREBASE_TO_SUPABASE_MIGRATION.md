# Complete Firebase to Supabase Migration Guide for Ru.na App

## Current Status

✅ **Already Completed:**
- Supabase self-hosted instance running on NAT VPS (<SERVER_IP>)
- Database schema created (users, chats, messages, statuses, etc.)
- Storage buckets configured (avatars, chat_media, status_media, group_icons)
- App code migrated to use Supabase instead of Firebase
- Authentication working with Supabase Auth
- Real-time features working with Supabase Realtime

⏳ **Still Needed:**
- User account migration from Firebase Auth to Supabase Auth
- Password reset notification to users
- Cleanup of Firebase remnants

## Migration Steps

### Phase 1: User Account Migration

**Files Created:**
- `migrate_users.js` - Migration script
- `package.json` - Node.js dependencies
- `MIGRATION_README.md` - Detailed migration instructions

**Steps:**

1. **Get Firebase Admin SDK Key**
   ```
   Firebase Console → Project Settings → Service Accounts → Generate new private key
   Rename downloaded file to: firebase-admin-key.json
   ```

2. **Install Dependencies**
   ```bash
   npm install
   ```

3. **Run Migration**
   ```bash
   npm run migrate
   ```

**What Gets Migrated:**
- ✅ Email addresses
- ✅ Email verification status
- ✅ Display names → usernames
- ✅ Profile photos
- ✅ Account creation dates
- ✅ User metadata

**What Does NOT Get Migrated:**
- ❌ Passwords (security limitation - must be reset)
- ❌ Phone numbers (if any)
- ❌ Custom claims (can be added manually)

### Phase 2: Password Reset Strategy

Since Firebase passwords cannot be exported, users must reset their passwords.

**Option A: Email Notification (Recommended)**
```javascript
// After migration, send this email to all users:

Subject: Important: Reset Your Password for Ru.na App

Hi [Username],

We've upgraded our authentication system to improve security and performance.
To continue using your account, please reset your password:

[Link to password reset page in your app]

Your username, chat history, and all data remain the same.
Only your password needs to be reset.

Thank you,
Ru.na Team
```

**Option B: In-App Detection**
```dart
// Add this to your login screen
if (user.userMetadata['migrated_from_firebase'] == true) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Password Reset Required'),
      content: Text('We\'ve upgraded our system. Please reset your password to continue.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Reset Password'),
        ),
      ],
    ),
  );
}
```

### Phase 3: Testing

1. **Test Migration**
   - Pick a test user from Firebase
   - Run migration script
   - Try logging in (should fail - expected)
   - Use "Forgot Password" flow
   - Login with new password
   - Verify all data is intact

2. **Test Features**
   - ✅ Chat messages still visible
   - ✅ Status updates working
   - ✅ Friend connections intact
   - ✅ Profile data correct
   - ✅ Call functionality working

### Phase 4: Cleanup (After Migration Confirmed)

**Remove Firebase Files:**
```bash
rm firebase.json
rm web/firebase-messaging-sw.js
rm firebase-admin-key.json
rm -rf android/app/google-services.json
rm -rf ios/Runner/GoogleService-Info.plist
```

**Remove from pubspec.yaml:**
```yaml
# Remove these if still present:
# firebase_core
# firebase_auth
# firebase_messaging
# cloud_firestore
# firebase_storage
```

**Update .gitignore:**
```
# Remove Firebase references
# google-services.json
# GoogleService-Info.plist
```

## Database Schema Reference

Your Supabase database has these tables:

```sql
-- Users
users (id, uid, email, username, photo_url, bio, presence_status, last_seen, created_at, updated_at)

-- Friends
friends (id, user_id, friend_id, status, created_at, updated_at)

-- Chats
chats (id, participant1_id, participant2_id, last_message, last_message_at, created_at, updated_at)

-- Messages
messages (id, chat_id, sender_id, receiver_id, text, type, status, reply_to_id, reply_to_text, caption, media_url, media_size, created_at, updated_at)

-- Recent Chats
recent_chats (id, user_id, other_user_id, last_message, unread_count, updated_at)

-- Status
statuses (id, uid, username, photo_url, content, caption, type, bg_color, viewed_by, expires_at, created_at)

-- Groups
groups (id, name, creator_id, group_icon, last_message, last_message_at, created_at, updated_at)
group_members (id, group_id, user_id, joined_at)
group_messages (id, group_id, sender_id, text, type, created_at)

-- Calls
calls (id, caller_id, caller_name, receiver_id, status, offer, answer, created_at, updated_at)
call_candidates (id, call_id, role, candidate, sdp_mid, sdp_m_line_index, created_at)
```

## Storage Buckets

```
avatars/          - User profile pictures
chat_media/       - Images/videos sent in chats
status_media/     - Status update media
group_icons/      - Group chat icons
```

## Environment Variables

Already configured in `supabase_keys.txt`:
```
SUPABASE_URL=https://supabase.vantageos.my.id
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SUPABASE_SERVICE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
JWT_SECRET=***REDACTED-JWT-SECRET***
POSTGRES_PASSWORD=***REDACTED-PG-PASSWORD***
SUPABASE_DB_URL=postgresql://postgres:***REDACTED-PG-PASSWORD***@<SERVER_IP>:5432/postgres
```

## Troubleshooting

### Migration Script Errors

**Error: Cannot find module './firebase-admin-key.json'**
- Download Firebase Admin SDK key
- Rename to `firebase-admin-key.json`
- Place in project root

**Error: User already exists**
- User was already migrated
- Script will skip and continue

**Error: Invalid API key**
- Check Supabase service key
- Verify Supabase server is running

### App Issues After Migration

**Users can't login**
- Expected! They need to reset password
- Guide them to "Forgot Password" flow

**Chat history missing**
- Check if `chats` and `messages` tables have data
- Verify user IDs match between Firebase and Supabase

**Status updates not showing**
- Check `statuses` table
- Verify storage bucket permissions

## Rollback Plan

If migration fails, you can:

1. Keep Firebase Auth running
2. Revert app code to use Firebase
3. Users can continue using Firebase credentials

**To rollback:**
```bash
git checkout firebase-version  # If you have a Firebase branch
# OR
# Manually revert code changes
```

## Support Resources

- **Supabase Docs:** https://supabase.com/docs
- **Firebase Admin SDK:** https://firebase.google.com/docs/admin/setup
- **Migration Issues:** Check console output for specific errors

## Next Steps

1. ✅ Download Firebase Admin SDK key
2. ✅ Run `npm install`
3. ✅ Run `npm run migrate`
4. ✅ Test with a few users
5. ✅ Send password reset notifications
6. ✅ Monitor for issues
7. ✅ Clean up Firebase files after confirmation

---

**Migration Date:** June 18, 2026  
**Firebase Project:** runaapp-cca6a  
**Supabase Instance:** https://supabase.vantageos.my.id
