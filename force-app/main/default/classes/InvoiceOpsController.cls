/**
 * 請求正本（Invoice__c）の連携・消込ロック操作。
 * 旧 InvoiceProductExport / Invoiced コントローラの後継。
 * 入口はすべて Contract_13_Can_Manage_Invoice_Ops 必須。
 */
public without sharing class InvoiceOpsController {
  @TestVisible
  private static final String CLEAR_EXPORT_WHEN_INVOICED_MESSAGE = '連携済の請求の消込日はクリアできません。';

  public class InvoiceRowDto {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date invoiceDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal taxAmount;
    @AuraEnabled
    public String billingAccountName;
    @AuraEnabled
    public Boolean invoiced;
    @AuraEnabled
    public Boolean exported;
    @AuraEnabled
    public Boolean locked;
    @AuraEnabled
    public Date systemIntegrationDate;
    @AuraEnabled
    public Date paymentClearingCompletedDate;
    @AuraEnabled
    public Integer lineCount;
  }

  // 業務データはクライアントキャッシュ禁止（画面表示は常に最新）
  @AuraEnabled
  public static List<InvoiceRowDto> getInvoices(Id contractHistoryId) {
    ContractPermissionUtil.assertManageInvoiceOps();
    Id serviceId = null;
    for (ContractHistory__c history : [
      SELECT ContractService__c
      FROM ContractHistory__c
      WHERE Id = :contractHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      serviceId = history.ContractService__c;
    }
    if (serviceId == null) {
      return new List<InvoiceRowDto>();
    }

    List<InvoiceRowDto> rows = new List<InvoiceRowDto>();
    for (Invoice__c invoice : [
      SELECT
        Id,
        Name,
        InvoiceDate__c,
        Amount__c,
        TaxAmount__c,
        BillingAccountSnapShot__r.Name,
        SystemIntegrationDate__c,
        PaymentClearingCompletedDate__c,
        (SELECT Id FROM InvoiceLines__r)
      FROM Invoice__c
      WHERE ContractService__c = :serviceId
      WITH SYSTEM_MODE
      ORDER BY InvoiceDate__c ASC NULLS LAST, CreatedDate ASC
    ]) {
      InvoiceRowDto row = new InvoiceRowDto();
      row.id = invoice.Id;
      row.name = invoice.Name;
      row.invoiceDate = invoice.InvoiceDate__c;
      row.amount = invoice.Amount__c;
      row.taxAmount = invoice.TaxAmount__c;
      row.billingAccountName = invoice.BillingAccountSnapShot__r == null
        ? null
        : invoice.BillingAccountSnapShot__r.Name;
      row.systemIntegrationDate = invoice.SystemIntegrationDate__c;
      row.paymentClearingCompletedDate = invoice.PaymentClearingCompletedDate__c;
      row.invoiced = invoice.SystemIntegrationDate__c != null;
      row.exported = invoice.PaymentClearingCompletedDate__c != null;
      row.locked = InvoiceLockUtil.isLocked(invoice);
      row.lineCount = invoice.InvoiceLines__r == null
        ? 0
        : invoice.InvoiceLines__r.size();
      rows.add(row);
    }
    return rows;
  }

  @AuraEnabled
  public static Integer markInvoiced(
    List<Id> invoiceIds,
    Date integrationDate
  ) {
    ContractPermissionUtil.assertManageInvoiceOps();
    return applyLockDates(invoiceIds, integrationDate, null, true);
  }

  @AuraEnabled
  public static Integer markExported(List<Id> invoiceIds, Date clearingDate) {
    ContractPermissionUtil.assertManageInvoiceOps();
    return applyLockDates(invoiceIds, null, clearingDate, false);
  }

  @AuraEnabled
  public static Integer clearExportDate(List<Id> invoiceIds) {
    ContractPermissionUtil.assertManageInvoiceOps();
    if (invoiceIds == null || invoiceIds.isEmpty()) {
      return 0;
    }
    List<Invoice__c> invoices = [
      SELECT Id, SystemIntegrationDate__c, PaymentClearingCompletedDate__c
      FROM Invoice__c
      WHERE Id IN :invoiceIds
      WITH SYSTEM_MODE
    ];
    List<Invoice__c> updates = new List<Invoice__c>();
    Boolean bypassIntegrity = ContractPermissionUtil.canBypassIntegrityGuards();
    for (Invoice__c invoice : invoices) {
      if (InvoiceLockUtil.isInvoiced(invoice) && !bypassIntegrity) {
        throw toAuraHandled(CLEAR_EXPORT_WHEN_INVOICED_MESSAGE);
      }
      // 消込額は手動前提のため触らない（消込日のみクリア）
      if (invoice.PaymentClearingCompletedDate__c != null) {
        invoice.PaymentClearingCompletedDate__c = null;
        updates.add(invoice);
      }
    }
    if (updates.isEmpty()) {
      return 0;
    }
    SystemContextAccess.updateRecords(updates);
    return updates.size();
  }

  private static Integer applyLockDates(
    List<Id> invoiceIds,
    Date integrationDate,
    Date clearingDate,
    Boolean forInvoiced
  ) {
    if (invoiceIds == null || invoiceIds.isEmpty()) {
      return 0;
    }
    Date value = forInvoiced
      ? (integrationDate == null ? Date.today() : integrationDate)
      : (clearingDate == null ? Date.today() : clearingDate);
    List<Invoice__c> invoices = [
      SELECT Id, SystemIntegrationDate__c, PaymentClearingCompletedDate__c
      FROM Invoice__c
      WHERE Id IN :invoiceIds
      WITH SYSTEM_MODE
    ];
    List<Invoice__c> updates = new List<Invoice__c>();
    for (Invoice__c invoice : invoices) {
      if (forInvoiced) {
        invoice.SystemIntegrationDate__c = value;
      } else {
        invoice.PaymentClearingCompletedDate__c = value;
      }
      updates.add(invoice);
    }
    if (updates.isEmpty()) {
      return 0;
    }
    // 未ロック→ロック付与はトリガ許可。更新は通常経路で可。
    SystemContextAccess.updateRecords(updates);
    return updates.size();
  }

  private static AuraHandledException toAuraHandled(String message) {
    String resolved = String.isNotBlank(message)
      ? message
      : '処理中にエラーが発生しました。';
    AuraHandledException ex = new AuraHandledException(resolved);
    ex.setMessage(resolved);
    return ex;
  }
}
