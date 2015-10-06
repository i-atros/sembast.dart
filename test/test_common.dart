library sembast.test.test_common;

// basically same as the io runner but with extra output
import 'package:sembast/src/memory/memory_file_system.dart';
import 'package:sembast/sembast.dart';
import 'dart:async';
import 'package:sembast/src/file_system.dart';
import 'package:dev_test/test.dart';
export 'package:dev_test/test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/src/sembast_fs.dart';
import 'package:path/path.dart';
import 'dart:convert';

// For test in memory
DatabaseTestContext get memoryDatabaseContext =>
    new DatabaseTestContext()..factory = memoryDatabaseFactory;
FsDatabaseTestContext get memoryFsDatabaseContext => new FsDatabaseTestContext()
  ..factory = new FsDatabaseFactory(memoryFileSystem);

class FsDatabaseTestContext extends DatabaseTestContext {
  FileSystem get fs => (factory as FsDatabaseFactory).fs;
  String get dbPath => join(fs.currentDirectory.path, super.dbPath);
}

class DatabaseTestContext {
  DatabaseFactory factory;

  String get dbPath => joinAll(testDescriptions) + ".db";
}

// FileSystem context
class FileSystemTestContext {
  FileSystem fs;
  String get outPath => fs.currentDirectory.path;
}

FileSystemTestContext get memoryFileSystemContext =>
    new FileSystemTestContext()..fs = memoryFileSystem;

Future<Database> setupForTest(DatabaseTestContext ctx) async {
  DatabaseFactory factory = ctx.factory;
  String dbPath = ctx.dbPath;
  await factory.deleteDatabase(dbPath);
  return factory.openDatabase(dbPath);
}

Future<List<Record>> recordStreamToList(Stream<Record> stream) {
  List<Record> records = [];
  return stream.listen((Record record) {
    records.add(record);
  }).asFuture().then((_) => records);
}

///
/// helper to read a list of string (lines)
///
Future<List<String>> readContent(FileSystem fs, String filePath) {
  List<String> content = [];
  return fs
      .newFile(filePath)
      .openRead()
      .transform(UTF8.decoder)
      .transform(new LineSplitter())
      .listen((String line) {
    content.add(line);
  }).asFuture(content);
}

Future writeContent(FileSystem fs, String filePath, List<String> lines) async {
  File file = fs.newFile(filePath);
  await file.create(recursive: true);
  IOSink sink = file.openWrite(mode: FileMode.WRITE);
  for (String line in lines) {
    sink.writeln(line);
  }
  await sink.close();
}

DatabaseExportStat getDatabaseExportStat(Database db) {
  return new DatabaseExportStat.fromJson(db.toJson()["exportStat"]);
}

devPrintJson(Map json) {
  print(const JsonEncoder.withIndent("  ").convert(json));
}
