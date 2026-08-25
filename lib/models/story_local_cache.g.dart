// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'story_local_cache.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetStoryLocalCacheCollection on Isar {
  IsarCollection<StoryLocalCache> get storyLocalCaches => this.collection();
}

const StoryLocalCacheSchema = CollectionSchema(
  name: r'StoryLocalCache',
  id: 641820057318,
  properties: {
    r'durationHours': PropertySchema(
      id: 0,
      name: r'durationHours',
      type: IsarType.long,
    ),
    r'expiresAt': PropertySchema(
      id: 1,
      name: r'expiresAt',
      type: IsarType.dateTime,
    ),
    r'localFilePath': PropertySchema(
      id: 2,
      name: r'localFilePath',
      type: IsarType.string,
    ),
    r'mediaType': PropertySchema(
      id: 3,
      name: r'mediaType',
      type: IsarType.string,
    ),
    r'originalStoryId': PropertySchema(
      id: 4,
      name: r'originalStoryId',
      type: IsarType.string,
    ),
    r'originalTimestamp': PropertySchema(
      id: 5,
      name: r'originalTimestamp',
      type: IsarType.dateTime,
    ),
    r'ownerId': PropertySchema(id: 6, name: r'ownerId', type: IsarType.string),
    r'publishedAt': PropertySchema(
      id: 7,
      name: r'publishedAt',
      type: IsarType.dateTime,
    ),
    r'remoteUrl': PropertySchema(
      id: 8,
      name: r'remoteUrl',
      type: IsarType.string,
    ),
    r'storyId': PropertySchema(id: 9, name: r'storyId', type: IsarType.string),
    r'text': PropertySchema(id: 10, name: r'text', type: IsarType.string),
    r'username': PropertySchema(
      id: 11,
      name: r'username',
      type: IsarType.string,
    ),
  },
  estimateSize: _storyLocalCacheEstimateSize,
  serialize: _storyLocalCacheSerialize,
  deserialize: _storyLocalCacheDeserialize,
  deserializeProp: _storyLocalCacheDeserializeProp,
  idName: r'id',
  indexes: {
    r'storyId': IndexSchema(
      id: 742893114304,
      name: r'storyId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'storyId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},
  getId: _storyLocalCacheGetId,
  getLinks: _storyLocalCacheGetLinks,
  attach: _storyLocalCacheAttach,
  version: '3.1.0+1',
);

int _storyLocalCacheEstimateSize(
  StoryLocalCache object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.localFilePath.length * 3;
  bytesCount += 3 + object.mediaType.length * 3;
  bytesCount += 3 + (object.originalStoryId?.length ?? 0) * 3;
  bytesCount += 3 + object.ownerId.length * 3;
  bytesCount += 3 + object.remoteUrl.length * 3;
  bytesCount += 3 + object.storyId.length * 3;
  bytesCount += 3 + object.text.length * 3;
  bytesCount += 3 + object.username.length * 3;
  return bytesCount;
}

void _storyLocalCacheSerialize(
  StoryLocalCache object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.durationHours);
  writer.writeDateTime(offsets[1], object.expiresAt);
  writer.writeString(offsets[2], object.localFilePath);
  writer.writeString(offsets[3], object.mediaType);
  writer.writeString(offsets[4], object.originalStoryId);
  writer.writeDateTime(offsets[5], object.originalTimestamp);
  writer.writeString(offsets[6], object.ownerId);
  writer.writeDateTime(offsets[7], object.publishedAt);
  writer.writeString(offsets[8], object.remoteUrl);
  writer.writeString(offsets[9], object.storyId);
  writer.writeString(offsets[10], object.text);
  writer.writeString(offsets[11], object.username);
}

StoryLocalCache _storyLocalCacheDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = StoryLocalCache();
  object.durationHours = reader.readLong(offsets[0]);
  object.expiresAt = reader.readDateTime(offsets[1]);
  object.id = id;
  object.localFilePath = reader.readString(offsets[2]);
  object.mediaType = reader.readString(offsets[3]);
  object.originalStoryId = reader.readStringOrNull(offsets[4]);
  object.originalTimestamp = reader.readDateTime(offsets[5]);
  object.ownerId = reader.readString(offsets[6]);
  object.publishedAt = reader.readDateTime(offsets[7]);
  object.remoteUrl = reader.readString(offsets[8]);
  object.storyId = reader.readString(offsets[9]);
  object.text = reader.readString(offsets[10]);
  object.username = reader.readString(offsets[11]);
  return object;
}

P _storyLocalCacheDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readDateTime(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readDateTime(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    case 11:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _storyLocalCacheGetId(StoryLocalCache object) => object.id;

List<IsarLinkBase<dynamic>> _storyLocalCacheGetLinks(StoryLocalCache object) =>
    [];

void _storyLocalCacheAttach(
  IsarCollection<dynamic> col,
  Id id,
  StoryLocalCache object,
) {
  object.id = id;
}

extension StoryLocalCacheQueryFilter
    on QueryBuilder<StoryLocalCache, StoryLocalCache, QFilterCondition> {
  QueryBuilder<StoryLocalCache, StoryLocalCache, QAfterFilterCondition>
  storyIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'storyId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }
}
