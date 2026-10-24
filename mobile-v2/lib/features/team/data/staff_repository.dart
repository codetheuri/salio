import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';

/// The shop's people, cached on the phone so each entry can say who
/// recorded it, offline too. The list is read from the server and replaced
/// whole; nothing here is written on the phone.
class StaffRepository {
  final AppDatabase db;

  StaffRepository(this.db);

  /// Replaces the cache with the server's team list (`list-staff`).
  Future<void> refresh(ApiClient api) async {
    final list = (await api.get('/staff') as List<dynamic>)
        .cast<Map<String, dynamic>>();
    await db.transaction(() async {
      await db.delete(db.staffMembers).go();
      await db.batch(
        (b) => b.insertAll(db.staffMembers, [
          for (final u in list)
            StaffMembersCompanion.insert(
              id: u['id'] as String,
              name: u['name'] as String,
              role: u['role'] as String,
              isActive: u['is_active'] as bool? ?? true,
            ),
        ]),
      );
    });
  }

  /// Names by user id, kept up to date.
  Stream<Map<String, String>> watchNames() => db
      .select(db.staffMembers)
      .watch()
      .map((rows) => {for (final r in rows) r.id: r.name});
}
