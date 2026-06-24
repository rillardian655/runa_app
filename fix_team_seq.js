// Fix: use aggregation pipeline to set $sequence on the team
// MongoDB doesn't allow $ prefix in regular update, need pipeline
var appDb = db.getSiblingDB('appwrite');

// Use replaceOne to set the full document including $sequence
var team = appDb.getCollection('_console_teams').findOne({_id: 'console'});
print('Current team:', JSON.stringify(team));

// Replace the document with $sequence added using replaceOne
var newTeam = {
  _id: team._id,
  _uid: team._uid,
  name: team.name,
  total: team.total,
  prefs: team.prefs,
  search: team.search,
  _permissions: team._permissions,
  _collection: team._collection,
  _createdAt: team._createdAt,
  _updatedAt: team._updatedAt
};

// Add $sequence using the pipeline update syntax
var r1 = appDb.getCollection('_console_teams').updateOne(
  {_id: 'console'},
  [{$addFields: {'$sequence': {$literal: 1}}}]
);
print('Pipeline update result:', JSON.stringify(r1));

// Verify
var teamAfter = appDb.getCollection('_console_teams').findOne({_id: 'console'});
print('Team after:', JSON.stringify(teamAfter));
