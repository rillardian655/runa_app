var appDb = db.getSiblingDB('appwrite');
var proj = appDb.getCollection('_console_projects').findOne({_id: 'runa-chat'});
print('database field:', proj.database);
print('version:', proj.version);
print('teamId:', proj.teamId);
print('teamInternalId:', proj.teamInternalId);

var r1 = appDb.getCollection('_console_projects').updateOne(
  {_id: 'runa-chat'},
  {$set: {
    teamInternalId: 'console',
    database: 'runa-chat',
    version: '1.9.0'
  }}
);
print('Project updated:', r1.modifiedCount);
