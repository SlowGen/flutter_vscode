'use strict';

// Source Map v3 queries for the breakpoint driver, delegating decoding to
// @jridgewell/trace-mapping — the maintained decoder the bundler ecosystem
// standardized on. The library's entry point arrives via
// FLUTTER_VSCODE_BREAKPOINT_TRACE_MAPPING_PATH because this module loads
// inside the pinned Extension Host, where the harness's node_modules
// directory is not on the require resolution path; run_breakpoint.cjs
// resolves the path and passes it through extensionTestsEnv.

const traceMappingPath =
  process.env.FLUTTER_VSCODE_BREAKPOINT_TRACE_MAPPING_PATH;
if (!traceMappingPath) {
  throw new Error(
    'FLUTTER_VSCODE_BREAKPOINT_TRACE_MAPPING_PATH is required — ' +
      'run this driver through run_breakpoint.cjs',
  );
}
const {TraceMap, originalPositionFor, eachMapping} = require(traceMappingPath);

/**
 * Opens a Source Map v3 document for position queries.
 *
 * Every line and column crossing this interface is 0-based, matching the
 * Chrome DevTools Protocol; the 1-based line convention trace-mapping
 * inherits from the source-map library stays inside this module.
 */
function openSourceMap(map) {
  const tracer = new TraceMap(map);
  return {
    /** Source strings with `sourceRoot` applied, in map order. */
    sources: tracer.resolvedSources,

    /** Every generated position that maps to `line` of `source`. */
    generatedPositionsFor(source, line) {
      const positions = [];
      eachMapping(tracer, (mapping) => {
        if (mapping.source === source && mapping.originalLine === line + 1) {
          positions.push({
            lineNumber: mapping.generatedLine - 1,
            columnNumber: mapping.generatedColumn,
          });
        }
      });
      return positions;
    },

    /**
     * The original position covering a generated position: the mapping on
     * the generated line with the greatest column not exceeding the queried
     * column. Returns null when no mapping covers the position.
     */
    originalFor(lineNumber, columnNumber) {
      const original = originalPositionFor(tracer, {
        line: lineNumber + 1,
        column: columnNumber,
      });
      if (original.source === null) {
        return null;
      }
      return {
        source: original.source,
        lineNumber: original.line - 1,
        columnNumber: original.column,
      };
    },
  };
}

module.exports = {openSourceMap};
