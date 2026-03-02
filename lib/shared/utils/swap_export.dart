import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_swap_status/my_swap_status_req.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';

Future<void> exportSwapData(BuildContext context, String uuid) async {
  final mm2Api = RepositoryProvider.of<Mm2Api>(context);
  final response = await mm2Api.getSwapStatus(MySwapStatusReq(uuid: uuid));
  final jsonStr = jsonEncode(response);
  await FileLoader.fromPlatform().save(
    fileName: 'swap_$uuid.json',
    data: jsonStr,
    type: LoadFileType.text,
  );
}
