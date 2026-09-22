import 'dart:async';

import 'package:nocterm/nocterm.dart' hide Cell;

import 'decision.dart';
import 'game.dart';

const _baseSeed = 7;
const _defaultFps = 12;
const _minimumFps = 1;
const _maximumFps = 30;
const _boardBorder = Color(0xFF38545D);
const _boardEmpty = Color(0xFF18323A);
const _boardFood = Color(0xFFFFCA72);
const _boardHead = Color(0xFFE3FFF3);

final class SnakeApp extends StatefulComponent {
  const SnakeApp({required this.decisions, this.onQuit, super.key});

  final DecisionProvider decisions;
  final void Function()? onQuit;

  @override
  State<SnakeApp> createState() => _SnakeAppState();
}

final class _SnakeAppState extends State<SnakeApp> {
  SnakeGame _game = SnakeGame();
  SnakeDecision? _decision;
  SnakeDecision? _lastDecision;
  Duration? _lastInferenceTime;
  String _status = 'ASKING JEV…';
  Object? _error;
  int _fps = _defaultFps;
  int _round = 1;
  int _bestScore = 0;
  int _interventions = 0;
  bool _paused = false;
  bool _busy = false;
  bool _quitting = false;
  int _generation = 0;
  Timer? _stepTimer;
  Timer? _roundTimer;
  Completer<void>? _cancellation;

  @override
  void initState() {
    _startDecision(rebuild: false);
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _roundTimer?.cancel();
    _cancelCurrentRequest();
    super.dispose();
  }

  void _startDecision({bool rebuild = true}) {
    if (_busy || _paused || _quitting || !_game.alive || _game.won) return;
    _busy = true;
    final generation = _generation;
    final cancellation = Completer<void>();
    _cancellation = cancellation;
    if (rebuild && mounted) {
      setState(() {
        _status = 'ASKING JEV…';
        _error = null;
      });
    } else {
      _status = 'ASKING JEV…';
      _error = null;
    }
    unawaited(_resolveDecision(generation, cancellation));
  }

  Future<void> _resolveDecision(
    int generation,
    Completer<void> cancellation,
  ) async {
    try {
      final decision = await component.decisions.decide(
        _game,
        cancellation: cancellation.future,
      );
      if (!mounted || generation != _generation || _quitting) return;
      _releaseRequest(cancellation);
      setState(() {
        _decision = decision;
        _lastDecision = decision;
        _lastInferenceTime = decision.inferenceTime;
        _status = _paused ? 'PAUSED · DECISION READY' : 'DECISION READY';
        _error = null;
      });
      if (!_paused) _scheduleStep(decision);
    } catch (error) {
      if (!mounted || generation != _generation || _quitting) return;
      _releaseRequest(cancellation);
      setState(() {
        _error = error;
        _decision = null;
        _status = 'API ERROR · NO MOVE EXECUTED';
      });
    } finally {
      _releaseRequest(cancellation);
      if (mounted &&
          generation != _generation &&
          !_paused &&
          !_quitting &&
          !_game.won &&
          _game.alive) {
        _startDecision();
      }
    }
  }

  void _releaseRequest(Completer<void> cancellation) {
    if (!identical(_cancellation, cancellation)) return;
    _cancellation = null;
    _busy = false;
  }

  void _scheduleStep(SnakeDecision decision) {
    _stepTimer?.cancel();
    final target =
        Duration(microseconds: Duration.microsecondsPerSecond ~/ _fps);
    final remaining = target - decision.inferenceTime;
    _stepTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _advance,
    );
  }

  void _advance() {
    final decision = _decision;
    if (decision == null || _paused || _quitting || _error != null) return;
    setState(() {
      _game.step(decision.executed);
      _bestScore = _game.score > _bestScore ? _game.score : _bestScore;
      if (decision.intervened) _interventions++;
      _decision = null;
      if (!_game.alive || _game.won) {
        _status =
            _game.won ? 'BOARD CLEAR' : 'GAME OVER · ${_game.deathReason}';
      } else {
        _status = 'ASKING JEV…';
      }
    });
    if (!_game.alive || _game.won) {
      _roundTimer?.cancel();
      _roundTimer = Timer(const Duration(seconds: 1), _startNextRound);
    } else {
      _startDecision();
    }
  }

  void _startNextRound() {
    if (_quitting || _paused) return;
    _resetRound();
  }

  void _resetRound() {
    _stepTimer?.cancel();
    _roundTimer?.cancel();
    _generation++;
    _cancelCurrentRequest();
    setState(() {
      _round++;
      _game = SnakeGame(seed: _baseSeed + _round - 1);
      _decision = null;
      _error = null;
      _status = _paused ? 'PAUSED' : 'ASKING JEV…';
    });
    if (!_paused && !_busy) _startDecision();
  }

  void _cancelCurrentRequest() {
    final cancellation = _cancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  bool _handleKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.keyC &&
        (event.isControlPressed || event.isAltPressed)) {
      _quit();
      return true;
    }

    switch (event.logicalKey) {
      case LogicalKey.keyQ:
        _quit();
        return true;
      case LogicalKey.space:
        final pausing = !_paused;
        setState(() {
          _paused = pausing;
          if (pausing) {
            _status = _busy
                ? 'PAUSED · WAITING FOR JEV'
                : _error != null
                    ? 'PAUSED · API ERROR'
                    : 'PAUSED';
          } else if (_game.won || !_game.alive) {
            _status = _game.won ? 'BOARD CLEAR' : 'GAME OVER';
          } else if (_decision != null) {
            _status = 'DECISION READY';
          } else if (_error != null) {
            _status = 'API ERROR · PRESS ENTER TO RETRY';
          } else {
            _status = 'ASKING JEV…';
          }
        });
        if (pausing) {
          _stepTimer?.cancel();
          _roundTimer?.cancel();
        } else if (_game.won || !_game.alive) {
          _roundTimer = Timer(const Duration(seconds: 1), _startNextRound);
        } else if (_decision != null) {
          _scheduleStep(_decision!);
        } else if (_error == null && !_busy) {
          _startDecision();
        }
        return true;
      case LogicalKey.arrowUp:
        setState(() {
          _fps = (_fps + 1).clamp(_minimumFps, _maximumFps).toInt();
        });
        if (_decision != null && !_paused) _scheduleStep(_decision!);
        return true;
      case LogicalKey.arrowDown:
        setState(() {
          _fps = (_fps - 1).clamp(_minimumFps, _maximumFps).toInt();
        });
        if (_decision != null && !_paused) _scheduleStep(_decision!);
        return true;
      case LogicalKey.keyR:
        _resetRound();
        return true;
      case LogicalKey.enter:
        if (_error != null && !_paused && !_busy) _startDecision();
        return true;
      default:
        return false;
    }
  }

  void _quit() {
    if (_quitting) return;
    _quitting = true;
    _generation++;
    _stepTimer?.cancel();
    _roundTimer?.cancel();
    _cancelCurrentRequest();
    component.onQuit?.call();
  }

  @override
  Component build(BuildContext context) {
    final decision = _decision;
    final displayDecision = decision ?? _lastDecision;
    return TuiTheme(
      data: TuiThemeData.dark,
      child: Focusable(
        focused: true,
        onKeyEvent: _handleKey,
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'JEV  /  SNAKE DEMO',
                    style: TextStyle(
                        color: Colors.cyan, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _paused ? 'PAUSED' : _status,
                    style: TextStyle(
                      color: _error != null
                          ? Colors.red
                          : _paused
                              ? Colors.yellow
                              : decision != null
                                  ? Colors.green
                                  : Colors.cyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text('─' * 102, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 1),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ROUND ${_round.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.cyan),
                      ),
                      ..._boardRows(),
                      const SizedBox(height: 1),
                      Text(
                        'SCORE  ${_game.score.toString().padLeft(3, '0')}',
                        style: const TextStyle(
                            color: Color(0xFF62F5B5),
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'LENGTH ${_game.body.length.toString().padLeft(3, '0')}',
                        style: const TextStyle(color: Color(0xFF8AD8E9)),
                      ),
                      Text(
                        'BEST   ${_bestScore.toString().padLeft(3, '0')}',
                        style: const TextStyle(color: Color(0xFFFFCA72)),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'JEV  /  ONLINE',
                          style: TextStyle(
                              color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'TARGET SPEED  $_fps moves/s',
                          style: const TextStyle(color: Color(0xFF8AD8E9)),
                        ),
                        Text(
                          'SHIELD EVENTS  $_interventions',
                          style: const TextStyle(color: Color(0xFFFFCA72)),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          decision != null
                              ? 'NEXT MOVE · PROBABILITIES'
                              : _lastDecision != null
                                  ? 'LAST MOVE · PROBABILITIES'
                                  : 'NEXT MOVE · PROBABILITIES',
                          style: const TextStyle(color: Colors.white),
                        ),
                        for (final direction in directions)
                          _probabilityLine(direction, displayDecision),
                        const SizedBox(height: 1),
                        Text(
                          displayDecision == null
                              ? 'Proposed: —   Executed: —'
                              : 'Proposed: ${displayDecision.proposed.label}  Executed: ${displayDecision.executed.label}',
                          style: const TextStyle(color: Colors.cyan),
                        ),
                        Text(
                          displayDecision == null
                              ? 'Risk: —   Food reachable: —'
                              : 'Dead-end risk: ${(displayDecision.deadEndRisk * 100).toStringAsFixed(1)}%  Food: ${(displayDecision.foodReachable * 100).toStringAsFixed(1)}%',
                        ),
                        Text(
                          _lastInferenceTime == null
                              ? 'LAST INFERENCE TIME   —'
                              : 'LAST INFERENCE TIME   ${(_lastInferenceTime!.inMicroseconds / 1000).toStringAsFixed(1)} ms',
                          style: const TextStyle(
                            color: Color(0xFF8AD8E9),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (displayDecision?.intervened ?? false)
                          const Text(
                            'LAST SHIELD INTERVENTION · unsafe proposal corrected',
                            style: TextStyle(color: Colors.yellow),
                          ),
                        if (_error != null) ...[
                          const Text(
                            'Jev request failed. No move was made.',
                            style: TextStyle(color: Colors.red),
                          ),
                          Text('$_error', maxLines: 2),
                          const Text('ENTER retries · R resets · Q quits'),
                        ],
                        if (_status == 'BOARD CLEAR' || !_game.alive)
                          const Text('Starting the next round shortly…'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              const Text(
                'SPACE pause   ↑/↓ speed   R restart   Q / Ctrl+C / Option+C quit',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Component> _boardRows() {
    final bodyIndexes = {
      for (var i = 0; i < _game.body.length; i++) _game.body[i]: i,
    };
    final rows = <Component>[
      Text(
        '┌${'──' * _game.width}┐',
        style: const TextStyle(color: _boardBorder),
      ),
    ];
    for (var y = 0; y < _game.height; y++) {
      final spans = <InlineSpan>[
        const TextSpan(text: '│', style: TextStyle(color: _boardBorder)),
      ];
      for (var x = 0; x < _game.width; x++) {
        final cell = Cell(x, y);
        final bodyIndex = bodyIndexes[cell];
        if (cell == _game.head) {
          spans.add(const TextSpan(
            text: '▓▓',
            style: TextStyle(color: _boardHead, fontWeight: FontWeight.bold),
          ));
        } else if (bodyIndex != null) {
          spans.add(TextSpan(
            text: '██',
            style: TextStyle(
              color: _bodyGradientColor(bodyIndex, _game.body.length),
            ),
          ));
        } else if (cell == _game.food) {
          spans.add(const TextSpan(
            text: '● ',
            style: TextStyle(color: _boardFood, fontWeight: FontWeight.bold),
          ));
        } else {
          spans.add(const TextSpan(
            text: '· ',
            style: TextStyle(color: _boardEmpty),
          ));
        }
      }
      spans.add(
          const TextSpan(text: '│', style: TextStyle(color: _boardBorder)));
      rows.add(RichText(text: TextSpan(children: spans)));
    }
    rows.add(Text(
      '└${'──' * _game.width}┘',
      style: const TextStyle(color: _boardBorder),
    ));
    return rows;
  }

  Color _bodyGradientColor(int bodyIndex, int bodyLength) {
    final t = ((bodyIndex - 1) / (bodyLength - 2).clamp(1, bodyLength))
        .clamp(0.0, 1.0);
    int channel(int start, int end) => (start + (end - start) * t).round();
    return Color.fromRGB(
      channel(0x62, 0x17),
      channel(0xF5, 0x68),
      channel(0xB5, 0x4E),
    );
  }

  Component _probabilityLine(Direction direction, SnakeDecision? decision) {
    final probability = decision?.probabilities[direction] ?? 0;
    final filled = (probability * 16).round().clamp(0, 16);
    final selected = decision?.proposed == direction;
    final marker = selected ? '›' : ' ';
    final bar = '█' * filled + '░' * (16 - filled);
    final percentage = (probability * 100).toStringAsFixed(1).padLeft(5);
    return Text(
      '$marker ${direction.label.padRight(5)} $bar $percentage%',
      style: TextStyle(color: selected ? Colors.green : Colors.grey),
    );
  }
}
