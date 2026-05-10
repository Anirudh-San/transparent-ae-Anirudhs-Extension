import javascript

/**
 * Predicate to check whether a PropRef `pr` has a reference on its `propName`
 * property, whose base flows from `base`. 
 * 
 * This pattern is common in our analysis, especially a chain of PropRef that 
 * ends win a PropWrite, e.g., `this.something.innerHTML = payload`
 * 
 * This is an extension of hasPropertyWrite() that the standard library has
 * that also handles non SourceNode types.
 */
predicate isPropagated(DataFlow::Node base, DataFlow::PropRef pr, string propName) {
  // `propName` corresponds to `pr`
  propName = pr.getPropertyName()

  // `base` is the same object as the base of `pr`
  and (
    // Normal (SourceNode, PropRead, e.g., `base.propName`)
    base.(DataFlow::SourceNode).flowsTo(pr.getBase())

    // Class member (e.g., `this.m = base; this.m.propName;`)
    or exists(DataFlow::ClassNode c, DataFlow::PropWrite pw, string memberName | 
      pw = c.getAnInstanceReference().getAPropertyWrite(memberName)
      and base = pw.getRhs()
      and pr.getBase() = c.getAnInstanceReference().getAPropertyRead(memberName)
    )

    // Object literal (e.g., `{ base: { propName: rhs }}`)
    or base.(DataFlow::PropWrite).getRhs() = pr.getBase()
    or pr.getBase().(DataFlow::SourceNode).flowsTo(base.(DataFlow::PropWrite).getRhs())
  )
}

/**
 * Recursively get a caller
 */
Function getACaller(Function callee) {
  exists(DataFlow::InvokeNode node | 
    node.getACallee() = callee
    and node.getEnclosingFunction() = result  
  )
}

/**
 * Recursively get all the bases of a `PropRead` (inclusive)
 * 
 * E.g., for `this.a.b`, it will return nodes for `this`, `this.a`, and `this.a.b`
 */
DataFlow::Node getAncestorBase(DataFlow::Node cur) {
  result = cur
  or result = getAncestorBase(cur.(DataFlow::PropRead).getBase())
}