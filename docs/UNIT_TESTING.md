# Unit and widget testing

Moved. See [TESTING.md](TESTING.md#2-unit-and-widget-tests).

`flutter test test_units/main.dart` **requires four `--dart-define`s** — without them ~36
GasFree tests hang rather than fail and wedge the whole run. The full command is in
TESTING.md.
