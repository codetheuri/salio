/// Permission names, matching server-v2's `internal/rbac`. Screens ask
/// `user.can(...)`, never the role's name (docs/10, §4.7), so that once the
/// server sends each user's list (backend B5) a role can change with no app
/// release.
abstract final class Permission {
  static const customersRead = 'customers.read';
  static const customersCreate = 'customers.create';
  static const customersUpdate = 'customers.update';
  static const customersDelete = 'customers.delete';
  static const customersCreditLimit = 'customers.credit_limit';

  static const transactionsRead = 'transactions.read';
  static const transactionsCreate = 'transactions.create';
  static const transactionsVoid = 'transactions.void';

  static const staffRead = 'staff.read';
  static const staffManage = 'staff.manage';

  static const businessRead = 'business.read';
  static const businessUpdate = 'business.update';

  static const reportsRead = 'reports.read';

  static const syncPull = 'sync.pull';
  static const syncPush = 'sync.push';

  static const salesRead = 'sales.read';
  static const salesCreate = 'sales.create';
  static const salesVoid = 'sales.void';

  static const stockRead = 'stock.read';
  static const stockRequest = 'stock.request';

  static const purchaseOrdersManage = 'purchase_orders.manage';

  static const suppliersRead = 'suppliers.read';
  static const suppliersManage = 'suppliers.manage';
  static const suppliersVoid = 'suppliers.void';

  /// Every permission. An owner holds all of them.
  static const all = {
    customersRead,
    customersCreate,
    customersUpdate,
    customersDelete,
    customersCreditLimit,
    transactionsRead,
    transactionsCreate,
    transactionsVoid,
    staffRead,
    staffManage,
    businessRead,
    businessUpdate,
    reportsRead,
    syncPull,
    syncPush,
    salesRead,
    salesCreate,
    salesVoid,
    stockRead,
    stockRequest,
    purchaseOrdersManage,
    suppliersRead,
    suppliersManage,
    suppliersVoid,
  };
}

/// The two roles. The server's `users.role` value is the name.
enum Role {
  owner,
  staff;

  /// What the role may do, until the server sends the list itself (B5).
  /// It mirrors `rbac.PermissionsFor`; testdata/shared/role_permissions.json
  /// holds the same table, and both the Go and the Dart tests compare
  /// against it, so a change on one side only fails CI.
  Set<String> get permissions => switch (this) {
    Role.owner => Permission.all,
    Role.staff => const {
      Permission.customersRead,
      Permission.customersCreate,
      Permission.customersUpdate,
      Permission.transactionsRead,
      Permission.transactionsCreate,
      Permission.staffRead,
      Permission.businessRead,
      Permission.reportsRead,
      Permission.syncPull,
      Permission.syncPush,
      Permission.salesRead,
      Permission.salesCreate,
      Permission.stockRead,
      Permission.stockRequest,
    },
  };
}
