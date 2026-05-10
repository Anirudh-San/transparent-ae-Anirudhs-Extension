import javascript

from DataFlow::PropWrite pw
where pw.getPropertyName() = "innerHTML"
  or pw.getPropertyName() = "textContent"
select pw.getFile().getRelativePath(),
       pw.getStartLine(),
       pw.getPropertyName(),
       pw.getRhs().toString()
