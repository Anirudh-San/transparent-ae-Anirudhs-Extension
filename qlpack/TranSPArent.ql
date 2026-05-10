/**
 * @name Client-side injection: TranSPArent
 * @description This query will count sinks that is in standard library and TranSPArent
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

import transparentsinks.Vue2
import transparentsinks.React
import transparentsinks.Angular

module TransparentFlowConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) {
    source instanceof ClientInjectionSource
  }

  predicate isBarrier(DataFlow::Node barrier) {
    barrier instanceof ClientInjectionBarrier
  }

  predicate isSink(DataFlow::Node sink) {
    // sink.getFile().getRelativePath().matches("%AposModalReport.vue") and
    not inBlacklistedFile(sink.getFile()) and (
      sink instanceof BaselineSink

      // New sinks
      or sink instanceof Vue2Sink
      or sink instanceof ReactSink
      or sink instanceof AngularSink
    )
  }
}

module TransparentFlow = TaintTracking::Global<TransparentFlowConfig>;
// import TransparentFlow::PathGraph

from TransparentFlow::PathNode source, TransparentFlow::PathNode sink
where TransparentFlow::flowPath(source, sink)
select sink.getNode().getFile().getRelativePath(), sink.getNode().getStartLine().toString()
// select sink.getNode(), source, sink, "debug"