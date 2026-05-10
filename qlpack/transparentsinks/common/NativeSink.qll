import javascript 
import PropPropagation

/**
 * Assuming `elm` is HTML Element, is `sink` a DOM sink associated with it?
 */
predicate isDomSink(DataFlow::Node elm, DataFlow::Node sink) {
  // PropWrite
  exists(DataFlow::PropWrite pw | 
      isPropagated(elm, pw, vulnNativeProp())
      and pw.getRhs() = sink
  )

  // MethodCallNode
  or exists(DataFlow::MethodCallNode mc | 
      elm = mc.getReceiver()
      and (
          isVulnNativeElementFixedMethod(mc, sink)
          or isVulnNativeElementGenericMethod(mc, _, sink)
      )
  )
}

/**
 * This predicate does not check the receiver
 */
predicate isVulnNativeElementFixedMethod(DataFlow::MethodCallNode mc, DataFlow::Node arg) {
  exists(int argPos, string name | arg = mc.getArgument(argPos) and name = mc.getMethodName() | 
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
  )
}

/**
 * This predicate does not check the receiver
 */
predicate isVulnNativeElementGenericMethod(DataFlow::MethodCallNode mc, DataFlow::Node kArg, DataFlow::Node vArg) {
  exists(int vArgPos, int kArgPos, string name | 
    vArg = mc.getArgument(vArgPos) 
    and kArg = mc.getArgument(kArgPos)
    and name = mc.getMethodName() | 

    name = "setAttribute" and vArgPos = 1 and kArgPos = 0 
    or name = "setAttributeNS" and vArgPos = 2 and (kArgPos = 0 or kArgPos = 1)
    // below are new! (these technically aren't URL, since they use `Attr` object)
    // TODO: flesh out `Attr` object detection
    or name = "setAttributeNode" and vArgPos = 0
    or name = "setAttributeNodeNS" and vArgPos = 0
  )
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
}