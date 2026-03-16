import 'package:hive_ce/hive.dart';

import 'persistence_provider.dart';

abstract class PersistedBasicType<T> implements ObjectWithPrimaryKey<T> {
  PersistedBasicType(this.primaryKey, this.value);

  final T value;

  @override
  final T primaryKey;
}

class PersistedString extends PersistedBasicType<String> {
  PersistedString(super.primaryKey, super.value);
}

class PersistedStringAdapter extends TypeAdapter<PersistedString> {
  @override
  final int typeId = 12;

  @override
  PersistedString read(BinaryReader reader) {
    final int numOfFields = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PersistedString(fields[0] as String, fields[1] as String);
  }

  @override
  void write(BinaryWriter writer, PersistedString obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.primaryKey)
      ..writeByte(1)
      ..write(obj.value);
  }
}
