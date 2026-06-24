// Clean up manually created team and project
var appDb = db.getSiblingDB('appwrite');

// Delete manually created team
var r1 = appDb.getCollection('_console_teams').deleteOne({_id: 'console'});
print('Deleted manual team:', r1.deletedCount);

// Delete manually created membership
var r2 = appDb.getCollection('_console_memberships').deleteOne({_id: 'membership-admin'});
print('Deleted manual membership:', r2.deletedCount);

// Delete the runa-chat project (will recreate via API)
var r3 = appDb.getCollection('_console_projects').deleteOne({_uid: 'runa-chat'});
print('Deleted runa-chat project:', r3.deletedCount);

// Remove memberships from user
var r4 = appDb.getCollection('_console_users').updateOne(
  {email: 'admin@runa.app'},
  {$set: {memberships: []}}
);
print('Cleared user memberships:', r4.modifiedCount);

// Verify
print('Teams remaining:', appDb.getCollection('_console_teams').countDocuments());
print('Projects remaining:', appDb.getCollection('_console_projects').countDocuments());
