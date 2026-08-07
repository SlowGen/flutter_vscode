part of '../generator.dart';

// Concerns the reviewed slice: that selected strategies and their relations hold together.

void _validateWalkingSliceStrategies(
  Map<String, Map<String, Object?>> declarationsById,
  Map<String, String> strategiesById,
) {
  final bindings = _SelectedBindings(declarationsById, strategiesById);
  for (final entry in strategiesById.entries) {
    final declaration = declarationsById[entry.key]!;
    if (!_strategyAcceptsDeclaration(entry.value, declaration)) {
      throw VSCodeBindingGenerationException(
        'WALKING_SLICE_PROFILE_MISMATCH',
        'Semantic strategy ${entry.value} does not support the pinned shape '
            'of ${entry.key}. Update the general translation rule or choose '
            'a strategy that matches this declaration.',
      );
    }
  }

  const {
    'commandExecution',
    'commandRegistration',
    'eventSubscription',
    'eventType',
    'hoverProviderRegistration',
    'intEnumMember',
    'jsObjectLiteral',
    'markdownHoverConstructor',
    'markdownStringConstructor',
    'nativeJsEnum',
    'numericRangeConstructor',
    'providerCallback',
    'providerObject',
    'providerResultProjection',
    'stringSelectorProjection',
    'subscriptionsArray',
    'thenableBoolMethod',
    'thenableFutureBridge',
    'unaryUriMethod',
    'uriArrayObjectField',
    'uriJoinPath',
    'uriToString',
    'voidEventValue',
    'webviewPanelCreation',
  }.forEach(bindings.single);

  final positionMembers = bindings.withStrategy('intGetterProjection');
  if (positionMembers.isEmpty) {
    throw const VSCodeBindingGenerationException(
      'WALKING_SLICE_PROFILE_MISMATCH',
      'The intGetterProjection rule requires at least one selected property.',
    );
  }
  final position = bindings.parentOf(positionMembers.first);
  if (positionMembers.any(
    (member) => member['parentId'] != bindings.id(position),
  )) {
    throw const VSCodeBindingGenerationException(
      'WALKING_SLICE_PROFILE_MISMATCH',
      'Selected intGetterProjection properties must share one host object.',
    );
  }

  _validateWalkingSliceRelations(bindings);
}
