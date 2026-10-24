import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_controller.dart';
import 'app_database.dart';

/// The signed-in account's own database file, `accounts/<user id>.db`
/// (docs/10, D5). Another account on the same phone opens another file, so
/// one shop's records can never show on another's screens. Read only while
/// someone is signed in; the router keeps every other screen away.
final databaseProvider = Provider<AppDatabase>((ref) {
  final userId = ref.watch(
    sessionProvider.select((s) => s.value?.account.userId),
  );
  if (userId == null) {
    throw StateError('databaseProvider read with nobody signed in');
  }
  final store = ref.watch(accountStoreProvider).requireValue;
  final path = store.databasePath(userId);
  final db = AppDatabase(
    driftDatabase(
      name: userId,
      native: DriftNativeOptions(
        databasePath: () async {
          await File(path).parent.create(recursive: true);
          return path;
        },
      ),
    ),
  );
  ref.onDispose(db.close);
  return db;
});
