/**
 * 契約期間明細 / 請求 / 請求明細の before insert で
 * InvoiceProductFieldCopy__mdt に基づく空欄埋めを行う。
 */
public without sharing class InvoiceFieldCopyTriggerHandler {
  public static void handlePeriodLineBeforeInsert(
    List<InvoiceProduct__c> records
  ) {
    InvoiceProductFieldCopyService.applyOnBeforeInsert(
      records,
      InvoiceProductFieldCopyService.TARGET_INVOICE_PRODUCT
    );
  }

  public static void handleInvoiceBeforeInsert(List<Invoice__c> records) {
    InvoiceProductFieldCopyService.applyOnBeforeInsert(
      records,
      InvoiceProductFieldCopyService.TARGET_INVOICE
    );
  }

  public static void handleInvoiceLineBeforeInsert(
    List<InvoiceLine__c> records
  ) {
    InvoiceProductFieldCopyService.applyOnBeforeInsert(
      records,
      InvoiceProductFieldCopyService.TARGET_INVOICE_LINE
    );
  }
}
