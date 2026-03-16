import 'package:hive_ce/hive.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/fiat_value.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss.dart';

class ProfitLossAdapter extends TypeAdapter<ProfitLoss> {
  @override
  final int typeId = 15;

  @override
  ProfitLoss read(BinaryReader reader) {
    final int numOfFields = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProfitLoss(
      profitLoss: fields[0] as double,
      coin: fields[1] as String,
      fiatPrice: fields[2] as FiatValue,
      internalId: fields[3] as String,
      myBalanceChange: fields[4] as double,
      receivedAmountFiatPrice: fields[5] as double,
      spentAmountFiatPrice: fields[6] as double,
      timestamp: fields[7] as DateTime,
      totalAmount: fields[8] as double,
      txHash: fields[9] as String,
    );
  }

  @override
  void write(BinaryWriter writer, ProfitLoss obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.profitLoss)
      ..writeByte(1)
      ..write(obj.coin)
      ..writeByte(2)
      ..write(obj.fiatPrice)
      ..writeByte(3)
      ..write(obj.internalId)
      ..writeByte(4)
      ..write(obj.myBalanceChange)
      ..writeByte(5)
      ..write(obj.receivedAmountFiatPrice)
      ..writeByte(6)
      ..write(obj.spentAmountFiatPrice)
      ..writeByte(7)
      ..write(obj.timestamp)
      ..writeByte(8)
      ..write(obj.totalAmount)
      ..writeByte(9)
      ..write(obj.txHash);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfitLossAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
