/**
 * This is a library defining the SPA-sinks included in CodeQL Javascript 
 * library. There are two possibilities where these sinks could be defined:
 * 
 * 1. __Vulnerability-based__: These sinks are defined inside dataflow security
 *  queries (semmle.javascript.security.dataflow.*). Since we target 
 *  client-side taint-style vulnerabilities, we look into 4 files:
 *    - `ClientSideUrlRedirect` (despite the name, includes `javascript:` XSS)
 *    - `CodeInjection`
 *    - `DomBasedXss`
 *    - `ExceptionXss`
 *    - `ReflectedXss` -> only header
 *    - `StoredXss` -> uses arbitrary XSS sink
 *    - `XssThroughDom` -> new sources only
 * 
 *    The sink could be imported straightforwardly (e.g., `VHtmlSink`) or is a 
 *    superset sink that includes SPA-sink (e.g., `AttributeUrlSink`). In the 
 *    latter case, we restrict the sink further to only include relevant 
 *    SPA-sink.
 * 
 * 2. __Framework-based__: These sinks are defined inside the framework
 *  model inside the library (semmle.javascript.framework.*). If the sink
 *  class is private (making them unimportable), we copy-pasted them in this 
 *  file, along with their private dependencies. We look into files relating
 *  directly into the our targeted frameworks:
 *    - `React.qll`
 *    - `Vue.qll`
 *    - `Angular2.qll`
 */

import javascript

import semmle.javascript.security.dataflow.DomBasedXssCustomizations
import semmle.javascript.security.dataflow.ClientSideUrlRedirectCustomizations
import semmle.javascript.security.dataflow.CodeInjectionCustomizations

// ============================================================================
// Private import start
// ============================================================================

// Angular-specific sink that are private, so we copy it here
module AngularSink {
  DataFlow::SourceNode domSanitizer() {
    result.hasUnderlyingType(["@angular/platform-browser", "@angular/core"], "DomSanitizer")
  }
  
  class AngularXssSink extends DataFlow::Node {
    AngularXssSink() {
      this =
        domSanitizer()
            .getAMethodCall(["bypassSecurityTrustHtml", "bypassSecurityTrustStyle"])
            .getArgument(0)
    }
  }
  
  class AngularCodeInjectionSink extends DataFlow::Node {
    AngularCodeInjectionSink() {
      this = domSanitizer().getAMethodCall("bypassSecurityTrustScript").getArgument(0)
    }
  }
  
  class AngularUrlSink extends DataFlow::Node {
    // We mark this as a client URL redirect sink for precision reasons, though its description can be a bit confusing.
    AngularUrlSink() {
      this =
        domSanitizer()
            .getAMethodCall(["bypassSecurityTrustUrl", "bypassSecurityTrustResourceUrl"])
            .getArgument(0)
    }
  }
}

// ============================================================================
// Private import end
// ============================================================================

class BaselineSink extends DataFlow::Node {
  BaselineSink() {
    // HTML-syntax: HTML (Vue SFC, Angular)
    // From `ClientSideUrlRedirectCustomizations.qll`

    // This is a more restrictive version of `AttributeUrlSink` (based on 
    // DOM::AtrributeDefinition) that only includes HTML-syntax sink (attribute
    // write) and excludes JS-syntax DOM API, which is irrelevant because it 
    // does not depend on any framework runtime.
    exists(DOM::AttributeDefinition attr | this = attr.getValueNode() |
      attr instanceof HTML::Attribute // This is how v-html is defined
      and attr.getName() = DOM::getAPropertyNameInterpretedAsJavaScriptUrl() 
    )

    // HTML-syntax: JSX (React, Vue JSX) 
    or this instanceof ClientSideUrlRedirect::ReactAttributeWriteUrlSink // `ClientSideUrlRedirectCustomizations.qll`
    or this instanceof CodeInjection::ReactScriptTag // `CodeInjectionCustomizations.qll

    // or exists(string name | name = ["open", "openDialog"] |
    //   this = DataFlow::globalVarRef(name).getACall().getArgument(0)
    // )

    // Vue-specific (all from `DomBasedXssCustomizations.qll`)
    or this instanceof DomBasedXss::VHtmlSink
    or this instanceof DomBasedXss::VueTemplateSink
    or this instanceof DomBasedXss::VueCreateElementSink

    // React-specific (all from `DomBasedXssCustomizations.qll`)
    or this instanceof DomBasedXss::DangerouslySetInnerHtmlSink
    
    // Angular-specific (all privately-defined in `Angular2.qll`)
    or this instanceof AngularSink::AngularXssSink
    or this instanceof AngularSink::AngularCodeInjectionSink
    or this instanceof AngularSink::AngularUrlSink
  }
}

// NOTE: Angular has DomValueSource that is the ref!
// NOTE: `AttributeWriteUrlSink` is not included because the only part that
// is relevant is already covered by `ReactAttributeWriteUrlSink`
