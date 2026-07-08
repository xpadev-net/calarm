import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

Future<QueryExecutor> openAppDatabase(String name) async {
  try {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    await configureSqliteForPlatform();
    return NativeDatabase.createInBackground(
      File(p.join(documentsDirectory.path, name)),
    );
  } on MissingPluginException catch (error) {
    debugPrint('Falling back to in-memory app database: $error');
    return NativeDatabase.memory();
  }
}

Future<void> configureSqliteForPlatform() async {
  if (!Platform.isAndroid) {
    return;
  }

  try {
    final temporaryDirectory = await getTemporaryDirectory();
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    sqlite3.tempDirectory = temporaryDirectory.path;
  } on MissingPluginException catch (error) {
    debugPrint('Could not configure sqlite temp directory: $error');
  }
}
