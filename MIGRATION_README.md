# Firebase to Supabase User Migration

This script migrates user accounts from Firebase Authentication to your self-hosted Supabase instance.

## Prerequisites

1. **Node.js** installed (v18 or higher)
2. **Firebase Admin SDK key** - Download from Firebase Console
3. **Supabase credentials** - Already configured in `supabase_keys.txt`

## Step 1: Get Firebase Admin SDK Key

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **runaapp-cca6a**
3. Go to **Project Settings** → **Service Accounts**
4. Click **Generate new private key**
5. Download the JSON file
6. Rename it to `firebase-admin-key.json` and place it in this directory

## Step 2: Install Dependencies

```bash
npm install
```

## Step 3: Run Migration

```bash
npm run migrate
```

## What Gets Migrated

✅ **Migrated:**
- User email addresses
- Email verification status
- Display names (as usernames)
- Profile photos
- Account creation dates
- User metadata

❌ **NOT Migrated:**
- Passwords (Firebase passwords cannot be exported for security reasons)
- Phone numbers (if you had them)
- Custom claims (can be added manually if needed)

## After Migration

### 1. Notify Users About Password Reset

Since passwords cannot be migrated, users will need to reset their passwords. You can:

**Option A: Send bulk email**
```bash
# Use your email service to send a notification
Subject: Action Required - Reset Your Password for Ru.na App

Body:
We've upgraded our authentication system! To continue using your account, 
please reset your password by clicking the link below:

[Password Reset Link]

Your username and profile data remain the same.
```

**Option B: In-app notification**
Add a check in your app that detects migrated users and prompts them to reset their password.

### 2. Test the Migration

1. Try logging in with a migrated account (it will fail - expected)
2. Use "Forgot Password" to reset the password
3. Login with the new password
4. Verify all user data is intact

### 3. Clean Up (Optional)

After confirming all users have migrated successfully:

1. Remove Firebase dependencies from your app
2. Delete `firebase.json` and `firebase-messaging-sw.js`
3. Remove Firebase Admin SDK key file
4. Archive your Firebase project (or keep it for reference)

## Troubleshooting

### Error: Cannot find module './firebase-admin-key.json'
- Make sure you downloaded the Firebase Admin SDK key
- Rename it to `firebase-admin-key.json`
- Place it in the same directory as this script

### Error: User already exists
- The user was already migrated or created in Supabase
- This is normal and the script will skip them

### Error: Invalid API key
- Check your Supabase service key in `supabase_keys.txt`
- Make sure the Supabase server is running

## Support

If you encounter issues:
1. Check the console output for error messages
2. Verify your Firebase project ID is `runaapp-cca6a`
3. Ensure your Supabase instance is accessible at `https://supabase.vantageos.my.id`
