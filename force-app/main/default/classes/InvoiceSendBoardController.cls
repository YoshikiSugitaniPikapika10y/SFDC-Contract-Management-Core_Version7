/**
 * 請求ボードの送付設定参照と確定入口。
 * 発行・送付の正は InvoiceBoardDocumentService。
 */
public without sharing class InvoiceSendBoardController {
  public static final Integer LIST_LIMIT = 500;

  public class SelectOptionDto {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
  }

  public class BoardContextDto {
    @AuraEnabled public Boolean canSend;
    @AuraEnabled public Boolean featureEnabled;
    /** 仕様: Core 第7.7.2節、Accounting 第3.1節 */
    @AuraEnabled public Boolean accountingEnabled;
    @AuraEnabled public List<SelectOptionDto> documentTemplateOptions;
    @AuraEnabled public List<SelectOptionDto> emailTemplateOptions;
    @AuraEnabled public String defaultDocumentTemplateKey;
    @AuraEnabled public String defaultEmailTemplateApiName;
    /** 仕様: Core 第11.3.1節・第7.10節 */
    @AuraEnabled public String companyBlockedReason;
    /** 仕様: Core 第11.3.2節・第7.10節 */
    @AuraEnabled public Boolean orgFromResolved;
    @AuraEnabled public Integer listLimit;
  }

  /** 仕様: Core 第11.3.1節、第11.3.2節、第7.10節 */
  @AuraEnabled(cacheable=true)
  public static BoardContextDto getBoardContext() {
    try {
      ContractDocumentSetting__c setting = loadOrganizationSetting();
      BoardContextDto result = new BoardContextDto();
      result.canSend = ContractPermissionUtil.has(
        ContractPermissionUtil.SEND_INVOICE
      );
      result.featureEnabled =
        ContractDocumentSettingService.requireSendMode('Invoice') !=
        ContractDocumentSettingService.MODE_UNUSED;
      result.accountingEnabled =
        GlAccountingPolicyService.requireOrgPolicy().AccountingEnabled__c ==
        true;
      result.documentTemplateOptions = new List<SelectOptionDto>();
      for (
        ContractDocumentTemplateService.TemplateDefinition definition :
        ContractDocumentTemplateService.getActiveTemplates(
          ContractDocumentTemplateService.TYPE_INVOICE
        )
      ) {
        result.documentTemplateOptions.add(
          option(definition.label, definition.templateKey)
        );
      }
      result.emailTemplateOptions = new List<SelectOptionDto>();
      for (
        ContractEmailTemplateService.EmailTemplateDefinition definition :
        ContractEmailTemplateService.getActiveTemplates(
          ContractEmailTemplateService.TYPE_INVOICE
        )
      ) {
        result.emailTemplateOptions.add(
          option(definition.label, definition.apiName)
        );
      }
      result.defaultDocumentTemplateKey =
        ContractDocumentTemplateService.initialSelectionKey(
          ContractDocumentTemplateService.TYPE_INVOICE
        );
      result.defaultEmailTemplateApiName =
        ContractEmailTemplateService.initialSelectionApiName(
          ContractEmailTemplateService.TYPE_INVOICE
        );
      result.orgFromResolved = String.isNotBlank(
        setting.InvoiceOrgWideEmailAddress__c
      );
      try {
        ContractDocumentSettingService.assertRequiredCompanyFields();
      } catch (ContractDocumentSettingService.SettingException ex) {
        result.companyBlockedReason = ContractDocumentSettingService.withDocumentSendHeading(
          ex.getMessage()
        );
      }
      result.listLimit = LIST_LIMIT;
      return result;
    } catch (Exception ex) {
      throw handled('請求送付画面の設定を取得できませんでした。', ex);
    }
  }

  public class ConfirmResultDto {
    @AuraEnabled public Integer confirmedCount;
    @AuraEnabled public String issueWarning;
    @AuraEnabled public String businessOperationKey;
  }

  public static ConfirmResultDto confirmInvoiceFromPreview(
    Id invoiceId,
    Date confirmationDate,
    String expectedToken
  ) {
    return confirmInvoiceFromPreview(
      invoiceId,
      confirmationDate,
      expectedToken,
      null
    );
  }

  public static ConfirmResultDto confirmInvoiceFromPreview(
    Id invoiceId,
    Date confirmationDate,
    String expectedToken,
    String businessOperationKey
  ) {
    return confirmInvoiceFromPreview(
      invoiceId,
      confirmationDate,
      expectedToken,
      businessOperationKey,
      null,
      false
    );
  }

  /** 仕様: Core 第7.7.3節、第7.9節、第7.9.7節、第7.10節、第11.3節。確定はPDFを付けない。 */
  @AuraEnabled
  public static ConfirmResultDto confirmInvoiceFromPreview(
    Id invoiceId,
    Date confirmationDate,
    String expectedToken,
    String businessOperationKey,
    Id contractHistoryId
  ) {
    return confirmInvoiceFromPreview(
      invoiceId,
      confirmationDate,
      expectedToken,
      businessOperationKey,
      contractHistoryId,
      true
    );
  }

  private static ConfirmResultDto confirmInvoiceFromPreview(
    Id invoiceId,
    Date confirmationDate,
    String expectedToken,
    String businessOperationKey,
    Id contractHistoryId,
    Boolean requireBoardScope
  ) {
    try {
      if (requireBoardScope == true) {
        InvoiceOpsController.assertInvoicesInScope(
          contractHistoryId,
          new List<Id>{ invoiceId }
        );
      }
      String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
        businessOperationKey
      );
      Invoice__c invoice = AccountingCauseLockService.lockInvoice(invoiceId);
      if (
        InvoiceTransactionStatusService.isConfirmed(invoice) &&
        invoice.BusinessOperationKey__c == operationKey
      ) {
        ConfirmResultDto existing = new ConfirmResultDto();
        existing.confirmedCount = 1;
        existing.businessOperationKey = operationKey;
        ContractOperationLogService.write(
          'ConfirmInvoice',
          operationKey,
          'Invoice__c',
          String.valueOf(invoice.Id)
        );
        return existing;
      }
      AccountingCauseLockService.assertInvoiceOperationUnchanged(
        invoiceId,
        expectedToken
      );
      if (!InvoiceTransactionStatusService.isDraft(invoice)) {
        throw handledMessage('未確定の請求のみ確定できます。');
      }
      Integer confirmedCount = InvoiceOpsController.markInvoiced(
        invoice.ContractHistory__c,
        new List<Id>{ invoice.Id },
        // 仕様: Core 第7.9節。画面の日付引数では書かない。確定処理が組織TZの操作日を書く。
        InvoiceTransactionStatusService.organizationToday(),
        operationKey
      );
      ConfirmResultDto result = new ConfirmResultDto();
      result.confirmedCount = confirmedCount;
      result.businessOperationKey = operationKey;
      ContractOperationLogService.write(
        'ConfirmInvoice',
        operationKey,
        'Invoice__c',
        String.valueOf(invoice.Id)
      );
      return result;
    } catch (AuraHandledException ex) {
      throw ex;
    } catch (Exception ex) {
      throw handled('請求を確定できませんでした。', ex);
    }
  }

  private static Invoice__c loadActionInvoice(Id invoiceId) {
    if (invoiceId == null) {
      throw handledMessage('請求IDが指定されていません。');
    }
    List<Invoice__c> records = [
      SELECT
        Id,
        ContractHistory__c,
        InvoiceTransactionStatus__c,
        LastModifiedDate
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (records.isEmpty()) {
      throw handledMessage('請求が見つかりません。');
    }
    return records[0];
  }

  private static void assertOpsActionAllowed(
    Invoice__c invoice,
    String expectedToken,
    Boolean enforcePermission
  ) {
    if (enforcePermission) {
      ContractPermissionUtil.assertSendInvoice();
    }
    ContractOptimisticLockUtil.assertRequiredUnchanged(
      invoice.LastModifiedDate,
      expectedToken,
      '請求'
    );
  }

  private static ContractDocumentSetting__c loadOrganizationSetting() {
    List<ContractDocumentSetting__c> settings = [
      SELECT
        InvoiceSendMode__c,
        InvoiceOrgWideEmailAddress__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return settings.isEmpty() ? new ContractDocumentSetting__c() : settings[0];
  }

  private static SelectOptionDto option(String label, String value) {
    SelectOptionDto item = new SelectOptionDto();
    item.label = label;
    item.value = value;
    return item;
  }

  private static AuraHandledException handled(
    String prefix,
    Exception source
  ) {
    String message = prefix;
    if (source != null && String.isNotBlank(source.getMessage())) {
      message += ' ' + source.getMessage();
    }
    return handledMessage(message);
  }

  private static AuraHandledException handledMessage(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
