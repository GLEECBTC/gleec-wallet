void reloadPage() {}

bool canLogin(String? _) => true;

dynamic initWasm() async {}

Future<void> wasmRunMm2(
  String params,
  void Function(int, String) handleLog,
) async {}
dynamic wasmMm2Status() async {}
Future<dynamic> wasmRpc(String request) async {}

String wasmVersion() => '';

void changeTheme(int themeModeIndex) {}
void changeHtmlTheme(int themeIndex) {}
