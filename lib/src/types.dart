import 'questions.dart';

/// Token usage for a request.
class Usage {
  const Usage({required this.inputTokens, required this.outputTokens});

  factory Usage.fromJson(Map<String, Object?> json) {
    return Usage(
      inputTokens: (json['input_tokens'] as num).toInt(),
      outputTokens: (json['output_tokens'] as num).toInt(),
    );
  }

  final int inputTokens;
  final int outputTokens;
}

/// Answer for a named question.
sealed class Answer {
  const Answer();

  String get type;

  factory Answer.fromJson(Map<String, Object?> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'noul' => NoulAnswer.fromJson(json),
      'choice' => ChoiceAnswer.fromJson(json),
      'score' => ScoreAnswer.fromJson(json),
      _ => throw FormatException('Unknown answer type: $type'),
    };
  }

  NoulAnswer asNoul() {
    if (this is NoulAnswer) return this as NoulAnswer;
    throw StateError('Expected noul answer, got $type');
  }

  ChoiceAnswer asChoice() {
    if (this is ChoiceAnswer) return this as ChoiceAnswer;
    throw StateError('Expected choice answer, got $type');
  }

  ScoreAnswer asScore() {
    if (this is ScoreAnswer) return this as ScoreAnswer;
    throw StateError('Expected score answer, got $type');
  }
}

class NoulAnswer extends Answer {
  const NoulAnswer({required this.noul});

  factory NoulAnswer.fromJson(Map<String, Object?> json) {
    return NoulAnswer(noul: (json['noul'] as num).toDouble());
  }

  /// Probability of yes, 0–1.
  final double noul;

  @override
  String get type => 'noul';
}

class ChoiceAnswer extends Answer {
  const ChoiceAnswer({
    required this.choice,
    required this.confidence,
    required this.probabilities,
  });

  factory ChoiceAnswer.fromJson(Map<String, Object?> json) {
    final probs = json['probabilities'] as Map<String, Object?>? ?? {};
    return ChoiceAnswer(
      choice: json['choice'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      probabilities: _doubleMap(probs),
    );
  }

  final String choice;
  final double confidence;
  final Map<String, double> probabilities;

  @override
  String get type => 'choice';
}

class ScoreAnswer extends Answer {
  const ScoreAnswer({
    required this.score,
    required this.confidence,
    required this.legend,
    required this.probabilities,
  });

  factory ScoreAnswer.fromJson(Map<String, Object?> json) {
    final legendRaw = json['legend'] as Map<String, Object?>? ?? {};
    final probs = json['probabilities'] as Map<String, Object?>? ?? {};
    return ScoreAnswer(
      score: (json['score'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      legend: legendRaw,
      probabilities: _doubleMap(probs),
    );
  }

  final double score;
  final double confidence;
  final Map<String, Object?> legend;
  final Map<String, double> probabilities;

  @override
  String get type => 'score';
}

/// Answers keyed by question name, plus model and usage.
class SystemOneResult {
  const SystemOneResult({
    required this.model,
    required this.answers,
    required this.usage,
  });

  factory SystemOneResult.fromJson(Map<String, Object?> json) {
    final raw = json['answers'] as Map<String, Object?>? ?? {};
    return SystemOneResult(
      model: json['model'] as String,
      answers: {
        for (final e in raw.entries)
          e.key: Answer.fromJson(e.value as Map<String, Object?>),
      },
      usage: Usage.fromJson(json['usage'] as Map<String, Object?>),
    );
  }

  final String model;
  final Map<String, Answer> answers;
  final Usage usage;

  NoulAnswer noul(String name) => _require(name).asNoul();
  ChoiceAnswer choice(String name) => _require(name).asChoice();
  ScoreAnswer score(String name) => _require(name).asScore();

  Answer _require(String name) {
    final a = answers[name];
    if (a == null) throw StateError('No answer named "$name"');
    return a;
  }
}

Map<String, double> _doubleMap(Map<String, Object?> source) {
  if (source.isEmpty) return const {};
  if (source.values.every((value) => value is double)) {
    return source.cast<String, double>();
  }
  return {
    for (final e in source.entries) e.key: (e.value as num).toDouble(),
  };
}

/// Metadata for an available model.
class ModelCard {
  const ModelCard({
    required this.name,
    required this.description,
    required this.releaseDate,
  });

  factory ModelCard.fromJson(Map<String, Object?> json) {
    return ModelCard(
      name: json['name'] as String,
      description: json['description'] as String,
      releaseDate: json['release_date'] as String,
    );
  }

  final String name;
  final String description;
  final String releaseDate;
}

enum LogLevel { debug, info, warn, error, off }

/// Log sink compatible with `print`-style logging.
abstract interface class TypeSafeLogger {
  void debug(String message, [Object? extra]);
  void info(String message, [Object? extra]);
  void warn(String message, [Object? extra]);
  void error(String message, [Object? extra]);
}

/// Maps questions to JSON for `POST /v1/systemone`.
Map<String, Object?> questionsToJson(Map<String, Question> questions) => {
      for (final e in questions.entries) e.key: e.value.toJson(),
    };
