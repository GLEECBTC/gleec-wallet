import 'package:flutter/material.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/common/screen_type.dart';

export 'package:web_dex/common/screen_type.dart';

bool get isMobile => screenType == ScreenType.mobile;
bool get isTablet => screenType == ScreenType.tablet;
bool get isDesktop => screenType == ScreenType.desktop;
bool get isWideScreen => windowWidth > maxScreenWidth + mainLayoutPadding;

bool get isNotMobile => !isMobile;
bool get isNotTablet => !isTablet;
bool get isNotDesktop => !isDesktop;

ScreenType _screenType = ScreenType.mobile;
ScreenType get screenType => _screenType;

double get screenWidth => _width;
double _width = 0;

double get screenHeight => _height;
double _height = 0;

/// Returns the screen type to its default. A widget test that sets another
/// must call this, or every later test in the isolate inherits it.
@visibleForTesting
void resetScreenType() {
  _screenType = ScreenType.mobile;
  _width = 0;
  _height = 0;
}

void updateScreenType(BuildContext context) {
  final size = MediaQuery.of(context).size;
  _width = size.width;
  _height = size.height;

  if (_width < 768) {
    _screenType = ScreenType.mobile;
  } else if (_width < 1024) {
    _screenType = ScreenType.tablet;
  } else {
    _screenType = ScreenType.desktop;
  }
}

/// Storing top context in global variable [materialPageContext]
/// allows us to use [isMobile], [isTablet], and [isDesktop] getters
/// without passing local context every single time.
///
// ignore: deprecated_member_use
/// [MediaQueryData.fromWindow] is deprecated and was replaced with
/// [MediaQueryData.fromView] on Flutter 3.10 due to the upcoming multi-window
/// support.

BuildContext? materialPageContext;
double get windowWidth => materialPageContext != null
    ? MediaQuery.of(materialPageContext!).size.width
    : MediaQueryData.fromView(View.of(materialPageContext!)).size.width;
