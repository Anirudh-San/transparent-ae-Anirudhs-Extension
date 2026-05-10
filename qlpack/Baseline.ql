/**
 * @name Client-side injection: Baseline
 * @description This query will count sinks that is in standard library
 * @kind problem
 * @problem.severity error
 * @security-severity 7.8
 * @precision high
 * @id js/xss
 * @tags security
 *       external/cwe/cwe-079
 *       external/cwe/cwe-116
 */

import javascript

import SourcesAndBarrier
import BaselineSinks

module BaselineFlowConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) {
    source instanceof ClientInjectionSource
  }

  predicate isBarrier(DataFlow::Node barrier) {
    barrier instanceof ClientInjectionBarrier
  }

  predicate isSink(DataFlow::Node sink) {
    not inBlacklistedFile(sink.getFile()) and (
      sink instanceof BaselineSink
    )
  }
}

module BaselineFlow = TaintTracking::Global<BaselineFlowConfig>;
// import BaselineFlow::PathGraph

from BaselineFlow::PathNode source, BaselineFlow::PathNode sink
where BaselineFlow::flowPath(source, sink)
select sink.getNode().getFile().getRelativePath(), sink.getNode().getStartLine().toString() 
