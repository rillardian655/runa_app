# App Version Update System

This document explains how to use the automatic version update notification system in Ru.na.

## Overview

The app now automatically checks for new versions when it starts and shows a popup dialog if an update is available. Users can choose to update immediately or later (unless it's a forced update).

## Features

- ✅ Automatic version checking on app startup
- ✅ Beautiful update dialog with version comparison
- ✅ Changelog display
- ✅ Optional forced updates
- ✅ Direct download link integration
- ✅ Platform-specific version management (Android, iOS, Web)

## Setup

### 1. Create the Database Table

Run the SQL migration file in your Supabase SQL Editor:

```bash
# File: supabase_migrations/20260618_add_app_versions_table.sql
```

Or manually create the table:

```sql
CREATE TABLE IF NOT EXISTS app_versions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
  version TEXT NOT NULL,
  download_url TEXT,
  changelog TEXT,
  force_update BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE app_versions ENABLE ROW LEVEL SECURITY;

-- Allow public read
CREATE POLICY "Allow public read access to app versions"
ON app_versions FOR SELECT
USING (true);

-- Allow service role to manage
CREATE POLICY "Allow service role to manage app versions"
ON app_versions FOR ALL
USING (auth.role() = 'service_role');
```

### 2. Add Initial Version

Insert the current version into the database:

```sql
INSERT INTO app_versions (platform, version, download_url, changelog, force_update)
VALUES (
  'android',
  '1.0.16',
  'https://github.com/yourusername/runa_app/releases/latest',
  '• Fixed calling crashes\n• Added version update notifications\n• Improved stability',
  false
);
```

## Managing Versions

### Adding a New Version

When you release a new version, add it to the database:

```sql
INSERT INTO app_versions (platform, version, download_url, changelog, force_update)
VALUES (
  'android',
  '1.0.17',
  'https://github.com/yourusername/runa_app/releases/download/v1.0.17/app-release.apk',
  '• New feature: Video calls\n• Bug fixes\n• Performance improvements',
  false  -- Set to true for critical updates
);
```

### Version Fields

- **platform**: `'android'`, `'ios'`, or `'web'`
- **version**: Semantic version string (e.g., `'1.0.17'`)
- **download_url**: Direct link to APK/App Store/website
- **changelog**: What's new in this version (supports newlines with `\n`)
- **force_update**: If `true`, users cannot dismiss the dialog

### Forcing Updates

For critical security fixes or breaking changes, set `force_update = true`:

```sql
INSERT INTO app_versions (platform, version, download_url, changelog, force_update)
VALUES (
  'android',
  '1.0.18',
  'https://github.com/yourusername/runa_app/releases/download/v1.0.18/app-release.apk',
  '• CRITICAL: Security vulnerability fixed\n• Please update immediately',
  true  -- Users cannot dismiss
);
```

## How It Works

### User Flow

1. **App starts** → Checks for updates in background
2. **Update available** → Shows dialog after 500ms delay
3. **User action**:
   - Click "Update Now" → Opens download URL
   - Click "Later" → Dismisses (if not forced)
   - Cannot dismiss if `force_update = true`

### Version Comparison

The system compares versions using semantic versioning:
- `1.0.15` < `1.0.16` ✅ Update available
- `1.0.16` = `1.0.16` ❌ No update
- `1.0.16` > `1.0.15` ❌ No update (user has newer)

### Update Dialog

The dialog shows:
- Current version vs Latest version
- Changelog (what's new)
- "Update Now" button (opens download URL)
- "Later" button (if not forced)

## Testing

### Test Update Detection

1. **Set a higher version in database**:
   ```sql
   INSERT INTO app_versions (platform, version, download_url, changelog)
   VALUES ('android', '99.0.0', 'https://example.com', 'Test update');
   ```

2. **Restart the app** → Should show update dialog

3. **Test forced update**:
   ```sql
   UPDATE app_versions SET force_update = true WHERE version = '99.0.0';
   ```

4. **Restart app** → Dialog should not be dismissible

### Test No Update

1. **Set current version in database**:
   ```sql
   INSERT INTO app_versions (platform, version)
   VALUES ('android', '1.0.15');  -- Same as app version
   ```

2. **Restart app** → No dialog should appear

## Updating pubspec.yaml

When you release a new version, update `pubspec.yaml`:

```yaml
version: 1.0.16+1  # version+build_number
```

Then rebuild and upload the APK.

## Download URL Options

### GitHub Releases (Recommended)

```
https://github.com/yourusername/runa_app/releases/download/v1.0.16/app-release.apk
```

### Direct File Hosting

```
https://yourserver.com/downloads/runa-v1.0.16.apk
```

### Google Play Store

```
https://play.google.com/store/apps/details?id=com.yourcompany.runa_app
```

### Latest Release (GitHub)

```
https://github.com/yourusername/runa_app/releases/latest
```

## Troubleshooting

### Update dialog not showing

1. Check if `app_versions` table exists
2. Verify there's a version higher than current app version
3. Check platform matches (`'android'`)
4. Check console logs for `[AppUpdate]` messages

### Download not working

1. Verify `download_url` is a valid URL
2. Test URL in browser
3. Check if URL requires authentication

### Version comparison issues

- Ensure versions follow semantic versioning: `MAJOR.MINOR.PATCH`
- Examples: `1.0.0`, `1.0.15`, `2.1.3`

## Advanced: Custom Update Logic

You can modify `app_update_service.dart` to:

- Check for updates periodically (not just on startup)
- Show different dialogs for major/minor/patch updates
- Add "Remind me later" with cooldown period
- Track update acceptance rates

## Example: Periodic Update Checks

Add to `main.dart`:

```dart
@override
void initState() {
  super.initState();
  _checkForUpdates();
  
  // Check every 6 hours
  Timer.periodic(const Duration(hours: 6), (_) {
    _checkForUpdates();
  });
}
```

## Security Notes

- The `app_versions` table is publicly readable (required for update checks)
- Only service role can insert/update versions (prevents tampering)
- Download URLs should use HTTPS
- Consider code signing for APKs

## Future Enhancements

Potential improvements:
- [ ] In-app APK download and installation
- [ ] Delta updates (only download changes)
- [ ] A/B testing for gradual rollouts
- [ ] Analytics on update acceptance
- [ ] Rollback mechanism
- [ ] Beta channel support

## Support

For issues or questions:
1. Check console logs for `[AppUpdate]` messages
2. Verify database table structure
3. Test with version `99.0.0` to force dialog
4. Check download URL is accessible

---

**Last Updated:** June 18, 2026  
**Current App Version:** 1.0.16
