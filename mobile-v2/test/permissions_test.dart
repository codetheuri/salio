import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/session/permissions.dart';

// The phone's role table must equal the server's. Both compare against the
// same file; server-v2/internal/rbac/shared_vectors_test.go is the other half.
void main() {
  final vectors =
      jsonDecode(
            File('../testdata/shared/role_permissions.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  for (final role in Role.values) {
    test('${role.name} has the permissions the server grants', () {
      final want = (vectors[role.name] as List<dynamic>).cast<String>();
      expect(role.permissions.toList()..sort(), want);
    });
  }

  test('every permission is in the catalogue', () {
    final named = {
      for (final role in Role.values)
        ...(vectors[role.name] as List<dynamic>).cast<String>(),
    };
    expect(Permission.all, named);
  });
}
