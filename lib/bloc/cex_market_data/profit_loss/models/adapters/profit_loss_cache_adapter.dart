import 'package:hive_ce/hive.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss_cache.dart';

class ProfitLossCacheAdapter extends TypeAdapter<ProfitLossCache> {
  @override
  final int typeId = 14;

  @override
  ProfitLossCache read(BinaryReader reader) {
    final int numOfFields = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return ProfitLossCache(
      coinId: fields[0] as String,
      fiatCoinId: fields[1] as String,
      lastUpdated: fields[2] as DateTime,
      profitLosses: (fields[3] as List).cast(),
      walletId: fields[4] as String,
      // Load conditionally, and set a default value for backwards compatibility
      // with existing data
      isHdWallet: fields.containsKey(5) ? fields[5] as bool : false,
    );
  }

  @override
  void write(BinaryWriter writer, ProfitLossCache obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.coinId)
      ..writeByte(1)
      ..write(obj.fiatCoinId)
      ..writeByte(2)
      ..write(obj.lastUpdated)
      ..writeByte(3)
      ..write(obj.profitLosses)
      ..writeByte(4)
      ..write(obj.walletId)
      ..writeByte(5)
      ..write(obj.isHdWallet);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfitLossCacheAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
