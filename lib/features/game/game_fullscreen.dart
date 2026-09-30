import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/telemetry/crash_guard.dart';

/// ModalRoute's current-route dependency also handles pushes made outside the
/// game (including system navigation), without requiring a global observer.
class GameFullscreen extends StatefulWidget {
  const GameFullscreen({super.key, required this.child});

  final Widget child;

  @override
  State<GameFullscreen> createState() => _GameFullscreenState();
}

class _GameFullscreenState extends State<GameFullscreen>
    with WidgetsBindingObserver {
  static final Set<_GameFullscreenState> _active = {};
  static const _display = MethodChannel('purechess/display');
  bool _current = false;

  static Future<void> _updateMode() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        _active.isEmpty
            ? SystemUiMode.edgeToEdge
            : SystemUiMode.immersiveSticky,
      );
      // Android 15+ enforces edge-to-edge. Hide its insets explicitly rather
      // than depending on Flutter's legacy system UI visibility flags.
      if (Platform.isAndroid) {
        await _display.invokeMethod<void>('setImmersive', _active.isNotEmpty);
      }
    } catch (error, stack) {
      reportHandledError('game_fullscreen', error, stack);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (_current == current) return;
    _current = current;
    if (current) {
      _active.add(this);
    } else {
      _active.remove(this);
    }
    unawaited(_updateMode());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_updateMode());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _active.remove(this);
    unawaited(_updateMode());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
