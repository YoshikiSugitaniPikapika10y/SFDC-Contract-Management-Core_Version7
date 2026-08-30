/**
 * 契約期間明細 / 請求 / 請求明細の before insert で
 * FieldCopyDefinition__c に基づく空欄埋めを行う。
 */
public without sharing class InvoiceFieldCopyTriggerHandler {
  /** 仕様: Core 第11.4.2節 */
  public static void handlePeriodLineBeforeInsert(
    List<InvoiceProduct__c> records
  ) {
    FieldCopyDefinitionService.applyOnInsert(
      records,
      InvoiceProductFieldCopyService.TARGET_INVOICE_PRODUCT
    );
  }

  /** 仕様: Core 第11.4.2節 */
  public static void handleInvoiceBeforeInsert(List<Invoice__c> records) {
    FieldCopyDefinitionService.applyOnInsert(
      records,
      InvoiceProductFieldCopyService.TARGET_INVOICE
    );
  }

  /** 仕様: Core 第11.4.2節 */
  public static void handleInvoiceLineBeforeInsert(
    List<InvoiceLine__c> records
  ) {
    FieldCopyDefinitionService.applyOnInsert(
      records,
      InvoiceProductFieldCopyService.TARGET_INVOICE_LINE
    );
  }
}
