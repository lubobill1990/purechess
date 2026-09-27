import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/board.dart';
import 'sound.dart';
import 'telemetry/analytics.dart';

enum FeedbackResult { playing, correct, incorrect, win, loss, draw, completed }

/// Observe immutable board snapshots, not the mutable session/controller.
class PlayFeedback extends StatefulWidget {
  const PlayFeedback({
    super.key,
    required this.session,
    required this.board,
    required this.source,
    required this.child,
    this.result = FeedbackResult.playing,
    this.celebration,
    this.prefs,
    this.analytics,
  });

  final Object session;
  final Board board;
  final String source;
  final FeedbackResult result;
  final String? celebration;
  final SharedPreferences? prefs;
  final Analytics? analytics;
  final Widget child;

  @override
  State<PlayFeedback> createState() => _PlayFeedbackState();
}

class _PlayFeedbackState extends State<PlayFeedback> {
  late final SoundService _sound;
  Timer? _dismiss;
  String? _title;
  bool _celebrated = false;
  int _event = 0;

  bool get _current {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        ModalRoute.of(context)?.isCurrent != false &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
  }

  @override
  void initState() {
    super.initState();
    _sound = SoundService(prefs: widget.prefs);
    // Opening an already-completed position must not replay its celebration.
    _celebrated = widget.result != FeedbackResult.playing;
  }

  @override
  void didUpdateWidget(PlayFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedSession = oldWidget.session != widget.session;
    if (changedSession ||
        (oldWidget.result != FeedbackResult.playing &&
            widget.result == FeedbackResult.playing)) {
      _dismiss?.cancel();
      _title = null;
      _celebrated = false;
      _sound.stop();
      _event++;
    }
    if (changedSession) return;
    final sounds = List.of(soundsForBoards(oldWidget.board, widget.board));
    if (oldWidget.result != widget.result) {
      final resultSound = switch (widget.result) {
        FeedbackResult.playing => null,
        FeedbackResult.correct ||
        FeedbackResult.completed => ChessSound.correct,
        FeedbackResult.incorrect => ChessSound.incorrect,
        FeedbackResult.win => ChessSound.victory,
        FeedbackResult.loss =>
          widget.board.status == GameStatus.checkmate
              ? ChessSound.checkmate
              : ChessSound.end,
        FeedbackResult.draw => ChessSound.end,
      };
      if (resultSound != null) {
        if (sounds.isNotEmpty) sounds.removeLast();
        sounds.add(resultSound);
      }
    }
    if (sounds.isNotEmpty && _current) {
      unawaited(_sound.play(sounds, isCurrent: () => _current));
    } else if (widget.board.plyCount < oldWidget.board.plyCount) {
      _sound.stop();
    }
    if (widget.celebration != null && !_celebrated) {
      _celebrated = true;
      if (!_current) return;
      _title = widget.celebration;
      final event = ++_event;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_current || event != _event || _title == null) return;
        (widget.analytics ?? Analytics.instance).event('celebrate_shown', {
          'source': widget.source,
          'result': widget.result.name,
        });
      });
      _dismiss?.cancel();
      _dismiss = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _title = null);
      });
    }
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    _sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      widget.child,
      if (_title != null)
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: CelebrationBadge(key: ValueKey(_event), title: _title!),
          ),
        ),
    ],
  );
}

class CelebrationBadge extends StatelessWidget {
  const CelebrationBadge({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduceMotion ? 1 : .85, end: 1),
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Material(
            elevation: 4,
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    color: colors.onPrimaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: colors.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
