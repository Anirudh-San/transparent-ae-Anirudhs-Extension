/**
 * A library to analyze DOM dataflow in Javascript.
 * This library is an extension and rewrite of `semmle.javascript.security.dataflow.DOM`
 * 
 * It aims to fix multiple problems that the original library has:
 * 1. False negatives: It doesn't mark `setAttribute()` with variable `propName` as a sink.
 *      This is particularly problematic for analyzing front-end frameworks since 
 *      they often use `setAttribute` to translate between templating engine prop 
 *      and the DOM attribute.
 * 2. False negatives: it doesn't have complete list of vulnerable sinks. (e.g. `append`, `write`)
 * 3. False positives: even if the argument is constant, it still marks the DOM manipulation as a sink. 
 *  - Handle this with the flow analysis?
 * 4. Maybe false positives: it marks certain methods as sinks, even though they don't exist for 
 *      certain classes. For example, `createElement()` only exists in `DOM::Document` but not 
 *      `DOM::Element`, but in the original library, it's marked as a sink for all `DOM::Node`.
 *      I've never encountered this in the wild though, so wontfix.
 * 
 * How the original library works:
 *  - `semmle.javascript.DOM` defines...
 *      - Syntax nodes
 *      - Source dataflow nodes -> usually uses `ref` functions because they use type tracking
 *  - `semmle.javascript.security.dataflow.DOM` defines...
 *      - Miscellaneous dataflow nodes, based on the source defined on `semmle.javascript.DOM`
 */

import javascript

import semmle.javascript.DOM
import semmle.javascript.security.dataflow.DOM

/**
 * A method call whose receiver is a DOM `Element` or `Document`
 * 
 * e.g.
 * `document.write(payload)`
 * `div.insertAdjacentHTML("beforeend", payload)`
 */
class DomMethodCallNodeExtended extends DataFlow::MethodCallNode {
    DomMethodCallNodeExtended() { 
        isDomNode(this.getReceiver()) 
        // Original library doesn't detect `document.write` due to the receiver type
        or DOM::documentRef().flowsTo(this.getReceiver())
    }

    /**
     * Holds if `arg` is an argument that is interpreted as HTML.
     * 
     * This is the same as CodeQL's, but with 9 new DOM sinks and filter literals!
     */
    predicate interpretsArgumentAsHtml(DataFlow::Node arg) {
        not arg.asExpr() instanceof Literal and
        isFixedSink(arg)
    }

    /**
     * Holds if `arg` is an argument that is used as a URL.
     * 
     * This is the same as CodeQL's, but with 2 new sinks and attribute name as a sink too!
     * And filter literals!
     */
    predicate interpretsArgumentAsUrl(DataFlow::Node arg) {
        isGenericSink(arg, _)
    }

    /**
     * Holds if a DOM method interprets argument(s) `arg` as HTML or URL without requiring 
     * a specifier argument (e.g. propName, namespace)
     * 
     * Empirically though, this type of DOM method always takes HTML instead of URL, so 
     * let's just use `interpretsArgumentAsHtml` for now.
     */
    predicate isFixedSink(DataFlow::Node payloadSink) {
        exists(int argPos, string name | payloadSink = this.getArgument(argPos) and name = this.getMethodName() | 
            // Node
            name = "appendChild" and argPos = 0 or
            // below are new!
            name = "insertBefore" and argPos = 0 or
            name = "replaceChild" and argPos = 1 or
        
            // Element
            name = "insertAdjacentHTML" and argPos = 1 or
            // name = "insertAdjacentElement" and argPos = 1 or 
            // below are new!
            name = "append" or          // shared with `Document` and `DocumentFragment`
            name = "prepend" or         // shared with `Document` and `DocumentFragment`
            name = "before" or          // shared with `DocumentType`
            name = "after" or           // shared with `DocumentType`
            name = "replaceWith" or     // shared with `DocumentType`
            name = "replaceChildren" or // shared with `DocumentFragment`

            // Document
            name = "write" and argPos = 0 or
            name = "writeln" and argPos = 0
            // name = "createElement" and argPos = 0 or 
            // below are new!
            // name = "createElementNS" and argPos = 1
        )
    }

    /**
     * Holds if a DOM method interprets argument(s) `payloadArg` as HTML or URL if certain value
     * flows to `specifierArg`
     * 
     * This is to be paired with `isDomPropInterpretedAsUrl`
     * 
     * Empirically though, this type of DOM method always takes URL instead of HTML, so specify
     * them here and let `interpretsArgumentAsUrl` ignore `specifierArg`.
     */
    predicate isGenericSink(DataFlow::Node payloadSink, DataFlow::Node propNameSink) {
        exists(int pArgPos, int sArgPos, string name | 
            payloadSink = this.getArgument(pArgPos) 
            and propNameSink = this.getArgument(sArgPos)
            and name = this.getMethodName() | 
            // Element
            // TODO: more sophisticated way to filter name?
            name = "setAttribute" and pArgPos = 1 and sArgPos = 0 
            or name = "setAttributeNS" and pArgPos = 2 and (sArgPos = 0 or sArgPos = 1)
            // below are new! (these technically aren't URL, since they use `Attr` object)
            // TODO: flesh out `Attr` object detection
            or name = "setAttributeNode" and pArgPos = 0
            or name = "setAttributeNodeNS" and pArgPos = 0
        )
    }
}

/**
 * A write to a DOM object property
 * 
 * Could be assignment e.g. `div.innerHTML = sink`
 * Could be function, e.g. `Object.defineProperty(div, "innerHTML", sink)`
 * Not that this is not a `MethodCallNode` because the receiver is not a `Node`
 * 
 * To get the payload, use `getRhs()` 
 *
 * e.g.
 * `div.innerHTML = "<script>alert(1)</script>"`
 * `div["innerHTML"] = "<script>alert(1)</script>"`
 * `iframe.src = "javascript:alert(1)"`
 */
class DomPropertyWriteExtended extends DataFlow::Node instanceof DataFlow::PropWrite {
    DomPropertyWriteExtended() { 
        isDomNode(super.getBase()) 
        // Heuristic: if there's a PropRef and the name is a nativeProp, then the base is an HTML Element
        or exists (DataFlow::PropRef p | p.getPropertyName() = vulnNativePropHTML() | 
            p.getBase().getALocalSource().flowsTo(this.getBase())
        )
    }

    // TESTING ONLY
    // predicate getPropertyNameExpr(Expr e) {
    //     e = super.getPropertyNameExpr()
    // }

    predicate interpretsValueAsHtml() {
        super.getPropertyName() = vulnNativePropHTML()
    }

    predicate interpretsValueAsUrl() {
        super.getPropertyName() = vulnNativeAttr()
    }

    /**
     * Dot-notation property, property initializer, JSX attribute?, `Object.defineProperties`
     * In Dot-notation property, the property itself is an `Identifier`
     */
    predicate isFixedSink() {
        // Vulnerable property
        (interpretsValueAsHtml() or interpretsValueAsUrl())
        // Any assignment that's not bracket-notation or `Object.defineProperty`
        and not (
            this.asExpr() instanceof IndexExpr
            or (
                this.asExpr() instanceof MethodCallExpr 
                and this.asExpr().(MethodCallExpr).getMethodName() = "defineProperty"
            )
        )
    }

    /**
     * Bracket-notation property and `Object.defineProperty`
     * 
     * We can't use `interpretsValueAs*` because property name can't be statically determined.
     */
    predicate isGenericSink(DataFlow::Node propNameSink) {
        // Pass property handle to `propNameSink`
        super.getPropertyNameExpr() = propNameSink.asExpr()
        // Bracket-notation property and `Object.defineProperty`
        and (
            this.asExpr() instanceof IndexExpr
            or (
                this.asExpr() instanceof MethodCallExpr 
                and this.asExpr().(MethodCallExpr).getMethodName() = "defineProperty"
            )
        )
    }

    /**
     * Gets the data flow node corresponding to the value being written.
     * 
     */
    DataFlow::Node getRhs() {
        not result.asExpr() instanceof Literal and (
            result = super.getRhs()
            or
            result = super.getWriteNode().(AssignAddExpr).getRhs().flow()
        )
    }
}

/**
 * Assume that `elm` is an HTML element
 */
predicate isDomSink(DataFlow::Node elm, DataFlow::Node payload) {
    // PropWrite
    exists(DataFlow::PropWrite pw | 
        elm = pw.getBase()
        and pw.getPropertyName() = vulnNativeProp()
        and pw.getRhs() = payload    
    )

    // MethodCallNode
    or exists(DataFlow::MethodCallNode mc, int argPos | 
        elm = mc.getReceiver()
        and (
            isVulnNativeElementFixedMethod(mc.getMethodName(), argPos)
            or isVulnNativeElementGenericMethod(mc.getMethodName(), 0, argPos)
        )
        and payload = mc.getArgument(argPos)
    )
}

bindingset[argPos]
predicate isVulnNativeElementFixedMethod(string name, int argPos) {
    // Node
    name = "appendChild" and argPos = 0 
    // below are new!
    or name = "insertBefore" and argPos = 0 
    or name = "replaceChild" and argPos = 1 

    // Element
    or name = "insertAdjacentHTML" and argPos = 1 
    // name = "insertAdjacentElement" and argPos = 1 or 
    // below are new!
    or name = "append"          // shared with `Document` and `DocumentFragment`
    or name = "prepend"         // shared with `Document` and `DocumentFragment`
    or name = "before"          // shared with `DocumentType`
    or name = "after"           // shared with `DocumentType`
    or name = "replaceWith"     // shared with `DocumentType`
    or name = "replaceChildren" // shared with `DocumentFragment`
}

bindingset[sArgPos]
predicate isVulnNativeElementGenericMethod(string name, int sArgPos, int pArgPos) {
    // TODO: more sophisticated way to filter name?
    name = "setAttribute" and pArgPos = 1 and sArgPos = 0 
    or name = "setAttributeNS" and pArgPos = 2 and (sArgPos = 0 or sArgPos = 1)
    // below are new! (these technically aren't URL, since they use `Attr` object)
    // TODO: flesh out `Attr` object detection
    or name = "setAttributeNode" and pArgPos = 0 and sArgPos = 0 
    or name = "setAttributeNodeNS" and pArgPos = 0 and sArgPos = 0 
}

/**
 * HTML Element property names that are vulnerable.
 */
string vulnNativeProp() {
    result = vulnNativeAttr()
    or result = vulnNativePropHTML()
}

/**
 * HTML Element property names that are vulnerable to HTML injection.
 */
string vulnNativePropHTML() {
    result = "innerHTML"
    or result = "outerHTML"
}

/**
 * HTML attribute names that are vulnerable. Always interprets value as URL. 
 */
string vulnNativeAttr() {
    // src, href, action, formaction, data
    result = DOM::getAPropertyNameInterpretedAsJavaScriptUrl()
    // New
    or result = "xlink:href"
    or result = "srcdoc"    // iframe
    or result = "code"      // embed, Chrome-specific
    or result = "data"      // object, Firefox-specific
    or result = "download"
}