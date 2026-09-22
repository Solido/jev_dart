import 'dart:async';

import 'package:jev_snake_demo/jev_snake_demo.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

final class _FakeDecisionProvider implements DecisionProvider {
  _FakeDecisionProvider(this.respond);

  final Future<SnakeDecision> Function(SnakeGame game, int call) respond;
  int calls = 0;

  @override
  Future<SnakeDecision> decide(
    SnakeGame game, {
    Future<void>? cancellation,
  }) {
    calls++;
    return respond(game, calls);
  }
}

SnakeDecision _safeDecision(SnakeGame game) {
  final moves = game.moves();
  final safe = moves.where((move) => move.safe).toList();
  final selected = safe.first.direction;
  return SnakeDecision(
    probabilities: {
      for (final direction in directions)
        direction: direction == selected ? 0.7 : 0.1,
    },
    proposed: selected,
    executed: selected,
    safeDirections: [for (final move in safe) move.direction],
    intervened: false,
    deadEndRisk: 0.03,
    foodReachable: 0.92,
    inferenceTime: Duration.zero,
    inputTokens: 100,
    outputTokens: 0,
  );
}

Future<void> _flush(NoctermTester tester) async {
  await Future<void>.delayed(Duration.zero);
  await tester.pump();
}

void main() {
  test('renders the game and handles pause, speed, restart, and quit',
      () async {
    await testNocterm(
      'Snake demo controls',
      (tester) async {
        final provider = _FakeDecisionProvider(
          (game, _) async => _safeDecision(game),
        );
        var quit = false;
        await tester.pumpComponent(
          SnakeApp(decisions: provider, onQuit: () => quit = true),
        );
        await _flush(tester);

        expect(tester.terminalState, containsText('JEV  /  ONLINE'));
        expect(tester.terminalState, containsText('NEXT MOVE'));
        expect(tester.terminalState, containsText('SCORE  000'));
        expect(tester.terminalState,
            isNot(containsText('Waiting for Jev response')));
        expect(provider.calls, 1);

        await tester.sendKey(LogicalKey.space);
        expect(tester.terminalState, containsText('PAUSED'));
        await tester.sendArrowUp();
        expect(tester.terminalState, containsText('TARGET SPEED  13 moves/s'));
        await tester.sendKey(LogicalKey.keyR);
        expect(tester.terminalState, containsText('ROUND 02'));
        await tester.sendKey(LogicalKey.keyQ);
        expect(quit, isTrue);
      },
      size: const Size(120, 40),
    );
  });

  test('keeps the board still on a final API error and retries with Enter',
      () async {
    await testNocterm(
      'API error and retry',
      (tester) async {
        final provider = _FakeDecisionProvider((game, call) async {
          if (call == 1) throw StateError('offline');
          return _safeDecision(game);
        });
        await tester.pumpComponent(SnakeApp(decisions: provider));
        await _flush(tester);

        expect(tester.terminalState, containsText('NO MOVE EXECUTED'));
        expect(tester.terminalState, containsText('No move was made'));
        expect(tester.terminalState,
            isNot(containsText('Waiting for Jev response')));
        final frozenBoard = tester.renderToString(showBorders: false);
        await Future<void>.delayed(const Duration(milliseconds: 110));
        await tester.pump();
        expect(tester.renderToString(showBorders: false), frozenBoard);

        await tester.sendKey(LogicalKey.enter);
        await _flush(tester);
        expect(provider.calls, 2);
        expect(tester.terminalState, containsText('DECISION READY'));
        expect(tester.terminalState,
            isNot(containsText('Waiting for Jev response')));
        await tester.sendKey(LogicalKey.keyQ);
      },
      size: const Size(120, 40),
    );
  });

  test(
      'ignores an old prediction after a reset before requesting the new board',
      () async {
    await testNocterm(
      'discard stale decision',
      (tester) async {
        final first = Completer<SnakeDecision>();
        final provider = _FakeDecisionProvider((game, call) {
          if (call == 1) return first.future;
          return Future.value(_safeDecision(game));
        });
        await tester.pumpComponent(SnakeApp(decisions: provider));
        expect(provider.calls, 1);

        await tester.sendKey(LogicalKey.keyR);
        expect(tester.terminalState, containsText('ROUND 02'));
        first.complete(_safeDecision(SnakeGame()));
        await _flush(tester);
        await _flush(tester);

        expect(provider.calls, 2);
        expect(tester.terminalState, containsText('ROUND 02'));
        expect(tester.terminalState, containsText('DECISION READY'));
        await tester.sendKey(LogicalKey.keyQ);
      },
      size: const Size(120, 40),
    );
  });
}
