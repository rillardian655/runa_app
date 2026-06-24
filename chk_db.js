var dbs = db.adminCommand({listDatabases:1}).databases.map(function(d){return d.name;});
print('All databases:', JSON.stringify(dbs));
var projDb = db.getSiblingDB('database_db_main');
var cols = projDb.getCollectionNames();
print('database_db_main collections count:', cols.length);
print('First 5:', JSON.stringify(cols.slice(0,5)));
