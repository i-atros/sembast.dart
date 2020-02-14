@TestOn('browser')
library sembast_web.test.idb_io_simple_test;

import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';
import 'package:test/test.dart';

var testPath = '.dart_tool/sembast_web/databases';

Future main() async {
  var factory = databaseFactoryWeb;

  group('idb_native', () {
    test('doc', () async {
      // Declare our store (records are mapd, ids are ints)
      var store = intMapStoreFactory.store();
      var factory = databaseFactoryWeb;

      // Open the database
      var db = await factory.openDatabase('test');

      // Add a new record
      var key =
          await store.add(db, <String, dynamic>{'name': 'Table', 'price': 15});

      // Read the record
      var value = await store.record(key).get(db);

      // Print the value
      print(value);

      // Close the database
      await db.close();
    });

    test('open', () async {
      var store = StoreRef<String, String>.main();
      var record = store.record('key');
      await factory.deleteDatabase('test');
      var db = await factory.openDatabase('test');
      expect(await record.get(db), isNull);
      await record.put(db, 'value');
      expect(await record.get(db), 'value');
      await db.close();

      db = await factory.openDatabase('test');
      await record.put(db, 'value');
      expect(await record.get(db), 'value');
      await db.close();
    });
  });
}