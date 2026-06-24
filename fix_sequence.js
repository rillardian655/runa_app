// Fix the $sequence attribute issue in _console__metadata for teams collection
var appDb = db.getSiblingDB('appwrite');

// Find the teams metadata entry
var teamsMeta = appDb.getCollection('_console__metadata').findOne({name: 'teams'});
print('Teams metadata _id:', teamsMeta ? teamsMeta._id : 'NOT FOUND');

if (teamsMeta) {
  var attrs = JSON.parse(teamsMeta.attributes);
  print('Current attrs count:', attrs.length);
  
  // Check if $sequence already exists
  var hasSeq = attrs.filter(function(a){return a['$id'] === '$sequence';}).length > 0;
  print('Has $sequence:', hasSeq);
  
  if (!hasSeq) {
    // Add $sequence attribute
    attrs.push({
      '$id': '$sequence',
      'type': 'integer',
      'size': 0,
      'required': false,
      'signed': false,
      'array': false,
      'filters': [],
      'default': null,
      'format': ''
    });
    
    var r1 = appDb.getCollection('_console__metadata').updateOne(
      {name: 'teams'},
      {$set: {attributes: JSON.stringify(attrs)}}
    );
    print('Updated teams metadata:', r1.modifiedCount);
  }
}

// Also fix the teams collection - add $sequence field to the console team
var team = appDb.getCollection('_console_teams').findOne({_id: 'console'});
print('Team $sequence:', team ? team['$sequence'] : 'NOT FOUND');

if (team && !team['$sequence']) {
  var r2 = appDb.getCollection('_console_teams').updateOne(
    {_id: 'console'},
    {$set: {'$sequence': 1}}
  );
  print('Updated team $sequence:', r2.modifiedCount);
}

// Verify
var teamAfter = appDb.getCollection('_console_teams').findOne({_id: 'console'}, {'$sequence': 1, _id: 1});
print('Team after fix:', JSON.stringify(teamAfter));
