// Initialize the project database for runa-chat
// This creates the _metadata collection that Appwrite needs

var appDb = db.getSiblingDB('appwrite');

// Check what _metadata looks like in the console db
var consoleMeta = appDb.getCollection('_console__metadata').findOne({_id: 'keys'});
print('Console keys metadata sample:', JSON.stringify(consoleMeta ? {_id: consoleMeta._id, name: consoleMeta.name} : null));

// Now initialize database_db_main
var projDb = db.getSiblingDB('database_db_main');

// Create _metadata collection with required structure
var now = new Date();

// Insert a basic metadata entry to initialize the database
var r1 = projDb.getCollection('_metadata').insertOne({
  _id: 'init',
  name: 'init',
  _createdAt: now,
  _updatedAt: now
});
print('Metadata init:', r1.insertedId);

// Verify
var cols = projDb.getCollectionNames();
print('database_db_main collections after init:', JSON.stringify(cols));
