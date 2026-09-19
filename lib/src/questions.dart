import 'errors.dart';

/// A question identified by its `type` field.
sealed class Question {
  const Question({this.instructions, this.criteria});

  /// Text, JSON object/array, or `null`.
  final Object? instructions;
  final Object? criteria;

  String get type;

  Map<String, Object?> toJson() {
    return {
      'type': type,
      if (instructions != null) 'instructions': instructions,
      if (criteria != null) 'criteria': criteria,
    };
  }
}

/// Yes/no question with optional outcome descriptions.
final class NoulQuestion extends Question {
  const NoulQuestion({super.instructions, Map<String, Object?>? criteria})
      : super(criteria: criteria);

  @override
  String get type => 'noul';

  Map<String, Object?>? get noulCriteria => criteria as Map<String, Object?>?;
}

/// Selects among named labels.
final class ChoiceQuestion extends Question {
  const ChoiceQuestion({
    super.instructions,
    required Map<String, Object?> criteria,
  }) : super(criteria: criteria);

  @override
  String get type => 'choice';

  Map<String, Object?> get choiceCriteria => criteria as Map<String, Object?>;
}

/// Ordered rubric; scores are indices from zero.
final class ScoreQuestion extends Question {
  const ScoreQuestion({
    super.instructions,
    required List<Object?> criteria,
  }) : super(criteria: criteria);

  @override
  String get type => 'score';

  List<Object?> get scoreCriteria => criteria as List<Object?>;
}

/// Create a yes/no question.
NoulQuestion noul([
  Object? instructions,
  Map<String, Object?>? criteria,
]) =>
    NoulQuestion(instructions: instructions, criteria: criteria);

/// Create a choice question. [criteria] must be a map of labels.
ChoiceQuestion choice(Object? instructions, Map<String, Object?> criteria) {
  return ChoiceQuestion(instructions: instructions, criteria: criteria);
}

/// Create a score question. [criteria] must have at least two entries.
ScoreQuestion score(Object? instructions, List<Object?> criteria) {
  if (criteria.length < 2) {
    throw TypeSafeException(
      'Score criteria must be a list of descriptions indexed by score from '
      'zero, with at least two scores.',
    );
  }
  return ScoreQuestion(instructions: instructions, criteria: criteria);
}

/// Reject empty question sets and invalid score criteria.
void validateQuestions(Map<String, Question> questions) {
  if (questions.isEmpty) {
    throw TypeSafeException('At least one question is required.');
  }
  questions.forEach((name, question) {
    if (question is! ScoreQuestion) return;
    if (question.scoreCriteria.length < 2) {
      throw TypeSafeException(
        'Score question "$name" has ${question.scoreCriteria.length} criteria; '
        'at least two scores are required.',
      );
    }
  });
}
