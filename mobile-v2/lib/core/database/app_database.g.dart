// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CustomersTable extends Customers
    with TableInfo<$CustomersTable, CustomerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncState, int> syncState =
      GeneratedColumn<int>(
        'sync_state',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<SyncState>($CustomersTable.$convertersyncState);
  static const VerificationMeta _localVersionMeta = const VerificationMeta(
    'localVersion',
  );
  @override
  late final GeneratedColumn<int> localVersion = GeneratedColumn<int>(
    'local_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _creditLimitCentsMeta = const VerificationMeta(
    'creditLimitCents',
  );
  @override
  late final GeneratedColumn<int> creditLimitCents = GeneratedColumn<int>(
    'credit_limit_cents',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _changedFieldsMeta = const VerificationMeta(
    'changedFields',
  );
  @override
  late final GeneratedColumn<String> changedFields = GeneratedColumn<String>(
    'changed_fields',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    isDeleted,
    syncState,
    localVersion,
    name,
    phone,
    notes,
    createdBy,
    creditLimitCents,
    changedFields,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'customers';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('local_version')) {
      context.handle(
        _localVersionMeta,
        localVersion.isAcceptableOrUnknown(
          data['local_version']!,
          _localVersionMeta,
        ),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    } else if (isInserting) {
      context.missing(_createdByMeta);
    }
    if (data.containsKey('credit_limit_cents')) {
      context.handle(
        _creditLimitCentsMeta,
        creditLimitCents.isAcceptableOrUnknown(
          data['credit_limit_cents']!,
          _creditLimitCentsMeta,
        ),
      );
    }
    if (data.containsKey('changed_fields')) {
      context.handle(
        _changedFieldsMeta,
        changedFields.isAcceptableOrUnknown(
          data['changed_fields']!,
          _changedFieldsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomerRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      syncState: $CustomersTable.$convertersyncState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}sync_state'],
        )!,
      ),
      localVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_version'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
      creditLimitCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}credit_limit_cents'],
      ),
      changedFields: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}changed_fields'],
      )!,
    );
  }

  @override
  $CustomersTable createAlias(String alias) {
    return $CustomersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SyncState, int, int> $convertersyncState =
      const EnumIndexConverter<SyncState>(SyncState.values);
}

class CustomerRow extends DataClass implements Insertable<CustomerRow> {
  final String id;
  final DateTime createdAt;

  /// When this version was made, by the server's clock (docs/10, D8).
  final DateTime updatedAt;

  /// A tombstone: nothing is deleted outright, or the next sync from another
  /// phone would bring it back.
  final bool isDeleted;
  final SyncState syncState;

  /// Goes up with every local change. A push batch remembers the version it
  /// carried; a record edited while its batch was in flight stays pending
  /// for the next one (docs/10, §4.3).
  final int localVersion;
  final String name;
  final String? phone;
  final String? notes;
  final String createdBy;
  final int? creditLimitCents;

  /// The fields edited on this phone since the last accepted push, comma
  /// separated. Empty while pending means a new record: all of it is ours.
  final String changedFields;
  const CustomerRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    required this.syncState,
    required this.localVersion,
    required this.name,
    this.phone,
    this.notes,
    required this.createdBy,
    this.creditLimitCents,
    required this.changedFields,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_deleted'] = Variable<bool>(isDeleted);
    {
      map['sync_state'] = Variable<int>(
        $CustomersTable.$convertersyncState.toSql(syncState),
      );
    }
    map['local_version'] = Variable<int>(localVersion);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_by'] = Variable<String>(createdBy);
    if (!nullToAbsent || creditLimitCents != null) {
      map['credit_limit_cents'] = Variable<int>(creditLimitCents);
    }
    map['changed_fields'] = Variable<String>(changedFields);
    return map;
  }

  CustomersCompanion toCompanion(bool nullToAbsent) {
    return CustomersCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      syncState: Value(syncState),
      localVersion: Value(localVersion),
      name: Value(name),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdBy: Value(createdBy),
      creditLimitCents: creditLimitCents == null && nullToAbsent
          ? const Value.absent()
          : Value(creditLimitCents),
      changedFields: Value(changedFields),
    );
  }

  factory CustomerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomerRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      syncState: $CustomersTable.$convertersyncState.fromJson(
        serializer.fromJson<int>(json['syncState']),
      ),
      localVersion: serializer.fromJson<int>(json['localVersion']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
      creditLimitCents: serializer.fromJson<int?>(json['creditLimitCents']),
      changedFields: serializer.fromJson<String>(json['changedFields']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'syncState': serializer.toJson<int>(
        $CustomersTable.$convertersyncState.toJson(syncState),
      ),
      'localVersion': serializer.toJson<int>(localVersion),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'notes': serializer.toJson<String?>(notes),
      'createdBy': serializer.toJson<String>(createdBy),
      'creditLimitCents': serializer.toJson<int?>(creditLimitCents),
      'changedFields': serializer.toJson<String>(changedFields),
    };
  }

  CustomerRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    SyncState? syncState,
    int? localVersion,
    String? name,
    Value<String?> phone = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    String? createdBy,
    Value<int?> creditLimitCents = const Value.absent(),
    String? changedFields,
  }) => CustomerRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
    syncState: syncState ?? this.syncState,
    localVersion: localVersion ?? this.localVersion,
    name: name ?? this.name,
    phone: phone.present ? phone.value : this.phone,
    notes: notes.present ? notes.value : this.notes,
    createdBy: createdBy ?? this.createdBy,
    creditLimitCents: creditLimitCents.present
        ? creditLimitCents.value
        : this.creditLimitCents,
    changedFields: changedFields ?? this.changedFields,
  );
  CustomerRow copyWithCompanion(CustomersCompanion data) {
    return CustomerRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      localVersion: data.localVersion.present
          ? data.localVersion.value
          : this.localVersion,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      creditLimitCents: data.creditLimitCents.present
          ? data.creditLimitCents.value
          : this.creditLimitCents,
      changedFields: data.changedFields.present
          ? data.changedFields.value
          : this.changedFields,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomerRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('syncState: $syncState, ')
          ..write('localVersion: $localVersion, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('notes: $notes, ')
          ..write('createdBy: $createdBy, ')
          ..write('creditLimitCents: $creditLimitCents, ')
          ..write('changedFields: $changedFields')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    isDeleted,
    syncState,
    localVersion,
    name,
    phone,
    notes,
    createdBy,
    creditLimitCents,
    changedFields,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomerRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isDeleted == this.isDeleted &&
          other.syncState == this.syncState &&
          other.localVersion == this.localVersion &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.notes == this.notes &&
          other.createdBy == this.createdBy &&
          other.creditLimitCents == this.creditLimitCents &&
          other.changedFields == this.changedFields);
}

class CustomersCompanion extends UpdateCompanion<CustomerRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isDeleted;
  final Value<SyncState> syncState;
  final Value<int> localVersion;
  final Value<String> name;
  final Value<String?> phone;
  final Value<String?> notes;
  final Value<String> createdBy;
  final Value<int?> creditLimitCents;
  final Value<String> changedFields;
  final Value<int> rowid;
  const CustomersCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.syncState = const Value.absent(),
    this.localVersion = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.creditLimitCents = const Value.absent(),
    this.changedFields = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomersCompanion.insert({
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.isDeleted = const Value.absent(),
    required SyncState syncState,
    this.localVersion = const Value.absent(),
    required String name,
    this.phone = const Value.absent(),
    this.notes = const Value.absent(),
    required String createdBy,
    this.creditLimitCents = const Value.absent(),
    this.changedFields = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       syncState = Value(syncState),
       name = Value(name),
       createdBy = Value(createdBy);
  static Insertable<CustomerRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isDeleted,
    Expression<int>? syncState,
    Expression<int>? localVersion,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<String>? notes,
    Expression<String>? createdBy,
    Expression<int>? creditLimitCents,
    Expression<String>? changedFields,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (syncState != null) 'sync_state': syncState,
      if (localVersion != null) 'local_version': localVersion,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (notes != null) 'notes': notes,
      if (createdBy != null) 'created_by': createdBy,
      if (creditLimitCents != null) 'credit_limit_cents': creditLimitCents,
      if (changedFields != null) 'changed_fields': changedFields,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomersCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isDeleted,
    Value<SyncState>? syncState,
    Value<int>? localVersion,
    Value<String>? name,
    Value<String?>? phone,
    Value<String?>? notes,
    Value<String>? createdBy,
    Value<int?>? creditLimitCents,
    Value<String>? changedFields,
    Value<int>? rowid,
  }) {
    return CustomersCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      syncState: syncState ?? this.syncState,
      localVersion: localVersion ?? this.localVersion,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      creditLimitCents: creditLimitCents ?? this.creditLimitCents,
      changedFields: changedFields ?? this.changedFields,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<int>(
        $CustomersTable.$convertersyncState.toSql(syncState.value),
      );
    }
    if (localVersion.present) {
      map['local_version'] = Variable<int>(localVersion.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (creditLimitCents.present) {
      map['credit_limit_cents'] = Variable<int>(creditLimitCents.value);
    }
    if (changedFields.present) {
      map['changed_fields'] = Variable<String>(changedFields.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomersCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('syncState: $syncState, ')
          ..write('localVersion: $localVersion, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('notes: $notes, ')
          ..write('createdBy: $createdBy, ')
          ..write('creditLimitCents: $creditLimitCents, ')
          ..write('changedFields: $changedFields, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LedgerEntriesTable extends LedgerEntries
    with TableInfo<$LedgerEntriesTable, LedgerEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LedgerEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncState, int> syncState =
      GeneratedColumn<int>(
        'sync_state',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<SyncState>($LedgerEntriesTable.$convertersyncState);
  static const VerificationMeta _localVersionMeta = const VerificationMeta(
    'localVersion',
  );
  @override
  late final GeneratedColumn<int> localVersion = GeneratedColumn<int>(
    'local_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountCentsMeta = const VerificationMeta(
    'amountCents',
  );
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
    'amount_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transactionDateMeta = const VerificationMeta(
    'transactionDate',
  );
  @override
  late final GeneratedColumn<DateTime> transactionDate =
      GeneratedColumn<DateTime>(
        'transaction_date',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _paymentMethodMeta = const VerificationMeta(
    'paymentMethod',
  );
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
    'payment_method',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referenceMeta = const VerificationMeta(
    'reference',
  );
  @override
  late final GeneratedColumn<String> reference = GeneratedColumn<String>(
    'reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _saleIdMeta = const VerificationMeta('saleId');
  @override
  late final GeneratedColumn<String> saleId = GeneratedColumn<String>(
    'sale_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    isDeleted,
    syncState,
    localVersion,
    customerId,
    userId,
    type,
    amountCents,
    description,
    transactionDate,
    paymentMethod,
    reference,
    dueDate,
    saleId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ledger_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<LedgerEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('local_version')) {
      context.handle(
        _localVersionMeta,
        localVersion.isAcceptableOrUnknown(
          data['local_version']!,
          _localVersionMeta,
        ),
      );
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_customerIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
        _amountCentsMeta,
        amountCents.isAcceptableOrUnknown(
          data['amount_cents']!,
          _amountCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('transaction_date')) {
      context.handle(
        _transactionDateMeta,
        transactionDate.isAcceptableOrUnknown(
          data['transaction_date']!,
          _transactionDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transactionDateMeta);
    }
    if (data.containsKey('payment_method')) {
      context.handle(
        _paymentMethodMeta,
        paymentMethod.isAcceptableOrUnknown(
          data['payment_method']!,
          _paymentMethodMeta,
        ),
      );
    }
    if (data.containsKey('reference')) {
      context.handle(
        _referenceMeta,
        reference.isAcceptableOrUnknown(data['reference']!, _referenceMeta),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('sale_id')) {
      context.handle(
        _saleIdMeta,
        saleId.isAcceptableOrUnknown(data['sale_id']!, _saleIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LedgerEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LedgerEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      syncState: $LedgerEntriesTable.$convertersyncState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}sync_state'],
        )!,
      ),
      localVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_version'],
      )!,
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      amountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_cents'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      transactionDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}transaction_date'],
      )!,
      paymentMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_method'],
      ),
      reference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference'],
      ),
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      saleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sale_id'],
      ),
    );
  }

  @override
  $LedgerEntriesTable createAlias(String alias) {
    return $LedgerEntriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SyncState, int, int> $convertersyncState =
      const EnumIndexConverter<SyncState>(SyncState.values);
}

class LedgerEntryRow extends DataClass implements Insertable<LedgerEntryRow> {
  final String id;
  final DateTime createdAt;

  /// When this version was made, by the server's clock (docs/10, D8).
  final DateTime updatedAt;

  /// A tombstone: nothing is deleted outright, or the next sync from another
  /// phone would bring it back.
  final bool isDeleted;
  final SyncState syncState;

  /// Goes up with every local change. A push batch remembers the version it
  /// carried; a record edited while its batch was in flight stays pending
  /// for the next one (docs/10, §4.3).
  final int localVersion;

  /// Not a foreign key, on purpose. Pull pages follow the server's single
  /// change sequence across every table, so an entry can arrive before its
  /// customer does (when the customer was edited after the entry was made).
  /// A foreign key would fail that page, and with it a new phone's first
  /// sync. The server guarantees the link.
  final String customerId;
  final String userId;

  /// `debt` or `payment`.
  final String type;

  /// Always above zero; the type gives the direction.
  final int amountCents;
  final String? description;
  final DateTime transactionDate;
  final String? paymentMethod;
  final String? reference;
  final DateTime? dueDate;
  final String? saleId;
  const LedgerEntryRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    required this.syncState,
    required this.localVersion,
    required this.customerId,
    required this.userId,
    required this.type,
    required this.amountCents,
    this.description,
    required this.transactionDate,
    this.paymentMethod,
    this.reference,
    this.dueDate,
    this.saleId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_deleted'] = Variable<bool>(isDeleted);
    {
      map['sync_state'] = Variable<int>(
        $LedgerEntriesTable.$convertersyncState.toSql(syncState),
      );
    }
    map['local_version'] = Variable<int>(localVersion);
    map['customer_id'] = Variable<String>(customerId);
    map['user_id'] = Variable<String>(userId);
    map['type'] = Variable<String>(type);
    map['amount_cents'] = Variable<int>(amountCents);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['transaction_date'] = Variable<DateTime>(transactionDate);
    if (!nullToAbsent || paymentMethod != null) {
      map['payment_method'] = Variable<String>(paymentMethod);
    }
    if (!nullToAbsent || reference != null) {
      map['reference'] = Variable<String>(reference);
    }
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    if (!nullToAbsent || saleId != null) {
      map['sale_id'] = Variable<String>(saleId);
    }
    return map;
  }

  LedgerEntriesCompanion toCompanion(bool nullToAbsent) {
    return LedgerEntriesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      syncState: Value(syncState),
      localVersion: Value(localVersion),
      customerId: Value(customerId),
      userId: Value(userId),
      type: Value(type),
      amountCents: Value(amountCents),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      transactionDate: Value(transactionDate),
      paymentMethod: paymentMethod == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentMethod),
      reference: reference == null && nullToAbsent
          ? const Value.absent()
          : Value(reference),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      saleId: saleId == null && nullToAbsent
          ? const Value.absent()
          : Value(saleId),
    );
  }

  factory LedgerEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LedgerEntryRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      syncState: $LedgerEntriesTable.$convertersyncState.fromJson(
        serializer.fromJson<int>(json['syncState']),
      ),
      localVersion: serializer.fromJson<int>(json['localVersion']),
      customerId: serializer.fromJson<String>(json['customerId']),
      userId: serializer.fromJson<String>(json['userId']),
      type: serializer.fromJson<String>(json['type']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      description: serializer.fromJson<String?>(json['description']),
      transactionDate: serializer.fromJson<DateTime>(json['transactionDate']),
      paymentMethod: serializer.fromJson<String?>(json['paymentMethod']),
      reference: serializer.fromJson<String?>(json['reference']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      saleId: serializer.fromJson<String?>(json['saleId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'syncState': serializer.toJson<int>(
        $LedgerEntriesTable.$convertersyncState.toJson(syncState),
      ),
      'localVersion': serializer.toJson<int>(localVersion),
      'customerId': serializer.toJson<String>(customerId),
      'userId': serializer.toJson<String>(userId),
      'type': serializer.toJson<String>(type),
      'amountCents': serializer.toJson<int>(amountCents),
      'description': serializer.toJson<String?>(description),
      'transactionDate': serializer.toJson<DateTime>(transactionDate),
      'paymentMethod': serializer.toJson<String?>(paymentMethod),
      'reference': serializer.toJson<String?>(reference),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'saleId': serializer.toJson<String?>(saleId),
    };
  }

  LedgerEntryRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    SyncState? syncState,
    int? localVersion,
    String? customerId,
    String? userId,
    String? type,
    int? amountCents,
    Value<String?> description = const Value.absent(),
    DateTime? transactionDate,
    Value<String?> paymentMethod = const Value.absent(),
    Value<String?> reference = const Value.absent(),
    Value<DateTime?> dueDate = const Value.absent(),
    Value<String?> saleId = const Value.absent(),
  }) => LedgerEntryRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
    syncState: syncState ?? this.syncState,
    localVersion: localVersion ?? this.localVersion,
    customerId: customerId ?? this.customerId,
    userId: userId ?? this.userId,
    type: type ?? this.type,
    amountCents: amountCents ?? this.amountCents,
    description: description.present ? description.value : this.description,
    transactionDate: transactionDate ?? this.transactionDate,
    paymentMethod: paymentMethod.present
        ? paymentMethod.value
        : this.paymentMethod,
    reference: reference.present ? reference.value : this.reference,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    saleId: saleId.present ? saleId.value : this.saleId,
  );
  LedgerEntryRow copyWithCompanion(LedgerEntriesCompanion data) {
    return LedgerEntryRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      localVersion: data.localVersion.present
          ? data.localVersion.value
          : this.localVersion,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      userId: data.userId.present ? data.userId.value : this.userId,
      type: data.type.present ? data.type.value : this.type,
      amountCents: data.amountCents.present
          ? data.amountCents.value
          : this.amountCents,
      description: data.description.present
          ? data.description.value
          : this.description,
      transactionDate: data.transactionDate.present
          ? data.transactionDate.value
          : this.transactionDate,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      reference: data.reference.present ? data.reference.value : this.reference,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      saleId: data.saleId.present ? data.saleId.value : this.saleId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LedgerEntryRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('syncState: $syncState, ')
          ..write('localVersion: $localVersion, ')
          ..write('customerId: $customerId, ')
          ..write('userId: $userId, ')
          ..write('type: $type, ')
          ..write('amountCents: $amountCents, ')
          ..write('description: $description, ')
          ..write('transactionDate: $transactionDate, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('reference: $reference, ')
          ..write('dueDate: $dueDate, ')
          ..write('saleId: $saleId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    isDeleted,
    syncState,
    localVersion,
    customerId,
    userId,
    type,
    amountCents,
    description,
    transactionDate,
    paymentMethod,
    reference,
    dueDate,
    saleId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LedgerEntryRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isDeleted == this.isDeleted &&
          other.syncState == this.syncState &&
          other.localVersion == this.localVersion &&
          other.customerId == this.customerId &&
          other.userId == this.userId &&
          other.type == this.type &&
          other.amountCents == this.amountCents &&
          other.description == this.description &&
          other.transactionDate == this.transactionDate &&
          other.paymentMethod == this.paymentMethod &&
          other.reference == this.reference &&
          other.dueDate == this.dueDate &&
          other.saleId == this.saleId);
}

class LedgerEntriesCompanion extends UpdateCompanion<LedgerEntryRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isDeleted;
  final Value<SyncState> syncState;
  final Value<int> localVersion;
  final Value<String> customerId;
  final Value<String> userId;
  final Value<String> type;
  final Value<int> amountCents;
  final Value<String?> description;
  final Value<DateTime> transactionDate;
  final Value<String?> paymentMethod;
  final Value<String?> reference;
  final Value<DateTime?> dueDate;
  final Value<String?> saleId;
  final Value<int> rowid;
  const LedgerEntriesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.syncState = const Value.absent(),
    this.localVersion = const Value.absent(),
    this.customerId = const Value.absent(),
    this.userId = const Value.absent(),
    this.type = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.description = const Value.absent(),
    this.transactionDate = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.reference = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.saleId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LedgerEntriesCompanion.insert({
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.isDeleted = const Value.absent(),
    required SyncState syncState,
    this.localVersion = const Value.absent(),
    required String customerId,
    required String userId,
    required String type,
    required int amountCents,
    this.description = const Value.absent(),
    required DateTime transactionDate,
    this.paymentMethod = const Value.absent(),
    this.reference = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.saleId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       syncState = Value(syncState),
       customerId = Value(customerId),
       userId = Value(userId),
       type = Value(type),
       amountCents = Value(amountCents),
       transactionDate = Value(transactionDate);
  static Insertable<LedgerEntryRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isDeleted,
    Expression<int>? syncState,
    Expression<int>? localVersion,
    Expression<String>? customerId,
    Expression<String>? userId,
    Expression<String>? type,
    Expression<int>? amountCents,
    Expression<String>? description,
    Expression<DateTime>? transactionDate,
    Expression<String>? paymentMethod,
    Expression<String>? reference,
    Expression<DateTime>? dueDate,
    Expression<String>? saleId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (syncState != null) 'sync_state': syncState,
      if (localVersion != null) 'local_version': localVersion,
      if (customerId != null) 'customer_id': customerId,
      if (userId != null) 'user_id': userId,
      if (type != null) 'type': type,
      if (amountCents != null) 'amount_cents': amountCents,
      if (description != null) 'description': description,
      if (transactionDate != null) 'transaction_date': transactionDate,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (reference != null) 'reference': reference,
      if (dueDate != null) 'due_date': dueDate,
      if (saleId != null) 'sale_id': saleId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LedgerEntriesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isDeleted,
    Value<SyncState>? syncState,
    Value<int>? localVersion,
    Value<String>? customerId,
    Value<String>? userId,
    Value<String>? type,
    Value<int>? amountCents,
    Value<String?>? description,
    Value<DateTime>? transactionDate,
    Value<String?>? paymentMethod,
    Value<String?>? reference,
    Value<DateTime?>? dueDate,
    Value<String?>? saleId,
    Value<int>? rowid,
  }) {
    return LedgerEntriesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      syncState: syncState ?? this.syncState,
      localVersion: localVersion ?? this.localVersion,
      customerId: customerId ?? this.customerId,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      amountCents: amountCents ?? this.amountCents,
      description: description ?? this.description,
      transactionDate: transactionDate ?? this.transactionDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      reference: reference ?? this.reference,
      dueDate: dueDate ?? this.dueDate,
      saleId: saleId ?? this.saleId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<int>(
        $LedgerEntriesTable.$convertersyncState.toSql(syncState.value),
      );
    }
    if (localVersion.present) {
      map['local_version'] = Variable<int>(localVersion.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (transactionDate.present) {
      map['transaction_date'] = Variable<DateTime>(transactionDate.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (reference.present) {
      map['reference'] = Variable<String>(reference.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (saleId.present) {
      map['sale_id'] = Variable<String>(saleId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LedgerEntriesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('syncState: $syncState, ')
          ..write('localVersion: $localVersion, ')
          ..write('customerId: $customerId, ')
          ..write('userId: $userId, ')
          ..write('type: $type, ')
          ..write('amountCents: $amountCents, ')
          ..write('description: $description, ')
          ..write('transactionDate: $transactionDate, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('reference: $reference, ')
          ..write('dueDate: $dueDate, ')
          ..write('saleId: $saleId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SalesTable extends Sales with TableInfo<$SalesTable, SaleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SalesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncState, int> syncState =
      GeneratedColumn<int>(
        'sync_state',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<SyncState>($SalesTable.$convertersyncState);
  static const VerificationMeta _localVersionMeta = const VerificationMeta(
    'localVersion',
  );
  @override
  late final GeneratedColumn<int> localVersion = GeneratedColumn<int>(
    'local_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productNameMeta = const VerificationMeta(
    'productName',
  );
  @override
  late final GeneratedColumn<String> productName = GeneratedColumn<String>(
    'product_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountCentsMeta = const VerificationMeta(
    'amountCents',
  );
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
    'amount_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paymentMethodMeta = const VerificationMeta(
    'paymentMethod',
  );
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
    'payment_method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _referenceMeta = const VerificationMeta(
    'reference',
  );
  @override
  late final GeneratedColumn<String> reference = GeneratedColumn<String>(
    'reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _saleDateMeta = const VerificationMeta(
    'saleDate',
  );
  @override
  late final GeneratedColumn<DateTime> saleDate = GeneratedColumn<DateTime>(
    'sale_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    isDeleted,
    syncState,
    localVersion,
    customerId,
    userId,
    productName,
    quantity,
    amountCents,
    paymentMethod,
    reference,
    dueDate,
    notes,
    saleDate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sales';
  @override
  VerificationContext validateIntegrity(
    Insertable<SaleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('local_version')) {
      context.handle(
        _localVersionMeta,
        localVersion.isAcceptableOrUnknown(
          data['local_version']!,
          _localVersionMeta,
        ),
      );
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('product_name')) {
      context.handle(
        _productNameMeta,
        productName.isAcceptableOrUnknown(
          data['product_name']!,
          _productNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_productNameMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
        _amountCentsMeta,
        amountCents.isAcceptableOrUnknown(
          data['amount_cents']!,
          _amountCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('payment_method')) {
      context.handle(
        _paymentMethodMeta,
        paymentMethod.isAcceptableOrUnknown(
          data['payment_method']!,
          _paymentMethodMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentMethodMeta);
    }
    if (data.containsKey('reference')) {
      context.handle(
        _referenceMeta,
        reference.isAcceptableOrUnknown(data['reference']!, _referenceMeta),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('sale_date')) {
      context.handle(
        _saleDateMeta,
        saleDate.isAcceptableOrUnknown(data['sale_date']!, _saleDateMeta),
      );
    } else if (isInserting) {
      context.missing(_saleDateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SaleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SaleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      syncState: $SalesTable.$convertersyncState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}sync_state'],
        )!,
      ),
      localVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_version'],
      )!,
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      ),
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      productName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_name'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      amountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_cents'],
      )!,
      paymentMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_method'],
      )!,
      reference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference'],
      ),
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      saleDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sale_date'],
      )!,
    );
  }

  @override
  $SalesTable createAlias(String alias) {
    return $SalesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SyncState, int, int> $convertersyncState =
      const EnumIndexConverter<SyncState>(SyncState.values);
}

class SaleRow extends DataClass implements Insertable<SaleRow> {
  final String id;
  final DateTime createdAt;

  /// When this version was made, by the server's clock (docs/10, D8).
  final DateTime updatedAt;

  /// A tombstone: nothing is deleted outright, or the next sync from another
  /// phone would bring it back.
  final bool isDeleted;
  final SyncState syncState;

  /// Goes up with every local change. A push batch remembers the version it
  /// carried; a record edited while its batch was in flight stays pending
  /// for the next one (docs/10, §4.3).
  final int localVersion;

  /// Set on a credit sale; not a foreign key, for the reason on
  /// [LedgerEntries.customerId].
  final String? customerId;
  final String userId;
  final String productName;

  /// In thousandths: 1.5 bags is 1500.
  final int quantity;
  final int amountCents;

  /// `cash`, `mpesa`, `bank` or `credit`.
  final String paymentMethod;
  final String? reference;
  final DateTime? dueDate;
  final String? notes;
  final DateTime saleDate;
  const SaleRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    required this.syncState,
    required this.localVersion,
    this.customerId,
    required this.userId,
    required this.productName,
    required this.quantity,
    required this.amountCents,
    required this.paymentMethod,
    this.reference,
    this.dueDate,
    this.notes,
    required this.saleDate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_deleted'] = Variable<bool>(isDeleted);
    {
      map['sync_state'] = Variable<int>(
        $SalesTable.$convertersyncState.toSql(syncState),
      );
    }
    map['local_version'] = Variable<int>(localVersion);
    if (!nullToAbsent || customerId != null) {
      map['customer_id'] = Variable<String>(customerId);
    }
    map['user_id'] = Variable<String>(userId);
    map['product_name'] = Variable<String>(productName);
    map['quantity'] = Variable<int>(quantity);
    map['amount_cents'] = Variable<int>(amountCents);
    map['payment_method'] = Variable<String>(paymentMethod);
    if (!nullToAbsent || reference != null) {
      map['reference'] = Variable<String>(reference);
    }
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['sale_date'] = Variable<DateTime>(saleDate);
    return map;
  }

  SalesCompanion toCompanion(bool nullToAbsent) {
    return SalesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      syncState: Value(syncState),
      localVersion: Value(localVersion),
      customerId: customerId == null && nullToAbsent
          ? const Value.absent()
          : Value(customerId),
      userId: Value(userId),
      productName: Value(productName),
      quantity: Value(quantity),
      amountCents: Value(amountCents),
      paymentMethod: Value(paymentMethod),
      reference: reference == null && nullToAbsent
          ? const Value.absent()
          : Value(reference),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      saleDate: Value(saleDate),
    );
  }

  factory SaleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SaleRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      syncState: $SalesTable.$convertersyncState.fromJson(
        serializer.fromJson<int>(json['syncState']),
      ),
      localVersion: serializer.fromJson<int>(json['localVersion']),
      customerId: serializer.fromJson<String?>(json['customerId']),
      userId: serializer.fromJson<String>(json['userId']),
      productName: serializer.fromJson<String>(json['productName']),
      quantity: serializer.fromJson<int>(json['quantity']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      reference: serializer.fromJson<String?>(json['reference']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      notes: serializer.fromJson<String?>(json['notes']),
      saleDate: serializer.fromJson<DateTime>(json['saleDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'syncState': serializer.toJson<int>(
        $SalesTable.$convertersyncState.toJson(syncState),
      ),
      'localVersion': serializer.toJson<int>(localVersion),
      'customerId': serializer.toJson<String?>(customerId),
      'userId': serializer.toJson<String>(userId),
      'productName': serializer.toJson<String>(productName),
      'quantity': serializer.toJson<int>(quantity),
      'amountCents': serializer.toJson<int>(amountCents),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'reference': serializer.toJson<String?>(reference),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'notes': serializer.toJson<String?>(notes),
      'saleDate': serializer.toJson<DateTime>(saleDate),
    };
  }

  SaleRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    SyncState? syncState,
    int? localVersion,
    Value<String?> customerId = const Value.absent(),
    String? userId,
    String? productName,
    int? quantity,
    int? amountCents,
    String? paymentMethod,
    Value<String?> reference = const Value.absent(),
    Value<DateTime?> dueDate = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    DateTime? saleDate,
  }) => SaleRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
    syncState: syncState ?? this.syncState,
    localVersion: localVersion ?? this.localVersion,
    customerId: customerId.present ? customerId.value : this.customerId,
    userId: userId ?? this.userId,
    productName: productName ?? this.productName,
    quantity: quantity ?? this.quantity,
    amountCents: amountCents ?? this.amountCents,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    reference: reference.present ? reference.value : this.reference,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    notes: notes.present ? notes.value : this.notes,
    saleDate: saleDate ?? this.saleDate,
  );
  SaleRow copyWithCompanion(SalesCompanion data) {
    return SaleRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      localVersion: data.localVersion.present
          ? data.localVersion.value
          : this.localVersion,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      userId: data.userId.present ? data.userId.value : this.userId,
      productName: data.productName.present
          ? data.productName.value
          : this.productName,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      amountCents: data.amountCents.present
          ? data.amountCents.value
          : this.amountCents,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      reference: data.reference.present ? data.reference.value : this.reference,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      notes: data.notes.present ? data.notes.value : this.notes,
      saleDate: data.saleDate.present ? data.saleDate.value : this.saleDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SaleRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('syncState: $syncState, ')
          ..write('localVersion: $localVersion, ')
          ..write('customerId: $customerId, ')
          ..write('userId: $userId, ')
          ..write('productName: $productName, ')
          ..write('quantity: $quantity, ')
          ..write('amountCents: $amountCents, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('reference: $reference, ')
          ..write('dueDate: $dueDate, ')
          ..write('notes: $notes, ')
          ..write('saleDate: $saleDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    isDeleted,
    syncState,
    localVersion,
    customerId,
    userId,
    productName,
    quantity,
    amountCents,
    paymentMethod,
    reference,
    dueDate,
    notes,
    saleDate,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SaleRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isDeleted == this.isDeleted &&
          other.syncState == this.syncState &&
          other.localVersion == this.localVersion &&
          other.customerId == this.customerId &&
          other.userId == this.userId &&
          other.productName == this.productName &&
          other.quantity == this.quantity &&
          other.amountCents == this.amountCents &&
          other.paymentMethod == this.paymentMethod &&
          other.reference == this.reference &&
          other.dueDate == this.dueDate &&
          other.notes == this.notes &&
          other.saleDate == this.saleDate);
}

class SalesCompanion extends UpdateCompanion<SaleRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isDeleted;
  final Value<SyncState> syncState;
  final Value<int> localVersion;
  final Value<String?> customerId;
  final Value<String> userId;
  final Value<String> productName;
  final Value<int> quantity;
  final Value<int> amountCents;
  final Value<String> paymentMethod;
  final Value<String?> reference;
  final Value<DateTime?> dueDate;
  final Value<String?> notes;
  final Value<DateTime> saleDate;
  final Value<int> rowid;
  const SalesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.syncState = const Value.absent(),
    this.localVersion = const Value.absent(),
    this.customerId = const Value.absent(),
    this.userId = const Value.absent(),
    this.productName = const Value.absent(),
    this.quantity = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.reference = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.notes = const Value.absent(),
    this.saleDate = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SalesCompanion.insert({
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.isDeleted = const Value.absent(),
    required SyncState syncState,
    this.localVersion = const Value.absent(),
    this.customerId = const Value.absent(),
    required String userId,
    required String productName,
    required int quantity,
    required int amountCents,
    required String paymentMethod,
    this.reference = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.notes = const Value.absent(),
    required DateTime saleDate,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       syncState = Value(syncState),
       userId = Value(userId),
       productName = Value(productName),
       quantity = Value(quantity),
       amountCents = Value(amountCents),
       paymentMethod = Value(paymentMethod),
       saleDate = Value(saleDate);
  static Insertable<SaleRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isDeleted,
    Expression<int>? syncState,
    Expression<int>? localVersion,
    Expression<String>? customerId,
    Expression<String>? userId,
    Expression<String>? productName,
    Expression<int>? quantity,
    Expression<int>? amountCents,
    Expression<String>? paymentMethod,
    Expression<String>? reference,
    Expression<DateTime>? dueDate,
    Expression<String>? notes,
    Expression<DateTime>? saleDate,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (syncState != null) 'sync_state': syncState,
      if (localVersion != null) 'local_version': localVersion,
      if (customerId != null) 'customer_id': customerId,
      if (userId != null) 'user_id': userId,
      if (productName != null) 'product_name': productName,
      if (quantity != null) 'quantity': quantity,
      if (amountCents != null) 'amount_cents': amountCents,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (reference != null) 'reference': reference,
      if (dueDate != null) 'due_date': dueDate,
      if (notes != null) 'notes': notes,
      if (saleDate != null) 'sale_date': saleDate,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SalesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isDeleted,
    Value<SyncState>? syncState,
    Value<int>? localVersion,
    Value<String?>? customerId,
    Value<String>? userId,
    Value<String>? productName,
    Value<int>? quantity,
    Value<int>? amountCents,
    Value<String>? paymentMethod,
    Value<String?>? reference,
    Value<DateTime?>? dueDate,
    Value<String?>? notes,
    Value<DateTime>? saleDate,
    Value<int>? rowid,
  }) {
    return SalesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      syncState: syncState ?? this.syncState,
      localVersion: localVersion ?? this.localVersion,
      customerId: customerId ?? this.customerId,
      userId: userId ?? this.userId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      amountCents: amountCents ?? this.amountCents,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      reference: reference ?? this.reference,
      dueDate: dueDate ?? this.dueDate,
      notes: notes ?? this.notes,
      saleDate: saleDate ?? this.saleDate,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<int>(
        $SalesTable.$convertersyncState.toSql(syncState.value),
      );
    }
    if (localVersion.present) {
      map['local_version'] = Variable<int>(localVersion.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (productName.present) {
      map['product_name'] = Variable<String>(productName.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (reference.present) {
      map['reference'] = Variable<String>(reference.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (saleDate.present) {
      map['sale_date'] = Variable<DateTime>(saleDate.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SalesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('syncState: $syncState, ')
          ..write('localVersion: $localVersion, ')
          ..write('customerId: $customerId, ')
          ..write('userId: $userId, ')
          ..write('productName: $productName, ')
          ..write('quantity: $quantity, ')
          ..write('amountCents: $amountCents, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('reference: $reference, ')
          ..write('dueDate: $dueDate, ')
          ..write('notes: $notes, ')
          ..write('saleDate: $saleDate, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StockRequestsTable extends StockRequests
    with TableInfo<$StockRequestsTable, StockRequestRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockRequestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncState, int> syncState =
      GeneratedColumn<int>(
        'sync_state',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<SyncState>($StockRequestsTable.$convertersyncState);
  static const VerificationMeta _localVersionMeta = const VerificationMeta(
    'localVersion',
  );
  @override
  late final GeneratedColumn<int> localVersion = GeneratedColumn<int>(
    'local_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productNameMeta = const VerificationMeta(
    'productName',
  );
  @override
  late final GeneratedColumn<String> productName = GeneratedColumn<String>(
    'product_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _neededOnMeta = const VerificationMeta(
    'neededOn',
  );
  @override
  late final GeneratedColumn<DateTime> neededOn = GeneratedColumn<DateTime>(
    'needed_on',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _purchaseOrderIdMeta = const VerificationMeta(
    'purchaseOrderId',
  );
  @override
  late final GeneratedColumn<String> purchaseOrderId = GeneratedColumn<String>(
    'purchase_order_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    isDeleted,
    syncState,
    localVersion,
    userId,
    productName,
    neededOn,
    notes,
    purchaseOrderId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_requests';
  @override
  VerificationContext validateIntegrity(
    Insertable<StockRequestRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('local_version')) {
      context.handle(
        _localVersionMeta,
        localVersion.isAcceptableOrUnknown(
          data['local_version']!,
          _localVersionMeta,
        ),
      );
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('product_name')) {
      context.handle(
        _productNameMeta,
        productName.isAcceptableOrUnknown(
          data['product_name']!,
          _productNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_productNameMeta);
    }
    if (data.containsKey('needed_on')) {
      context.handle(
        _neededOnMeta,
        neededOn.isAcceptableOrUnknown(data['needed_on']!, _neededOnMeta),
      );
    } else if (isInserting) {
      context.missing(_neededOnMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('purchase_order_id')) {
      context.handle(
        _purchaseOrderIdMeta,
        purchaseOrderId.isAcceptableOrUnknown(
          data['purchase_order_id']!,
          _purchaseOrderIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StockRequestRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockRequestRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      syncState: $StockRequestsTable.$convertersyncState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}sync_state'],
        )!,
      ),
      localVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_version'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      productName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_name'],
      )!,
      neededOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}needed_on'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      purchaseOrderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purchase_order_id'],
      ),
    );
  }

  @override
  $StockRequestsTable createAlias(String alias) {
    return $StockRequestsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SyncState, int, int> $convertersyncState =
      const EnumIndexConverter<SyncState>(SyncState.values);
}

class StockRequestRow extends DataClass implements Insertable<StockRequestRow> {
  final String id;
  final DateTime createdAt;

  /// When this version was made, by the server's clock (docs/10, D8).
  final DateTime updatedAt;

  /// A tombstone: nothing is deleted outright, or the next sync from another
  /// phone would bring it back.
  final bool isDeleted;
  final SyncState syncState;

  /// Goes up with every local change. A push batch remembers the version it
  /// carried; a record edited while its batch was in flight stays pending
  /// for the next one (docs/10, §4.3).
  final int localVersion;
  final String userId;
  final String productName;
  final DateTime neededOn;
  final String? notes;

  /// Set by the server when the note goes on an order; never sent.
  final String? purchaseOrderId;
  const StockRequestRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    required this.syncState,
    required this.localVersion,
    required this.userId,
    required this.productName,
    required this.neededOn,
    this.notes,
    this.purchaseOrderId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_deleted'] = Variable<bool>(isDeleted);
    {
      map['sync_state'] = Variable<int>(
        $StockRequestsTable.$convertersyncState.toSql(syncState),
      );
    }
    map['local_version'] = Variable<int>(localVersion);
    map['user_id'] = Variable<String>(userId);
    map['product_name'] = Variable<String>(productName);
    map['needed_on'] = Variable<DateTime>(neededOn);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || purchaseOrderId != null) {
      map['purchase_order_id'] = Variable<String>(purchaseOrderId);
    }
    return map;
  }

  StockRequestsCompanion toCompanion(bool nullToAbsent) {
    return StockRequestsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      syncState: Value(syncState),
      localVersion: Value(localVersion),
      userId: Value(userId),
      productName: Value(productName),
      neededOn: Value(neededOn),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      purchaseOrderId: purchaseOrderId == null && nullToAbsent
          ? const Value.absent()
          : Value(purchaseOrderId),
    );
  }

  factory StockRequestRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockRequestRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      syncState: $StockRequestsTable.$convertersyncState.fromJson(
        serializer.fromJson<int>(json['syncState']),
      ),
      localVersion: serializer.fromJson<int>(json['localVersion']),
      userId: serializer.fromJson<String>(json['userId']),
      productName: serializer.fromJson<String>(json['productName']),
      neededOn: serializer.fromJson<DateTime>(json['neededOn']),
      notes: serializer.fromJson<String?>(json['notes']),
      purchaseOrderId: serializer.fromJson<String?>(json['purchaseOrderId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'syncState': serializer.toJson<int>(
        $StockRequestsTable.$convertersyncState.toJson(syncState),
      ),
      'localVersion': serializer.toJson<int>(localVersion),
      'userId': serializer.toJson<String>(userId),
      'productName': serializer.toJson<String>(productName),
      'neededOn': serializer.toJson<DateTime>(neededOn),
      'notes': serializer.toJson<String?>(notes),
      'purchaseOrderId': serializer.toJson<String?>(purchaseOrderId),
    };
  }

  StockRequestRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    SyncState? syncState,
    int? localVersion,
    String? userId,
    String? productName,
    DateTime? neededOn,
    Value<String?> notes = const Value.absent(),
    Value<String?> purchaseOrderId = const Value.absent(),
  }) => StockRequestRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
    syncState: syncState ?? this.syncState,
    localVersion: localVersion ?? this.localVersion,
    userId: userId ?? this.userId,
    productName: productName ?? this.productName,
    neededOn: neededOn ?? this.neededOn,
    notes: notes.present ? notes.value : this.notes,
    purchaseOrderId: purchaseOrderId.present
        ? purchaseOrderId.value
        : this.purchaseOrderId,
  );
  StockRequestRow copyWithCompanion(StockRequestsCompanion data) {
    return StockRequestRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      localVersion: data.localVersion.present
          ? data.localVersion.value
          : this.localVersion,
      userId: data.userId.present ? data.userId.value : this.userId,
      productName: data.productName.present
          ? data.productName.value
          : this.productName,
      neededOn: data.neededOn.present ? data.neededOn.value : this.neededOn,
      notes: data.notes.present ? data.notes.value : this.notes,
      purchaseOrderId: data.purchaseOrderId.present
          ? data.purchaseOrderId.value
          : this.purchaseOrderId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockRequestRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('syncState: $syncState, ')
          ..write('localVersion: $localVersion, ')
          ..write('userId: $userId, ')
          ..write('productName: $productName, ')
          ..write('neededOn: $neededOn, ')
          ..write('notes: $notes, ')
          ..write('purchaseOrderId: $purchaseOrderId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    isDeleted,
    syncState,
    localVersion,
    userId,
    productName,
    neededOn,
    notes,
    purchaseOrderId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockRequestRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isDeleted == this.isDeleted &&
          other.syncState == this.syncState &&
          other.localVersion == this.localVersion &&
          other.userId == this.userId &&
          other.productName == this.productName &&
          other.neededOn == this.neededOn &&
          other.notes == this.notes &&
          other.purchaseOrderId == this.purchaseOrderId);
}

class StockRequestsCompanion extends UpdateCompanion<StockRequestRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isDeleted;
  final Value<SyncState> syncState;
  final Value<int> localVersion;
  final Value<String> userId;
  final Value<String> productName;
  final Value<DateTime> neededOn;
  final Value<String?> notes;
  final Value<String?> purchaseOrderId;
  final Value<int> rowid;
  const StockRequestsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.syncState = const Value.absent(),
    this.localVersion = const Value.absent(),
    this.userId = const Value.absent(),
    this.productName = const Value.absent(),
    this.neededOn = const Value.absent(),
    this.notes = const Value.absent(),
    this.purchaseOrderId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockRequestsCompanion.insert({
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.isDeleted = const Value.absent(),
    required SyncState syncState,
    this.localVersion = const Value.absent(),
    required String userId,
    required String productName,
    required DateTime neededOn,
    this.notes = const Value.absent(),
    this.purchaseOrderId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       syncState = Value(syncState),
       userId = Value(userId),
       productName = Value(productName),
       neededOn = Value(neededOn);
  static Insertable<StockRequestRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isDeleted,
    Expression<int>? syncState,
    Expression<int>? localVersion,
    Expression<String>? userId,
    Expression<String>? productName,
    Expression<DateTime>? neededOn,
    Expression<String>? notes,
    Expression<String>? purchaseOrderId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (syncState != null) 'sync_state': syncState,
      if (localVersion != null) 'local_version': localVersion,
      if (userId != null) 'user_id': userId,
      if (productName != null) 'product_name': productName,
      if (neededOn != null) 'needed_on': neededOn,
      if (notes != null) 'notes': notes,
      if (purchaseOrderId != null) 'purchase_order_id': purchaseOrderId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockRequestsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isDeleted,
    Value<SyncState>? syncState,
    Value<int>? localVersion,
    Value<String>? userId,
    Value<String>? productName,
    Value<DateTime>? neededOn,
    Value<String?>? notes,
    Value<String?>? purchaseOrderId,
    Value<int>? rowid,
  }) {
    return StockRequestsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      syncState: syncState ?? this.syncState,
      localVersion: localVersion ?? this.localVersion,
      userId: userId ?? this.userId,
      productName: productName ?? this.productName,
      neededOn: neededOn ?? this.neededOn,
      notes: notes ?? this.notes,
      purchaseOrderId: purchaseOrderId ?? this.purchaseOrderId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<int>(
        $StockRequestsTable.$convertersyncState.toSql(syncState.value),
      );
    }
    if (localVersion.present) {
      map['local_version'] = Variable<int>(localVersion.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (productName.present) {
      map['product_name'] = Variable<String>(productName.value);
    }
    if (neededOn.present) {
      map['needed_on'] = Variable<DateTime>(neededOn.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (purchaseOrderId.present) {
      map['purchase_order_id'] = Variable<String>(purchaseOrderId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockRequestsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('syncState: $syncState, ')
          ..write('localVersion: $localVersion, ')
          ..write('userId: $userId, ')
          ..write('productName: $productName, ')
          ..write('neededOn: $neededOn, ')
          ..write('notes: $notes, ')
          ..write('purchaseOrderId: $purchaseOrderId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SuppliersTable extends Suppliers
    with TableInfo<$SuppliersTable, SupplierRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SuppliersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncState, int> syncState =
      GeneratedColumn<int>(
        'sync_state',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<SyncState>($SuppliersTable.$convertersyncState);
  static const VerificationMeta _localVersionMeta = const VerificationMeta(
    'localVersion',
  );
  @override
  late final GeneratedColumn<int> localVersion = GeneratedColumn<int>(
    'local_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    isDeleted,
    syncState,
    localVersion,
    name,
    phone,
    notes,
    createdBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'suppliers';
  @override
  VerificationContext validateIntegrity(
    Insertable<SupplierRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('local_version')) {
      context.handle(
        _localVersionMeta,
        localVersion.isAcceptableOrUnknown(
          data['local_version']!,
          _localVersionMeta,
        ),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    } else if (isInserting) {
      context.missing(_createdByMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SupplierRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SupplierRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      syncState: $SuppliersTable.$convertersyncState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}sync_state'],
        )!,
      ),
      localVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_version'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
    );
  }

  @override
  $SuppliersTable createAlias(String alias) {
    return $SuppliersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SyncState, int, int> $convertersyncState =
      const EnumIndexConverter<SyncState>(SyncState.values);
}

class SupplierRow extends DataClass implements Insertable<SupplierRow> {
  final String id;
  final DateTime createdAt;

  /// When this version was made, by the server's clock (docs/10, D8).
  final DateTime updatedAt;

  /// A tombstone: nothing is deleted outright, or the next sync from another
  /// phone would bring it back.
  final bool isDeleted;
  final SyncState syncState;

  /// Goes up with every local change. A push batch remembers the version it
  /// carried; a record edited while its batch was in flight stays pending
  /// for the next one (docs/10, §4.3).
  final int localVersion;
  final String name;
  final String? phone;
  final String? notes;
  final String createdBy;
  const SupplierRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    required this.syncState,
    required this.localVersion,
    required this.name,
    this.phone,
    this.notes,
    required this.createdBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_deleted'] = Variable<bool>(isDeleted);
    {
      map['sync_state'] = Variable<int>(
        $SuppliersTable.$convertersyncState.toSql(syncState),
      );
    }
    map['local_version'] = Variable<int>(localVersion);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_by'] = Variable<String>(createdBy);
    return map;
  }

  SuppliersCompanion toCompanion(bool nullToAbsent) {
    return SuppliersCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      syncState: Value(syncState),
      localVersion: Value(localVersion),
      name: Value(name),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdBy: Value(createdBy),
    );
  }

  factory SupplierRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SupplierRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      syncState: $SuppliersTable.$convertersyncState.fromJson(
        serializer.fromJson<int>(json['syncState']),
      ),
      localVersion: serializer.fromJson<int>(json['localVersion']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'syncState': serializer.toJson<int>(
        $SuppliersTable.$convertersyncState.toJson(syncState),
      ),
      'localVersion': serializer.toJson<int>(localVersion),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'notes': serializer.toJson<String?>(notes),
      'createdBy': serializer.toJson<String>(createdBy),
    };
  }

  SupplierRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    SyncState? syncState,
    int? localVersion,
    String? name,
    Value<String?> phone = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    String? createdBy,
  }) => SupplierRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
    syncState: syncState ?? this.syncState,
    localVersion: localVersion ?? this.localVersion,
    name: name ?? this.name,
    phone: phone.present ? phone.value : this.phone,
    notes: notes.present ? notes.value : this.notes,
    createdBy: createdBy ?? this.createdBy,
  );
  SupplierRow copyWithCompanion(SuppliersCompanion data) {
    return SupplierRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      localVersion: data.localVersion.present
          ? data.localVersion.value
          : this.localVersion,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SupplierRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('syncState: $syncState, ')
          ..write('localVersion: $localVersion, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('notes: $notes, ')
          ..write('createdBy: $createdBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    isDeleted,
    syncState,
    localVersion,
    name,
    phone,
    notes,
    createdBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SupplierRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isDeleted == this.isDeleted &&
          other.syncState == this.syncState &&
          other.localVersion == this.localVersion &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.notes == this.notes &&
          other.createdBy == this.createdBy);
}

class SuppliersCompanion extends UpdateCompanion<SupplierRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isDeleted;
  final Value<SyncState> syncState;
  final Value<int> localVersion;
  final Value<String> name;
  final Value<String?> phone;
  final Value<String?> notes;
  final Value<String> createdBy;
  final Value<int> rowid;
  const SuppliersCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.syncState = const Value.absent(),
    this.localVersion = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SuppliersCompanion.insert({
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.isDeleted = const Value.absent(),
    required SyncState syncState,
    this.localVersion = const Value.absent(),
    required String name,
    this.phone = const Value.absent(),
    this.notes = const Value.absent(),
    required String createdBy,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       syncState = Value(syncState),
       name = Value(name),
       createdBy = Value(createdBy);
  static Insertable<SupplierRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isDeleted,
    Expression<int>? syncState,
    Expression<int>? localVersion,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<String>? notes,
    Expression<String>? createdBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (syncState != null) 'sync_state': syncState,
      if (localVersion != null) 'local_version': localVersion,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (notes != null) 'notes': notes,
      if (createdBy != null) 'created_by': createdBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SuppliersCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isDeleted,
    Value<SyncState>? syncState,
    Value<int>? localVersion,
    Value<String>? name,
    Value<String?>? phone,
    Value<String?>? notes,
    Value<String>? createdBy,
    Value<int>? rowid,
  }) {
    return SuppliersCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      syncState: syncState ?? this.syncState,
      localVersion: localVersion ?? this.localVersion,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<int>(
        $SuppliersTable.$convertersyncState.toSql(syncState.value),
      );
    }
    if (localVersion.present) {
      map['local_version'] = Variable<int>(localVersion.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SuppliersCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('syncState: $syncState, ')
          ..write('localVersion: $localVersion, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('notes: $notes, ')
          ..write('createdBy: $createdBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SupplierEntriesTable extends SupplierEntries
    with TableInfo<$SupplierEntriesTable, SupplierEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SupplierEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncState, int> syncState =
      GeneratedColumn<int>(
        'sync_state',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<SyncState>($SupplierEntriesTable.$convertersyncState);
  static const VerificationMeta _localVersionMeta = const VerificationMeta(
    'localVersion',
  );
  @override
  late final GeneratedColumn<int> localVersion = GeneratedColumn<int>(
    'local_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _supplierIdMeta = const VerificationMeta(
    'supplierId',
  );
  @override
  late final GeneratedColumn<String> supplierId = GeneratedColumn<String>(
    'supplier_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountCentsMeta = const VerificationMeta(
    'amountCents',
  );
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
    'amount_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transactionDateMeta = const VerificationMeta(
    'transactionDate',
  );
  @override
  late final GeneratedColumn<DateTime> transactionDate =
      GeneratedColumn<DateTime>(
        'transaction_date',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paymentMethodMeta = const VerificationMeta(
    'paymentMethod',
  );
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
    'payment_method',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referenceMeta = const VerificationMeta(
    'reference',
  );
  @override
  late final GeneratedColumn<String> reference = GeneratedColumn<String>(
    'reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _purchaseOrderIdMeta = const VerificationMeta(
    'purchaseOrderId',
  );
  @override
  late final GeneratedColumn<String> purchaseOrderId = GeneratedColumn<String>(
    'purchase_order_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    isDeleted,
    syncState,
    localVersion,
    supplierId,
    userId,
    type,
    amountCents,
    description,
    transactionDate,
    dueDate,
    paymentMethod,
    reference,
    purchaseOrderId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'supplier_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SupplierEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('local_version')) {
      context.handle(
        _localVersionMeta,
        localVersion.isAcceptableOrUnknown(
          data['local_version']!,
          _localVersionMeta,
        ),
      );
    }
    if (data.containsKey('supplier_id')) {
      context.handle(
        _supplierIdMeta,
        supplierId.isAcceptableOrUnknown(data['supplier_id']!, _supplierIdMeta),
      );
    } else if (isInserting) {
      context.missing(_supplierIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
        _amountCentsMeta,
        amountCents.isAcceptableOrUnknown(
          data['amount_cents']!,
          _amountCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('transaction_date')) {
      context.handle(
        _transactionDateMeta,
        transactionDate.isAcceptableOrUnknown(
          data['transaction_date']!,
          _transactionDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transactionDateMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('payment_method')) {
      context.handle(
        _paymentMethodMeta,
        paymentMethod.isAcceptableOrUnknown(
          data['payment_method']!,
          _paymentMethodMeta,
        ),
      );
    }
    if (data.containsKey('reference')) {
      context.handle(
        _referenceMeta,
        reference.isAcceptableOrUnknown(data['reference']!, _referenceMeta),
      );
    }
    if (data.containsKey('purchase_order_id')) {
      context.handle(
        _purchaseOrderIdMeta,
        purchaseOrderId.isAcceptableOrUnknown(
          data['purchase_order_id']!,
          _purchaseOrderIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SupplierEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SupplierEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      syncState: $SupplierEntriesTable.$convertersyncState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}sync_state'],
        )!,
      ),
      localVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_version'],
      )!,
      supplierId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supplier_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      amountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_cents'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      transactionDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}transaction_date'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      paymentMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_method'],
      ),
      reference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference'],
      ),
      purchaseOrderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purchase_order_id'],
      ),
    );
  }

  @override
  $SupplierEntriesTable createAlias(String alias) {
    return $SupplierEntriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SyncState, int, int> $convertersyncState =
      const EnumIndexConverter<SyncState>(SyncState.values);
}

class SupplierEntryRow extends DataClass
    implements Insertable<SupplierEntryRow> {
  final String id;
  final DateTime createdAt;

  /// When this version was made, by the server's clock (docs/10, D8).
  final DateTime updatedAt;

  /// A tombstone: nothing is deleted outright, or the next sync from another
  /// phone would bring it back.
  final bool isDeleted;
  final SyncState syncState;

  /// Goes up with every local change. A push batch remembers the version it
  /// carried; a record edited while its batch was in flight stays pending
  /// for the next one (docs/10, §4.3).
  final int localVersion;

  /// Not a foreign key, for the reason on [LedgerEntries.customerId].
  final String supplierId;
  final String userId;

  /// `bill` or `payment`.
  final String type;
  final int amountCents;
  final String description;
  final DateTime transactionDate;
  final DateTime? dueDate;
  final String? paymentMethod;
  final String? reference;
  final String? purchaseOrderId;
  const SupplierEntryRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    required this.syncState,
    required this.localVersion,
    required this.supplierId,
    required this.userId,
    required this.type,
    required this.amountCents,
    required this.description,
    required this.transactionDate,
    this.dueDate,
    this.paymentMethod,
    this.reference,
    this.purchaseOrderId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_deleted'] = Variable<bool>(isDeleted);
    {
      map['sync_state'] = Variable<int>(
        $SupplierEntriesTable.$convertersyncState.toSql(syncState),
      );
    }
    map['local_version'] = Variable<int>(localVersion);
    map['supplier_id'] = Variable<String>(supplierId);
    map['user_id'] = Variable<String>(userId);
    map['type'] = Variable<String>(type);
    map['amount_cents'] = Variable<int>(amountCents);
    map['description'] = Variable<String>(description);
    map['transaction_date'] = Variable<DateTime>(transactionDate);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    if (!nullToAbsent || paymentMethod != null) {
      map['payment_method'] = Variable<String>(paymentMethod);
    }
    if (!nullToAbsent || reference != null) {
      map['reference'] = Variable<String>(reference);
    }
    if (!nullToAbsent || purchaseOrderId != null) {
      map['purchase_order_id'] = Variable<String>(purchaseOrderId);
    }
    return map;
  }

  SupplierEntriesCompanion toCompanion(bool nullToAbsent) {
    return SupplierEntriesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      syncState: Value(syncState),
      localVersion: Value(localVersion),
      supplierId: Value(supplierId),
      userId: Value(userId),
      type: Value(type),
      amountCents: Value(amountCents),
      description: Value(description),
      transactionDate: Value(transactionDate),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      paymentMethod: paymentMethod == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentMethod),
      reference: reference == null && nullToAbsent
          ? const Value.absent()
          : Value(reference),
      purchaseOrderId: purchaseOrderId == null && nullToAbsent
          ? const Value.absent()
          : Value(purchaseOrderId),
    );
  }

  factory SupplierEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SupplierEntryRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      syncState: $SupplierEntriesTable.$convertersyncState.fromJson(
        serializer.fromJson<int>(json['syncState']),
      ),
      localVersion: serializer.fromJson<int>(json['localVersion']),
      supplierId: serializer.fromJson<String>(json['supplierId']),
      userId: serializer.fromJson<String>(json['userId']),
      type: serializer.fromJson<String>(json['type']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      description: serializer.fromJson<String>(json['description']),
      transactionDate: serializer.fromJson<DateTime>(json['transactionDate']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      paymentMethod: serializer.fromJson<String?>(json['paymentMethod']),
      reference: serializer.fromJson<String?>(json['reference']),
      purchaseOrderId: serializer.fromJson<String?>(json['purchaseOrderId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'syncState': serializer.toJson<int>(
        $SupplierEntriesTable.$convertersyncState.toJson(syncState),
      ),
      'localVersion': serializer.toJson<int>(localVersion),
      'supplierId': serializer.toJson<String>(supplierId),
      'userId': serializer.toJson<String>(userId),
      'type': serializer.toJson<String>(type),
      'amountCents': serializer.toJson<int>(amountCents),
      'description': serializer.toJson<String>(description),
      'transactionDate': serializer.toJson<DateTime>(transactionDate),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'paymentMethod': serializer.toJson<String?>(paymentMethod),
      'reference': serializer.toJson<String?>(reference),
      'purchaseOrderId': serializer.toJson<String?>(purchaseOrderId),
    };
  }

  SupplierEntryRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    SyncState? syncState,
    int? localVersion,
    String? supplierId,
    String? userId,
    String? type,
    int? amountCents,
    String? description,
    DateTime? transactionDate,
    Value<DateTime?> dueDate = const Value.absent(),
    Value<String?> paymentMethod = const Value.absent(),
    Value<String?> reference = const Value.absent(),
    Value<String?> purchaseOrderId = const Value.absent(),
  }) => SupplierEntryRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
    syncState: syncState ?? this.syncState,
    localVersion: localVersion ?? this.localVersion,
    supplierId: supplierId ?? this.supplierId,
    userId: userId ?? this.userId,
    type: type ?? this.type,
    amountCents: amountCents ?? this.amountCents,
    description: description ?? this.description,
    transactionDate: transactionDate ?? this.transactionDate,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    paymentMethod: paymentMethod.present
        ? paymentMethod.value
        : this.paymentMethod,
    reference: reference.present ? reference.value : this.reference,
    purchaseOrderId: purchaseOrderId.present
        ? purchaseOrderId.value
        : this.purchaseOrderId,
  );
  SupplierEntryRow copyWithCompanion(SupplierEntriesCompanion data) {
    return SupplierEntryRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      localVersion: data.localVersion.present
          ? data.localVersion.value
          : this.localVersion,
      supplierId: data.supplierId.present
          ? data.supplierId.value
          : this.supplierId,
      userId: data.userId.present ? data.userId.value : this.userId,
      type: data.type.present ? data.type.value : this.type,
      amountCents: data.amountCents.present
          ? data.amountCents.value
          : this.amountCents,
      description: data.description.present
          ? data.description.value
          : this.description,
      transactionDate: data.transactionDate.present
          ? data.transactionDate.value
          : this.transactionDate,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      reference: data.reference.present ? data.reference.value : this.reference,
      purchaseOrderId: data.purchaseOrderId.present
          ? data.purchaseOrderId.value
          : this.purchaseOrderId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SupplierEntryRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('syncState: $syncState, ')
          ..write('localVersion: $localVersion, ')
          ..write('supplierId: $supplierId, ')
          ..write('userId: $userId, ')
          ..write('type: $type, ')
          ..write('amountCents: $amountCents, ')
          ..write('description: $description, ')
          ..write('transactionDate: $transactionDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('reference: $reference, ')
          ..write('purchaseOrderId: $purchaseOrderId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    isDeleted,
    syncState,
    localVersion,
    supplierId,
    userId,
    type,
    amountCents,
    description,
    transactionDate,
    dueDate,
    paymentMethod,
    reference,
    purchaseOrderId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SupplierEntryRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isDeleted == this.isDeleted &&
          other.syncState == this.syncState &&
          other.localVersion == this.localVersion &&
          other.supplierId == this.supplierId &&
          other.userId == this.userId &&
          other.type == this.type &&
          other.amountCents == this.amountCents &&
          other.description == this.description &&
          other.transactionDate == this.transactionDate &&
          other.dueDate == this.dueDate &&
          other.paymentMethod == this.paymentMethod &&
          other.reference == this.reference &&
          other.purchaseOrderId == this.purchaseOrderId);
}

class SupplierEntriesCompanion extends UpdateCompanion<SupplierEntryRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isDeleted;
  final Value<SyncState> syncState;
  final Value<int> localVersion;
  final Value<String> supplierId;
  final Value<String> userId;
  final Value<String> type;
  final Value<int> amountCents;
  final Value<String> description;
  final Value<DateTime> transactionDate;
  final Value<DateTime?> dueDate;
  final Value<String?> paymentMethod;
  final Value<String?> reference;
  final Value<String?> purchaseOrderId;
  final Value<int> rowid;
  const SupplierEntriesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.syncState = const Value.absent(),
    this.localVersion = const Value.absent(),
    this.supplierId = const Value.absent(),
    this.userId = const Value.absent(),
    this.type = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.description = const Value.absent(),
    this.transactionDate = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.reference = const Value.absent(),
    this.purchaseOrderId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SupplierEntriesCompanion.insert({
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.isDeleted = const Value.absent(),
    required SyncState syncState,
    this.localVersion = const Value.absent(),
    required String supplierId,
    required String userId,
    required String type,
    required int amountCents,
    required String description,
    required DateTime transactionDate,
    this.dueDate = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.reference = const Value.absent(),
    this.purchaseOrderId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       syncState = Value(syncState),
       supplierId = Value(supplierId),
       userId = Value(userId),
       type = Value(type),
       amountCents = Value(amountCents),
       description = Value(description),
       transactionDate = Value(transactionDate);
  static Insertable<SupplierEntryRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isDeleted,
    Expression<int>? syncState,
    Expression<int>? localVersion,
    Expression<String>? supplierId,
    Expression<String>? userId,
    Expression<String>? type,
    Expression<int>? amountCents,
    Expression<String>? description,
    Expression<DateTime>? transactionDate,
    Expression<DateTime>? dueDate,
    Expression<String>? paymentMethod,
    Expression<String>? reference,
    Expression<String>? purchaseOrderId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (syncState != null) 'sync_state': syncState,
      if (localVersion != null) 'local_version': localVersion,
      if (supplierId != null) 'supplier_id': supplierId,
      if (userId != null) 'user_id': userId,
      if (type != null) 'type': type,
      if (amountCents != null) 'amount_cents': amountCents,
      if (description != null) 'description': description,
      if (transactionDate != null) 'transaction_date': transactionDate,
      if (dueDate != null) 'due_date': dueDate,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (reference != null) 'reference': reference,
      if (purchaseOrderId != null) 'purchase_order_id': purchaseOrderId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SupplierEntriesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isDeleted,
    Value<SyncState>? syncState,
    Value<int>? localVersion,
    Value<String>? supplierId,
    Value<String>? userId,
    Value<String>? type,
    Value<int>? amountCents,
    Value<String>? description,
    Value<DateTime>? transactionDate,
    Value<DateTime?>? dueDate,
    Value<String?>? paymentMethod,
    Value<String?>? reference,
    Value<String?>? purchaseOrderId,
    Value<int>? rowid,
  }) {
    return SupplierEntriesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      syncState: syncState ?? this.syncState,
      localVersion: localVersion ?? this.localVersion,
      supplierId: supplierId ?? this.supplierId,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      amountCents: amountCents ?? this.amountCents,
      description: description ?? this.description,
      transactionDate: transactionDate ?? this.transactionDate,
      dueDate: dueDate ?? this.dueDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      reference: reference ?? this.reference,
      purchaseOrderId: purchaseOrderId ?? this.purchaseOrderId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<int>(
        $SupplierEntriesTable.$convertersyncState.toSql(syncState.value),
      );
    }
    if (localVersion.present) {
      map['local_version'] = Variable<int>(localVersion.value);
    }
    if (supplierId.present) {
      map['supplier_id'] = Variable<String>(supplierId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (transactionDate.present) {
      map['transaction_date'] = Variable<DateTime>(transactionDate.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (reference.present) {
      map['reference'] = Variable<String>(reference.value);
    }
    if (purchaseOrderId.present) {
      map['purchase_order_id'] = Variable<String>(purchaseOrderId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SupplierEntriesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('syncState: $syncState, ')
          ..write('localVersion: $localVersion, ')
          ..write('supplierId: $supplierId, ')
          ..write('userId: $userId, ')
          ..write('type: $type, ')
          ..write('amountCents: $amountCents, ')
          ..write('description: $description, ')
          ..write('transactionDate: $transactionDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('reference: $reference, ')
          ..write('purchaseOrderId: $purchaseOrderId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaRow extends DataClass implements Insertable<SyncMetaRow> {
  final String key;
  final String value;
  const SyncMetaRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(key: Value(key), value: Value(value));
  }

  factory SyncMetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncMetaRow copyWith({String? key, String? value}) =>
      SyncMetaRow(key: key ?? this.key, value: value ?? this.value);
  SyncMetaRow copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncMetaRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PushBatchesTable extends PushBatches
    with TableInfo<$PushBatchesTable, PushBatchRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PushBatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordsMeta = const VerificationMeta(
    'records',
  );
  @override
  late final GeneratedColumn<String> records = GeneratedColumn<String>(
    'records',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    body,
    records,
    createdAt,
    attempts,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'push_batches';
  @override
  VerificationContext validateIntegrity(
    Insertable<PushBatchRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('records')) {
      context.handle(
        _recordsMeta,
        records.isAcceptableOrUnknown(data['records']!, _recordsMeta),
      );
    } else if (isInserting) {
      context.missing(_recordsMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  PushBatchRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PushBatchRow(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      records: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}records'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
    );
  }

  @override
  $PushBatchesTable createAlias(String alias) {
    return $PushBatchesTable(attachedDatabase, alias);
  }
}

class PushBatchRow extends DataClass implements Insertable<PushBatchRow> {
  final String operationId;

  /// The JSON body, exactly as sent.
  final String body;

  /// The records it carries and the local version of each, as JSON:
  /// `[{"table":"customers","id":"…","version":3}, …]`.
  final String records;
  final DateTime createdAt;
  final int attempts;
  const PushBatchRow({
    required this.operationId,
    required this.body,
    required this.records,
    required this.createdAt,
    required this.attempts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['body'] = Variable<String>(body);
    map['records'] = Variable<String>(records);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    return map;
  }

  PushBatchesCompanion toCompanion(bool nullToAbsent) {
    return PushBatchesCompanion(
      operationId: Value(operationId),
      body: Value(body),
      records: Value(records),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
    );
  }

  factory PushBatchRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PushBatchRow(
      operationId: serializer.fromJson<String>(json['operationId']),
      body: serializer.fromJson<String>(json['body']),
      records: serializer.fromJson<String>(json['records']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'body': serializer.toJson<String>(body),
      'records': serializer.toJson<String>(records),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
    };
  }

  PushBatchRow copyWith({
    String? operationId,
    String? body,
    String? records,
    DateTime? createdAt,
    int? attempts,
  }) => PushBatchRow(
    operationId: operationId ?? this.operationId,
    body: body ?? this.body,
    records: records ?? this.records,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
  );
  PushBatchRow copyWithCompanion(PushBatchesCompanion data) {
    return PushBatchRow(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      body: data.body.present ? data.body.value : this.body,
      records: data.records.present ? data.records.value : this.records,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PushBatchRow(')
          ..write('operationId: $operationId, ')
          ..write('body: $body, ')
          ..write('records: $records, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(operationId, body, records, createdAt, attempts);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PushBatchRow &&
          other.operationId == this.operationId &&
          other.body == this.body &&
          other.records == this.records &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts);
}

class PushBatchesCompanion extends UpdateCompanion<PushBatchRow> {
  final Value<String> operationId;
  final Value<String> body;
  final Value<String> records;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<int> rowid;
  const PushBatchesCompanion({
    this.operationId = const Value.absent(),
    this.body = const Value.absent(),
    this.records = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PushBatchesCompanion.insert({
    required String operationId,
    required String body,
    required String records,
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       body = Value(body),
       records = Value(records),
       createdAt = Value(createdAt);
  static Insertable<PushBatchRow> custom({
    Expression<String>? operationId,
    Expression<String>? body,
    Expression<String>? records,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (body != null) 'body': body,
      if (records != null) 'records': records,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PushBatchesCompanion copyWith({
    Value<String>? operationId,
    Value<String>? body,
    Value<String>? records,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<int>? rowid,
  }) {
    return PushBatchesCompanion(
      operationId: operationId ?? this.operationId,
      body: body ?? this.body,
      records: records ?? this.records,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (records.present) {
      map['records'] = Variable<String>(records.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PushBatchesCompanion(')
          ..write('operationId: $operationId, ')
          ..write('body: $body, ')
          ..write('records: $records, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncIssuesTable extends SyncIssues
    with TableInfo<$SyncIssuesTable, SyncIssueRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncIssuesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _recordTableMeta = const VerificationMeta(
    'recordTable',
  );
  @override
  late final GeneratedColumn<String> recordTable = GeneratedColumn<String>(
    'record_table',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldMeta = const VerificationMeta('field');
  @override
  late final GeneratedColumn<String> field = GeneratedColumn<String>(
    'field',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverCopyMeta = const VerificationMeta(
    'serverCopy',
  );
  @override
  late final GeneratedColumn<String> serverCopy = GeneratedColumn<String>(
    'server_copy',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    recordTable,
    recordId,
    field,
    reason,
    detail,
    serverCopy,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_issues';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncIssueRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('record_table')) {
      context.handle(
        _recordTableMeta,
        recordTable.isAcceptableOrUnknown(
          data['record_table']!,
          _recordTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordTableMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('field')) {
      context.handle(
        _fieldMeta,
        field.isAcceptableOrUnknown(data['field']!, _fieldMeta),
      );
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    }
    if (data.containsKey('server_copy')) {
      context.handle(
        _serverCopyMeta,
        serverCopy.isAcceptableOrUnknown(data['server_copy']!, _serverCopyMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncIssueRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncIssueRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      recordTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_table'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      field: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field'],
      ),
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      ),
      serverCopy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_copy'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SyncIssuesTable createAlias(String alias) {
    return $SyncIssuesTable(attachedDatabase, alias);
  }
}

class SyncIssueRow extends DataClass implements Insertable<SyncIssueRow> {
  final int id;
  final String recordTable;
  final String recordId;
  final String? field;
  final String reason;
  final String? detail;

  /// The server's copy of the record when it refused a change to one it
  /// holds, as JSON (B2). "Discard mine" puts it back; without one, the
  /// record never reached the server and discarding removes it.
  final String? serverCopy;
  final DateTime createdAt;
  const SyncIssueRow({
    required this.id,
    required this.recordTable,
    required this.recordId,
    this.field,
    required this.reason,
    this.detail,
    this.serverCopy,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['record_table'] = Variable<String>(recordTable);
    map['record_id'] = Variable<String>(recordId);
    if (!nullToAbsent || field != null) {
      map['field'] = Variable<String>(field);
    }
    map['reason'] = Variable<String>(reason);
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    if (!nullToAbsent || serverCopy != null) {
      map['server_copy'] = Variable<String>(serverCopy);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SyncIssuesCompanion toCompanion(bool nullToAbsent) {
    return SyncIssuesCompanion(
      id: Value(id),
      recordTable: Value(recordTable),
      recordId: Value(recordId),
      field: field == null && nullToAbsent
          ? const Value.absent()
          : Value(field),
      reason: Value(reason),
      detail: detail == null && nullToAbsent
          ? const Value.absent()
          : Value(detail),
      serverCopy: serverCopy == null && nullToAbsent
          ? const Value.absent()
          : Value(serverCopy),
      createdAt: Value(createdAt),
    );
  }

  factory SyncIssueRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncIssueRow(
      id: serializer.fromJson<int>(json['id']),
      recordTable: serializer.fromJson<String>(json['recordTable']),
      recordId: serializer.fromJson<String>(json['recordId']),
      field: serializer.fromJson<String?>(json['field']),
      reason: serializer.fromJson<String>(json['reason']),
      detail: serializer.fromJson<String?>(json['detail']),
      serverCopy: serializer.fromJson<String?>(json['serverCopy']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'recordTable': serializer.toJson<String>(recordTable),
      'recordId': serializer.toJson<String>(recordId),
      'field': serializer.toJson<String?>(field),
      'reason': serializer.toJson<String>(reason),
      'detail': serializer.toJson<String?>(detail),
      'serverCopy': serializer.toJson<String?>(serverCopy),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SyncIssueRow copyWith({
    int? id,
    String? recordTable,
    String? recordId,
    Value<String?> field = const Value.absent(),
    String? reason,
    Value<String?> detail = const Value.absent(),
    Value<String?> serverCopy = const Value.absent(),
    DateTime? createdAt,
  }) => SyncIssueRow(
    id: id ?? this.id,
    recordTable: recordTable ?? this.recordTable,
    recordId: recordId ?? this.recordId,
    field: field.present ? field.value : this.field,
    reason: reason ?? this.reason,
    detail: detail.present ? detail.value : this.detail,
    serverCopy: serverCopy.present ? serverCopy.value : this.serverCopy,
    createdAt: createdAt ?? this.createdAt,
  );
  SyncIssueRow copyWithCompanion(SyncIssuesCompanion data) {
    return SyncIssueRow(
      id: data.id.present ? data.id.value : this.id,
      recordTable: data.recordTable.present
          ? data.recordTable.value
          : this.recordTable,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      field: data.field.present ? data.field.value : this.field,
      reason: data.reason.present ? data.reason.value : this.reason,
      detail: data.detail.present ? data.detail.value : this.detail,
      serverCopy: data.serverCopy.present
          ? data.serverCopy.value
          : this.serverCopy,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncIssueRow(')
          ..write('id: $id, ')
          ..write('recordTable: $recordTable, ')
          ..write('recordId: $recordId, ')
          ..write('field: $field, ')
          ..write('reason: $reason, ')
          ..write('detail: $detail, ')
          ..write('serverCopy: $serverCopy, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    recordTable,
    recordId,
    field,
    reason,
    detail,
    serverCopy,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncIssueRow &&
          other.id == this.id &&
          other.recordTable == this.recordTable &&
          other.recordId == this.recordId &&
          other.field == this.field &&
          other.reason == this.reason &&
          other.detail == this.detail &&
          other.serverCopy == this.serverCopy &&
          other.createdAt == this.createdAt);
}

class SyncIssuesCompanion extends UpdateCompanion<SyncIssueRow> {
  final Value<int> id;
  final Value<String> recordTable;
  final Value<String> recordId;
  final Value<String?> field;
  final Value<String> reason;
  final Value<String?> detail;
  final Value<String?> serverCopy;
  final Value<DateTime> createdAt;
  const SyncIssuesCompanion({
    this.id = const Value.absent(),
    this.recordTable = const Value.absent(),
    this.recordId = const Value.absent(),
    this.field = const Value.absent(),
    this.reason = const Value.absent(),
    this.detail = const Value.absent(),
    this.serverCopy = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SyncIssuesCompanion.insert({
    this.id = const Value.absent(),
    required String recordTable,
    required String recordId,
    this.field = const Value.absent(),
    required String reason,
    this.detail = const Value.absent(),
    this.serverCopy = const Value.absent(),
    required DateTime createdAt,
  }) : recordTable = Value(recordTable),
       recordId = Value(recordId),
       reason = Value(reason),
       createdAt = Value(createdAt);
  static Insertable<SyncIssueRow> custom({
    Expression<int>? id,
    Expression<String>? recordTable,
    Expression<String>? recordId,
    Expression<String>? field,
    Expression<String>? reason,
    Expression<String>? detail,
    Expression<String>? serverCopy,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recordTable != null) 'record_table': recordTable,
      if (recordId != null) 'record_id': recordId,
      if (field != null) 'field': field,
      if (reason != null) 'reason': reason,
      if (detail != null) 'detail': detail,
      if (serverCopy != null) 'server_copy': serverCopy,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SyncIssuesCompanion copyWith({
    Value<int>? id,
    Value<String>? recordTable,
    Value<String>? recordId,
    Value<String?>? field,
    Value<String>? reason,
    Value<String?>? detail,
    Value<String?>? serverCopy,
    Value<DateTime>? createdAt,
  }) {
    return SyncIssuesCompanion(
      id: id ?? this.id,
      recordTable: recordTable ?? this.recordTable,
      recordId: recordId ?? this.recordId,
      field: field ?? this.field,
      reason: reason ?? this.reason,
      detail: detail ?? this.detail,
      serverCopy: serverCopy ?? this.serverCopy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (recordTable.present) {
      map['record_table'] = Variable<String>(recordTable.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (field.present) {
      map['field'] = Variable<String>(field.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (serverCopy.present) {
      map['server_copy'] = Variable<String>(serverCopy.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncIssuesCompanion(')
          ..write('id: $id, ')
          ..write('recordTable: $recordTable, ')
          ..write('recordId: $recordId, ')
          ..write('field: $field, ')
          ..write('reason: $reason, ')
          ..write('detail: $detail, ')
          ..write('serverCopy: $serverCopy, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ResyncSeenTable extends ResyncSeen
    with TableInfo<$ResyncSeenTable, ResyncSeenRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ResyncSeenTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordTableMeta = const VerificationMeta(
    'recordTable',
  );
  @override
  late final GeneratedColumn<String> recordTable = GeneratedColumn<String>(
    'record_table',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [recordTable, recordId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'resync_seen';
  @override
  VerificationContext validateIntegrity(
    Insertable<ResyncSeenRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('record_table')) {
      context.handle(
        _recordTableMeta,
        recordTable.isAcceptableOrUnknown(
          data['record_table']!,
          _recordTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordTableMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordTable, recordId};
  @override
  ResyncSeenRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ResyncSeenRow(
      recordTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_table'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
    );
  }

  @override
  $ResyncSeenTable createAlias(String alias) {
    return $ResyncSeenTable(attachedDatabase, alias);
  }
}

class ResyncSeenRow extends DataClass implements Insertable<ResyncSeenRow> {
  final String recordTable;
  final String recordId;
  const ResyncSeenRow({required this.recordTable, required this.recordId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['record_table'] = Variable<String>(recordTable);
    map['record_id'] = Variable<String>(recordId);
    return map;
  }

  ResyncSeenCompanion toCompanion(bool nullToAbsent) {
    return ResyncSeenCompanion(
      recordTable: Value(recordTable),
      recordId: Value(recordId),
    );
  }

  factory ResyncSeenRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ResyncSeenRow(
      recordTable: serializer.fromJson<String>(json['recordTable']),
      recordId: serializer.fromJson<String>(json['recordId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recordTable': serializer.toJson<String>(recordTable),
      'recordId': serializer.toJson<String>(recordId),
    };
  }

  ResyncSeenRow copyWith({String? recordTable, String? recordId}) =>
      ResyncSeenRow(
        recordTable: recordTable ?? this.recordTable,
        recordId: recordId ?? this.recordId,
      );
  ResyncSeenRow copyWithCompanion(ResyncSeenCompanion data) {
    return ResyncSeenRow(
      recordTable: data.recordTable.present
          ? data.recordTable.value
          : this.recordTable,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ResyncSeenRow(')
          ..write('recordTable: $recordTable, ')
          ..write('recordId: $recordId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(recordTable, recordId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ResyncSeenRow &&
          other.recordTable == this.recordTable &&
          other.recordId == this.recordId);
}

class ResyncSeenCompanion extends UpdateCompanion<ResyncSeenRow> {
  final Value<String> recordTable;
  final Value<String> recordId;
  final Value<int> rowid;
  const ResyncSeenCompanion({
    this.recordTable = const Value.absent(),
    this.recordId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ResyncSeenCompanion.insert({
    required String recordTable,
    required String recordId,
    this.rowid = const Value.absent(),
  }) : recordTable = Value(recordTable),
       recordId = Value(recordId);
  static Insertable<ResyncSeenRow> custom({
    Expression<String>? recordTable,
    Expression<String>? recordId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordTable != null) 'record_table': recordTable,
      if (recordId != null) 'record_id': recordId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ResyncSeenCompanion copyWith({
    Value<String>? recordTable,
    Value<String>? recordId,
    Value<int>? rowid,
  }) {
    return ResyncSeenCompanion(
      recordTable: recordTable ?? this.recordTable,
      recordId: recordId ?? this.recordId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordTable.present) {
      map['record_table'] = Variable<String>(recordTable.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ResyncSeenCompanion(')
          ..write('recordTable: $recordTable, ')
          ..write('recordId: $recordId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StaffMembersTable extends StaffMembers
    with TableInfo<$StaffMembersTable, StaffMemberRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StaffMembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, role, isActive];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'staff_members';
  @override
  VerificationContext validateIntegrity(
    Insertable<StaffMemberRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    } else if (isInserting) {
      context.missing(_isActiveMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StaffMemberRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StaffMemberRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $StaffMembersTable createAlias(String alias) {
    return $StaffMembersTable(attachedDatabase, alias);
  }
}

class StaffMemberRow extends DataClass implements Insertable<StaffMemberRow> {
  final String id;
  final String name;

  /// `owner` or `staff`.
  final String role;
  final bool isActive;
  const StaffMemberRow({
    required this.id,
    required this.name,
    required this.role,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['role'] = Variable<String>(role);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  StaffMembersCompanion toCompanion(bool nullToAbsent) {
    return StaffMembersCompanion(
      id: Value(id),
      name: Value(name),
      role: Value(role),
      isActive: Value(isActive),
    );
  }

  factory StaffMemberRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StaffMemberRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      role: serializer.fromJson<String>(json['role']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'role': serializer.toJson<String>(role),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  StaffMemberRow copyWith({
    String? id,
    String? name,
    String? role,
    bool? isActive,
  }) => StaffMemberRow(
    id: id ?? this.id,
    name: name ?? this.name,
    role: role ?? this.role,
    isActive: isActive ?? this.isActive,
  );
  StaffMemberRow copyWithCompanion(StaffMembersCompanion data) {
    return StaffMemberRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      role: data.role.present ? data.role.value : this.role,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StaffMemberRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, role, isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StaffMemberRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.role == this.role &&
          other.isActive == this.isActive);
}

class StaffMembersCompanion extends UpdateCompanion<StaffMemberRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> role;
  final Value<bool> isActive;
  final Value<int> rowid;
  const StaffMembersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.role = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StaffMembersCompanion.insert({
    required String id,
    required String name,
    required String role,
    required bool isActive,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       role = Value(role),
       isActive = Value(isActive);
  static Insertable<StaffMemberRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? role,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (role != null) 'role': role,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StaffMembersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? role,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return StaffMembersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StaffMembersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReportCacheTable extends ReportCache
    with TableInfo<$ReportCacheTable, ReportCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReportCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, body, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'report_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReportCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  ReportCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReportCacheRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $ReportCacheTable createAlias(String alias) {
    return $ReportCacheTable(attachedDatabase, alias);
  }
}

class ReportCacheRow extends DataClass implements Insertable<ReportCacheRow> {
  final String key;

  /// The `data` of the server's answer, as JSON.
  final String body;

  /// When it was read, by the server's clock.
  final DateTime fetchedAt;
  const ReportCacheRow({
    required this.key,
    required this.body,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['body'] = Variable<String>(body);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  ReportCacheCompanion toCompanion(bool nullToAbsent) {
    return ReportCacheCompanion(
      key: Value(key),
      body: Value(body),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory ReportCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReportCacheRow(
      key: serializer.fromJson<String>(json['key']),
      body: serializer.fromJson<String>(json['body']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'body': serializer.toJson<String>(body),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  ReportCacheRow copyWith({String? key, String? body, DateTime? fetchedAt}) =>
      ReportCacheRow(
        key: key ?? this.key,
        body: body ?? this.body,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
  ReportCacheRow copyWithCompanion(ReportCacheCompanion data) {
    return ReportCacheRow(
      key: data.key.present ? data.key.value : this.key,
      body: data.body.present ? data.body.value : this.body,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReportCacheRow(')
          ..write('key: $key, ')
          ..write('body: $body, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, body, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReportCacheRow &&
          other.key == this.key &&
          other.body == this.body &&
          other.fetchedAt == this.fetchedAt);
}

class ReportCacheCompanion extends UpdateCompanion<ReportCacheRow> {
  final Value<String> key;
  final Value<String> body;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const ReportCacheCompanion({
    this.key = const Value.absent(),
    this.body = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReportCacheCompanion.insert({
    required String key,
    required String body,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       body = Value(body),
       fetchedAt = Value(fetchedAt);
  static Insertable<ReportCacheRow> custom({
    Expression<String>? key,
    Expression<String>? body,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (body != null) 'body': body,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReportCacheCompanion copyWith({
    Value<String>? key,
    Value<String>? body,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return ReportCacheCompanion(
      key: key ?? this.key,
      body: body ?? this.body,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReportCacheCompanion(')
          ..write('key: $key, ')
          ..write('body: $body, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CustomersTable customers = $CustomersTable(this);
  late final $LedgerEntriesTable ledgerEntries = $LedgerEntriesTable(this);
  late final $SalesTable sales = $SalesTable(this);
  late final $StockRequestsTable stockRequests = $StockRequestsTable(this);
  late final $SuppliersTable suppliers = $SuppliersTable(this);
  late final $SupplierEntriesTable supplierEntries = $SupplierEntriesTable(
    this,
  );
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  late final $PushBatchesTable pushBatches = $PushBatchesTable(this);
  late final $SyncIssuesTable syncIssues = $SyncIssuesTable(this);
  late final $ResyncSeenTable resyncSeen = $ResyncSeenTable(this);
  late final $StaffMembersTable staffMembers = $StaffMembersTable(this);
  late final $ReportCacheTable reportCache = $ReportCacheTable(this);
  late final Index customersSyncState = Index(
    'customers_sync_state',
    'CREATE INDEX customers_sync_state ON customers (sync_state)',
  );
  late final Index ledgerEntriesCustomer = Index(
    'ledger_entries_customer',
    'CREATE INDEX ledger_entries_customer ON ledger_entries (customer_id, is_deleted)',
  );
  late final Index ledgerEntriesSyncState = Index(
    'ledger_entries_sync_state',
    'CREATE INDEX ledger_entries_sync_state ON ledger_entries (sync_state)',
  );
  late final Index salesCustomer = Index(
    'sales_customer',
    'CREATE INDEX sales_customer ON sales (customer_id, is_deleted)',
  );
  late final Index salesSyncState = Index(
    'sales_sync_state',
    'CREATE INDEX sales_sync_state ON sales (sync_state)',
  );
  late final Index stockRequestsSyncState = Index(
    'stock_requests_sync_state',
    'CREATE INDEX stock_requests_sync_state ON stock_requests (sync_state)',
  );
  late final Index suppliersSyncState = Index(
    'suppliers_sync_state',
    'CREATE INDEX suppliers_sync_state ON suppliers (sync_state)',
  );
  late final Index supplierEntriesSupplier = Index(
    'supplier_entries_supplier',
    'CREATE INDEX supplier_entries_supplier ON supplier_entries (supplier_id, is_deleted)',
  );
  late final Index supplierEntriesSyncState = Index(
    'supplier_entries_sync_state',
    'CREATE INDEX supplier_entries_sync_state ON supplier_entries (sync_state)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    customers,
    ledgerEntries,
    sales,
    stockRequests,
    suppliers,
    supplierEntries,
    syncMeta,
    pushBatches,
    syncIssues,
    resyncSeen,
    staffMembers,
    reportCache,
    customersSyncState,
    ledgerEntriesCustomer,
    ledgerEntriesSyncState,
    salesCustomer,
    salesSyncState,
    stockRequestsSyncState,
    suppliersSyncState,
    supplierEntriesSupplier,
    supplierEntriesSyncState,
  ];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$CustomersTableCreateCompanionBuilder =
    CustomersCompanion Function({
      required String id,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<bool> isDeleted,
      required SyncState syncState,
      Value<int> localVersion,
      required String name,
      Value<String?> phone,
      Value<String?> notes,
      required String createdBy,
      Value<int?> creditLimitCents,
      Value<String> changedFields,
      Value<int> rowid,
    });
typedef $$CustomersTableUpdateCompanionBuilder =
    CustomersCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDeleted,
      Value<SyncState> syncState,
      Value<int> localVersion,
      Value<String> name,
      Value<String?> phone,
      Value<String?> notes,
      Value<String> createdBy,
      Value<int?> creditLimitCents,
      Value<String> changedFields,
      Value<int> rowid,
    });

class $$CustomersTableFilterComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SyncState, SyncState, int> get syncState =>
      $composableBuilder(
        column: $table.syncState,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get creditLimitCents => $composableBuilder(
    column: $table.creditLimitCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get changedFields => $composableBuilder(
    column: $table.changedFields,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CustomersTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get creditLimitCents => $composableBuilder(
    column: $table.creditLimitCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get changedFields => $composableBuilder(
    column: $table.changedFields,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CustomersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SyncState, int> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<int> get creditLimitCents => $composableBuilder(
    column: $table.creditLimitCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get changedFields => $composableBuilder(
    column: $table.changedFields,
    builder: (column) => column,
  );
}

class $$CustomersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CustomersTable,
          CustomerRow,
          $$CustomersTableFilterComposer,
          $$CustomersTableOrderingComposer,
          $$CustomersTableAnnotationComposer,
          $$CustomersTableCreateCompanionBuilder,
          $$CustomersTableUpdateCompanionBuilder,
          (
            CustomerRow,
            BaseReferences<_$AppDatabase, $CustomersTable, CustomerRow>,
          ),
          CustomerRow,
          PrefetchHooks Function()
        > {
  $$CustomersTableTableManager(_$AppDatabase db, $CustomersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<SyncState> syncState = const Value.absent(),
                Value<int> localVersion = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> createdBy = const Value.absent(),
                Value<int?> creditLimitCents = const Value.absent(),
                Value<String> changedFields = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomersCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                syncState: syncState,
                localVersion: localVersion,
                name: name,
                phone: phone,
                notes: notes,
                createdBy: createdBy,
                creditLimitCents: creditLimitCents,
                changedFields: changedFields,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<bool> isDeleted = const Value.absent(),
                required SyncState syncState,
                Value<int> localVersion = const Value.absent(),
                required String name,
                Value<String?> phone = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                required String createdBy,
                Value<int?> creditLimitCents = const Value.absent(),
                Value<String> changedFields = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomersCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                syncState: syncState,
                localVersion: localVersion,
                name: name,
                phone: phone,
                notes: notes,
                createdBy: createdBy,
                creditLimitCents: creditLimitCents,
                changedFields: changedFields,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CustomersTable, CustomerRow>(table),
                  BaseReferences<_$AppDatabase, $CustomersTable, CustomerRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CustomersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CustomersTable,
      CustomerRow,
      $$CustomersTableFilterComposer,
      $$CustomersTableOrderingComposer,
      $$CustomersTableAnnotationComposer,
      $$CustomersTableCreateCompanionBuilder,
      $$CustomersTableUpdateCompanionBuilder,
      (
        CustomerRow,
        BaseReferences<_$AppDatabase, $CustomersTable, CustomerRow>,
      ),
      CustomerRow,
      PrefetchHooks Function()
    >;
typedef $$LedgerEntriesTableCreateCompanionBuilder =
    LedgerEntriesCompanion Function({
      required String id,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<bool> isDeleted,
      required SyncState syncState,
      Value<int> localVersion,
      required String customerId,
      required String userId,
      required String type,
      required int amountCents,
      Value<String?> description,
      required DateTime transactionDate,
      Value<String?> paymentMethod,
      Value<String?> reference,
      Value<DateTime?> dueDate,
      Value<String?> saleId,
      Value<int> rowid,
    });
typedef $$LedgerEntriesTableUpdateCompanionBuilder =
    LedgerEntriesCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDeleted,
      Value<SyncState> syncState,
      Value<int> localVersion,
      Value<String> customerId,
      Value<String> userId,
      Value<String> type,
      Value<int> amountCents,
      Value<String?> description,
      Value<DateTime> transactionDate,
      Value<String?> paymentMethod,
      Value<String?> reference,
      Value<DateTime?> dueDate,
      Value<String?> saleId,
      Value<int> rowid,
    });

class $$LedgerEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LedgerEntriesTable> {
  $$LedgerEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SyncState, SyncState, int> get syncState =>
      $composableBuilder(
        column: $table.syncState,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get transactionDate => $composableBuilder(
    column: $table.transactionDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get saleId => $composableBuilder(
    column: $table.saleId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LedgerEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LedgerEntriesTable> {
  $$LedgerEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get transactionDate => $composableBuilder(
    column: $table.transactionDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get saleId => $composableBuilder(
    column: $table.saleId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LedgerEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LedgerEntriesTable> {
  $$LedgerEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SyncState, int> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get transactionDate => $composableBuilder(
    column: $table.transactionDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reference =>
      $composableBuilder(column: $table.reference, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get saleId =>
      $composableBuilder(column: $table.saleId, builder: (column) => column);
}

class $$LedgerEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LedgerEntriesTable,
          LedgerEntryRow,
          $$LedgerEntriesTableFilterComposer,
          $$LedgerEntriesTableOrderingComposer,
          $$LedgerEntriesTableAnnotationComposer,
          $$LedgerEntriesTableCreateCompanionBuilder,
          $$LedgerEntriesTableUpdateCompanionBuilder,
          (
            LedgerEntryRow,
            BaseReferences<_$AppDatabase, $LedgerEntriesTable, LedgerEntryRow>,
          ),
          LedgerEntryRow,
          PrefetchHooks Function()
        > {
  $$LedgerEntriesTableTableManager(_$AppDatabase db, $LedgerEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LedgerEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LedgerEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LedgerEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<SyncState> syncState = const Value.absent(),
                Value<int> localVersion = const Value.absent(),
                Value<String> customerId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> amountCents = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> transactionDate = const Value.absent(),
                Value<String?> paymentMethod = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<String?> saleId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LedgerEntriesCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                syncState: syncState,
                localVersion: localVersion,
                customerId: customerId,
                userId: userId,
                type: type,
                amountCents: amountCents,
                description: description,
                transactionDate: transactionDate,
                paymentMethod: paymentMethod,
                reference: reference,
                dueDate: dueDate,
                saleId: saleId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<bool> isDeleted = const Value.absent(),
                required SyncState syncState,
                Value<int> localVersion = const Value.absent(),
                required String customerId,
                required String userId,
                required String type,
                required int amountCents,
                Value<String?> description = const Value.absent(),
                required DateTime transactionDate,
                Value<String?> paymentMethod = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<String?> saleId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LedgerEntriesCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                syncState: syncState,
                localVersion: localVersion,
                customerId: customerId,
                userId: userId,
                type: type,
                amountCents: amountCents,
                description: description,
                transactionDate: transactionDate,
                paymentMethod: paymentMethod,
                reference: reference,
                dueDate: dueDate,
                saleId: saleId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LedgerEntriesTable, LedgerEntryRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LedgerEntriesTable,
                    LedgerEntryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LedgerEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LedgerEntriesTable,
      LedgerEntryRow,
      $$LedgerEntriesTableFilterComposer,
      $$LedgerEntriesTableOrderingComposer,
      $$LedgerEntriesTableAnnotationComposer,
      $$LedgerEntriesTableCreateCompanionBuilder,
      $$LedgerEntriesTableUpdateCompanionBuilder,
      (
        LedgerEntryRow,
        BaseReferences<_$AppDatabase, $LedgerEntriesTable, LedgerEntryRow>,
      ),
      LedgerEntryRow,
      PrefetchHooks Function()
    >;
typedef $$SalesTableCreateCompanionBuilder =
    SalesCompanion Function({
      required String id,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<bool> isDeleted,
      required SyncState syncState,
      Value<int> localVersion,
      Value<String?> customerId,
      required String userId,
      required String productName,
      required int quantity,
      required int amountCents,
      required String paymentMethod,
      Value<String?> reference,
      Value<DateTime?> dueDate,
      Value<String?> notes,
      required DateTime saleDate,
      Value<int> rowid,
    });
typedef $$SalesTableUpdateCompanionBuilder =
    SalesCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDeleted,
      Value<SyncState> syncState,
      Value<int> localVersion,
      Value<String?> customerId,
      Value<String> userId,
      Value<String> productName,
      Value<int> quantity,
      Value<int> amountCents,
      Value<String> paymentMethod,
      Value<String?> reference,
      Value<DateTime?> dueDate,
      Value<String?> notes,
      Value<DateTime> saleDate,
      Value<int> rowid,
    });

class $$SalesTableFilterComposer extends Composer<_$AppDatabase, $SalesTable> {
  $$SalesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SyncState, SyncState, int> get syncState =>
      $composableBuilder(
        column: $table.syncState,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get saleDate => $composableBuilder(
    column: $table.saleDate,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SalesTableOrderingComposer
    extends Composer<_$AppDatabase, $SalesTable> {
  $$SalesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get saleDate => $composableBuilder(
    column: $table.saleDate,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SalesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SalesTable> {
  $$SalesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SyncState, int> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reference =>
      $composableBuilder(column: $table.reference, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get saleDate =>
      $composableBuilder(column: $table.saleDate, builder: (column) => column);
}

class $$SalesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SalesTable,
          SaleRow,
          $$SalesTableFilterComposer,
          $$SalesTableOrderingComposer,
          $$SalesTableAnnotationComposer,
          $$SalesTableCreateCompanionBuilder,
          $$SalesTableUpdateCompanionBuilder,
          (SaleRow, BaseReferences<_$AppDatabase, $SalesTable, SaleRow>),
          SaleRow,
          PrefetchHooks Function()
        > {
  $$SalesTableTableManager(_$AppDatabase db, $SalesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SalesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<SyncState> syncState = const Value.absent(),
                Value<int> localVersion = const Value.absent(),
                Value<String?> customerId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> productName = const Value.absent(),
                Value<int> quantity = const Value.absent(),
                Value<int> amountCents = const Value.absent(),
                Value<String> paymentMethod = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> saleDate = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SalesCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                syncState: syncState,
                localVersion: localVersion,
                customerId: customerId,
                userId: userId,
                productName: productName,
                quantity: quantity,
                amountCents: amountCents,
                paymentMethod: paymentMethod,
                reference: reference,
                dueDate: dueDate,
                notes: notes,
                saleDate: saleDate,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<bool> isDeleted = const Value.absent(),
                required SyncState syncState,
                Value<int> localVersion = const Value.absent(),
                Value<String?> customerId = const Value.absent(),
                required String userId,
                required String productName,
                required int quantity,
                required int amountCents,
                required String paymentMethod,
                Value<String?> reference = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                required DateTime saleDate,
                Value<int> rowid = const Value.absent(),
              }) => SalesCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                syncState: syncState,
                localVersion: localVersion,
                customerId: customerId,
                userId: userId,
                productName: productName,
                quantity: quantity,
                amountCents: amountCents,
                paymentMethod: paymentMethod,
                reference: reference,
                dueDate: dueDate,
                notes: notes,
                saleDate: saleDate,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SalesTable, SaleRow>(table),
                  BaseReferences<_$AppDatabase, $SalesTable, SaleRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SalesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SalesTable,
      SaleRow,
      $$SalesTableFilterComposer,
      $$SalesTableOrderingComposer,
      $$SalesTableAnnotationComposer,
      $$SalesTableCreateCompanionBuilder,
      $$SalesTableUpdateCompanionBuilder,
      (SaleRow, BaseReferences<_$AppDatabase, $SalesTable, SaleRow>),
      SaleRow,
      PrefetchHooks Function()
    >;
typedef $$StockRequestsTableCreateCompanionBuilder =
    StockRequestsCompanion Function({
      required String id,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<bool> isDeleted,
      required SyncState syncState,
      Value<int> localVersion,
      required String userId,
      required String productName,
      required DateTime neededOn,
      Value<String?> notes,
      Value<String?> purchaseOrderId,
      Value<int> rowid,
    });
typedef $$StockRequestsTableUpdateCompanionBuilder =
    StockRequestsCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDeleted,
      Value<SyncState> syncState,
      Value<int> localVersion,
      Value<String> userId,
      Value<String> productName,
      Value<DateTime> neededOn,
      Value<String?> notes,
      Value<String?> purchaseOrderId,
      Value<int> rowid,
    });

class $$StockRequestsTableFilterComposer
    extends Composer<_$AppDatabase, $StockRequestsTable> {
  $$StockRequestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SyncState, SyncState, int> get syncState =>
      $composableBuilder(
        column: $table.syncState,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get neededOn => $composableBuilder(
    column: $table.neededOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purchaseOrderId => $composableBuilder(
    column: $table.purchaseOrderId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StockRequestsTableOrderingComposer
    extends Composer<_$AppDatabase, $StockRequestsTable> {
  $$StockRequestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get neededOn => $composableBuilder(
    column: $table.neededOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purchaseOrderId => $composableBuilder(
    column: $table.purchaseOrderId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StockRequestsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StockRequestsTable> {
  $$StockRequestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SyncState, int> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get neededOn =>
      $composableBuilder(column: $table.neededOn, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get purchaseOrderId => $composableBuilder(
    column: $table.purchaseOrderId,
    builder: (column) => column,
  );
}

class $$StockRequestsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StockRequestsTable,
          StockRequestRow,
          $$StockRequestsTableFilterComposer,
          $$StockRequestsTableOrderingComposer,
          $$StockRequestsTableAnnotationComposer,
          $$StockRequestsTableCreateCompanionBuilder,
          $$StockRequestsTableUpdateCompanionBuilder,
          (
            StockRequestRow,
            BaseReferences<_$AppDatabase, $StockRequestsTable, StockRequestRow>,
          ),
          StockRequestRow,
          PrefetchHooks Function()
        > {
  $$StockRequestsTableTableManager(_$AppDatabase db, $StockRequestsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StockRequestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StockRequestsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StockRequestsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<SyncState> syncState = const Value.absent(),
                Value<int> localVersion = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> productName = const Value.absent(),
                Value<DateTime> neededOn = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> purchaseOrderId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StockRequestsCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                syncState: syncState,
                localVersion: localVersion,
                userId: userId,
                productName: productName,
                neededOn: neededOn,
                notes: notes,
                purchaseOrderId: purchaseOrderId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<bool> isDeleted = const Value.absent(),
                required SyncState syncState,
                Value<int> localVersion = const Value.absent(),
                required String userId,
                required String productName,
                required DateTime neededOn,
                Value<String?> notes = const Value.absent(),
                Value<String?> purchaseOrderId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StockRequestsCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                syncState: syncState,
                localVersion: localVersion,
                userId: userId,
                productName: productName,
                neededOn: neededOn,
                notes: notes,
                purchaseOrderId: purchaseOrderId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StockRequestsTable, StockRequestRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $StockRequestsTable,
                    StockRequestRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StockRequestsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StockRequestsTable,
      StockRequestRow,
      $$StockRequestsTableFilterComposer,
      $$StockRequestsTableOrderingComposer,
      $$StockRequestsTableAnnotationComposer,
      $$StockRequestsTableCreateCompanionBuilder,
      $$StockRequestsTableUpdateCompanionBuilder,
      (
        StockRequestRow,
        BaseReferences<_$AppDatabase, $StockRequestsTable, StockRequestRow>,
      ),
      StockRequestRow,
      PrefetchHooks Function()
    >;
typedef $$SuppliersTableCreateCompanionBuilder =
    SuppliersCompanion Function({
      required String id,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<bool> isDeleted,
      required SyncState syncState,
      Value<int> localVersion,
      required String name,
      Value<String?> phone,
      Value<String?> notes,
      required String createdBy,
      Value<int> rowid,
    });
typedef $$SuppliersTableUpdateCompanionBuilder =
    SuppliersCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDeleted,
      Value<SyncState> syncState,
      Value<int> localVersion,
      Value<String> name,
      Value<String?> phone,
      Value<String?> notes,
      Value<String> createdBy,
      Value<int> rowid,
    });

class $$SuppliersTableFilterComposer
    extends Composer<_$AppDatabase, $SuppliersTable> {
  $$SuppliersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SyncState, SyncState, int> get syncState =>
      $composableBuilder(
        column: $table.syncState,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SuppliersTableOrderingComposer
    extends Composer<_$AppDatabase, $SuppliersTable> {
  $$SuppliersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SuppliersTableAnnotationComposer
    extends Composer<_$AppDatabase, $SuppliersTable> {
  $$SuppliersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SyncState, int> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);
}

class $$SuppliersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SuppliersTable,
          SupplierRow,
          $$SuppliersTableFilterComposer,
          $$SuppliersTableOrderingComposer,
          $$SuppliersTableAnnotationComposer,
          $$SuppliersTableCreateCompanionBuilder,
          $$SuppliersTableUpdateCompanionBuilder,
          (
            SupplierRow,
            BaseReferences<_$AppDatabase, $SuppliersTable, SupplierRow>,
          ),
          SupplierRow,
          PrefetchHooks Function()
        > {
  $$SuppliersTableTableManager(_$AppDatabase db, $SuppliersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SuppliersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SuppliersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SuppliersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<SyncState> syncState = const Value.absent(),
                Value<int> localVersion = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> createdBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SuppliersCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                syncState: syncState,
                localVersion: localVersion,
                name: name,
                phone: phone,
                notes: notes,
                createdBy: createdBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<bool> isDeleted = const Value.absent(),
                required SyncState syncState,
                Value<int> localVersion = const Value.absent(),
                required String name,
                Value<String?> phone = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                required String createdBy,
                Value<int> rowid = const Value.absent(),
              }) => SuppliersCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                syncState: syncState,
                localVersion: localVersion,
                name: name,
                phone: phone,
                notes: notes,
                createdBy: createdBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SuppliersTable, SupplierRow>(table),
                  BaseReferences<_$AppDatabase, $SuppliersTable, SupplierRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SuppliersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SuppliersTable,
      SupplierRow,
      $$SuppliersTableFilterComposer,
      $$SuppliersTableOrderingComposer,
      $$SuppliersTableAnnotationComposer,
      $$SuppliersTableCreateCompanionBuilder,
      $$SuppliersTableUpdateCompanionBuilder,
      (
        SupplierRow,
        BaseReferences<_$AppDatabase, $SuppliersTable, SupplierRow>,
      ),
      SupplierRow,
      PrefetchHooks Function()
    >;
typedef $$SupplierEntriesTableCreateCompanionBuilder =
    SupplierEntriesCompanion Function({
      required String id,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<bool> isDeleted,
      required SyncState syncState,
      Value<int> localVersion,
      required String supplierId,
      required String userId,
      required String type,
      required int amountCents,
      required String description,
      required DateTime transactionDate,
      Value<DateTime?> dueDate,
      Value<String?> paymentMethod,
      Value<String?> reference,
      Value<String?> purchaseOrderId,
      Value<int> rowid,
    });
typedef $$SupplierEntriesTableUpdateCompanionBuilder =
    SupplierEntriesCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDeleted,
      Value<SyncState> syncState,
      Value<int> localVersion,
      Value<String> supplierId,
      Value<String> userId,
      Value<String> type,
      Value<int> amountCents,
      Value<String> description,
      Value<DateTime> transactionDate,
      Value<DateTime?> dueDate,
      Value<String?> paymentMethod,
      Value<String?> reference,
      Value<String?> purchaseOrderId,
      Value<int> rowid,
    });

class $$SupplierEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $SupplierEntriesTable> {
  $$SupplierEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SyncState, SyncState, int> get syncState =>
      $composableBuilder(
        column: $table.syncState,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supplierId => $composableBuilder(
    column: $table.supplierId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get transactionDate => $composableBuilder(
    column: $table.transactionDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purchaseOrderId => $composableBuilder(
    column: $table.purchaseOrderId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SupplierEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $SupplierEntriesTable> {
  $$SupplierEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supplierId => $composableBuilder(
    column: $table.supplierId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get transactionDate => $composableBuilder(
    column: $table.transactionDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purchaseOrderId => $composableBuilder(
    column: $table.purchaseOrderId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SupplierEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SupplierEntriesTable> {
  $$SupplierEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SyncState, int> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get supplierId => $composableBuilder(
    column: $table.supplierId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get transactionDate => $composableBuilder(
    column: $table.transactionDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reference =>
      $composableBuilder(column: $table.reference, builder: (column) => column);

  GeneratedColumn<String> get purchaseOrderId => $composableBuilder(
    column: $table.purchaseOrderId,
    builder: (column) => column,
  );
}

class $$SupplierEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SupplierEntriesTable,
          SupplierEntryRow,
          $$SupplierEntriesTableFilterComposer,
          $$SupplierEntriesTableOrderingComposer,
          $$SupplierEntriesTableAnnotationComposer,
          $$SupplierEntriesTableCreateCompanionBuilder,
          $$SupplierEntriesTableUpdateCompanionBuilder,
          (
            SupplierEntryRow,
            BaseReferences<
              _$AppDatabase,
              $SupplierEntriesTable,
              SupplierEntryRow
            >,
          ),
          SupplierEntryRow,
          PrefetchHooks Function()
        > {
  $$SupplierEntriesTableTableManager(
    _$AppDatabase db,
    $SupplierEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SupplierEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SupplierEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SupplierEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<SyncState> syncState = const Value.absent(),
                Value<int> localVersion = const Value.absent(),
                Value<String> supplierId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> amountCents = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<DateTime> transactionDate = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<String?> paymentMethod = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<String?> purchaseOrderId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SupplierEntriesCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                syncState: syncState,
                localVersion: localVersion,
                supplierId: supplierId,
                userId: userId,
                type: type,
                amountCents: amountCents,
                description: description,
                transactionDate: transactionDate,
                dueDate: dueDate,
                paymentMethod: paymentMethod,
                reference: reference,
                purchaseOrderId: purchaseOrderId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<bool> isDeleted = const Value.absent(),
                required SyncState syncState,
                Value<int> localVersion = const Value.absent(),
                required String supplierId,
                required String userId,
                required String type,
                required int amountCents,
                required String description,
                required DateTime transactionDate,
                Value<DateTime?> dueDate = const Value.absent(),
                Value<String?> paymentMethod = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<String?> purchaseOrderId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SupplierEntriesCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                syncState: syncState,
                localVersion: localVersion,
                supplierId: supplierId,
                userId: userId,
                type: type,
                amountCents: amountCents,
                description: description,
                transactionDate: transactionDate,
                dueDate: dueDate,
                paymentMethod: paymentMethod,
                reference: reference,
                purchaseOrderId: purchaseOrderId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SupplierEntriesTable, SupplierEntryRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SupplierEntriesTable,
                    SupplierEntryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SupplierEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SupplierEntriesTable,
      SupplierEntryRow,
      $$SupplierEntriesTableFilterComposer,
      $$SupplierEntriesTableOrderingComposer,
      $$SupplierEntriesTableAnnotationComposer,
      $$SupplierEntriesTableCreateCompanionBuilder,
      $$SupplierEntriesTableUpdateCompanionBuilder,
      (
        SupplierEntryRow,
        BaseReferences<_$AppDatabase, $SupplierEntriesTable, SupplierEntryRow>,
      ),
      SupplierEntryRow,
      PrefetchHooks Function()
    >;
typedef $$SyncMetaTableCreateCompanionBuilder =
    SyncMetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SyncMetaTableUpdateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetaTable,
          SyncMetaRow,
          $$SyncMetaTableFilterComposer,
          $$SyncMetaTableOrderingComposer,
          $$SyncMetaTableAnnotationComposer,
          $$SyncMetaTableCreateCompanionBuilder,
          $$SyncMetaTableUpdateCompanionBuilder,
          (
            SyncMetaRow,
            BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaRow>,
          ),
          SyncMetaRow,
          PrefetchHooks Function()
        > {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncMetaTable, SyncMetaRow>(table),
                  BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetaTable,
      SyncMetaRow,
      $$SyncMetaTableFilterComposer,
      $$SyncMetaTableOrderingComposer,
      $$SyncMetaTableAnnotationComposer,
      $$SyncMetaTableCreateCompanionBuilder,
      $$SyncMetaTableUpdateCompanionBuilder,
      (SyncMetaRow, BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaRow>),
      SyncMetaRow,
      PrefetchHooks Function()
    >;
typedef $$PushBatchesTableCreateCompanionBuilder =
    PushBatchesCompanion Function({
      required String operationId,
      required String body,
      required String records,
      required DateTime createdAt,
      Value<int> attempts,
      Value<int> rowid,
    });
typedef $$PushBatchesTableUpdateCompanionBuilder =
    PushBatchesCompanion Function({
      Value<String> operationId,
      Value<String> body,
      Value<String> records,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<int> rowid,
    });

class $$PushBatchesTableFilterComposer
    extends Composer<_$AppDatabase, $PushBatchesTable> {
  $$PushBatchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get records => $composableBuilder(
    column: $table.records,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PushBatchesTableOrderingComposer
    extends Composer<_$AppDatabase, $PushBatchesTable> {
  $$PushBatchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get records => $composableBuilder(
    column: $table.records,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PushBatchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PushBatchesTable> {
  $$PushBatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get records =>
      $composableBuilder(column: $table.records, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);
}

class $$PushBatchesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PushBatchesTable,
          PushBatchRow,
          $$PushBatchesTableFilterComposer,
          $$PushBatchesTableOrderingComposer,
          $$PushBatchesTableAnnotationComposer,
          $$PushBatchesTableCreateCompanionBuilder,
          $$PushBatchesTableUpdateCompanionBuilder,
          (
            PushBatchRow,
            BaseReferences<_$AppDatabase, $PushBatchesTable, PushBatchRow>,
          ),
          PushBatchRow,
          PrefetchHooks Function()
        > {
  $$PushBatchesTableTableManager(_$AppDatabase db, $PushBatchesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PushBatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PushBatchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PushBatchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> records = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PushBatchesCompanion(
                operationId: operationId,
                body: body,
                records: records,
                createdAt: createdAt,
                attempts: attempts,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String body,
                required String records,
                required DateTime createdAt,
                Value<int> attempts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PushBatchesCompanion.insert(
                operationId: operationId,
                body: body,
                records: records,
                createdAt: createdAt,
                attempts: attempts,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PushBatchesTable, PushBatchRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PushBatchesTable,
                    PushBatchRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PushBatchesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PushBatchesTable,
      PushBatchRow,
      $$PushBatchesTableFilterComposer,
      $$PushBatchesTableOrderingComposer,
      $$PushBatchesTableAnnotationComposer,
      $$PushBatchesTableCreateCompanionBuilder,
      $$PushBatchesTableUpdateCompanionBuilder,
      (
        PushBatchRow,
        BaseReferences<_$AppDatabase, $PushBatchesTable, PushBatchRow>,
      ),
      PushBatchRow,
      PrefetchHooks Function()
    >;
typedef $$SyncIssuesTableCreateCompanionBuilder =
    SyncIssuesCompanion Function({
      Value<int> id,
      required String recordTable,
      required String recordId,
      Value<String?> field,
      required String reason,
      Value<String?> detail,
      Value<String?> serverCopy,
      required DateTime createdAt,
    });
typedef $$SyncIssuesTableUpdateCompanionBuilder =
    SyncIssuesCompanion Function({
      Value<int> id,
      Value<String> recordTable,
      Value<String> recordId,
      Value<String?> field,
      Value<String> reason,
      Value<String?> detail,
      Value<String?> serverCopy,
      Value<DateTime> createdAt,
    });

class $$SyncIssuesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncIssuesTable> {
  $$SyncIssuesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordTable => $composableBuilder(
    column: $table.recordTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverCopy => $composableBuilder(
    column: $table.serverCopy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncIssuesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncIssuesTable> {
  $$SyncIssuesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordTable => $composableBuilder(
    column: $table.recordTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverCopy => $composableBuilder(
    column: $table.serverCopy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncIssuesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncIssuesTable> {
  $$SyncIssuesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get recordTable => $composableBuilder(
    column: $table.recordTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get field =>
      $composableBuilder(column: $table.field, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumn<String> get serverCopy => $composableBuilder(
    column: $table.serverCopy,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncIssuesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncIssuesTable,
          SyncIssueRow,
          $$SyncIssuesTableFilterComposer,
          $$SyncIssuesTableOrderingComposer,
          $$SyncIssuesTableAnnotationComposer,
          $$SyncIssuesTableCreateCompanionBuilder,
          $$SyncIssuesTableUpdateCompanionBuilder,
          (
            SyncIssueRow,
            BaseReferences<_$AppDatabase, $SyncIssuesTable, SyncIssueRow>,
          ),
          SyncIssueRow,
          PrefetchHooks Function()
        > {
  $$SyncIssuesTableTableManager(_$AppDatabase db, $SyncIssuesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncIssuesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncIssuesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncIssuesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> recordTable = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<String?> field = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<String?> detail = const Value.absent(),
                Value<String?> serverCopy = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SyncIssuesCompanion(
                id: id,
                recordTable: recordTable,
                recordId: recordId,
                field: field,
                reason: reason,
                detail: detail,
                serverCopy: serverCopy,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String recordTable,
                required String recordId,
                Value<String?> field = const Value.absent(),
                required String reason,
                Value<String?> detail = const Value.absent(),
                Value<String?> serverCopy = const Value.absent(),
                required DateTime createdAt,
              }) => SyncIssuesCompanion.insert(
                id: id,
                recordTable: recordTable,
                recordId: recordId,
                field: field,
                reason: reason,
                detail: detail,
                serverCopy: serverCopy,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncIssuesTable, SyncIssueRow>(table),
                  BaseReferences<_$AppDatabase, $SyncIssuesTable, SyncIssueRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncIssuesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncIssuesTable,
      SyncIssueRow,
      $$SyncIssuesTableFilterComposer,
      $$SyncIssuesTableOrderingComposer,
      $$SyncIssuesTableAnnotationComposer,
      $$SyncIssuesTableCreateCompanionBuilder,
      $$SyncIssuesTableUpdateCompanionBuilder,
      (
        SyncIssueRow,
        BaseReferences<_$AppDatabase, $SyncIssuesTable, SyncIssueRow>,
      ),
      SyncIssueRow,
      PrefetchHooks Function()
    >;
typedef $$ResyncSeenTableCreateCompanionBuilder =
    ResyncSeenCompanion Function({
      required String recordTable,
      required String recordId,
      Value<int> rowid,
    });
typedef $$ResyncSeenTableUpdateCompanionBuilder =
    ResyncSeenCompanion Function({
      Value<String> recordTable,
      Value<String> recordId,
      Value<int> rowid,
    });

class $$ResyncSeenTableFilterComposer
    extends Composer<_$AppDatabase, $ResyncSeenTable> {
  $$ResyncSeenTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recordTable => $composableBuilder(
    column: $table.recordTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ResyncSeenTableOrderingComposer
    extends Composer<_$AppDatabase, $ResyncSeenTable> {
  $$ResyncSeenTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recordTable => $composableBuilder(
    column: $table.recordTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ResyncSeenTableAnnotationComposer
    extends Composer<_$AppDatabase, $ResyncSeenTable> {
  $$ResyncSeenTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recordTable => $composableBuilder(
    column: $table.recordTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);
}

class $$ResyncSeenTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ResyncSeenTable,
          ResyncSeenRow,
          $$ResyncSeenTableFilterComposer,
          $$ResyncSeenTableOrderingComposer,
          $$ResyncSeenTableAnnotationComposer,
          $$ResyncSeenTableCreateCompanionBuilder,
          $$ResyncSeenTableUpdateCompanionBuilder,
          (
            ResyncSeenRow,
            BaseReferences<_$AppDatabase, $ResyncSeenTable, ResyncSeenRow>,
          ),
          ResyncSeenRow,
          PrefetchHooks Function()
        > {
  $$ResyncSeenTableTableManager(_$AppDatabase db, $ResyncSeenTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ResyncSeenTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ResyncSeenTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ResyncSeenTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> recordTable = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResyncSeenCompanion(
                recordTable: recordTable,
                recordId: recordId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recordTable,
                required String recordId,
                Value<int> rowid = const Value.absent(),
              }) => ResyncSeenCompanion.insert(
                recordTable: recordTable,
                recordId: recordId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ResyncSeenTable, ResyncSeenRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ResyncSeenTable,
                    ResyncSeenRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ResyncSeenTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ResyncSeenTable,
      ResyncSeenRow,
      $$ResyncSeenTableFilterComposer,
      $$ResyncSeenTableOrderingComposer,
      $$ResyncSeenTableAnnotationComposer,
      $$ResyncSeenTableCreateCompanionBuilder,
      $$ResyncSeenTableUpdateCompanionBuilder,
      (
        ResyncSeenRow,
        BaseReferences<_$AppDatabase, $ResyncSeenTable, ResyncSeenRow>,
      ),
      ResyncSeenRow,
      PrefetchHooks Function()
    >;
typedef $$StaffMembersTableCreateCompanionBuilder =
    StaffMembersCompanion Function({
      required String id,
      required String name,
      required String role,
      required bool isActive,
      Value<int> rowid,
    });
typedef $$StaffMembersTableUpdateCompanionBuilder =
    StaffMembersCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> role,
      Value<bool> isActive,
      Value<int> rowid,
    });

class $$StaffMembersTableFilterComposer
    extends Composer<_$AppDatabase, $StaffMembersTable> {
  $$StaffMembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StaffMembersTableOrderingComposer
    extends Composer<_$AppDatabase, $StaffMembersTable> {
  $$StaffMembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StaffMembersTableAnnotationComposer
    extends Composer<_$AppDatabase, $StaffMembersTable> {
  $$StaffMembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);
}

class $$StaffMembersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StaffMembersTable,
          StaffMemberRow,
          $$StaffMembersTableFilterComposer,
          $$StaffMembersTableOrderingComposer,
          $$StaffMembersTableAnnotationComposer,
          $$StaffMembersTableCreateCompanionBuilder,
          $$StaffMembersTableUpdateCompanionBuilder,
          (
            StaffMemberRow,
            BaseReferences<_$AppDatabase, $StaffMembersTable, StaffMemberRow>,
          ),
          StaffMemberRow,
          PrefetchHooks Function()
        > {
  $$StaffMembersTableTableManager(_$AppDatabase db, $StaffMembersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StaffMembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StaffMembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StaffMembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StaffMembersCompanion(
                id: id,
                name: name,
                role: role,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String role,
                required bool isActive,
                Value<int> rowid = const Value.absent(),
              }) => StaffMembersCompanion.insert(
                id: id,
                name: name,
                role: role,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StaffMembersTable, StaffMemberRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $StaffMembersTable,
                    StaffMemberRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StaffMembersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StaffMembersTable,
      StaffMemberRow,
      $$StaffMembersTableFilterComposer,
      $$StaffMembersTableOrderingComposer,
      $$StaffMembersTableAnnotationComposer,
      $$StaffMembersTableCreateCompanionBuilder,
      $$StaffMembersTableUpdateCompanionBuilder,
      (
        StaffMemberRow,
        BaseReferences<_$AppDatabase, $StaffMembersTable, StaffMemberRow>,
      ),
      StaffMemberRow,
      PrefetchHooks Function()
    >;
typedef $$ReportCacheTableCreateCompanionBuilder =
    ReportCacheCompanion Function({
      required String key,
      required String body,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$ReportCacheTableUpdateCompanionBuilder =
    ReportCacheCompanion Function({
      Value<String> key,
      Value<String> body,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$ReportCacheTableFilterComposer
    extends Composer<_$AppDatabase, $ReportCacheTable> {
  $$ReportCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReportCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $ReportCacheTable> {
  $$ReportCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReportCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReportCacheTable> {
  $$ReportCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$ReportCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReportCacheTable,
          ReportCacheRow,
          $$ReportCacheTableFilterComposer,
          $$ReportCacheTableOrderingComposer,
          $$ReportCacheTableAnnotationComposer,
          $$ReportCacheTableCreateCompanionBuilder,
          $$ReportCacheTableUpdateCompanionBuilder,
          (
            ReportCacheRow,
            BaseReferences<_$AppDatabase, $ReportCacheTable, ReportCacheRow>,
          ),
          ReportCacheRow,
          PrefetchHooks Function()
        > {
  $$ReportCacheTableTableManager(_$AppDatabase db, $ReportCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReportCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReportCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReportCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReportCacheCompanion(
                key: key,
                body: body,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String body,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReportCacheCompanion.insert(
                key: key,
                body: body,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReportCacheTable, ReportCacheRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReportCacheTable,
                    ReportCacheRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReportCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReportCacheTable,
      ReportCacheRow,
      $$ReportCacheTableFilterComposer,
      $$ReportCacheTableOrderingComposer,
      $$ReportCacheTableAnnotationComposer,
      $$ReportCacheTableCreateCompanionBuilder,
      $$ReportCacheTableUpdateCompanionBuilder,
      (
        ReportCacheRow,
        BaseReferences<_$AppDatabase, $ReportCacheTable, ReportCacheRow>,
      ),
      ReportCacheRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db, _db.customers);
  $$LedgerEntriesTableTableManager get ledgerEntries =>
      $$LedgerEntriesTableTableManager(_db, _db.ledgerEntries);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db, _db.sales);
  $$StockRequestsTableTableManager get stockRequests =>
      $$StockRequestsTableTableManager(_db, _db.stockRequests);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db, _db.suppliers);
  $$SupplierEntriesTableTableManager get supplierEntries =>
      $$SupplierEntriesTableTableManager(_db, _db.supplierEntries);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
  $$PushBatchesTableTableManager get pushBatches =>
      $$PushBatchesTableTableManager(_db, _db.pushBatches);
  $$SyncIssuesTableTableManager get syncIssues =>
      $$SyncIssuesTableTableManager(_db, _db.syncIssues);
  $$ResyncSeenTableTableManager get resyncSeen =>
      $$ResyncSeenTableTableManager(_db, _db.resyncSeen);
  $$StaffMembersTableTableManager get staffMembers =>
      $$StaffMembersTableTableManager(_db, _db.staffMembers);
  $$ReportCacheTableTableManager get reportCache =>
      $$ReportCacheTableTableManager(_db, _db.reportCache);
}
