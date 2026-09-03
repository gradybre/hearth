// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hearth_database.dart';

// ignore_for_file: type=lint
class $RecipesTable extends Recipes with TableInfo<$RecipesTable, RecipeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecipesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _servingsMeta = const VerificationMeta(
    'servings',
  );
  @override
  late final GeneratedColumn<double> servings = GeneratedColumn<double>(
    'servings',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _prepSecondsMeta = const VerificationMeta(
    'prepSeconds',
  );
  @override
  late final GeneratedColumn<int> prepSeconds = GeneratedColumn<int>(
    'prep_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cookSecondsMeta = const VerificationMeta(
    'cookSeconds',
  );
  @override
  late final GeneratedColumn<int> cookSeconds = GeneratedColumn<int>(
    'cook_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cuisineMeta = const VerificationMeta(
    'cuisine',
  );
  @override
  late final GeneratedColumn<String> cuisine = GeneratedColumn<String>(
    'cuisine',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> tags =
      GeneratedColumn<String>(
        'tags',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<String>>($RecipesTable.$convertertags);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cooked'),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _photoUrlMeta = const VerificationMeta(
    'photoUrl',
  );
  @override
  late final GeneratedColumn<String> photoUrl = GeneratedColumn<String>(
    'photo_url',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    title,
    servings,
    prepSeconds,
    cookSeconds,
    cuisine,
    tags,
    kind,
    source,
    photoUrl,
    notes,
    createdBy,
    isDeleted,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recipes';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecipeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('servings')) {
      context.handle(
        _servingsMeta,
        servings.isAcceptableOrUnknown(data['servings']!, _servingsMeta),
      );
    } else if (isInserting) {
      context.missing(_servingsMeta);
    }
    if (data.containsKey('prep_seconds')) {
      context.handle(
        _prepSecondsMeta,
        prepSeconds.isAcceptableOrUnknown(
          data['prep_seconds']!,
          _prepSecondsMeta,
        ),
      );
    }
    if (data.containsKey('cook_seconds')) {
      context.handle(
        _cookSecondsMeta,
        cookSeconds.isAcceptableOrUnknown(
          data['cook_seconds']!,
          _cookSecondsMeta,
        ),
      );
    }
    if (data.containsKey('cuisine')) {
      context.handle(
        _cuisineMeta,
        cuisine.isAcceptableOrUnknown(data['cuisine']!, _cuisineMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('photo_url')) {
      context.handle(
        _photoUrlMeta,
        photoUrl.isAcceptableOrUnknown(data['photo_url']!, _photoUrlMeta),
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
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecipeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecipeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      servings: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}servings'],
      )!,
      prepSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}prep_seconds'],
      ),
      cookSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cook_seconds'],
      ),
      cuisine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cuisine'],
      ),
      tags: $RecipesTable.$convertertags.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}tags'],
        )!,
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      photoUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_url'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      ),
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RecipesTable createAlias(String alias) {
    return $RecipesTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $convertertags =
      const StringListConverter();
}

class RecipeRow extends DataClass implements Insertable<RecipeRow> {
  final String id;
  final String householdId;
  final String title;
  final double servings;
  final int? prepSeconds;
  final int? cookSeconds;
  final String? cuisine;
  final List<String> tags;

  /// Cooked, or eaten out (spec §5.2). An eaten-out recipe never reaches the
  /// shopping list.
  final String kind;
  final String source;
  final String? photoUrl;
  final String? notes;
  final String? createdBy;
  final bool isDeleted;
  final DateTime updatedAt;
  const RecipeRow({
    required this.id,
    required this.householdId,
    required this.title,
    required this.servings,
    this.prepSeconds,
    this.cookSeconds,
    this.cuisine,
    required this.tags,
    required this.kind,
    required this.source,
    this.photoUrl,
    this.notes,
    this.createdBy,
    required this.isDeleted,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['title'] = Variable<String>(title);
    map['servings'] = Variable<double>(servings);
    if (!nullToAbsent || prepSeconds != null) {
      map['prep_seconds'] = Variable<int>(prepSeconds);
    }
    if (!nullToAbsent || cookSeconds != null) {
      map['cook_seconds'] = Variable<int>(cookSeconds);
    }
    if (!nullToAbsent || cuisine != null) {
      map['cuisine'] = Variable<String>(cuisine);
    }
    {
      map['tags'] = Variable<String>($RecipesTable.$convertertags.toSql(tags));
    }
    map['kind'] = Variable<String>(kind);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || photoUrl != null) {
      map['photo_url'] = Variable<String>(photoUrl);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<String>(createdBy);
    }
    map['is_deleted'] = Variable<bool>(isDeleted);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RecipesCompanion toCompanion(bool nullToAbsent) {
    return RecipesCompanion(
      id: Value(id),
      householdId: Value(householdId),
      title: Value(title),
      servings: Value(servings),
      prepSeconds: prepSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(prepSeconds),
      cookSeconds: cookSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(cookSeconds),
      cuisine: cuisine == null && nullToAbsent
          ? const Value.absent()
          : Value(cuisine),
      tags: Value(tags),
      kind: Value(kind),
      source: Value(source),
      photoUrl: photoUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(photoUrl),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
      isDeleted: Value(isDeleted),
      updatedAt: Value(updatedAt),
    );
  }

  factory RecipeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecipeRow(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      title: serializer.fromJson<String>(json['title']),
      servings: serializer.fromJson<double>(json['servings']),
      prepSeconds: serializer.fromJson<int?>(json['prepSeconds']),
      cookSeconds: serializer.fromJson<int?>(json['cookSeconds']),
      cuisine: serializer.fromJson<String?>(json['cuisine']),
      tags: serializer.fromJson<List<String>>(json['tags']),
      kind: serializer.fromJson<String>(json['kind']),
      source: serializer.fromJson<String>(json['source']),
      photoUrl: serializer.fromJson<String?>(json['photoUrl']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'title': serializer.toJson<String>(title),
      'servings': serializer.toJson<double>(servings),
      'prepSeconds': serializer.toJson<int?>(prepSeconds),
      'cookSeconds': serializer.toJson<int?>(cookSeconds),
      'cuisine': serializer.toJson<String?>(cuisine),
      'tags': serializer.toJson<List<String>>(tags),
      'kind': serializer.toJson<String>(kind),
      'source': serializer.toJson<String>(source),
      'photoUrl': serializer.toJson<String?>(photoUrl),
      'notes': serializer.toJson<String?>(notes),
      'createdBy': serializer.toJson<String?>(createdBy),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RecipeRow copyWith({
    String? id,
    String? householdId,
    String? title,
    double? servings,
    Value<int?> prepSeconds = const Value.absent(),
    Value<int?> cookSeconds = const Value.absent(),
    Value<String?> cuisine = const Value.absent(),
    List<String>? tags,
    String? kind,
    String? source,
    Value<String?> photoUrl = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> createdBy = const Value.absent(),
    bool? isDeleted,
    DateTime? updatedAt,
  }) => RecipeRow(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    title: title ?? this.title,
    servings: servings ?? this.servings,
    prepSeconds: prepSeconds.present ? prepSeconds.value : this.prepSeconds,
    cookSeconds: cookSeconds.present ? cookSeconds.value : this.cookSeconds,
    cuisine: cuisine.present ? cuisine.value : this.cuisine,
    tags: tags ?? this.tags,
    kind: kind ?? this.kind,
    source: source ?? this.source,
    photoUrl: photoUrl.present ? photoUrl.value : this.photoUrl,
    notes: notes.present ? notes.value : this.notes,
    createdBy: createdBy.present ? createdBy.value : this.createdBy,
    isDeleted: isDeleted ?? this.isDeleted,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RecipeRow copyWithCompanion(RecipesCompanion data) {
    return RecipeRow(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      title: data.title.present ? data.title.value : this.title,
      servings: data.servings.present ? data.servings.value : this.servings,
      prepSeconds: data.prepSeconds.present
          ? data.prepSeconds.value
          : this.prepSeconds,
      cookSeconds: data.cookSeconds.present
          ? data.cookSeconds.value
          : this.cookSeconds,
      cuisine: data.cuisine.present ? data.cuisine.value : this.cuisine,
      tags: data.tags.present ? data.tags.value : this.tags,
      kind: data.kind.present ? data.kind.value : this.kind,
      source: data.source.present ? data.source.value : this.source,
      photoUrl: data.photoUrl.present ? data.photoUrl.value : this.photoUrl,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecipeRow(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('title: $title, ')
          ..write('servings: $servings, ')
          ..write('prepSeconds: $prepSeconds, ')
          ..write('cookSeconds: $cookSeconds, ')
          ..write('cuisine: $cuisine, ')
          ..write('tags: $tags, ')
          ..write('kind: $kind, ')
          ..write('source: $source, ')
          ..write('photoUrl: $photoUrl, ')
          ..write('notes: $notes, ')
          ..write('createdBy: $createdBy, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    title,
    servings,
    prepSeconds,
    cookSeconds,
    cuisine,
    tags,
    kind,
    source,
    photoUrl,
    notes,
    createdBy,
    isDeleted,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecipeRow &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.title == this.title &&
          other.servings == this.servings &&
          other.prepSeconds == this.prepSeconds &&
          other.cookSeconds == this.cookSeconds &&
          other.cuisine == this.cuisine &&
          other.tags == this.tags &&
          other.kind == this.kind &&
          other.source == this.source &&
          other.photoUrl == this.photoUrl &&
          other.notes == this.notes &&
          other.createdBy == this.createdBy &&
          other.isDeleted == this.isDeleted &&
          other.updatedAt == this.updatedAt);
}

class RecipesCompanion extends UpdateCompanion<RecipeRow> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> title;
  final Value<double> servings;
  final Value<int?> prepSeconds;
  final Value<int?> cookSeconds;
  final Value<String?> cuisine;
  final Value<List<String>> tags;
  final Value<String> kind;
  final Value<String> source;
  final Value<String?> photoUrl;
  final Value<String?> notes;
  final Value<String?> createdBy;
  final Value<bool> isDeleted;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const RecipesCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.title = const Value.absent(),
    this.servings = const Value.absent(),
    this.prepSeconds = const Value.absent(),
    this.cookSeconds = const Value.absent(),
    this.cuisine = const Value.absent(),
    this.tags = const Value.absent(),
    this.kind = const Value.absent(),
    this.source = const Value.absent(),
    this.photoUrl = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecipesCompanion.insert({
    required String id,
    required String householdId,
    required String title,
    required double servings,
    this.prepSeconds = const Value.absent(),
    this.cookSeconds = const Value.absent(),
    this.cuisine = const Value.absent(),
    this.tags = const Value.absent(),
    this.kind = const Value.absent(),
    this.source = const Value.absent(),
    this.photoUrl = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.isDeleted = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       title = Value(title),
       servings = Value(servings),
       updatedAt = Value(updatedAt);
  static Insertable<RecipeRow> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? title,
    Expression<double>? servings,
    Expression<int>? prepSeconds,
    Expression<int>? cookSeconds,
    Expression<String>? cuisine,
    Expression<String>? tags,
    Expression<String>? kind,
    Expression<String>? source,
    Expression<String>? photoUrl,
    Expression<String>? notes,
    Expression<String>? createdBy,
    Expression<bool>? isDeleted,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (title != null) 'title': title,
      if (servings != null) 'servings': servings,
      if (prepSeconds != null) 'prep_seconds': prepSeconds,
      if (cookSeconds != null) 'cook_seconds': cookSeconds,
      if (cuisine != null) 'cuisine': cuisine,
      if (tags != null) 'tags': tags,
      if (kind != null) 'kind': kind,
      if (source != null) 'source': source,
      if (photoUrl != null) 'photo_url': photoUrl,
      if (notes != null) 'notes': notes,
      if (createdBy != null) 'created_by': createdBy,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecipesCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? title,
    Value<double>? servings,
    Value<int?>? prepSeconds,
    Value<int?>? cookSeconds,
    Value<String?>? cuisine,
    Value<List<String>>? tags,
    Value<String>? kind,
    Value<String>? source,
    Value<String?>? photoUrl,
    Value<String?>? notes,
    Value<String?>? createdBy,
    Value<bool>? isDeleted,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return RecipesCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      title: title ?? this.title,
      servings: servings ?? this.servings,
      prepSeconds: prepSeconds ?? this.prepSeconds,
      cookSeconds: cookSeconds ?? this.cookSeconds,
      cuisine: cuisine ?? this.cuisine,
      tags: tags ?? this.tags,
      kind: kind ?? this.kind,
      source: source ?? this.source,
      photoUrl: photoUrl ?? this.photoUrl,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      isDeleted: isDeleted ?? this.isDeleted,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (servings.present) {
      map['servings'] = Variable<double>(servings.value);
    }
    if (prepSeconds.present) {
      map['prep_seconds'] = Variable<int>(prepSeconds.value);
    }
    if (cookSeconds.present) {
      map['cook_seconds'] = Variable<int>(cookSeconds.value);
    }
    if (cuisine.present) {
      map['cuisine'] = Variable<String>(cuisine.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(
        $RecipesTable.$convertertags.toSql(tags.value),
      );
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (photoUrl.present) {
      map['photo_url'] = Variable<String>(photoUrl.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecipesCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('title: $title, ')
          ..write('servings: $servings, ')
          ..write('prepSeconds: $prepSeconds, ')
          ..write('cookSeconds: $cookSeconds, ')
          ..write('cuisine: $cuisine, ')
          ..write('tags: $tags, ')
          ..write('kind: $kind, ')
          ..write('source: $source, ')
          ..write('photoUrl: $photoUrl, ')
          ..write('notes: $notes, ')
          ..write('createdBy: $createdBy, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecipeSectionsTable extends RecipeSections
    with TableInfo<$RecipeSectionsTable, RecipeSectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecipeSectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recipeIdMeta = const VerificationMeta(
    'recipeId',
  );
  @override
  late final GeneratedColumn<String> recipeId = GeneratedColumn<String>(
    'recipe_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES recipes (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Main'),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, recipeId, name, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recipe_sections';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecipeSectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('recipe_id')) {
      context.handle(
        _recipeIdMeta,
        recipeId.isAcceptableOrUnknown(data['recipe_id']!, _recipeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recipeIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecipeSectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecipeSectionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      recipeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $RecipeSectionsTable createAlias(String alias) {
    return $RecipeSectionsTable(attachedDatabase, alias);
  }
}

class RecipeSectionRow extends DataClass
    implements Insertable<RecipeSectionRow> {
  final String id;
  final String recipeId;
  final String name;
  final int sortOrder;
  const RecipeSectionRow({
    required this.id,
    required this.recipeId,
    required this.name,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['recipe_id'] = Variable<String>(recipeId);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  RecipeSectionsCompanion toCompanion(bool nullToAbsent) {
    return RecipeSectionsCompanion(
      id: Value(id),
      recipeId: Value(recipeId),
      name: Value(name),
      sortOrder: Value(sortOrder),
    );
  }

  factory RecipeSectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecipeSectionRow(
      id: serializer.fromJson<String>(json['id']),
      recipeId: serializer.fromJson<String>(json['recipeId']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'recipeId': serializer.toJson<String>(recipeId),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  RecipeSectionRow copyWith({
    String? id,
    String? recipeId,
    String? name,
    int? sortOrder,
  }) => RecipeSectionRow(
    id: id ?? this.id,
    recipeId: recipeId ?? this.recipeId,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  RecipeSectionRow copyWithCompanion(RecipeSectionsCompanion data) {
    return RecipeSectionRow(
      id: data.id.present ? data.id.value : this.id,
      recipeId: data.recipeId.present ? data.recipeId.value : this.recipeId,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecipeSectionRow(')
          ..write('id: $id, ')
          ..write('recipeId: $recipeId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, recipeId, name, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecipeSectionRow &&
          other.id == this.id &&
          other.recipeId == this.recipeId &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder);
}

class RecipeSectionsCompanion extends UpdateCompanion<RecipeSectionRow> {
  final Value<String> id;
  final Value<String> recipeId;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const RecipeSectionsCompanion({
    this.id = const Value.absent(),
    this.recipeId = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecipeSectionsCompanion.insert({
    required String id,
    required String recipeId,
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       recipeId = Value(recipeId);
  static Insertable<RecipeSectionRow> custom({
    Expression<String>? id,
    Expression<String>? recipeId,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recipeId != null) 'recipe_id': recipeId,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecipeSectionsCompanion copyWith({
    Value<String>? id,
    Value<String>? recipeId,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return RecipeSectionsCompanion(
      id: id ?? this.id,
      recipeId: recipeId ?? this.recipeId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (recipeId.present) {
      map['recipe_id'] = Variable<String>(recipeId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecipeSectionsCompanion(')
          ..write('id: $id, ')
          ..write('recipeId: $recipeId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecipeIngredientsTable extends RecipeIngredients
    with TableInfo<$RecipeIngredientsTable, RecipeIngredientRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecipeIngredientsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recipeIdMeta = const VerificationMeta(
    'recipeId',
  );
  @override
  late final GeneratedColumn<String> recipeId = GeneratedColumn<String>(
    'recipe_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES recipes (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sectionIdMeta = const VerificationMeta(
    'sectionId',
  );
  @override
  late final GeneratedColumn<String> sectionId = GeneratedColumn<String>(
    'section_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _foodIdMeta = const VerificationMeta('foodId');
  @override
  late final GeneratedColumn<String> foodId = GeneratedColumn<String>(
    'food_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawTextMeta = const VerificationMeta(
    'rawText',
  );
  @override
  late final GeneratedColumn<String> rawText = GeneratedColumn<String>(
    'raw_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _quantityCanonicalMeta = const VerificationMeta(
    'quantityCanonical',
  );
  @override
  late final GeneratedColumn<double> quantityCanonical =
      GeneratedColumn<double>(
        'quantity_canonical',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _quantityKindMeta = const VerificationMeta(
    'quantityKind',
  );
  @override
  late final GeneratedColumn<String> quantityKind = GeneratedColumn<String>(
    'quantity_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quantityUnitMeta = const VerificationMeta(
    'quantityUnit',
  );
  @override
  late final GeneratedColumn<String> quantityUnit = GeneratedColumn<String>(
    'quantity_unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _prepNoteMeta = const VerificationMeta(
    'prepNote',
  );
  @override
  late final GeneratedColumn<String> prepNote = GeneratedColumn<String>(
    'prep_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isOptionalMeta = const VerificationMeta(
    'isOptional',
  );
  @override
  late final GeneratedColumn<bool> isOptional = GeneratedColumn<bool>(
    'is_optional',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_optional" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _needsNoMatchMeta = const VerificationMeta(
    'needsNoMatch',
  );
  @override
  late final GeneratedColumn<bool> needsNoMatch = GeneratedColumn<bool>(
    'needs_no_match',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_no_match" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    recipeId,
    sectionId,
    foodId,
    rawText,
    name,
    quantityCanonical,
    quantityKind,
    quantityUnit,
    prepNote,
    isOptional,
    needsNoMatch,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recipe_ingredients';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecipeIngredientRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('recipe_id')) {
      context.handle(
        _recipeIdMeta,
        recipeId.isAcceptableOrUnknown(data['recipe_id']!, _recipeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recipeIdMeta);
    }
    if (data.containsKey('section_id')) {
      context.handle(
        _sectionIdMeta,
        sectionId.isAcceptableOrUnknown(data['section_id']!, _sectionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sectionIdMeta);
    }
    if (data.containsKey('food_id')) {
      context.handle(
        _foodIdMeta,
        foodId.isAcceptableOrUnknown(data['food_id']!, _foodIdMeta),
      );
    }
    if (data.containsKey('raw_text')) {
      context.handle(
        _rawTextMeta,
        rawText.isAcceptableOrUnknown(data['raw_text']!, _rawTextMeta),
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
    if (data.containsKey('quantity_canonical')) {
      context.handle(
        _quantityCanonicalMeta,
        quantityCanonical.isAcceptableOrUnknown(
          data['quantity_canonical']!,
          _quantityCanonicalMeta,
        ),
      );
    }
    if (data.containsKey('quantity_kind')) {
      context.handle(
        _quantityKindMeta,
        quantityKind.isAcceptableOrUnknown(
          data['quantity_kind']!,
          _quantityKindMeta,
        ),
      );
    }
    if (data.containsKey('quantity_unit')) {
      context.handle(
        _quantityUnitMeta,
        quantityUnit.isAcceptableOrUnknown(
          data['quantity_unit']!,
          _quantityUnitMeta,
        ),
      );
    }
    if (data.containsKey('prep_note')) {
      context.handle(
        _prepNoteMeta,
        prepNote.isAcceptableOrUnknown(data['prep_note']!, _prepNoteMeta),
      );
    }
    if (data.containsKey('is_optional')) {
      context.handle(
        _isOptionalMeta,
        isOptional.isAcceptableOrUnknown(data['is_optional']!, _isOptionalMeta),
      );
    }
    if (data.containsKey('needs_no_match')) {
      context.handle(
        _needsNoMatchMeta,
        needsNoMatch.isAcceptableOrUnknown(
          data['needs_no_match']!,
          _needsNoMatchMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecipeIngredientRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecipeIngredientRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      recipeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_id'],
      )!,
      sectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_id'],
      )!,
      foodId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}food_id'],
      ),
      rawText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_text'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      quantityCanonical: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quantity_canonical'],
      ),
      quantityKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quantity_kind'],
      ),
      quantityUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quantity_unit'],
      ),
      prepNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prep_note'],
      ),
      isOptional: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_optional'],
      )!,
      needsNoMatch: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_no_match'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $RecipeIngredientsTable createAlias(String alias) {
    return $RecipeIngredientsTable(attachedDatabase, alias);
  }
}

class RecipeIngredientRow extends DataClass
    implements Insertable<RecipeIngredientRow> {
  final String id;
  final String recipeId;
  final String sectionId;
  final String? foodId;
  final String? rawText;
  final String name;

  /// Stored canonically: ml, g, or items. Null for "salt to taste".
  final double? quantityCanonical;
  final String? quantityKind;

  /// The unit the line was authored in — a display hint only.
  final String? quantityUnit;
  final String? prepNote;
  final bool isOptional;

  /// A line that will never have a food behind it: salt, pepper, a spice
  /// (spec §5.3). Distinct from [isOptional], which is what the recipe said.
  final bool needsNoMatch;
  final int sortOrder;
  const RecipeIngredientRow({
    required this.id,
    required this.recipeId,
    required this.sectionId,
    this.foodId,
    this.rawText,
    required this.name,
    this.quantityCanonical,
    this.quantityKind,
    this.quantityUnit,
    this.prepNote,
    required this.isOptional,
    required this.needsNoMatch,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['recipe_id'] = Variable<String>(recipeId);
    map['section_id'] = Variable<String>(sectionId);
    if (!nullToAbsent || foodId != null) {
      map['food_id'] = Variable<String>(foodId);
    }
    if (!nullToAbsent || rawText != null) {
      map['raw_text'] = Variable<String>(rawText);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || quantityCanonical != null) {
      map['quantity_canonical'] = Variable<double>(quantityCanonical);
    }
    if (!nullToAbsent || quantityKind != null) {
      map['quantity_kind'] = Variable<String>(quantityKind);
    }
    if (!nullToAbsent || quantityUnit != null) {
      map['quantity_unit'] = Variable<String>(quantityUnit);
    }
    if (!nullToAbsent || prepNote != null) {
      map['prep_note'] = Variable<String>(prepNote);
    }
    map['is_optional'] = Variable<bool>(isOptional);
    map['needs_no_match'] = Variable<bool>(needsNoMatch);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  RecipeIngredientsCompanion toCompanion(bool nullToAbsent) {
    return RecipeIngredientsCompanion(
      id: Value(id),
      recipeId: Value(recipeId),
      sectionId: Value(sectionId),
      foodId: foodId == null && nullToAbsent
          ? const Value.absent()
          : Value(foodId),
      rawText: rawText == null && nullToAbsent
          ? const Value.absent()
          : Value(rawText),
      name: Value(name),
      quantityCanonical: quantityCanonical == null && nullToAbsent
          ? const Value.absent()
          : Value(quantityCanonical),
      quantityKind: quantityKind == null && nullToAbsent
          ? const Value.absent()
          : Value(quantityKind),
      quantityUnit: quantityUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(quantityUnit),
      prepNote: prepNote == null && nullToAbsent
          ? const Value.absent()
          : Value(prepNote),
      isOptional: Value(isOptional),
      needsNoMatch: Value(needsNoMatch),
      sortOrder: Value(sortOrder),
    );
  }

  factory RecipeIngredientRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecipeIngredientRow(
      id: serializer.fromJson<String>(json['id']),
      recipeId: serializer.fromJson<String>(json['recipeId']),
      sectionId: serializer.fromJson<String>(json['sectionId']),
      foodId: serializer.fromJson<String?>(json['foodId']),
      rawText: serializer.fromJson<String?>(json['rawText']),
      name: serializer.fromJson<String>(json['name']),
      quantityCanonical: serializer.fromJson<double?>(
        json['quantityCanonical'],
      ),
      quantityKind: serializer.fromJson<String?>(json['quantityKind']),
      quantityUnit: serializer.fromJson<String?>(json['quantityUnit']),
      prepNote: serializer.fromJson<String?>(json['prepNote']),
      isOptional: serializer.fromJson<bool>(json['isOptional']),
      needsNoMatch: serializer.fromJson<bool>(json['needsNoMatch']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'recipeId': serializer.toJson<String>(recipeId),
      'sectionId': serializer.toJson<String>(sectionId),
      'foodId': serializer.toJson<String?>(foodId),
      'rawText': serializer.toJson<String?>(rawText),
      'name': serializer.toJson<String>(name),
      'quantityCanonical': serializer.toJson<double?>(quantityCanonical),
      'quantityKind': serializer.toJson<String?>(quantityKind),
      'quantityUnit': serializer.toJson<String?>(quantityUnit),
      'prepNote': serializer.toJson<String?>(prepNote),
      'isOptional': serializer.toJson<bool>(isOptional),
      'needsNoMatch': serializer.toJson<bool>(needsNoMatch),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  RecipeIngredientRow copyWith({
    String? id,
    String? recipeId,
    String? sectionId,
    Value<String?> foodId = const Value.absent(),
    Value<String?> rawText = const Value.absent(),
    String? name,
    Value<double?> quantityCanonical = const Value.absent(),
    Value<String?> quantityKind = const Value.absent(),
    Value<String?> quantityUnit = const Value.absent(),
    Value<String?> prepNote = const Value.absent(),
    bool? isOptional,
    bool? needsNoMatch,
    int? sortOrder,
  }) => RecipeIngredientRow(
    id: id ?? this.id,
    recipeId: recipeId ?? this.recipeId,
    sectionId: sectionId ?? this.sectionId,
    foodId: foodId.present ? foodId.value : this.foodId,
    rawText: rawText.present ? rawText.value : this.rawText,
    name: name ?? this.name,
    quantityCanonical: quantityCanonical.present
        ? quantityCanonical.value
        : this.quantityCanonical,
    quantityKind: quantityKind.present ? quantityKind.value : this.quantityKind,
    quantityUnit: quantityUnit.present ? quantityUnit.value : this.quantityUnit,
    prepNote: prepNote.present ? prepNote.value : this.prepNote,
    isOptional: isOptional ?? this.isOptional,
    needsNoMatch: needsNoMatch ?? this.needsNoMatch,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  RecipeIngredientRow copyWithCompanion(RecipeIngredientsCompanion data) {
    return RecipeIngredientRow(
      id: data.id.present ? data.id.value : this.id,
      recipeId: data.recipeId.present ? data.recipeId.value : this.recipeId,
      sectionId: data.sectionId.present ? data.sectionId.value : this.sectionId,
      foodId: data.foodId.present ? data.foodId.value : this.foodId,
      rawText: data.rawText.present ? data.rawText.value : this.rawText,
      name: data.name.present ? data.name.value : this.name,
      quantityCanonical: data.quantityCanonical.present
          ? data.quantityCanonical.value
          : this.quantityCanonical,
      quantityKind: data.quantityKind.present
          ? data.quantityKind.value
          : this.quantityKind,
      quantityUnit: data.quantityUnit.present
          ? data.quantityUnit.value
          : this.quantityUnit,
      prepNote: data.prepNote.present ? data.prepNote.value : this.prepNote,
      isOptional: data.isOptional.present
          ? data.isOptional.value
          : this.isOptional,
      needsNoMatch: data.needsNoMatch.present
          ? data.needsNoMatch.value
          : this.needsNoMatch,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecipeIngredientRow(')
          ..write('id: $id, ')
          ..write('recipeId: $recipeId, ')
          ..write('sectionId: $sectionId, ')
          ..write('foodId: $foodId, ')
          ..write('rawText: $rawText, ')
          ..write('name: $name, ')
          ..write('quantityCanonical: $quantityCanonical, ')
          ..write('quantityKind: $quantityKind, ')
          ..write('quantityUnit: $quantityUnit, ')
          ..write('prepNote: $prepNote, ')
          ..write('isOptional: $isOptional, ')
          ..write('needsNoMatch: $needsNoMatch, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    recipeId,
    sectionId,
    foodId,
    rawText,
    name,
    quantityCanonical,
    quantityKind,
    quantityUnit,
    prepNote,
    isOptional,
    needsNoMatch,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecipeIngredientRow &&
          other.id == this.id &&
          other.recipeId == this.recipeId &&
          other.sectionId == this.sectionId &&
          other.foodId == this.foodId &&
          other.rawText == this.rawText &&
          other.name == this.name &&
          other.quantityCanonical == this.quantityCanonical &&
          other.quantityKind == this.quantityKind &&
          other.quantityUnit == this.quantityUnit &&
          other.prepNote == this.prepNote &&
          other.isOptional == this.isOptional &&
          other.needsNoMatch == this.needsNoMatch &&
          other.sortOrder == this.sortOrder);
}

class RecipeIngredientsCompanion extends UpdateCompanion<RecipeIngredientRow> {
  final Value<String> id;
  final Value<String> recipeId;
  final Value<String> sectionId;
  final Value<String?> foodId;
  final Value<String?> rawText;
  final Value<String> name;
  final Value<double?> quantityCanonical;
  final Value<String?> quantityKind;
  final Value<String?> quantityUnit;
  final Value<String?> prepNote;
  final Value<bool> isOptional;
  final Value<bool> needsNoMatch;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const RecipeIngredientsCompanion({
    this.id = const Value.absent(),
    this.recipeId = const Value.absent(),
    this.sectionId = const Value.absent(),
    this.foodId = const Value.absent(),
    this.rawText = const Value.absent(),
    this.name = const Value.absent(),
    this.quantityCanonical = const Value.absent(),
    this.quantityKind = const Value.absent(),
    this.quantityUnit = const Value.absent(),
    this.prepNote = const Value.absent(),
    this.isOptional = const Value.absent(),
    this.needsNoMatch = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecipeIngredientsCompanion.insert({
    required String id,
    required String recipeId,
    required String sectionId,
    this.foodId = const Value.absent(),
    this.rawText = const Value.absent(),
    required String name,
    this.quantityCanonical = const Value.absent(),
    this.quantityKind = const Value.absent(),
    this.quantityUnit = const Value.absent(),
    this.prepNote = const Value.absent(),
    this.isOptional = const Value.absent(),
    this.needsNoMatch = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       recipeId = Value(recipeId),
       sectionId = Value(sectionId),
       name = Value(name);
  static Insertable<RecipeIngredientRow> custom({
    Expression<String>? id,
    Expression<String>? recipeId,
    Expression<String>? sectionId,
    Expression<String>? foodId,
    Expression<String>? rawText,
    Expression<String>? name,
    Expression<double>? quantityCanonical,
    Expression<String>? quantityKind,
    Expression<String>? quantityUnit,
    Expression<String>? prepNote,
    Expression<bool>? isOptional,
    Expression<bool>? needsNoMatch,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recipeId != null) 'recipe_id': recipeId,
      if (sectionId != null) 'section_id': sectionId,
      if (foodId != null) 'food_id': foodId,
      if (rawText != null) 'raw_text': rawText,
      if (name != null) 'name': name,
      if (quantityCanonical != null) 'quantity_canonical': quantityCanonical,
      if (quantityKind != null) 'quantity_kind': quantityKind,
      if (quantityUnit != null) 'quantity_unit': quantityUnit,
      if (prepNote != null) 'prep_note': prepNote,
      if (isOptional != null) 'is_optional': isOptional,
      if (needsNoMatch != null) 'needs_no_match': needsNoMatch,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecipeIngredientsCompanion copyWith({
    Value<String>? id,
    Value<String>? recipeId,
    Value<String>? sectionId,
    Value<String?>? foodId,
    Value<String?>? rawText,
    Value<String>? name,
    Value<double?>? quantityCanonical,
    Value<String?>? quantityKind,
    Value<String?>? quantityUnit,
    Value<String?>? prepNote,
    Value<bool>? isOptional,
    Value<bool>? needsNoMatch,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return RecipeIngredientsCompanion(
      id: id ?? this.id,
      recipeId: recipeId ?? this.recipeId,
      sectionId: sectionId ?? this.sectionId,
      foodId: foodId ?? this.foodId,
      rawText: rawText ?? this.rawText,
      name: name ?? this.name,
      quantityCanonical: quantityCanonical ?? this.quantityCanonical,
      quantityKind: quantityKind ?? this.quantityKind,
      quantityUnit: quantityUnit ?? this.quantityUnit,
      prepNote: prepNote ?? this.prepNote,
      isOptional: isOptional ?? this.isOptional,
      needsNoMatch: needsNoMatch ?? this.needsNoMatch,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (recipeId.present) {
      map['recipe_id'] = Variable<String>(recipeId.value);
    }
    if (sectionId.present) {
      map['section_id'] = Variable<String>(sectionId.value);
    }
    if (foodId.present) {
      map['food_id'] = Variable<String>(foodId.value);
    }
    if (rawText.present) {
      map['raw_text'] = Variable<String>(rawText.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (quantityCanonical.present) {
      map['quantity_canonical'] = Variable<double>(quantityCanonical.value);
    }
    if (quantityKind.present) {
      map['quantity_kind'] = Variable<String>(quantityKind.value);
    }
    if (quantityUnit.present) {
      map['quantity_unit'] = Variable<String>(quantityUnit.value);
    }
    if (prepNote.present) {
      map['prep_note'] = Variable<String>(prepNote.value);
    }
    if (isOptional.present) {
      map['is_optional'] = Variable<bool>(isOptional.value);
    }
    if (needsNoMatch.present) {
      map['needs_no_match'] = Variable<bool>(needsNoMatch.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecipeIngredientsCompanion(')
          ..write('id: $id, ')
          ..write('recipeId: $recipeId, ')
          ..write('sectionId: $sectionId, ')
          ..write('foodId: $foodId, ')
          ..write('rawText: $rawText, ')
          ..write('name: $name, ')
          ..write('quantityCanonical: $quantityCanonical, ')
          ..write('quantityKind: $quantityKind, ')
          ..write('quantityUnit: $quantityUnit, ')
          ..write('prepNote: $prepNote, ')
          ..write('isOptional: $isOptional, ')
          ..write('needsNoMatch: $needsNoMatch, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecipeStepsTable extends RecipeSteps
    with TableInfo<$RecipeStepsTable, RecipeStepRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecipeStepsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recipeIdMeta = const VerificationMeta(
    'recipeId',
  );
  @override
  late final GeneratedColumn<String> recipeId = GeneratedColumn<String>(
    'recipe_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES recipes (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sectionIdMeta = const VerificationMeta(
    'sectionId',
  );
  @override
  late final GeneratedColumn<String> sectionId = GeneratedColumn<String>(
    'section_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepNumberMeta = const VerificationMeta(
    'stepNumber',
  );
  @override
  late final GeneratedColumn<int> stepNumber = GeneratedColumn<int>(
    'step_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  static const VerificationMeta _timerSecondsMeta = const VerificationMeta(
    'timerSeconds',
  );
  @override
  late final GeneratedColumn<int> timerSeconds = GeneratedColumn<int>(
    'timer_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    recipeId,
    sectionId,
    stepNumber,
    body,
    timerSeconds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recipe_steps';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecipeStepRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('recipe_id')) {
      context.handle(
        _recipeIdMeta,
        recipeId.isAcceptableOrUnknown(data['recipe_id']!, _recipeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recipeIdMeta);
    }
    if (data.containsKey('section_id')) {
      context.handle(
        _sectionIdMeta,
        sectionId.isAcceptableOrUnknown(data['section_id']!, _sectionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sectionIdMeta);
    }
    if (data.containsKey('step_number')) {
      context.handle(
        _stepNumberMeta,
        stepNumber.isAcceptableOrUnknown(data['step_number']!, _stepNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_stepNumberMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('timer_seconds')) {
      context.handle(
        _timerSecondsMeta,
        timerSeconds.isAcceptableOrUnknown(
          data['timer_seconds']!,
          _timerSecondsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecipeStepRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecipeStepRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      recipeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_id'],
      )!,
      sectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_id'],
      )!,
      stepNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}step_number'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      timerSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timer_seconds'],
      ),
    );
  }

  @override
  $RecipeStepsTable createAlias(String alias) {
    return $RecipeStepsTable(attachedDatabase, alias);
  }
}

class RecipeStepRow extends DataClass implements Insertable<RecipeStepRow> {
  final String id;
  final String recipeId;
  final String sectionId;
  final int stepNumber;
  final String body;
  final int? timerSeconds;
  const RecipeStepRow({
    required this.id,
    required this.recipeId,
    required this.sectionId,
    required this.stepNumber,
    required this.body,
    this.timerSeconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['recipe_id'] = Variable<String>(recipeId);
    map['section_id'] = Variable<String>(sectionId);
    map['step_number'] = Variable<int>(stepNumber);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || timerSeconds != null) {
      map['timer_seconds'] = Variable<int>(timerSeconds);
    }
    return map;
  }

  RecipeStepsCompanion toCompanion(bool nullToAbsent) {
    return RecipeStepsCompanion(
      id: Value(id),
      recipeId: Value(recipeId),
      sectionId: Value(sectionId),
      stepNumber: Value(stepNumber),
      body: Value(body),
      timerSeconds: timerSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(timerSeconds),
    );
  }

  factory RecipeStepRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecipeStepRow(
      id: serializer.fromJson<String>(json['id']),
      recipeId: serializer.fromJson<String>(json['recipeId']),
      sectionId: serializer.fromJson<String>(json['sectionId']),
      stepNumber: serializer.fromJson<int>(json['stepNumber']),
      body: serializer.fromJson<String>(json['body']),
      timerSeconds: serializer.fromJson<int?>(json['timerSeconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'recipeId': serializer.toJson<String>(recipeId),
      'sectionId': serializer.toJson<String>(sectionId),
      'stepNumber': serializer.toJson<int>(stepNumber),
      'body': serializer.toJson<String>(body),
      'timerSeconds': serializer.toJson<int?>(timerSeconds),
    };
  }

  RecipeStepRow copyWith({
    String? id,
    String? recipeId,
    String? sectionId,
    int? stepNumber,
    String? body,
    Value<int?> timerSeconds = const Value.absent(),
  }) => RecipeStepRow(
    id: id ?? this.id,
    recipeId: recipeId ?? this.recipeId,
    sectionId: sectionId ?? this.sectionId,
    stepNumber: stepNumber ?? this.stepNumber,
    body: body ?? this.body,
    timerSeconds: timerSeconds.present ? timerSeconds.value : this.timerSeconds,
  );
  RecipeStepRow copyWithCompanion(RecipeStepsCompanion data) {
    return RecipeStepRow(
      id: data.id.present ? data.id.value : this.id,
      recipeId: data.recipeId.present ? data.recipeId.value : this.recipeId,
      sectionId: data.sectionId.present ? data.sectionId.value : this.sectionId,
      stepNumber: data.stepNumber.present
          ? data.stepNumber.value
          : this.stepNumber,
      body: data.body.present ? data.body.value : this.body,
      timerSeconds: data.timerSeconds.present
          ? data.timerSeconds.value
          : this.timerSeconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecipeStepRow(')
          ..write('id: $id, ')
          ..write('recipeId: $recipeId, ')
          ..write('sectionId: $sectionId, ')
          ..write('stepNumber: $stepNumber, ')
          ..write('body: $body, ')
          ..write('timerSeconds: $timerSeconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, recipeId, sectionId, stepNumber, body, timerSeconds);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecipeStepRow &&
          other.id == this.id &&
          other.recipeId == this.recipeId &&
          other.sectionId == this.sectionId &&
          other.stepNumber == this.stepNumber &&
          other.body == this.body &&
          other.timerSeconds == this.timerSeconds);
}

class RecipeStepsCompanion extends UpdateCompanion<RecipeStepRow> {
  final Value<String> id;
  final Value<String> recipeId;
  final Value<String> sectionId;
  final Value<int> stepNumber;
  final Value<String> body;
  final Value<int?> timerSeconds;
  final Value<int> rowid;
  const RecipeStepsCompanion({
    this.id = const Value.absent(),
    this.recipeId = const Value.absent(),
    this.sectionId = const Value.absent(),
    this.stepNumber = const Value.absent(),
    this.body = const Value.absent(),
    this.timerSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecipeStepsCompanion.insert({
    required String id,
    required String recipeId,
    required String sectionId,
    required int stepNumber,
    required String body,
    this.timerSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       recipeId = Value(recipeId),
       sectionId = Value(sectionId),
       stepNumber = Value(stepNumber),
       body = Value(body);
  static Insertable<RecipeStepRow> custom({
    Expression<String>? id,
    Expression<String>? recipeId,
    Expression<String>? sectionId,
    Expression<int>? stepNumber,
    Expression<String>? body,
    Expression<int>? timerSeconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recipeId != null) 'recipe_id': recipeId,
      if (sectionId != null) 'section_id': sectionId,
      if (stepNumber != null) 'step_number': stepNumber,
      if (body != null) 'body': body,
      if (timerSeconds != null) 'timer_seconds': timerSeconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecipeStepsCompanion copyWith({
    Value<String>? id,
    Value<String>? recipeId,
    Value<String>? sectionId,
    Value<int>? stepNumber,
    Value<String>? body,
    Value<int?>? timerSeconds,
    Value<int>? rowid,
  }) {
    return RecipeStepsCompanion(
      id: id ?? this.id,
      recipeId: recipeId ?? this.recipeId,
      sectionId: sectionId ?? this.sectionId,
      stepNumber: stepNumber ?? this.stepNumber,
      body: body ?? this.body,
      timerSeconds: timerSeconds ?? this.timerSeconds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (recipeId.present) {
      map['recipe_id'] = Variable<String>(recipeId.value);
    }
    if (sectionId.present) {
      map['section_id'] = Variable<String>(sectionId.value);
    }
    if (stepNumber.present) {
      map['step_number'] = Variable<int>(stepNumber.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (timerSeconds.present) {
      map['timer_seconds'] = Variable<int>(timerSeconds.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecipeStepsCompanion(')
          ..write('id: $id, ')
          ..write('recipeId: $recipeId, ')
          ..write('sectionId: $sectionId, ')
          ..write('stepNumber: $stepNumber, ')
          ..write('body: $body, ')
          ..write('timerSeconds: $timerSeconds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecipeFavoritesTable extends RecipeFavorites
    with TableInfo<$RecipeFavoritesTable, RecipeFavoriteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecipeFavoritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recipeIdMeta = const VerificationMeta(
    'recipeId',
  );
  @override
  late final GeneratedColumn<String> recipeId = GeneratedColumn<String>(
    'recipe_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES recipes (id) ON DELETE CASCADE',
    ),
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
  List<GeneratedColumn> get $columns => [userId, recipeId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recipe_favorites';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecipeFavoriteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('recipe_id')) {
      context.handle(
        _recipeIdMeta,
        recipeId.isAcceptableOrUnknown(data['recipe_id']!, _recipeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recipeIdMeta);
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
  Set<GeneratedColumn> get $primaryKey => {userId, recipeId};
  @override
  RecipeFavoriteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecipeFavoriteRow(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      recipeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $RecipeFavoritesTable createAlias(String alias) {
    return $RecipeFavoritesTable(attachedDatabase, alias);
  }
}

class RecipeFavoriteRow extends DataClass
    implements Insertable<RecipeFavoriteRow> {
  final String userId;
  final String recipeId;
  final DateTime createdAt;
  const RecipeFavoriteRow({
    required this.userId,
    required this.recipeId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['recipe_id'] = Variable<String>(recipeId);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RecipeFavoritesCompanion toCompanion(bool nullToAbsent) {
    return RecipeFavoritesCompanion(
      userId: Value(userId),
      recipeId: Value(recipeId),
      createdAt: Value(createdAt),
    );
  }

  factory RecipeFavoriteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecipeFavoriteRow(
      userId: serializer.fromJson<String>(json['userId']),
      recipeId: serializer.fromJson<String>(json['recipeId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'recipeId': serializer.toJson<String>(recipeId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  RecipeFavoriteRow copyWith({
    String? userId,
    String? recipeId,
    DateTime? createdAt,
  }) => RecipeFavoriteRow(
    userId: userId ?? this.userId,
    recipeId: recipeId ?? this.recipeId,
    createdAt: createdAt ?? this.createdAt,
  );
  RecipeFavoriteRow copyWithCompanion(RecipeFavoritesCompanion data) {
    return RecipeFavoriteRow(
      userId: data.userId.present ? data.userId.value : this.userId,
      recipeId: data.recipeId.present ? data.recipeId.value : this.recipeId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecipeFavoriteRow(')
          ..write('userId: $userId, ')
          ..write('recipeId: $recipeId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(userId, recipeId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecipeFavoriteRow &&
          other.userId == this.userId &&
          other.recipeId == this.recipeId &&
          other.createdAt == this.createdAt);
}

class RecipeFavoritesCompanion extends UpdateCompanion<RecipeFavoriteRow> {
  final Value<String> userId;
  final Value<String> recipeId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const RecipeFavoritesCompanion({
    this.userId = const Value.absent(),
    this.recipeId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecipeFavoritesCompanion.insert({
    required String userId,
    required String recipeId,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       recipeId = Value(recipeId),
       createdAt = Value(createdAt);
  static Insertable<RecipeFavoriteRow> custom({
    Expression<String>? userId,
    Expression<String>? recipeId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (recipeId != null) 'recipe_id': recipeId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecipeFavoritesCompanion copyWith({
    Value<String>? userId,
    Value<String>? recipeId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return RecipeFavoritesCompanion(
      userId: userId ?? this.userId,
      recipeId: recipeId ?? this.recipeId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (recipeId.present) {
      map['recipe_id'] = Variable<String>(recipeId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecipeFavoritesCompanion(')
          ..write('userId: $userId, ')
          ..write('recipeId: $recipeId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CollectionsTable extends Collections
    with TableInfo<$CollectionsTable, CollectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
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
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    name,
    sortOrder,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collections';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CollectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CollectionsTable createAlias(String alias) {
    return $CollectionsTable(attachedDatabase, alias);
  }
}

class CollectionRow extends DataClass implements Insertable<CollectionRow> {
  final String id;
  final String householdId;
  final String name;
  final int sortOrder;
  final DateTime updatedAt;
  const CollectionRow({
    required this.id,
    required this.householdId,
    required this.name,
    required this.sortOrder,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CollectionsCompanion toCompanion(bool nullToAbsent) {
    return CollectionsCompanion(
      id: Value(id),
      householdId: Value(householdId),
      name: Value(name),
      sortOrder: Value(sortOrder),
      updatedAt: Value(updatedAt),
    );
  }

  factory CollectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionRow(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CollectionRow copyWith({
    String? id,
    String? householdId,
    String? name,
    int? sortOrder,
    DateTime? updatedAt,
  }) => CollectionRow(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CollectionRow copyWithCompanion(CollectionsCompanion data) {
    return CollectionRow(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionRow(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, householdId, name, sortOrder, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionRow &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.updatedAt == this.updatedAt);
}

class CollectionsCompanion extends UpdateCompanion<CollectionRow> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CollectionsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionsCompanion.insert({
    required String id,
    required String householdId,
    required String name,
    this.sortOrder = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<CollectionRow> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionsCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CollectionsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecipeCollectionsTable extends RecipeCollections
    with TableInfo<$RecipeCollectionsTable, RecipeCollectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecipeCollectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<String> collectionId = GeneratedColumn<String>(
    'collection_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES collections (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _recipeIdMeta = const VerificationMeta(
    'recipeId',
  );
  @override
  late final GeneratedColumn<String> recipeId = GeneratedColumn<String>(
    'recipe_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES recipes (id) ON DELETE CASCADE',
    ),
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
  List<GeneratedColumn> get $columns => [collectionId, recipeId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recipe_collections';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecipeCollectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('recipe_id')) {
      context.handle(
        _recipeIdMeta,
        recipeId.isAcceptableOrUnknown(data['recipe_id']!, _recipeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recipeIdMeta);
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
  Set<GeneratedColumn> get $primaryKey => {collectionId, recipeId};
  @override
  RecipeCollectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecipeCollectionRow(
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_id'],
      )!,
      recipeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $RecipeCollectionsTable createAlias(String alias) {
    return $RecipeCollectionsTable(attachedDatabase, alias);
  }
}

class RecipeCollectionRow extends DataClass
    implements Insertable<RecipeCollectionRow> {
  final String collectionId;
  final String recipeId;
  final DateTime createdAt;
  const RecipeCollectionRow({
    required this.collectionId,
    required this.recipeId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['collection_id'] = Variable<String>(collectionId);
    map['recipe_id'] = Variable<String>(recipeId);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RecipeCollectionsCompanion toCompanion(bool nullToAbsent) {
    return RecipeCollectionsCompanion(
      collectionId: Value(collectionId),
      recipeId: Value(recipeId),
      createdAt: Value(createdAt),
    );
  }

  factory RecipeCollectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecipeCollectionRow(
      collectionId: serializer.fromJson<String>(json['collectionId']),
      recipeId: serializer.fromJson<String>(json['recipeId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'collectionId': serializer.toJson<String>(collectionId),
      'recipeId': serializer.toJson<String>(recipeId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  RecipeCollectionRow copyWith({
    String? collectionId,
    String? recipeId,
    DateTime? createdAt,
  }) => RecipeCollectionRow(
    collectionId: collectionId ?? this.collectionId,
    recipeId: recipeId ?? this.recipeId,
    createdAt: createdAt ?? this.createdAt,
  );
  RecipeCollectionRow copyWithCompanion(RecipeCollectionsCompanion data) {
    return RecipeCollectionRow(
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      recipeId: data.recipeId.present ? data.recipeId.value : this.recipeId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecipeCollectionRow(')
          ..write('collectionId: $collectionId, ')
          ..write('recipeId: $recipeId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(collectionId, recipeId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecipeCollectionRow &&
          other.collectionId == this.collectionId &&
          other.recipeId == this.recipeId &&
          other.createdAt == this.createdAt);
}

class RecipeCollectionsCompanion extends UpdateCompanion<RecipeCollectionRow> {
  final Value<String> collectionId;
  final Value<String> recipeId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const RecipeCollectionsCompanion({
    this.collectionId = const Value.absent(),
    this.recipeId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecipeCollectionsCompanion.insert({
    required String collectionId,
    required String recipeId,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : collectionId = Value(collectionId),
       recipeId = Value(recipeId),
       createdAt = Value(createdAt);
  static Insertable<RecipeCollectionRow> custom({
    Expression<String>? collectionId,
    Expression<String>? recipeId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (collectionId != null) 'collection_id': collectionId,
      if (recipeId != null) 'recipe_id': recipeId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecipeCollectionsCompanion copyWith({
    Value<String>? collectionId,
    Value<String>? recipeId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return RecipeCollectionsCompanion(
      collectionId: collectionId ?? this.collectionId,
      recipeId: recipeId ?? this.recipeId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (collectionId.present) {
      map['collection_id'] = Variable<String>(collectionId.value);
    }
    if (recipeId.present) {
      map['recipe_id'] = Variable<String>(recipeId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecipeCollectionsCompanion(')
          ..write('collectionId: $collectionId, ')
          ..write('recipeId: $recipeId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FoodsTable extends Foods with TableInfo<$FoodsTable, FoodRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _brandMeta = const VerificationMeta('brand');
  @override
  late final GeneratedColumn<String> brand = GeneratedColumn<String>(
    'brand',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storeTagMeta = const VerificationMeta(
    'storeTag',
  );
  @override
  late final GeneratedColumn<String> storeTag = GeneratedColumn<String>(
    'store_tag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _walmartItemIdMeta = const VerificationMeta(
    'walmartItemId',
  );
  @override
  late final GeneratedColumn<String> walmartItemId = GeneratedColumn<String>(
    'walmart_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _packCanonicalMeta = const VerificationMeta(
    'packCanonical',
  );
  @override
  late final GeneratedColumn<double> packCanonical = GeneratedColumn<double>(
    'pack_canonical',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _packKindMeta = const VerificationMeta(
    'packKind',
  );
  @override
  late final GeneratedColumn<String> packKind = GeneratedColumn<String>(
    'pack_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _packUnitMeta = const VerificationMeta(
    'packUnit',
  );
  @override
  late final GeneratedColumn<String> packUnit = GeneratedColumn<String>(
    'pack_unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _barcodeMeta = const VerificationMeta(
    'barcode',
  );
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
    'barcode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gramsPerMillilitreMeta =
      const VerificationMeta('gramsPerMillilitre');
  @override
  late final GeneratedColumn<double> gramsPerMillilitre =
      GeneratedColumn<double>(
        'grams_per_millilitre',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _macrosOverriddenMeta = const VerificationMeta(
    'macrosOverridden',
  );
  @override
  late final GeneratedColumn<bool> macrosOverridden = GeneratedColumn<bool>(
    'macros_overridden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("macros_overridden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isZeroCalorieMeta = const VerificationMeta(
    'isZeroCalorie',
  );
  @override
  late final GeneratedColumn<bool> isZeroCalorie = GeneratedColumn<bool>(
    'is_zero_calorie',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_zero_calorie" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    name,
    brand,
    storeTag,
    walmartItemId,
    packCanonical,
    packKind,
    packUnit,
    barcode,
    gramsPerMillilitre,
    source,
    macrosOverridden,
    isDefault,
    isZeroCalorie,
    isDeleted,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'foods';
  @override
  VerificationContext validateIntegrity(
    Insertable<FoodRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
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
    if (data.containsKey('brand')) {
      context.handle(
        _brandMeta,
        brand.isAcceptableOrUnknown(data['brand']!, _brandMeta),
      );
    }
    if (data.containsKey('store_tag')) {
      context.handle(
        _storeTagMeta,
        storeTag.isAcceptableOrUnknown(data['store_tag']!, _storeTagMeta),
      );
    }
    if (data.containsKey('walmart_item_id')) {
      context.handle(
        _walmartItemIdMeta,
        walmartItemId.isAcceptableOrUnknown(
          data['walmart_item_id']!,
          _walmartItemIdMeta,
        ),
      );
    }
    if (data.containsKey('pack_canonical')) {
      context.handle(
        _packCanonicalMeta,
        packCanonical.isAcceptableOrUnknown(
          data['pack_canonical']!,
          _packCanonicalMeta,
        ),
      );
    }
    if (data.containsKey('pack_kind')) {
      context.handle(
        _packKindMeta,
        packKind.isAcceptableOrUnknown(data['pack_kind']!, _packKindMeta),
      );
    }
    if (data.containsKey('pack_unit')) {
      context.handle(
        _packUnitMeta,
        packUnit.isAcceptableOrUnknown(data['pack_unit']!, _packUnitMeta),
      );
    }
    if (data.containsKey('barcode')) {
      context.handle(
        _barcodeMeta,
        barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta),
      );
    }
    if (data.containsKey('grams_per_millilitre')) {
      context.handle(
        _gramsPerMillilitreMeta,
        gramsPerMillilitre.isAcceptableOrUnknown(
          data['grams_per_millilitre']!,
          _gramsPerMillilitreMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('macros_overridden')) {
      context.handle(
        _macrosOverriddenMeta,
        macrosOverridden.isAcceptableOrUnknown(
          data['macros_overridden']!,
          _macrosOverriddenMeta,
        ),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('is_zero_calorie')) {
      context.handle(
        _isZeroCalorieMeta,
        isZeroCalorie.isAcceptableOrUnknown(
          data['is_zero_calorie']!,
          _isZeroCalorieMeta,
        ),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FoodRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FoodRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      brand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand'],
      ),
      storeTag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_tag'],
      ),
      walmartItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}walmart_item_id'],
      ),
      packCanonical: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pack_canonical'],
      ),
      packKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_kind'],
      ),
      packUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_unit'],
      ),
      barcode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}barcode'],
      ),
      gramsPerMillilitre: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}grams_per_millilitre'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      macrosOverridden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}macros_overridden'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      isZeroCalorie: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_zero_calorie'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FoodsTable createAlias(String alias) {
    return $FoodsTable(attachedDatabase, alias);
  }
}

class FoodRow extends DataClass implements Insertable<FoodRow> {
  final String id;

  /// Null means a global food from the shared catalogue.
  final String? householdId;
  final String name;
  final String? brand;
  final String? storeTag;

  /// The Walmart item id for the product bought, and how much is in one of
  /// them — what lets the shopping export fill a basket (spec §5.7).
  final String? walmartItemId;
  final double? packCanonical;
  final String? packKind;
  final String? packUnit;
  final String? barcode;
  final double? gramsPerMillilitre;
  final String source;
  final bool macrosOverridden;

  /// A standing choice, matched to recipe lines naming the same thing (§5.3).
  final bool isDefault;

  /// Confirmed to carry no macros — black coffee, sparkling water (§5.5).
  final bool isZeroCalorie;
  final bool isDeleted;
  final DateTime updatedAt;
  const FoodRow({
    required this.id,
    this.householdId,
    required this.name,
    this.brand,
    this.storeTag,
    this.walmartItemId,
    this.packCanonical,
    this.packKind,
    this.packUnit,
    this.barcode,
    this.gramsPerMillilitre,
    required this.source,
    required this.macrosOverridden,
    required this.isDefault,
    required this.isZeroCalorie,
    required this.isDeleted,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || householdId != null) {
      map['household_id'] = Variable<String>(householdId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || brand != null) {
      map['brand'] = Variable<String>(brand);
    }
    if (!nullToAbsent || storeTag != null) {
      map['store_tag'] = Variable<String>(storeTag);
    }
    if (!nullToAbsent || walmartItemId != null) {
      map['walmart_item_id'] = Variable<String>(walmartItemId);
    }
    if (!nullToAbsent || packCanonical != null) {
      map['pack_canonical'] = Variable<double>(packCanonical);
    }
    if (!nullToAbsent || packKind != null) {
      map['pack_kind'] = Variable<String>(packKind);
    }
    if (!nullToAbsent || packUnit != null) {
      map['pack_unit'] = Variable<String>(packUnit);
    }
    if (!nullToAbsent || barcode != null) {
      map['barcode'] = Variable<String>(barcode);
    }
    if (!nullToAbsent || gramsPerMillilitre != null) {
      map['grams_per_millilitre'] = Variable<double>(gramsPerMillilitre);
    }
    map['source'] = Variable<String>(source);
    map['macros_overridden'] = Variable<bool>(macrosOverridden);
    map['is_default'] = Variable<bool>(isDefault);
    map['is_zero_calorie'] = Variable<bool>(isZeroCalorie);
    map['is_deleted'] = Variable<bool>(isDeleted);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  FoodsCompanion toCompanion(bool nullToAbsent) {
    return FoodsCompanion(
      id: Value(id),
      householdId: householdId == null && nullToAbsent
          ? const Value.absent()
          : Value(householdId),
      name: Value(name),
      brand: brand == null && nullToAbsent
          ? const Value.absent()
          : Value(brand),
      storeTag: storeTag == null && nullToAbsent
          ? const Value.absent()
          : Value(storeTag),
      walmartItemId: walmartItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(walmartItemId),
      packCanonical: packCanonical == null && nullToAbsent
          ? const Value.absent()
          : Value(packCanonical),
      packKind: packKind == null && nullToAbsent
          ? const Value.absent()
          : Value(packKind),
      packUnit: packUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(packUnit),
      barcode: barcode == null && nullToAbsent
          ? const Value.absent()
          : Value(barcode),
      gramsPerMillilitre: gramsPerMillilitre == null && nullToAbsent
          ? const Value.absent()
          : Value(gramsPerMillilitre),
      source: Value(source),
      macrosOverridden: Value(macrosOverridden),
      isDefault: Value(isDefault),
      isZeroCalorie: Value(isZeroCalorie),
      isDeleted: Value(isDeleted),
      updatedAt: Value(updatedAt),
    );
  }

  factory FoodRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FoodRow(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String?>(json['householdId']),
      name: serializer.fromJson<String>(json['name']),
      brand: serializer.fromJson<String?>(json['brand']),
      storeTag: serializer.fromJson<String?>(json['storeTag']),
      walmartItemId: serializer.fromJson<String?>(json['walmartItemId']),
      packCanonical: serializer.fromJson<double?>(json['packCanonical']),
      packKind: serializer.fromJson<String?>(json['packKind']),
      packUnit: serializer.fromJson<String?>(json['packUnit']),
      barcode: serializer.fromJson<String?>(json['barcode']),
      gramsPerMillilitre: serializer.fromJson<double?>(
        json['gramsPerMillilitre'],
      ),
      source: serializer.fromJson<String>(json['source']),
      macrosOverridden: serializer.fromJson<bool>(json['macrosOverridden']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      isZeroCalorie: serializer.fromJson<bool>(json['isZeroCalorie']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String?>(householdId),
      'name': serializer.toJson<String>(name),
      'brand': serializer.toJson<String?>(brand),
      'storeTag': serializer.toJson<String?>(storeTag),
      'walmartItemId': serializer.toJson<String?>(walmartItemId),
      'packCanonical': serializer.toJson<double?>(packCanonical),
      'packKind': serializer.toJson<String?>(packKind),
      'packUnit': serializer.toJson<String?>(packUnit),
      'barcode': serializer.toJson<String?>(barcode),
      'gramsPerMillilitre': serializer.toJson<double?>(gramsPerMillilitre),
      'source': serializer.toJson<String>(source),
      'macrosOverridden': serializer.toJson<bool>(macrosOverridden),
      'isDefault': serializer.toJson<bool>(isDefault),
      'isZeroCalorie': serializer.toJson<bool>(isZeroCalorie),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  FoodRow copyWith({
    String? id,
    Value<String?> householdId = const Value.absent(),
    String? name,
    Value<String?> brand = const Value.absent(),
    Value<String?> storeTag = const Value.absent(),
    Value<String?> walmartItemId = const Value.absent(),
    Value<double?> packCanonical = const Value.absent(),
    Value<String?> packKind = const Value.absent(),
    Value<String?> packUnit = const Value.absent(),
    Value<String?> barcode = const Value.absent(),
    Value<double?> gramsPerMillilitre = const Value.absent(),
    String? source,
    bool? macrosOverridden,
    bool? isDefault,
    bool? isZeroCalorie,
    bool? isDeleted,
    DateTime? updatedAt,
  }) => FoodRow(
    id: id ?? this.id,
    householdId: householdId.present ? householdId.value : this.householdId,
    name: name ?? this.name,
    brand: brand.present ? brand.value : this.brand,
    storeTag: storeTag.present ? storeTag.value : this.storeTag,
    walmartItemId: walmartItemId.present
        ? walmartItemId.value
        : this.walmartItemId,
    packCanonical: packCanonical.present
        ? packCanonical.value
        : this.packCanonical,
    packKind: packKind.present ? packKind.value : this.packKind,
    packUnit: packUnit.present ? packUnit.value : this.packUnit,
    barcode: barcode.present ? barcode.value : this.barcode,
    gramsPerMillilitre: gramsPerMillilitre.present
        ? gramsPerMillilitre.value
        : this.gramsPerMillilitre,
    source: source ?? this.source,
    macrosOverridden: macrosOverridden ?? this.macrosOverridden,
    isDefault: isDefault ?? this.isDefault,
    isZeroCalorie: isZeroCalorie ?? this.isZeroCalorie,
    isDeleted: isDeleted ?? this.isDeleted,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  FoodRow copyWithCompanion(FoodsCompanion data) {
    return FoodRow(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      name: data.name.present ? data.name.value : this.name,
      brand: data.brand.present ? data.brand.value : this.brand,
      storeTag: data.storeTag.present ? data.storeTag.value : this.storeTag,
      walmartItemId: data.walmartItemId.present
          ? data.walmartItemId.value
          : this.walmartItemId,
      packCanonical: data.packCanonical.present
          ? data.packCanonical.value
          : this.packCanonical,
      packKind: data.packKind.present ? data.packKind.value : this.packKind,
      packUnit: data.packUnit.present ? data.packUnit.value : this.packUnit,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      gramsPerMillilitre: data.gramsPerMillilitre.present
          ? data.gramsPerMillilitre.value
          : this.gramsPerMillilitre,
      source: data.source.present ? data.source.value : this.source,
      macrosOverridden: data.macrosOverridden.present
          ? data.macrosOverridden.value
          : this.macrosOverridden,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      isZeroCalorie: data.isZeroCalorie.present
          ? data.isZeroCalorie.value
          : this.isZeroCalorie,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FoodRow(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('storeTag: $storeTag, ')
          ..write('walmartItemId: $walmartItemId, ')
          ..write('packCanonical: $packCanonical, ')
          ..write('packKind: $packKind, ')
          ..write('packUnit: $packUnit, ')
          ..write('barcode: $barcode, ')
          ..write('gramsPerMillilitre: $gramsPerMillilitre, ')
          ..write('source: $source, ')
          ..write('macrosOverridden: $macrosOverridden, ')
          ..write('isDefault: $isDefault, ')
          ..write('isZeroCalorie: $isZeroCalorie, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    name,
    brand,
    storeTag,
    walmartItemId,
    packCanonical,
    packKind,
    packUnit,
    barcode,
    gramsPerMillilitre,
    source,
    macrosOverridden,
    isDefault,
    isZeroCalorie,
    isDeleted,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoodRow &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.name == this.name &&
          other.brand == this.brand &&
          other.storeTag == this.storeTag &&
          other.walmartItemId == this.walmartItemId &&
          other.packCanonical == this.packCanonical &&
          other.packKind == this.packKind &&
          other.packUnit == this.packUnit &&
          other.barcode == this.barcode &&
          other.gramsPerMillilitre == this.gramsPerMillilitre &&
          other.source == this.source &&
          other.macrosOverridden == this.macrosOverridden &&
          other.isDefault == this.isDefault &&
          other.isZeroCalorie == this.isZeroCalorie &&
          other.isDeleted == this.isDeleted &&
          other.updatedAt == this.updatedAt);
}

class FoodsCompanion extends UpdateCompanion<FoodRow> {
  final Value<String> id;
  final Value<String?> householdId;
  final Value<String> name;
  final Value<String?> brand;
  final Value<String?> storeTag;
  final Value<String?> walmartItemId;
  final Value<double?> packCanonical;
  final Value<String?> packKind;
  final Value<String?> packUnit;
  final Value<String?> barcode;
  final Value<double?> gramsPerMillilitre;
  final Value<String> source;
  final Value<bool> macrosOverridden;
  final Value<bool> isDefault;
  final Value<bool> isZeroCalorie;
  final Value<bool> isDeleted;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const FoodsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.name = const Value.absent(),
    this.brand = const Value.absent(),
    this.storeTag = const Value.absent(),
    this.walmartItemId = const Value.absent(),
    this.packCanonical = const Value.absent(),
    this.packKind = const Value.absent(),
    this.packUnit = const Value.absent(),
    this.barcode = const Value.absent(),
    this.gramsPerMillilitre = const Value.absent(),
    this.source = const Value.absent(),
    this.macrosOverridden = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.isZeroCalorie = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoodsCompanion.insert({
    required String id,
    this.householdId = const Value.absent(),
    required String name,
    this.brand = const Value.absent(),
    this.storeTag = const Value.absent(),
    this.walmartItemId = const Value.absent(),
    this.packCanonical = const Value.absent(),
    this.packKind = const Value.absent(),
    this.packUnit = const Value.absent(),
    this.barcode = const Value.absent(),
    this.gramsPerMillilitre = const Value.absent(),
    this.source = const Value.absent(),
    this.macrosOverridden = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.isZeroCalorie = const Value.absent(),
    this.isDeleted = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<FoodRow> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? name,
    Expression<String>? brand,
    Expression<String>? storeTag,
    Expression<String>? walmartItemId,
    Expression<double>? packCanonical,
    Expression<String>? packKind,
    Expression<String>? packUnit,
    Expression<String>? barcode,
    Expression<double>? gramsPerMillilitre,
    Expression<String>? source,
    Expression<bool>? macrosOverridden,
    Expression<bool>? isDefault,
    Expression<bool>? isZeroCalorie,
    Expression<bool>? isDeleted,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (name != null) 'name': name,
      if (brand != null) 'brand': brand,
      if (storeTag != null) 'store_tag': storeTag,
      if (walmartItemId != null) 'walmart_item_id': walmartItemId,
      if (packCanonical != null) 'pack_canonical': packCanonical,
      if (packKind != null) 'pack_kind': packKind,
      if (packUnit != null) 'pack_unit': packUnit,
      if (barcode != null) 'barcode': barcode,
      if (gramsPerMillilitre != null)
        'grams_per_millilitre': gramsPerMillilitre,
      if (source != null) 'source': source,
      if (macrosOverridden != null) 'macros_overridden': macrosOverridden,
      if (isDefault != null) 'is_default': isDefault,
      if (isZeroCalorie != null) 'is_zero_calorie': isZeroCalorie,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoodsCompanion copyWith({
    Value<String>? id,
    Value<String?>? householdId,
    Value<String>? name,
    Value<String?>? brand,
    Value<String?>? storeTag,
    Value<String?>? walmartItemId,
    Value<double?>? packCanonical,
    Value<String?>? packKind,
    Value<String?>? packUnit,
    Value<String?>? barcode,
    Value<double?>? gramsPerMillilitre,
    Value<String>? source,
    Value<bool>? macrosOverridden,
    Value<bool>? isDefault,
    Value<bool>? isZeroCalorie,
    Value<bool>? isDeleted,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return FoodsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      storeTag: storeTag ?? this.storeTag,
      walmartItemId: walmartItemId ?? this.walmartItemId,
      packCanonical: packCanonical ?? this.packCanonical,
      packKind: packKind ?? this.packKind,
      packUnit: packUnit ?? this.packUnit,
      barcode: barcode ?? this.barcode,
      gramsPerMillilitre: gramsPerMillilitre ?? this.gramsPerMillilitre,
      source: source ?? this.source,
      macrosOverridden: macrosOverridden ?? this.macrosOverridden,
      isDefault: isDefault ?? this.isDefault,
      isZeroCalorie: isZeroCalorie ?? this.isZeroCalorie,
      isDeleted: isDeleted ?? this.isDeleted,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (storeTag.present) {
      map['store_tag'] = Variable<String>(storeTag.value);
    }
    if (walmartItemId.present) {
      map['walmart_item_id'] = Variable<String>(walmartItemId.value);
    }
    if (packCanonical.present) {
      map['pack_canonical'] = Variable<double>(packCanonical.value);
    }
    if (packKind.present) {
      map['pack_kind'] = Variable<String>(packKind.value);
    }
    if (packUnit.present) {
      map['pack_unit'] = Variable<String>(packUnit.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (gramsPerMillilitre.present) {
      map['grams_per_millilitre'] = Variable<double>(gramsPerMillilitre.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (macrosOverridden.present) {
      map['macros_overridden'] = Variable<bool>(macrosOverridden.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (isZeroCalorie.present) {
      map['is_zero_calorie'] = Variable<bool>(isZeroCalorie.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoodsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('storeTag: $storeTag, ')
          ..write('walmartItemId: $walmartItemId, ')
          ..write('packCanonical: $packCanonical, ')
          ..write('packKind: $packKind, ')
          ..write('packUnit: $packUnit, ')
          ..write('barcode: $barcode, ')
          ..write('gramsPerMillilitre: $gramsPerMillilitre, ')
          ..write('source: $source, ')
          ..write('macrosOverridden: $macrosOverridden, ')
          ..write('isDefault: $isDefault, ')
          ..write('isZeroCalorie: $isZeroCalorie, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FoodServingOptionsTable extends FoodServingOptions
    with TableInfo<$FoodServingOptionsTable, FoodServingOptionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoodServingOptionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _foodIdMeta = const VerificationMeta('foodId');
  @override
  late final GeneratedColumn<String> foodId = GeneratedColumn<String>(
    'food_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES foods (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountCanonicalMeta = const VerificationMeta(
    'amountCanonical',
  );
  @override
  late final GeneratedColumn<double> amountCanonical = GeneratedColumn<double>(
    'amount_canonical',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountKindMeta = const VerificationMeta(
    'amountKind',
  );
  @override
  late final GeneratedColumn<String> amountKind = GeneratedColumn<String>(
    'amount_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountUnitMeta = const VerificationMeta(
    'amountUnit',
  );
  @override
  late final GeneratedColumn<String> amountUnit = GeneratedColumn<String>(
    'amount_unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kcalMeta = const VerificationMeta('kcal');
  @override
  late final GeneratedColumn<double> kcal = GeneratedColumn<double>(
    'kcal',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _proteinGMeta = const VerificationMeta(
    'proteinG',
  );
  @override
  late final GeneratedColumn<double> proteinG = GeneratedColumn<double>(
    'protein_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _carbGMeta = const VerificationMeta('carbG');
  @override
  late final GeneratedColumn<double> carbG = GeneratedColumn<double>(
    'carb_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fatGMeta = const VerificationMeta('fatG');
  @override
  late final GeneratedColumn<double> fatG = GeneratedColumn<double>(
    'fat_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fiberGMeta = const VerificationMeta('fiberG');
  @override
  late final GeneratedColumn<double> fiberG = GeneratedColumn<double>(
    'fiber_g',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sodiumMgMeta = const VerificationMeta(
    'sodiumMg',
  );
  @override
  late final GeneratedColumn<double> sodiumMg = GeneratedColumn<double>(
    'sodium_mg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cholesterolMgMeta = const VerificationMeta(
    'cholesterolMg',
  );
  @override
  late final GeneratedColumn<double> cholesterolMg = GeneratedColumn<double>(
    'cholesterol_mg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    foodId,
    label,
    amountCanonical,
    amountKind,
    amountUnit,
    kcal,
    proteinG,
    carbG,
    fatG,
    fiberG,
    sodiumMg,
    cholesterolMg,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'food_serving_options';
  @override
  VerificationContext validateIntegrity(
    Insertable<FoodServingOptionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('food_id')) {
      context.handle(
        _foodIdMeta,
        foodId.isAcceptableOrUnknown(data['food_id']!, _foodIdMeta),
      );
    } else if (isInserting) {
      context.missing(_foodIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('amount_canonical')) {
      context.handle(
        _amountCanonicalMeta,
        amountCanonical.isAcceptableOrUnknown(
          data['amount_canonical']!,
          _amountCanonicalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCanonicalMeta);
    }
    if (data.containsKey('amount_kind')) {
      context.handle(
        _amountKindMeta,
        amountKind.isAcceptableOrUnknown(data['amount_kind']!, _amountKindMeta),
      );
    } else if (isInserting) {
      context.missing(_amountKindMeta);
    }
    if (data.containsKey('amount_unit')) {
      context.handle(
        _amountUnitMeta,
        amountUnit.isAcceptableOrUnknown(data['amount_unit']!, _amountUnitMeta),
      );
    }
    if (data.containsKey('kcal')) {
      context.handle(
        _kcalMeta,
        kcal.isAcceptableOrUnknown(data['kcal']!, _kcalMeta),
      );
    }
    if (data.containsKey('protein_g')) {
      context.handle(
        _proteinGMeta,
        proteinG.isAcceptableOrUnknown(data['protein_g']!, _proteinGMeta),
      );
    }
    if (data.containsKey('carb_g')) {
      context.handle(
        _carbGMeta,
        carbG.isAcceptableOrUnknown(data['carb_g']!, _carbGMeta),
      );
    }
    if (data.containsKey('fat_g')) {
      context.handle(
        _fatGMeta,
        fatG.isAcceptableOrUnknown(data['fat_g']!, _fatGMeta),
      );
    }
    if (data.containsKey('fiber_g')) {
      context.handle(
        _fiberGMeta,
        fiberG.isAcceptableOrUnknown(data['fiber_g']!, _fiberGMeta),
      );
    }
    if (data.containsKey('sodium_mg')) {
      context.handle(
        _sodiumMgMeta,
        sodiumMg.isAcceptableOrUnknown(data['sodium_mg']!, _sodiumMgMeta),
      );
    }
    if (data.containsKey('cholesterol_mg')) {
      context.handle(
        _cholesterolMgMeta,
        cholesterolMg.isAcceptableOrUnknown(
          data['cholesterol_mg']!,
          _cholesterolMgMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FoodServingOptionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FoodServingOptionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      foodId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}food_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      amountCanonical: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount_canonical'],
      )!,
      amountKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}amount_kind'],
      )!,
      amountUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}amount_unit'],
      ),
      kcal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}kcal'],
      )!,
      proteinG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_g'],
      )!,
      carbG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carb_g'],
      )!,
      fatG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_g'],
      )!,
      fiberG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fiber_g'],
      ),
      sodiumMg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sodium_mg'],
      ),
      cholesterolMg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cholesterol_mg'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $FoodServingOptionsTable createAlias(String alias) {
    return $FoodServingOptionsTable(attachedDatabase, alias);
  }
}

class FoodServingOptionRow extends DataClass
    implements Insertable<FoodServingOptionRow> {
  final String id;
  final String foodId;
  final String label;
  final double amountCanonical;
  final String amountKind;
  final String? amountUnit;
  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;

  /// The three minor nutrients (spec §5.6). Nullable and **no default**: null
  /// is unknown, and a `withDefault(0)` here would quietly turn every food
  /// that has never heard of fibre into one that claims to have none.
  final double? fiberG;
  final double? sodiumMg;
  final double? cholesterolMg;
  final int sortOrder;
  const FoodServingOptionRow({
    required this.id,
    required this.foodId,
    required this.label,
    required this.amountCanonical,
    required this.amountKind,
    this.amountUnit,
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    this.fiberG,
    this.sodiumMg,
    this.cholesterolMg,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['food_id'] = Variable<String>(foodId);
    map['label'] = Variable<String>(label);
    map['amount_canonical'] = Variable<double>(amountCanonical);
    map['amount_kind'] = Variable<String>(amountKind);
    if (!nullToAbsent || amountUnit != null) {
      map['amount_unit'] = Variable<String>(amountUnit);
    }
    map['kcal'] = Variable<double>(kcal);
    map['protein_g'] = Variable<double>(proteinG);
    map['carb_g'] = Variable<double>(carbG);
    map['fat_g'] = Variable<double>(fatG);
    if (!nullToAbsent || fiberG != null) {
      map['fiber_g'] = Variable<double>(fiberG);
    }
    if (!nullToAbsent || sodiumMg != null) {
      map['sodium_mg'] = Variable<double>(sodiumMg);
    }
    if (!nullToAbsent || cholesterolMg != null) {
      map['cholesterol_mg'] = Variable<double>(cholesterolMg);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  FoodServingOptionsCompanion toCompanion(bool nullToAbsent) {
    return FoodServingOptionsCompanion(
      id: Value(id),
      foodId: Value(foodId),
      label: Value(label),
      amountCanonical: Value(amountCanonical),
      amountKind: Value(amountKind),
      amountUnit: amountUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(amountUnit),
      kcal: Value(kcal),
      proteinG: Value(proteinG),
      carbG: Value(carbG),
      fatG: Value(fatG),
      fiberG: fiberG == null && nullToAbsent
          ? const Value.absent()
          : Value(fiberG),
      sodiumMg: sodiumMg == null && nullToAbsent
          ? const Value.absent()
          : Value(sodiumMg),
      cholesterolMg: cholesterolMg == null && nullToAbsent
          ? const Value.absent()
          : Value(cholesterolMg),
      sortOrder: Value(sortOrder),
    );
  }

  factory FoodServingOptionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FoodServingOptionRow(
      id: serializer.fromJson<String>(json['id']),
      foodId: serializer.fromJson<String>(json['foodId']),
      label: serializer.fromJson<String>(json['label']),
      amountCanonical: serializer.fromJson<double>(json['amountCanonical']),
      amountKind: serializer.fromJson<String>(json['amountKind']),
      amountUnit: serializer.fromJson<String?>(json['amountUnit']),
      kcal: serializer.fromJson<double>(json['kcal']),
      proteinG: serializer.fromJson<double>(json['proteinG']),
      carbG: serializer.fromJson<double>(json['carbG']),
      fatG: serializer.fromJson<double>(json['fatG']),
      fiberG: serializer.fromJson<double?>(json['fiberG']),
      sodiumMg: serializer.fromJson<double?>(json['sodiumMg']),
      cholesterolMg: serializer.fromJson<double?>(json['cholesterolMg']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'foodId': serializer.toJson<String>(foodId),
      'label': serializer.toJson<String>(label),
      'amountCanonical': serializer.toJson<double>(amountCanonical),
      'amountKind': serializer.toJson<String>(amountKind),
      'amountUnit': serializer.toJson<String?>(amountUnit),
      'kcal': serializer.toJson<double>(kcal),
      'proteinG': serializer.toJson<double>(proteinG),
      'carbG': serializer.toJson<double>(carbG),
      'fatG': serializer.toJson<double>(fatG),
      'fiberG': serializer.toJson<double?>(fiberG),
      'sodiumMg': serializer.toJson<double?>(sodiumMg),
      'cholesterolMg': serializer.toJson<double?>(cholesterolMg),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  FoodServingOptionRow copyWith({
    String? id,
    String? foodId,
    String? label,
    double? amountCanonical,
    String? amountKind,
    Value<String?> amountUnit = const Value.absent(),
    double? kcal,
    double? proteinG,
    double? carbG,
    double? fatG,
    Value<double?> fiberG = const Value.absent(),
    Value<double?> sodiumMg = const Value.absent(),
    Value<double?> cholesterolMg = const Value.absent(),
    int? sortOrder,
  }) => FoodServingOptionRow(
    id: id ?? this.id,
    foodId: foodId ?? this.foodId,
    label: label ?? this.label,
    amountCanonical: amountCanonical ?? this.amountCanonical,
    amountKind: amountKind ?? this.amountKind,
    amountUnit: amountUnit.present ? amountUnit.value : this.amountUnit,
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbG: carbG ?? this.carbG,
    fatG: fatG ?? this.fatG,
    fiberG: fiberG.present ? fiberG.value : this.fiberG,
    sodiumMg: sodiumMg.present ? sodiumMg.value : this.sodiumMg,
    cholesterolMg: cholesterolMg.present
        ? cholesterolMg.value
        : this.cholesterolMg,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  FoodServingOptionRow copyWithCompanion(FoodServingOptionsCompanion data) {
    return FoodServingOptionRow(
      id: data.id.present ? data.id.value : this.id,
      foodId: data.foodId.present ? data.foodId.value : this.foodId,
      label: data.label.present ? data.label.value : this.label,
      amountCanonical: data.amountCanonical.present
          ? data.amountCanonical.value
          : this.amountCanonical,
      amountKind: data.amountKind.present
          ? data.amountKind.value
          : this.amountKind,
      amountUnit: data.amountUnit.present
          ? data.amountUnit.value
          : this.amountUnit,
      kcal: data.kcal.present ? data.kcal.value : this.kcal,
      proteinG: data.proteinG.present ? data.proteinG.value : this.proteinG,
      carbG: data.carbG.present ? data.carbG.value : this.carbG,
      fatG: data.fatG.present ? data.fatG.value : this.fatG,
      fiberG: data.fiberG.present ? data.fiberG.value : this.fiberG,
      sodiumMg: data.sodiumMg.present ? data.sodiumMg.value : this.sodiumMg,
      cholesterolMg: data.cholesterolMg.present
          ? data.cholesterolMg.value
          : this.cholesterolMg,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FoodServingOptionRow(')
          ..write('id: $id, ')
          ..write('foodId: $foodId, ')
          ..write('label: $label, ')
          ..write('amountCanonical: $amountCanonical, ')
          ..write('amountKind: $amountKind, ')
          ..write('amountUnit: $amountUnit, ')
          ..write('kcal: $kcal, ')
          ..write('proteinG: $proteinG, ')
          ..write('carbG: $carbG, ')
          ..write('fatG: $fatG, ')
          ..write('fiberG: $fiberG, ')
          ..write('sodiumMg: $sodiumMg, ')
          ..write('cholesterolMg: $cholesterolMg, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    foodId,
    label,
    amountCanonical,
    amountKind,
    amountUnit,
    kcal,
    proteinG,
    carbG,
    fatG,
    fiberG,
    sodiumMg,
    cholesterolMg,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoodServingOptionRow &&
          other.id == this.id &&
          other.foodId == this.foodId &&
          other.label == this.label &&
          other.amountCanonical == this.amountCanonical &&
          other.amountKind == this.amountKind &&
          other.amountUnit == this.amountUnit &&
          other.kcal == this.kcal &&
          other.proteinG == this.proteinG &&
          other.carbG == this.carbG &&
          other.fatG == this.fatG &&
          other.fiberG == this.fiberG &&
          other.sodiumMg == this.sodiumMg &&
          other.cholesterolMg == this.cholesterolMg &&
          other.sortOrder == this.sortOrder);
}

class FoodServingOptionsCompanion
    extends UpdateCompanion<FoodServingOptionRow> {
  final Value<String> id;
  final Value<String> foodId;
  final Value<String> label;
  final Value<double> amountCanonical;
  final Value<String> amountKind;
  final Value<String?> amountUnit;
  final Value<double> kcal;
  final Value<double> proteinG;
  final Value<double> carbG;
  final Value<double> fatG;
  final Value<double?> fiberG;
  final Value<double?> sodiumMg;
  final Value<double?> cholesterolMg;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const FoodServingOptionsCompanion({
    this.id = const Value.absent(),
    this.foodId = const Value.absent(),
    this.label = const Value.absent(),
    this.amountCanonical = const Value.absent(),
    this.amountKind = const Value.absent(),
    this.amountUnit = const Value.absent(),
    this.kcal = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.carbG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.fiberG = const Value.absent(),
    this.sodiumMg = const Value.absent(),
    this.cholesterolMg = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoodServingOptionsCompanion.insert({
    required String id,
    required String foodId,
    required String label,
    required double amountCanonical,
    required String amountKind,
    this.amountUnit = const Value.absent(),
    this.kcal = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.carbG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.fiberG = const Value.absent(),
    this.sodiumMg = const Value.absent(),
    this.cholesterolMg = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       foodId = Value(foodId),
       label = Value(label),
       amountCanonical = Value(amountCanonical),
       amountKind = Value(amountKind);
  static Insertable<FoodServingOptionRow> custom({
    Expression<String>? id,
    Expression<String>? foodId,
    Expression<String>? label,
    Expression<double>? amountCanonical,
    Expression<String>? amountKind,
    Expression<String>? amountUnit,
    Expression<double>? kcal,
    Expression<double>? proteinG,
    Expression<double>? carbG,
    Expression<double>? fatG,
    Expression<double>? fiberG,
    Expression<double>? sodiumMg,
    Expression<double>? cholesterolMg,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (foodId != null) 'food_id': foodId,
      if (label != null) 'label': label,
      if (amountCanonical != null) 'amount_canonical': amountCanonical,
      if (amountKind != null) 'amount_kind': amountKind,
      if (amountUnit != null) 'amount_unit': amountUnit,
      if (kcal != null) 'kcal': kcal,
      if (proteinG != null) 'protein_g': proteinG,
      if (carbG != null) 'carb_g': carbG,
      if (fatG != null) 'fat_g': fatG,
      if (fiberG != null) 'fiber_g': fiberG,
      if (sodiumMg != null) 'sodium_mg': sodiumMg,
      if (cholesterolMg != null) 'cholesterol_mg': cholesterolMg,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoodServingOptionsCompanion copyWith({
    Value<String>? id,
    Value<String>? foodId,
    Value<String>? label,
    Value<double>? amountCanonical,
    Value<String>? amountKind,
    Value<String?>? amountUnit,
    Value<double>? kcal,
    Value<double>? proteinG,
    Value<double>? carbG,
    Value<double>? fatG,
    Value<double?>? fiberG,
    Value<double?>? sodiumMg,
    Value<double?>? cholesterolMg,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return FoodServingOptionsCompanion(
      id: id ?? this.id,
      foodId: foodId ?? this.foodId,
      label: label ?? this.label,
      amountCanonical: amountCanonical ?? this.amountCanonical,
      amountKind: amountKind ?? this.amountKind,
      amountUnit: amountUnit ?? this.amountUnit,
      kcal: kcal ?? this.kcal,
      proteinG: proteinG ?? this.proteinG,
      carbG: carbG ?? this.carbG,
      fatG: fatG ?? this.fatG,
      fiberG: fiberG ?? this.fiberG,
      sodiumMg: sodiumMg ?? this.sodiumMg,
      cholesterolMg: cholesterolMg ?? this.cholesterolMg,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (foodId.present) {
      map['food_id'] = Variable<String>(foodId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (amountCanonical.present) {
      map['amount_canonical'] = Variable<double>(amountCanonical.value);
    }
    if (amountKind.present) {
      map['amount_kind'] = Variable<String>(amountKind.value);
    }
    if (amountUnit.present) {
      map['amount_unit'] = Variable<String>(amountUnit.value);
    }
    if (kcal.present) {
      map['kcal'] = Variable<double>(kcal.value);
    }
    if (proteinG.present) {
      map['protein_g'] = Variable<double>(proteinG.value);
    }
    if (carbG.present) {
      map['carb_g'] = Variable<double>(carbG.value);
    }
    if (fatG.present) {
      map['fat_g'] = Variable<double>(fatG.value);
    }
    if (fiberG.present) {
      map['fiber_g'] = Variable<double>(fiberG.value);
    }
    if (sodiumMg.present) {
      map['sodium_mg'] = Variable<double>(sodiumMg.value);
    }
    if (cholesterolMg.present) {
      map['cholesterol_mg'] = Variable<double>(cholesterolMg.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoodServingOptionsCompanion(')
          ..write('id: $id, ')
          ..write('foodId: $foodId, ')
          ..write('label: $label, ')
          ..write('amountCanonical: $amountCanonical, ')
          ..write('amountKind: $amountKind, ')
          ..write('amountUnit: $amountUnit, ')
          ..write('kcal: $kcal, ')
          ..write('proteinG: $proteinG, ')
          ..write('carbG: $carbG, ')
          ..write('fatG: $fatG, ')
          ..write('fiberG: $fiberG, ')
          ..write('sodiumMg: $sodiumMg, ')
          ..write('cholesterolMg: $cholesterolMg, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MealPlanDaysTable extends MealPlanDays
    with TableInfo<$MealPlanDaysTable, MealPlanDayRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MealPlanDaysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<DateTime> day = GeneratedColumn<DateTime>(
    'day',
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
  @override
  List<GeneratedColumn> get $columns => [id, userId, day, notes, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meal_plan_days';
  @override
  VerificationContext validateIntegrity(
    Insertable<MealPlanDayRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {userId, day},
  ];
  @override
  MealPlanDayRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MealPlanDayRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}day'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MealPlanDaysTable createAlias(String alias) {
    return $MealPlanDaysTable(attachedDatabase, alias);
  }
}

class MealPlanDayRow extends DataClass implements Insertable<MealPlanDayRow> {
  final String id;
  final String userId;
  final DateTime day;
  final String? notes;
  final DateTime updatedAt;
  const MealPlanDayRow({
    required this.id,
    required this.userId,
    required this.day,
    this.notes,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['day'] = Variable<DateTime>(day);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MealPlanDaysCompanion toCompanion(bool nullToAbsent) {
    return MealPlanDaysCompanion(
      id: Value(id),
      userId: Value(userId),
      day: Value(day),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      updatedAt: Value(updatedAt),
    );
  }

  factory MealPlanDayRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MealPlanDayRow(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      day: serializer.fromJson<DateTime>(json['day']),
      notes: serializer.fromJson<String?>(json['notes']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'day': serializer.toJson<DateTime>(day),
      'notes': serializer.toJson<String?>(notes),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MealPlanDayRow copyWith({
    String? id,
    String? userId,
    DateTime? day,
    Value<String?> notes = const Value.absent(),
    DateTime? updatedAt,
  }) => MealPlanDayRow(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    day: day ?? this.day,
    notes: notes.present ? notes.value : this.notes,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MealPlanDayRow copyWithCompanion(MealPlanDaysCompanion data) {
    return MealPlanDayRow(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      day: data.day.present ? data.day.value : this.day,
      notes: data.notes.present ? data.notes.value : this.notes,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MealPlanDayRow(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('day: $day, ')
          ..write('notes: $notes, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, userId, day, notes, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MealPlanDayRow &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.day == this.day &&
          other.notes == this.notes &&
          other.updatedAt == this.updatedAt);
}

class MealPlanDaysCompanion extends UpdateCompanion<MealPlanDayRow> {
  final Value<String> id;
  final Value<String> userId;
  final Value<DateTime> day;
  final Value<String?> notes;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MealPlanDaysCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.day = const Value.absent(),
    this.notes = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MealPlanDaysCompanion.insert({
    required String id,
    required String userId,
    required DateTime day,
    this.notes = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       day = Value(day),
       updatedAt = Value(updatedAt);
  static Insertable<MealPlanDayRow> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<DateTime>? day,
    Expression<String>? notes,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (day != null) 'day': day,
      if (notes != null) 'notes': notes,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MealPlanDaysCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<DateTime>? day,
    Value<String?>? notes,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return MealPlanDaysCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      day: day ?? this.day,
      notes: notes ?? this.notes,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (day.present) {
      map['day'] = Variable<DateTime>(day.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MealPlanDaysCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('day: $day, ')
          ..write('notes: $notes, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MealPlanEntriesTable extends MealPlanEntries
    with TableInfo<$MealPlanEntriesTable, MealPlanEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MealPlanEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayIdMeta = const VerificationMeta('dayId');
  @override
  late final GeneratedColumn<String> dayId = GeneratedColumn<String>(
    'day_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES meal_plan_days (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _mealSlotMeta = const VerificationMeta(
    'mealSlot',
  );
  @override
  late final GeneratedColumn<String> mealSlot = GeneratedColumn<String>(
    'meal_slot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refTypeMeta = const VerificationMeta(
    'refType',
  );
  @override
  late final GeneratedColumn<String> refType = GeneratedColumn<String>(
    'ref_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _servingsMeta = const VerificationMeta(
    'servings',
  );
  @override
  late final GeneratedColumn<double> servings = GeneratedColumn<double>(
    'servings',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPlannedMeta = const VerificationMeta(
    'isPlanned',
  );
  @override
  late final GeneratedColumn<bool> isPlanned = GeneratedColumn<bool>(
    'is_planned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_planned" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _isLoggedMeta = const VerificationMeta(
    'isLogged',
  );
  @override
  late final GeneratedColumn<bool> isLogged = GeneratedColumn<bool>(
    'is_logged',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_logged" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _loggedAtMeta = const VerificationMeta(
    'loggedAt',
  );
  @override
  late final GeneratedColumn<DateTime> loggedAt = GeneratedColumn<DateTime>(
    'logged_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _macroSnapshotMeta = const VerificationMeta(
    'macroSnapshot',
  );
  @override
  late final GeneratedColumn<String> macroSnapshot = GeneratedColumn<String>(
    'macro_snapshot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    dayId,
    mealSlot,
    refType,
    refId,
    servings,
    isPlanned,
    isLogged,
    loggedAt,
    macroSnapshot,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meal_plan_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<MealPlanEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('day_id')) {
      context.handle(
        _dayIdMeta,
        dayId.isAcceptableOrUnknown(data['day_id']!, _dayIdMeta),
      );
    } else if (isInserting) {
      context.missing(_dayIdMeta);
    }
    if (data.containsKey('meal_slot')) {
      context.handle(
        _mealSlotMeta,
        mealSlot.isAcceptableOrUnknown(data['meal_slot']!, _mealSlotMeta),
      );
    } else if (isInserting) {
      context.missing(_mealSlotMeta);
    }
    if (data.containsKey('ref_type')) {
      context.handle(
        _refTypeMeta,
        refType.isAcceptableOrUnknown(data['ref_type']!, _refTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_refTypeMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    } else if (isInserting) {
      context.missing(_refIdMeta);
    }
    if (data.containsKey('servings')) {
      context.handle(
        _servingsMeta,
        servings.isAcceptableOrUnknown(data['servings']!, _servingsMeta),
      );
    } else if (isInserting) {
      context.missing(_servingsMeta);
    }
    if (data.containsKey('is_planned')) {
      context.handle(
        _isPlannedMeta,
        isPlanned.isAcceptableOrUnknown(data['is_planned']!, _isPlannedMeta),
      );
    }
    if (data.containsKey('is_logged')) {
      context.handle(
        _isLoggedMeta,
        isLogged.isAcceptableOrUnknown(data['is_logged']!, _isLoggedMeta),
      );
    }
    if (data.containsKey('logged_at')) {
      context.handle(
        _loggedAtMeta,
        loggedAt.isAcceptableOrUnknown(data['logged_at']!, _loggedAtMeta),
      );
    }
    if (data.containsKey('macro_snapshot')) {
      context.handle(
        _macroSnapshotMeta,
        macroSnapshot.isAcceptableOrUnknown(
          data['macro_snapshot']!,
          _macroSnapshotMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MealPlanEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MealPlanEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      dayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day_id'],
      )!,
      mealSlot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meal_slot'],
      )!,
      refType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_type'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      )!,
      servings: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}servings'],
      )!,
      isPlanned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_planned'],
      )!,
      isLogged: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_logged'],
      )!,
      loggedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}logged_at'],
      ),
      macroSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}macro_snapshot'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MealPlanEntriesTable createAlias(String alias) {
    return $MealPlanEntriesTable(attachedDatabase, alias);
  }
}

class MealPlanEntryRow extends DataClass
    implements Insertable<MealPlanEntryRow> {
  final String id;
  final String dayId;
  final String mealSlot;
  final String refType;
  final String refId;
  final double servings;
  final bool isPlanned;
  final bool isLogged;
  final DateTime? loggedAt;

  /// Macros and portion frozen at log time, as JSON. Never recomputed —
  /// editing a recipe later must not rewrite past days (spec §4).
  final String? macroSnapshot;
  final DateTime updatedAt;
  const MealPlanEntryRow({
    required this.id,
    required this.dayId,
    required this.mealSlot,
    required this.refType,
    required this.refId,
    required this.servings,
    required this.isPlanned,
    required this.isLogged,
    this.loggedAt,
    this.macroSnapshot,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['day_id'] = Variable<String>(dayId);
    map['meal_slot'] = Variable<String>(mealSlot);
    map['ref_type'] = Variable<String>(refType);
    map['ref_id'] = Variable<String>(refId);
    map['servings'] = Variable<double>(servings);
    map['is_planned'] = Variable<bool>(isPlanned);
    map['is_logged'] = Variable<bool>(isLogged);
    if (!nullToAbsent || loggedAt != null) {
      map['logged_at'] = Variable<DateTime>(loggedAt);
    }
    if (!nullToAbsent || macroSnapshot != null) {
      map['macro_snapshot'] = Variable<String>(macroSnapshot);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MealPlanEntriesCompanion toCompanion(bool nullToAbsent) {
    return MealPlanEntriesCompanion(
      id: Value(id),
      dayId: Value(dayId),
      mealSlot: Value(mealSlot),
      refType: Value(refType),
      refId: Value(refId),
      servings: Value(servings),
      isPlanned: Value(isPlanned),
      isLogged: Value(isLogged),
      loggedAt: loggedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(loggedAt),
      macroSnapshot: macroSnapshot == null && nullToAbsent
          ? const Value.absent()
          : Value(macroSnapshot),
      updatedAt: Value(updatedAt),
    );
  }

  factory MealPlanEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MealPlanEntryRow(
      id: serializer.fromJson<String>(json['id']),
      dayId: serializer.fromJson<String>(json['dayId']),
      mealSlot: serializer.fromJson<String>(json['mealSlot']),
      refType: serializer.fromJson<String>(json['refType']),
      refId: serializer.fromJson<String>(json['refId']),
      servings: serializer.fromJson<double>(json['servings']),
      isPlanned: serializer.fromJson<bool>(json['isPlanned']),
      isLogged: serializer.fromJson<bool>(json['isLogged']),
      loggedAt: serializer.fromJson<DateTime?>(json['loggedAt']),
      macroSnapshot: serializer.fromJson<String?>(json['macroSnapshot']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'dayId': serializer.toJson<String>(dayId),
      'mealSlot': serializer.toJson<String>(mealSlot),
      'refType': serializer.toJson<String>(refType),
      'refId': serializer.toJson<String>(refId),
      'servings': serializer.toJson<double>(servings),
      'isPlanned': serializer.toJson<bool>(isPlanned),
      'isLogged': serializer.toJson<bool>(isLogged),
      'loggedAt': serializer.toJson<DateTime?>(loggedAt),
      'macroSnapshot': serializer.toJson<String?>(macroSnapshot),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MealPlanEntryRow copyWith({
    String? id,
    String? dayId,
    String? mealSlot,
    String? refType,
    String? refId,
    double? servings,
    bool? isPlanned,
    bool? isLogged,
    Value<DateTime?> loggedAt = const Value.absent(),
    Value<String?> macroSnapshot = const Value.absent(),
    DateTime? updatedAt,
  }) => MealPlanEntryRow(
    id: id ?? this.id,
    dayId: dayId ?? this.dayId,
    mealSlot: mealSlot ?? this.mealSlot,
    refType: refType ?? this.refType,
    refId: refId ?? this.refId,
    servings: servings ?? this.servings,
    isPlanned: isPlanned ?? this.isPlanned,
    isLogged: isLogged ?? this.isLogged,
    loggedAt: loggedAt.present ? loggedAt.value : this.loggedAt,
    macroSnapshot: macroSnapshot.present
        ? macroSnapshot.value
        : this.macroSnapshot,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MealPlanEntryRow copyWithCompanion(MealPlanEntriesCompanion data) {
    return MealPlanEntryRow(
      id: data.id.present ? data.id.value : this.id,
      dayId: data.dayId.present ? data.dayId.value : this.dayId,
      mealSlot: data.mealSlot.present ? data.mealSlot.value : this.mealSlot,
      refType: data.refType.present ? data.refType.value : this.refType,
      refId: data.refId.present ? data.refId.value : this.refId,
      servings: data.servings.present ? data.servings.value : this.servings,
      isPlanned: data.isPlanned.present ? data.isPlanned.value : this.isPlanned,
      isLogged: data.isLogged.present ? data.isLogged.value : this.isLogged,
      loggedAt: data.loggedAt.present ? data.loggedAt.value : this.loggedAt,
      macroSnapshot: data.macroSnapshot.present
          ? data.macroSnapshot.value
          : this.macroSnapshot,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MealPlanEntryRow(')
          ..write('id: $id, ')
          ..write('dayId: $dayId, ')
          ..write('mealSlot: $mealSlot, ')
          ..write('refType: $refType, ')
          ..write('refId: $refId, ')
          ..write('servings: $servings, ')
          ..write('isPlanned: $isPlanned, ')
          ..write('isLogged: $isLogged, ')
          ..write('loggedAt: $loggedAt, ')
          ..write('macroSnapshot: $macroSnapshot, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    dayId,
    mealSlot,
    refType,
    refId,
    servings,
    isPlanned,
    isLogged,
    loggedAt,
    macroSnapshot,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MealPlanEntryRow &&
          other.id == this.id &&
          other.dayId == this.dayId &&
          other.mealSlot == this.mealSlot &&
          other.refType == this.refType &&
          other.refId == this.refId &&
          other.servings == this.servings &&
          other.isPlanned == this.isPlanned &&
          other.isLogged == this.isLogged &&
          other.loggedAt == this.loggedAt &&
          other.macroSnapshot == this.macroSnapshot &&
          other.updatedAt == this.updatedAt);
}

class MealPlanEntriesCompanion extends UpdateCompanion<MealPlanEntryRow> {
  final Value<String> id;
  final Value<String> dayId;
  final Value<String> mealSlot;
  final Value<String> refType;
  final Value<String> refId;
  final Value<double> servings;
  final Value<bool> isPlanned;
  final Value<bool> isLogged;
  final Value<DateTime?> loggedAt;
  final Value<String?> macroSnapshot;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MealPlanEntriesCompanion({
    this.id = const Value.absent(),
    this.dayId = const Value.absent(),
    this.mealSlot = const Value.absent(),
    this.refType = const Value.absent(),
    this.refId = const Value.absent(),
    this.servings = const Value.absent(),
    this.isPlanned = const Value.absent(),
    this.isLogged = const Value.absent(),
    this.loggedAt = const Value.absent(),
    this.macroSnapshot = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MealPlanEntriesCompanion.insert({
    required String id,
    required String dayId,
    required String mealSlot,
    required String refType,
    required String refId,
    required double servings,
    this.isPlanned = const Value.absent(),
    this.isLogged = const Value.absent(),
    this.loggedAt = const Value.absent(),
    this.macroSnapshot = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       dayId = Value(dayId),
       mealSlot = Value(mealSlot),
       refType = Value(refType),
       refId = Value(refId),
       servings = Value(servings),
       updatedAt = Value(updatedAt);
  static Insertable<MealPlanEntryRow> custom({
    Expression<String>? id,
    Expression<String>? dayId,
    Expression<String>? mealSlot,
    Expression<String>? refType,
    Expression<String>? refId,
    Expression<double>? servings,
    Expression<bool>? isPlanned,
    Expression<bool>? isLogged,
    Expression<DateTime>? loggedAt,
    Expression<String>? macroSnapshot,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dayId != null) 'day_id': dayId,
      if (mealSlot != null) 'meal_slot': mealSlot,
      if (refType != null) 'ref_type': refType,
      if (refId != null) 'ref_id': refId,
      if (servings != null) 'servings': servings,
      if (isPlanned != null) 'is_planned': isPlanned,
      if (isLogged != null) 'is_logged': isLogged,
      if (loggedAt != null) 'logged_at': loggedAt,
      if (macroSnapshot != null) 'macro_snapshot': macroSnapshot,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MealPlanEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? dayId,
    Value<String>? mealSlot,
    Value<String>? refType,
    Value<String>? refId,
    Value<double>? servings,
    Value<bool>? isPlanned,
    Value<bool>? isLogged,
    Value<DateTime?>? loggedAt,
    Value<String?>? macroSnapshot,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return MealPlanEntriesCompanion(
      id: id ?? this.id,
      dayId: dayId ?? this.dayId,
      mealSlot: mealSlot ?? this.mealSlot,
      refType: refType ?? this.refType,
      refId: refId ?? this.refId,
      servings: servings ?? this.servings,
      isPlanned: isPlanned ?? this.isPlanned,
      isLogged: isLogged ?? this.isLogged,
      loggedAt: loggedAt ?? this.loggedAt,
      macroSnapshot: macroSnapshot ?? this.macroSnapshot,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (dayId.present) {
      map['day_id'] = Variable<String>(dayId.value);
    }
    if (mealSlot.present) {
      map['meal_slot'] = Variable<String>(mealSlot.value);
    }
    if (refType.present) {
      map['ref_type'] = Variable<String>(refType.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (servings.present) {
      map['servings'] = Variable<double>(servings.value);
    }
    if (isPlanned.present) {
      map['is_planned'] = Variable<bool>(isPlanned.value);
    }
    if (isLogged.present) {
      map['is_logged'] = Variable<bool>(isLogged.value);
    }
    if (loggedAt.present) {
      map['logged_at'] = Variable<DateTime>(loggedAt.value);
    }
    if (macroSnapshot.present) {
      map['macro_snapshot'] = Variable<String>(macroSnapshot.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MealPlanEntriesCompanion(')
          ..write('id: $id, ')
          ..write('dayId: $dayId, ')
          ..write('mealSlot: $mealSlot, ')
          ..write('refType: $refType, ')
          ..write('refId: $refId, ')
          ..write('servings: $servings, ')
          ..write('isPlanned: $isPlanned, ')
          ..write('isLogged: $isLogged, ')
          ..write('loggedAt: $loggedAt, ')
          ..write('macroSnapshot: $macroSnapshot, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MacroTargetsTable extends MacroTargets
    with TableInfo<$MacroTargetsTable, MacroTargetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MacroTargetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _weekStartDateMeta = const VerificationMeta(
    'weekStartDate',
  );
  @override
  late final GeneratedColumn<DateTime> weekStartDate =
      GeneratedColumn<DateTime>(
        'week_start_date',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _kcalMeta = const VerificationMeta('kcal');
  @override
  late final GeneratedColumn<double> kcal = GeneratedColumn<double>(
    'kcal',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _proteinGMeta = const VerificationMeta(
    'proteinG',
  );
  @override
  late final GeneratedColumn<double> proteinG = GeneratedColumn<double>(
    'protein_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _carbGMeta = const VerificationMeta('carbG');
  @override
  late final GeneratedColumn<double> carbG = GeneratedColumn<double>(
    'carb_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fatGMeta = const VerificationMeta('fatG');
  @override
  late final GeneratedColumn<double> fatG = GeneratedColumn<double>(
    'fat_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    weekStartDate,
    kcal,
    proteinG,
    carbG,
    fatG,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'macro_targets';
  @override
  VerificationContext validateIntegrity(
    Insertable<MacroTargetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('week_start_date')) {
      context.handle(
        _weekStartDateMeta,
        weekStartDate.isAcceptableOrUnknown(
          data['week_start_date']!,
          _weekStartDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_weekStartDateMeta);
    }
    if (data.containsKey('kcal')) {
      context.handle(
        _kcalMeta,
        kcal.isAcceptableOrUnknown(data['kcal']!, _kcalMeta),
      );
    } else if (isInserting) {
      context.missing(_kcalMeta);
    }
    if (data.containsKey('protein_g')) {
      context.handle(
        _proteinGMeta,
        proteinG.isAcceptableOrUnknown(data['protein_g']!, _proteinGMeta),
      );
    } else if (isInserting) {
      context.missing(_proteinGMeta);
    }
    if (data.containsKey('carb_g')) {
      context.handle(
        _carbGMeta,
        carbG.isAcceptableOrUnknown(data['carb_g']!, _carbGMeta),
      );
    } else if (isInserting) {
      context.missing(_carbGMeta);
    }
    if (data.containsKey('fat_g')) {
      context.handle(
        _fatGMeta,
        fatG.isAcceptableOrUnknown(data['fat_g']!, _fatGMeta),
      );
    } else if (isInserting) {
      context.missing(_fatGMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {userId, weekStartDate},
  ];
  @override
  MacroTargetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MacroTargetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      weekStartDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}week_start_date'],
      )!,
      kcal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}kcal'],
      )!,
      proteinG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_g'],
      )!,
      carbG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carb_g'],
      )!,
      fatG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_g'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MacroTargetsTable createAlias(String alias) {
    return $MacroTargetsTable(attachedDatabase, alias);
  }
}

class MacroTargetRow extends DataClass implements Insertable<MacroTargetRow> {
  final String id;
  final String userId;
  final DateTime weekStartDate;
  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;
  final DateTime updatedAt;
  const MacroTargetRow({
    required this.id,
    required this.userId,
    required this.weekStartDate,
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['week_start_date'] = Variable<DateTime>(weekStartDate);
    map['kcal'] = Variable<double>(kcal);
    map['protein_g'] = Variable<double>(proteinG);
    map['carb_g'] = Variable<double>(carbG);
    map['fat_g'] = Variable<double>(fatG);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MacroTargetsCompanion toCompanion(bool nullToAbsent) {
    return MacroTargetsCompanion(
      id: Value(id),
      userId: Value(userId),
      weekStartDate: Value(weekStartDate),
      kcal: Value(kcal),
      proteinG: Value(proteinG),
      carbG: Value(carbG),
      fatG: Value(fatG),
      updatedAt: Value(updatedAt),
    );
  }

  factory MacroTargetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MacroTargetRow(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      weekStartDate: serializer.fromJson<DateTime>(json['weekStartDate']),
      kcal: serializer.fromJson<double>(json['kcal']),
      proteinG: serializer.fromJson<double>(json['proteinG']),
      carbG: serializer.fromJson<double>(json['carbG']),
      fatG: serializer.fromJson<double>(json['fatG']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'weekStartDate': serializer.toJson<DateTime>(weekStartDate),
      'kcal': serializer.toJson<double>(kcal),
      'proteinG': serializer.toJson<double>(proteinG),
      'carbG': serializer.toJson<double>(carbG),
      'fatG': serializer.toJson<double>(fatG),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MacroTargetRow copyWith({
    String? id,
    String? userId,
    DateTime? weekStartDate,
    double? kcal,
    double? proteinG,
    double? carbG,
    double? fatG,
    DateTime? updatedAt,
  }) => MacroTargetRow(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    weekStartDate: weekStartDate ?? this.weekStartDate,
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbG: carbG ?? this.carbG,
    fatG: fatG ?? this.fatG,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MacroTargetRow copyWithCompanion(MacroTargetsCompanion data) {
    return MacroTargetRow(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      weekStartDate: data.weekStartDate.present
          ? data.weekStartDate.value
          : this.weekStartDate,
      kcal: data.kcal.present ? data.kcal.value : this.kcal,
      proteinG: data.proteinG.present ? data.proteinG.value : this.proteinG,
      carbG: data.carbG.present ? data.carbG.value : this.carbG,
      fatG: data.fatG.present ? data.fatG.value : this.fatG,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MacroTargetRow(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('weekStartDate: $weekStartDate, ')
          ..write('kcal: $kcal, ')
          ..write('proteinG: $proteinG, ')
          ..write('carbG: $carbG, ')
          ..write('fatG: $fatG, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    weekStartDate,
    kcal,
    proteinG,
    carbG,
    fatG,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MacroTargetRow &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.weekStartDate == this.weekStartDate &&
          other.kcal == this.kcal &&
          other.proteinG == this.proteinG &&
          other.carbG == this.carbG &&
          other.fatG == this.fatG &&
          other.updatedAt == this.updatedAt);
}

class MacroTargetsCompanion extends UpdateCompanion<MacroTargetRow> {
  final Value<String> id;
  final Value<String> userId;
  final Value<DateTime> weekStartDate;
  final Value<double> kcal;
  final Value<double> proteinG;
  final Value<double> carbG;
  final Value<double> fatG;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MacroTargetsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.weekStartDate = const Value.absent(),
    this.kcal = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.carbG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MacroTargetsCompanion.insert({
    required String id,
    required String userId,
    required DateTime weekStartDate,
    required double kcal,
    required double proteinG,
    required double carbG,
    required double fatG,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       weekStartDate = Value(weekStartDate),
       kcal = Value(kcal),
       proteinG = Value(proteinG),
       carbG = Value(carbG),
       fatG = Value(fatG),
       updatedAt = Value(updatedAt);
  static Insertable<MacroTargetRow> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<DateTime>? weekStartDate,
    Expression<double>? kcal,
    Expression<double>? proteinG,
    Expression<double>? carbG,
    Expression<double>? fatG,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (weekStartDate != null) 'week_start_date': weekStartDate,
      if (kcal != null) 'kcal': kcal,
      if (proteinG != null) 'protein_g': proteinG,
      if (carbG != null) 'carb_g': carbG,
      if (fatG != null) 'fat_g': fatG,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MacroTargetsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<DateTime>? weekStartDate,
    Value<double>? kcal,
    Value<double>? proteinG,
    Value<double>? carbG,
    Value<double>? fatG,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return MacroTargetsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      weekStartDate: weekStartDate ?? this.weekStartDate,
      kcal: kcal ?? this.kcal,
      proteinG: proteinG ?? this.proteinG,
      carbG: carbG ?? this.carbG,
      fatG: fatG ?? this.fatG,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (weekStartDate.present) {
      map['week_start_date'] = Variable<DateTime>(weekStartDate.value);
    }
    if (kcal.present) {
      map['kcal'] = Variable<double>(kcal.value);
    }
    if (proteinG.present) {
      map['protein_g'] = Variable<double>(proteinG.value);
    }
    if (carbG.present) {
      map['carb_g'] = Variable<double>(carbG.value);
    }
    if (fatG.present) {
      map['fat_g'] = Variable<double>(fatG.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MacroTargetsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('weekStartDate: $weekStartDate, ')
          ..write('kcal: $kcal, ')
          ..write('proteinG: $proteinG, ')
          ..write('carbG: $carbG, ')
          ..write('fatG: $fatG, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IngredientMatchesTable extends IngredientMatches
    with TableInfo<$IngredientMatchesTable, IngredientMatchRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IngredientMatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ingredientStringMeta = const VerificationMeta(
    'ingredientString',
  );
  @override
  late final GeneratedColumn<String> ingredientString = GeneratedColumn<String>(
    'ingredient_string',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _foodIdMeta = const VerificationMeta('foodId');
  @override
  late final GeneratedColumn<String> foodId = GeneratedColumn<String>(
    'food_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES foods (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _needsNoMatchMeta = const VerificationMeta(
    'needsNoMatch',
  );
  @override
  late final GeneratedColumn<bool> needsNoMatch = GeneratedColumn<bool>(
    'needs_no_match',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_no_match" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    ingredientString,
    foodId,
    needsNoMatch,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ingredient_matches';
  @override
  VerificationContext validateIntegrity(
    Insertable<IngredientMatchRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('ingredient_string')) {
      context.handle(
        _ingredientStringMeta,
        ingredientString.isAcceptableOrUnknown(
          data['ingredient_string']!,
          _ingredientStringMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ingredientStringMeta);
    }
    if (data.containsKey('food_id')) {
      context.handle(
        _foodIdMeta,
        foodId.isAcceptableOrUnknown(data['food_id']!, _foodIdMeta),
      );
    }
    if (data.containsKey('needs_no_match')) {
      context.handle(
        _needsNoMatchMeta,
        needsNoMatch.isAcceptableOrUnknown(
          data['needs_no_match']!,
          _needsNoMatchMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {householdId, ingredientString},
  ];
  @override
  IngredientMatchRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IngredientMatchRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      ingredientString: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ingredient_string'],
      )!,
      foodId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}food_id'],
      ),
      needsNoMatch: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_no_match'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $IngredientMatchesTable createAlias(String alias) {
    return $IngredientMatchesTable(attachedDatabase, alias);
  }
}

class IngredientMatchRow extends DataClass
    implements Insertable<IngredientMatchRow> {
  final String id;
  final String householdId;

  /// The normalised ingredient string — the same key the density lookup and
  /// consolidation use, so they all agree on what counts as "the same thing".
  final String ingredientString;

  /// Null when the answer is [needsNoMatch] rather than a food.
  final String? foodId;

  /// The other answer this row can carry: nothing to match, because the line
  /// is salt (spec §5.3).
  ///
  /// One table rather than two, because "what does this wording resolve to?"
  /// is one question — and the unique key below already guarantees one answer
  /// per wording. Two tables could disagree about the same string.
  final bool needsNoMatch;
  final DateTime updatedAt;
  const IngredientMatchRow({
    required this.id,
    required this.householdId,
    required this.ingredientString,
    this.foodId,
    required this.needsNoMatch,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['ingredient_string'] = Variable<String>(ingredientString);
    if (!nullToAbsent || foodId != null) {
      map['food_id'] = Variable<String>(foodId);
    }
    map['needs_no_match'] = Variable<bool>(needsNoMatch);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  IngredientMatchesCompanion toCompanion(bool nullToAbsent) {
    return IngredientMatchesCompanion(
      id: Value(id),
      householdId: Value(householdId),
      ingredientString: Value(ingredientString),
      foodId: foodId == null && nullToAbsent
          ? const Value.absent()
          : Value(foodId),
      needsNoMatch: Value(needsNoMatch),
      updatedAt: Value(updatedAt),
    );
  }

  factory IngredientMatchRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IngredientMatchRow(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      ingredientString: serializer.fromJson<String>(json['ingredientString']),
      foodId: serializer.fromJson<String?>(json['foodId']),
      needsNoMatch: serializer.fromJson<bool>(json['needsNoMatch']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'ingredientString': serializer.toJson<String>(ingredientString),
      'foodId': serializer.toJson<String?>(foodId),
      'needsNoMatch': serializer.toJson<bool>(needsNoMatch),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  IngredientMatchRow copyWith({
    String? id,
    String? householdId,
    String? ingredientString,
    Value<String?> foodId = const Value.absent(),
    bool? needsNoMatch,
    DateTime? updatedAt,
  }) => IngredientMatchRow(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    ingredientString: ingredientString ?? this.ingredientString,
    foodId: foodId.present ? foodId.value : this.foodId,
    needsNoMatch: needsNoMatch ?? this.needsNoMatch,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  IngredientMatchRow copyWithCompanion(IngredientMatchesCompanion data) {
    return IngredientMatchRow(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      ingredientString: data.ingredientString.present
          ? data.ingredientString.value
          : this.ingredientString,
      foodId: data.foodId.present ? data.foodId.value : this.foodId,
      needsNoMatch: data.needsNoMatch.present
          ? data.needsNoMatch.value
          : this.needsNoMatch,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IngredientMatchRow(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('ingredientString: $ingredientString, ')
          ..write('foodId: $foodId, ')
          ..write('needsNoMatch: $needsNoMatch, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    ingredientString,
    foodId,
    needsNoMatch,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IngredientMatchRow &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.ingredientString == this.ingredientString &&
          other.foodId == this.foodId &&
          other.needsNoMatch == this.needsNoMatch &&
          other.updatedAt == this.updatedAt);
}

class IngredientMatchesCompanion extends UpdateCompanion<IngredientMatchRow> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> ingredientString;
  final Value<String?> foodId;
  final Value<bool> needsNoMatch;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const IngredientMatchesCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.ingredientString = const Value.absent(),
    this.foodId = const Value.absent(),
    this.needsNoMatch = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IngredientMatchesCompanion.insert({
    required String id,
    required String householdId,
    required String ingredientString,
    this.foodId = const Value.absent(),
    this.needsNoMatch = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       ingredientString = Value(ingredientString),
       updatedAt = Value(updatedAt);
  static Insertable<IngredientMatchRow> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? ingredientString,
    Expression<String>? foodId,
    Expression<bool>? needsNoMatch,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (ingredientString != null) 'ingredient_string': ingredientString,
      if (foodId != null) 'food_id': foodId,
      if (needsNoMatch != null) 'needs_no_match': needsNoMatch,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IngredientMatchesCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? ingredientString,
    Value<String?>? foodId,
    Value<bool>? needsNoMatch,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return IngredientMatchesCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      ingredientString: ingredientString ?? this.ingredientString,
      foodId: foodId ?? this.foodId,
      needsNoMatch: needsNoMatch ?? this.needsNoMatch,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (ingredientString.present) {
      map['ingredient_string'] = Variable<String>(ingredientString.value);
    }
    if (foodId.present) {
      map['food_id'] = Variable<String>(foodId.value);
    }
    if (needsNoMatch.present) {
      map['needs_no_match'] = Variable<bool>(needsNoMatch.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IngredientMatchesCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('ingredientString: $ingredientString, ')
          ..write('foodId: $foodId, ')
          ..write('needsNoMatch: $needsNoMatch, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CookTimersTable extends CookTimers
    with TableInfo<$CookTimersTable, CookTimerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CookTimersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepNumberMeta = const VerificationMeta(
    'stepNumber',
  );
  @override
  late final GeneratedColumn<int> stepNumber = GeneratedColumn<int>(
    'step_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stepIdMeta = const VerificationMeta('stepId');
  @override
  late final GeneratedColumn<String> stepId = GeneratedColumn<String>(
    'step_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _elapsedWhenPausedSecondsMeta =
      const VerificationMeta('elapsedWhenPausedSeconds');
  @override
  late final GeneratedColumn<int> elapsedWhenPausedSeconds =
      GeneratedColumn<int>(
        'elapsed_when_paused_seconds',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _recipeTitleMeta = const VerificationMeta(
    'recipeTitle',
  );
  @override
  late final GeneratedColumn<String> recipeTitle = GeneratedColumn<String>(
    'recipe_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    label,
    durationSeconds,
    startedAt,
    stepNumber,
    stepId,
    elapsedWhenPausedSeconds,
    recipeTitle,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cook_timers';
  @override
  VerificationContext validateIntegrity(
    Insertable<CookTimerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationSecondsMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('step_number')) {
      context.handle(
        _stepNumberMeta,
        stepNumber.isAcceptableOrUnknown(data['step_number']!, _stepNumberMeta),
      );
    }
    if (data.containsKey('step_id')) {
      context.handle(
        _stepIdMeta,
        stepId.isAcceptableOrUnknown(data['step_id']!, _stepIdMeta),
      );
    }
    if (data.containsKey('elapsed_when_paused_seconds')) {
      context.handle(
        _elapsedWhenPausedSecondsMeta,
        elapsedWhenPausedSeconds.isAcceptableOrUnknown(
          data['elapsed_when_paused_seconds']!,
          _elapsedWhenPausedSecondsMeta,
        ),
      );
    }
    if (data.containsKey('recipe_title')) {
      context.handle(
        _recipeTitleMeta,
        recipeTitle.isAcceptableOrUnknown(
          data['recipe_title']!,
          _recipeTitleMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CookTimerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CookTimerRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      stepNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}step_number'],
      ),
      stepId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}step_id'],
      ),
      elapsedWhenPausedSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}elapsed_when_paused_seconds'],
      ),
      recipeTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_title'],
      ),
    );
  }

  @override
  $CookTimersTable createAlias(String alias) {
    return $CookTimersTable(attachedDatabase, alias);
  }
}

class CookTimerRow extends DataClass implements Insertable<CookTimerRow> {
  final String id;
  final String label;
  final int durationSeconds;
  final DateTime startedAt;
  final int? stepNumber;

  /// The step this timer belongs to — one timer per step, not one per tap.
  final String? stepId;

  /// Elapsed seconds at the moment it was paused; null while running.
  final int? elapsedWhenPausedSeconds;

  /// What was being cooked, for a timer seen from outside cook mode.
  final String? recipeTitle;
  const CookTimerRow({
    required this.id,
    required this.label,
    required this.durationSeconds,
    required this.startedAt,
    this.stepNumber,
    this.stepId,
    this.elapsedWhenPausedSeconds,
    this.recipeTitle,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['label'] = Variable<String>(label);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || stepNumber != null) {
      map['step_number'] = Variable<int>(stepNumber);
    }
    if (!nullToAbsent || stepId != null) {
      map['step_id'] = Variable<String>(stepId);
    }
    if (!nullToAbsent || elapsedWhenPausedSeconds != null) {
      map['elapsed_when_paused_seconds'] = Variable<int>(
        elapsedWhenPausedSeconds,
      );
    }
    if (!nullToAbsent || recipeTitle != null) {
      map['recipe_title'] = Variable<String>(recipeTitle);
    }
    return map;
  }

  CookTimersCompanion toCompanion(bool nullToAbsent) {
    return CookTimersCompanion(
      id: Value(id),
      label: Value(label),
      durationSeconds: Value(durationSeconds),
      startedAt: Value(startedAt),
      stepNumber: stepNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(stepNumber),
      stepId: stepId == null && nullToAbsent
          ? const Value.absent()
          : Value(stepId),
      elapsedWhenPausedSeconds: elapsedWhenPausedSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(elapsedWhenPausedSeconds),
      recipeTitle: recipeTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(recipeTitle),
    );
  }

  factory CookTimerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CookTimerRow(
      id: serializer.fromJson<String>(json['id']),
      label: serializer.fromJson<String>(json['label']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      stepNumber: serializer.fromJson<int?>(json['stepNumber']),
      stepId: serializer.fromJson<String?>(json['stepId']),
      elapsedWhenPausedSeconds: serializer.fromJson<int?>(
        json['elapsedWhenPausedSeconds'],
      ),
      recipeTitle: serializer.fromJson<String?>(json['recipeTitle']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'label': serializer.toJson<String>(label),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'stepNumber': serializer.toJson<int?>(stepNumber),
      'stepId': serializer.toJson<String?>(stepId),
      'elapsedWhenPausedSeconds': serializer.toJson<int?>(
        elapsedWhenPausedSeconds,
      ),
      'recipeTitle': serializer.toJson<String?>(recipeTitle),
    };
  }

  CookTimerRow copyWith({
    String? id,
    String? label,
    int? durationSeconds,
    DateTime? startedAt,
    Value<int?> stepNumber = const Value.absent(),
    Value<String?> stepId = const Value.absent(),
    Value<int?> elapsedWhenPausedSeconds = const Value.absent(),
    Value<String?> recipeTitle = const Value.absent(),
  }) => CookTimerRow(
    id: id ?? this.id,
    label: label ?? this.label,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    startedAt: startedAt ?? this.startedAt,
    stepNumber: stepNumber.present ? stepNumber.value : this.stepNumber,
    stepId: stepId.present ? stepId.value : this.stepId,
    elapsedWhenPausedSeconds: elapsedWhenPausedSeconds.present
        ? elapsedWhenPausedSeconds.value
        : this.elapsedWhenPausedSeconds,
    recipeTitle: recipeTitle.present ? recipeTitle.value : this.recipeTitle,
  );
  CookTimerRow copyWithCompanion(CookTimersCompanion data) {
    return CookTimerRow(
      id: data.id.present ? data.id.value : this.id,
      label: data.label.present ? data.label.value : this.label,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      stepNumber: data.stepNumber.present
          ? data.stepNumber.value
          : this.stepNumber,
      stepId: data.stepId.present ? data.stepId.value : this.stepId,
      elapsedWhenPausedSeconds: data.elapsedWhenPausedSeconds.present
          ? data.elapsedWhenPausedSeconds.value
          : this.elapsedWhenPausedSeconds,
      recipeTitle: data.recipeTitle.present
          ? data.recipeTitle.value
          : this.recipeTitle,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CookTimerRow(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('startedAt: $startedAt, ')
          ..write('stepNumber: $stepNumber, ')
          ..write('stepId: $stepId, ')
          ..write('elapsedWhenPausedSeconds: $elapsedWhenPausedSeconds, ')
          ..write('recipeTitle: $recipeTitle')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    label,
    durationSeconds,
    startedAt,
    stepNumber,
    stepId,
    elapsedWhenPausedSeconds,
    recipeTitle,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CookTimerRow &&
          other.id == this.id &&
          other.label == this.label &&
          other.durationSeconds == this.durationSeconds &&
          other.startedAt == this.startedAt &&
          other.stepNumber == this.stepNumber &&
          other.stepId == this.stepId &&
          other.elapsedWhenPausedSeconds == this.elapsedWhenPausedSeconds &&
          other.recipeTitle == this.recipeTitle);
}

class CookTimersCompanion extends UpdateCompanion<CookTimerRow> {
  final Value<String> id;
  final Value<String> label;
  final Value<int> durationSeconds;
  final Value<DateTime> startedAt;
  final Value<int?> stepNumber;
  final Value<String?> stepId;
  final Value<int?> elapsedWhenPausedSeconds;
  final Value<String?> recipeTitle;
  final Value<int> rowid;
  const CookTimersCompanion({
    this.id = const Value.absent(),
    this.label = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.stepNumber = const Value.absent(),
    this.stepId = const Value.absent(),
    this.elapsedWhenPausedSeconds = const Value.absent(),
    this.recipeTitle = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CookTimersCompanion.insert({
    required String id,
    required String label,
    required int durationSeconds,
    required DateTime startedAt,
    this.stepNumber = const Value.absent(),
    this.stepId = const Value.absent(),
    this.elapsedWhenPausedSeconds = const Value.absent(),
    this.recipeTitle = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       label = Value(label),
       durationSeconds = Value(durationSeconds),
       startedAt = Value(startedAt);
  static Insertable<CookTimerRow> custom({
    Expression<String>? id,
    Expression<String>? label,
    Expression<int>? durationSeconds,
    Expression<DateTime>? startedAt,
    Expression<int>? stepNumber,
    Expression<String>? stepId,
    Expression<int>? elapsedWhenPausedSeconds,
    Expression<String>? recipeTitle,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (label != null) 'label': label,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (startedAt != null) 'started_at': startedAt,
      if (stepNumber != null) 'step_number': stepNumber,
      if (stepId != null) 'step_id': stepId,
      if (elapsedWhenPausedSeconds != null)
        'elapsed_when_paused_seconds': elapsedWhenPausedSeconds,
      if (recipeTitle != null) 'recipe_title': recipeTitle,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CookTimersCompanion copyWith({
    Value<String>? id,
    Value<String>? label,
    Value<int>? durationSeconds,
    Value<DateTime>? startedAt,
    Value<int?>? stepNumber,
    Value<String?>? stepId,
    Value<int?>? elapsedWhenPausedSeconds,
    Value<String?>? recipeTitle,
    Value<int>? rowid,
  }) {
    return CookTimersCompanion(
      id: id ?? this.id,
      label: label ?? this.label,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      startedAt: startedAt ?? this.startedAt,
      stepNumber: stepNumber ?? this.stepNumber,
      stepId: stepId ?? this.stepId,
      elapsedWhenPausedSeconds:
          elapsedWhenPausedSeconds ?? this.elapsedWhenPausedSeconds,
      recipeTitle: recipeTitle ?? this.recipeTitle,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (stepNumber.present) {
      map['step_number'] = Variable<int>(stepNumber.value);
    }
    if (stepId.present) {
      map['step_id'] = Variable<String>(stepId.value);
    }
    if (elapsedWhenPausedSeconds.present) {
      map['elapsed_when_paused_seconds'] = Variable<int>(
        elapsedWhenPausedSeconds.value,
      );
    }
    if (recipeTitle.present) {
      map['recipe_title'] = Variable<String>(recipeTitle.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CookTimersCompanion(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('startedAt: $startedAt, ')
          ..write('stepNumber: $stepNumber, ')
          ..write('stepId: $stepId, ')
          ..write('elapsedWhenPausedSeconds: $elapsedWhenPausedSeconds, ')
          ..write('recipeTitle: $recipeTitle, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FoodProfilesTable extends FoodProfiles
    with TableInfo<$FoodProfilesTable, FoodProfileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoodProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _caloriesPerMealTargetMeta =
      const VerificationMeta('caloriesPerMealTarget');
  @override
  late final GeneratedColumn<double> caloriesPerMealTarget =
      GeneratedColumn<double>(
        'calories_per_meal_target',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _proteinTargetGMeta = const VerificationMeta(
    'proteinTargetG',
  );
  @override
  late final GeneratedColumn<double> proteinTargetG = GeneratedColumn<double>(
    'protein_target_g',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _preferredMealTypesMeta =
      const VerificationMeta('preferredMealTypes');
  @override
  late final GeneratedColumn<String> preferredMealTypes =
      GeneratedColumn<String>(
        'preferred_meal_types',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant<String>(''),
      );
  static const VerificationMeta _dietaryPreferencesMeta =
      const VerificationMeta('dietaryPreferences');
  @override
  late final GeneratedColumn<String> dietaryPreferences =
      GeneratedColumn<String>(
        'dietary_preferences',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant<String>(''),
      );
  static const VerificationMeta _dislikesMeta = const VerificationMeta(
    'dislikes',
  );
  @override
  late final GeneratedColumn<String> dislikes = GeneratedColumn<String>(
    'dislikes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant<String>(''),
  );
  static const VerificationMeta _allergiesMeta = const VerificationMeta(
    'allergies',
  );
  @override
  late final GeneratedColumn<String> allergies = GeneratedColumn<String>(
    'allergies',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant<String>(''),
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
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    caloriesPerMealTarget,
    proteinTargetG,
    preferredMealTypes,
    dietaryPreferences,
    dislikes,
    allergies,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'food_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<FoodProfileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('calories_per_meal_target')) {
      context.handle(
        _caloriesPerMealTargetMeta,
        caloriesPerMealTarget.isAcceptableOrUnknown(
          data['calories_per_meal_target']!,
          _caloriesPerMealTargetMeta,
        ),
      );
    }
    if (data.containsKey('protein_target_g')) {
      context.handle(
        _proteinTargetGMeta,
        proteinTargetG.isAcceptableOrUnknown(
          data['protein_target_g']!,
          _proteinTargetGMeta,
        ),
      );
    }
    if (data.containsKey('preferred_meal_types')) {
      context.handle(
        _preferredMealTypesMeta,
        preferredMealTypes.isAcceptableOrUnknown(
          data['preferred_meal_types']!,
          _preferredMealTypesMeta,
        ),
      );
    }
    if (data.containsKey('dietary_preferences')) {
      context.handle(
        _dietaryPreferencesMeta,
        dietaryPreferences.isAcceptableOrUnknown(
          data['dietary_preferences']!,
          _dietaryPreferencesMeta,
        ),
      );
    }
    if (data.containsKey('dislikes')) {
      context.handle(
        _dislikesMeta,
        dislikes.isAcceptableOrUnknown(data['dislikes']!, _dislikesMeta),
      );
    }
    if (data.containsKey('allergies')) {
      context.handle(
        _allergiesMeta,
        allergies.isAcceptableOrUnknown(data['allergies']!, _allergiesMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  FoodProfileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FoodProfileRow(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      caloriesPerMealTarget: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}calories_per_meal_target'],
      ),
      proteinTargetG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_target_g'],
      ),
      preferredMealTypes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preferred_meal_types'],
      )!,
      dietaryPreferences: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dietary_preferences'],
      )!,
      dislikes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dislikes'],
      )!,
      allergies: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}allergies'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FoodProfilesTable createAlias(String alias) {
    return $FoodProfilesTable(attachedDatabase, alias);
  }
}

class FoodProfileRow extends DataClass implements Insertable<FoodProfileRow> {
  final String userId;
  final double? caloriesPerMealTarget;
  final double? proteinTargetG;
  final String preferredMealTypes;
  final String dietaryPreferences;
  final String dislikes;
  final String allergies;
  final DateTime updatedAt;
  const FoodProfileRow({
    required this.userId,
    this.caloriesPerMealTarget,
    this.proteinTargetG,
    required this.preferredMealTypes,
    required this.dietaryPreferences,
    required this.dislikes,
    required this.allergies,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || caloriesPerMealTarget != null) {
      map['calories_per_meal_target'] = Variable<double>(caloriesPerMealTarget);
    }
    if (!nullToAbsent || proteinTargetG != null) {
      map['protein_target_g'] = Variable<double>(proteinTargetG);
    }
    map['preferred_meal_types'] = Variable<String>(preferredMealTypes);
    map['dietary_preferences'] = Variable<String>(dietaryPreferences);
    map['dislikes'] = Variable<String>(dislikes);
    map['allergies'] = Variable<String>(allergies);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  FoodProfilesCompanion toCompanion(bool nullToAbsent) {
    return FoodProfilesCompanion(
      userId: Value(userId),
      caloriesPerMealTarget: caloriesPerMealTarget == null && nullToAbsent
          ? const Value.absent()
          : Value(caloriesPerMealTarget),
      proteinTargetG: proteinTargetG == null && nullToAbsent
          ? const Value.absent()
          : Value(proteinTargetG),
      preferredMealTypes: Value(preferredMealTypes),
      dietaryPreferences: Value(dietaryPreferences),
      dislikes: Value(dislikes),
      allergies: Value(allergies),
      updatedAt: Value(updatedAt),
    );
  }

  factory FoodProfileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FoodProfileRow(
      userId: serializer.fromJson<String>(json['userId']),
      caloriesPerMealTarget: serializer.fromJson<double?>(
        json['caloriesPerMealTarget'],
      ),
      proteinTargetG: serializer.fromJson<double?>(json['proteinTargetG']),
      preferredMealTypes: serializer.fromJson<String>(
        json['preferredMealTypes'],
      ),
      dietaryPreferences: serializer.fromJson<String>(
        json['dietaryPreferences'],
      ),
      dislikes: serializer.fromJson<String>(json['dislikes']),
      allergies: serializer.fromJson<String>(json['allergies']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'caloriesPerMealTarget': serializer.toJson<double?>(
        caloriesPerMealTarget,
      ),
      'proteinTargetG': serializer.toJson<double?>(proteinTargetG),
      'preferredMealTypes': serializer.toJson<String>(preferredMealTypes),
      'dietaryPreferences': serializer.toJson<String>(dietaryPreferences),
      'dislikes': serializer.toJson<String>(dislikes),
      'allergies': serializer.toJson<String>(allergies),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  FoodProfileRow copyWith({
    String? userId,
    Value<double?> caloriesPerMealTarget = const Value.absent(),
    Value<double?> proteinTargetG = const Value.absent(),
    String? preferredMealTypes,
    String? dietaryPreferences,
    String? dislikes,
    String? allergies,
    DateTime? updatedAt,
  }) => FoodProfileRow(
    userId: userId ?? this.userId,
    caloriesPerMealTarget: caloriesPerMealTarget.present
        ? caloriesPerMealTarget.value
        : this.caloriesPerMealTarget,
    proteinTargetG: proteinTargetG.present
        ? proteinTargetG.value
        : this.proteinTargetG,
    preferredMealTypes: preferredMealTypes ?? this.preferredMealTypes,
    dietaryPreferences: dietaryPreferences ?? this.dietaryPreferences,
    dislikes: dislikes ?? this.dislikes,
    allergies: allergies ?? this.allergies,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  FoodProfileRow copyWithCompanion(FoodProfilesCompanion data) {
    return FoodProfileRow(
      userId: data.userId.present ? data.userId.value : this.userId,
      caloriesPerMealTarget: data.caloriesPerMealTarget.present
          ? data.caloriesPerMealTarget.value
          : this.caloriesPerMealTarget,
      proteinTargetG: data.proteinTargetG.present
          ? data.proteinTargetG.value
          : this.proteinTargetG,
      preferredMealTypes: data.preferredMealTypes.present
          ? data.preferredMealTypes.value
          : this.preferredMealTypes,
      dietaryPreferences: data.dietaryPreferences.present
          ? data.dietaryPreferences.value
          : this.dietaryPreferences,
      dislikes: data.dislikes.present ? data.dislikes.value : this.dislikes,
      allergies: data.allergies.present ? data.allergies.value : this.allergies,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FoodProfileRow(')
          ..write('userId: $userId, ')
          ..write('caloriesPerMealTarget: $caloriesPerMealTarget, ')
          ..write('proteinTargetG: $proteinTargetG, ')
          ..write('preferredMealTypes: $preferredMealTypes, ')
          ..write('dietaryPreferences: $dietaryPreferences, ')
          ..write('dislikes: $dislikes, ')
          ..write('allergies: $allergies, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    caloriesPerMealTarget,
    proteinTargetG,
    preferredMealTypes,
    dietaryPreferences,
    dislikes,
    allergies,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoodProfileRow &&
          other.userId == this.userId &&
          other.caloriesPerMealTarget == this.caloriesPerMealTarget &&
          other.proteinTargetG == this.proteinTargetG &&
          other.preferredMealTypes == this.preferredMealTypes &&
          other.dietaryPreferences == this.dietaryPreferences &&
          other.dislikes == this.dislikes &&
          other.allergies == this.allergies &&
          other.updatedAt == this.updatedAt);
}

class FoodProfilesCompanion extends UpdateCompanion<FoodProfileRow> {
  final Value<String> userId;
  final Value<double?> caloriesPerMealTarget;
  final Value<double?> proteinTargetG;
  final Value<String> preferredMealTypes;
  final Value<String> dietaryPreferences;
  final Value<String> dislikes;
  final Value<String> allergies;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const FoodProfilesCompanion({
    this.userId = const Value.absent(),
    this.caloriesPerMealTarget = const Value.absent(),
    this.proteinTargetG = const Value.absent(),
    this.preferredMealTypes = const Value.absent(),
    this.dietaryPreferences = const Value.absent(),
    this.dislikes = const Value.absent(),
    this.allergies = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoodProfilesCompanion.insert({
    required String userId,
    this.caloriesPerMealTarget = const Value.absent(),
    this.proteinTargetG = const Value.absent(),
    this.preferredMealTypes = const Value.absent(),
    this.dietaryPreferences = const Value.absent(),
    this.dislikes = const Value.absent(),
    this.allergies = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       updatedAt = Value(updatedAt);
  static Insertable<FoodProfileRow> custom({
    Expression<String>? userId,
    Expression<double>? caloriesPerMealTarget,
    Expression<double>? proteinTargetG,
    Expression<String>? preferredMealTypes,
    Expression<String>? dietaryPreferences,
    Expression<String>? dislikes,
    Expression<String>? allergies,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (caloriesPerMealTarget != null)
        'calories_per_meal_target': caloriesPerMealTarget,
      if (proteinTargetG != null) 'protein_target_g': proteinTargetG,
      if (preferredMealTypes != null)
        'preferred_meal_types': preferredMealTypes,
      if (dietaryPreferences != null) 'dietary_preferences': dietaryPreferences,
      if (dislikes != null) 'dislikes': dislikes,
      if (allergies != null) 'allergies': allergies,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoodProfilesCompanion copyWith({
    Value<String>? userId,
    Value<double?>? caloriesPerMealTarget,
    Value<double?>? proteinTargetG,
    Value<String>? preferredMealTypes,
    Value<String>? dietaryPreferences,
    Value<String>? dislikes,
    Value<String>? allergies,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return FoodProfilesCompanion(
      userId: userId ?? this.userId,
      caloriesPerMealTarget:
          caloriesPerMealTarget ?? this.caloriesPerMealTarget,
      proteinTargetG: proteinTargetG ?? this.proteinTargetG,
      preferredMealTypes: preferredMealTypes ?? this.preferredMealTypes,
      dietaryPreferences: dietaryPreferences ?? this.dietaryPreferences,
      dislikes: dislikes ?? this.dislikes,
      allergies: allergies ?? this.allergies,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (caloriesPerMealTarget.present) {
      map['calories_per_meal_target'] = Variable<double>(
        caloriesPerMealTarget.value,
      );
    }
    if (proteinTargetG.present) {
      map['protein_target_g'] = Variable<double>(proteinTargetG.value);
    }
    if (preferredMealTypes.present) {
      map['preferred_meal_types'] = Variable<String>(preferredMealTypes.value);
    }
    if (dietaryPreferences.present) {
      map['dietary_preferences'] = Variable<String>(dietaryPreferences.value);
    }
    if (dislikes.present) {
      map['dislikes'] = Variable<String>(dislikes.value);
    }
    if (allergies.present) {
      map['allergies'] = Variable<String>(allergies.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoodProfilesCompanion(')
          ..write('userId: $userId, ')
          ..write('caloriesPerMealTarget: $caloriesPerMealTarget, ')
          ..write('proteinTargetG: $proteinTargetG, ')
          ..write('preferredMealTypes: $preferredMealTypes, ')
          ..write('dietaryPreferences: $dietaryPreferences, ')
          ..write('dislikes: $dislikes, ')
          ..write('allergies: $allergies, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PreferencesTable extends Preferences
    with TableInfo<$PreferencesTable, PreferenceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PreferencesTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<PreferenceRow> instance, {
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
  PreferenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PreferenceRow(
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
  $PreferencesTable createAlias(String alias) {
    return $PreferencesTable(attachedDatabase, alias);
  }
}

class PreferenceRow extends DataClass implements Insertable<PreferenceRow> {
  final String key;
  final String value;
  const PreferenceRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  PreferencesCompanion toCompanion(bool nullToAbsent) {
    return PreferencesCompanion(key: Value(key), value: Value(value));
  }

  factory PreferenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PreferenceRow(
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

  PreferenceRow copyWith({String? key, String? value}) =>
      PreferenceRow(key: key ?? this.key, value: value ?? this.value);
  PreferenceRow copyWithCompanion(PreferencesCompanion data) {
    return PreferenceRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PreferenceRow(')
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
      (other is PreferenceRow &&
          other.key == this.key &&
          other.value == this.value);
}

class PreferencesCompanion extends UpdateCompanion<PreferenceRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const PreferencesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PreferencesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<PreferenceRow> custom({
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

  PreferencesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return PreferencesCompanion(
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
    return (StringBuffer('PreferencesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CookSessionsTable extends CookSessions
    with TableInfo<$CookSessionsTable, CookSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CookSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recipeIdMeta = const VerificationMeta(
    'recipeId',
  );
  @override
  late final GeneratedColumn<String> recipeId = GeneratedColumn<String>(
    'recipe_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentStepMeta = const VerificationMeta(
    'currentStep',
  );
  @override
  late final GeneratedColumn<int> currentStep = GeneratedColumn<int>(
    'current_step',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _checkedStepIdsMeta = const VerificationMeta(
    'checkedStepIds',
  );
  @override
  late final GeneratedColumn<String> checkedStepIds = GeneratedColumn<String>(
    'checked_step_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
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
  @override
  List<GeneratedColumn> get $columns => [
    recipeId,
    currentStep,
    checkedStepIds,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cook_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CookSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('recipe_id')) {
      context.handle(
        _recipeIdMeta,
        recipeId.isAcceptableOrUnknown(data['recipe_id']!, _recipeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recipeIdMeta);
    }
    if (data.containsKey('current_step')) {
      context.handle(
        _currentStepMeta,
        currentStep.isAcceptableOrUnknown(
          data['current_step']!,
          _currentStepMeta,
        ),
      );
    }
    if (data.containsKey('checked_step_ids')) {
      context.handle(
        _checkedStepIdsMeta,
        checkedStepIds.isAcceptableOrUnknown(
          data['checked_step_ids']!,
          _checkedStepIdsMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recipeId};
  @override
  CookSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CookSessionRow(
      recipeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_id'],
      )!,
      currentStep: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_step'],
      )!,
      checkedStepIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checked_step_ids'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CookSessionsTable createAlias(String alias) {
    return $CookSessionsTable(attachedDatabase, alias);
  }
}

class CookSessionRow extends DataClass implements Insertable<CookSessionRow> {
  final String recipeId;
  final int currentStep;

  /// The ids of the steps ticked off, as a JSON array.
  final String checkedStepIds;
  final DateTime updatedAt;
  const CookSessionRow({
    required this.recipeId,
    required this.currentStep,
    required this.checkedStepIds,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['recipe_id'] = Variable<String>(recipeId);
    map['current_step'] = Variable<int>(currentStep);
    map['checked_step_ids'] = Variable<String>(checkedStepIds);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CookSessionsCompanion toCompanion(bool nullToAbsent) {
    return CookSessionsCompanion(
      recipeId: Value(recipeId),
      currentStep: Value(currentStep),
      checkedStepIds: Value(checkedStepIds),
      updatedAt: Value(updatedAt),
    );
  }

  factory CookSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CookSessionRow(
      recipeId: serializer.fromJson<String>(json['recipeId']),
      currentStep: serializer.fromJson<int>(json['currentStep']),
      checkedStepIds: serializer.fromJson<String>(json['checkedStepIds']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recipeId': serializer.toJson<String>(recipeId),
      'currentStep': serializer.toJson<int>(currentStep),
      'checkedStepIds': serializer.toJson<String>(checkedStepIds),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CookSessionRow copyWith({
    String? recipeId,
    int? currentStep,
    String? checkedStepIds,
    DateTime? updatedAt,
  }) => CookSessionRow(
    recipeId: recipeId ?? this.recipeId,
    currentStep: currentStep ?? this.currentStep,
    checkedStepIds: checkedStepIds ?? this.checkedStepIds,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CookSessionRow copyWithCompanion(CookSessionsCompanion data) {
    return CookSessionRow(
      recipeId: data.recipeId.present ? data.recipeId.value : this.recipeId,
      currentStep: data.currentStep.present
          ? data.currentStep.value
          : this.currentStep,
      checkedStepIds: data.checkedStepIds.present
          ? data.checkedStepIds.value
          : this.checkedStepIds,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CookSessionRow(')
          ..write('recipeId: $recipeId, ')
          ..write('currentStep: $currentStep, ')
          ..write('checkedStepIds: $checkedStepIds, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(recipeId, currentStep, checkedStepIds, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CookSessionRow &&
          other.recipeId == this.recipeId &&
          other.currentStep == this.currentStep &&
          other.checkedStepIds == this.checkedStepIds &&
          other.updatedAt == this.updatedAt);
}

class CookSessionsCompanion extends UpdateCompanion<CookSessionRow> {
  final Value<String> recipeId;
  final Value<int> currentStep;
  final Value<String> checkedStepIds;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CookSessionsCompanion({
    this.recipeId = const Value.absent(),
    this.currentStep = const Value.absent(),
    this.checkedStepIds = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CookSessionsCompanion.insert({
    required String recipeId,
    this.currentStep = const Value.absent(),
    this.checkedStepIds = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : recipeId = Value(recipeId),
       updatedAt = Value(updatedAt);
  static Insertable<CookSessionRow> custom({
    Expression<String>? recipeId,
    Expression<int>? currentStep,
    Expression<String>? checkedStepIds,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recipeId != null) 'recipe_id': recipeId,
      if (currentStep != null) 'current_step': currentStep,
      if (checkedStepIds != null) 'checked_step_ids': checkedStepIds,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CookSessionsCompanion copyWith({
    Value<String>? recipeId,
    Value<int>? currentStep,
    Value<String>? checkedStepIds,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CookSessionsCompanion(
      recipeId: recipeId ?? this.recipeId,
      currentStep: currentStep ?? this.currentStep,
      checkedStepIds: checkedStepIds ?? this.checkedStepIds,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recipeId.present) {
      map['recipe_id'] = Variable<String>(recipeId.value);
    }
    if (currentStep.present) {
      map['current_step'] = Variable<int>(currentStep.value);
    }
    if (checkedStepIds.present) {
      map['checked_step_ids'] = Variable<String>(checkedStepIds.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CookSessionsCompanion(')
          ..write('recipeId: $recipeId, ')
          ..write('currentStep: $currentStep, ')
          ..write('checkedStepIds: $checkedStepIds, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecipePhotosTable extends RecipePhotos
    with TableInfo<$RecipePhotosTable, RecipePhotoRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecipePhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recipeIdMeta = const VerificationMeta(
    'recipeId',
  );
  @override
  late final GeneratedColumn<String> recipeId = GeneratedColumn<String>(
    'recipe_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES recipes (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remotePathMeta = const VerificationMeta(
    'remotePath',
  );
  @override
  late final GeneratedColumn<String> remotePath = GeneratedColumn<String>(
    'remote_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncAttemptsMeta = const VerificationMeta(
    'syncAttempts',
  );
  @override
  late final GeneratedColumn<int> syncAttempts = GeneratedColumn<int>(
    'sync_attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(0),
  );
  static const VerificationMeta _syncErrorMeta = const VerificationMeta(
    'syncError',
  );
  @override
  late final GeneratedColumn<String> syncError = GeneratedColumn<String>(
    'sync_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptedPathMeta = const VerificationMeta(
    'attemptedPath',
  );
  @override
  late final GeneratedColumn<String> attemptedPath = GeneratedColumn<String>(
    'attempted_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  @override
  List<GeneratedColumn> get $columns => [
    recipeId,
    fileName,
    remotePath,
    syncAttempts,
    syncError,
    attemptedPath,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recipe_photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecipePhotoRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('recipe_id')) {
      context.handle(
        _recipeIdMeta,
        recipeId.isAcceptableOrUnknown(data['recipe_id']!, _recipeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recipeIdMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    }
    if (data.containsKey('remote_path')) {
      context.handle(
        _remotePathMeta,
        remotePath.isAcceptableOrUnknown(data['remote_path']!, _remotePathMeta),
      );
    }
    if (data.containsKey('sync_attempts')) {
      context.handle(
        _syncAttemptsMeta,
        syncAttempts.isAcceptableOrUnknown(
          data['sync_attempts']!,
          _syncAttemptsMeta,
        ),
      );
    }
    if (data.containsKey('sync_error')) {
      context.handle(
        _syncErrorMeta,
        syncError.isAcceptableOrUnknown(data['sync_error']!, _syncErrorMeta),
      );
    }
    if (data.containsKey('attempted_path')) {
      context.handle(
        _attemptedPathMeta,
        attemptedPath.isAcceptableOrUnknown(
          data['attempted_path']!,
          _attemptedPathMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recipeId};
  @override
  RecipePhotoRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecipePhotoRow(
      recipeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_id'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      ),
      remotePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_path'],
      ),
      syncAttempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_attempts'],
      )!,
      syncError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_error'],
      ),
      attemptedPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attempted_path'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RecipePhotosTable createAlias(String alias) {
    return $RecipePhotosTable(attachedDatabase, alias);
  }
}

class RecipePhotoRow extends DataClass implements Insertable<RecipePhotoRow> {
  final String recipeId;

  /// Null when this device knows about a photo it does not have.
  final String? fileName;

  /// The object path [fileName] is a copy of, or null when it was never
  /// uploaded. Compared against the recipe's `photoUrl` to spot a stale copy —
  /// a string compare, and reliable only because objects are immutable.
  final String? remotePath;

  /// Stops a permanently failing upload from retrying for ever.
  ///
  /// Load-bearing: writing this wakes the sync listener, which retries, which
  /// writes it again. The loop terminates *only* because the candidate query
  /// filters on this being under the limit.
  final int syncAttempts;
  final String? syncError;

  /// The object path the last failed download was for.
  ///
  /// Separate from [remotePath], which says what [fileName] is a copy of. A
  /// stale row keeps its old file while a replacement fails to arrive, so the
  /// two paths genuinely differ — and "has the partner replaced it *again*
  /// since we gave up" can only be answered by remembering what was tried.
  final String? attemptedPath;
  final DateTime updatedAt;
  const RecipePhotoRow({
    required this.recipeId,
    this.fileName,
    this.remotePath,
    required this.syncAttempts,
    this.syncError,
    this.attemptedPath,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['recipe_id'] = Variable<String>(recipeId);
    if (!nullToAbsent || fileName != null) {
      map['file_name'] = Variable<String>(fileName);
    }
    if (!nullToAbsent || remotePath != null) {
      map['remote_path'] = Variable<String>(remotePath);
    }
    map['sync_attempts'] = Variable<int>(syncAttempts);
    if (!nullToAbsent || syncError != null) {
      map['sync_error'] = Variable<String>(syncError);
    }
    if (!nullToAbsent || attemptedPath != null) {
      map['attempted_path'] = Variable<String>(attemptedPath);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RecipePhotosCompanion toCompanion(bool nullToAbsent) {
    return RecipePhotosCompanion(
      recipeId: Value(recipeId),
      fileName: fileName == null && nullToAbsent
          ? const Value.absent()
          : Value(fileName),
      remotePath: remotePath == null && nullToAbsent
          ? const Value.absent()
          : Value(remotePath),
      syncAttempts: Value(syncAttempts),
      syncError: syncError == null && nullToAbsent
          ? const Value.absent()
          : Value(syncError),
      attemptedPath: attemptedPath == null && nullToAbsent
          ? const Value.absent()
          : Value(attemptedPath),
      updatedAt: Value(updatedAt),
    );
  }

  factory RecipePhotoRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecipePhotoRow(
      recipeId: serializer.fromJson<String>(json['recipeId']),
      fileName: serializer.fromJson<String?>(json['fileName']),
      remotePath: serializer.fromJson<String?>(json['remotePath']),
      syncAttempts: serializer.fromJson<int>(json['syncAttempts']),
      syncError: serializer.fromJson<String?>(json['syncError']),
      attemptedPath: serializer.fromJson<String?>(json['attemptedPath']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recipeId': serializer.toJson<String>(recipeId),
      'fileName': serializer.toJson<String?>(fileName),
      'remotePath': serializer.toJson<String?>(remotePath),
      'syncAttempts': serializer.toJson<int>(syncAttempts),
      'syncError': serializer.toJson<String?>(syncError),
      'attemptedPath': serializer.toJson<String?>(attemptedPath),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RecipePhotoRow copyWith({
    String? recipeId,
    Value<String?> fileName = const Value.absent(),
    Value<String?> remotePath = const Value.absent(),
    int? syncAttempts,
    Value<String?> syncError = const Value.absent(),
    Value<String?> attemptedPath = const Value.absent(),
    DateTime? updatedAt,
  }) => RecipePhotoRow(
    recipeId: recipeId ?? this.recipeId,
    fileName: fileName.present ? fileName.value : this.fileName,
    remotePath: remotePath.present ? remotePath.value : this.remotePath,
    syncAttempts: syncAttempts ?? this.syncAttempts,
    syncError: syncError.present ? syncError.value : this.syncError,
    attemptedPath: attemptedPath.present
        ? attemptedPath.value
        : this.attemptedPath,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RecipePhotoRow copyWithCompanion(RecipePhotosCompanion data) {
    return RecipePhotoRow(
      recipeId: data.recipeId.present ? data.recipeId.value : this.recipeId,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      remotePath: data.remotePath.present
          ? data.remotePath.value
          : this.remotePath,
      syncAttempts: data.syncAttempts.present
          ? data.syncAttempts.value
          : this.syncAttempts,
      syncError: data.syncError.present ? data.syncError.value : this.syncError,
      attemptedPath: data.attemptedPath.present
          ? data.attemptedPath.value
          : this.attemptedPath,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecipePhotoRow(')
          ..write('recipeId: $recipeId, ')
          ..write('fileName: $fileName, ')
          ..write('remotePath: $remotePath, ')
          ..write('syncAttempts: $syncAttempts, ')
          ..write('syncError: $syncError, ')
          ..write('attemptedPath: $attemptedPath, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    recipeId,
    fileName,
    remotePath,
    syncAttempts,
    syncError,
    attemptedPath,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecipePhotoRow &&
          other.recipeId == this.recipeId &&
          other.fileName == this.fileName &&
          other.remotePath == this.remotePath &&
          other.syncAttempts == this.syncAttempts &&
          other.syncError == this.syncError &&
          other.attemptedPath == this.attemptedPath &&
          other.updatedAt == this.updatedAt);
}

class RecipePhotosCompanion extends UpdateCompanion<RecipePhotoRow> {
  final Value<String> recipeId;
  final Value<String?> fileName;
  final Value<String?> remotePath;
  final Value<int> syncAttempts;
  final Value<String?> syncError;
  final Value<String?> attemptedPath;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const RecipePhotosCompanion({
    this.recipeId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.remotePath = const Value.absent(),
    this.syncAttempts = const Value.absent(),
    this.syncError = const Value.absent(),
    this.attemptedPath = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecipePhotosCompanion.insert({
    required String recipeId,
    this.fileName = const Value.absent(),
    this.remotePath = const Value.absent(),
    this.syncAttempts = const Value.absent(),
    this.syncError = const Value.absent(),
    this.attemptedPath = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : recipeId = Value(recipeId),
       updatedAt = Value(updatedAt);
  static Insertable<RecipePhotoRow> custom({
    Expression<String>? recipeId,
    Expression<String>? fileName,
    Expression<String>? remotePath,
    Expression<int>? syncAttempts,
    Expression<String>? syncError,
    Expression<String>? attemptedPath,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recipeId != null) 'recipe_id': recipeId,
      if (fileName != null) 'file_name': fileName,
      if (remotePath != null) 'remote_path': remotePath,
      if (syncAttempts != null) 'sync_attempts': syncAttempts,
      if (syncError != null) 'sync_error': syncError,
      if (attemptedPath != null) 'attempted_path': attemptedPath,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecipePhotosCompanion copyWith({
    Value<String>? recipeId,
    Value<String?>? fileName,
    Value<String?>? remotePath,
    Value<int>? syncAttempts,
    Value<String?>? syncError,
    Value<String?>? attemptedPath,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return RecipePhotosCompanion(
      recipeId: recipeId ?? this.recipeId,
      fileName: fileName ?? this.fileName,
      remotePath: remotePath ?? this.remotePath,
      syncAttempts: syncAttempts ?? this.syncAttempts,
      syncError: syncError ?? this.syncError,
      attemptedPath: attemptedPath ?? this.attemptedPath,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recipeId.present) {
      map['recipe_id'] = Variable<String>(recipeId.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (remotePath.present) {
      map['remote_path'] = Variable<String>(remotePath.value);
    }
    if (syncAttempts.present) {
      map['sync_attempts'] = Variable<int>(syncAttempts.value);
    }
    if (syncError.present) {
      map['sync_error'] = Variable<String>(syncError.value);
    }
    if (attemptedPath.present) {
      map['attempted_path'] = Variable<String>(attemptedPath.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecipePhotosCompanion(')
          ..write('recipeId: $recipeId, ')
          ..write('fileName: $fileName, ')
          ..write('remotePath: $remotePath, ')
          ..write('syncAttempts: $syncAttempts, ')
          ..write('syncError: $syncError, ')
          ..write('attemptedPath: $attemptedPath, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlanTemplatesTable extends PlanTemplates
    with TableInfo<$PlanTemplatesTable, PlanTemplateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanTemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entriesMeta = const VerificationMeta(
    'entries',
  );
  @override
  late final GeneratedColumn<String> entries = GeneratedColumn<String>(
    'entries',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant<String>('[]'),
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
  @override
  List<GeneratedColumn> get $columns => [id, userId, name, entries, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plan_templates';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlanTemplateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('entries')) {
      context.handle(
        _entriesMeta,
        entries.isAcceptableOrUnknown(data['entries']!, _entriesMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlanTemplateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanTemplateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      entries: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entries'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlanTemplatesTable createAlias(String alias) {
    return $PlanTemplatesTable(attachedDatabase, alias);
  }
}

class PlanTemplateRow extends DataClass implements Insertable<PlanTemplateRow> {
  final String id;
  final String userId;
  final String name;
  final String entries;
  final DateTime updatedAt;
  const PlanTemplateRow({
    required this.id,
    required this.userId,
    required this.name,
    required this.entries,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['entries'] = Variable<String>(entries);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PlanTemplatesCompanion toCompanion(bool nullToAbsent) {
    return PlanTemplatesCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      entries: Value(entries),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlanTemplateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanTemplateRow(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      entries: serializer.fromJson<String>(json['entries']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'entries': serializer.toJson<String>(entries),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PlanTemplateRow copyWith({
    String? id,
    String? userId,
    String? name,
    String? entries,
    DateTime? updatedAt,
  }) => PlanTemplateRow(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    entries: entries ?? this.entries,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlanTemplateRow copyWithCompanion(PlanTemplatesCompanion data) {
    return PlanTemplateRow(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      entries: data.entries.present ? data.entries.value : this.entries,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanTemplateRow(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('entries: $entries, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, userId, name, entries, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanTemplateRow &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.entries == this.entries &&
          other.updatedAt == this.updatedAt);
}

class PlanTemplatesCompanion extends UpdateCompanion<PlanTemplateRow> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> name;
  final Value<String> entries;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PlanTemplatesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.entries = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlanTemplatesCompanion.insert({
    required String id,
    required String userId,
    required String name,
    this.entries = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<PlanTemplateRow> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<String>? entries,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (entries != null) 'entries': entries,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlanTemplatesCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? name,
    Value<String>? entries,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PlanTemplatesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      entries: entries ?? this.entries,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (entries.present) {
      map['entries'] = Variable<String>(entries.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanTemplatesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('entries: $entries, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingWritesTable extends PendingWrites
    with TableInfo<$PendingWritesTable, PendingWriteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingWritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _entityTableMeta = const VerificationMeta(
    'entityTable',
  );
  @override
  late final GeneratedColumn<String> entityTable = GeneratedColumn<String>(
    'entity_table',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _queuedAtMeta = const VerificationMeta(
    'queuedAt',
  );
  @override
  late final GeneratedColumn<DateTime> queuedAt = GeneratedColumn<DateTime>(
    'queued_at',
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
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sequence,
    entityTable,
    entityId,
    operation,
    payload,
    queuedAt,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_writes';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingWriteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    }
    if (data.containsKey('entity_table')) {
      context.handle(
        _entityTableMeta,
        entityTable.isAcceptableOrUnknown(
          data['entity_table']!,
          _entityTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_entityTableMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('queued_at')) {
      context.handle(
        _queuedAtMeta,
        queuedAt.isAcceptableOrUnknown(data['queued_at']!, _queuedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_queuedAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sequence};
  @override
  PendingWriteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingWriteRow(
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      entityTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_table'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      queuedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}queued_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $PendingWritesTable createAlias(String alias) {
    return $PendingWritesTable(attachedDatabase, alias);
  }
}

class PendingWriteRow extends DataClass implements Insertable<PendingWriteRow> {
  final int sequence;

  /// The Supabase table this write targets.
  final String entityTable;
  final String entityId;

  /// `upsert` or `delete`. Recipes and foods are soft-deleted, so a hard
  /// delete only ever reaches rows the spec allows to disappear.
  final String operation;

  /// The full row as JSON. Whole-record last-write-wins means the payload is
  /// the entire record, never a patch (spec §7.1).
  final String payload;
  final DateTime queuedAt;
  final int attempts;
  final String? lastError;
  const PendingWriteRow({
    required this.sequence,
    required this.entityTable,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.queuedAt,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sequence'] = Variable<int>(sequence);
    map['entity_table'] = Variable<String>(entityTable);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    map['payload'] = Variable<String>(payload);
    map['queued_at'] = Variable<DateTime>(queuedAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  PendingWritesCompanion toCompanion(bool nullToAbsent) {
    return PendingWritesCompanion(
      sequence: Value(sequence),
      entityTable: Value(entityTable),
      entityId: Value(entityId),
      operation: Value(operation),
      payload: Value(payload),
      queuedAt: Value(queuedAt),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory PendingWriteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingWriteRow(
      sequence: serializer.fromJson<int>(json['sequence']),
      entityTable: serializer.fromJson<String>(json['entityTable']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String>(json['payload']),
      queuedAt: serializer.fromJson<DateTime>(json['queuedAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sequence': serializer.toJson<int>(sequence),
      'entityTable': serializer.toJson<String>(entityTable),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String>(payload),
      'queuedAt': serializer.toJson<DateTime>(queuedAt),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  PendingWriteRow copyWith({
    int? sequence,
    String? entityTable,
    String? entityId,
    String? operation,
    String? payload,
    DateTime? queuedAt,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => PendingWriteRow(
    sequence: sequence ?? this.sequence,
    entityTable: entityTable ?? this.entityTable,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    payload: payload ?? this.payload,
    queuedAt: queuedAt ?? this.queuedAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  PendingWriteRow copyWithCompanion(PendingWritesCompanion data) {
    return PendingWriteRow(
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      entityTable: data.entityTable.present
          ? data.entityTable.value
          : this.entityTable,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      queuedAt: data.queuedAt.present ? data.queuedAt.value : this.queuedAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingWriteRow(')
          ..write('sequence: $sequence, ')
          ..write('entityTable: $entityTable, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('queuedAt: $queuedAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sequence,
    entityTable,
    entityId,
    operation,
    payload,
    queuedAt,
    attempts,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingWriteRow &&
          other.sequence == this.sequence &&
          other.entityTable == this.entityTable &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.queuedAt == this.queuedAt &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class PendingWritesCompanion extends UpdateCompanion<PendingWriteRow> {
  final Value<int> sequence;
  final Value<String> entityTable;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String> payload;
  final Value<DateTime> queuedAt;
  final Value<int> attempts;
  final Value<String?> lastError;
  const PendingWritesCompanion({
    this.sequence = const Value.absent(),
    this.entityTable = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.queuedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  PendingWritesCompanion.insert({
    this.sequence = const Value.absent(),
    required String entityTable,
    required String entityId,
    required String operation,
    required String payload,
    required DateTime queuedAt,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  }) : entityTable = Value(entityTable),
       entityId = Value(entityId),
       operation = Value(operation),
       payload = Value(payload),
       queuedAt = Value(queuedAt);
  static Insertable<PendingWriteRow> custom({
    Expression<int>? sequence,
    Expression<String>? entityTable,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<DateTime>? queuedAt,
    Expression<int>? attempts,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (sequence != null) 'sequence': sequence,
      if (entityTable != null) 'entity_table': entityTable,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (queuedAt != null) 'queued_at': queuedAt,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
    });
  }

  PendingWritesCompanion copyWith({
    Value<int>? sequence,
    Value<String>? entityTable,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String>? payload,
    Value<DateTime>? queuedAt,
    Value<int>? attempts,
    Value<String?>? lastError,
  }) {
    return PendingWritesCompanion(
      sequence: sequence ?? this.sequence,
      entityTable: entityTable ?? this.entityTable,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      queuedAt: queuedAt ?? this.queuedAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (entityTable.present) {
      map['entity_table'] = Variable<String>(entityTable.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (queuedAt.present) {
      map['queued_at'] = Variable<DateTime>(queuedAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingWritesCompanion(')
          ..write('sequence: $sequence, ')
          ..write('entityTable: $entityTable, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('queuedAt: $queuedAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $ShoppingListsTable extends ShoppingLists
    with TableInfo<$ShoppingListsTable, ShoppingListRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShoppingListsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromDateMeta = const VerificationMeta(
    'fromDate',
  );
  @override
  late final GeneratedColumn<DateTime> fromDate = GeneratedColumn<DateTime>(
    'from_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toDateMeta = const VerificationMeta('toDate');
  @override
  late final GeneratedColumn<DateTime> toDate = GeneratedColumn<DateTime>(
    'to_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('draft'),
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    fromDate,
    toDate,
    status,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shopping_lists';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShoppingListRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('from_date')) {
      context.handle(
        _fromDateMeta,
        fromDate.isAcceptableOrUnknown(data['from_date']!, _fromDateMeta),
      );
    } else if (isInserting) {
      context.missing(_fromDateMeta);
    }
    if (data.containsKey('to_date')) {
      context.handle(
        _toDateMeta,
        toDate.isAcceptableOrUnknown(data['to_date']!, _toDateMeta),
      );
    } else if (isInserting) {
      context.missing(_toDateMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShoppingListRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShoppingListRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      fromDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}from_date'],
      )!,
      toDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}to_date'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ShoppingListsTable createAlias(String alias) {
    return $ShoppingListsTable(attachedDatabase, alias);
  }
}

class ShoppingListRow extends DataClass implements Insertable<ShoppingListRow> {
  final String id;
  final String householdId;
  final DateTime fromDate;
  final DateTime toDate;
  final String status;
  final DateTime updatedAt;
  const ShoppingListRow({
    required this.id,
    required this.householdId,
    required this.fromDate,
    required this.toDate,
    required this.status,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['from_date'] = Variable<DateTime>(fromDate);
    map['to_date'] = Variable<DateTime>(toDate);
    map['status'] = Variable<String>(status);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ShoppingListsCompanion toCompanion(bool nullToAbsent) {
    return ShoppingListsCompanion(
      id: Value(id),
      householdId: Value(householdId),
      fromDate: Value(fromDate),
      toDate: Value(toDate),
      status: Value(status),
      updatedAt: Value(updatedAt),
    );
  }

  factory ShoppingListRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShoppingListRow(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      fromDate: serializer.fromJson<DateTime>(json['fromDate']),
      toDate: serializer.fromJson<DateTime>(json['toDate']),
      status: serializer.fromJson<String>(json['status']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'fromDate': serializer.toJson<DateTime>(fromDate),
      'toDate': serializer.toJson<DateTime>(toDate),
      'status': serializer.toJson<String>(status),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ShoppingListRow copyWith({
    String? id,
    String? householdId,
    DateTime? fromDate,
    DateTime? toDate,
    String? status,
    DateTime? updatedAt,
  }) => ShoppingListRow(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    fromDate: fromDate ?? this.fromDate,
    toDate: toDate ?? this.toDate,
    status: status ?? this.status,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ShoppingListRow copyWithCompanion(ShoppingListsCompanion data) {
    return ShoppingListRow(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      fromDate: data.fromDate.present ? data.fromDate.value : this.fromDate,
      toDate: data.toDate.present ? data.toDate.value : this.toDate,
      status: data.status.present ? data.status.value : this.status,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingListRow(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('fromDate: $fromDate, ')
          ..write('toDate: $toDate, ')
          ..write('status: $status, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, householdId, fromDate, toDate, status, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShoppingListRow &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.fromDate == this.fromDate &&
          other.toDate == this.toDate &&
          other.status == this.status &&
          other.updatedAt == this.updatedAt);
}

class ShoppingListsCompanion extends UpdateCompanion<ShoppingListRow> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<DateTime> fromDate;
  final Value<DateTime> toDate;
  final Value<String> status;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ShoppingListsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.fromDate = const Value.absent(),
    this.toDate = const Value.absent(),
    this.status = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShoppingListsCompanion.insert({
    required String id,
    required String householdId,
    required DateTime fromDate,
    required DateTime toDate,
    this.status = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       fromDate = Value(fromDate),
       toDate = Value(toDate),
       updatedAt = Value(updatedAt);
  static Insertable<ShoppingListRow> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<DateTime>? fromDate,
    Expression<DateTime>? toDate,
    Expression<String>? status,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (fromDate != null) 'from_date': fromDate,
      if (toDate != null) 'to_date': toDate,
      if (status != null) 'status': status,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShoppingListsCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<DateTime>? fromDate,
    Value<DateTime>? toDate,
    Value<String>? status,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ShoppingListsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (fromDate.present) {
      map['from_date'] = Variable<DateTime>(fromDate.value);
    }
    if (toDate.present) {
      map['to_date'] = Variable<DateTime>(toDate.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingListsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('fromDate: $fromDate, ')
          ..write('toDate: $toDate, ')
          ..write('status: $status, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShoppingListItemsTable extends ShoppingListItems
    with TableInfo<$ShoppingListItemsTable, ShoppingItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShoppingListItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _listIdMeta = const VerificationMeta('listId');
  @override
  late final GeneratedColumn<String> listId = GeneratedColumn<String>(
    'list_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemKeyMeta = const VerificationMeta(
    'itemKey',
  );
  @override
  late final GeneratedColumn<String> itemKey = GeneratedColumn<String>(
    'item_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _foodIdMeta = const VerificationMeta('foodId');
  @override
  late final GeneratedColumn<String> foodId = GeneratedColumn<String>(
    'food_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _plannedCanonicalMeta = const VerificationMeta(
    'plannedCanonical',
  );
  @override
  late final GeneratedColumn<double> plannedCanonical = GeneratedColumn<double>(
    'planned_canonical',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plannedKindMeta = const VerificationMeta(
    'plannedKind',
  );
  @override
  late final GeneratedColumn<String> plannedKind = GeneratedColumn<String>(
    'planned_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plannedUnitMeta = const VerificationMeta(
    'plannedUnit',
  );
  @override
  late final GeneratedColumn<String> plannedUnit = GeneratedColumn<String>(
    'planned_unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plannedRestMeta = const VerificationMeta(
    'plannedRest',
  );
  @override
  late final GeneratedColumn<String> plannedRest = GeneratedColumn<String>(
    'planned_rest',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _wantedCanonicalMeta = const VerificationMeta(
    'wantedCanonical',
  );
  @override
  late final GeneratedColumn<double> wantedCanonical = GeneratedColumn<double>(
    'wanted_canonical',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wantedKindMeta = const VerificationMeta(
    'wantedKind',
  );
  @override
  late final GeneratedColumn<String> wantedKind = GeneratedColumn<String>(
    'wanted_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wantedUnitMeta = const VerificationMeta(
    'wantedUnit',
  );
  @override
  late final GeneratedColumn<String> wantedUnit = GeneratedColumn<String>(
    'wanted_unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _onHandCanonicalMeta = const VerificationMeta(
    'onHandCanonical',
  );
  @override
  late final GeneratedColumn<double> onHandCanonical = GeneratedColumn<double>(
    'on_hand_canonical',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _onHandKindMeta = const VerificationMeta(
    'onHandKind',
  );
  @override
  late final GeneratedColumn<String> onHandKind = GeneratedColumn<String>(
    'on_hand_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _onHandUnitMeta = const VerificationMeta(
    'onHandUnit',
  );
  @override
  late final GeneratedColumn<String> onHandUnit = GeneratedColumn<String>(
    'on_hand_unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _checkedMeta = const VerificationMeta(
    'checked',
  );
  @override
  late final GeneratedColumn<bool> checked = GeneratedColumn<bool>(
    'checked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("checked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isManualMeta = const VerificationMeta(
    'isManual',
  );
  @override
  late final GeneratedColumn<bool> isManual = GeneratedColumn<bool>(
    'is_manual',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_manual" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hasUnquantifiedMeta = const VerificationMeta(
    'hasUnquantified',
  );
  @override
  late final GeneratedColumn<bool> hasUnquantified = GeneratedColumn<bool>(
    'has_unquantified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_unquantified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _storeTagMeta = const VerificationMeta(
    'storeTag',
  );
  @override
  late final GeneratedColumn<String> storeTag = GeneratedColumn<String>(
    'store_tag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sourceRecipeIdsMeta = const VerificationMeta(
    'sourceRecipeIds',
  );
  @override
  late final GeneratedColumn<String> sourceRecipeIds = GeneratedColumn<String>(
    'source_recipe_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    listId,
    itemKey,
    foodId,
    name,
    plannedCanonical,
    plannedKind,
    plannedUnit,
    plannedRest,
    wantedCanonical,
    wantedKind,
    wantedUnit,
    onHandCanonical,
    onHandKind,
    onHandUnit,
    checked,
    isManual,
    hasUnquantified,
    storeTag,
    sortOrder,
    sourceRecipeIds,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shopping_list_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShoppingItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('list_id')) {
      context.handle(
        _listIdMeta,
        listId.isAcceptableOrUnknown(data['list_id']!, _listIdMeta),
      );
    } else if (isInserting) {
      context.missing(_listIdMeta);
    }
    if (data.containsKey('item_key')) {
      context.handle(
        _itemKeyMeta,
        itemKey.isAcceptableOrUnknown(data['item_key']!, _itemKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_itemKeyMeta);
    }
    if (data.containsKey('food_id')) {
      context.handle(
        _foodIdMeta,
        foodId.isAcceptableOrUnknown(data['food_id']!, _foodIdMeta),
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
    if (data.containsKey('planned_canonical')) {
      context.handle(
        _plannedCanonicalMeta,
        plannedCanonical.isAcceptableOrUnknown(
          data['planned_canonical']!,
          _plannedCanonicalMeta,
        ),
      );
    }
    if (data.containsKey('planned_kind')) {
      context.handle(
        _plannedKindMeta,
        plannedKind.isAcceptableOrUnknown(
          data['planned_kind']!,
          _plannedKindMeta,
        ),
      );
    }
    if (data.containsKey('planned_unit')) {
      context.handle(
        _plannedUnitMeta,
        plannedUnit.isAcceptableOrUnknown(
          data['planned_unit']!,
          _plannedUnitMeta,
        ),
      );
    }
    if (data.containsKey('planned_rest')) {
      context.handle(
        _plannedRestMeta,
        plannedRest.isAcceptableOrUnknown(
          data['planned_rest']!,
          _plannedRestMeta,
        ),
      );
    }
    if (data.containsKey('wanted_canonical')) {
      context.handle(
        _wantedCanonicalMeta,
        wantedCanonical.isAcceptableOrUnknown(
          data['wanted_canonical']!,
          _wantedCanonicalMeta,
        ),
      );
    }
    if (data.containsKey('wanted_kind')) {
      context.handle(
        _wantedKindMeta,
        wantedKind.isAcceptableOrUnknown(data['wanted_kind']!, _wantedKindMeta),
      );
    }
    if (data.containsKey('wanted_unit')) {
      context.handle(
        _wantedUnitMeta,
        wantedUnit.isAcceptableOrUnknown(data['wanted_unit']!, _wantedUnitMeta),
      );
    }
    if (data.containsKey('on_hand_canonical')) {
      context.handle(
        _onHandCanonicalMeta,
        onHandCanonical.isAcceptableOrUnknown(
          data['on_hand_canonical']!,
          _onHandCanonicalMeta,
        ),
      );
    }
    if (data.containsKey('on_hand_kind')) {
      context.handle(
        _onHandKindMeta,
        onHandKind.isAcceptableOrUnknown(
          data['on_hand_kind']!,
          _onHandKindMeta,
        ),
      );
    }
    if (data.containsKey('on_hand_unit')) {
      context.handle(
        _onHandUnitMeta,
        onHandUnit.isAcceptableOrUnknown(
          data['on_hand_unit']!,
          _onHandUnitMeta,
        ),
      );
    }
    if (data.containsKey('checked')) {
      context.handle(
        _checkedMeta,
        checked.isAcceptableOrUnknown(data['checked']!, _checkedMeta),
      );
    }
    if (data.containsKey('is_manual')) {
      context.handle(
        _isManualMeta,
        isManual.isAcceptableOrUnknown(data['is_manual']!, _isManualMeta),
      );
    }
    if (data.containsKey('has_unquantified')) {
      context.handle(
        _hasUnquantifiedMeta,
        hasUnquantified.isAcceptableOrUnknown(
          data['has_unquantified']!,
          _hasUnquantifiedMeta,
        ),
      );
    }
    if (data.containsKey('store_tag')) {
      context.handle(
        _storeTagMeta,
        storeTag.isAcceptableOrUnknown(data['store_tag']!, _storeTagMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('source_recipe_ids')) {
      context.handle(
        _sourceRecipeIdsMeta,
        sourceRecipeIds.isAcceptableOrUnknown(
          data['source_recipe_ids']!,
          _sourceRecipeIdsMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShoppingItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShoppingItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      listId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}list_id'],
      )!,
      itemKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_key'],
      )!,
      foodId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}food_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      plannedCanonical: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}planned_canonical'],
      ),
      plannedKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}planned_kind'],
      ),
      plannedUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}planned_unit'],
      ),
      plannedRest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}planned_rest'],
      )!,
      wantedCanonical: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}wanted_canonical'],
      ),
      wantedKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wanted_kind'],
      ),
      wantedUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wanted_unit'],
      ),
      onHandCanonical: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}on_hand_canonical'],
      ),
      onHandKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}on_hand_kind'],
      ),
      onHandUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}on_hand_unit'],
      ),
      checked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}checked'],
      )!,
      isManual: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_manual'],
      )!,
      hasUnquantified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_unquantified'],
      )!,
      storeTag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_tag'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      sourceRecipeIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_recipe_ids'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ShoppingListItemsTable createAlias(String alias) {
    return $ShoppingListItemsTable(attachedDatabase, alias);
  }
}

class ShoppingItemRow extends DataClass implements Insertable<ShoppingItemRow> {
  final String id;
  final String listId;

  /// What duplicates are matched on, so a line survives a rebuild by being
  /// recognised rather than by being in the same place.
  final String itemKey;
  final String? foodId;
  final String name;
  final double? plannedCanonical;
  final String? plannedKind;
  final String? plannedUnit;

  /// The rest of what the recipes said, when they said it more than one way.
  ///
  /// JSON list of {canonical, kind, unit}. A line written as 2 tbsp *and*
  /// 50 g with no density to reconcile them has two planned amounts; keeping
  /// only the first made the line read as measurable on reload and quietly
  /// dropped the other half of the requirement.
  final String plannedRest;
  final double? wantedCanonical;
  final String? wantedKind;
  final String? wantedUnit;
  final double? onHandCanonical;
  final String? onHandKind;
  final String? onHandUnit;
  final bool checked;
  final bool isManual;
  final bool hasUnquantified;
  final String? storeTag;
  final int sortOrder;

  /// Comma-separated, like the other places this cache stores a small list —
  /// it is only ever read back whole.
  final String sourceRecipeIds;
  final DateTime updatedAt;
  const ShoppingItemRow({
    required this.id,
    required this.listId,
    required this.itemKey,
    this.foodId,
    required this.name,
    this.plannedCanonical,
    this.plannedKind,
    this.plannedUnit,
    required this.plannedRest,
    this.wantedCanonical,
    this.wantedKind,
    this.wantedUnit,
    this.onHandCanonical,
    this.onHandKind,
    this.onHandUnit,
    required this.checked,
    required this.isManual,
    required this.hasUnquantified,
    this.storeTag,
    required this.sortOrder,
    required this.sourceRecipeIds,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['list_id'] = Variable<String>(listId);
    map['item_key'] = Variable<String>(itemKey);
    if (!nullToAbsent || foodId != null) {
      map['food_id'] = Variable<String>(foodId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || plannedCanonical != null) {
      map['planned_canonical'] = Variable<double>(plannedCanonical);
    }
    if (!nullToAbsent || plannedKind != null) {
      map['planned_kind'] = Variable<String>(plannedKind);
    }
    if (!nullToAbsent || plannedUnit != null) {
      map['planned_unit'] = Variable<String>(plannedUnit);
    }
    map['planned_rest'] = Variable<String>(plannedRest);
    if (!nullToAbsent || wantedCanonical != null) {
      map['wanted_canonical'] = Variable<double>(wantedCanonical);
    }
    if (!nullToAbsent || wantedKind != null) {
      map['wanted_kind'] = Variable<String>(wantedKind);
    }
    if (!nullToAbsent || wantedUnit != null) {
      map['wanted_unit'] = Variable<String>(wantedUnit);
    }
    if (!nullToAbsent || onHandCanonical != null) {
      map['on_hand_canonical'] = Variable<double>(onHandCanonical);
    }
    if (!nullToAbsent || onHandKind != null) {
      map['on_hand_kind'] = Variable<String>(onHandKind);
    }
    if (!nullToAbsent || onHandUnit != null) {
      map['on_hand_unit'] = Variable<String>(onHandUnit);
    }
    map['checked'] = Variable<bool>(checked);
    map['is_manual'] = Variable<bool>(isManual);
    map['has_unquantified'] = Variable<bool>(hasUnquantified);
    if (!nullToAbsent || storeTag != null) {
      map['store_tag'] = Variable<String>(storeTag);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['source_recipe_ids'] = Variable<String>(sourceRecipeIds);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ShoppingListItemsCompanion toCompanion(bool nullToAbsent) {
    return ShoppingListItemsCompanion(
      id: Value(id),
      listId: Value(listId),
      itemKey: Value(itemKey),
      foodId: foodId == null && nullToAbsent
          ? const Value.absent()
          : Value(foodId),
      name: Value(name),
      plannedCanonical: plannedCanonical == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedCanonical),
      plannedKind: plannedKind == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedKind),
      plannedUnit: plannedUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedUnit),
      plannedRest: Value(plannedRest),
      wantedCanonical: wantedCanonical == null && nullToAbsent
          ? const Value.absent()
          : Value(wantedCanonical),
      wantedKind: wantedKind == null && nullToAbsent
          ? const Value.absent()
          : Value(wantedKind),
      wantedUnit: wantedUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(wantedUnit),
      onHandCanonical: onHandCanonical == null && nullToAbsent
          ? const Value.absent()
          : Value(onHandCanonical),
      onHandKind: onHandKind == null && nullToAbsent
          ? const Value.absent()
          : Value(onHandKind),
      onHandUnit: onHandUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(onHandUnit),
      checked: Value(checked),
      isManual: Value(isManual),
      hasUnquantified: Value(hasUnquantified),
      storeTag: storeTag == null && nullToAbsent
          ? const Value.absent()
          : Value(storeTag),
      sortOrder: Value(sortOrder),
      sourceRecipeIds: Value(sourceRecipeIds),
      updatedAt: Value(updatedAt),
    );
  }

  factory ShoppingItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShoppingItemRow(
      id: serializer.fromJson<String>(json['id']),
      listId: serializer.fromJson<String>(json['listId']),
      itemKey: serializer.fromJson<String>(json['itemKey']),
      foodId: serializer.fromJson<String?>(json['foodId']),
      name: serializer.fromJson<String>(json['name']),
      plannedCanonical: serializer.fromJson<double?>(json['plannedCanonical']),
      plannedKind: serializer.fromJson<String?>(json['plannedKind']),
      plannedUnit: serializer.fromJson<String?>(json['plannedUnit']),
      plannedRest: serializer.fromJson<String>(json['plannedRest']),
      wantedCanonical: serializer.fromJson<double?>(json['wantedCanonical']),
      wantedKind: serializer.fromJson<String?>(json['wantedKind']),
      wantedUnit: serializer.fromJson<String?>(json['wantedUnit']),
      onHandCanonical: serializer.fromJson<double?>(json['onHandCanonical']),
      onHandKind: serializer.fromJson<String?>(json['onHandKind']),
      onHandUnit: serializer.fromJson<String?>(json['onHandUnit']),
      checked: serializer.fromJson<bool>(json['checked']),
      isManual: serializer.fromJson<bool>(json['isManual']),
      hasUnquantified: serializer.fromJson<bool>(json['hasUnquantified']),
      storeTag: serializer.fromJson<String?>(json['storeTag']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      sourceRecipeIds: serializer.fromJson<String>(json['sourceRecipeIds']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'listId': serializer.toJson<String>(listId),
      'itemKey': serializer.toJson<String>(itemKey),
      'foodId': serializer.toJson<String?>(foodId),
      'name': serializer.toJson<String>(name),
      'plannedCanonical': serializer.toJson<double?>(plannedCanonical),
      'plannedKind': serializer.toJson<String?>(plannedKind),
      'plannedUnit': serializer.toJson<String?>(plannedUnit),
      'plannedRest': serializer.toJson<String>(plannedRest),
      'wantedCanonical': serializer.toJson<double?>(wantedCanonical),
      'wantedKind': serializer.toJson<String?>(wantedKind),
      'wantedUnit': serializer.toJson<String?>(wantedUnit),
      'onHandCanonical': serializer.toJson<double?>(onHandCanonical),
      'onHandKind': serializer.toJson<String?>(onHandKind),
      'onHandUnit': serializer.toJson<String?>(onHandUnit),
      'checked': serializer.toJson<bool>(checked),
      'isManual': serializer.toJson<bool>(isManual),
      'hasUnquantified': serializer.toJson<bool>(hasUnquantified),
      'storeTag': serializer.toJson<String?>(storeTag),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'sourceRecipeIds': serializer.toJson<String>(sourceRecipeIds),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ShoppingItemRow copyWith({
    String? id,
    String? listId,
    String? itemKey,
    Value<String?> foodId = const Value.absent(),
    String? name,
    Value<double?> plannedCanonical = const Value.absent(),
    Value<String?> plannedKind = const Value.absent(),
    Value<String?> plannedUnit = const Value.absent(),
    String? plannedRest,
    Value<double?> wantedCanonical = const Value.absent(),
    Value<String?> wantedKind = const Value.absent(),
    Value<String?> wantedUnit = const Value.absent(),
    Value<double?> onHandCanonical = const Value.absent(),
    Value<String?> onHandKind = const Value.absent(),
    Value<String?> onHandUnit = const Value.absent(),
    bool? checked,
    bool? isManual,
    bool? hasUnquantified,
    Value<String?> storeTag = const Value.absent(),
    int? sortOrder,
    String? sourceRecipeIds,
    DateTime? updatedAt,
  }) => ShoppingItemRow(
    id: id ?? this.id,
    listId: listId ?? this.listId,
    itemKey: itemKey ?? this.itemKey,
    foodId: foodId.present ? foodId.value : this.foodId,
    name: name ?? this.name,
    plannedCanonical: plannedCanonical.present
        ? plannedCanonical.value
        : this.plannedCanonical,
    plannedKind: plannedKind.present ? plannedKind.value : this.plannedKind,
    plannedUnit: plannedUnit.present ? plannedUnit.value : this.plannedUnit,
    plannedRest: plannedRest ?? this.plannedRest,
    wantedCanonical: wantedCanonical.present
        ? wantedCanonical.value
        : this.wantedCanonical,
    wantedKind: wantedKind.present ? wantedKind.value : this.wantedKind,
    wantedUnit: wantedUnit.present ? wantedUnit.value : this.wantedUnit,
    onHandCanonical: onHandCanonical.present
        ? onHandCanonical.value
        : this.onHandCanonical,
    onHandKind: onHandKind.present ? onHandKind.value : this.onHandKind,
    onHandUnit: onHandUnit.present ? onHandUnit.value : this.onHandUnit,
    checked: checked ?? this.checked,
    isManual: isManual ?? this.isManual,
    hasUnquantified: hasUnquantified ?? this.hasUnquantified,
    storeTag: storeTag.present ? storeTag.value : this.storeTag,
    sortOrder: sortOrder ?? this.sortOrder,
    sourceRecipeIds: sourceRecipeIds ?? this.sourceRecipeIds,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ShoppingItemRow copyWithCompanion(ShoppingListItemsCompanion data) {
    return ShoppingItemRow(
      id: data.id.present ? data.id.value : this.id,
      listId: data.listId.present ? data.listId.value : this.listId,
      itemKey: data.itemKey.present ? data.itemKey.value : this.itemKey,
      foodId: data.foodId.present ? data.foodId.value : this.foodId,
      name: data.name.present ? data.name.value : this.name,
      plannedCanonical: data.plannedCanonical.present
          ? data.plannedCanonical.value
          : this.plannedCanonical,
      plannedKind: data.plannedKind.present
          ? data.plannedKind.value
          : this.plannedKind,
      plannedUnit: data.plannedUnit.present
          ? data.plannedUnit.value
          : this.plannedUnit,
      plannedRest: data.plannedRest.present
          ? data.plannedRest.value
          : this.plannedRest,
      wantedCanonical: data.wantedCanonical.present
          ? data.wantedCanonical.value
          : this.wantedCanonical,
      wantedKind: data.wantedKind.present
          ? data.wantedKind.value
          : this.wantedKind,
      wantedUnit: data.wantedUnit.present
          ? data.wantedUnit.value
          : this.wantedUnit,
      onHandCanonical: data.onHandCanonical.present
          ? data.onHandCanonical.value
          : this.onHandCanonical,
      onHandKind: data.onHandKind.present
          ? data.onHandKind.value
          : this.onHandKind,
      onHandUnit: data.onHandUnit.present
          ? data.onHandUnit.value
          : this.onHandUnit,
      checked: data.checked.present ? data.checked.value : this.checked,
      isManual: data.isManual.present ? data.isManual.value : this.isManual,
      hasUnquantified: data.hasUnquantified.present
          ? data.hasUnquantified.value
          : this.hasUnquantified,
      storeTag: data.storeTag.present ? data.storeTag.value : this.storeTag,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      sourceRecipeIds: data.sourceRecipeIds.present
          ? data.sourceRecipeIds.value
          : this.sourceRecipeIds,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingItemRow(')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('itemKey: $itemKey, ')
          ..write('foodId: $foodId, ')
          ..write('name: $name, ')
          ..write('plannedCanonical: $plannedCanonical, ')
          ..write('plannedKind: $plannedKind, ')
          ..write('plannedUnit: $plannedUnit, ')
          ..write('plannedRest: $plannedRest, ')
          ..write('wantedCanonical: $wantedCanonical, ')
          ..write('wantedKind: $wantedKind, ')
          ..write('wantedUnit: $wantedUnit, ')
          ..write('onHandCanonical: $onHandCanonical, ')
          ..write('onHandKind: $onHandKind, ')
          ..write('onHandUnit: $onHandUnit, ')
          ..write('checked: $checked, ')
          ..write('isManual: $isManual, ')
          ..write('hasUnquantified: $hasUnquantified, ')
          ..write('storeTag: $storeTag, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('sourceRecipeIds: $sourceRecipeIds, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    listId,
    itemKey,
    foodId,
    name,
    plannedCanonical,
    plannedKind,
    plannedUnit,
    plannedRest,
    wantedCanonical,
    wantedKind,
    wantedUnit,
    onHandCanonical,
    onHandKind,
    onHandUnit,
    checked,
    isManual,
    hasUnquantified,
    storeTag,
    sortOrder,
    sourceRecipeIds,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShoppingItemRow &&
          other.id == this.id &&
          other.listId == this.listId &&
          other.itemKey == this.itemKey &&
          other.foodId == this.foodId &&
          other.name == this.name &&
          other.plannedCanonical == this.plannedCanonical &&
          other.plannedKind == this.plannedKind &&
          other.plannedUnit == this.plannedUnit &&
          other.plannedRest == this.plannedRest &&
          other.wantedCanonical == this.wantedCanonical &&
          other.wantedKind == this.wantedKind &&
          other.wantedUnit == this.wantedUnit &&
          other.onHandCanonical == this.onHandCanonical &&
          other.onHandKind == this.onHandKind &&
          other.onHandUnit == this.onHandUnit &&
          other.checked == this.checked &&
          other.isManual == this.isManual &&
          other.hasUnquantified == this.hasUnquantified &&
          other.storeTag == this.storeTag &&
          other.sortOrder == this.sortOrder &&
          other.sourceRecipeIds == this.sourceRecipeIds &&
          other.updatedAt == this.updatedAt);
}

class ShoppingListItemsCompanion extends UpdateCompanion<ShoppingItemRow> {
  final Value<String> id;
  final Value<String> listId;
  final Value<String> itemKey;
  final Value<String?> foodId;
  final Value<String> name;
  final Value<double?> plannedCanonical;
  final Value<String?> plannedKind;
  final Value<String?> plannedUnit;
  final Value<String> plannedRest;
  final Value<double?> wantedCanonical;
  final Value<String?> wantedKind;
  final Value<String?> wantedUnit;
  final Value<double?> onHandCanonical;
  final Value<String?> onHandKind;
  final Value<String?> onHandUnit;
  final Value<bool> checked;
  final Value<bool> isManual;
  final Value<bool> hasUnquantified;
  final Value<String?> storeTag;
  final Value<int> sortOrder;
  final Value<String> sourceRecipeIds;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ShoppingListItemsCompanion({
    this.id = const Value.absent(),
    this.listId = const Value.absent(),
    this.itemKey = const Value.absent(),
    this.foodId = const Value.absent(),
    this.name = const Value.absent(),
    this.plannedCanonical = const Value.absent(),
    this.plannedKind = const Value.absent(),
    this.plannedUnit = const Value.absent(),
    this.plannedRest = const Value.absent(),
    this.wantedCanonical = const Value.absent(),
    this.wantedKind = const Value.absent(),
    this.wantedUnit = const Value.absent(),
    this.onHandCanonical = const Value.absent(),
    this.onHandKind = const Value.absent(),
    this.onHandUnit = const Value.absent(),
    this.checked = const Value.absent(),
    this.isManual = const Value.absent(),
    this.hasUnquantified = const Value.absent(),
    this.storeTag = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.sourceRecipeIds = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShoppingListItemsCompanion.insert({
    required String id,
    required String listId,
    required String itemKey,
    this.foodId = const Value.absent(),
    required String name,
    this.plannedCanonical = const Value.absent(),
    this.plannedKind = const Value.absent(),
    this.plannedUnit = const Value.absent(),
    this.plannedRest = const Value.absent(),
    this.wantedCanonical = const Value.absent(),
    this.wantedKind = const Value.absent(),
    this.wantedUnit = const Value.absent(),
    this.onHandCanonical = const Value.absent(),
    this.onHandKind = const Value.absent(),
    this.onHandUnit = const Value.absent(),
    this.checked = const Value.absent(),
    this.isManual = const Value.absent(),
    this.hasUnquantified = const Value.absent(),
    this.storeTag = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.sourceRecipeIds = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       listId = Value(listId),
       itemKey = Value(itemKey),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<ShoppingItemRow> custom({
    Expression<String>? id,
    Expression<String>? listId,
    Expression<String>? itemKey,
    Expression<String>? foodId,
    Expression<String>? name,
    Expression<double>? plannedCanonical,
    Expression<String>? plannedKind,
    Expression<String>? plannedUnit,
    Expression<String>? plannedRest,
    Expression<double>? wantedCanonical,
    Expression<String>? wantedKind,
    Expression<String>? wantedUnit,
    Expression<double>? onHandCanonical,
    Expression<String>? onHandKind,
    Expression<String>? onHandUnit,
    Expression<bool>? checked,
    Expression<bool>? isManual,
    Expression<bool>? hasUnquantified,
    Expression<String>? storeTag,
    Expression<int>? sortOrder,
    Expression<String>? sourceRecipeIds,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (listId != null) 'list_id': listId,
      if (itemKey != null) 'item_key': itemKey,
      if (foodId != null) 'food_id': foodId,
      if (name != null) 'name': name,
      if (plannedCanonical != null) 'planned_canonical': plannedCanonical,
      if (plannedKind != null) 'planned_kind': plannedKind,
      if (plannedUnit != null) 'planned_unit': plannedUnit,
      if (plannedRest != null) 'planned_rest': plannedRest,
      if (wantedCanonical != null) 'wanted_canonical': wantedCanonical,
      if (wantedKind != null) 'wanted_kind': wantedKind,
      if (wantedUnit != null) 'wanted_unit': wantedUnit,
      if (onHandCanonical != null) 'on_hand_canonical': onHandCanonical,
      if (onHandKind != null) 'on_hand_kind': onHandKind,
      if (onHandUnit != null) 'on_hand_unit': onHandUnit,
      if (checked != null) 'checked': checked,
      if (isManual != null) 'is_manual': isManual,
      if (hasUnquantified != null) 'has_unquantified': hasUnquantified,
      if (storeTag != null) 'store_tag': storeTag,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (sourceRecipeIds != null) 'source_recipe_ids': sourceRecipeIds,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShoppingListItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? listId,
    Value<String>? itemKey,
    Value<String?>? foodId,
    Value<String>? name,
    Value<double?>? plannedCanonical,
    Value<String?>? plannedKind,
    Value<String?>? plannedUnit,
    Value<String>? plannedRest,
    Value<double?>? wantedCanonical,
    Value<String?>? wantedKind,
    Value<String?>? wantedUnit,
    Value<double?>? onHandCanonical,
    Value<String?>? onHandKind,
    Value<String?>? onHandUnit,
    Value<bool>? checked,
    Value<bool>? isManual,
    Value<bool>? hasUnquantified,
    Value<String?>? storeTag,
    Value<int>? sortOrder,
    Value<String>? sourceRecipeIds,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ShoppingListItemsCompanion(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      itemKey: itemKey ?? this.itemKey,
      foodId: foodId ?? this.foodId,
      name: name ?? this.name,
      plannedCanonical: plannedCanonical ?? this.plannedCanonical,
      plannedKind: plannedKind ?? this.plannedKind,
      plannedUnit: plannedUnit ?? this.plannedUnit,
      plannedRest: plannedRest ?? this.plannedRest,
      wantedCanonical: wantedCanonical ?? this.wantedCanonical,
      wantedKind: wantedKind ?? this.wantedKind,
      wantedUnit: wantedUnit ?? this.wantedUnit,
      onHandCanonical: onHandCanonical ?? this.onHandCanonical,
      onHandKind: onHandKind ?? this.onHandKind,
      onHandUnit: onHandUnit ?? this.onHandUnit,
      checked: checked ?? this.checked,
      isManual: isManual ?? this.isManual,
      hasUnquantified: hasUnquantified ?? this.hasUnquantified,
      storeTag: storeTag ?? this.storeTag,
      sortOrder: sortOrder ?? this.sortOrder,
      sourceRecipeIds: sourceRecipeIds ?? this.sourceRecipeIds,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (listId.present) {
      map['list_id'] = Variable<String>(listId.value);
    }
    if (itemKey.present) {
      map['item_key'] = Variable<String>(itemKey.value);
    }
    if (foodId.present) {
      map['food_id'] = Variable<String>(foodId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (plannedCanonical.present) {
      map['planned_canonical'] = Variable<double>(plannedCanonical.value);
    }
    if (plannedKind.present) {
      map['planned_kind'] = Variable<String>(plannedKind.value);
    }
    if (plannedUnit.present) {
      map['planned_unit'] = Variable<String>(plannedUnit.value);
    }
    if (plannedRest.present) {
      map['planned_rest'] = Variable<String>(plannedRest.value);
    }
    if (wantedCanonical.present) {
      map['wanted_canonical'] = Variable<double>(wantedCanonical.value);
    }
    if (wantedKind.present) {
      map['wanted_kind'] = Variable<String>(wantedKind.value);
    }
    if (wantedUnit.present) {
      map['wanted_unit'] = Variable<String>(wantedUnit.value);
    }
    if (onHandCanonical.present) {
      map['on_hand_canonical'] = Variable<double>(onHandCanonical.value);
    }
    if (onHandKind.present) {
      map['on_hand_kind'] = Variable<String>(onHandKind.value);
    }
    if (onHandUnit.present) {
      map['on_hand_unit'] = Variable<String>(onHandUnit.value);
    }
    if (checked.present) {
      map['checked'] = Variable<bool>(checked.value);
    }
    if (isManual.present) {
      map['is_manual'] = Variable<bool>(isManual.value);
    }
    if (hasUnquantified.present) {
      map['has_unquantified'] = Variable<bool>(hasUnquantified.value);
    }
    if (storeTag.present) {
      map['store_tag'] = Variable<String>(storeTag.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (sourceRecipeIds.present) {
      map['source_recipe_ids'] = Variable<String>(sourceRecipeIds.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingListItemsCompanion(')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('itemKey: $itemKey, ')
          ..write('foodId: $foodId, ')
          ..write('name: $name, ')
          ..write('plannedCanonical: $plannedCanonical, ')
          ..write('plannedKind: $plannedKind, ')
          ..write('plannedUnit: $plannedUnit, ')
          ..write('plannedRest: $plannedRest, ')
          ..write('wantedCanonical: $wantedCanonical, ')
          ..write('wantedKind: $wantedKind, ')
          ..write('wantedUnit: $wantedUnit, ')
          ..write('onHandCanonical: $onHandCanonical, ')
          ..write('onHandKind: $onHandKind, ')
          ..write('onHandUnit: $onHandUnit, ')
          ..write('checked: $checked, ')
          ..write('isManual: $isManual, ')
          ..write('hasUnquantified: $hasUnquantified, ')
          ..write('storeTag: $storeTag, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('sourceRecipeIds: $sourceRecipeIds, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$HearthDatabase extends GeneratedDatabase {
  _$HearthDatabase(QueryExecutor e) : super(e);
  $HearthDatabaseManager get managers => $HearthDatabaseManager(this);
  late final $RecipesTable recipes = $RecipesTable(this);
  late final $RecipeSectionsTable recipeSections = $RecipeSectionsTable(this);
  late final $RecipeIngredientsTable recipeIngredients =
      $RecipeIngredientsTable(this);
  late final $RecipeStepsTable recipeSteps = $RecipeStepsTable(this);
  late final $RecipeFavoritesTable recipeFavorites = $RecipeFavoritesTable(
    this,
  );
  late final $CollectionsTable collections = $CollectionsTable(this);
  late final $RecipeCollectionsTable recipeCollections =
      $RecipeCollectionsTable(this);
  late final $FoodsTable foods = $FoodsTable(this);
  late final $FoodServingOptionsTable foodServingOptions =
      $FoodServingOptionsTable(this);
  late final $MealPlanDaysTable mealPlanDays = $MealPlanDaysTable(this);
  late final $MealPlanEntriesTable mealPlanEntries = $MealPlanEntriesTable(
    this,
  );
  late final $MacroTargetsTable macroTargets = $MacroTargetsTable(this);
  late final $IngredientMatchesTable ingredientMatches =
      $IngredientMatchesTable(this);
  late final $CookTimersTable cookTimers = $CookTimersTable(this);
  late final $FoodProfilesTable foodProfiles = $FoodProfilesTable(this);
  late final $PreferencesTable preferences = $PreferencesTable(this);
  late final $CookSessionsTable cookSessions = $CookSessionsTable(this);
  late final $RecipePhotosTable recipePhotos = $RecipePhotosTable(this);
  late final $PlanTemplatesTable planTemplates = $PlanTemplatesTable(this);
  late final $PendingWritesTable pendingWrites = $PendingWritesTable(this);
  late final $ShoppingListsTable shoppingLists = $ShoppingListsTable(this);
  late final $ShoppingListItemsTable shoppingListItems =
      $ShoppingListItemsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    recipes,
    recipeSections,
    recipeIngredients,
    recipeSteps,
    recipeFavorites,
    collections,
    recipeCollections,
    foods,
    foodServingOptions,
    mealPlanDays,
    mealPlanEntries,
    macroTargets,
    ingredientMatches,
    cookTimers,
    foodProfiles,
    preferences,
    cookSessions,
    recipePhotos,
    planTemplates,
    pendingWrites,
    shoppingLists,
    shoppingListItems,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'recipes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('recipe_sections', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'recipes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('recipe_ingredients', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'recipes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('recipe_steps', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'recipes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('recipe_favorites', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'collections',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('recipe_collections', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'recipes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('recipe_collections', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'foods',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('food_serving_options', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'meal_plan_days',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('meal_plan_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'foods',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('ingredient_matches', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'recipes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('recipe_photos', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$RecipesTableCreateCompanionBuilder = RecipesCompanion Function({
  required String id,
  required String householdId,
  required String title,
  required double servings,
  Value<int?> prepSeconds,
  Value<int?> cookSeconds,
  Value<String?> cuisine,
  Value<List<String>> tags,
  Value<String> kind,
  Value<String> source,
  Value<String?> photoUrl,
  Value<String?> notes,
  Value<String?> createdBy,
  Value<bool> isDeleted,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$RecipesTableUpdateCompanionBuilder = RecipesCompanion Function({
  Value<String> id,
  Value<String> householdId,
  Value<String> title,
  Value<double> servings,
  Value<int?> prepSeconds,
  Value<int?> cookSeconds,
  Value<String?> cuisine,
  Value<List<String>> tags,
  Value<String> kind,
  Value<String> source,
  Value<String?> photoUrl,
  Value<String?> notes,
  Value<String?> createdBy,
  Value<bool> isDeleted,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

final class $$RecipesTableReferences
    extends BaseReferences<_$HearthDatabase, $RecipesTable, RecipeRow> {
  $$RecipesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$RecipeSectionsTable, List<RecipeSectionRow>>
  _recipeSectionsRefsTable(_$HearthDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.recipeSections,
        aliasName: 'recipes__id__recipe_sections__recipe_id',
      );

  $$RecipeSectionsTableProcessedTableManager get recipeSectionsRefs {
    final manager = $$RecipeSectionsTableTableManager(
      $_db,
      $_db.recipeSections,
    ).filter((f) => f.recipeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_recipeSectionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RecipeIngredientsTable, List<RecipeIngredientRow>>
  _recipeIngredientsRefsTable(_$HearthDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.recipeIngredients,
        aliasName: 'recipes__id__recipe_ingredients__recipe_id',
      );

  $$RecipeIngredientsTableProcessedTableManager get recipeIngredientsRefs {
    final manager = $$RecipeIngredientsTableTableManager(
      $_db,
      $_db.recipeIngredients,
    ).filter((f) => f.recipeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _recipeIngredientsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RecipeStepsTable, List<RecipeStepRow>>
  _recipeStepsRefsTable(_$HearthDatabase db) => MultiTypedResultKey.fromTable(
    db.recipeSteps,
    aliasName: 'recipes__id__recipe_steps__recipe_id',
  );

  $$RecipeStepsTableProcessedTableManager get recipeStepsRefs {
    final manager = $$RecipeStepsTableTableManager(
      $_db,
      $_db.recipeSteps,
    ).filter((f) => f.recipeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_recipeStepsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RecipeFavoritesTable, List<RecipeFavoriteRow>>
  _recipeFavoritesRefsTable(_$HearthDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.recipeFavorites,
        aliasName: 'recipes__id__recipe_favorites__recipe_id',
      );

  $$RecipeFavoritesTableProcessedTableManager get recipeFavoritesRefs {
    final manager = $$RecipeFavoritesTableTableManager(
      $_db,
      $_db.recipeFavorites,
    ).filter((f) => f.recipeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _recipeFavoritesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RecipeCollectionsTable, List<RecipeCollectionRow>>
  _recipeCollectionsRefsTable(_$HearthDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.recipeCollections,
        aliasName: 'recipes__id__recipe_collections__recipe_id',
      );

  $$RecipeCollectionsTableProcessedTableManager get recipeCollectionsRefs {
    final manager = $$RecipeCollectionsTableTableManager(
      $_db,
      $_db.recipeCollections,
    ).filter((f) => f.recipeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _recipeCollectionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RecipePhotosTable, List<RecipePhotoRow>>
  _recipePhotosRefsTable(_$HearthDatabase db) => MultiTypedResultKey.fromTable(
    db.recipePhotos,
    aliasName: 'recipes__id__recipe_photos__recipe_id',
  );

  $$RecipePhotosTableProcessedTableManager get recipePhotosRefs {
    final manager = $$RecipePhotosTableTableManager(
      $_db,
      $_db.recipePhotos,
    ).filter((f) => f.recipeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_recipePhotosRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RecipesTableFilterComposer
    extends Composer<_$HearthDatabase, $RecipesTable> {
  $$RecipesTableFilterComposer({
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

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get servings => $composableBuilder(
    column: $table.servings,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get prepSeconds => $composableBuilder(
    column: $table.prepSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cookSeconds => $composableBuilder(
    column: $table.cookSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cuisine => $composableBuilder(
    column: $table.cuisine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String> get tags =>
      $composableBuilder(
        column: $table.tags,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoUrl => $composableBuilder(
    column: $table.photoUrl,
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

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> recipeSectionsRefs(
    Expression<bool> Function($$RecipeSectionsTableFilterComposer f) f,
  ) {
    final $$RecipeSectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeSections,
      getReferencedColumn: (t) => t.recipeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeSectionsTableFilterComposer(
            $db: $db,
            $table: $db.recipeSections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> recipeIngredientsRefs(
    Expression<bool> Function($$RecipeIngredientsTableFilterComposer f) f,
  ) {
    final $$RecipeIngredientsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeIngredients,
      getReferencedColumn: (t) => t.recipeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeIngredientsTableFilterComposer(
            $db: $db,
            $table: $db.recipeIngredients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> recipeStepsRefs(
    Expression<bool> Function($$RecipeStepsTableFilterComposer f) f,
  ) {
    final $$RecipeStepsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeSteps,
      getReferencedColumn: (t) => t.recipeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeStepsTableFilterComposer(
            $db: $db,
            $table: $db.recipeSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> recipeFavoritesRefs(
    Expression<bool> Function($$RecipeFavoritesTableFilterComposer f) f,
  ) {
    final $$RecipeFavoritesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeFavorites,
      getReferencedColumn: (t) => t.recipeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeFavoritesTableFilterComposer(
            $db: $db,
            $table: $db.recipeFavorites,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> recipeCollectionsRefs(
    Expression<bool> Function($$RecipeCollectionsTableFilterComposer f) f,
  ) {
    final $$RecipeCollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeCollections,
      getReferencedColumn: (t) => t.recipeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeCollectionsTableFilterComposer(
            $db: $db,
            $table: $db.recipeCollections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> recipePhotosRefs(
    Expression<bool> Function($$RecipePhotosTableFilterComposer f) f,
  ) {
    final $$RecipePhotosTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipePhotos,
      getReferencedColumn: (t) => t.recipeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipePhotosTableFilterComposer(
            $db: $db,
            $table: $db.recipePhotos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecipesTableOrderingComposer
    extends Composer<_$HearthDatabase, $RecipesTable> {
  $$RecipesTableOrderingComposer({
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

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get servings => $composableBuilder(
    column: $table.servings,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get prepSeconds => $composableBuilder(
    column: $table.prepSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cookSeconds => $composableBuilder(
    column: $table.cookSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cuisine => $composableBuilder(
    column: $table.cuisine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoUrl => $composableBuilder(
    column: $table.photoUrl,
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

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecipesTableAnnotationComposer
    extends Composer<_$HearthDatabase, $RecipesTable> {
  $$RecipesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<double> get servings =>
      $composableBuilder(column: $table.servings, builder: (column) => column);

  GeneratedColumn<int> get prepSeconds => $composableBuilder(
    column: $table.prepSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cookSeconds => $composableBuilder(
    column: $table.cookSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cuisine =>
      $composableBuilder(column: $table.cuisine, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<String>, String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get photoUrl =>
      $composableBuilder(column: $table.photoUrl, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> recipeSectionsRefs<T extends Object>(
    Expression<T> Function($$RecipeSectionsTableAnnotationComposer a) f,
  ) {
    final $$RecipeSectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeSections,
      getReferencedColumn: (t) => t.recipeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeSectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.recipeSections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> recipeIngredientsRefs<T extends Object>(
    Expression<T> Function($$RecipeIngredientsTableAnnotationComposer a) f,
  ) {
    final $$RecipeIngredientsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.recipeIngredients,
          getReferencedColumn: (t) => t.recipeId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RecipeIngredientsTableAnnotationComposer(
                $db: $db,
                $table: $db.recipeIngredients,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> recipeStepsRefs<T extends Object>(
    Expression<T> Function($$RecipeStepsTableAnnotationComposer a) f,
  ) {
    final $$RecipeStepsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeSteps,
      getReferencedColumn: (t) => t.recipeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeStepsTableAnnotationComposer(
            $db: $db,
            $table: $db.recipeSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> recipeFavoritesRefs<T extends Object>(
    Expression<T> Function($$RecipeFavoritesTableAnnotationComposer a) f,
  ) {
    final $$RecipeFavoritesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeFavorites,
      getReferencedColumn: (t) => t.recipeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeFavoritesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipeFavorites,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> recipeCollectionsRefs<T extends Object>(
    Expression<T> Function($$RecipeCollectionsTableAnnotationComposer a) f,
  ) {
    final $$RecipeCollectionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.recipeCollections,
          getReferencedColumn: (t) => t.recipeId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RecipeCollectionsTableAnnotationComposer(
                $db: $db,
                $table: $db.recipeCollections,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> recipePhotosRefs<T extends Object>(
    Expression<T> Function($$RecipePhotosTableAnnotationComposer a) f,
  ) {
    final $$RecipePhotosTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipePhotos,
      getReferencedColumn: (t) => t.recipeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipePhotosTableAnnotationComposer(
            $db: $db,
            $table: $db.recipePhotos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecipesTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $RecipesTable,
          RecipeRow,
          $$RecipesTableFilterComposer,
          $$RecipesTableOrderingComposer,
          $$RecipesTableAnnotationComposer,
          $$RecipesTableCreateCompanionBuilder,
          $$RecipesTableUpdateCompanionBuilder,
          (RecipeRow, $$RecipesTableReferences),
          RecipeRow,
          PrefetchHooks Function({
            bool recipeSectionsRefs,
            bool recipeIngredientsRefs,
            bool recipeStepsRefs,
            bool recipeFavoritesRefs,
            bool recipeCollectionsRefs,
            bool recipePhotosRefs,
          })
        > {
  $$RecipesTableTableManager(_$HearthDatabase db, $RecipesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecipesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecipesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecipesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<double> servings = const Value.absent(),
                Value<int?> prepSeconds = const Value.absent(),
                Value<int?> cookSeconds = const Value.absent(),
                Value<String?> cuisine = const Value.absent(),
                Value<List<String>> tags = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> photoUrl = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipesCompanion(
                id: id,
                householdId: householdId,
                title: title,
                servings: servings,
                prepSeconds: prepSeconds,
                cookSeconds: cookSeconds,
                cuisine: cuisine,
                tags: tags,
                kind: kind,
                source: source,
                photoUrl: photoUrl,
                notes: notes,
                createdBy: createdBy,
                isDeleted: isDeleted,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required String title,
                required double servings,
                Value<int?> prepSeconds = const Value.absent(),
                Value<int?> cookSeconds = const Value.absent(),
                Value<String?> cuisine = const Value.absent(),
                Value<List<String>> tags = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> photoUrl = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RecipesCompanion.insert(
                id: id,
                householdId: householdId,
                title: title,
                servings: servings,
                prepSeconds: prepSeconds,
                cookSeconds: cookSeconds,
                cuisine: cuisine,
                tags: tags,
                kind: kind,
                source: source,
                photoUrl: photoUrl,
                notes: notes,
                createdBy: createdBy,
                isDeleted: isDeleted,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecipesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                recipeSectionsRefs = false,
                recipeIngredientsRefs = false,
                recipeStepsRefs = false,
                recipeFavoritesRefs = false,
                recipeCollectionsRefs = false,
                recipePhotosRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (recipeSectionsRefs) db.recipeSections,
                    if (recipeIngredientsRefs) db.recipeIngredients,
                    if (recipeStepsRefs) db.recipeSteps,
                    if (recipeFavoritesRefs) db.recipeFavorites,
                    if (recipeCollectionsRefs) db.recipeCollections,
                    if (recipePhotosRefs) db.recipePhotos,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (recipeSectionsRefs)
                        await $_getPrefetchedData<
                          RecipeRow,
                          $RecipesTable,
                          RecipeSectionRow
                        >(
                          currentTable: table,
                          referencedTable: $$RecipesTableReferences
                              ._recipeSectionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RecipesTableReferences(
                                db,
                                table,
                                p0,
                              ).recipeSectionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.recipeId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (recipeIngredientsRefs)
                        await $_getPrefetchedData<
                          RecipeRow,
                          $RecipesTable,
                          RecipeIngredientRow
                        >(
                          currentTable: table,
                          referencedTable: $$RecipesTableReferences
                              ._recipeIngredientsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RecipesTableReferences(
                                db,
                                table,
                                p0,
                              ).recipeIngredientsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.recipeId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (recipeStepsRefs)
                        await $_getPrefetchedData<
                          RecipeRow,
                          $RecipesTable,
                          RecipeStepRow
                        >(
                          currentTable: table,
                          referencedTable: $$RecipesTableReferences
                              ._recipeStepsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RecipesTableReferences(
                                db,
                                table,
                                p0,
                              ).recipeStepsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.recipeId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (recipeFavoritesRefs)
                        await $_getPrefetchedData<
                          RecipeRow,
                          $RecipesTable,
                          RecipeFavoriteRow
                        >(
                          currentTable: table,
                          referencedTable: $$RecipesTableReferences
                              ._recipeFavoritesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RecipesTableReferences(
                                db,
                                table,
                                p0,
                              ).recipeFavoritesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.recipeId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (recipeCollectionsRefs)
                        await $_getPrefetchedData<
                          RecipeRow,
                          $RecipesTable,
                          RecipeCollectionRow
                        >(
                          currentTable: table,
                          referencedTable: $$RecipesTableReferences
                              ._recipeCollectionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RecipesTableReferences(
                                db,
                                table,
                                p0,
                              ).recipeCollectionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.recipeId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (recipePhotosRefs)
                        await $_getPrefetchedData<
                          RecipeRow,
                          $RecipesTable,
                          RecipePhotoRow
                        >(
                          currentTable: table,
                          referencedTable: $$RecipesTableReferences
                              ._recipePhotosRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RecipesTableReferences(
                                db,
                                table,
                                p0,
                              ).recipePhotosRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.recipeId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$RecipesTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $RecipesTable,
      RecipeRow,
      $$RecipesTableFilterComposer,
      $$RecipesTableOrderingComposer,
      $$RecipesTableAnnotationComposer,
      $$RecipesTableCreateCompanionBuilder,
      $$RecipesTableUpdateCompanionBuilder,
      (RecipeRow, $$RecipesTableReferences),
      RecipeRow,
      PrefetchHooks Function({
        bool recipeSectionsRefs,
        bool recipeIngredientsRefs,
        bool recipeStepsRefs,
        bool recipeFavoritesRefs,
        bool recipeCollectionsRefs,
        bool recipePhotosRefs,
      })
    >;
typedef $$RecipeSectionsTableCreateCompanionBuilder =
    RecipeSectionsCompanion Function({
      required String id,
      required String recipeId,
      Value<String> name,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$RecipeSectionsTableUpdateCompanionBuilder =
    RecipeSectionsCompanion Function({
      Value<String> id,
      Value<String> recipeId,
      Value<String> name,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$RecipeSectionsTableReferences
    extends
        BaseReferences<
          _$HearthDatabase,
          $RecipeSectionsTable,
          RecipeSectionRow
        > {
  $$RecipeSectionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RecipesTable _recipeIdTable(_$HearthDatabase db) =>
      db.recipes.createAlias('recipe_sections__recipe_id__recipes__id');

  $$RecipesTableProcessedTableManager get recipeId {
    final $_column = $_itemColumn<String>('recipe_id')!;

    final manager = $$RecipesTableTableManager(
      $_db,
      $_db.recipes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recipeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RecipeSectionsTableFilterComposer
    extends Composer<_$HearthDatabase, $RecipeSectionsTable> {
  $$RecipeSectionsTableFilterComposer({
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

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$RecipesTableFilterComposer get recipeId {
    final $$RecipesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableFilterComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeSectionsTableOrderingComposer
    extends Composer<_$HearthDatabase, $RecipeSectionsTable> {
  $$RecipeSectionsTableOrderingComposer({
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

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$RecipesTableOrderingComposer get recipeId {
    final $$RecipesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableOrderingComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeSectionsTableAnnotationComposer
    extends Composer<_$HearthDatabase, $RecipeSectionsTable> {
  $$RecipeSectionsTableAnnotationComposer({
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

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$RecipesTableAnnotationComposer get recipeId {
    final $$RecipesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeSectionsTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $RecipeSectionsTable,
          RecipeSectionRow,
          $$RecipeSectionsTableFilterComposer,
          $$RecipeSectionsTableOrderingComposer,
          $$RecipeSectionsTableAnnotationComposer,
          $$RecipeSectionsTableCreateCompanionBuilder,
          $$RecipeSectionsTableUpdateCompanionBuilder,
          (RecipeSectionRow, $$RecipeSectionsTableReferences),
          RecipeSectionRow,
          PrefetchHooks Function({bool recipeId})
        > {
  $$RecipeSectionsTableTableManager(
    _$HearthDatabase db,
    $RecipeSectionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecipeSectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecipeSectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecipeSectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> recipeId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipeSectionsCompanion(
                id: id,
                recipeId: recipeId,
                name: name,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String recipeId,
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipeSectionsCompanion.insert(
                id: id,
                recipeId: recipeId,
                name: name,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecipeSectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({recipeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (recipeId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.recipeId,
                        referencedTable: $$RecipeSectionsTableReferences
                            ._recipeIdTable(db),
                        referencedColumn: $$RecipeSectionsTableReferences
                            ._recipeIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RecipeSectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $RecipeSectionsTable,
      RecipeSectionRow,
      $$RecipeSectionsTableFilterComposer,
      $$RecipeSectionsTableOrderingComposer,
      $$RecipeSectionsTableAnnotationComposer,
      $$RecipeSectionsTableCreateCompanionBuilder,
      $$RecipeSectionsTableUpdateCompanionBuilder,
      (RecipeSectionRow, $$RecipeSectionsTableReferences),
      RecipeSectionRow,
      PrefetchHooks Function({bool recipeId})
    >;
typedef $$RecipeIngredientsTableCreateCompanionBuilder =
    RecipeIngredientsCompanion Function({
      required String id,
      required String recipeId,
      required String sectionId,
      Value<String?> foodId,
      Value<String?> rawText,
      required String name,
      Value<double?> quantityCanonical,
      Value<String?> quantityKind,
      Value<String?> quantityUnit,
      Value<String?> prepNote,
      Value<bool> isOptional,
      Value<bool> needsNoMatch,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$RecipeIngredientsTableUpdateCompanionBuilder =
    RecipeIngredientsCompanion Function({
      Value<String> id,
      Value<String> recipeId,
      Value<String> sectionId,
      Value<String?> foodId,
      Value<String?> rawText,
      Value<String> name,
      Value<double?> quantityCanonical,
      Value<String?> quantityKind,
      Value<String?> quantityUnit,
      Value<String?> prepNote,
      Value<bool> isOptional,
      Value<bool> needsNoMatch,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$RecipeIngredientsTableReferences
    extends
        BaseReferences<
          _$HearthDatabase,
          $RecipeIngredientsTable,
          RecipeIngredientRow
        > {
  $$RecipeIngredientsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RecipesTable _recipeIdTable(_$HearthDatabase db) =>
      db.recipes.createAlias('recipe_ingredients__recipe_id__recipes__id');

  $$RecipesTableProcessedTableManager get recipeId {
    final $_column = $_itemColumn<String>('recipe_id')!;

    final manager = $$RecipesTableTableManager(
      $_db,
      $_db.recipes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recipeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RecipeIngredientsTableFilterComposer
    extends Composer<_$HearthDatabase, $RecipeIngredientsTable> {
  $$RecipeIngredientsTableFilterComposer({
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

  ColumnFilters<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get foodId => $composableBuilder(
    column: $table.foodId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get quantityCanonical => $composableBuilder(
    column: $table.quantityCanonical,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quantityKind => $composableBuilder(
    column: $table.quantityKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quantityUnit => $composableBuilder(
    column: $table.quantityUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prepNote => $composableBuilder(
    column: $table.prepNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOptional => $composableBuilder(
    column: $table.isOptional,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsNoMatch => $composableBuilder(
    column: $table.needsNoMatch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$RecipesTableFilterComposer get recipeId {
    final $$RecipesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableFilterComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeIngredientsTableOrderingComposer
    extends Composer<_$HearthDatabase, $RecipeIngredientsTable> {
  $$RecipeIngredientsTableOrderingComposer({
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

  ColumnOrderings<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get foodId => $composableBuilder(
    column: $table.foodId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get quantityCanonical => $composableBuilder(
    column: $table.quantityCanonical,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quantityKind => $composableBuilder(
    column: $table.quantityKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quantityUnit => $composableBuilder(
    column: $table.quantityUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prepNote => $composableBuilder(
    column: $table.prepNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOptional => $composableBuilder(
    column: $table.isOptional,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsNoMatch => $composableBuilder(
    column: $table.needsNoMatch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$RecipesTableOrderingComposer get recipeId {
    final $$RecipesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableOrderingComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeIngredientsTableAnnotationComposer
    extends Composer<_$HearthDatabase, $RecipeIngredientsTable> {
  $$RecipeIngredientsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sectionId =>
      $composableBuilder(column: $table.sectionId, builder: (column) => column);

  GeneratedColumn<String> get foodId =>
      $composableBuilder(column: $table.foodId, builder: (column) => column);

  GeneratedColumn<String> get rawText =>
      $composableBuilder(column: $table.rawText, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get quantityCanonical => $composableBuilder(
    column: $table.quantityCanonical,
    builder: (column) => column,
  );

  GeneratedColumn<String> get quantityKind => $composableBuilder(
    column: $table.quantityKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get quantityUnit => $composableBuilder(
    column: $table.quantityUnit,
    builder: (column) => column,
  );

  GeneratedColumn<String> get prepNote =>
      $composableBuilder(column: $table.prepNote, builder: (column) => column);

  GeneratedColumn<bool> get isOptional => $composableBuilder(
    column: $table.isOptional,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get needsNoMatch => $composableBuilder(
    column: $table.needsNoMatch,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$RecipesTableAnnotationComposer get recipeId {
    final $$RecipesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeIngredientsTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $RecipeIngredientsTable,
          RecipeIngredientRow,
          $$RecipeIngredientsTableFilterComposer,
          $$RecipeIngredientsTableOrderingComposer,
          $$RecipeIngredientsTableAnnotationComposer,
          $$RecipeIngredientsTableCreateCompanionBuilder,
          $$RecipeIngredientsTableUpdateCompanionBuilder,
          (RecipeIngredientRow, $$RecipeIngredientsTableReferences),
          RecipeIngredientRow,
          PrefetchHooks Function({bool recipeId})
        > {
  $$RecipeIngredientsTableTableManager(
    _$HearthDatabase db,
    $RecipeIngredientsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecipeIngredientsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecipeIngredientsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecipeIngredientsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> recipeId = const Value.absent(),
                Value<String> sectionId = const Value.absent(),
                Value<String?> foodId = const Value.absent(),
                Value<String?> rawText = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double?> quantityCanonical = const Value.absent(),
                Value<String?> quantityKind = const Value.absent(),
                Value<String?> quantityUnit = const Value.absent(),
                Value<String?> prepNote = const Value.absent(),
                Value<bool> isOptional = const Value.absent(),
                Value<bool> needsNoMatch = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipeIngredientsCompanion(
                id: id,
                recipeId: recipeId,
                sectionId: sectionId,
                foodId: foodId,
                rawText: rawText,
                name: name,
                quantityCanonical: quantityCanonical,
                quantityKind: quantityKind,
                quantityUnit: quantityUnit,
                prepNote: prepNote,
                isOptional: isOptional,
                needsNoMatch: needsNoMatch,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String recipeId,
                required String sectionId,
                Value<String?> foodId = const Value.absent(),
                Value<String?> rawText = const Value.absent(),
                required String name,
                Value<double?> quantityCanonical = const Value.absent(),
                Value<String?> quantityKind = const Value.absent(),
                Value<String?> quantityUnit = const Value.absent(),
                Value<String?> prepNote = const Value.absent(),
                Value<bool> isOptional = const Value.absent(),
                Value<bool> needsNoMatch = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipeIngredientsCompanion.insert(
                id: id,
                recipeId: recipeId,
                sectionId: sectionId,
                foodId: foodId,
                rawText: rawText,
                name: name,
                quantityCanonical: quantityCanonical,
                quantityKind: quantityKind,
                quantityUnit: quantityUnit,
                prepNote: prepNote,
                isOptional: isOptional,
                needsNoMatch: needsNoMatch,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecipeIngredientsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({recipeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (recipeId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.recipeId,
                        referencedTable: $$RecipeIngredientsTableReferences
                            ._recipeIdTable(db),
                        referencedColumn: $$RecipeIngredientsTableReferences
                            ._recipeIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RecipeIngredientsTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $RecipeIngredientsTable,
      RecipeIngredientRow,
      $$RecipeIngredientsTableFilterComposer,
      $$RecipeIngredientsTableOrderingComposer,
      $$RecipeIngredientsTableAnnotationComposer,
      $$RecipeIngredientsTableCreateCompanionBuilder,
      $$RecipeIngredientsTableUpdateCompanionBuilder,
      (RecipeIngredientRow, $$RecipeIngredientsTableReferences),
      RecipeIngredientRow,
      PrefetchHooks Function({bool recipeId})
    >;
typedef $$RecipeStepsTableCreateCompanionBuilder =
    RecipeStepsCompanion Function({
      required String id,
      required String recipeId,
      required String sectionId,
      required int stepNumber,
      required String body,
      Value<int?> timerSeconds,
      Value<int> rowid,
    });
typedef $$RecipeStepsTableUpdateCompanionBuilder =
    RecipeStepsCompanion Function({
      Value<String> id,
      Value<String> recipeId,
      Value<String> sectionId,
      Value<int> stepNumber,
      Value<String> body,
      Value<int?> timerSeconds,
      Value<int> rowid,
    });

final class $$RecipeStepsTableReferences
    extends BaseReferences<_$HearthDatabase, $RecipeStepsTable, RecipeStepRow> {
  $$RecipeStepsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $RecipesTable _recipeIdTable(_$HearthDatabase db) =>
      db.recipes.createAlias('recipe_steps__recipe_id__recipes__id');

  $$RecipesTableProcessedTableManager get recipeId {
    final $_column = $_itemColumn<String>('recipe_id')!;

    final manager = $$RecipesTableTableManager(
      $_db,
      $_db.recipes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recipeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RecipeStepsTableFilterComposer
    extends Composer<_$HearthDatabase, $RecipeStepsTable> {
  $$RecipeStepsTableFilterComposer({
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

  ColumnFilters<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stepNumber => $composableBuilder(
    column: $table.stepNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timerSeconds => $composableBuilder(
    column: $table.timerSeconds,
    builder: (column) => ColumnFilters(column),
  );

  $$RecipesTableFilterComposer get recipeId {
    final $$RecipesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableFilterComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeStepsTableOrderingComposer
    extends Composer<_$HearthDatabase, $RecipeStepsTable> {
  $$RecipeStepsTableOrderingComposer({
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

  ColumnOrderings<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stepNumber => $composableBuilder(
    column: $table.stepNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timerSeconds => $composableBuilder(
    column: $table.timerSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  $$RecipesTableOrderingComposer get recipeId {
    final $$RecipesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableOrderingComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeStepsTableAnnotationComposer
    extends Composer<_$HearthDatabase, $RecipeStepsTable> {
  $$RecipeStepsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sectionId =>
      $composableBuilder(column: $table.sectionId, builder: (column) => column);

  GeneratedColumn<int> get stepNumber => $composableBuilder(
    column: $table.stepNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get timerSeconds => $composableBuilder(
    column: $table.timerSeconds,
    builder: (column) => column,
  );

  $$RecipesTableAnnotationComposer get recipeId {
    final $$RecipesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeStepsTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $RecipeStepsTable,
          RecipeStepRow,
          $$RecipeStepsTableFilterComposer,
          $$RecipeStepsTableOrderingComposer,
          $$RecipeStepsTableAnnotationComposer,
          $$RecipeStepsTableCreateCompanionBuilder,
          $$RecipeStepsTableUpdateCompanionBuilder,
          (RecipeStepRow, $$RecipeStepsTableReferences),
          RecipeStepRow,
          PrefetchHooks Function({bool recipeId})
        > {
  $$RecipeStepsTableTableManager(_$HearthDatabase db, $RecipeStepsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecipeStepsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecipeStepsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecipeStepsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> recipeId = const Value.absent(),
                Value<String> sectionId = const Value.absent(),
                Value<int> stepNumber = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int?> timerSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipeStepsCompanion(
                id: id,
                recipeId: recipeId,
                sectionId: sectionId,
                stepNumber: stepNumber,
                body: body,
                timerSeconds: timerSeconds,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String recipeId,
                required String sectionId,
                required int stepNumber,
                required String body,
                Value<int?> timerSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipeStepsCompanion.insert(
                id: id,
                recipeId: recipeId,
                sectionId: sectionId,
                stepNumber: stepNumber,
                body: body,
                timerSeconds: timerSeconds,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecipeStepsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({recipeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (recipeId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.recipeId,
                        referencedTable: $$RecipeStepsTableReferences
                            ._recipeIdTable(db),
                        referencedColumn: $$RecipeStepsTableReferences
                            ._recipeIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RecipeStepsTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $RecipeStepsTable,
      RecipeStepRow,
      $$RecipeStepsTableFilterComposer,
      $$RecipeStepsTableOrderingComposer,
      $$RecipeStepsTableAnnotationComposer,
      $$RecipeStepsTableCreateCompanionBuilder,
      $$RecipeStepsTableUpdateCompanionBuilder,
      (RecipeStepRow, $$RecipeStepsTableReferences),
      RecipeStepRow,
      PrefetchHooks Function({bool recipeId})
    >;
typedef $$RecipeFavoritesTableCreateCompanionBuilder =
    RecipeFavoritesCompanion Function({
      required String userId,
      required String recipeId,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$RecipeFavoritesTableUpdateCompanionBuilder =
    RecipeFavoritesCompanion Function({
      Value<String> userId,
      Value<String> recipeId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$RecipeFavoritesTableReferences
    extends
        BaseReferences<
          _$HearthDatabase,
          $RecipeFavoritesTable,
          RecipeFavoriteRow
        > {
  $$RecipeFavoritesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RecipesTable _recipeIdTable(_$HearthDatabase db) =>
      db.recipes.createAlias('recipe_favorites__recipe_id__recipes__id');

  $$RecipesTableProcessedTableManager get recipeId {
    final $_column = $_itemColumn<String>('recipe_id')!;

    final manager = $$RecipesTableTableManager(
      $_db,
      $_db.recipes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recipeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RecipeFavoritesTableFilterComposer
    extends Composer<_$HearthDatabase, $RecipeFavoritesTable> {
  $$RecipeFavoritesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$RecipesTableFilterComposer get recipeId {
    final $$RecipesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableFilterComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeFavoritesTableOrderingComposer
    extends Composer<_$HearthDatabase, $RecipeFavoritesTable> {
  $$RecipeFavoritesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$RecipesTableOrderingComposer get recipeId {
    final $$RecipesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableOrderingComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeFavoritesTableAnnotationComposer
    extends Composer<_$HearthDatabase, $RecipeFavoritesTable> {
  $$RecipeFavoritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$RecipesTableAnnotationComposer get recipeId {
    final $$RecipesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeFavoritesTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $RecipeFavoritesTable,
          RecipeFavoriteRow,
          $$RecipeFavoritesTableFilterComposer,
          $$RecipeFavoritesTableOrderingComposer,
          $$RecipeFavoritesTableAnnotationComposer,
          $$RecipeFavoritesTableCreateCompanionBuilder,
          $$RecipeFavoritesTableUpdateCompanionBuilder,
          (RecipeFavoriteRow, $$RecipeFavoritesTableReferences),
          RecipeFavoriteRow,
          PrefetchHooks Function({bool recipeId})
        > {
  $$RecipeFavoritesTableTableManager(
    _$HearthDatabase db,
    $RecipeFavoritesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecipeFavoritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecipeFavoritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecipeFavoritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> recipeId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipeFavoritesCompanion(
                userId: userId,
                recipeId: recipeId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String recipeId,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => RecipeFavoritesCompanion.insert(
                userId: userId,
                recipeId: recipeId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecipeFavoritesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({recipeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (recipeId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.recipeId,
                        referencedTable: $$RecipeFavoritesTableReferences
                            ._recipeIdTable(db),
                        referencedColumn: $$RecipeFavoritesTableReferences
                            ._recipeIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RecipeFavoritesTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $RecipeFavoritesTable,
      RecipeFavoriteRow,
      $$RecipeFavoritesTableFilterComposer,
      $$RecipeFavoritesTableOrderingComposer,
      $$RecipeFavoritesTableAnnotationComposer,
      $$RecipeFavoritesTableCreateCompanionBuilder,
      $$RecipeFavoritesTableUpdateCompanionBuilder,
      (RecipeFavoriteRow, $$RecipeFavoritesTableReferences),
      RecipeFavoriteRow,
      PrefetchHooks Function({bool recipeId})
    >;
typedef $$CollectionsTableCreateCompanionBuilder =
    CollectionsCompanion Function({
      required String id,
      required String householdId,
      required String name,
      Value<int> sortOrder,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CollectionsTableUpdateCompanionBuilder =
    CollectionsCompanion Function({
      Value<String> id,
      Value<String> householdId,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$CollectionsTableReferences
    extends BaseReferences<_$HearthDatabase, $CollectionsTable, CollectionRow> {
  $$CollectionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$RecipeCollectionsTable, List<RecipeCollectionRow>>
  _recipeCollectionsRefsTable(_$HearthDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.recipeCollections,
        aliasName: 'collections__id__recipe_collections__collection_id',
      );

  $$RecipeCollectionsTableProcessedTableManager get recipeCollectionsRefs {
    final manager = $$RecipeCollectionsTableTableManager(
      $_db,
      $_db.recipeCollections,
    ).filter((f) => f.collectionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _recipeCollectionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CollectionsTableFilterComposer
    extends Composer<_$HearthDatabase, $CollectionsTable> {
  $$CollectionsTableFilterComposer({
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

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> recipeCollectionsRefs(
    Expression<bool> Function($$RecipeCollectionsTableFilterComposer f) f,
  ) {
    final $$RecipeCollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeCollections,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeCollectionsTableFilterComposer(
            $db: $db,
            $table: $db.recipeCollections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CollectionsTableOrderingComposer
    extends Composer<_$HearthDatabase, $CollectionsTable> {
  $$CollectionsTableOrderingComposer({
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

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionsTableAnnotationComposer
    extends Composer<_$HearthDatabase, $CollectionsTable> {
  $$CollectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> recipeCollectionsRefs<T extends Object>(
    Expression<T> Function($$RecipeCollectionsTableAnnotationComposer a) f,
  ) {
    final $$RecipeCollectionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.recipeCollections,
          getReferencedColumn: (t) => t.collectionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RecipeCollectionsTableAnnotationComposer(
                $db: $db,
                $table: $db.recipeCollections,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$CollectionsTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $CollectionsTable,
          CollectionRow,
          $$CollectionsTableFilterComposer,
          $$CollectionsTableOrderingComposer,
          $$CollectionsTableAnnotationComposer,
          $$CollectionsTableCreateCompanionBuilder,
          $$CollectionsTableUpdateCompanionBuilder,
          (CollectionRow, $$CollectionsTableReferences),
          CollectionRow,
          PrefetchHooks Function({bool recipeCollectionsRefs})
        > {
  $$CollectionsTableTableManager(_$HearthDatabase db, $CollectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion(
                id: id,
                householdId: householdId,
                name: name,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion.insert(
                id: id,
                householdId: householdId,
                name: name,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CollectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({recipeCollectionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (recipeCollectionsRefs) db.recipeCollections,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (recipeCollectionsRefs)
                    await $_getPrefetchedData<
                      CollectionRow,
                      $CollectionsTable,
                      RecipeCollectionRow
                    >(
                      currentTable: table,
                      referencedTable: $$CollectionsTableReferences
                          ._recipeCollectionsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CollectionsTableReferences(
                            db,
                            table,
                            p0,
                          ).recipeCollectionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.collectionId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CollectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $CollectionsTable,
      CollectionRow,
      $$CollectionsTableFilterComposer,
      $$CollectionsTableOrderingComposer,
      $$CollectionsTableAnnotationComposer,
      $$CollectionsTableCreateCompanionBuilder,
      $$CollectionsTableUpdateCompanionBuilder,
      (CollectionRow, $$CollectionsTableReferences),
      CollectionRow,
      PrefetchHooks Function({bool recipeCollectionsRefs})
    >;
typedef $$RecipeCollectionsTableCreateCompanionBuilder =
    RecipeCollectionsCompanion Function({
      required String collectionId,
      required String recipeId,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$RecipeCollectionsTableUpdateCompanionBuilder =
    RecipeCollectionsCompanion Function({
      Value<String> collectionId,
      Value<String> recipeId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$RecipeCollectionsTableReferences
    extends
        BaseReferences<
          _$HearthDatabase,
          $RecipeCollectionsTable,
          RecipeCollectionRow
        > {
  $$RecipeCollectionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CollectionsTable _collectionIdTable(_$HearthDatabase db) => db
      .collections
      .createAlias('recipe_collections__collection_id__collections__id');

  $$CollectionsTableProcessedTableManager get collectionId {
    final $_column = $_itemColumn<String>('collection_id')!;

    final manager = $$CollectionsTableTableManager(
      $_db,
      $_db.collections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_collectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $RecipesTable _recipeIdTable(_$HearthDatabase db) =>
      db.recipes.createAlias('recipe_collections__recipe_id__recipes__id');

  $$RecipesTableProcessedTableManager get recipeId {
    final $_column = $_itemColumn<String>('recipe_id')!;

    final manager = $$RecipesTableTableManager(
      $_db,
      $_db.recipes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recipeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RecipeCollectionsTableFilterComposer
    extends Composer<_$HearthDatabase, $RecipeCollectionsTable> {
  $$RecipeCollectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CollectionsTableFilterComposer get collectionId {
    final $$CollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableFilterComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecipesTableFilterComposer get recipeId {
    final $$RecipesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableFilterComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeCollectionsTableOrderingComposer
    extends Composer<_$HearthDatabase, $RecipeCollectionsTable> {
  $$RecipeCollectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CollectionsTableOrderingComposer get collectionId {
    final $$CollectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableOrderingComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecipesTableOrderingComposer get recipeId {
    final $$RecipesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableOrderingComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeCollectionsTableAnnotationComposer
    extends Composer<_$HearthDatabase, $RecipeCollectionsTable> {
  $$RecipeCollectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CollectionsTableAnnotationComposer get collectionId {
    final $$CollectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecipesTableAnnotationComposer get recipeId {
    final $$RecipesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeCollectionsTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $RecipeCollectionsTable,
          RecipeCollectionRow,
          $$RecipeCollectionsTableFilterComposer,
          $$RecipeCollectionsTableOrderingComposer,
          $$RecipeCollectionsTableAnnotationComposer,
          $$RecipeCollectionsTableCreateCompanionBuilder,
          $$RecipeCollectionsTableUpdateCompanionBuilder,
          (RecipeCollectionRow, $$RecipeCollectionsTableReferences),
          RecipeCollectionRow,
          PrefetchHooks Function({bool collectionId, bool recipeId})
        > {
  $$RecipeCollectionsTableTableManager(
    _$HearthDatabase db,
    $RecipeCollectionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecipeCollectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecipeCollectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecipeCollectionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> collectionId = const Value.absent(),
                Value<String> recipeId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipeCollectionsCompanion(
                collectionId: collectionId,
                recipeId: recipeId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String collectionId,
                required String recipeId,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => RecipeCollectionsCompanion.insert(
                collectionId: collectionId,
                recipeId: recipeId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecipeCollectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({collectionId = false, recipeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (collectionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.collectionId,
                        referencedTable: $$RecipeCollectionsTableReferences
                            ._collectionIdTable(db),
                        referencedColumn: $$RecipeCollectionsTableReferences
                            ._collectionIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (recipeId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.recipeId,
                        referencedTable: $$RecipeCollectionsTableReferences
                            ._recipeIdTable(db),
                        referencedColumn: $$RecipeCollectionsTableReferences
                            ._recipeIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RecipeCollectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $RecipeCollectionsTable,
      RecipeCollectionRow,
      $$RecipeCollectionsTableFilterComposer,
      $$RecipeCollectionsTableOrderingComposer,
      $$RecipeCollectionsTableAnnotationComposer,
      $$RecipeCollectionsTableCreateCompanionBuilder,
      $$RecipeCollectionsTableUpdateCompanionBuilder,
      (RecipeCollectionRow, $$RecipeCollectionsTableReferences),
      RecipeCollectionRow,
      PrefetchHooks Function({bool collectionId, bool recipeId})
    >;
typedef $$FoodsTableCreateCompanionBuilder = FoodsCompanion Function({
  required String id,
  Value<String?> householdId,
  required String name,
  Value<String?> brand,
  Value<String?> storeTag,
  Value<String?> walmartItemId,
  Value<double?> packCanonical,
  Value<String?> packKind,
  Value<String?> packUnit,
  Value<String?> barcode,
  Value<double?> gramsPerMillilitre,
  Value<String> source,
  Value<bool> macrosOverridden,
  Value<bool> isDefault,
  Value<bool> isZeroCalorie,
  Value<bool> isDeleted,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$FoodsTableUpdateCompanionBuilder = FoodsCompanion Function({
  Value<String> id,
  Value<String?> householdId,
  Value<String> name,
  Value<String?> brand,
  Value<String?> storeTag,
  Value<String?> walmartItemId,
  Value<double?> packCanonical,
  Value<String?> packKind,
  Value<String?> packUnit,
  Value<String?> barcode,
  Value<double?> gramsPerMillilitre,
  Value<String> source,
  Value<bool> macrosOverridden,
  Value<bool> isDefault,
  Value<bool> isZeroCalorie,
  Value<bool> isDeleted,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

final class $$FoodsTableReferences
    extends BaseReferences<_$HearthDatabase, $FoodsTable, FoodRow> {
  $$FoodsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $FoodServingOptionsTable,
    List<FoodServingOptionRow>
  >
  _foodServingOptionsRefsTable(_$HearthDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.foodServingOptions,
        aliasName: 'foods__id__food_serving_options__food_id',
      );

  $$FoodServingOptionsTableProcessedTableManager get foodServingOptionsRefs {
    final manager = $$FoodServingOptionsTableTableManager(
      $_db,
      $_db.foodServingOptions,
    ).filter((f) => f.foodId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _foodServingOptionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$IngredientMatchesTable, List<IngredientMatchRow>>
  _ingredientMatchesRefsTable(_$HearthDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.ingredientMatches,
        aliasName: 'foods__id__ingredient_matches__food_id',
      );

  $$IngredientMatchesTableProcessedTableManager get ingredientMatchesRefs {
    final manager = $$IngredientMatchesTableTableManager(
      $_db,
      $_db.ingredientMatches,
    ).filter((f) => f.foodId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _ingredientMatchesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FoodsTableFilterComposer
    extends Composer<_$HearthDatabase, $FoodsTable> {
  $$FoodsTableFilterComposer({
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

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeTag => $composableBuilder(
    column: $table.storeTag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get walmartItemId => $composableBuilder(
    column: $table.walmartItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get packCanonical => $composableBuilder(
    column: $table.packCanonical,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packKind => $composableBuilder(
    column: $table.packKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packUnit => $composableBuilder(
    column: $table.packUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gramsPerMillilitre => $composableBuilder(
    column: $table.gramsPerMillilitre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get macrosOverridden => $composableBuilder(
    column: $table.macrosOverridden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isZeroCalorie => $composableBuilder(
    column: $table.isZeroCalorie,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> foodServingOptionsRefs(
    Expression<bool> Function($$FoodServingOptionsTableFilterComposer f) f,
  ) {
    final $$FoodServingOptionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.foodServingOptions,
      getReferencedColumn: (t) => t.foodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodServingOptionsTableFilterComposer(
            $db: $db,
            $table: $db.foodServingOptions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> ingredientMatchesRefs(
    Expression<bool> Function($$IngredientMatchesTableFilterComposer f) f,
  ) {
    final $$IngredientMatchesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ingredientMatches,
      getReferencedColumn: (t) => t.foodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IngredientMatchesTableFilterComposer(
            $db: $db,
            $table: $db.ingredientMatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FoodsTableOrderingComposer
    extends Composer<_$HearthDatabase, $FoodsTable> {
  $$FoodsTableOrderingComposer({
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

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeTag => $composableBuilder(
    column: $table.storeTag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get walmartItemId => $composableBuilder(
    column: $table.walmartItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get packCanonical => $composableBuilder(
    column: $table.packCanonical,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packKind => $composableBuilder(
    column: $table.packKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packUnit => $composableBuilder(
    column: $table.packUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gramsPerMillilitre => $composableBuilder(
    column: $table.gramsPerMillilitre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get macrosOverridden => $composableBuilder(
    column: $table.macrosOverridden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isZeroCalorie => $composableBuilder(
    column: $table.isZeroCalorie,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoodsTableAnnotationComposer
    extends Composer<_$HearthDatabase, $FoodsTable> {
  $$FoodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<String> get storeTag =>
      $composableBuilder(column: $table.storeTag, builder: (column) => column);

  GeneratedColumn<String> get walmartItemId => $composableBuilder(
    column: $table.walmartItemId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get packCanonical => $composableBuilder(
    column: $table.packCanonical,
    builder: (column) => column,
  );

  GeneratedColumn<String> get packKind =>
      $composableBuilder(column: $table.packKind, builder: (column) => column);

  GeneratedColumn<String> get packUnit =>
      $composableBuilder(column: $table.packUnit, builder: (column) => column);

  GeneratedColumn<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<double> get gramsPerMillilitre => $composableBuilder(
    column: $table.gramsPerMillilitre,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get macrosOverridden => $composableBuilder(
    column: $table.macrosOverridden,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<bool> get isZeroCalorie => $composableBuilder(
    column: $table.isZeroCalorie,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> foodServingOptionsRefs<T extends Object>(
    Expression<T> Function($$FoodServingOptionsTableAnnotationComposer a) f,
  ) {
    final $$FoodServingOptionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.foodServingOptions,
          getReferencedColumn: (t) => t.foodId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$FoodServingOptionsTableAnnotationComposer(
                $db: $db,
                $table: $db.foodServingOptions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> ingredientMatchesRefs<T extends Object>(
    Expression<T> Function($$IngredientMatchesTableAnnotationComposer a) f,
  ) {
    final $$IngredientMatchesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.ingredientMatches,
          getReferencedColumn: (t) => t.foodId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$IngredientMatchesTableAnnotationComposer(
                $db: $db,
                $table: $db.ingredientMatches,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$FoodsTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $FoodsTable,
          FoodRow,
          $$FoodsTableFilterComposer,
          $$FoodsTableOrderingComposer,
          $$FoodsTableAnnotationComposer,
          $$FoodsTableCreateCompanionBuilder,
          $$FoodsTableUpdateCompanionBuilder,
          (FoodRow, $$FoodsTableReferences),
          FoodRow,
          PrefetchHooks Function({
            bool foodServingOptionsRefs,
            bool ingredientMatchesRefs,
          })
        > {
  $$FoodsTableTableManager(_$HearthDatabase db, $FoodsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> householdId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> brand = const Value.absent(),
                Value<String?> storeTag = const Value.absent(),
                Value<String?> walmartItemId = const Value.absent(),
                Value<double?> packCanonical = const Value.absent(),
                Value<String?> packKind = const Value.absent(),
                Value<String?> packUnit = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<double?> gramsPerMillilitre = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> macrosOverridden = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<bool> isZeroCalorie = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoodsCompanion(
                id: id,
                householdId: householdId,
                name: name,
                brand: brand,
                storeTag: storeTag,
                walmartItemId: walmartItemId,
                packCanonical: packCanonical,
                packKind: packKind,
                packUnit: packUnit,
                barcode: barcode,
                gramsPerMillilitre: gramsPerMillilitre,
                source: source,
                macrosOverridden: macrosOverridden,
                isDefault: isDefault,
                isZeroCalorie: isZeroCalorie,
                isDeleted: isDeleted,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> householdId = const Value.absent(),
                required String name,
                Value<String?> brand = const Value.absent(),
                Value<String?> storeTag = const Value.absent(),
                Value<String?> walmartItemId = const Value.absent(),
                Value<double?> packCanonical = const Value.absent(),
                Value<String?> packKind = const Value.absent(),
                Value<String?> packUnit = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<double?> gramsPerMillilitre = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> macrosOverridden = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<bool> isZeroCalorie = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => FoodsCompanion.insert(
                id: id,
                householdId: householdId,
                name: name,
                brand: brand,
                storeTag: storeTag,
                walmartItemId: walmartItemId,
                packCanonical: packCanonical,
                packKind: packKind,
                packUnit: packUnit,
                barcode: barcode,
                gramsPerMillilitre: gramsPerMillilitre,
                source: source,
                macrosOverridden: macrosOverridden,
                isDefault: isDefault,
                isZeroCalorie: isZeroCalorie,
                isDeleted: isDeleted,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$FoodsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                foodServingOptionsRefs = false,
                ingredientMatchesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (foodServingOptionsRefs) db.foodServingOptions,
                    if (ingredientMatchesRefs) db.ingredientMatches,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (foodServingOptionsRefs)
                        await $_getPrefetchedData<
                          FoodRow,
                          $FoodsTable,
                          FoodServingOptionRow
                        >(
                          currentTable: table,
                          referencedTable: $$FoodsTableReferences
                              ._foodServingOptionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FoodsTableReferences(
                                db,
                                table,
                                p0,
                              ).foodServingOptionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.foodId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (ingredientMatchesRefs)
                        await $_getPrefetchedData<
                          FoodRow,
                          $FoodsTable,
                          IngredientMatchRow
                        >(
                          currentTable: table,
                          referencedTable: $$FoodsTableReferences
                              ._ingredientMatchesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FoodsTableReferences(
                                db,
                                table,
                                p0,
                              ).ingredientMatchesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.foodId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$FoodsTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $FoodsTable,
      FoodRow,
      $$FoodsTableFilterComposer,
      $$FoodsTableOrderingComposer,
      $$FoodsTableAnnotationComposer,
      $$FoodsTableCreateCompanionBuilder,
      $$FoodsTableUpdateCompanionBuilder,
      (FoodRow, $$FoodsTableReferences),
      FoodRow,
      PrefetchHooks Function({
        bool foodServingOptionsRefs,
        bool ingredientMatchesRefs,
      })
    >;
typedef $$FoodServingOptionsTableCreateCompanionBuilder =
    FoodServingOptionsCompanion Function({
      required String id,
      required String foodId,
      required String label,
      required double amountCanonical,
      required String amountKind,
      Value<String?> amountUnit,
      Value<double> kcal,
      Value<double> proteinG,
      Value<double> carbG,
      Value<double> fatG,
      Value<double?> fiberG,
      Value<double?> sodiumMg,
      Value<double?> cholesterolMg,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$FoodServingOptionsTableUpdateCompanionBuilder =
    FoodServingOptionsCompanion Function({
      Value<String> id,
      Value<String> foodId,
      Value<String> label,
      Value<double> amountCanonical,
      Value<String> amountKind,
      Value<String?> amountUnit,
      Value<double> kcal,
      Value<double> proteinG,
      Value<double> carbG,
      Value<double> fatG,
      Value<double?> fiberG,
      Value<double?> sodiumMg,
      Value<double?> cholesterolMg,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$FoodServingOptionsTableReferences
    extends
        BaseReferences<
          _$HearthDatabase,
          $FoodServingOptionsTable,
          FoodServingOptionRow
        > {
  $$FoodServingOptionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $FoodsTable _foodIdTable(_$HearthDatabase db) =>
      db.foods.createAlias('food_serving_options__food_id__foods__id');

  $$FoodsTableProcessedTableManager get foodId {
    final $_column = $_itemColumn<String>('food_id')!;

    final manager = $$FoodsTableTableManager(
      $_db,
      $_db.foods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_foodIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FoodServingOptionsTableFilterComposer
    extends Composer<_$HearthDatabase, $FoodServingOptionsTable> {
  $$FoodServingOptionsTableFilterComposer({
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

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amountCanonical => $composableBuilder(
    column: $table.amountCanonical,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get amountKind => $composableBuilder(
    column: $table.amountKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get amountUnit => $composableBuilder(
    column: $table.amountUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbG => $composableBuilder(
    column: $table.carbG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fiberG => $composableBuilder(
    column: $table.fiberG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sodiumMg => $composableBuilder(
    column: $table.sodiumMg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cholesterolMg => $composableBuilder(
    column: $table.cholesterolMg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$FoodsTableFilterComposer get foodId {
    final $$FoodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.foodId,
      referencedTable: $db.foods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodsTableFilterComposer(
            $db: $db,
            $table: $db.foods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoodServingOptionsTableOrderingComposer
    extends Composer<_$HearthDatabase, $FoodServingOptionsTable> {
  $$FoodServingOptionsTableOrderingComposer({
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

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amountCanonical => $composableBuilder(
    column: $table.amountCanonical,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get amountKind => $composableBuilder(
    column: $table.amountKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get amountUnit => $composableBuilder(
    column: $table.amountUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbG => $composableBuilder(
    column: $table.carbG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fiberG => $composableBuilder(
    column: $table.fiberG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sodiumMg => $composableBuilder(
    column: $table.sodiumMg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cholesterolMg => $composableBuilder(
    column: $table.cholesterolMg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$FoodsTableOrderingComposer get foodId {
    final $$FoodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.foodId,
      referencedTable: $db.foods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodsTableOrderingComposer(
            $db: $db,
            $table: $db.foods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoodServingOptionsTableAnnotationComposer
    extends Composer<_$HearthDatabase, $FoodServingOptionsTable> {
  $$FoodServingOptionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<double> get amountCanonical => $composableBuilder(
    column: $table.amountCanonical,
    builder: (column) => column,
  );

  GeneratedColumn<String> get amountKind => $composableBuilder(
    column: $table.amountKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get amountUnit => $composableBuilder(
    column: $table.amountUnit,
    builder: (column) => column,
  );

  GeneratedColumn<double> get kcal =>
      $composableBuilder(column: $table.kcal, builder: (column) => column);

  GeneratedColumn<double> get proteinG =>
      $composableBuilder(column: $table.proteinG, builder: (column) => column);

  GeneratedColumn<double> get carbG =>
      $composableBuilder(column: $table.carbG, builder: (column) => column);

  GeneratedColumn<double> get fatG =>
      $composableBuilder(column: $table.fatG, builder: (column) => column);

  GeneratedColumn<double> get fiberG =>
      $composableBuilder(column: $table.fiberG, builder: (column) => column);

  GeneratedColumn<double> get sodiumMg =>
      $composableBuilder(column: $table.sodiumMg, builder: (column) => column);

  GeneratedColumn<double> get cholesterolMg => $composableBuilder(
    column: $table.cholesterolMg,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$FoodsTableAnnotationComposer get foodId {
    final $$FoodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.foodId,
      referencedTable: $db.foods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodsTableAnnotationComposer(
            $db: $db,
            $table: $db.foods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoodServingOptionsTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $FoodServingOptionsTable,
          FoodServingOptionRow,
          $$FoodServingOptionsTableFilterComposer,
          $$FoodServingOptionsTableOrderingComposer,
          $$FoodServingOptionsTableAnnotationComposer,
          $$FoodServingOptionsTableCreateCompanionBuilder,
          $$FoodServingOptionsTableUpdateCompanionBuilder,
          (FoodServingOptionRow, $$FoodServingOptionsTableReferences),
          FoodServingOptionRow,
          PrefetchHooks Function({bool foodId})
        > {
  $$FoodServingOptionsTableTableManager(
    _$HearthDatabase db,
    $FoodServingOptionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoodServingOptionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoodServingOptionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoodServingOptionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> foodId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<double> amountCanonical = const Value.absent(),
                Value<String> amountKind = const Value.absent(),
                Value<String?> amountUnit = const Value.absent(),
                Value<double> kcal = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> carbG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                Value<double?> fiberG = const Value.absent(),
                Value<double?> sodiumMg = const Value.absent(),
                Value<double?> cholesterolMg = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoodServingOptionsCompanion(
                id: id,
                foodId: foodId,
                label: label,
                amountCanonical: amountCanonical,
                amountKind: amountKind,
                amountUnit: amountUnit,
                kcal: kcal,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG,
                fiberG: fiberG,
                sodiumMg: sodiumMg,
                cholesterolMg: cholesterolMg,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String foodId,
                required String label,
                required double amountCanonical,
                required String amountKind,
                Value<String?> amountUnit = const Value.absent(),
                Value<double> kcal = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> carbG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                Value<double?> fiberG = const Value.absent(),
                Value<double?> sodiumMg = const Value.absent(),
                Value<double?> cholesterolMg = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoodServingOptionsCompanion.insert(
                id: id,
                foodId: foodId,
                label: label,
                amountCanonical: amountCanonical,
                amountKind: amountKind,
                amountUnit: amountUnit,
                kcal: kcal,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG,
                fiberG: fiberG,
                sodiumMg: sodiumMg,
                cholesterolMg: cholesterolMg,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FoodServingOptionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({foodId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (foodId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.foodId,
                        referencedTable: $$FoodServingOptionsTableReferences
                            ._foodIdTable(db),
                        referencedColumn: $$FoodServingOptionsTableReferences
                            ._foodIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FoodServingOptionsTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $FoodServingOptionsTable,
      FoodServingOptionRow,
      $$FoodServingOptionsTableFilterComposer,
      $$FoodServingOptionsTableOrderingComposer,
      $$FoodServingOptionsTableAnnotationComposer,
      $$FoodServingOptionsTableCreateCompanionBuilder,
      $$FoodServingOptionsTableUpdateCompanionBuilder,
      (FoodServingOptionRow, $$FoodServingOptionsTableReferences),
      FoodServingOptionRow,
      PrefetchHooks Function({bool foodId})
    >;
typedef $$MealPlanDaysTableCreateCompanionBuilder =
    MealPlanDaysCompanion Function({
      required String id,
      required String userId,
      required DateTime day,
      Value<String?> notes,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$MealPlanDaysTableUpdateCompanionBuilder =
    MealPlanDaysCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<DateTime> day,
      Value<String?> notes,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$MealPlanDaysTableReferences
    extends
        BaseReferences<_$HearthDatabase, $MealPlanDaysTable, MealPlanDayRow> {
  $$MealPlanDaysTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MealPlanEntriesTable, List<MealPlanEntryRow>>
  _mealPlanEntriesRefsTable(_$HearthDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.mealPlanEntries,
        aliasName: 'meal_plan_days__id__meal_plan_entries__day_id',
      );

  $$MealPlanEntriesTableProcessedTableManager get mealPlanEntriesRefs {
    final manager = $$MealPlanEntriesTableTableManager(
      $_db,
      $_db.mealPlanEntries,
    ).filter((f) => f.dayId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _mealPlanEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MealPlanDaysTableFilterComposer
    extends Composer<_$HearthDatabase, $MealPlanDaysTable> {
  $$MealPlanDaysTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> mealPlanEntriesRefs(
    Expression<bool> Function($$MealPlanEntriesTableFilterComposer f) f,
  ) {
    final $$MealPlanEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mealPlanEntries,
      getReferencedColumn: (t) => t.dayId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealPlanEntriesTableFilterComposer(
            $db: $db,
            $table: $db.mealPlanEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MealPlanDaysTableOrderingComposer
    extends Composer<_$HearthDatabase, $MealPlanDaysTable> {
  $$MealPlanDaysTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MealPlanDaysTableAnnotationComposer
    extends Composer<_$HearthDatabase, $MealPlanDaysTable> {
  $$MealPlanDaysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<DateTime> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> mealPlanEntriesRefs<T extends Object>(
    Expression<T> Function($$MealPlanEntriesTableAnnotationComposer a) f,
  ) {
    final $$MealPlanEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mealPlanEntries,
      getReferencedColumn: (t) => t.dayId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealPlanEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.mealPlanEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MealPlanDaysTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $MealPlanDaysTable,
          MealPlanDayRow,
          $$MealPlanDaysTableFilterComposer,
          $$MealPlanDaysTableOrderingComposer,
          $$MealPlanDaysTableAnnotationComposer,
          $$MealPlanDaysTableCreateCompanionBuilder,
          $$MealPlanDaysTableUpdateCompanionBuilder,
          (MealPlanDayRow, $$MealPlanDaysTableReferences),
          MealPlanDayRow,
          PrefetchHooks Function({bool mealPlanEntriesRefs})
        > {
  $$MealPlanDaysTableTableManager(_$HearthDatabase db, $MealPlanDaysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MealPlanDaysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MealPlanDaysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MealPlanDaysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<DateTime> day = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MealPlanDaysCompanion(
                id: id,
                userId: userId,
                day: day,
                notes: notes,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required DateTime day,
                Value<String?> notes = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => MealPlanDaysCompanion.insert(
                id: id,
                userId: userId,
                day: day,
                notes: notes,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MealPlanDaysTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({mealPlanEntriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (mealPlanEntriesRefs) db.mealPlanEntries,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (mealPlanEntriesRefs)
                    await $_getPrefetchedData<
                      MealPlanDayRow,
                      $MealPlanDaysTable,
                      MealPlanEntryRow
                    >(
                      currentTable: table,
                      referencedTable: $$MealPlanDaysTableReferences
                          ._mealPlanEntriesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$MealPlanDaysTableReferences(
                            db,
                            table,
                            p0,
                          ).mealPlanEntriesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.dayId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$MealPlanDaysTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $MealPlanDaysTable,
      MealPlanDayRow,
      $$MealPlanDaysTableFilterComposer,
      $$MealPlanDaysTableOrderingComposer,
      $$MealPlanDaysTableAnnotationComposer,
      $$MealPlanDaysTableCreateCompanionBuilder,
      $$MealPlanDaysTableUpdateCompanionBuilder,
      (MealPlanDayRow, $$MealPlanDaysTableReferences),
      MealPlanDayRow,
      PrefetchHooks Function({bool mealPlanEntriesRefs})
    >;
typedef $$MealPlanEntriesTableCreateCompanionBuilder =
    MealPlanEntriesCompanion Function({
      required String id,
      required String dayId,
      required String mealSlot,
      required String refType,
      required String refId,
      required double servings,
      Value<bool> isPlanned,
      Value<bool> isLogged,
      Value<DateTime?> loggedAt,
      Value<String?> macroSnapshot,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$MealPlanEntriesTableUpdateCompanionBuilder =
    MealPlanEntriesCompanion Function({
      Value<String> id,
      Value<String> dayId,
      Value<String> mealSlot,
      Value<String> refType,
      Value<String> refId,
      Value<double> servings,
      Value<bool> isPlanned,
      Value<bool> isLogged,
      Value<DateTime?> loggedAt,
      Value<String?> macroSnapshot,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$MealPlanEntriesTableReferences
    extends
        BaseReferences<
          _$HearthDatabase,
          $MealPlanEntriesTable,
          MealPlanEntryRow
        > {
  $$MealPlanEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MealPlanDaysTable _dayIdTable(_$HearthDatabase db) => db.mealPlanDays
      .createAlias('meal_plan_entries__day_id__meal_plan_days__id');

  $$MealPlanDaysTableProcessedTableManager get dayId {
    final $_column = $_itemColumn<String>('day_id')!;

    final manager = $$MealPlanDaysTableTableManager(
      $_db,
      $_db.mealPlanDays,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_dayIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MealPlanEntriesTableFilterComposer
    extends Composer<_$HearthDatabase, $MealPlanEntriesTable> {
  $$MealPlanEntriesTableFilterComposer({
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

  ColumnFilters<String> get mealSlot => $composableBuilder(
    column: $table.mealSlot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refType => $composableBuilder(
    column: $table.refType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get servings => $composableBuilder(
    column: $table.servings,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPlanned => $composableBuilder(
    column: $table.isPlanned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLogged => $composableBuilder(
    column: $table.isLogged,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get macroSnapshot => $composableBuilder(
    column: $table.macroSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MealPlanDaysTableFilterComposer get dayId {
    final $$MealPlanDaysTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.dayId,
      referencedTable: $db.mealPlanDays,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealPlanDaysTableFilterComposer(
            $db: $db,
            $table: $db.mealPlanDays,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MealPlanEntriesTableOrderingComposer
    extends Composer<_$HearthDatabase, $MealPlanEntriesTable> {
  $$MealPlanEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get mealSlot => $composableBuilder(
    column: $table.mealSlot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refType => $composableBuilder(
    column: $table.refType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get servings => $composableBuilder(
    column: $table.servings,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPlanned => $composableBuilder(
    column: $table.isPlanned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLogged => $composableBuilder(
    column: $table.isLogged,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get macroSnapshot => $composableBuilder(
    column: $table.macroSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MealPlanDaysTableOrderingComposer get dayId {
    final $$MealPlanDaysTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.dayId,
      referencedTable: $db.mealPlanDays,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealPlanDaysTableOrderingComposer(
            $db: $db,
            $table: $db.mealPlanDays,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MealPlanEntriesTableAnnotationComposer
    extends Composer<_$HearthDatabase, $MealPlanEntriesTable> {
  $$MealPlanEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mealSlot =>
      $composableBuilder(column: $table.mealSlot, builder: (column) => column);

  GeneratedColumn<String> get refType =>
      $composableBuilder(column: $table.refType, builder: (column) => column);

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<double> get servings =>
      $composableBuilder(column: $table.servings, builder: (column) => column);

  GeneratedColumn<bool> get isPlanned =>
      $composableBuilder(column: $table.isPlanned, builder: (column) => column);

  GeneratedColumn<bool> get isLogged =>
      $composableBuilder(column: $table.isLogged, builder: (column) => column);

  GeneratedColumn<DateTime> get loggedAt =>
      $composableBuilder(column: $table.loggedAt, builder: (column) => column);

  GeneratedColumn<String> get macroSnapshot => $composableBuilder(
    column: $table.macroSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$MealPlanDaysTableAnnotationComposer get dayId {
    final $$MealPlanDaysTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.dayId,
      referencedTable: $db.mealPlanDays,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealPlanDaysTableAnnotationComposer(
            $db: $db,
            $table: $db.mealPlanDays,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MealPlanEntriesTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $MealPlanEntriesTable,
          MealPlanEntryRow,
          $$MealPlanEntriesTableFilterComposer,
          $$MealPlanEntriesTableOrderingComposer,
          $$MealPlanEntriesTableAnnotationComposer,
          $$MealPlanEntriesTableCreateCompanionBuilder,
          $$MealPlanEntriesTableUpdateCompanionBuilder,
          (MealPlanEntryRow, $$MealPlanEntriesTableReferences),
          MealPlanEntryRow,
          PrefetchHooks Function({bool dayId})
        > {
  $$MealPlanEntriesTableTableManager(
    _$HearthDatabase db,
    $MealPlanEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MealPlanEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MealPlanEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MealPlanEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> dayId = const Value.absent(),
                Value<String> mealSlot = const Value.absent(),
                Value<String> refType = const Value.absent(),
                Value<String> refId = const Value.absent(),
                Value<double> servings = const Value.absent(),
                Value<bool> isPlanned = const Value.absent(),
                Value<bool> isLogged = const Value.absent(),
                Value<DateTime?> loggedAt = const Value.absent(),
                Value<String?> macroSnapshot = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MealPlanEntriesCompanion(
                id: id,
                dayId: dayId,
                mealSlot: mealSlot,
                refType: refType,
                refId: refId,
                servings: servings,
                isPlanned: isPlanned,
                isLogged: isLogged,
                loggedAt: loggedAt,
                macroSnapshot: macroSnapshot,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String dayId,
                required String mealSlot,
                required String refType,
                required String refId,
                required double servings,
                Value<bool> isPlanned = const Value.absent(),
                Value<bool> isLogged = const Value.absent(),
                Value<DateTime?> loggedAt = const Value.absent(),
                Value<String?> macroSnapshot = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => MealPlanEntriesCompanion.insert(
                id: id,
                dayId: dayId,
                mealSlot: mealSlot,
                refType: refType,
                refId: refId,
                servings: servings,
                isPlanned: isPlanned,
                isLogged: isLogged,
                loggedAt: loggedAt,
                macroSnapshot: macroSnapshot,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MealPlanEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({dayId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (dayId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.dayId,
                        referencedTable: $$MealPlanEntriesTableReferences
                            ._dayIdTable(db),
                        referencedColumn: $$MealPlanEntriesTableReferences
                            ._dayIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MealPlanEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $MealPlanEntriesTable,
      MealPlanEntryRow,
      $$MealPlanEntriesTableFilterComposer,
      $$MealPlanEntriesTableOrderingComposer,
      $$MealPlanEntriesTableAnnotationComposer,
      $$MealPlanEntriesTableCreateCompanionBuilder,
      $$MealPlanEntriesTableUpdateCompanionBuilder,
      (MealPlanEntryRow, $$MealPlanEntriesTableReferences),
      MealPlanEntryRow,
      PrefetchHooks Function({bool dayId})
    >;
typedef $$MacroTargetsTableCreateCompanionBuilder =
    MacroTargetsCompanion Function({
      required String id,
      required String userId,
      required DateTime weekStartDate,
      required double kcal,
      required double proteinG,
      required double carbG,
      required double fatG,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$MacroTargetsTableUpdateCompanionBuilder =
    MacroTargetsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<DateTime> weekStartDate,
      Value<double> kcal,
      Value<double> proteinG,
      Value<double> carbG,
      Value<double> fatG,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$MacroTargetsTableFilterComposer
    extends Composer<_$HearthDatabase, $MacroTargetsTable> {
  $$MacroTargetsTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get weekStartDate => $composableBuilder(
    column: $table.weekStartDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbG => $composableBuilder(
    column: $table.carbG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MacroTargetsTableOrderingComposer
    extends Composer<_$HearthDatabase, $MacroTargetsTable> {
  $$MacroTargetsTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get weekStartDate => $composableBuilder(
    column: $table.weekStartDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbG => $composableBuilder(
    column: $table.carbG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MacroTargetsTableAnnotationComposer
    extends Composer<_$HearthDatabase, $MacroTargetsTable> {
  $$MacroTargetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<DateTime> get weekStartDate => $composableBuilder(
    column: $table.weekStartDate,
    builder: (column) => column,
  );

  GeneratedColumn<double> get kcal =>
      $composableBuilder(column: $table.kcal, builder: (column) => column);

  GeneratedColumn<double> get proteinG =>
      $composableBuilder(column: $table.proteinG, builder: (column) => column);

  GeneratedColumn<double> get carbG =>
      $composableBuilder(column: $table.carbG, builder: (column) => column);

  GeneratedColumn<double> get fatG =>
      $composableBuilder(column: $table.fatG, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MacroTargetsTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $MacroTargetsTable,
          MacroTargetRow,
          $$MacroTargetsTableFilterComposer,
          $$MacroTargetsTableOrderingComposer,
          $$MacroTargetsTableAnnotationComposer,
          $$MacroTargetsTableCreateCompanionBuilder,
          $$MacroTargetsTableUpdateCompanionBuilder,
          (
            MacroTargetRow,
            BaseReferences<
              _$HearthDatabase,
              $MacroTargetsTable,
              MacroTargetRow
            >,
          ),
          MacroTargetRow,
          PrefetchHooks Function()
        > {
  $$MacroTargetsTableTableManager(_$HearthDatabase db, $MacroTargetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MacroTargetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MacroTargetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MacroTargetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<DateTime> weekStartDate = const Value.absent(),
                Value<double> kcal = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> carbG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MacroTargetsCompanion(
                id: id,
                userId: userId,
                weekStartDate: weekStartDate,
                kcal: kcal,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required DateTime weekStartDate,
                required double kcal,
                required double proteinG,
                required double carbG,
                required double fatG,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => MacroTargetsCompanion.insert(
                id: id,
                userId: userId,
                weekStartDate: weekStartDate,
                kcal: kcal,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MacroTargetsTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $MacroTargetsTable,
      MacroTargetRow,
      $$MacroTargetsTableFilterComposer,
      $$MacroTargetsTableOrderingComposer,
      $$MacroTargetsTableAnnotationComposer,
      $$MacroTargetsTableCreateCompanionBuilder,
      $$MacroTargetsTableUpdateCompanionBuilder,
      (
        MacroTargetRow,
        BaseReferences<_$HearthDatabase, $MacroTargetsTable, MacroTargetRow>,
      ),
      MacroTargetRow,
      PrefetchHooks Function()
    >;
typedef $$IngredientMatchesTableCreateCompanionBuilder =
    IngredientMatchesCompanion Function({
      required String id,
      required String householdId,
      required String ingredientString,
      Value<String?> foodId,
      Value<bool> needsNoMatch,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$IngredientMatchesTableUpdateCompanionBuilder =
    IngredientMatchesCompanion Function({
      Value<String> id,
      Value<String> householdId,
      Value<String> ingredientString,
      Value<String?> foodId,
      Value<bool> needsNoMatch,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$IngredientMatchesTableReferences
    extends
        BaseReferences<
          _$HearthDatabase,
          $IngredientMatchesTable,
          IngredientMatchRow
        > {
  $$IngredientMatchesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $FoodsTable _foodIdTable(_$HearthDatabase db) =>
      db.foods.createAlias('ingredient_matches__food_id__foods__id');

  $$FoodsTableProcessedTableManager? get foodId {
    final $_column = $_itemColumn<String>('food_id');
    if ($_column == null) return null;
    final manager = $$FoodsTableTableManager(
      $_db,
      $_db.foods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_foodIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$IngredientMatchesTableFilterComposer
    extends Composer<_$HearthDatabase, $IngredientMatchesTable> {
  $$IngredientMatchesTableFilterComposer({
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

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ingredientString => $composableBuilder(
    column: $table.ingredientString,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsNoMatch => $composableBuilder(
    column: $table.needsNoMatch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$FoodsTableFilterComposer get foodId {
    final $$FoodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.foodId,
      referencedTable: $db.foods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodsTableFilterComposer(
            $db: $db,
            $table: $db.foods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IngredientMatchesTableOrderingComposer
    extends Composer<_$HearthDatabase, $IngredientMatchesTable> {
  $$IngredientMatchesTableOrderingComposer({
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

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ingredientString => $composableBuilder(
    column: $table.ingredientString,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsNoMatch => $composableBuilder(
    column: $table.needsNoMatch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$FoodsTableOrderingComposer get foodId {
    final $$FoodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.foodId,
      referencedTable: $db.foods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodsTableOrderingComposer(
            $db: $db,
            $table: $db.foods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IngredientMatchesTableAnnotationComposer
    extends Composer<_$HearthDatabase, $IngredientMatchesTable> {
  $$IngredientMatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ingredientString => $composableBuilder(
    column: $table.ingredientString,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get needsNoMatch => $composableBuilder(
    column: $table.needsNoMatch,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$FoodsTableAnnotationComposer get foodId {
    final $$FoodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.foodId,
      referencedTable: $db.foods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodsTableAnnotationComposer(
            $db: $db,
            $table: $db.foods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IngredientMatchesTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $IngredientMatchesTable,
          IngredientMatchRow,
          $$IngredientMatchesTableFilterComposer,
          $$IngredientMatchesTableOrderingComposer,
          $$IngredientMatchesTableAnnotationComposer,
          $$IngredientMatchesTableCreateCompanionBuilder,
          $$IngredientMatchesTableUpdateCompanionBuilder,
          (IngredientMatchRow, $$IngredientMatchesTableReferences),
          IngredientMatchRow,
          PrefetchHooks Function({bool foodId})
        > {
  $$IngredientMatchesTableTableManager(
    _$HearthDatabase db,
    $IngredientMatchesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IngredientMatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IngredientMatchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IngredientMatchesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> ingredientString = const Value.absent(),
                Value<String?> foodId = const Value.absent(),
                Value<bool> needsNoMatch = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IngredientMatchesCompanion(
                id: id,
                householdId: householdId,
                ingredientString: ingredientString,
                foodId: foodId,
                needsNoMatch: needsNoMatch,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required String ingredientString,
                Value<String?> foodId = const Value.absent(),
                Value<bool> needsNoMatch = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => IngredientMatchesCompanion.insert(
                id: id,
                householdId: householdId,
                ingredientString: ingredientString,
                foodId: foodId,
                needsNoMatch: needsNoMatch,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$IngredientMatchesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({foodId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (foodId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.foodId,
                        referencedTable: $$IngredientMatchesTableReferences
                            ._foodIdTable(db),
                        referencedColumn: $$IngredientMatchesTableReferences
                            ._foodIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$IngredientMatchesTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $IngredientMatchesTable,
      IngredientMatchRow,
      $$IngredientMatchesTableFilterComposer,
      $$IngredientMatchesTableOrderingComposer,
      $$IngredientMatchesTableAnnotationComposer,
      $$IngredientMatchesTableCreateCompanionBuilder,
      $$IngredientMatchesTableUpdateCompanionBuilder,
      (IngredientMatchRow, $$IngredientMatchesTableReferences),
      IngredientMatchRow,
      PrefetchHooks Function({bool foodId})
    >;
typedef $$CookTimersTableCreateCompanionBuilder = CookTimersCompanion Function({
  required String id,
  required String label,
  required int durationSeconds,
  required DateTime startedAt,
  Value<int?> stepNumber,
  Value<String?> stepId,
  Value<int?> elapsedWhenPausedSeconds,
  Value<String?> recipeTitle,
  Value<int> rowid,
});
typedef $$CookTimersTableUpdateCompanionBuilder = CookTimersCompanion Function({
  Value<String> id,
  Value<String> label,
  Value<int> durationSeconds,
  Value<DateTime> startedAt,
  Value<int?> stepNumber,
  Value<String?> stepId,
  Value<int?> elapsedWhenPausedSeconds,
  Value<String?> recipeTitle,
  Value<int> rowid,
});

class $$CookTimersTableFilterComposer
    extends Composer<_$HearthDatabase, $CookTimersTable> {
  $$CookTimersTableFilterComposer({
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

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stepNumber => $composableBuilder(
    column: $table.stepNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stepId => $composableBuilder(
    column: $table.stepId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get elapsedWhenPausedSeconds => $composableBuilder(
    column: $table.elapsedWhenPausedSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipeTitle => $composableBuilder(
    column: $table.recipeTitle,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CookTimersTableOrderingComposer
    extends Composer<_$HearthDatabase, $CookTimersTable> {
  $$CookTimersTableOrderingComposer({
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

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stepNumber => $composableBuilder(
    column: $table.stepNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stepId => $composableBuilder(
    column: $table.stepId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get elapsedWhenPausedSeconds => $composableBuilder(
    column: $table.elapsedWhenPausedSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipeTitle => $composableBuilder(
    column: $table.recipeTitle,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CookTimersTableAnnotationComposer
    extends Composer<_$HearthDatabase, $CookTimersTable> {
  $$CookTimersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get stepNumber => $composableBuilder(
    column: $table.stepNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stepId =>
      $composableBuilder(column: $table.stepId, builder: (column) => column);

  GeneratedColumn<int> get elapsedWhenPausedSeconds => $composableBuilder(
    column: $table.elapsedWhenPausedSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recipeTitle => $composableBuilder(
    column: $table.recipeTitle,
    builder: (column) => column,
  );
}

class $$CookTimersTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $CookTimersTable,
          CookTimerRow,
          $$CookTimersTableFilterComposer,
          $$CookTimersTableOrderingComposer,
          $$CookTimersTableAnnotationComposer,
          $$CookTimersTableCreateCompanionBuilder,
          $$CookTimersTableUpdateCompanionBuilder,
          (
            CookTimerRow,
            BaseReferences<_$HearthDatabase, $CookTimersTable, CookTimerRow>,
          ),
          CookTimerRow,
          PrefetchHooks Function()
        > {
  $$CookTimersTableTableManager(_$HearthDatabase db, $CookTimersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CookTimersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CookTimersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CookTimersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<int?> stepNumber = const Value.absent(),
                Value<String?> stepId = const Value.absent(),
                Value<int?> elapsedWhenPausedSeconds = const Value.absent(),
                Value<String?> recipeTitle = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CookTimersCompanion(
                id: id,
                label: label,
                durationSeconds: durationSeconds,
                startedAt: startedAt,
                stepNumber: stepNumber,
                stepId: stepId,
                elapsedWhenPausedSeconds: elapsedWhenPausedSeconds,
                recipeTitle: recipeTitle,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String label,
                required int durationSeconds,
                required DateTime startedAt,
                Value<int?> stepNumber = const Value.absent(),
                Value<String?> stepId = const Value.absent(),
                Value<int?> elapsedWhenPausedSeconds = const Value.absent(),
                Value<String?> recipeTitle = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CookTimersCompanion.insert(
                id: id,
                label: label,
                durationSeconds: durationSeconds,
                startedAt: startedAt,
                stepNumber: stepNumber,
                stepId: stepId,
                elapsedWhenPausedSeconds: elapsedWhenPausedSeconds,
                recipeTitle: recipeTitle,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CookTimersTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $CookTimersTable,
      CookTimerRow,
      $$CookTimersTableFilterComposer,
      $$CookTimersTableOrderingComposer,
      $$CookTimersTableAnnotationComposer,
      $$CookTimersTableCreateCompanionBuilder,
      $$CookTimersTableUpdateCompanionBuilder,
      (
        CookTimerRow,
        BaseReferences<_$HearthDatabase, $CookTimersTable, CookTimerRow>,
      ),
      CookTimerRow,
      PrefetchHooks Function()
    >;
typedef $$FoodProfilesTableCreateCompanionBuilder =
    FoodProfilesCompanion Function({
      required String userId,
      Value<double?> caloriesPerMealTarget,
      Value<double?> proteinTargetG,
      Value<String> preferredMealTypes,
      Value<String> dietaryPreferences,
      Value<String> dislikes,
      Value<String> allergies,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$FoodProfilesTableUpdateCompanionBuilder =
    FoodProfilesCompanion Function({
      Value<String> userId,
      Value<double?> caloriesPerMealTarget,
      Value<double?> proteinTargetG,
      Value<String> preferredMealTypes,
      Value<String> dietaryPreferences,
      Value<String> dislikes,
      Value<String> allergies,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$FoodProfilesTableFilterComposer
    extends Composer<_$HearthDatabase, $FoodProfilesTable> {
  $$FoodProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get caloriesPerMealTarget => $composableBuilder(
    column: $table.caloriesPerMealTarget,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinTargetG => $composableBuilder(
    column: $table.proteinTargetG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preferredMealTypes => $composableBuilder(
    column: $table.preferredMealTypes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dietaryPreferences => $composableBuilder(
    column: $table.dietaryPreferences,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dislikes => $composableBuilder(
    column: $table.dislikes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get allergies => $composableBuilder(
    column: $table.allergies,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FoodProfilesTableOrderingComposer
    extends Composer<_$HearthDatabase, $FoodProfilesTable> {
  $$FoodProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get caloriesPerMealTarget => $composableBuilder(
    column: $table.caloriesPerMealTarget,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinTargetG => $composableBuilder(
    column: $table.proteinTargetG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preferredMealTypes => $composableBuilder(
    column: $table.preferredMealTypes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dietaryPreferences => $composableBuilder(
    column: $table.dietaryPreferences,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dislikes => $composableBuilder(
    column: $table.dislikes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get allergies => $composableBuilder(
    column: $table.allergies,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoodProfilesTableAnnotationComposer
    extends Composer<_$HearthDatabase, $FoodProfilesTable> {
  $$FoodProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<double> get caloriesPerMealTarget => $composableBuilder(
    column: $table.caloriesPerMealTarget,
    builder: (column) => column,
  );

  GeneratedColumn<double> get proteinTargetG => $composableBuilder(
    column: $table.proteinTargetG,
    builder: (column) => column,
  );

  GeneratedColumn<String> get preferredMealTypes => $composableBuilder(
    column: $table.preferredMealTypes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dietaryPreferences => $composableBuilder(
    column: $table.dietaryPreferences,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dislikes =>
      $composableBuilder(column: $table.dislikes, builder: (column) => column);

  GeneratedColumn<String> get allergies =>
      $composableBuilder(column: $table.allergies, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$FoodProfilesTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $FoodProfilesTable,
          FoodProfileRow,
          $$FoodProfilesTableFilterComposer,
          $$FoodProfilesTableOrderingComposer,
          $$FoodProfilesTableAnnotationComposer,
          $$FoodProfilesTableCreateCompanionBuilder,
          $$FoodProfilesTableUpdateCompanionBuilder,
          (
            FoodProfileRow,
            BaseReferences<
              _$HearthDatabase,
              $FoodProfilesTable,
              FoodProfileRow
            >,
          ),
          FoodProfileRow,
          PrefetchHooks Function()
        > {
  $$FoodProfilesTableTableManager(_$HearthDatabase db, $FoodProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoodProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoodProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoodProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<double?> caloriesPerMealTarget = const Value.absent(),
                Value<double?> proteinTargetG = const Value.absent(),
                Value<String> preferredMealTypes = const Value.absent(),
                Value<String> dietaryPreferences = const Value.absent(),
                Value<String> dislikes = const Value.absent(),
                Value<String> allergies = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoodProfilesCompanion(
                userId: userId,
                caloriesPerMealTarget: caloriesPerMealTarget,
                proteinTargetG: proteinTargetG,
                preferredMealTypes: preferredMealTypes,
                dietaryPreferences: dietaryPreferences,
                dislikes: dislikes,
                allergies: allergies,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                Value<double?> caloriesPerMealTarget = const Value.absent(),
                Value<double?> proteinTargetG = const Value.absent(),
                Value<String> preferredMealTypes = const Value.absent(),
                Value<String> dietaryPreferences = const Value.absent(),
                Value<String> dislikes = const Value.absent(),
                Value<String> allergies = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => FoodProfilesCompanion.insert(
                userId: userId,
                caloriesPerMealTarget: caloriesPerMealTarget,
                proteinTargetG: proteinTargetG,
                preferredMealTypes: preferredMealTypes,
                dietaryPreferences: dietaryPreferences,
                dislikes: dislikes,
                allergies: allergies,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FoodProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $FoodProfilesTable,
      FoodProfileRow,
      $$FoodProfilesTableFilterComposer,
      $$FoodProfilesTableOrderingComposer,
      $$FoodProfilesTableAnnotationComposer,
      $$FoodProfilesTableCreateCompanionBuilder,
      $$FoodProfilesTableUpdateCompanionBuilder,
      (
        FoodProfileRow,
        BaseReferences<_$HearthDatabase, $FoodProfilesTable, FoodProfileRow>,
      ),
      FoodProfileRow,
      PrefetchHooks Function()
    >;
typedef $$PreferencesTableCreateCompanionBuilder =
    PreferencesCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$PreferencesTableUpdateCompanionBuilder =
    PreferencesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$PreferencesTableFilterComposer
    extends Composer<_$HearthDatabase, $PreferencesTable> {
  $$PreferencesTableFilterComposer({
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

class $$PreferencesTableOrderingComposer
    extends Composer<_$HearthDatabase, $PreferencesTable> {
  $$PreferencesTableOrderingComposer({
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

class $$PreferencesTableAnnotationComposer
    extends Composer<_$HearthDatabase, $PreferencesTable> {
  $$PreferencesTableAnnotationComposer({
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

class $$PreferencesTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $PreferencesTable,
          PreferenceRow,
          $$PreferencesTableFilterComposer,
          $$PreferencesTableOrderingComposer,
          $$PreferencesTableAnnotationComposer,
          $$PreferencesTableCreateCompanionBuilder,
          $$PreferencesTableUpdateCompanionBuilder,
          (
            PreferenceRow,
            BaseReferences<_$HearthDatabase, $PreferencesTable, PreferenceRow>,
          ),
          PreferenceRow,
          PrefetchHooks Function()
        > {
  $$PreferencesTableTableManager(_$HearthDatabase db, $PreferencesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => PreferencesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => PreferencesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $PreferencesTable,
      PreferenceRow,
      $$PreferencesTableFilterComposer,
      $$PreferencesTableOrderingComposer,
      $$PreferencesTableAnnotationComposer,
      $$PreferencesTableCreateCompanionBuilder,
      $$PreferencesTableUpdateCompanionBuilder,
      (
        PreferenceRow,
        BaseReferences<_$HearthDatabase, $PreferencesTable, PreferenceRow>,
      ),
      PreferenceRow,
      PrefetchHooks Function()
    >;
typedef $$CookSessionsTableCreateCompanionBuilder =
    CookSessionsCompanion Function({
      required String recipeId,
      Value<int> currentStep,
      Value<String> checkedStepIds,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CookSessionsTableUpdateCompanionBuilder =
    CookSessionsCompanion Function({
      Value<String> recipeId,
      Value<int> currentStep,
      Value<String> checkedStepIds,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CookSessionsTableFilterComposer
    extends Composer<_$HearthDatabase, $CookSessionsTable> {
  $$CookSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recipeId => $composableBuilder(
    column: $table.recipeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentStep => $composableBuilder(
    column: $table.currentStep,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checkedStepIds => $composableBuilder(
    column: $table.checkedStepIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CookSessionsTableOrderingComposer
    extends Composer<_$HearthDatabase, $CookSessionsTable> {
  $$CookSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recipeId => $composableBuilder(
    column: $table.recipeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentStep => $composableBuilder(
    column: $table.currentStep,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checkedStepIds => $composableBuilder(
    column: $table.checkedStepIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CookSessionsTableAnnotationComposer
    extends Composer<_$HearthDatabase, $CookSessionsTable> {
  $$CookSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recipeId =>
      $composableBuilder(column: $table.recipeId, builder: (column) => column);

  GeneratedColumn<int> get currentStep => $composableBuilder(
    column: $table.currentStep,
    builder: (column) => column,
  );

  GeneratedColumn<String> get checkedStepIds => $composableBuilder(
    column: $table.checkedStepIds,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CookSessionsTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $CookSessionsTable,
          CookSessionRow,
          $$CookSessionsTableFilterComposer,
          $$CookSessionsTableOrderingComposer,
          $$CookSessionsTableAnnotationComposer,
          $$CookSessionsTableCreateCompanionBuilder,
          $$CookSessionsTableUpdateCompanionBuilder,
          (
            CookSessionRow,
            BaseReferences<
              _$HearthDatabase,
              $CookSessionsTable,
              CookSessionRow
            >,
          ),
          CookSessionRow,
          PrefetchHooks Function()
        > {
  $$CookSessionsTableTableManager(_$HearthDatabase db, $CookSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CookSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CookSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CookSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> recipeId = const Value.absent(),
                Value<int> currentStep = const Value.absent(),
                Value<String> checkedStepIds = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CookSessionsCompanion(
                recipeId: recipeId,
                currentStep: currentStep,
                checkedStepIds: checkedStepIds,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recipeId,
                Value<int> currentStep = const Value.absent(),
                Value<String> checkedStepIds = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CookSessionsCompanion.insert(
                recipeId: recipeId,
                currentStep: currentStep,
                checkedStepIds: checkedStepIds,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CookSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $CookSessionsTable,
      CookSessionRow,
      $$CookSessionsTableFilterComposer,
      $$CookSessionsTableOrderingComposer,
      $$CookSessionsTableAnnotationComposer,
      $$CookSessionsTableCreateCompanionBuilder,
      $$CookSessionsTableUpdateCompanionBuilder,
      (
        CookSessionRow,
        BaseReferences<_$HearthDatabase, $CookSessionsTable, CookSessionRow>,
      ),
      CookSessionRow,
      PrefetchHooks Function()
    >;
typedef $$RecipePhotosTableCreateCompanionBuilder =
    RecipePhotosCompanion Function({
      required String recipeId,
      Value<String?> fileName,
      Value<String?> remotePath,
      Value<int> syncAttempts,
      Value<String?> syncError,
      Value<String?> attemptedPath,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$RecipePhotosTableUpdateCompanionBuilder =
    RecipePhotosCompanion Function({
      Value<String> recipeId,
      Value<String?> fileName,
      Value<String?> remotePath,
      Value<int> syncAttempts,
      Value<String?> syncError,
      Value<String?> attemptedPath,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$RecipePhotosTableReferences
    extends
        BaseReferences<_$HearthDatabase, $RecipePhotosTable, RecipePhotoRow> {
  $$RecipePhotosTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $RecipesTable _recipeIdTable(_$HearthDatabase db) =>
      db.recipes.createAlias('recipe_photos__recipe_id__recipes__id');

  $$RecipesTableProcessedTableManager get recipeId {
    final $_column = $_itemColumn<String>('recipe_id')!;

    final manager = $$RecipesTableTableManager(
      $_db,
      $_db.recipes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recipeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RecipePhotosTableFilterComposer
    extends Composer<_$HearthDatabase, $RecipePhotosTable> {
  $$RecipePhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remotePath => $composableBuilder(
    column: $table.remotePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncAttempts => $composableBuilder(
    column: $table.syncAttempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncError => $composableBuilder(
    column: $table.syncError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attemptedPath => $composableBuilder(
    column: $table.attemptedPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$RecipesTableFilterComposer get recipeId {
    final $$RecipesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableFilterComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipePhotosTableOrderingComposer
    extends Composer<_$HearthDatabase, $RecipePhotosTable> {
  $$RecipePhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remotePath => $composableBuilder(
    column: $table.remotePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncAttempts => $composableBuilder(
    column: $table.syncAttempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncError => $composableBuilder(
    column: $table.syncError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attemptedPath => $composableBuilder(
    column: $table.attemptedPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$RecipesTableOrderingComposer get recipeId {
    final $$RecipesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableOrderingComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipePhotosTableAnnotationComposer
    extends Composer<_$HearthDatabase, $RecipePhotosTable> {
  $$RecipePhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get remotePath => $composableBuilder(
    column: $table.remotePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncAttempts => $composableBuilder(
    column: $table.syncAttempts,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncError =>
      $composableBuilder(column: $table.syncError, builder: (column) => column);

  GeneratedColumn<String> get attemptedPath => $composableBuilder(
    column: $table.attemptedPath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$RecipesTableAnnotationComposer get recipeId {
    final $$RecipesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipePhotosTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $RecipePhotosTable,
          RecipePhotoRow,
          $$RecipePhotosTableFilterComposer,
          $$RecipePhotosTableOrderingComposer,
          $$RecipePhotosTableAnnotationComposer,
          $$RecipePhotosTableCreateCompanionBuilder,
          $$RecipePhotosTableUpdateCompanionBuilder,
          (RecipePhotoRow, $$RecipePhotosTableReferences),
          RecipePhotoRow,
          PrefetchHooks Function({bool recipeId})
        > {
  $$RecipePhotosTableTableManager(_$HearthDatabase db, $RecipePhotosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecipePhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecipePhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecipePhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> recipeId = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<String?> remotePath = const Value.absent(),
                Value<int> syncAttempts = const Value.absent(),
                Value<String?> syncError = const Value.absent(),
                Value<String?> attemptedPath = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipePhotosCompanion(
                recipeId: recipeId,
                fileName: fileName,
                remotePath: remotePath,
                syncAttempts: syncAttempts,
                syncError: syncError,
                attemptedPath: attemptedPath,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recipeId,
                Value<String?> fileName = const Value.absent(),
                Value<String?> remotePath = const Value.absent(),
                Value<int> syncAttempts = const Value.absent(),
                Value<String?> syncError = const Value.absent(),
                Value<String?> attemptedPath = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RecipePhotosCompanion.insert(
                recipeId: recipeId,
                fileName: fileName,
                remotePath: remotePath,
                syncAttempts: syncAttempts,
                syncError: syncError,
                attemptedPath: attemptedPath,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecipePhotosTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({recipeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (recipeId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.recipeId,
                        referencedTable: $$RecipePhotosTableReferences
                            ._recipeIdTable(db),
                        referencedColumn: $$RecipePhotosTableReferences
                            ._recipeIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RecipePhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $RecipePhotosTable,
      RecipePhotoRow,
      $$RecipePhotosTableFilterComposer,
      $$RecipePhotosTableOrderingComposer,
      $$RecipePhotosTableAnnotationComposer,
      $$RecipePhotosTableCreateCompanionBuilder,
      $$RecipePhotosTableUpdateCompanionBuilder,
      (RecipePhotoRow, $$RecipePhotosTableReferences),
      RecipePhotoRow,
      PrefetchHooks Function({bool recipeId})
    >;
typedef $$PlanTemplatesTableCreateCompanionBuilder =
    PlanTemplatesCompanion Function({
      required String id,
      required String userId,
      required String name,
      Value<String> entries,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PlanTemplatesTableUpdateCompanionBuilder =
    PlanTemplatesCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> name,
      Value<String> entries,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$PlanTemplatesTableFilterComposer
    extends Composer<_$HearthDatabase, $PlanTemplatesTable> {
  $$PlanTemplatesTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entries => $composableBuilder(
    column: $table.entries,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlanTemplatesTableOrderingComposer
    extends Composer<_$HearthDatabase, $PlanTemplatesTable> {
  $$PlanTemplatesTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entries => $composableBuilder(
    column: $table.entries,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlanTemplatesTableAnnotationComposer
    extends Composer<_$HearthDatabase, $PlanTemplatesTable> {
  $$PlanTemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get entries =>
      $composableBuilder(column: $table.entries, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PlanTemplatesTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $PlanTemplatesTable,
          PlanTemplateRow,
          $$PlanTemplatesTableFilterComposer,
          $$PlanTemplatesTableOrderingComposer,
          $$PlanTemplatesTableAnnotationComposer,
          $$PlanTemplatesTableCreateCompanionBuilder,
          $$PlanTemplatesTableUpdateCompanionBuilder,
          (
            PlanTemplateRow,
            BaseReferences<
              _$HearthDatabase,
              $PlanTemplatesTable,
              PlanTemplateRow
            >,
          ),
          PlanTemplateRow,
          PrefetchHooks Function()
        > {
  $$PlanTemplatesTableTableManager(
    _$HearthDatabase db,
    $PlanTemplatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanTemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlanTemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlanTemplatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> entries = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanTemplatesCompanion(
                id: id,
                userId: userId,
                name: name,
                entries: entries,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String name,
                Value<String> entries = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlanTemplatesCompanion.insert(
                id: id,
                userId: userId,
                name: name,
                entries: entries,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlanTemplatesTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $PlanTemplatesTable,
      PlanTemplateRow,
      $$PlanTemplatesTableFilterComposer,
      $$PlanTemplatesTableOrderingComposer,
      $$PlanTemplatesTableAnnotationComposer,
      $$PlanTemplatesTableCreateCompanionBuilder,
      $$PlanTemplatesTableUpdateCompanionBuilder,
      (
        PlanTemplateRow,
        BaseReferences<_$HearthDatabase, $PlanTemplatesTable, PlanTemplateRow>,
      ),
      PlanTemplateRow,
      PrefetchHooks Function()
    >;
typedef $$PendingWritesTableCreateCompanionBuilder =
    PendingWritesCompanion Function({
      Value<int> sequence,
      required String entityTable,
      required String entityId,
      required String operation,
      required String payload,
      required DateTime queuedAt,
      Value<int> attempts,
      Value<String?> lastError,
    });
typedef $$PendingWritesTableUpdateCompanionBuilder =
    PendingWritesCompanion Function({
      Value<int> sequence,
      Value<String> entityTable,
      Value<String> entityId,
      Value<String> operation,
      Value<String> payload,
      Value<DateTime> queuedAt,
      Value<int> attempts,
      Value<String?> lastError,
    });

class $$PendingWritesTableFilterComposer
    extends Composer<_$HearthDatabase, $PendingWritesTable> {
  $$PendingWritesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityTable => $composableBuilder(
    column: $table.entityTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get queuedAt => $composableBuilder(
    column: $table.queuedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingWritesTableOrderingComposer
    extends Composer<_$HearthDatabase, $PendingWritesTable> {
  $$PendingWritesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityTable => $composableBuilder(
    column: $table.entityTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get queuedAt => $composableBuilder(
    column: $table.queuedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingWritesTableAnnotationComposer
    extends Composer<_$HearthDatabase, $PendingWritesTable> {
  $$PendingWritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get entityTable => $composableBuilder(
    column: $table.entityTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get queuedAt =>
      $composableBuilder(column: $table.queuedAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$PendingWritesTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $PendingWritesTable,
          PendingWriteRow,
          $$PendingWritesTableFilterComposer,
          $$PendingWritesTableOrderingComposer,
          $$PendingWritesTableAnnotationComposer,
          $$PendingWritesTableCreateCompanionBuilder,
          $$PendingWritesTableUpdateCompanionBuilder,
          (
            PendingWriteRow,
            BaseReferences<
              _$HearthDatabase,
              $PendingWritesTable,
              PendingWriteRow
            >,
          ),
          PendingWriteRow,
          PrefetchHooks Function()
        > {
  $$PendingWritesTableTableManager(
    _$HearthDatabase db,
    $PendingWritesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingWritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingWritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingWritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> sequence = const Value.absent(),
                Value<String> entityTable = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> queuedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => PendingWritesCompanion(
                sequence: sequence,
                entityTable: entityTable,
                entityId: entityId,
                operation: operation,
                payload: payload,
                queuedAt: queuedAt,
                attempts: attempts,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> sequence = const Value.absent(),
                required String entityTable,
                required String entityId,
                required String operation,
                required String payload,
                required DateTime queuedAt,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => PendingWritesCompanion.insert(
                sequence: sequence,
                entityTable: entityTable,
                entityId: entityId,
                operation: operation,
                payload: payload,
                queuedAt: queuedAt,
                attempts: attempts,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingWritesTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $PendingWritesTable,
      PendingWriteRow,
      $$PendingWritesTableFilterComposer,
      $$PendingWritesTableOrderingComposer,
      $$PendingWritesTableAnnotationComposer,
      $$PendingWritesTableCreateCompanionBuilder,
      $$PendingWritesTableUpdateCompanionBuilder,
      (
        PendingWriteRow,
        BaseReferences<_$HearthDatabase, $PendingWritesTable, PendingWriteRow>,
      ),
      PendingWriteRow,
      PrefetchHooks Function()
    >;
typedef $$ShoppingListsTableCreateCompanionBuilder =
    ShoppingListsCompanion Function({
      required String id,
      required String householdId,
      required DateTime fromDate,
      required DateTime toDate,
      Value<String> status,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ShoppingListsTableUpdateCompanionBuilder =
    ShoppingListsCompanion Function({
      Value<String> id,
      Value<String> householdId,
      Value<DateTime> fromDate,
      Value<DateTime> toDate,
      Value<String> status,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ShoppingListsTableFilterComposer
    extends Composer<_$HearthDatabase, $ShoppingListsTable> {
  $$ShoppingListsTableFilterComposer({
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

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fromDate => $composableBuilder(
    column: $table.fromDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get toDate => $composableBuilder(
    column: $table.toDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ShoppingListsTableOrderingComposer
    extends Composer<_$HearthDatabase, $ShoppingListsTable> {
  $$ShoppingListsTableOrderingComposer({
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

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fromDate => $composableBuilder(
    column: $table.fromDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get toDate => $composableBuilder(
    column: $table.toDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ShoppingListsTableAnnotationComposer
    extends Composer<_$HearthDatabase, $ShoppingListsTable> {
  $$ShoppingListsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fromDate =>
      $composableBuilder(column: $table.fromDate, builder: (column) => column);

  GeneratedColumn<DateTime> get toDate =>
      $composableBuilder(column: $table.toDate, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ShoppingListsTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $ShoppingListsTable,
          ShoppingListRow,
          $$ShoppingListsTableFilterComposer,
          $$ShoppingListsTableOrderingComposer,
          $$ShoppingListsTableAnnotationComposer,
          $$ShoppingListsTableCreateCompanionBuilder,
          $$ShoppingListsTableUpdateCompanionBuilder,
          (
            ShoppingListRow,
            BaseReferences<
              _$HearthDatabase,
              $ShoppingListsTable,
              ShoppingListRow
            >,
          ),
          ShoppingListRow,
          PrefetchHooks Function()
        > {
  $$ShoppingListsTableTableManager(
    _$HearthDatabase db,
    $ShoppingListsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShoppingListsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShoppingListsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShoppingListsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<DateTime> fromDate = const Value.absent(),
                Value<DateTime> toDate = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShoppingListsCompanion(
                id: id,
                householdId: householdId,
                fromDate: fromDate,
                toDate: toDate,
                status: status,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required DateTime fromDate,
                required DateTime toDate,
                Value<String> status = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ShoppingListsCompanion.insert(
                id: id,
                householdId: householdId,
                fromDate: fromDate,
                toDate: toDate,
                status: status,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ShoppingListsTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $ShoppingListsTable,
      ShoppingListRow,
      $$ShoppingListsTableFilterComposer,
      $$ShoppingListsTableOrderingComposer,
      $$ShoppingListsTableAnnotationComposer,
      $$ShoppingListsTableCreateCompanionBuilder,
      $$ShoppingListsTableUpdateCompanionBuilder,
      (
        ShoppingListRow,
        BaseReferences<_$HearthDatabase, $ShoppingListsTable, ShoppingListRow>,
      ),
      ShoppingListRow,
      PrefetchHooks Function()
    >;
typedef $$ShoppingListItemsTableCreateCompanionBuilder =
    ShoppingListItemsCompanion Function({
      required String id,
      required String listId,
      required String itemKey,
      Value<String?> foodId,
      required String name,
      Value<double?> plannedCanonical,
      Value<String?> plannedKind,
      Value<String?> plannedUnit,
      Value<String> plannedRest,
      Value<double?> wantedCanonical,
      Value<String?> wantedKind,
      Value<String?> wantedUnit,
      Value<double?> onHandCanonical,
      Value<String?> onHandKind,
      Value<String?> onHandUnit,
      Value<bool> checked,
      Value<bool> isManual,
      Value<bool> hasUnquantified,
      Value<String?> storeTag,
      Value<int> sortOrder,
      Value<String> sourceRecipeIds,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ShoppingListItemsTableUpdateCompanionBuilder =
    ShoppingListItemsCompanion Function({
      Value<String> id,
      Value<String> listId,
      Value<String> itemKey,
      Value<String?> foodId,
      Value<String> name,
      Value<double?> plannedCanonical,
      Value<String?> plannedKind,
      Value<String?> plannedUnit,
      Value<String> plannedRest,
      Value<double?> wantedCanonical,
      Value<String?> wantedKind,
      Value<String?> wantedUnit,
      Value<double?> onHandCanonical,
      Value<String?> onHandKind,
      Value<String?> onHandUnit,
      Value<bool> checked,
      Value<bool> isManual,
      Value<bool> hasUnquantified,
      Value<String?> storeTag,
      Value<int> sortOrder,
      Value<String> sourceRecipeIds,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ShoppingListItemsTableFilterComposer
    extends Composer<_$HearthDatabase, $ShoppingListItemsTable> {
  $$ShoppingListItemsTableFilterComposer({
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

  ColumnFilters<String> get listId => $composableBuilder(
    column: $table.listId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemKey => $composableBuilder(
    column: $table.itemKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get foodId => $composableBuilder(
    column: $table.foodId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get plannedCanonical => $composableBuilder(
    column: $table.plannedCanonical,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plannedKind => $composableBuilder(
    column: $table.plannedKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plannedUnit => $composableBuilder(
    column: $table.plannedUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plannedRest => $composableBuilder(
    column: $table.plannedRest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get wantedCanonical => $composableBuilder(
    column: $table.wantedCanonical,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wantedKind => $composableBuilder(
    column: $table.wantedKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wantedUnit => $composableBuilder(
    column: $table.wantedUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get onHandCanonical => $composableBuilder(
    column: $table.onHandCanonical,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get onHandKind => $composableBuilder(
    column: $table.onHandKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get onHandUnit => $composableBuilder(
    column: $table.onHandUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get checked => $composableBuilder(
    column: $table.checked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isManual => $composableBuilder(
    column: $table.isManual,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasUnquantified => $composableBuilder(
    column: $table.hasUnquantified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeTag => $composableBuilder(
    column: $table.storeTag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceRecipeIds => $composableBuilder(
    column: $table.sourceRecipeIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ShoppingListItemsTableOrderingComposer
    extends Composer<_$HearthDatabase, $ShoppingListItemsTable> {
  $$ShoppingListItemsTableOrderingComposer({
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

  ColumnOrderings<String> get listId => $composableBuilder(
    column: $table.listId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemKey => $composableBuilder(
    column: $table.itemKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get foodId => $composableBuilder(
    column: $table.foodId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get plannedCanonical => $composableBuilder(
    column: $table.plannedCanonical,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plannedKind => $composableBuilder(
    column: $table.plannedKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plannedUnit => $composableBuilder(
    column: $table.plannedUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plannedRest => $composableBuilder(
    column: $table.plannedRest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get wantedCanonical => $composableBuilder(
    column: $table.wantedCanonical,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wantedKind => $composableBuilder(
    column: $table.wantedKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wantedUnit => $composableBuilder(
    column: $table.wantedUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get onHandCanonical => $composableBuilder(
    column: $table.onHandCanonical,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get onHandKind => $composableBuilder(
    column: $table.onHandKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get onHandUnit => $composableBuilder(
    column: $table.onHandUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get checked => $composableBuilder(
    column: $table.checked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isManual => $composableBuilder(
    column: $table.isManual,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasUnquantified => $composableBuilder(
    column: $table.hasUnquantified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeTag => $composableBuilder(
    column: $table.storeTag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceRecipeIds => $composableBuilder(
    column: $table.sourceRecipeIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ShoppingListItemsTableAnnotationComposer
    extends Composer<_$HearthDatabase, $ShoppingListItemsTable> {
  $$ShoppingListItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get listId =>
      $composableBuilder(column: $table.listId, builder: (column) => column);

  GeneratedColumn<String> get itemKey =>
      $composableBuilder(column: $table.itemKey, builder: (column) => column);

  GeneratedColumn<String> get foodId =>
      $composableBuilder(column: $table.foodId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get plannedCanonical => $composableBuilder(
    column: $table.plannedCanonical,
    builder: (column) => column,
  );

  GeneratedColumn<String> get plannedKind => $composableBuilder(
    column: $table.plannedKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get plannedUnit => $composableBuilder(
    column: $table.plannedUnit,
    builder: (column) => column,
  );

  GeneratedColumn<String> get plannedRest => $composableBuilder(
    column: $table.plannedRest,
    builder: (column) => column,
  );

  GeneratedColumn<double> get wantedCanonical => $composableBuilder(
    column: $table.wantedCanonical,
    builder: (column) => column,
  );

  GeneratedColumn<String> get wantedKind => $composableBuilder(
    column: $table.wantedKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get wantedUnit => $composableBuilder(
    column: $table.wantedUnit,
    builder: (column) => column,
  );

  GeneratedColumn<double> get onHandCanonical => $composableBuilder(
    column: $table.onHandCanonical,
    builder: (column) => column,
  );

  GeneratedColumn<String> get onHandKind => $composableBuilder(
    column: $table.onHandKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get onHandUnit => $composableBuilder(
    column: $table.onHandUnit,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get checked =>
      $composableBuilder(column: $table.checked, builder: (column) => column);

  GeneratedColumn<bool> get isManual =>
      $composableBuilder(column: $table.isManual, builder: (column) => column);

  GeneratedColumn<bool> get hasUnquantified => $composableBuilder(
    column: $table.hasUnquantified,
    builder: (column) => column,
  );

  GeneratedColumn<String> get storeTag =>
      $composableBuilder(column: $table.storeTag, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get sourceRecipeIds => $composableBuilder(
    column: $table.sourceRecipeIds,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ShoppingListItemsTableTableManager
    extends
        RootTableManager<
          _$HearthDatabase,
          $ShoppingListItemsTable,
          ShoppingItemRow,
          $$ShoppingListItemsTableFilterComposer,
          $$ShoppingListItemsTableOrderingComposer,
          $$ShoppingListItemsTableAnnotationComposer,
          $$ShoppingListItemsTableCreateCompanionBuilder,
          $$ShoppingListItemsTableUpdateCompanionBuilder,
          (
            ShoppingItemRow,
            BaseReferences<
              _$HearthDatabase,
              $ShoppingListItemsTable,
              ShoppingItemRow
            >,
          ),
          ShoppingItemRow,
          PrefetchHooks Function()
        > {
  $$ShoppingListItemsTableTableManager(
    _$HearthDatabase db,
    $ShoppingListItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShoppingListItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShoppingListItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShoppingListItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> listId = const Value.absent(),
                Value<String> itemKey = const Value.absent(),
                Value<String?> foodId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double?> plannedCanonical = const Value.absent(),
                Value<String?> plannedKind = const Value.absent(),
                Value<String?> plannedUnit = const Value.absent(),
                Value<String> plannedRest = const Value.absent(),
                Value<double?> wantedCanonical = const Value.absent(),
                Value<String?> wantedKind = const Value.absent(),
                Value<String?> wantedUnit = const Value.absent(),
                Value<double?> onHandCanonical = const Value.absent(),
                Value<String?> onHandKind = const Value.absent(),
                Value<String?> onHandUnit = const Value.absent(),
                Value<bool> checked = const Value.absent(),
                Value<bool> isManual = const Value.absent(),
                Value<bool> hasUnquantified = const Value.absent(),
                Value<String?> storeTag = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> sourceRecipeIds = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShoppingListItemsCompanion(
                id: id,
                listId: listId,
                itemKey: itemKey,
                foodId: foodId,
                name: name,
                plannedCanonical: plannedCanonical,
                plannedKind: plannedKind,
                plannedUnit: plannedUnit,
                plannedRest: plannedRest,
                wantedCanonical: wantedCanonical,
                wantedKind: wantedKind,
                wantedUnit: wantedUnit,
                onHandCanonical: onHandCanonical,
                onHandKind: onHandKind,
                onHandUnit: onHandUnit,
                checked: checked,
                isManual: isManual,
                hasUnquantified: hasUnquantified,
                storeTag: storeTag,
                sortOrder: sortOrder,
                sourceRecipeIds: sourceRecipeIds,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String listId,
                required String itemKey,
                Value<String?> foodId = const Value.absent(),
                required String name,
                Value<double?> plannedCanonical = const Value.absent(),
                Value<String?> plannedKind = const Value.absent(),
                Value<String?> plannedUnit = const Value.absent(),
                Value<String> plannedRest = const Value.absent(),
                Value<double?> wantedCanonical = const Value.absent(),
                Value<String?> wantedKind = const Value.absent(),
                Value<String?> wantedUnit = const Value.absent(),
                Value<double?> onHandCanonical = const Value.absent(),
                Value<String?> onHandKind = const Value.absent(),
                Value<String?> onHandUnit = const Value.absent(),
                Value<bool> checked = const Value.absent(),
                Value<bool> isManual = const Value.absent(),
                Value<bool> hasUnquantified = const Value.absent(),
                Value<String?> storeTag = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> sourceRecipeIds = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ShoppingListItemsCompanion.insert(
                id: id,
                listId: listId,
                itemKey: itemKey,
                foodId: foodId,
                name: name,
                plannedCanonical: plannedCanonical,
                plannedKind: plannedKind,
                plannedUnit: plannedUnit,
                plannedRest: plannedRest,
                wantedCanonical: wantedCanonical,
                wantedKind: wantedKind,
                wantedUnit: wantedUnit,
                onHandCanonical: onHandCanonical,
                onHandKind: onHandKind,
                onHandUnit: onHandUnit,
                checked: checked,
                isManual: isManual,
                hasUnquantified: hasUnquantified,
                storeTag: storeTag,
                sortOrder: sortOrder,
                sourceRecipeIds: sourceRecipeIds,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ShoppingListItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$HearthDatabase,
      $ShoppingListItemsTable,
      ShoppingItemRow,
      $$ShoppingListItemsTableFilterComposer,
      $$ShoppingListItemsTableOrderingComposer,
      $$ShoppingListItemsTableAnnotationComposer,
      $$ShoppingListItemsTableCreateCompanionBuilder,
      $$ShoppingListItemsTableUpdateCompanionBuilder,
      (
        ShoppingItemRow,
        BaseReferences<
          _$HearthDatabase,
          $ShoppingListItemsTable,
          ShoppingItemRow
        >,
      ),
      ShoppingItemRow,
      PrefetchHooks Function()
    >;

class $HearthDatabaseManager {
  final _$HearthDatabase _db;
  $HearthDatabaseManager(this._db);
  $$RecipesTableTableManager get recipes =>
      $$RecipesTableTableManager(_db, _db.recipes);
  $$RecipeSectionsTableTableManager get recipeSections =>
      $$RecipeSectionsTableTableManager(_db, _db.recipeSections);
  $$RecipeIngredientsTableTableManager get recipeIngredients =>
      $$RecipeIngredientsTableTableManager(_db, _db.recipeIngredients);
  $$RecipeStepsTableTableManager get recipeSteps =>
      $$RecipeStepsTableTableManager(_db, _db.recipeSteps);
  $$RecipeFavoritesTableTableManager get recipeFavorites =>
      $$RecipeFavoritesTableTableManager(_db, _db.recipeFavorites);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db, _db.collections);
  $$RecipeCollectionsTableTableManager get recipeCollections =>
      $$RecipeCollectionsTableTableManager(_db, _db.recipeCollections);
  $$FoodsTableTableManager get foods =>
      $$FoodsTableTableManager(_db, _db.foods);
  $$FoodServingOptionsTableTableManager get foodServingOptions =>
      $$FoodServingOptionsTableTableManager(_db, _db.foodServingOptions);
  $$MealPlanDaysTableTableManager get mealPlanDays =>
      $$MealPlanDaysTableTableManager(_db, _db.mealPlanDays);
  $$MealPlanEntriesTableTableManager get mealPlanEntries =>
      $$MealPlanEntriesTableTableManager(_db, _db.mealPlanEntries);
  $$MacroTargetsTableTableManager get macroTargets =>
      $$MacroTargetsTableTableManager(_db, _db.macroTargets);
  $$IngredientMatchesTableTableManager get ingredientMatches =>
      $$IngredientMatchesTableTableManager(_db, _db.ingredientMatches);
  $$CookTimersTableTableManager get cookTimers =>
      $$CookTimersTableTableManager(_db, _db.cookTimers);
  $$FoodProfilesTableTableManager get foodProfiles =>
      $$FoodProfilesTableTableManager(_db, _db.foodProfiles);
  $$PreferencesTableTableManager get preferences =>
      $$PreferencesTableTableManager(_db, _db.preferences);
  $$CookSessionsTableTableManager get cookSessions =>
      $$CookSessionsTableTableManager(_db, _db.cookSessions);
  $$RecipePhotosTableTableManager get recipePhotos =>
      $$RecipePhotosTableTableManager(_db, _db.recipePhotos);
  $$PlanTemplatesTableTableManager get planTemplates =>
      $$PlanTemplatesTableTableManager(_db, _db.planTemplates);
  $$PendingWritesTableTableManager get pendingWrites =>
      $$PendingWritesTableTableManager(_db, _db.pendingWrites);
  $$ShoppingListsTableTableManager get shoppingLists =>
      $$ShoppingListsTableTableManager(_db, _db.shoppingLists);
  $$ShoppingListItemsTableTableManager get shoppingListItems =>
      $$ShoppingListItemsTableTableManager(_db, _db.shoppingListItems);
}
