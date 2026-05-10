import javascript

from DataFlow::CallNode c
where c.getCalleeName() = "createElementNS"
  or c.getCalleeName() = "setAttributeNS"
  or c.getCalleeName() = "setAttribute"
select c.getFile().getRelativePath(),
       c.getStartLine(),
       c.getCalleeName(),
       c.getArgument(0).toString()
