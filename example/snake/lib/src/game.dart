import 'dart:collection';
import 'dart:math';

const directions = <Direction>[
  Direction.up,
  Direction.down,
  Direction.left,
  Direction.right,
];

enum Direction { up, down, left, right }

extension DirectionLabel on Direction {
  String get label => switch (this) {
        Direction.up => 'UP',
        Direction.down => 'DOWN',
        Direction.left => 'LEFT',
        Direction.right => 'RIGHT',
      };

  Cell get vector => switch (this) {
        Direction.up => const Cell(0, -1),
        Direction.down => const Cell(0, 1),
        Direction.left => const Cell(-1, 0),
        Direction.right => const Cell(1, 0),
      };
}

final class Cell {
  const Cell(this.x, this.y);

  final int x;
  final int y;

  Cell operator +(Cell other) => Cell(x + other.x, y + other.y);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Cell && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

final class MoveInfo {
  const MoveInfo({
    required this.direction,
    required this.legal,
    required this.safe,
    required this.advance,
    required this.reason,
    required this.eats,
  });

  final Direction direction;
  final bool legal;
  final bool safe;
  final int advance;
  final String reason;
  final bool eats;
}

/// A deterministic Snake board and the cycle-based safety planner.
final class SnakeGame {
  SnakeGame({
    this.width = 24,
    this.height = 16,
    this.seed = 7,
    this.initialLength = 6,
  })  : cycle = hamiltonianCycle(width, height),
        _random = Random(seed) {
    capacity = width * height;
    indices = {for (var i = 0; i < cycle.length; i++) cycle[i]: i};
    if (initialLength < 2 || initialLength >= capacity) {
      throw ArgumentError.value(
        initialLength,
        'initialLength',
        'Must be at least 2 and smaller than the board capacity',
      );
    }
    final start = indices[Cell(width ~/ 2, height ~/ 2)]!;
    body = [
      for (var i = 0; i < initialLength; i++) cycle[(start - i) % capacity],
    ];
    food = _spawnFood();
  }

  final int width;
  final int height;
  final int seed;
  final int initialLength;
  final List<Cell> cycle;
  final Random _random;
  late final int capacity;
  late final Map<Cell, int> indices;
  late List<Cell> body;
  Cell? food;
  int score = 0;
  int ticks = 0;
  bool alive = true;
  bool won = false;
  String? deathReason;

  Cell get head => body.first;

  Cell _spawnFood() {
    final occupied = body.toSet();
    final empty = cycle.where((cell) => !occupied.contains(cell)).toList();
    return empty[_random.nextInt(empty.length)];
  }

  Cell target(Direction direction) => head + direction.vector;

  String legalReason(Direction direction) {
    final cell = target(direction);
    if (cell.x < 0 || cell.x >= width || cell.y < 0 || cell.y >= height) {
      return 'wall';
    }
    if (cell == body[1]) return 'reverse';
    final occupied = body.toSet();
    if (cell != food) occupied.remove(body.last);
    return occupied.contains(cell) ? 'body' : 'legal';
  }

  List<MoveInfo> moves() {
    if (!alive || won) return const [];
    final headIndex = indices[head]!;
    final tailDistance = (indices[body.last]! - headIndex) % capacity;
    final foodIndex = food == null ? headIndex : indices[food]!;
    final foodDistance = (foodIndex - headIndex) % capacity;
    return [
      for (final direction in directions)
        _moveInfo(
          direction,
          headIndex: headIndex,
          tailDistance: tailDistance,
          foodDistance: foodDistance,
        ),
    ];
  }

  MoveInfo _moveInfo(
    Direction direction, {
    required int headIndex,
    required int tailDistance,
    required int foodDistance,
  }) {
    var reason = legalReason(direction);
    final legal = reason == 'legal';
    final targetCell = target(direction);
    final advance = (indices[targetCell] ?? headIndex) - headIndex;
    final wrappedAdvance = advance % capacity;
    final eats = targetCell == food;
    var safe = legal;
    if (safe &&
        (wrappedAdvance > tailDistance ||
            (wrappedAdvance == tailDistance && eats))) {
      safe = false;
      reason = 'would cross the tail';
    }
    if (safe && (wrappedAdvance == 0 || wrappedAdvance > foodDistance)) {
      safe = false;
      reason = 'would skip the food on the safe route';
    }
    return MoveInfo(
      direction: direction,
      legal: legal,
      safe: safe,
      advance: wrappedAdvance,
      reason: reason,
      eats: eats,
    );
  }

  ({bool reachable, int openCells}) foodReachability() {
    final blocked = body.toSet()..remove(head);
    final visited = <Cell>{head};
    final queue = Queue<Cell>()..add(head);
    while (queue.isNotEmpty) {
      final cell = queue.removeFirst();
      for (final direction in directions) {
        final next = cell + direction.vector;
        if (next.x < 0 ||
            next.x >= width ||
            next.y < 0 ||
            next.y >= height ||
            blocked.contains(next) ||
            !visited.add(next)) {
          continue;
        }
        queue.add(next);
      }
    }
    return (
      reachable: food != null && visited.contains(food),
      openCells: visited.length
    );
  }

  bool step(Direction direction) {
    if (!alive || won) throw StateError('Cannot step a finished game');
    ticks++;
    final reason = legalReason(direction);
    if (reason != 'legal') {
      alive = false;
      deathReason = reason;
      return false;
    }
    final targetCell = target(direction);
    body.insert(0, targetCell);
    if (targetCell == food) {
      score++;
      if (body.length == capacity) {
        won = true;
        food = null;
      } else {
        food = _spawnFood();
      }
      return true;
    }
    body.removeLast();
    return false;
  }

  bool cycleOrderValid() {
    final ordered = body.reversed.map((cell) => indices[cell]!).toList();
    var total = 0;
    for (var i = 0; i + 1 < ordered.length; i++) {
      final distance = (ordered[i + 1] - ordered[i]) % capacity;
      if (distance <= 0) return false;
      total += distance;
    }
    return total < capacity;
  }
}

List<Cell> hamiltonianCycle(int width, int height) {
  if (width < 4 || height < 4 || (width.isOdd && height.isOdd)) {
    throw ArgumentError(
        'Board dimensions must be >= 4 with at least one even dimension');
  }
  if (height.isOdd) {
    return [
      for (final cell in hamiltonianCycle(height, width)) Cell(cell.y, cell.x)
    ];
  }

  final path = <Cell>[const Cell(0, 0)];
  for (var y = 0; y < height; y++) {
    if (y.isEven) {
      for (var x = 1; x < width; x++) {
        path.add(Cell(x, y));
      }
    } else {
      for (var x = width - 1; x > 0; x--) {
        path.add(Cell(x, y));
      }
    }
  }
  for (var y = height - 1; y > 0; y--) {
    path.add(Cell(0, y));
  }
  return path;
}
