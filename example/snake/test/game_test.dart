import 'dart:math';

import 'package:jev_snake_demo/jev_snake_demo.dart';
import 'package:test/test.dart';

void main() {
  group('Hamiltonian cycle', () {
    for (final shape in [(4, 4), (4, 5), (5, 4), (24, 16)]) {
      test('${shape.$1} by ${shape.$2} visits and closes the board', () {
        final (width, height) = shape;
        final cycle = hamiltonianCycle(width, height);
        expect(cycle.toSet(), hasLength(width * height));
        expect(
            cycle.every(
                (c) => c.x >= 0 && c.x < width && c.y >= 0 && c.y < height),
            isTrue);
        for (var i = 0; i < cycle.length; i++) {
          final a = cycle[i];
          final b = cycle[(i + 1) % cycle.length];
          expect((a.x - b.x).abs() + (a.y - b.y).abs(), 1);
        }
      });
    }

    test('rejects dimensions that cannot form the supported cycle', () {
      for (final (width, height) in [(3, 4), (4, 3), (5, 5)]) {
        expect(() => hamiltonianCycle(width, height), throwsArgumentError);
      }
    });
  });

  test('tail vacancy, reverse collision, wall collision, and board clear', () {
    final game = SnakeGame(width: 4, height: 4, initialLength: 4);
    game.body = [Cell(1, 1), Cell(1, 2), Cell(0, 2), Cell(0, 1)];
    game.food = const Cell(3, 3);

    expect(game.legalReason(Direction.left), 'legal');
    expect(game.legalReason(Direction.down), 'reverse');
    game.step(Direction.left);
    expect(game.alive, isTrue);
    expect(game.body, hasLength(4));
    expect(game.head, const Cell(0, 1));
    game.step(Direction.left);
    expect(game.alive, isFalse);
    expect(game.deathReason, 'wall');

    final almostFull = SnakeGame(width: 4, height: 4, initialLength: 15);
    final safe = almostFull.moves().firstWhere((move) => move.safe);
    expect(almostFull.step(safe.direction), isTrue);
    expect(almostFull.won, isTrue);
    expect(almostFull.food, isNull);
    expect(almostFull.body, hasLength(16));
    expect(almostFull.score, 1);
    expect(almostFull.moves(), isEmpty);
  });

  test('safe choices complete a board without breaking cycle order', () {
    for (var seed = 0; seed < 12; seed++) {
      final game = SnakeGame(width: 6, height: 6, seed: seed);
      final random = Random(seed + 100);
      for (var step = 0; step < game.capacity * game.capacity; step++) {
        final safe = game.moves().where((move) => move.safe).toList();
        expect(safe, isNotEmpty);
        game.step(safe[random.nextInt(safe.length)].direction);
        expect(game.alive, isTrue);
        expect(game.cycleOrderValid(), isTrue);
        expect(game.body.toSet(), hasLength(game.body.length));
        expect(game.body.length, game.initialLength + game.score);
        if (game.won) break;
      }
      expect(game.won, isTrue, reason: 'seed $seed');
    }
  });

  test('same seed and actions reproduce the same game state', () {
    final first = SnakeGame(seed: 71);
    final second = SnakeGame(seed: 71);
    for (var i = 0; i < 100 && first.alive; i++) {
      final move = first.moves().where((move) => move.safe).reduce(
            (a, b) => a.advance > b.advance ? a : b,
          );
      first.step(move.direction);
      second.step(move.direction);
      expect(second.body, first.body);
      expect(second.food, first.food);
      expect(second.score, first.score);
      expect(second.ticks, first.ticks);
    }
  });

  test('reports food reachability through currently empty cells', () {
    final game = SnakeGame(width: 6, height: 6);
    final result = game.foodReachability();
    expect(result.reachable, isTrue);
    expect(result.openCells, greaterThan(game.body.length));
  });

  test('rejects an invalid initial length', () {
    expect(
      () => SnakeGame(width: 4, height: 4, initialLength: 1),
      throwsArgumentError,
    );
    expect(
      () => SnakeGame(width: 4, height: 4, initialLength: 16),
      throwsArgumentError,
    );
  });
}
