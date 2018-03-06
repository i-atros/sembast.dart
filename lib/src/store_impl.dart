import 'dart:async';
import 'package:sembast/sembast.dart';
import 'database_impl.dart';
import 'package:sembast/src/finder.dart';
import 'package:sembast/src/record_impl.dart';

class SembastStore implements Store {
  final SembastDatabase database;

  ///
  /// Store name
  ///
  @override
  final String name;
  // for key generation
  int _lastIntKey = 0;

  Map<dynamic, Record> recordMap = new Map();
  Map<dynamic, Record> txnRecords;

  bool get isInTransaction => database.isInTransaction;

  SembastStore(this.database, this.name);

  ///
  /// return the key
  ///
  Future put(var value, [var key]) {
    return database.inTransaction(() {
      Record record = new SembastRecord.copy(this, key, value, false);

      txnPutRecord(record);
      if (database.LOGV) {
        SembastDatabase.logger
            .fine("${database.currentTransaction} put ${record}");
      }
      return record.key;
    });
  }

  ///
  /// stream all the records
  ///
  @override
  Stream<Record> get records {
    StreamController<Record> ctlr = new StreamController();
    inTransaction(() {
      _forEachRecords(null, (Record record) {
        ctlr.add(record);
      });
    }).then((_) {
      ctlr.close();
    });
    return ctlr.stream;
  }

  _forEachRecords(Filter filter, void action(Record record)) {
// handle record in transaction first
    if (isInTransaction && txnRecords != null) {
      txnRecords.values.forEach((Record record) {
        if (Filter.matchRecord(filter, record)) {
          action(record);
        }
      });
    }

    // then the regular unless already in transaction
    recordMap.values.forEach((Record record) {
      if (isInTransaction && txnRecords != null) {
        if (txnRecords.keys.contains(record.key)) {
          // already handled
          return;
        }
      }
      if (Filter.matchRecord(filter, record)) {
        action(record);
      }
    });
  }

  ///
  /// find the first matching record
  ///
  @override
  Future<Record> findRecord(Finder finder) {
    if ((finder as SembastFinder).limit != 1) {
      finder = (finder as SembastFinder).clone(limit: 1);
    }
    return findRecords(finder).then((List<Record> records) {
      if (records.isNotEmpty) {
        return records.first;
      }
      return null;
    });
  }

  ///
  /// find all records
  ///
  @override
  Future<List<Record>> findRecords(Finder finder) {
    return inTransaction(() {
      List<Record> result;

      result = [];

      _forEachRecords((finder as SembastFinder).filter, (Record record) {
        result.add(record);
      });

      // sort
      result.sort((Record record1, record2) =>
          (finder as SembastFinder).compare(record1, record2));
      return result;
    }) as Future<List<Record>>;
  }

  ///
  /// return true if it existed before
  ///
  bool setRecordInMemory(Record record) {
    SembastStore store = record.store as SembastStore;
    bool exists = store.recordMap[record.key] != null;
    if (record.deleted) {
      store.recordMap.remove(record.key);
    } else {
      store.recordMap[record.key] = record;
    }
    return exists;
  }

  void loadRecord(Record record) {
    var key = record.key;
    setRecordInMemory(record);
    // update for auto increment
    if (key is int) {
      if (key > _lastIntKey) {
        _lastIntKey = key;
      }
    }
  }

  ///
  /// execture the actions in a transaction
  /// use the current if any
  ///
  Future inTransaction(action()) {
    return database.inTransaction(action);
  }

  // Use Database.putRecord instead
  @deprecated
  Future<Record> putRecord(Record record) {
    return database.putRecord(record);
  }

  // Use Database.putRecords instead
  @deprecated
  Future<List<Record>> putRecords(List<Record> records) {
    return database.putRecords(records);
  }

  Record txnPutRecord(Record record) {
    assert(record.store == this);
    // auto-gen key if needed
    if (record.key == null) {
      (record as SembastRecord).key = ++_lastIntKey;
    } else {
      // update last int key in case auto gen is needed again
      var recordKey = record.key;
      if (recordKey is int) {
        int intKey = recordKey;
        if (intKey > _lastIntKey) {
          _lastIntKey = intKey;
        }
      }
    }

    // add to store transaction
    if (txnRecords == null) {
      txnRecords = new Map();
    }
    txnRecords[record.key] = record;

    return record;
  }

  // record must have been clone before
  @deprecated
  List<Record> txnPutRecords(List<Record> records) {
    return database.txnPutRecords(records);
  }

  Record _getRecord(var key) {
    var record;

    // look in current transaction
    if (isInTransaction) {
      if (txnRecords != null) {
        record = txnRecords[key];
      }
    }

    if (record == null) {
      record = recordMap[key];
    }
    if (database.LOGV) {
      SembastDatabase.logger
          .fine("${database.currentTransaction} get ${record} key ${key}");
    }
    return record as Record;
  }

  ///
  /// get a record by key
  ///
  @override
  Future<Record> getRecord(var key) {
    Record record = _getRecord(key);
    if (record != null) {
      if (record.deleted) {
        record = null;
      }
    }
    return new Future.value(record);
  }

  ///
  /// Get all records from a list of keys
  ///
  @override
  Future<List<Record>> getRecords(Iterable keys) {
    List<Record> records = [];

    for (var key in keys) {
      Record record = _getRecord(key);
      if (record != null) {
        if (!record.deleted) {
          records.add(record);
          ;
        }
      }
    }
    return new Future.value(records);
  }

  ///
  /// get a value from a key
  ///
  @override
  Future get(var key) {
    return getRecord(key).then((Record record) {
      if (record != null) {
        return record.value;
      }
      return null;
    });
  }

  ///
  /// count all records
  ///
  @override
  Future<int> count([Filter filter]) {
    return inTransaction(() {
      int count = 0;
      _forEachRecords(filter, (Record record) {
        count++;
      });
      return count;
    }) as Future<int>;
  }

  ///
  /// delete a record by key
  ///
  Future delete(var key) {
    return inTransaction(() {
      Record record = _getRecord(key);
      if (record == null) {
        return null;
      } else {
        // clone to keep the existing as is
        Record clone = (record as SembastRecord).clone();
        (clone as SembastRecord).deleted = true;
        txnPutRecord(clone);
        return key;
      }
    });
  }

  ///
  /// return the list of deleted keys
  ///
  @override
  Future deleteAll(Iterable keys) {
    return inTransaction(() {
      List<Record> updates = [];
      List deletedKeys = [];
      for (var key in keys) {
        Record record = _getRecord(key);
        if (record != null) {
          Record clone = (record as SembastRecord).clone();
          (clone as SembastRecord).deleted = true;
          updates.add(clone);
          deletedKeys.add(key);
        }
      }

      if (updates.isNotEmpty) {
        database.txnPutRecords(updates);
      }
      return deletedKeys;
    });
  }

  bool hasKey(var key) {
    return recordMap.containsKey(key);
  }

  void rollback() {
    // clear map;
    txnRecords = null;
  }

  ///
  /// debug json
  ///
  Map toJson() {
    Map map = {};
    if (name != null) {
      map["name"] = name;
    }
    if (recordMap != null) {
      map["count"] = recordMap.length;
    }
    return map;
  }

  @override
  String toString() {
    return "${name}";
  }

  ///
  /// delete all records in a store
  ///
  /// TODO: decide on return value
  ///
  @override
  Future clear() {
    return inTransaction(() {
      // first delete the one in transaction
      return new Future.sync(() {
        if (txnRecords != null) {
          return deleteAll(new List.from(txnRecords.keys, growable: false));
        }
      }).then((_) {
        Iterable keys = recordMap.keys;
        return deleteAll(new List.from(keys, growable: false));
      });
    });
  }
}