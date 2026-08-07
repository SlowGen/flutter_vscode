const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {importVscodeDeclarations} = require('../src/importer.cjs');

const pendingCoverage = {
  discovery: 'discovered',
  semantics: 'pending',
  binding: 'pending',
  host: 'pending',
};

test('imports module, namespace, and function into canonical IR', () => {
  const source = `
    declare module 'vscode' {
      export namespace commands {
        export function ping(message: string): Disposable;
      }
    }
  `;

  assert.deepEqual(importVscodeDeclarations(source, 'fixture.d.ts'), {
    schemaVersion: 1,
    module: {
      id: 'module:vscode',
      name: 'vscode',
    },
    declarations: [
      {
        id: 'namespace:vscode.commands',
        kind: 'namespace',
        name: 'commands',
        qualifiedName: 'vscode.commands',
        parentId: 'module:vscode',
        deprecated: false,
        visibility: 'public',
        coverage: pendingCoverage,
      },
      {
        id:
          'function:vscode.commands.ping@' +
          'ebfe0aaf239337bd13815365e2ddd66659aa68c9c5505e9a82d5160f8bf1f4fc',
        kind: 'function',
        name: 'ping',
        qualifiedName: 'vscode.commands.ping',
        parentId: 'namespace:vscode.commands',
        deprecated: false,
        visibility: 'public',
        coverage: pendingCoverage,
        overloadOrdinal: 0,
        canonicalSignature:
          '{"typeParameters":[],"parameters":[{"optional":false,' +
          '"rest":false,"type":{"kind":"primitive","name":"string"}}],' +
          '"returnType":{"kind":"reference","name":"Disposable",' +
          '"typeArguments":[]}}',
        typeParameters: [],
        parameters: [
          {
            name: 'message',
            optional: false,
            rest: false,
            type: {
              kind: 'primitive',
              name: 'string',
            },
          },
        ],
        returnType: {
          kind: 'reference',
          name: 'Disposable',
          typeArguments: [],
        },
      },
    ],
  });
});

test('root vscode module rejects unprojected modifiers', () => {
  assert.throws(
    () => importVscodeDeclarations(
      "async module 'vscode' {}",
      'root-module-modifier.d.ts',
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
      assert.match(error.message, /module:vscode/);
      assert.match(error.message, /modifier AsyncKeyword/);
      assert.match(error.message, /async/);
      return true;
    },
  );
});

test('merged namespaces preserve semantically significant overload order', () => {
  const first = `
    declare module 'vscode' {
      export namespace commands {
        /** @deprecated Use executeNew. */
        export function execute(value: string): Disposable;
        export function execute(value: number): Disposable;
      }
      export namespace commands {
        export function ping(): void;
      }
    }
  `;
  const reordered = `
    declare module 'vscode' {
      export namespace commands { export function ping(): void; }
      export namespace commands {
        export function execute(value: number): Disposable;
        /** @deprecated Use executeNew. */
        export function execute(value: string): Disposable;
      }
    }
  `;

  const firstIr = importVscodeDeclarations(first, 'first.d.ts');
  const reorderedIr = importVscodeDeclarations(reordered, 'reordered.d.ts');

  assert.notDeepEqual(firstIr, reorderedIr);
  assert.deepEqual(
    firstIr.declarations
      .filter((item) => item.qualifiedName === 'vscode.commands.execute')
      .map((item) => [item.parameters[0].type.name, item.overloadOrdinal]),
    [['string', 0], ['number', 1]],
  );
  assert.deepEqual(
    reorderedIr.declarations
      .filter((item) => item.qualifiedName === 'vscode.commands.execute')
      .map((item) => [item.parameters[0].type.name, item.overloadOrdinal]),
    [['number', 0], ['string', 1]],
  );
  assert.equal(
    firstIr.declarations.filter((item) => item.kind === 'namespace').length,
    1,
  );
  assert.equal(
    new Set(firstIr.declarations.map((item) => item.id)).size,
    firstIr.declarations.length,
  );
  assert.equal(
    firstIr.declarations.find(
      (item) =>
        item.qualifiedName === 'vscode.commands.execute' &&
        item.parameters[0].type.name === 'string',
    ).deprecated,
    true,
  );
});

test('inventories supported global declarations beside the vscode module', () => {
  const source = `
    type GlobalOptions = string;
    declare module 'vscode' {}
  `;

  const declarations = importVscodeDeclarations(
    source,
    'global-declaration.d.ts',
  ).declarations;

  assert.deepEqual(
    declarations.map((item) => [item.id, item.kind]),
    [['typeAlias:global.GlobalOptions', 'typeAlias']],
  );
});

test('global augmentations fail closed instead of becoming namespaces', () => {
  for (const [fileName, source] of [
    [
      'top-level-global-augmentation.d.ts',
      `
        declare global { interface AddedGlobal {} }
        declare module 'vscode' {}
      `,
    ],
    [
      'nested-global-augmentation.d.ts',
      `
        declare module 'vscode' {
          global { interface AddedGlobal {} }
        }
      `,
    ],
  ]) {
    assert.throws(
      () => importVscodeDeclarations(source, fileName),
      (error) => {
        assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
        assert.match(error.message, /global augmentation/);
        assert.match(error.message, /global \{/);
        return true;
      },
      fileName,
    );
  }
});

test('inventories every merged vscode module declaration', () => {
  const source = `
    declare module 'vscode' { export function first(): void; }
    declare module 'vscode' { export function second(): void; }
  `;

  const declarations = importVscodeDeclarations(
    source,
    'merged-module.d.ts',
  ).declarations;

  assert.deepEqual(
    declarations.map((item) => item.qualifiedName),
    ['vscode.first', 'vscode.second'],
  );
});

test('merged interface heritage is de-duplicated in semantic source order', () => {
  const first = `
    declare module 'vscode' {
      export interface Service<T> extends Base<T> {}
      export interface Service<T> extends Other<T>, Base<T> {}
    }
  `;
  const reordered = `
    declare module 'vscode' {
      export interface Service<T> extends Other<T>, Base<T> {}
      export interface Service<T> extends Base<T> {}
    }
  `;

  const firstService = importVscodeDeclarations(
    first,
    'first-interface-merge.d.ts',
  ).declarations.find((item) => item.id === 'interface:vscode.Service');
  const reorderedService = importVscodeDeclarations(
    reordered,
    'reordered-interface-merge.d.ts',
  ).declarations.find((item) => item.id === 'interface:vscode.Service');

  assert.notDeepEqual(firstService, reorderedService);
  assert.deepEqual(firstService.extends, [
    {
      kind: 'reference',
      name: 'Base',
      typeArguments: [
        {kind: 'reference', name: 'T', typeArguments: []},
      ],
    },
    {
      kind: 'reference',
      name: 'Other',
      typeArguments: [
        {kind: 'reference', name: 'T', typeArguments: []},
      ],
    },
  ]);
  assert.deepEqual(
    reorderedService.extends.map((item) => item.name),
    ['Other', 'Base'],
  );
});

test('unexpected interface heritage fails closed instead of disappearing', () => {
  assert.throws(
    () => importVscodeDeclarations(`
      declare module 'vscode' {
        export interface Service extends Base implements Hidden {}
      }
    `, 'interface-implements.d.ts'),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
      assert.match(error.message, /heritage clause/);
      assert.match(error.message, /implements Hidden/);
      return true;
    },
  );
});

test('incompatible merged interface type parameters fail closed', () => {
  const source = `
    declare module 'vscode' {
      export interface Service<T extends Base> {}
      export interface Service<T extends Other> {}
    }
  `;

  assert.throws(
    () => importVscodeDeclarations(source, 'interface-conflict.d.ts'),
    (error) => {
      assert.equal(error.code, 'CONFLICTING_DECLARATION');
      assert.match(error.message, /interface-conflict\.d\.ts/);
      assert.match(error.message, /interface:vscode\.Service/);
      assert.match(error.message, /typeParameters/);
      return true;
    },
  );
});

test('conflicting merged interface properties fail closed', () => {
  const source = `
    declare module 'vscode' {
      export interface Service { value: string; }
      export interface Service { value: number; }
    }
  `;

  assert.throws(
    () => importVscodeDeclarations(source, 'property-conflict.d.ts'),
    (error) => {
      assert.equal(error.code, 'CONFLICTING_DECLARATION');
      assert.match(error.message, /property-conflict\.d\.ts/);
      assert.match(
        error.message,
        /property:interface:vscode\.Service\/\$instance\/value/,
      );
      assert.match(error.message, /type/);
      return true;
    },
  );
});

test('conflicting merged enum member initializers fail closed', () => {
  const source = `
    declare module 'vscode' {
      export enum Mode { ready = 1 }
      export enum Mode { ready = 2 }
    }
  `;

  assert.throws(
    () => importVscodeDeclarations(source, 'enum-member-conflict.d.ts'),
    (error) => {
      assert.equal(error.code, 'CONFLICTING_DECLARATION');
      assert.match(error.message, /enum-member-conflict\.d\.ts/);
      assert.match(
        error.message,
        /enumMember:enum:vscode\.Mode\/ready/,
      );
      assert.match(error.message, /initializer/);
      return true;
    },
  );
});

test('implicit enum members fail closed instead of losing ordinal semantics', () => {
  const source = `
    declare module 'vscode' {
      export enum Mode { first, second = 2 }
    }
  `;

  assert.throws(
    () => importVscodeDeclarations(source, 'implicit-enum-member.d.ts'),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
      assert.match(error.message, /implicit-enum-member\.d\.ts/);
      assert.match(error.message, /enum:vscode\.Mode/);
      assert.match(error.message, /implicit enum member EnumMember/);
      assert.match(error.message, /first/);
      return true;
    },
  );
});

test('conflicting repeated declaration headers fail closed', () => {
  const cases = [
    {
      fileName: 'type-alias-conflict.d.ts',
      declarations: `
        export type Value = string;
        export type Value = number;
      `,
      id: /typeAlias:vscode\.Value/,
      field: /type/,
    },
    {
      fileName: 'variable-conflict.d.ts',
      declarations: `
        export const value: string;
        export const value: number;
      `,
      id: /variable:vscode\.value/,
      field: /type/,
    },
    {
      fileName: 'class-conflict.d.ts',
      declarations: `
        export class Service extends Base {}
        export class Service extends Other {}
      `,
      id: /class:vscode\.Service/,
      field: /extends/,
    },
    {
      fileName: 'enum-conflict.d.ts',
      declarations: `
        export enum Mode { first = 1 }
        export const enum Mode { second = 2 }
      `,
      id: /enum:vscode\.Mode/,
      field: /constant/,
    },
  ];

  for (const testCase of cases) {
    const source = `
      declare module 'vscode' {
        ${testCase.declarations}
      }
    `;
    assert.throws(
      () => importVscodeDeclarations(source, testCase.fileName),
      (error) => {
        assert.equal(error.code, 'CONFLICTING_DECLARATION');
        assert.match(error.message, new RegExp(testCase.fileName.replace('.', '\\.')));
        assert.match(error.message, testCase.id);
        assert.match(error.message, testCase.field);
        return true;
      },
    );
  }
});

test('non-mergeable duplicate declarations fail closed even when identical', () => {
  const cases = [
    {
      fileName: 'duplicate-class.d.ts',
      declarations: 'export class Service {} export class Service {}',
      id: /class:vscode\.Service/,
    },
    {
      fileName: 'duplicate-type-alias.d.ts',
      declarations: 'export type Value = string; export type Value = string;',
      id: /typeAlias:vscode\.Value/,
    },
    {
      fileName: 'duplicate-enum-member.d.ts',
      declarations: `
        export enum Mode { ready = 1 }
        export enum Mode { ready = 1 }
      `,
      id: /enumMember:enum:vscode\.Mode\/ready/,
    },
  ];

  for (const testCase of cases) {
    assert.throws(
      () => importVscodeDeclarations(`
        declare module 'vscode' { ${testCase.declarations} }
      `, testCase.fileName),
      (error) => {
        assert.equal(error.code, 'CONFLICTING_DECLARATION');
        assert.match(error.message, testCase.id);
        assert.match(error.message, /cannot be merged/);
        return true;
      },
    );
  }
});

test('variable declarations preserve const, let, and mergeable var semantics', () => {
  const declarations = importVscodeDeclarations(`
    declare module 'vscode' {
      export const fixed: string;
      export let scoped: string;
      export var ambient: string;
    }
  `, 'variable-kinds.d.ts').declarations.filter(
    (item) => item.kind === 'variable',
  );

  assert.deepEqual(
    Object.fromEntries(
      declarations.map((item) => [
        item.name,
        [item.declarationKind, item.constant],
      ]),
    ),
    {
      ambient: ['var', false],
      fixed: ['const', true],
      scoped: ['let', false],
    },
  );

  const importedValue = (keyword) => importVscodeDeclarations(`
    declare module 'vscode' { export ${keyword} value: string; }
  `, `${keyword}-variable.d.ts`).declarations.find(
    (item) => item.id === 'variable:vscode.value',
  );
  assert.notDeepEqual(importedValue('let'), importedValue('var'));

  const mergedVar = importVscodeDeclarations(`
    declare module 'vscode' {
      export var value: string;
      export var value: string;
    }
  `, 'merged-var.d.ts').declarations.find(
    (item) => item.id === 'variable:vscode.value',
  );
  assert.equal(mergedVar.occurrenceCount, 2);

  assert.throws(
    () => importVscodeDeclarations(`
      declare module 'vscode' {
        export let value: string;
        export let value: string;
      }
    `, 'duplicate-let.d.ts'),
    (error) => {
      assert.equal(error.code, 'CONFLICTING_DECLARATION');
      assert.match(error.message, /variable:vscode\.value/);
      assert.match(error.message, /cannot be merged/);
      return true;
    },
  );
});

test('resource variable declarations fail closed instead of becoming var or const', () => {
  for (const keyword of ['using', 'await using']) {
    assert.throws(
      () => importVscodeDeclarations(`
        declare module 'vscode' {
          export ${keyword} resource: Disposable;
        }
      `, `${keyword.replace(' ', '-')}-variable.d.ts`),
      (error) => {
        assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
        assert.match(error.message, /resource variable declaration/);
        assert.match(error.message, new RegExp(`${keyword} resource`));
        return true;
      },
      keyword,
    );
  }
});

test('inventories every segment of a dotted namespace', () => {
  const source = `
    declare module 'vscode' {
      export namespace languages.providers {
        export function ping(): void;
      }
    }
  `;

  const declarations = importVscodeDeclarations(
    source,
    'dotted-namespace.d.ts',
  ).declarations;

  assert.deepEqual(
    declarations.map((item) => [item.qualifiedName, item.kind]),
    [
      ['vscode.languages', 'namespace'],
      ['vscode.languages.providers', 'namespace'],
      ['vscode.languages.providers.ping', 'function'],
    ],
  );
});

test('signature IDs ignore parameter names', () => {
  const withValue = `
    declare module 'vscode' {
      export namespace commands {
        export function ping(value: string): Disposable;
      }
    }
  `;
  const withMessage = `
    declare module 'vscode' {
      export namespace commands {
        export function ping(message: string): Disposable;
      }
    }
  `;

  const valueId = importVscodeDeclarations(
    withValue,
    'value.d.ts',
  ).declarations.find((item) => item.kind === 'function').id;
  const messageId = importVscodeDeclarations(
    withMessage,
    'message.d.ts',
  ).declarations.find((item) => item.kind === 'function').id;

  assert.equal(valueId, messageId);
});

test('computed and literal member names have distinct stable IDs', () => {
  const source = `
    declare module 'vscode' {
      export interface Values {
        [Symbol.iterator](): void;
        '[Symbol.iterator]'(): void;
      }
    }
  `;

  const methods = importVscodeDeclarations(
    source,
    'member-name-kinds.d.ts',
  ).declarations.filter((item) => item.kind === 'method');

  assert.equal(methods.length, 2);
  assert.equal(new Set(methods.map((item) => item.id)).size, 2);
  assert.deepEqual(
    methods.map((item) => item.name).sort(),
    ['"[Symbol.iterator]"', '[Symbol.iterator]'],
  );
  assert.equal(
    methods.some((item) =>
      item.id.startsWith('method:vscode.Values.[Symbol.iterator]@')),
    true,
  );
});

test('identifier-safe string member names share semantic stable IDs', () => {
  const declarations = (memberName) => importVscodeDeclarations(`
    declare module 'vscode' {
      export interface Values { ${memberName}(): void; }
    }
  `, 'identifier-member-name.d.ts').declarations;

  const identifier = declarations('foo');
  const stringLiteral = declarations("'foo'");

  assert.deepEqual(
    identifier.map((item) => item.id),
    stringLiteral.map((item) => item.id),
  );
  assert.equal(
    identifier.find((item) => item.kind === 'method').name,
    'foo',
  );
  assert.equal(
    stringLiteral.find((item) => item.kind === 'method').name,
    'foo',
  );
});

test('numeric and equivalent string member names share stable IDs', () => {
  const declarations = (memberName) => importVscodeDeclarations(`
    declare module 'vscode' {
      export interface Values { ${memberName}(): void; }
    }
  `, 'numeric-member-name.d.ts').declarations;

  const numeric = declarations('1');
  const stringLiteral = declarations("'1'");

  assert.deepEqual(
    numeric.map((item) => item.id),
    stringLiteral.map((item) => item.id),
  );
  assert.equal(
    stringLiteral.find((item) => item.kind === 'method').name,
    '1',
  );
});

test('inline type-literal overloads retain distinct shape IDs', () => {
  const source = `
    declare module 'vscode' {
      export function configure(options: { first: string }): void;
      export function configure(options: { second: number }): void;
    }
  `;

  const overloads = importVscodeDeclarations(
    source,
    'inline-type-literal-overloads.d.ts',
  ).declarations.filter(
    (item) =>
      item.kind === 'function' &&
      item.qualifiedName === 'vscode.configure',
  );

  assert.equal(overloads.length, 2);
  assert.equal(new Set(overloads.map((item) => item.id)).size, 2);
  assert.deepEqual(overloads.map((item) => item.overloadOrdinal), [0, 1]);
});

test('signature IDs ignore nested callback and tuple labels', () => {
  const first = `
    declare module 'vscode' {
      export function register(
        callback: (value: string) => void,
        tuple: [first: string],
      ): void;
    }
  `;
  const renamed = `
    declare module 'vscode' {
      export function register(
        handler: (message: string) => void,
        coordinates: [label: string],
      ): void;
    }
  `;

  const firstId = importVscodeDeclarations(
    first,
    'first-labels.d.ts',
  ).declarations.find((item) => item.kind === 'function').id;
  const renamedId = importVscodeDeclarations(
    renamed,
    'renamed-labels.d.ts',
  ).declarations.find((item) => item.kind === 'function').id;

  assert.equal(firstId, renamedId);
});

test('signature IDs alpha-normalize outer generics in nested callbacks', () => {
  const functionId = (typeParameter) => importVscodeDeclarations(`
    declare module 'vscode' {
      export function register<${typeParameter}>(
        callback: (value: ${typeParameter}) => ${typeParameter},
      ): void;
    }
  `, `callback-${typeParameter}.d.ts`).declarations.find(
    (item) => item.kind === 'function',
  ).id;

  assert.equal(functionId('T'), functionId('U'));
});

test('stable IDs alpha-normalize outer generics in type literals', () => {
  const declarationIds = (typeParameter) => importVscodeDeclarations(`
    declare module 'vscode' {
      export function configure<${typeParameter}>(
        options: {
          value: ${typeParameter};
          map(value: ${typeParameter}): ${typeParameter};
          (value: ${typeParameter}): ${typeParameter};
          [key: string]: ${typeParameter};
        },
      ): void;
    }
  `, `type-literal-${typeParameter}.d.ts`).declarations.map(
    (item) => item.id,
  );

  assert.deepEqual(declarationIds('T'), declarationIds('U'));
});

test('stable IDs alpha-normalize generic interface members', () => {
  const declarationIds = (typeParameter) => importVscodeDeclarations(`
    declare module 'vscode' {
      export interface Box<${typeParameter}> {
        value: ${typeParameter};
        map(value: ${typeParameter}): {
          current: ${typeParameter};
          read(): ${typeParameter};
          (value: ${typeParameter}): ${typeParameter};
          [key: string]: ${typeParameter};
        };
        (value: ${typeParameter}): ${typeParameter};
        [key: string]: ${typeParameter};
      }
    }
  `, `generic-interface-${typeParameter}.d.ts`).declarations.map(
    (item) => item.id,
  );

  assert.deepEqual(declarationIds('T'), declarationIds('U'));
});

test('stable IDs alpha-normalize generic class members', () => {
  const declarationIds = (typeParameter) => importVscodeDeclarations(`
    declare module 'vscode' {
      export class Box<${typeParameter}> {
        value: ${typeParameter};
        constructor(value: ${typeParameter});
        map(value: ${typeParameter}): {
          current: ${typeParameter};
          read(): ${typeParameter};
          [key: string]: ${typeParameter};
        };
        [key: string]: ${typeParameter};
      }
    }
  `, `generic-class-${typeParameter}.d.ts`).declarations.map(
    (item) => item.id,
  );

  assert.deepEqual(declarationIds('T'), declarationIds('U'));
});

test('stable IDs alpha-normalize generic type-alias literals', () => {
  const declarationIds = (typeParameter) => importVscodeDeclarations(`
    declare module 'vscode' {
      export type Box<${typeParameter}> = {
        value: ${typeParameter};
        map(value: ${typeParameter}): ${typeParameter};
        (value: ${typeParameter}): ${typeParameter};
        [key: string]: ${typeParameter};
      };
    }
  `, `generic-alias-${typeParameter}.d.ts`).declarations.map(
    (item) => item.id,
  );

  assert.deepEqual(declarationIds('T'), declarationIds('U'));
});

test('signature IDs alpha-normalize generic constraint and default literals', () => {
  const functionId = (typeParameter, metadata) => importVscodeDeclarations(`
    declare module 'vscode' {
      export function configure<${typeParameter} ${metadata}>(
        value: ${typeParameter},
      ): void;
    }
  `, `generic-metadata-${typeParameter}.d.ts`).declarations.find(
    (item) => item.kind === 'function',
  ).id;

  for (const metadata of [
    'extends { value: TYPE_PARAMETER }',
    '= { value: TYPE_PARAMETER }',
  ]) {
    assert.equal(
      functionId('T', metadata.replaceAll('TYPE_PARAMETER', 'T')),
      functionId('U', metadata.replaceAll('TYPE_PARAMETER', 'U')),
    );
  }
});

test('signature IDs alpha-normalize outer generics in member metadata', () => {
  const methodId = (outer, inner) => importVscodeDeclarations(`
    declare module 'vscode' {
      export interface Box<${outer}> {
        map<${inner} extends { value: ${outer} } = { value: ${outer} }>(
          value: ${inner},
        ): ${outer};
      }
    }
  `, `generic-member-metadata-${outer}-${inner}.d.ts`).declarations.find(
    (item) => item.kind === 'method',
  ).id;

  assert.equal(methodId('T', 'U'), methodId('V', 'W'));
});

test('inventories every declaration and member category', () => {
  const source = `
    declare module 'vscode' {
      export namespace nested {}

      export interface Service<T> extends Base<T> {
        readonly value?: T;
        call(input: string): Thenable<T>;
        call(input: number): Thenable<T>;
        (input: T): void;
        [key: string]: T;
      }

      export class Widget {
        readonly label: string;
        constructor(label: string);
        constructor(label: string, count: number);
        run(): void;
      }

      export enum Mode { first = 'first', second = 'second' }
      export type Options = { enabled: boolean; [key: string]: unknown };
      export const first: string, second: number;
      export function create(value: string): Widget;
      export function create(value: number): Widget;
    }
  `;

  const declarations = importVscodeDeclarations(
    source,
    'all-categories.d.ts',
  ).declarations;
  const kinds = Object.fromEntries(
    [...new Set(declarations.map((item) => item.kind))]
      .sort()
      .map((kind) => [
        kind,
        declarations.filter((item) => item.kind === kind).length,
      ]),
  );

  assert.deepEqual(kinds, {
    callSignature: 1,
    class: 1,
    constructor: 2,
    enum: 1,
    enumMember: 2,
    function: 2,
    indexSignature: 2,
    interface: 1,
    method: 3,
    namespace: 1,
    property: 3,
    typeAlias: 1,
    typeLiteral: 1,
    variable: 2,
  });
  assert.equal(
    new Set(declarations.map((item) => item.id)).size,
    declarations.length,
  );
});

test('constructor parameter properties fail closed instead of losing modifiers', () => {
  const source = `
    declare module 'vscode' {
      export class Service {
        constructor(public readonly value: string);
      }
    }
  `;

  assert.throws(
    () => importVscodeDeclarations(source, 'parameter-property.d.ts'),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
      assert.match(error.message, /parameter-property\.d\.ts/);
      assert.match(error.message, /class:vscode\.Service/);
      assert.match(error.message, /parameter property Parameter/);
      assert.match(error.message, /public readonly value: string/);
      return true;
    },
  );
});

test('missing public type annotations fail closed instead of becoming void', () => {
  const declarations = [
    'export interface Shape { value; }',
    'export function run(value): void;',
    'export function run();',
  ];

  for (const [index, declaration] of declarations.entries()) {
    assert.throws(
      () => importVscodeDeclarations(`
        declare module 'vscode' { ${declaration} }
      `, `missing-annotation-${index}.d.ts`),
      (error) => {
        assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
        assert.match(error.message, /missing type annotation/);
        return true;
      },
    );
  }
});

test('missing nested type-literal annotations fail closed instead of becoming void', () => {
  assert.throws(
    () => importVscodeDeclarations(`
      declare module 'vscode' {
        export interface Box<T extends { value; }> {}
      }
    `, 'missing-nested-annotation.d.ts'),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
      assert.match(error.message, /missing-nested-annotation\.d\.ts/);
      assert.match(error.message, /missing type annotation/);
      assert.match(error.message, /value/);
      return true;
    },
  );
});

test('this parameters fail closed instead of shifting callback arity', () => {
  assert.throws(
    () => importVscodeDeclarations(`
      declare module 'vscode' {
        export interface Service {}
        export function register(
          callback: (this: Service, value: string) => void
        ): void;
      }
    `, 'this-parameter.d.ts'),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
      assert.match(error.message, /this-parameter\.d\.ts/);
      assert.match(error.message, /this parameter/);
      assert.match(error.message, /this: Service/);
      return true;
    },
  );
});

test('initializer-only ambient variables fail closed without an explicit type', () => {
  assert.throws(
    () => importVscodeDeclarations(`
      declare module 'vscode' { export const answer = 1; }
    `, 'initializer-only-variable.d.ts'),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
      assert.match(error.message, /initializer-only-variable\.d\.ts/);
      assert.match(error.message, /missing type annotation/);
      assert.match(error.message, /answer = 1/);
      return true;
    },
  );
});

test('implementation syntax fails closed instead of disappearing from IR', () => {
  const cases = [
    {
      name: 'function body',
      declaration: 'export function run(): void {}',
      category: /implementation body/,
      snippet: /\{\}/,
    },
    {
      name: 'generator function',
      declaration: 'export function* values(): Iterable<number>;',
      category: /generator declaration/,
      snippet: /\*/,
    },
    {
      name: 'method body',
      declaration: 'export class Service { run(): void {} }',
      category: /implementation body/,
      snippet: /\{\}/,
    },
    {
      name: 'generator method',
      declaration: 'export class Service { *values(): Iterable<number>; }',
      category: /generator declaration/,
      snippet: /\*/,
    },
    {
      name: 'constructor body',
      declaration: 'export class Service { constructor() {} }',
      category: /implementation body/,
      snippet: /\{\}/,
    },
    {
      name: 'property initializer',
      declaration: "export class Service { value: string = 'value'; }",
      category: /property initializer/,
      snippet: /'value'/,
    },
    {
      name: 'function parameter initializer',
      declaration: "export function run(value: string = 'value'): void;",
      category: /parameter initializer/,
      snippet: /'value'/,
    },
    {
      name: 'method parameter initializer',
      declaration: "export class Service { run(value: string = 'value'): void; }",
      category: /parameter initializer/,
      snippet: /'value'/,
    },
    {
      name: 'constructor parameter initializer',
      declaration: "export class Service { constructor(value: string = 'value'); }",
      category: /parameter initializer/,
      snippet: /'value'/,
    },
    {
      name: 'typed variable initializer',
      declaration: "export const value: string = 'value';",
      category: /variable initializer/,
      snippet: /'value'/,
    },
    {
      name: 'definite assignment property',
      declaration: 'export class Service { value!: string; }',
      category: /definite assignment assertion/,
      snippet: /: !$/,
    },
    {
      name: 'definite assignment variable',
      declaration: 'export let value!: string;',
      category: /definite assignment assertion/,
      snippet: /: !$/,
    },
  ];

  for (const testCase of cases) {
    assert.throws(
      () => importVscodeDeclarations(`
        declare module 'vscode' { ${testCase.declaration} }
      `, `implementation-${testCase.name.replaceAll(' ', '-')}.d.ts`),
      (error) => {
        assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
        assert.match(error.message, testCase.category);
        assert.match(error.message, testCase.snippet);
        return true;
      },
      testCase.name,
    );
  }
});

test('type parameter modifiers fail closed instead of disappearing from IR', () => {
  const cases = [
    {
      fileName: 'const-type-parameter.d.ts',
      declaration: 'export function create<const T>(value: T): T;',
      snippet: /const T/,
    },
    {
      fileName: 'variance-type-parameter.d.ts',
      declaration: 'export interface Box<out T> { value: T; }',
      snippet: /out T/,
    },
  ];

  for (const testCase of cases) {
    const source = `
      declare module 'vscode' {
        ${testCase.declaration}
      }
    `;
    assert.throws(
      () => importVscodeDeclarations(source, testCase.fileName),
      (error) => {
        assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
        assert.match(error.message, /type parameter modifier TypeParameter/);
        assert.match(error.message, testCase.snippet);
        return true;
      },
    );
  }
});

test('distinguishes static and instance method signatures', () => {
  const source = `
    declare module 'vscode' {
      export class Service {
        static run(): void;
        run(): void;
      }
    }
  `;

  const methods = importVscodeDeclarations(
    source,
    'static-instance.d.ts',
  ).declarations.filter((item) => item.kind === 'method');

  assert.equal(methods.length, 2);
  assert.equal(new Set(methods.map((item) => item.id)).size, 2);
  assert.deepEqual(
    methods.map((item) => item.static).sort(),
    [false, true],
  );
});

test('distinguishes static and instance properties', () => {
  const source = `
    declare module 'vscode' {
      export class Service {
        static readonly value: string;
        readonly value: string;
      }
    }
  `;

  const properties = importVscodeDeclarations(
    source,
    'static-instance-properties.d.ts',
  ).declarations.filter((item) => item.kind === 'property');

  assert.equal(properties.length, 2);
  assert.equal(new Set(properties.map((item) => item.id)).size, 2);
  assert.deepEqual(
    properties.map((item) => item.static).sort(),
    [false, true],
  );
});

test('records abstract property semantics', () => {
  const source = `
    declare module 'vscode' {
      export abstract class AbstractService {
        abstract value: string;
      }
      export class ConcreteService {
        value: string;
      }
    }
  `;

  const properties = importVscodeDeclarations(
    source,
    'abstract-property.d.ts',
  ).declarations.filter((item) => item.kind === 'property');

  assert.deepEqual(
    properties.map((item) => [item.qualifiedName, item.abstract]),
    [
      ['vscode.AbstractService.value', true],
      ['vscode.ConcreteService.value', false],
    ],
  );
});

test('unprojected property modifiers fail closed', () => {
  const source = `
    declare module 'vscode' {
      export class Service { accessor value: string; }
    }
  `;

  assert.throws(
    () => importVscodeDeclarations(source, 'property-modifier.d.ts'),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
      assert.match(error.message, /property-modifier\.d\.ts/);
      assert.match(error.message, /class:vscode\.Service/);
      assert.match(error.message, /modifier AccessorKeyword/);
      return true;
    },
  );
});

test('interface-shaped members reject context-invalid modifiers', () => {
  const contexts = [
    {
      name: 'interface',
      wrap: (member) => `export interface Shape { ${member} }`,
    },
    {
      name: 'type-literal',
      wrap: (member) =>
        `export function use<T extends { ${member} }>(): void;`,
    },
  ];
  const propertyModifiers = [
    'public',
    'private',
    'protected',
    'static',
    'abstract',
    'declare',
    'override',
    'accessor',
  ];
  const methodModifiers = [...propertyModifiers, 'readonly'];

  for (const context of contexts) {
    for (const [memberKind, modifiers, member] of [
      ['property', propertyModifiers, (modifier) => `${modifier} value: string;`],
      ['method', methodModifiers, (modifier) => `${modifier} run(): void;`],
    ]) {
      for (const modifier of modifiers) {
        assert.throws(
          () => importVscodeDeclarations(`
            declare module 'vscode' {
              ${context.wrap(member(modifier))}
            }
          `, `${context.name}-${memberKind}-${modifier}.d.ts`),
          (error) => {
            assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
            assert.match(error.message, /modifier/);
            assert.match(error.message, new RegExp(`: ${modifier}$`));
            return true;
          },
          `${context.name} ${memberKind} ${modifier}`,
        );
      }
    }
  }
});

test('records readonly index-signature semantics in IDs and IR', () => {
  const source = `
    declare module 'vscode' {
      export interface MutableBag { [key: string]: number; }
      export interface ReadonlyBag { readonly [key: string]: number; }
    }
  `;

  const signatures = importVscodeDeclarations(
    source,
    'readonly-index.d.ts',
  ).declarations.filter((item) => item.kind === 'indexSignature');

  assert.deepEqual(signatures.map((item) => item.readonly), [false, true]);
  assert.deepEqual(
    signatures.map((item) => JSON.parse(item.canonicalSignature).readonly),
    [false, true],
  );
});

test('numeric literals remain distinct from strings and reject unsafe values', () => {
  const source = `
    declare module 'vscode' {
      export type Numeric = 1;
      export type Text = '1';
      export enum Mode { numeric = 1, text = '1' }
    }
  `;
  const declarations = importVscodeDeclarations(
    source,
    'numeric-literals.d.ts',
  ).declarations;

  assert.deepEqual(
    declarations
      .filter((item) => item.kind === 'typeAlias')
      .map((item) => item.type.value),
    [1, '1'],
  );
  assert.deepEqual(
    declarations
      .filter((item) => item.kind === 'enumMember')
      .map((item) => item.initializer.value),
    [1, '1'],
  );
  assert.throws(
    () => importVscodeDeclarations(`
      declare module 'vscode' {
        export type Unsafe = 9007199254740993;
      }
    `, 'unsafe-numeric-literal.d.ts'),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
      assert.match(error.message, /unsafe-numeric-literal\.d\.ts/);
      assert.match(error.message, /unsafe numeric literal/);
      return true;
    },
  );
});

test('intersection and nested type-literal member order and modifiers survive', () => {
  const intersection = (members) => importVscodeDeclarations(`
    declare module 'vscode' { export type Combined = ${members}; }
  `, 'intersection.d.ts').declarations.find(
    (item) => item.id === 'typeAlias:vscode.Combined',
  ).type;
  assert.notDeepEqual(
    intersection('((value: string) => 1) & ((value: string) => 2)'),
    intersection('((value: string) => 2) & ((value: string) => 1)'),
  );
  assert.notDeepEqual(intersection('1 | 2'), intersection('2 | 1'));

  const constraintShape = (member) => importVscodeDeclarations(`
    declare module 'vscode' {
      export interface Box<T extends { ${member} }> {}
    }
  `, 'constraint-shape.d.ts').declarations.find(
    (item) => item.id === 'interface:vscode.Box',
  ).typeParameters[0].constraint.shape;
  assert.notDeepEqual(
    constraintShape('run(): void;'),
    constraintShape('run?(): void;'),
  );
  assert.notDeepEqual(
    constraintShape('[key: string]: unknown;'),
    constraintShape('readonly [key: string]: unknown;'),
  );
  assert.notDeepEqual(
    constraintShape('first(): 1; second(): 2;'),
    constraintShape('second(): 2; first(): 1;'),
  );
});

test('nested type-literal IDs follow owner and shape across operand reorder', () => {
  const imported = (type) => {
    const declarations = importVscodeDeclarations(`
      declare module 'vscode' { export type Choice = ${type}; }
    `, 'nested-shape-order.d.ts').declarations;
    return {
      choice: declarations.find(
        (item) => item.id === 'typeAlias:vscode.Choice',
      ).type,
      idsByShape: Object.fromEntries(
        declarations
          .filter((item) => item.kind === 'typeLiteral')
          .map((item) => [item.shapeHash, item.id])
          .sort(),
      ),
    };
  };

  for (const operator of ['|', '&']) {
    const first = imported(`{ a: string } ${operator} { b: number }`);
    const reversed = imported(`{ b: number } ${operator} { a: string }`);

    assert.deepEqual(first.idsByShape, reversed.idsByShape);
    assert.equal(
      Object.values(first.idsByShape).every((id) => !id.includes('$item')),
      true,
    );
    assert.notDeepEqual(first.choice, reversed.choice);
  }
});

test('registered type literals carry their canonical member shape', () => {
  const crypto = require('node:crypto');
  const declarations = importVscodeDeclarations(`
    declare module 'vscode' {
      export function watch(options: {
        recursive: boolean;
        excludes: readonly string[];
        [key: string]: unknown;
      }): void;
    }
  `, 'registered-shape.d.ts').declarations;
  const literal = declarations.find((item) => item.kind === 'typeLiteral');
  assert.ok(literal.shape, 'registered type literal must carry its shape');
  assert.deepEqual(Object.keys(literal.shape), ['members']);
  assert.equal(
    crypto.createHash('sha256')
      .update(JSON.stringify(literal.shape))
      .digest('hex'),
    literal.shapeHash,
  );
  assert.deepEqual(
    literal.shape.members.map((member) => `${member.kind}:${member.name ?? ''}`),
    ['property:recursive', 'property:excludes', 'indexSignature:'],
  );
});

test('private identifiers are mechanically excluded from public coverage', () => {
  const property = importVscodeDeclarations(`
    declare module 'vscode' { export class Service { #secret: string; } }
  `, 'private-identifier.d.ts').declarations.find(
    (item) => item.kind === 'property',
  );

  assert.equal(property.visibility, 'private');
  assert.equal(property.coverage.semantics, 'excluded');
  assert.equal(property.coverage.host, 'notApplicable');
});

test('inline declarations inherit effective owner visibility recursively', () => {
  const declarations = importVscodeDeclarations(`
    declare module 'vscode' {
      export class Service {
        private privateShape: {
          nested: { value: string };
        };
        protected run(
          input: { nested: { value: string } },
        ): { nested: { value: string } };
        public publicShape: {
          nested: { value: string };
        };
      }
    }
  `, 'nested-visibility.d.ts').declarations;
  const declarationsById = new Map(
    declarations.map((declaration) => [declaration.id, declaration]),
  );
  const descendantsOf = (rootId) => declarations.filter((declaration) => {
    let parentId = declaration.parentId;
    while (parentId) {
      if (parentId === rootId) {
        return true;
      }
      parentId = declarationsById.get(parentId)?.parentId;
    }
    return false;
  });
  const roots = [
    ['privateShape', 'private'],
    ['run', 'protected'],
    ['publicShape', 'public'],
  ];

  for (const [name, visibility] of roots) {
    const root = declarations.find(
      (declaration) =>
        declaration.parentId === 'class:vscode.Service' &&
        declaration.name === name,
    );
    const descendants = descendantsOf(root.id);
    assert.ok(descendants.length >= 4, `${name} recursive descendants`);
    for (const declaration of [root, ...descendants]) {
      assert.equal(declaration.visibility, visibility, declaration.id);
      assert.equal(
        declaration.coverage.semantics,
        visibility === 'public' ? 'pending' : 'excluded',
        declaration.id,
      );
      assert.equal(
        declaration.coverage.host,
        visibility === 'public' ? 'pending' : 'notApplicable',
        declaration.id,
      );
    }
  }
});

test('inventories the complete pinned VS Code API without omissions', () => {
  const inputPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/vscode.d.ts',
  );
  const declarations = importVscodeDeclarations(
    fs.readFileSync(inputPath, 'utf8'),
    inputPath,
  ).declarations;
  const kinds = Object.fromEntries(
    [...new Set(declarations.map((item) => item.kind))]
      .sort()
      .map((kind) => [
        kind,
        declarations.filter((item) => item.kind === kind).length,
      ]),
  );

  assert.deepEqual(kinds, {
    callSignature: 1,
    class: 122,
    constructor: 123,
    enum: 64,
    enumMember: 234,
    function: 154,
    indexSignature: 28,
    interface: 303,
    method: 394,
    namespace: 16,
    property: 1334,
    typeAlias: 20,
    typeLiteral: 91,
    variable: 98,
  });
  assert.equal(
    new Set(declarations.map((item) => item.id)).size,
    declarations.length,
  );
  assert.equal(
    declarations
      .filter((item) => item.kind === 'function')
      .reduce((total, item) => total + (item.occurrenceCount ?? 1), 0),
    154,
  );
  assert.equal(
    declarations.some((item) => item.id === 'interface:global.Thenable'),
    true,
  );
});

test('fails closed on an unclassified public type member', () => {
  const source = `
    declare module 'vscode' {
      export interface FutureShape {
        new (): FutureShape;
      }
    }
  `;

  assert.throws(
    () => importVscodeDeclarations(source, 'unsupported-member.d.ts'),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
      assert.match(error.message, /unsupported-member\.d\.ts/);
      assert.match(error.message, /interface:vscode\.FutureShape/);
      assert.match(error.message, /ConstructSignature/);
      assert.match(error.message, /new \(\): FutureShape/);
      return true;
    },
  );
});

test('fails closed on an unclassified public module statement', () => {
  const source = `
    declare module 'vscode' {
      export import futureApi = FutureNamespace;
    }
  `;

  assert.throws(
    () => importVscodeDeclarations(source, 'unsupported-statement.d.ts'),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
      assert.match(error.message, /unsupported-statement\.d\.ts/);
      assert.match(error.message, /module:vscode/);
      assert.match(error.message, /ImportEqualsDeclaration/);
      assert.match(error.message, /futureApi = FutureNamespace/);
      return true;
    },
  );
});

test('nested unsupported syntax has a contextual fail-closed diagnostic', () => {
  const source = `
    declare module 'vscode' {
      export interface FutureShape<T> {
        value: T extends string ? true : false;
      }
    }
  `;

  assert.throws(
    () => importVscodeDeclarations(source, 'unsupported-nested-type.d.ts'),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_PUBLIC_SYNTAX');
      assert.match(error.message, /unsupported-nested-type\.d\.ts/);
      assert.match(
        error.message,
        /property:interface:vscode\.FutureShape\/\$instance\/value/,
      );
      assert.match(error.message, /ConditionalType/);
      assert.match(error.message, /T extends string \? true : false/);
      return true;
    },
  );
});

test('records orthogonal coverage states and explicit visibility exclusions', () => {
  const inputPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/vscode.d.ts',
  );
  const declarations = importVscodeDeclarations(
    fs.readFileSync(inputPath, 'utf8'),
    inputPath,
  ).declarations;
  const excluded = declarations.filter(
    (item) => item.coverage.semantics === 'excluded',
  );

  assert.equal(
    declarations.every(
      (item) => item.coverage.discovery === 'discovered',
    ),
    true,
  );
  assert.deepEqual(
    Object.fromEntries(
      ['private', 'protected'].map((visibility) => [
        visibility,
        excluded.filter((item) => item.visibility === visibility).length,
      ]),
    ),
    {private: 9, protected: 1},
  );
  assert.equal(excluded.every((item) => item.kind === 'constructor'), true);
  assert.equal(
    excluded.every(
      (item) =>
        item.coverage.binding === 'excluded' &&
        item.coverage.host === 'notApplicable',
    ),
    true,
  );
  assert.equal(
    declarations
      .filter((item) => item.visibility === 'public')
      .every(
        (item) =>
          item.coverage.semantics === 'pending' &&
          item.coverage.binding === 'pending' &&
          item.coverage.host === 'pending',
      ),
    true,
  );
});
