part of '../generator.dart';

// Concerns the generator itself: its failure type, its outputs, and the selected slice it walks.

/// A deterministic generation failure with a stable machine-readable code.
///
/// The one failure type is `package:dart_vscode`'s [ContributionException];
/// this maintainer-tool name survives as an alias so generation diagnostics
/// and contribution diagnostics stay a single catchable type.
typedef VSCodeBindingGenerationException = ContributionException;

final class _SelectedBindings {
  _SelectedBindings(this.declarationsById, this.strategiesById);

  final Map<String, Map<String, Object?>> declarationsById;
  final Map<String, String> strategiesById;

  List<Map<String, Object?>> withStrategy(String strategy) {
    final result = <Map<String, Object?>>[
      for (final entry in strategiesById.entries)
        if (entry.value == strategy) declarationsById[entry.key]!,
    ]..sort((left, right) => id(left).compareTo(id(right)));
    return result;
  }

  Map<String, Object?> single(String strategy) {
    final matches = withStrategy(strategy);
    if (matches.length != 1) {
      throw VSCodeBindingGenerationException(
        'WALKING_SLICE_PROFILE_MISMATCH',
        'The $strategy translation rule requires exactly one selected '
            'declaration, found ${matches.length}.',
      );
    }
    return matches.single;
  }

  Map<String, Object?> singleWhere(
    String strategy,
    bool Function(Map<String, Object?> declaration) predicate,
  ) {
    final matches = withStrategy(strategy).where(predicate).toList();
    if (matches.length != 1) {
      throw VSCodeBindingGenerationException(
        'WALKING_SLICE_PROFILE_MISMATCH',
        'The $strategy relation requires exactly one matching declaration, '
            'found ${matches.length}.',
      );
    }
    return matches.single;
  }

  Map<String, Object?> parentOf(Map<String, Object?> declaration) {
    final parentId = string(
      declaration['parentId'],
      'inventory declaration ${id(declaration)}.parentId',
    );
    final parent = declarationsById[parentId];
    if (parent == null) {
      throw VSCodeBindingGenerationException(
        'WALKING_SLICE_PROFILE_MISMATCH',
        'Selected declaration ${id(declaration)} has missing parent '
            '$parentId.',
      );
    }
    return parent;
  }

  List<Map<String, Object?>> childrenOf(
    Map<String, Object?> parent,
    String strategy,
  ) => withStrategy(
    strategy,
  ).where((candidate) => candidate['parentId'] == id(parent)).toList();

  Map<String, Object?> singleChildOf(
    Map<String, Object?> parent,
    String strategy,
  ) {
    final matches = childrenOf(parent, strategy);
    if (matches.length != 1) {
      throw VSCodeBindingGenerationException(
        'WALKING_SLICE_PROFILE_MISMATCH',
        'Selected ${string(parent['kind'], 'parent.kind')} ${id(parent)} '
            'requires exactly one $strategy child, found ${matches.length}.',
      );
    }
    return matches.single;
  }

  Map<String, Object?> parentWithChild(
    String parentStrategy,
    String childStrategy,
  ) => singleWhere(
    parentStrategy,
    (parent) => childrenOf(parent, childStrategy).isNotEmpty,
  );

  Map<String, Object?> selectedReference(Object? value) {
    final type = objectMap(value, 'selected reference type');
    if (type['kind'] != 'reference') {
      throw const VSCodeBindingGenerationException(
        'WALKING_SLICE_PROFILE_MISMATCH',
        'A selected reference relation did not contain a reference type.',
      );
    }
    final referenceName = string(type['name'], 'selected reference type.name');
    final matches = <Map<String, Object?>>[
      for (final entry in strategiesById.entries)
        if (entry.value != 'reviewedExcluded' &&
            name(declarationsById[entry.key]!) == referenceName)
          declarationsById[entry.key]!,
    ];
    if (matches.length != 1) {
      throw VSCodeBindingGenerationException(
        'WALKING_SLICE_PROFILE_MISMATCH',
        'Reference $referenceName must resolve to exactly one selected '
            'declaration, found ${matches.length}.',
      );
    }
    return matches.single;
  }

  String id(Map<String, Object?> declaration) =>
      string(declaration['id'], 'inventory declaration.id');

  String name(Map<String, Object?> declaration) => _dartIdentifier(
    declaration['name'],
    'inventory declaration ${id(declaration)}.name',
  );
}

/// Generates the reviewed VS Code API slice selected by Semantic Overrides.
final class VSCodeBindingGenerator {
  static const _strategies = {
    'boolObjectField',
    'boolGetterProjection',
    'commandExecution',
    'commandRegistration',
    'disposableStructuralType',
    'disposeMethod',
    'eventSubscription',
    'eventType',
    'eventValue',
    'hoverProviderRegistration',
    'intEnumMember',
    'intGetterProjection',
    'jsObjectLiteral',
    'markdownHoverConstructor',
    'markdownStringConstructor',
    'namespaceObject',
    'nativeJsClass',
    'nativeJsEnum',
    'numericRangeConstructor',
    'objectGetterProjection',
    'opaqueHostObject',
    'opaqueJsObject',
    'providerCallback',
    'providerObject',
    'providerResultProjection',
    'reviewedExcluded',
    'stringSelectorProjection',
    'stringGetterProjection',
    'stringGetterSetterProjection',
    'subscriptionsArray',
    'thenableBoolMethod',
    'thenableFutureBridge',
    'unaryUriMethod',
    'uriArrayObjectField',
    'uriJoinPath',
    'uriToString',
    'voidEventValue',
    'webviewPanelCreation',
  };

  /// Validates [overrides] against [inventory] with the full walking-slice
  /// review and returns the maintainer coverage ledger.
  String generateCoverageLedger({
    required Map<String, Object?> inventory,
    required Map<String, Object?> overrides,
  }) {
    validateInputSchemaVersion(inventory, 'inventory');
    validateInputSchemaVersion(overrides, 'overrides');
    validateIrExactKeys(
      inventory,
      const {
        'schemaVersion',
        'source',
        'manifestSchema',
        'manifestValidator',
        'contributionSchemas',
        'module',
        'declarations',
      },
      path: 'inventory',
    );
    validateIrModule(inventory['module']);
    _rejectUnexpectedKeys(
      overrides,
      const {
        'schemaVersion',
        'vscodeVersion',
        'manifestSchemaSha256',
        'manifestValidatorSha256',
        'commandsContributionSchemaSha256',
        'viewsContributionSchemaSha256',
        'configurationContributionSchemaSha256',
        'hostContracts',
        'targets',
        'entries',
        'removals',
      },
      subject: 'Semantic Override top-level object',
    );
    final source = validateIrSource(
      inventory['source'],
      inventory: inventory,
    );
    final product = objectMap(source['product'], 'inventory.source.product');
    final inventoryVersion = string(
      product['version'],
      'inventory.source.product.version',
    );
    final inputSha256 = sha256Digest(
      source['inputSha256'],
      'inventory.source.inputSha256',
    );
    final overrideVersion = string(
      overrides['vscodeVersion'],
      'overrides.vscodeVersion',
    );
    if (overrideVersion != inventoryVersion) {
      throw VSCodeBindingGenerationException(
        'OVERRIDE_VERSION_MISMATCH',
        'Semantic Overrides target VS Code $overrideVersion, but the '
            'inventory targets $inventoryVersion.',
      );
    }
    final manifestSchemaSha256 = validateManifestSchema(inventory);
    final overrideManifestSchemaSha256 = sha256Digest(
      overrides['manifestSchemaSha256'],
      'overrides.manifestSchemaSha256',
    );
    if (overrideManifestSchemaSha256 != manifestSchemaSha256) {
      throw VSCodeBindingGenerationException(
        'MANIFEST_SCHEMA_PIN_MISMATCH',
        'Semantic Overrides reviewed manifest schema '
            '$overrideManifestSchemaSha256, but the inventory uses '
            '$manifestSchemaSha256.',
      );
    }
    final manifestValidatorSha256 = validateManifestValidator(inventory);
    final overrideManifestValidatorSha256 = sha256Digest(
      overrides['manifestValidatorSha256'],
      'overrides.manifestValidatorSha256',
    );
    if (overrideManifestValidatorSha256 != manifestValidatorSha256) {
      throw VSCodeBindingGenerationException(
        'MANIFEST_VALIDATOR_PIN_MISMATCH',
        'Semantic Overrides reviewed manifest validator '
            '$overrideManifestValidatorSha256, but the inventory uses '
            '$manifestValidatorSha256.',
      );
    }
    final commandsContributionSchemaSha256 = validateCommandsContributionSchema(
      inventory,
    );
    final overrideCommandsContributionSchemaSha256 = sha256Digest(
      overrides['commandsContributionSchemaSha256'],
      'overrides.commandsContributionSchemaSha256',
    );
    if (overrideCommandsContributionSchemaSha256 !=
        commandsContributionSchemaSha256) {
      throw VSCodeBindingGenerationException(
        'CONTRIBUTION_SCHEMA_PIN_MISMATCH',
        'Semantic Overrides reviewed commands contribution schema '
            '$overrideCommandsContributionSchemaSha256, but the inventory '
            'uses $commandsContributionSchemaSha256.',
      );
    }
    final viewsContributionSchemaSha256 = validateViewsContributionSchemas(
      inventory,
    );
    final overrideViewsContributionSchemaSha256 = sha256Digest(
      overrides['viewsContributionSchemaSha256'],
      'overrides.viewsContributionSchemaSha256',
    );
    if (overrideViewsContributionSchemaSha256 !=
        viewsContributionSchemaSha256) {
      throw VSCodeBindingGenerationException(
        'CONTRIBUTION_SCHEMA_PIN_MISMATCH',
        'Semantic Overrides reviewed views contribution schema '
            '$overrideViewsContributionSchemaSha256, but the inventory '
            'uses $viewsContributionSchemaSha256.',
      );
    }
    final configurationContributionSchemaSha256 =
        validateConfigurationContributionSchema(inventory);
    final overrideConfigurationContributionSchemaSha256 = sha256Digest(
      overrides['configurationContributionSchemaSha256'],
      'overrides.configurationContributionSchemaSha256',
    );
    if (overrideConfigurationContributionSchemaSha256 !=
        configurationContributionSchemaSha256) {
      throw VSCodeBindingGenerationException(
        'CONTRIBUTION_SCHEMA_PIN_MISMATCH',
        'Semantic Overrides reviewed configuration contribution schema '
            '$overrideConfigurationContributionSchemaSha256, but the '
            'inventory uses $configurationContributionSchemaSha256.',
      );
    }
    final declarations = objectList(
      inventory['declarations'],
      'inventory.declarations',
    );
    final declarationsById = <String, Map<String, Object?>>{};
    final declarationPathsById = <String, String>{};
    for (var index = 0; index < declarations.length; index += 1) {
      final declarationValue = declarations[index];
      final path = 'inventory.declarations[$index]';
      final declaration = objectMap(
        declarationValue,
        path,
      );
      validateIrDeclarationKeys(declaration, path);
      final id = string(declaration['id'], 'inventory declaration.id');
      if (declarationsById.containsKey(id)) {
        throw VSCodeBindingGenerationException(
          'INVALID_GENERATOR_INPUT',
          'Inventory contains duplicate entry $id.',
        );
      }
      declarationsById[id] = declaration;
      declarationPathsById[id] = path;
    }
    validateIrDeclarationOrder(declarations);
    for (final entry in declarationsById.entries) {
      final path = declarationPathsById[entry.key]!;
      validateIrDeclarationIdentity(
        entry.value,
        path,
        declarationsById,
      );
      final inheritedScopes = irInheritedTypeParameterScopes(
        entry.value,
        declarationsById,
        path,
      );
      validateIrDeclarationTypes(
        entry.value,
        path,
        inheritedScopes: inheritedScopes,
      );
    }
    validateIrOverloadOrdinals(declarationsById, declarationPathsById);
    validateIrTypeLiteralGraph(declarationsById, declarationPathsById);
    final knownIds = declarationsById.keys.toSet();
    final publicIds = declarationsById.entries
        .where((entry) => entry.value['visibility'] == 'public')
        .map((entry) => entry.key)
        .toSet();
    if (overrides.containsKey('removals')) {
      _validateReviewedRemovals(overrides['removals'], publicIds);
    }
    final hostContracts = _validateHostContracts(overrides['hostContracts']);
    final entries = objectMap(overrides['entries'], 'overrides.entries');
    final targetList = <String>[
      for (final target in objectList(
        overrides['targets'],
        'overrides.targets',
      ))
        string(target, 'overrides.targets entry'),
    ];
    final targetIds = <String>{};
    for (final id in targetList) {
      if (!targetIds.add(id)) {
        throw VSCodeBindingGenerationException(
          'DUPLICATE_TARGET_ID',
          'Selected binding target $id appears more than once.',
        );
      }
    }
    final strategiesById = <String, String>{};
    final hostContractsById = <String, String>{};
    for (final id in entries.keys) {
      if (!knownIds.contains(id)) {
        throw VSCodeBindingGenerationException(
          'UNKNOWN_OVERRIDE_ID',
          'Semantic Override $id does not match any inventory entry.',
        );
      }
      if (!targetIds.contains(id)) {
        throw VSCodeBindingGenerationException(
          'UNUSED_OVERRIDE',
          'Semantic Override $id is outside the selected binding closure.',
        );
      }
      final entry = objectMap(entries[id], 'overrides.entries.$id');
      final strategy = string(
        entry['strategy'],
        'overrides.entries.$id.strategy',
      );
      if (!_strategies.contains(strategy)) {
        throw VSCodeBindingGenerationException(
          'UNKNOWN_OVERRIDE_STRATEGY',
          'Semantic Override $id uses unknown strategy $strategy.',
        );
      }
      final expectedDeclarationSha256 = string(
        entry['declarationSha256'],
        'overrides.entries.$id.declarationSha256',
      );
      final actualDeclarationSha256 = computeDeclarationFingerprint(
        declarationsById[id]!,
      );
      if (expectedDeclarationSha256 != actualDeclarationSha256) {
        throw VSCodeBindingGenerationException(
          'STALE_SEMANTIC_OVERRIDE',
          'Semantic Override $id reviewed declaration '
              '$expectedDeclarationSha256, but the pinned inventory now has '
              '$actualDeclarationSha256.',
        );
      }
      if (strategy == 'reviewedExcluded') {
        if (entry.containsKey('hostContract')) {
          throw VSCodeBindingGenerationException(
            'INVALID_OVERRIDE',
            'Reviewed exclusion $id cannot cite a Host Contract.',
          );
        }
        final reason = entry['reason'];
        if (reason is! String || isEcmaScriptFalsyOrWhitespace(reason)) {
          throw VSCodeBindingGenerationException(
            'INVALID_OVERRIDE',
            'Reviewed exclusion $id requires a non-empty reason.',
          );
        }
      } else {
        final hostContractValue = entry['hostContract'];
        if (hostContractValue is! String || hostContractValue.isEmpty) {
          throw VSCodeBindingGenerationException(
            'INVALID_OVERRIDE',
            'Emitted binding $id must cite an executable Host Contract.',
          );
        }
        final hostContract = hostContractValue;
        if (!hostContracts.containsKey(hostContract)) {
          throw VSCodeBindingGenerationException(
            'INVALID_OVERRIDE',
            'Emitted binding $id cites unknown Host Contract $hostContract.',
          );
        }
        hostContractsById[id] = hostContract;
      }
      _rejectUnexpectedKeys(
        entry,
        strategy == 'reviewedExcluded'
            ? const {'strategy', 'declarationSha256', 'reason'}
            : const {'strategy', 'declarationSha256', 'hostContract'},
        subject: 'Semantic Override entry $id',
      );
      strategiesById[id] = strategy;
    }
    for (final id in targetIds) {
      if (!publicIds.contains(id)) {
        throw VSCodeBindingGenerationException(
          'UNKNOWN_TARGET_ID',
          'Selected binding target $id does not match any public inventory '
              'entry.',
        );
      }
      if (!entries.containsKey(id)) {
        throw VSCodeBindingGenerationException(
          'MISSING_OVERRIDE',
          'Selected binding target $id has no Semantic Override.',
        );
      }
    }

    final observedHostContracts = hostContractsById.values.toSet();
    final unusedHostContracts =
        hostContracts.keys
            .where((contract) => !observedHostContracts.contains(contract))
            .toList()
          ..sort();
    if (unusedHostContracts.isNotEmpty) {
      throw VSCodeBindingGenerationException(
        'INVALID_OVERRIDE',
        'Semantic Overrides contain unused Host Contracts: '
            '${unusedHostContracts.map((contract) => '$contract is not cited').join(', ')}.',
      );
    }

    final walkingSlice = strategiesById.values.any(
      (strategy) => strategy != 'opaqueJsObject',
    );
    if (walkingSlice) {
      _validateWalkingSliceStrategies(declarationsById, strategiesById);
    }
    return emitCoverageLedger(
      inventoryVersion: inventoryVersion,
      inputSha256: inputSha256,
      manifestSchemaSha256: manifestSchemaSha256,
      manifestValidatorSha256: manifestValidatorSha256,
      commandsContributionSchemaSha256: commandsContributionSchemaSha256,
      viewsContributionSchemaSha256: viewsContributionSchemaSha256,
      configurationContributionSchemaSha256:
          configurationContributionSchemaSha256,
      declarationsById: declarationsById,
      entries: entries,
      strategiesById: strategiesById,
      hostContracts: hostContracts,
      hostContractsById: hostContractsById,
    );
  }
}

void _validateWalkingSliceRelations(_SelectedBindings bindings) {
  // This local assertion reads most clearly as `(declaration, condition,
  // relationship)` at each call site.
  void expectRelation(
    Map<String, Object?> declaration,
    // The condition reads as the subject of this local assertion.
    // ignore: avoid_positional_boolean_parameters
    bool matches,
    String relationship,
  ) {
    if (!matches) {
      throw VSCodeBindingGenerationException(
        'WALKING_SLICE_PROFILE_MISMATCH',
        'Selected declaration ${bindings.id(declaration)} does not satisfy '
            'the $relationship relation required by its generated Dart '
            'binding.',
      );
    }
  }

  bool references(
    Object? value,
    Map<String, Object?> target, {
    int? typeArgumentCount,
  }) {
    if (!_isType(value, kind: 'reference', name: bindings.name(target))) {
      return false;
    }
    if (typeArgumentCount == null) {
      return true;
    }
    final arguments = (value! as Map<Object?, Object?>)['typeArguments'];
    return arguments is List<Object?> && arguments.length == typeArgumentCount;
  }

  bool containsReference(
    Object? value,
    Map<String, Object?> target,
  ) {
    if (references(value, target)) {
      return true;
    }
    if (value is! Map<Object?, Object?>) {
      return false;
    }
    final types = value['types'];
    return types is List<Object?> &&
        types.any((candidate) => references(candidate, target));
  }

  Object? referenceArgument(Object? value, int index) {
    if (!_isType(value, kind: 'reference')) {
      return null;
    }
    final arguments = (value! as Map<Object?, Object?>)['typeArguments'];
    if (arguments is! List<Object?> || index >= arguments.length) {
      return null;
    }
    return arguments[index];
  }

  Object? arrayElement(Object? value) {
    if (!_isType(value, kind: 'array')) {
      return null;
    }
    return (value! as Map<Object?, Object?>)['elementType'];
  }

  Object? readonlyArrayElement(Object? value) {
    if (!_isType(value, kind: 'operator')) {
      return null;
    }
    final operator = value! as Map<Object?, Object?>;
    if (operator['operator'] != 'readonly') {
      return null;
    }
    return arrayElement(operator['type']);
  }

  final thenable = bindings.single('thenableFutureBridge');
  final event = bindings.single('eventType');
  final disposable = bindings.parentWithChild(
    'nativeJsClass',
    'disposeMethod',
  );
  final uriJoinPath = bindings.single('uriJoinPath');
  final uri = bindings.parentOf(uriJoinPath);
  final positionMembers = bindings.withStrategy('intGetterProjection');
  final position = bindings.parentOf(positionMembers.first);
  final cancellationProperty = bindings.single('boolGetterProjection');
  final cancellationToken = bindings.parentOf(cancellationProperty);
  final markdownConstructor = bindings.single('markdownStringConstructor');
  final markdown = bindings.parentOf(markdownConstructor);
  final rangeConstructor = bindings.single('numericRangeConstructor');
  final range = bindings.parentOf(rangeConstructor);
  final hoverConstructor = bindings.single('markdownHoverConstructor');
  final hover = bindings.parentOf(hoverConstructor);
  final viewColumnMember = bindings.single('intEnumMember');
  final viewColumn = bindings.parentOf(viewColumnMember);
  final webviewPostMessage = bindings.single('thenableBoolMethod');
  final webview = bindings.parentOf(webviewPostMessage);
  final panelDisposeEvent = bindings.single('voidEventValue');
  final webviewPanel = bindings.parentOf(panelDisposeEvent);
  final webviewOptions = bindings.single('jsObjectLiteral');
  final provider = bindings.single('providerObject');
  final providerResult = bindings.single('providerResultProjection');
  final documentSelector = bindings.single('stringSelectorProjection');

  for (final constructor in [
    markdownConstructor,
    rangeConstructor,
    hoverConstructor,
  ]) {
    final parent = bindings.parentOf(constructor);
    expectRelation(
      parent,
      parent['kind'] == 'class' && parent['abstract'] == false,
      'non-abstract native class behind an emitted constructor',
    );
  }

  final commandExecution = bindings.single('commandExecution');
  final commandRegistration = bindings.single('commandRegistration');
  expectRelation(
    commandRegistration,
    commandRegistration['parentId'] == commandExecution['parentId'],
    'shared commands namespace',
  );
  expectRelation(
    commandExecution,
    references(commandExecution['returnType'], thenable, typeArgumentCount: 1),
    'selected Thenable return type',
  );
  expectRelation(
    commandRegistration,
    references(commandRegistration['returnType'], disposable),
    'selected Disposable return type',
  );

  final eventSubscription = bindings.single('eventSubscription');
  final eventSubscriptionParameters = _declarationParameters(
    eventSubscription,
  );
  expectRelation(
    eventSubscription,
    eventSubscription['parentId'] == bindings.id(event) &&
        _functionConsumesSingleTypeParameter(
          eventSubscriptionParameters.first['type'],
          event,
        ),
    'selected Event call signature parent and listener generic',
  );
  expectRelation(
    eventSubscription,
    references(eventSubscription['returnType'], disposable) &&
        references(
          arrayElement(eventSubscriptionParameters[2]['type']),
          disposable,
        ),
    'selected Disposable event subscription types',
  );
  for (final eventValue in bindings.withStrategy('eventValue')) {
    expectRelation(
      eventValue,
      references(eventValue['type'], event, typeArgumentCount: 1),
      'selected Event value type',
    );
  }
  expectRelation(
    panelDisposeEvent,
    references(panelDisposeEvent['type'], event, typeArgumentCount: 1),
    'selected Event<void> value type',
  );

  expectRelation(
    webviewPostMessage,
    references(
      webviewPostMessage['returnType'],
      thenable,
      typeArgumentCount: 1,
    ),
    'selected Thenable<boolean> return type',
  );
  final webviewUri = bindings.single('unaryUriMethod');
  final webviewUriParameters = _declarationParameters(webviewUri);
  expectRelation(
    webviewUri,
    webviewUri['parentId'] == bindings.id(webview) &&
        references(webviewUriParameters.single['type'], uri) &&
        references(webviewUri['returnType'], uri),
    'selected Webview and Uri types',
  );
  for (final strategy in const [
    'stringGetterProjection',
    'stringGetterSetterProjection',
  ]) {
    final property = bindings.single(strategy);
    expectRelation(
      property,
      property['parentId'] == bindings.id(webview),
      'selected Webview parent',
    );
  }
  final webviewReceive = bindings.singleWhere(
    'eventValue',
    (declaration) => declaration['kind'] == 'property',
  );
  expectRelation(
    webviewReceive,
    webviewReceive['parentId'] == bindings.id(webview) &&
        _isReferenceWithSingleArgument(
          webviewReceive['type'],
          bindings.name(event),
          'primitive',
          'any',
        ),
    'selected Webview parent and message value type',
  );

  final uriToString = bindings.single('uriToString');
  expectRelation(
    uriToString,
    uriToString['parentId'] == bindings.id(uri),
    'selected Uri parent',
  );
  final optionsRoots = bindings.single('uriArrayObjectField');
  expectRelation(
    optionsRoots,
    optionsRoots['parentId'] == bindings.id(webviewOptions) &&
        references(readonlyArrayElement(optionsRoots['type']), uri),
    'selected WebviewOptions and Uri element types',
  );
  final optionsScripts = bindings.single('boolObjectField');
  expectRelation(
    optionsScripts,
    optionsScripts['parentId'] == bindings.id(webviewOptions),
    'selected WebviewOptions parent',
  );

  final contextSubscriptions = bindings.single('subscriptionsArray');
  final extensionContext = bindings.parentOf(contextSubscriptions);
  final contextDisposable = bindings.single('disposableStructuralType');
  final subscriptionElement = arrayElement(contextSubscriptions['type']);
  expectRelation(
    contextSubscriptions,
    subscriptionElement is Map<Object?, Object?> &&
        subscriptionElement['kind'] == 'typeLiteral' &&
        subscriptionElement['id'] == bindings.id(contextDisposable),
    'selected structural subscription element type',
  );
  final extensionUri = bindings.singleChildOf(
    extensionContext,
    'objectGetterProjection',
  );
  expectRelation(
    extensionUri,
    references(extensionUri['type'], uri),
    'selected Uri property type',
  );

  final disposalMethods = [
    bindings.singleChildOf(disposable, 'disposeMethod'),
    bindings.singleChildOf(contextDisposable, 'disposeMethod'),
    bindings.singleChildOf(webviewPanel, 'disposeMethod'),
  ];
  final disposalNameCounts = <String, int>{};
  for (final disposalMethod in disposalMethods) {
    final name = bindings.name(disposalMethod);
    disposalNameCounts[name] = (disposalNameCounts[name] ?? 0) + 1;
  }
  final disposalNamesByFrequency = disposalNameCounts.entries.toList()
    ..sort((left, right) {
      final countOrder = right.value.compareTo(left.value);
      return countOrder != 0 ? countOrder : left.key.compareTo(right.key);
    });
  final disposalName = disposalNamesByFrequency.first.key;
  for (final disposalMethod in disposalMethods) {
    expectRelation(
      disposalMethod,
      bindings.name(disposalMethod) == disposalName,
      'shared structural, native, and panel disposal member name',
    );
  }

  final panelWebview = bindings.singleChildOf(
    webviewPanel,
    'objectGetterProjection',
  );
  expectRelation(
    panelWebview,
    references(panelWebview['type'], webview),
    'selected Webview property type',
  );
  final panelCreation = bindings.single('webviewPanelCreation');
  final panelCreationParameters = _declarationParameters(panelCreation);
  expectRelation(
    panelCreation,
    references(panelCreation['returnType'], webviewPanel) &&
        containsReference(panelCreationParameters[2]['type'], viewColumn) &&
        containsReference(panelCreationParameters[3]['type'], webviewOptions),
    'selected ViewColumn, WebviewOptions, and WebviewPanel types',
  );

  final hoverRegistration = bindings.single('hoverProviderRegistration');
  final hoverRegistrationParameters = _declarationParameters(
    hoverRegistration,
  );
  expectRelation(
    hoverRegistration,
    references(hoverRegistrationParameters[0]['type'], documentSelector) &&
        references(hoverRegistrationParameters[1]['type'], provider) &&
        references(hoverRegistration['returnType'], disposable),
    'selected selector, provider, and Disposable types',
  );
  final providerCallback = bindings.single('providerCallback');
  final providerParameters = _declarationParameters(providerCallback);
  final callbackDocument = bindings.selectedReference(
    providerParameters[0]['type'],
  );
  expectRelation(
    providerCallback,
    providerCallback['parentId'] == bindings.id(provider) &&
        references(providerParameters[1]['type'], position) &&
        references(providerParameters[2]['type'], cancellationToken) &&
        references(providerCallback['returnType'], providerResult) &&
        references(referenceArgument(providerCallback['returnType'], 0), hover),
    'selected provider callback types',
  );
  expectRelation(
    providerResult,
    _isProviderResultProjection(
      providerResult,
      bindings.name(thenable),
    ),
    'selected ProviderResult generic and Thenable union shape',
  );
  final workspaceEvent = bindings.singleWhere(
    'eventValue',
    (declaration) => declaration['kind'] == 'variable',
  );
  expectRelation(
    workspaceEvent,
    references(referenceArgument(workspaceEvent['type'], 0), callbackDocument),
    'provider document event argument type',
  );

  final hoverParameters = _declarationParameters(hoverConstructor);
  expectRelation(
    hoverConstructor,
    containsReference(hoverParameters[0]['type'], markdown) &&
        references(hoverParameters[1]['type'], range),
    'selected MarkdownString and Range constructor types',
  );
}
