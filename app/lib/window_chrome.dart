import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

class WindowsChrome {
  WindowsChrome._();

  static final ffi.DynamicLibrary _user32 = ffi.DynamicLibrary.open('user32.dll');
  static final ffi.DynamicLibrary _gdi32 = ffi.DynamicLibrary.open('gdi32.dll');
  static final ffi.DynamicLibrary _dwmapi = ffi.DynamicLibrary.open('dwmapi.dll');

  static final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint16>, ffi.Pointer<ffi.Uint16>)
      _findWindow = _user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint16>, ffi.Pointer<ffi.Uint16>),
          ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Uint16>, ffi.Pointer<ffi.Uint16>)>('FindWindowW');

  static final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>) _getWindowRect =
      _user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>),
          int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>)>('GetWindowRect');

  static final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, int) _setWindowRgn =
      _user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Int32),
          int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, int)>('SetWindowRgn');

  static final ffi.Pointer<ffi.Void> Function(int, int, int, int, int, int) _createRoundRectRgn =
      _gdi32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
              ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32),
          ffi.Pointer<ffi.Void> Function(int, int, int, int, int, int)>('CreateRoundRectRgn');

  static final int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>, int)
      _dwmSetWindowAttribute = _dwmapi.lookupFunction<
          ffi.Int32 Function(
              ffi.Pointer<ffi.Void>, ffi.Uint32, ffi.Pointer<ffi.Void>, ffi.Uint32),
          int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>, int)>(
          'DwmSetWindowAttribute');

  static const int _immersiveDarkMode = 20;
  static const int _cornerPreference = 33;
  static const int _cornerDoNotRound = 1;
  static const int _radius = 6;

  static ffi.Pointer<ffi.Void>? _hwnd() {
    final title = 'SemFlix TV'.toNativeUtf16();
    final hwnd = _findWindow(ffi.nullptr, title.cast<ffi.Uint16>());
    calloc.free(title);
    return hwnd == ffi.nullptr ? null : hwnd;
  }

  static void _dwmSetInt(int attribute, int value) {
    final pref = calloc<ffi.Int32>();
    pref.value = value;
    _dwmSetWindowAttribute(
        _hwnd() ?? ffi.nullptr, attribute, pref.cast<ffi.Void>(), 4);
    calloc.free(pref);
  }

  static void applyRoundedCorners() {
    final hwnd = _hwnd();
    if (hwnd == null) return;

    _dwmSetInt(_immersiveDarkMode, 1);
    _dwmSetInt(_cornerPreference, _cornerDoNotRound);

    final rect = calloc<ffi.Int32>(4);
    if (_getWindowRect(hwnd, rect) == 0) {
      calloc.free(rect);
      return;
    }
    final w = rect.elementAt(2).value - rect.elementAt(0).value;
    final h = rect.elementAt(3).value - rect.elementAt(1).value;
    calloc.free(rect);
    if (w <= 0 || h <= 0) return;

    final region = _createRoundRectRgn(0, 0, w, h, _radius * 2, _radius * 2);
    if (region == ffi.nullptr) return;
    _setWindowRgn(hwnd, region, 1);
  }

  static void clearRoundedCorners() {
    final hwnd = _hwnd();
    if (hwnd == null) return;
    _setWindowRgn(hwnd, ffi.nullptr, 1);
  }
}
