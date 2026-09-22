import 'package:jev_dart/jev_dart.dart';

import 'game.dart';

final class SnakeDecision {
  SnakeDecision({
    required Map<Direction, double> probabilities,
    required this.proposed,
    required this.executed,
    required this.safeDirections,
    required this.intervened,
    required this.deadEndRisk,
    required this.foodReachable,
    required this.inferenceTime,
    required this.inputTokens,
    required this.outputTokens,
  }) : probabilities = Map.unmodifiable(probabilities);

  final Map<Direction, double> probabilities;
  final Direction proposed;
  final Direction executed;
  final List<Direction> safeDirections;
  final bool intervened;
  final double deadEndRisk;
  final double foodReachable;
  final Duration inferenceTime;
  final int inputTokens;
  final int outputTokens;
}

abstract interface class DecisionProvider {
  Future<SnakeDecision> decide(
    SnakeGame game, {
    Future<void>? cancellation,
  });
}

/// Uses Jev for the direction probabilities and keeps execution safety local.
final class JevDecisionProvider implements DecisionProvider {
  JevDecisionProvider(this.client, {this.model});

  final TypeSafeClient client;
  final String? model;

  @override
  Future<SnakeDecision> decide(
    SnakeGame game, {
    Future<void>? cancellation,
  }) async {
    final started = Stopwatch()..start();
    final moves = game.moves();
    final safe = moves.where((move) => move.safe).toList();
    if (safe.isEmpty) {
      throw StateError('Cycle safety invariant violated: no safe direction');
    }
    final preferred = safe.reduce(
      (best, move) => move.advance > best.advance ? move : best,
    );
    final reachability = game.foodReachability();
    final criteria = <String, Object?>{
      for (final move in moves)
        move.direction.label: !move.legal
            ? 'Blocked. Collision.'
            : !move.safe
                ? 'Unsafe. Traps the snake.'
                : move.eats
                    ? 'Safe. Eat food now. Best.'
                    : move.direction == preferred.direction
                        ? 'Safe. Best route to food.'
                        : 'Safe. Slower route.',
    };
    final result = await client.systemOne(
      state: 'Safe route: yes. '
          'Food reachable through empty cells: ${reachability.reachable ? 'yes' : 'no'}.',
      questions: {
        'move': choice('Choose the best safe move toward food.', criteria),
        'risk': noul('Is a safe route available?'),
        'food': noul('Is food reachable through empty cells?'),
      },
      model: model,
      cancellation: cancellation,
    );

    final answer = result.choice('move');
    final probabilities = <Direction, double>{};
    for (final direction in directions) {
      final probability = answer.probabilities[direction.label];
      if (probability == null ||
          !probability.isFinite ||
          probability < 0 ||
          probability > 1) {
        throw FormatException(
          'Jev returned an invalid probability for ${direction.label}',
        );
      }
      probabilities[direction] = probability;
    }
    final proposed = directions.reduce(
      (best, direction) =>
          probabilities[direction]! > probabilities[best]! ? direction : best,
    );
    final executed = safe.any((move) => move.direction == proposed)
        ? proposed
        : safe.map((move) => move.direction).reduce((best, direction) =>
            probabilities[direction]! > probabilities[best]!
                ? direction
                : best);
    final risk = result.noul('risk').noul;
    final foodReachable = result.noul('food').noul;
    if (!risk.isFinite || risk < 0 || risk > 1) {
      throw const FormatException(
          'Jev returned an invalid safe-route probability');
    }
    if (!foodReachable.isFinite || foodReachable < 0 || foodReachable > 1) {
      throw const FormatException('Jev returned an invalid food probability');
    }

    return SnakeDecision(
      probabilities: probabilities,
      proposed: proposed,
      executed: executed,
      safeDirections: [for (final move in safe) move.direction],
      intervened: proposed != executed,
      deadEndRisk: 1 - risk,
      foodReachable: foodReachable,
      inferenceTime: started.elapsed,
      inputTokens: result.usage.inputTokens,
      outputTokens: result.usage.outputTokens,
    );
  }
}
