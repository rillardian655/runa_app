// Inspect the console metadata structure to understand what's needed
var appDb = db.getSiblingDB('appwrite');

// Get a sample metadata entry
var sample = appDb.getCollection('_console__metadata').findOne({_id: 'keys'});
if (sample) {
  print('KEYS META:', JSON.stringify(sample).substring(0, 500));
} else {
  print('No keys metadata found');
}

// Get all metadata entries
var allMeta = appDb.getCollection('_console__metadata').find({}, {_id:1, name:1}).toArray();
print('All metadata IDs:', JSON.stringify(allMeta.map(function(m){return m._id;})));

// Check what the sequence attribute looks like
var seqMeta = appDb.getCollection('_console__metadata').findOne({});
if (seqMeta && seqMeta.attributes) {
  var attrs = JSON.parse(seqMeta.attributes);
  var seqAttr = attrs.filter(function(a){return a['$id'] === '$sequence';});
  print('Sequence attr:', JSON.stringify(seqAttr));
}
