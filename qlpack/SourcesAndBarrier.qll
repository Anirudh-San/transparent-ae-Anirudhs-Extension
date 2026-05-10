import javascript

import semmle.javascript.security.dataflow.DomBasedXssCustomizations
import semmle.javascript.security.dataflow.XssThroughDomCustomizations
import semmle.javascript.security.TaintedUrlSuffixCustomizations

import transparentsinks.common.PropPropagation

/**
 * Client-side injection sources.
 *
 * This includes
 *  - DOM input (whatever source is in `XssThroughDom`)
 *  - URL (whatever source is in `TaintedUrlSuffix`)
 *  - Component parameters
 */
class ClientInjectionSource extends DataFlow::Node {
  ClientInjectionSource() {
    this instanceof XssThroughDom::Source
    or this = TaintedUrlSuffix::source()

    // Component parameters
    // Vue 2
    or exists(Vue::Component c | 
      this = c.getAPropertyValue(_)
      // `this` methods in JS syntax (e.g., `render`)
      or exists(DataFlow::FunctionNode renderFunc | 
        renderFunc.flowsTo(c.getRender())
        or renderFunc.getName() = "render" 
      |
        this = renderFunc.getParameter(1) // props
        or this.(DataFlow::ThisNode).getBinder() = renderFunc // this
      ) 
      // `this` property (e.g., `this.$refs`)
      or exists(DataFlow::Node receiver | 
        (
          this.(DataFlow::MethodCallNode).getReceiver() = receiver
          or this.(DataFlow::PropRead).getBase() = receiver
        )
        // in SFC, `this` is not a `ThisNode`, so compare string instead
        and getAncestorBase(receiver).toString() = "this.$refs" 
      )
      // `create` methods
      or exists(DataFlow::FunctionNode createFunc | 
        (createFunc.flowsTo(c.getMethods())
        or createFunc.getName().matches("create%"))
        and this = createFunc.getAParameter()
      )
      // `actions` methods
      or exists(DataFlow::FunctionNode actionsFunc | 
        (actionsFunc.flowsTo(c.getMethods())
        or actionsFunc.getName().matches("getActions"))
        and this = actionsFunc.getAParameter()
      )
    // React
    ) or exists(ReactComponent c | 
      this = c.getACandidatePropsSource()
      or this = c.getADirectPropsAccess()
      or this = c.getACandidateStateSource()
      or this = c.getADirectStateAccess()
    // React: sometimes component does not define a name "props"
    ) or exists(Function f | 
      // f.getName().matches("render%")
      f.getNumParameter() = 1
      and forex(Expr e | 
        e.flow().(DataFlow::SourceNode).flowsToExpr(f.getAReturnedExpr())
        and not exists(e.getStringValue()) // no string literal
      |
        e instanceof JsxNode
        or e instanceof ReactElementDefinition
      )
      and this = DataFlow::parameterNode(f.getParameter(0))
    // React: Component could be wrapped in `forwardRef`
    ) or exists(DataFlow::CallNode f | 
      f.getCalleeName() = "forwardRef"
      and this = f.getABoundCallbackParameter(0, 0) // props 
    // Angular
    ) or exists(Angular2::ComponentClass c | 
      this = c.getATemplateArgument(_)
      or this = c.getFieldInputNode(_)
    // Angular: Inputs
    ) or exists(DataFlow::ClassNode c, DataFlow::CallNode decorator | 
      decorator = c.getADecorator()
      and decorator = DataFlow::moduleMember(any(string s | s in [ "angular2/core", "@angular/core" ]), any(string s | s in [ "Component", "Directive" ])).getACall()
      // and this = decorator.getOptionArgument(0, "inputs")
      and exists(string inputName | 
        // this instanceof DataFlow::PropRead
        this.(DataFlow::PropRead).getBase().toString() = "this"
        and this.(DataFlow::PropRead).getPropertyName() = inputName
      //   thisProp.getBase() instanceof DataFlow::ThisNode
      //   and thisProp.getPropertyName() = inputName
        and decorator.getOptionArgument(0, "inputs").toString().matches("%" + inputName + "%")
      )
    )
  }
}

/**
 * Barrier for client-side injection sinks.
 * 
 * This effectively includes:
 *  - `MetacharEscapeSanitizer` (from `Xss`)
 *  - `UriEncodingSantizer` (from `Xss`)
 *  - `SerializeJavascriptSanitizer` (from `Xss`)
 *  - `IsEscapedInSwitchSanitizer` (from `Xss`)
 *  - `HtmlSanitizerAsSanitizer` (from `DomBasedXss`)
 *  - `SafePropertyReadSanitizer` (from `DomBasedXss`)
 */
class ClientInjectionBarrier extends DataFlow::Node {
  ClientInjectionBarrier() {
    this instanceof DomBasedXss::Sanitizer
  }
}

/**
 * Tweaks to the default Vue's VHtmlAttribute step.
 * 
 * The problem with the default step is that it only matches simple expression
 * like `v-html="foo"` and does not match more complicated expressions like 
 * property access `v-html="foo.bar"`.
 */
class TweakedVHtmlAttributeStep extends TaintTracking::SharedTaintStep {
  override predicate viewComponentStep(DataFlow::Node pred, DataFlow::Node succ) {
    exists(Vue::Component component, string expr, Vue::VHtmlAttribute attr |
      attr.getAttr().getRoot() = component.getTemplateElement().(Vue::Template::HtmlElement).getElement() 
      and (
        // regex change from the original
        expr = attr.getAttr().getValue().regexpCapture("(?<!\\.)([a-zA-Z_$][\\w$]+).*", 1)
      ) and
      pred.toString() = expr 
      and pred.getLocation().getFile() = succ.getLocation().getFile()
      and succ = attr
    )
  }
}

/**
 * Tweaks to the default React's `DangerouslySetInnerHtmlStep`.
 * 
 * Expands to include function calls.
 */
class TweakedDangerouslySetInnerHtmlStep extends TaintTracking::SharedTaintStep {
  override predicate step(DataFlow::Node pred, DataFlow::Node succ) {
    succ instanceof DomBasedXss::DangerouslySetInnerHtmlSink
    and pred = succ.(DataFlow::CallNode).getAnArgument()
  }
}

/**
 * Blacklist irrelevant files based on path heuristic:
 *  - Tests
 *  - Documentation (and examples)
 *  - Bundles (includes transpiled SPA component)
 */
predicate inBlacklistedFile(File file) {
  exists(string relativePath | relativePath = file.getRelativePath() | 
    // Tests
    relativePath.matches("%test%")
    or relativePath.matches("%.spec%")

    // Documentation
    or relativePath.matches("%example%")
    or relativePath.matches("%docs%")

    // Bundles
    or relativePath.matches("%static%")
    or relativePath.matches("%asset%")
    or relativePath.matches("%dist%")
    or relativePath.matches("%libs%")
  )
}

/**
 * Related function calls that produce HTML content.
 */
class HtmlStep extends TaintTracking::SharedTaintStep {
  override predicate step(DataFlow::Node pred, DataFlow::Node succ) {
    exists(DataFlow::InvokeNode call | 
      succ = call 
      and pred = call.getAnArgument()
      and (
        call instanceof DataFlow::CallNode and (
          call.getCalleeName() = "makeHtml"
          or call.getCalleeName() = "postrender"
          or call.getCalleeName() = "prerender"
          or (
            call instanceof DataFlow::MethodCallNode
            and (
              call.getCalleeName() = "render"
              or call.getCalleeName() = "createObjectURL"
            )
          )
        ) 
        or 
        call instanceof DataFlow::NewNode and (
          call.getCalleeName() = "Blob"
        )
      )
    )
  }
}

/**
 * Missing step for array literals.
 */
class ArrayStep extends TaintTracking::SharedTaintStep {
  override predicate step(DataFlow::Node pred, DataFlow::Node succ) {
    succ instanceof DataFlow::ArrayLiteralNode
    and pred = succ.(DataFlow::ArrayLiteralNode).getAnElement()
  }
}

