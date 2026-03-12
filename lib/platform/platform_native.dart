void reloadPage() {}

bool canLogin(String? _) => true;

Future<dynamic> initWasm() async {}

Future<void> wasmRunMm2(
  String params,
  void Function(int, String) handleLog,
) async {}
dynamic wasmMm2Status() async {}
dynamic wasmRpc(String request) async {}

String wasmVersion() => '';

void changeTheme(int themeModeIndex) {}
void changeHtmlTheme(int themeIndex) {}
