import 'dart:math';

import 'package:hive_ce/hive.dart';
import 'package:web_dex/bloc/cex_market_data/models/graph_cache.dart';
import 'package:web_dex/bloc/cex_market_data/models/graph_type.dart';

class GraphCacheAdapter extends TypeAdapter<GraphCache> {
  @override
  final int typeId = 17;

  @override
  GraphCache read(BinaryReader reader) {
    final int numOfFields = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GraphCache(
      coinId: fields[0] as String,
      fiatCoinId: fields[1] as String,
      lastUpdated: fields[2] as DateTime,
      graph: (fields[3] as List<dynamic>).cast<Point<double>>(),
      graphType: GraphType.fromName(fields[4] as String),
      walletId: fields[5] as String,
      // Load conditionally, and set a default value for backwards compatibility
      // with existing data
      isHdWallet: fields.containsKey(6) ? fields[6] as bool : false,
    );
  }

  @override
  void write(BinaryWriter writer, GraphCache obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.coinId)
      ..writeByte(1)
      ..write(obj.fiatCoinId)
      ..writeByte(2)
      ..write(obj.lastUpdated)
      ..writeByte(3)
      ..write(obj.graph)
      ..writeByte(4)
      ..write(obj.graphType.name)
      ..writeByte(5)
      ..write(obj.walletId)
      ..writeByte(6)
      ..write(obj.isHdWallet);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphCacheAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
