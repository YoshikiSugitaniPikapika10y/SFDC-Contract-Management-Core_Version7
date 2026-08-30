/**
 * InvoiceDocumentPdf Visualforce ページ用コントローラ。
 */
public with sharing class InvoiceDocumentPdfController {
  public InvoiceDocumentService.DocumentContext context { get; private set; }
  public Boolean hasContext { get; private set; }

  public InvoiceDocumentPdfController() {
    Id invoiceId = parseRecordId();
    if (invoiceId == null) {
      hasContext = false;
      return;
    }
    try {
      context = InvoiceDocumentService.loadContext(invoiceId);
      hasContext = true;
    } catch (InvoiceDocumentService.InvoiceDocumentException ex) {
      hasContext = false;
      ApexPages.addMessage(
        new ApexPages.Message(ApexPages.Severity.ERROR, ex.getMessage())
      );
    }
  }

  private Id parseRecordId() {
    String rawId = ApexPages.currentPage().getParameters().get('id');
    if (String.isBlank(rawId)) {
      return null;
    }
    try {
      return (Id) rawId;
    } catch (Exception ex) {
      return null;
    }
  }
}
