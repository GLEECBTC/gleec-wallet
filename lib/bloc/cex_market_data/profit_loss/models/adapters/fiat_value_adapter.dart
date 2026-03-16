import 'package:hive_ce/hive.dart';

import '../fiat_value.dart';

class FiatValueAdapter extends TypeAdapter<FiatValue> {
  @override
  final int typeId = 16;

  @override
  FiatValue read(BinaryReader reader) {
    final int numOfFields = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FiatValue(currency: fields[0] as String, value: fields[1] as double);
  }

  @override
  void write(BinaryWriter writer, FiatValue obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.currency)
      ..writeByte(1)
      ..write(obj.value);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FiatValueAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
