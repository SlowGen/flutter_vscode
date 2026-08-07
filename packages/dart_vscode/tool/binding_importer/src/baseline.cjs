const crypto = require('node:crypto');

const REVIEWED_STRATEGIES = new Set([
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
]);

function validateBaselineUpdate(previous, candidate, overrides) {
  validateOverrideStructure(candidate, overrides);
  validateRemovalStructure(previous, candidate, overrides.removals);
  const previousById = new Map(
    previous.declarations.map((item) => [item.id, item]),
  );
  const candidateIds = new Set(
    candidate.declarations
      .filter((item) => item.visibility === 'public')
      .map((item) => item.id),
  );
  const targets = new Set(
    Array.isArray(overrides.targets) ? overrides.targets : [],
  );
  const entries = isObject(overrides.entries) ? overrides.entries : {};
  const unclassified = candidate.declarations
    .filter((item) => item.visibility === 'public')
    .map((item) => {
      const previousItem = previousById.get(item.id);
      if (previousItem === undefined) {
        return [item, 'new public symbol'];
      }
      if (canonicalDeclaration(previousItem) !== canonicalDeclaration(item)) {
        return [item, 'changed public symbol'];
      }
      return undefined;
    })
    .filter((item) => item !== undefined)
    .map(([item, reason]) => [
      item,
      reason,
      classificationProblem(item, targets, entries, overrides.hostContracts),
    ])
    .filter(([, , problem]) => problem !== undefined)
    .map(
      ([item, reason, problem]) => `${item.id} (${reason}; ${problem})`,
    )
    .concat(
      previous.declarations
        .filter(
          (item) =>
            item.visibility === 'public' && !candidateIds.has(item.id),
        )
        .map((item) => [
          item,
          removalClassificationProblem(item, overrides.removals),
        ])
        .filter(([, problem]) => problem !== undefined)
        .map(
          ([item, problem]) =>
            `${item.id} (removed public symbol; ${problem})`,
        ),
    )
    .sort();

  if (unclassified.length > 0) {
    const error = new Error(
      'The candidate VS Code baseline contains unclassified public API:\n' +
        unclassified.map((item) => `- ${item}`).join('\n') +
        '\nAdd a reviewed Semantic Override or a deterministic general rule ' +
        'before updating the baseline.',
    );
    error.code = 'UNCLASSIFIED_BASELINE_DELTA';
    throw error;
  }
  validateHostContractUsage(overrides.entries, overrides.hostContracts);
}

function validateBaselineOverrides(candidate, overrides) {
  validateOverrideStructure(candidate, overrides);
  validateRemovalStructure({declarations: []}, candidate, overrides.removals);
  validateHostContractUsage(overrides.entries, overrides.hostContracts);
}

function validateRemovalStructure(previous, candidate, rawRemovals) {
  if (rawRemovals !== undefined && !isObject(rawRemovals)) {
    const error = new Error(
      'Semantic Overrides removals must be an object when present.',
    );
    error.code = 'UNCLASSIFIED_BASELINE_DELTA';
    throw error;
  }
  const removals = isObject(rawRemovals) ? rawRemovals : {};
  const candidateIds = new Set(
    candidate.declarations
      .filter((item) => item.visibility === 'public')
      .map((item) => item.id),
  );
  const removedById = new Map(
    previous.declarations
      .filter(
        (item) => item.visibility === 'public' && !candidateIds.has(item.id),
      )
      .map((item) => [item.id, item]),
  );
  const problems = Object.keys(removals)
    .map((id) => {
      const removed = removedById.get(id);
      if (removed === undefined) {
        return `stale reviewed removal ${id}`;
      }
      const problem = removalClassificationProblem(removed, removals);
      return problem === undefined ? undefined : `${id}: ${problem}`;
    })
    .filter((problem) => problem !== undefined)
    .sort();
  if (problems.length === 0) {
    return;
  }
  const error = new Error(
    'Semantic Overrides contain invalid removal metadata:\n' +
      problems.map((problem) => `- ${problem}`).join('\n'),
  );
  error.code = 'UNCLASSIFIED_BASELINE_DELTA';
  throw error;
}

function validateOverrideStructure(candidate, overrides) {
  if (!isObject(overrides) || overrides.schemaVersion !== 1) {
    const error = new Error('Semantic Overrides schemaVersion must be 1.');
    error.code = 'UNCLASSIFIED_BASELINE_DELTA';
    throw error;
  }
  validateDeclaredHostContracts(overrides.hostContracts);
  const requiredFields = [
    'commandsContributionSchemaSha256',
    'configurationContributionSchemaSha256',
    'entries',
    'hostContracts',
    'manifestSchemaSha256',
    'manifestValidatorSha256',
    'schemaVersion',
    'targets',
    'viewsContributionSchemaSha256',
    'vscodeVersion',
  ];
  const expectedFields = Object.prototype.hasOwnProperty.call(
    overrides,
    'removals',
  )
    ? [...requiredFields, 'removals'].sort()
    : requiredFields;
  if (
    canonicalJson(Object.keys(overrides).sort()) !==
    canonicalJson(expectedFields)
  ) {
    const error = new Error(
      'Semantic Override top-level fields must be exactly ' +
        `${requiredFields.join(', ')}; removals is optional.`,
    );
    error.code = 'UNCLASSIFIED_BASELINE_DELTA';
    throw error;
  }
  validateRootEvidence(candidate, overrides);
  const targets = Array.isArray(overrides?.targets) ? overrides.targets : [];
  const entries = isObject(overrides?.entries) ? overrides.entries : {};
  const targetSet = new Set(targets);
  const publicCandidateIds = new Set(
    candidate.declarations
      .filter((declaration) => declaration.visibility === 'public')
      .map((declaration) => declaration.id),
  );
  const candidateById = new Map(
    candidate.declarations.map((declaration) => [declaration.id, declaration]),
  );
  const duplicateTargets = [
    ...new Set(
      targets.filter((target, index) => targets.indexOf(target) !== index),
    ),
  ];
  const problems = targets
    .filter((target) => entries[target] === undefined)
    .map((target) => `target ${target} has no classification entry`)
    .concat(
      duplicateTargets.map((target) => `duplicate target ${target}`),
      Object.keys(entries)
        .filter((entry) => !targetSet.has(entry))
        .map((entry) => `entry ${entry} has no target`),
      targets
        .filter((target) => !publicCandidateIds.has(target))
        .map(
          (target) =>
            `target ${target} does not name a candidate public declaration`,
        ),
      targets
        .filter((target) => publicCandidateIds.has(target))
        .map((target) => [
          target,
          classificationProblem(
            candidateById.get(target),
            targetSet,
            entries,
            overrides.hostContracts,
          ),
        ])
        .filter(([, problem]) => problem !== undefined)
        .map(([target, problem]) => `entry ${target}: ${problem}`),
    )
    .sort();
  if (problems.length === 0) {
    return;
  }
  const error = new Error(
    'Semantic Overrides contain stale classification metadata:\n' +
      problems.map((problem) => `- ${problem}`).join('\n'),
  );
  error.code = 'UNCLASSIFIED_BASELINE_DELTA';
  throw error;
}

function validateRootEvidence(candidate, overrides) {
  const problems = [];
  const candidateVersion = candidate?.source?.product?.version;
  const overrideVersion = overrides.vscodeVersion;
  if (typeof candidateVersion !== 'string' || candidateVersion.length === 0) {
    problems.push(
      'candidate source.product.version must be a non-empty string',
    );
  }
  if (typeof overrideVersion !== 'string' || overrideVersion.length === 0) {
    problems.push('vscodeVersion must be a non-empty string');
  } else if (
    typeof candidateVersion === 'string' &&
    candidateVersion.length > 0 &&
    overrideVersion !== candidateVersion
  ) {
    problems.push(
      `vscodeVersion ${overrideVersion} does not match candidate product ` +
        `version ${candidateVersion}`,
    );
  }

  const evidence = [
    [
      'manifestSchemaSha256',
      'manifestSchema.inputSha256',
      candidate?.manifestSchema?.inputSha256,
    ],
    [
      'manifestValidatorSha256',
      'manifestValidator.inputSha256',
      candidate?.manifestValidator?.inputSha256,
    ],
    [
      'commandsContributionSchemaSha256',
      'contributionSchemas.commands.inputSha256',
      candidate?.contributionSchemas?.commands?.inputSha256,
    ],
    [
      'viewsContributionSchemaSha256',
      'contributionSchemas.views.inputSha256',
      candidate?.contributionSchemas?.views?.inputSha256,
    ],
    [
      'configurationContributionSchemaSha256',
      'contributionSchemas.configuration.inputSha256',
      candidate?.contributionSchemas?.configuration?.inputSha256,
    ],
  ];
  for (const [overrideField, candidateField, candidateHash] of evidence) {
    const reviewedHash = overrides[overrideField];
    const candidateHashIsValid =
      typeof candidateHash === 'string' && /^[0-9a-f]{64}$/.test(candidateHash);
    if (!candidateHashIsValid) {
      problems.push(
        `candidate ${candidateField} must be a lowercase SHA-256 digest`,
      );
    }
    if (
      typeof reviewedHash !== 'string' ||
      !/^[0-9a-f]{64}$/.test(reviewedHash)
    ) {
      problems.push(`${overrideField} must be a lowercase SHA-256 digest`);
    } else if (candidateHashIsValid && reviewedHash !== candidateHash) {
      problems.push(
        `${overrideField} ${reviewedHash} does not match candidate evidence ` +
          `${candidateHash}`,
      );
    }
  }

  if (problems.length === 0) {
    return;
  }
  const error = new Error(
    'Semantic Overrides contain invalid root evidence metadata:\n' +
      problems.map((problem) => `- ${problem}`).join('\n'),
  );
  error.code = 'UNCLASSIFIED_BASELINE_DELTA';
  throw error;
}

function removalClassificationProblem(item, rawRemovals) {
  const removals = isObject(rawRemovals) ? rawRemovals : {};
  const entry = removals[item.id];
  if (!isObject(entry)) {
    return 'missing reviewed classification';
  }
  if (
    canonicalJson(Object.keys(entry).sort()) !==
    canonicalJson(['declarationSha256', 'reason', 'strategy'])
  ) {
    return (
      'reviewedRemoval fields must be exactly ' +
      'declarationSha256, reason, and strategy'
    );
  }
  if (entry.strategy !== 'reviewedRemoval') {
    return 'strategy must be reviewedRemoval';
  }
  const actualFingerprint = declarationFingerprint(item);
  if (entry.declarationSha256 !== actualFingerprint) {
    return (
      'declarationSha256 does not match the removed declaration ' +
      actualFingerprint
    );
  }
  if (typeof entry.reason !== 'string' || entry.reason.trim().length === 0) {
    return 'reviewedRemoval requires a non-empty reason';
  }
  return undefined;
}

function validateDeclaredHostContracts(rawContracts) {
  if (!isObject(rawContracts) || Object.keys(rawContracts).length === 0) {
    const error = new Error(
      'Semantic Overrides must declare at least one executable Host Contract.',
    );
    error.code = 'UNCLASSIFIED_BASELINE_DELTA';
    throw error;
  }
  const malformed = Object.entries(rawContracts)
    .map(([id, contract]) => {
      if (!/^[a-z][A-Za-z0-9]*$/.test(id)) {
        return `Host Contract ID ${id} must be lower camel case`;
      }
      if (!isExecutableHostContract(contract)) {
        return `Host Contract ${id} is missing or malformed`;
      }
      return undefined;
    })
    .filter((problem) => problem !== undefined)
    .sort();
  if (malformed.length === 0) {
    return;
  }
  const error = new Error(
    'Semantic Overrides contain invalid Host Contracts:\n' +
      malformed.map((problem) => `- ${problem}`).join('\n'),
  );
  error.code = 'UNCLASSIFIED_BASELINE_DELTA';
  throw error;
}

function validateHostContractUsage(rawEntries, rawContracts) {
  const entries = isObject(rawEntries) ? rawEntries : {};
  const contracts = isObject(rawContracts) ? rawContracts : {};
  const cited = new Set(
    Object.values(entries)
      .filter(
        (entry) =>
          isObject(entry) && typeof entry.hostContract === 'string',
      )
      .map((entry) => entry.hostContract),
  );
  const unused = Object.keys(contracts)
    .filter((contract) => !cited.has(contract))
    .sort();
  if (unused.length === 0) {
    return;
  }
  const error = new Error(
    'Semantic Overrides contain unused Host Contracts:\n' +
      unused
        .map((contract) => `- Host Contract ${contract} is not cited`)
        .join('\n'),
  );
  error.code = 'UNCLASSIFIED_BASELINE_DELTA';
  throw error;
}

function classificationProblem(item, targets, entries, rawContracts) {
  if (!targets.has(item.id) || entries[item.id] === undefined) {
    return 'missing reviewed classification';
  }
  const entry = entries[item.id];
  if (!isObject(entry)) {
    return 'classification must be an object';
  }
  if (!REVIEWED_STRATEGIES.has(entry.strategy)) {
    return 'strategy is missing or unsupported';
  }
  const expectedFields = entry.strategy === 'reviewedExcluded'
    ? ['declarationSha256', 'reason', 'strategy']
    : ['declarationSha256', 'hostContract', 'strategy'];
  if (
    canonicalJson(Object.keys(entry).sort()) !== canonicalJson(expectedFields)
  ) {
    return (
      `${entry.strategy} fields must be exactly ` + expectedFields.join(', ')
    );
  }
  const actualFingerprint = declarationFingerprint(item);
  if (entry.declarationSha256 !== actualFingerprint) {
    return (
      'declarationSha256 does not match the candidate declaration ' +
      actualFingerprint
    );
  }
  if (entry.strategy === 'reviewedExcluded') {
    if (typeof entry.reason !== 'string' || entry.reason.trim().length === 0) {
      return 'reviewedExcluded requires a non-empty reason';
    }
    if (entry.hostContract !== undefined) {
      return 'reviewedExcluded cannot cite a Host Contract';
    }
    return undefined;
  }
  if (typeof entry.hostContract !== 'string' || entry.hostContract.length === 0) {
    return 'emitted classifications require a Host Contract';
  }
  const contracts = isObject(rawContracts) ? rawContracts : {};
  const contract = contracts[entry.hostContract];
  if (!isExecutableHostContract(contract)) {
    return `Host Contract ${entry.hostContract} is missing or malformed`;
  }
  return undefined;
}

function declarationFingerprint(declaration) {
  return crypto
    .createHash('sha256')
    .update(canonicalDeclaration(declaration))
    .digest('hex');
}

function isExecutableHostContract(value) {
  if (!isObject(value) || value.boundary !== 'vscodeExtensionHost') {
    return false;
  }
  const keys = Object.keys(value).sort();
  if (
    canonicalJson(keys) !==
    canonicalJson(['artifact', 'artifactSha256', 'boundary'])
  ) {
    return false;
  }
  const artifactPrefix = 'tool/bindings/contracts/';
  const artifact = value.artifact;
  const artifactName = typeof artifact === 'string'
    ? artifact.slice(artifactPrefix.length)
    : '';
  return (
    typeof artifact === 'string' &&
    artifact.startsWith(artifactPrefix) &&
    artifactName.length > '.json'.length &&
    artifactName.endsWith('.json') &&
    /^tool\/bindings\/contracts\/[a-z0-9](?:[a-z0-9._-]*[a-z0-9])?\.json$/.test(
      artifact,
    ) &&
    !artifactName.includes('/') &&
    !artifact.includes('\\') &&
    !artifact.split('/').some(
      (segment) => segment.length === 0 || segment === '.' || segment === '..',
    ) &&
    typeof value.artifactSha256 === 'string' &&
    /^[0-9a-f]{64}$/.test(value.artifactSha256)
  );
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function canonicalDeclaration(declaration) {
  const semantic = {...declaration};
  delete semantic.coverage;
  return canonicalJson(semantic);
}

function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(',')}]`;
  }
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

module.exports = {validateBaselineOverrides, validateBaselineUpdate};
