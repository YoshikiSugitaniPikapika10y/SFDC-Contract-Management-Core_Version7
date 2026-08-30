/**
 * 契約サービスを編集する画面の入口。
 */
public without sharing class ContractServiceEditController {
  public class ContextDto {
    @AuraEnabled
    public Id recordId;

    @AuraEnabled
    public String name;

    @AuraEnabled
    public Id billingAccountId;

    @AuraEnabled
    public String billingAccountName;

    /** 仕様: Core 第3.4.1節。請求アカウント候補の絞り込み用。 */
    @AuraEnabled
    public Id accountId;

    @AuraEnabled
    public List<BillingAccountOptionDto> relatedBillingAccounts;

    @AuraEnabled
    public Decimal taxPercent;

    @AuraEnabled
    public String customerMemo;

    @AuraEnabled
    public Map<String, Object> customFields;

    @AuraEnabled
    public String lastModifiedToken;
  }

  public class SaveResult {
    @AuraEnabled
    public Id recordId;

    @AuraEnabled
    public String businessOperationKey;
  }

  public class BillingAccountOptionDto {
    @AuraEnabled
    public Id id;

    @AuraEnabled
    public String name;
  }

  /** 仕様: Core 第3.4.1節、第4.3.12節、共通基盤 第3.8節・第10.4節。保存入口は 08。 */
  @AuraEnabled
  public static ContextDto getContext(Id recordId) {
    ContractPermissionUtil.assertEditService();
    if (recordId == null) {
      throw handled('契約サービスが指定されていません。');
    }
    ContractService__c service;
    try {
      SObject loaded = EstimateQueryService.loadRecordWithWizardFields(
        recordId,
        ContractService__c.SObjectType,
        ContractWizardFieldService.WizardTarget.ContractService,
        new List<String>{
          'Id',
          'Name',
          'Account__c',
          'BiilingAcccount__c',
          'BiilingAcccount__r.Name',
          'TaxPercent__c',
          'CustomerMemo__c',
          'LastModifiedDate'
        }
      );
      service = loaded == null ? null : (ContractService__c) loaded;
    } catch (ContractWizardFieldService.WizardFieldConfigException ex) {
      throw handled(ex.getMessage());
    }
    if (service == null) {
      throw handled('契約サービスが見つかりません。');
    }
    ContextDto dto = new ContextDto();
    dto.recordId = service.Id;
    dto.name = service.Name;
    dto.accountId = service.Account__c;
    dto.billingAccountId = service.BiilingAcccount__c;
    dto.billingAccountName = service.BiilingAcccount__r == null
      ? null
      : service.BiilingAcccount__r.Name;
    dto.relatedBillingAccounts = loadRelatedBillingAccounts(service.Account__c);
    dto.taxPercent = TaxCalculationUtil.fromPercentFieldStorage(
      service.TaxPercent__c
    );
    dto.customerMemo = service.CustomerMemo__c;
    dto.customFields = ContractWizardFieldService.extractCustomFields(
      service,
      ContractWizardFieldService.WizardTarget.ContractService
    );
    dto.lastModifiedToken = ContractOptimisticLockUtil.toToken(
      service.LastModifiedDate
    );
    return dto;
  }

  /** 仕様: Core 第3.4.1節、第4.3.12節、共通基盤 第10.4節。キー発行は 08。 */
  @AuraEnabled
  public static String issueContractServiceOperationKey() {
    ContractPermissionUtil.assertEditService();
    return AccountingCauseLockService.issueOperationKey();
  }

  public static SaveResult save(
    Id recordId,
    String name,
    Id billingAccountId,
    Decimal taxPercent,
    String customerMemo,
    String customFieldsJson
  ) {
    return save(
      recordId,
      name,
      billingAccountId,
      taxPercent,
      customerMemo,
      customFieldsJson,
      null,
      null
    );
  }

  /** 仕様: Core 第3.4.1節、第4.3.12節、共通基盤 第3.8節・第10.4節。保存は 08。 */
  @AuraEnabled
  public static SaveResult save(
    Id recordId,
    String name,
    Id billingAccountId,
    Decimal taxPercent,
    String customerMemo,
    String customFieldsJson,
    String expectedLastModifiedToken,
    String businessOperationKey
  ) {
    ContractPermissionUtil.assertEditService();
    if (recordId == null) {
      throw handled('契約サービスが指定されていません。');
    }
    if (String.isBlank(name)) {
      throw handled('名前を入力してください。');
    }
    if (billingAccountId == null) {
      throw handled('請求アカウントを入力してください。');
    }
    if (taxPercent == null) {
      throw handled('税率を入力してください。');
    }
    Decimal displayPercent;
    try {
      displayPercent = TaxCalculationUtil.resolveTaxPercent(taxPercent);
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      throw handled(ex.getMessage());
    }
    try {
      ContractWizardFieldService.validateActiveDefinitions();
    } catch (ContractWizardFieldService.WizardFieldConfigException ex) {
      throw handled(ex.getMessage());
    }

    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      businessOperationKey
    );
    ContractService__c current;
    try {
      current = AccountingCauseLockService.lockService(recordId);
    } catch (AccountingCauseLockService.LockException ex) {
      throw handled(ex.getMessage());
    }
    if (current.BusinessOperationKey__c == operationKey) {
      SaveResult existing = new SaveResult();
      existing.recordId = current.Id;
      existing.businessOperationKey = operationKey;
      ContractOperationLogService.write(
        'EditService',
        operationKey,
        'ContractService__c',
        String.valueOf(current.Id)
      );
      return existing;
    }
    ContractOptimisticLockUtil.assertRequiredUnchanged(
      current.LastModifiedDate,
      expectedLastModifiedToken,
      '契約サービス'
    );
    List<BillingAccount__c> accountRows = [
      SELECT Id, Account__c
      FROM BillingAccount__c
      WHERE Id = :billingAccountId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (accountRows.isEmpty()) {
      throw handled('請求アカウントが見つかりません。');
    }
    // 仕様: Core 第3.4.1節。他取引先の請求アカウントへの付け替えを許す。取引先一致は拒否しない。

    Map<String, Object> incoming = ContractWizardFieldService.parseCustomFieldsJson(
      customFieldsJson
    );
    Map<String, Object> toApply = new Map<String, Object>();
    for (
      String apiName : ContractWizardFieldService.getActiveFieldApiNames(
        ContractWizardFieldService.WizardTarget.ContractService
      )
    ) {
      toApply.put(
        apiName,
        incoming.containsKey(apiName) ? incoming.get(apiName) : null
      );
    }
    String requiredError = ContractWizardFieldService.validateRequiredCustomFields(
      ContractWizardFieldService.WizardTarget.ContractService,
      toApply,
      null,
      null
    );
    if (requiredError != null) {
      throw handled(requiredError);
    }

    ContractService__c toUpdate = new ContractService__c(
      Id = recordId,
      Name = name.trim(),
      BiilingAcccount__c = billingAccountId,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(displayPercent),
      CustomerMemo__c = customerMemo,
      BusinessOperationKey__c = operationKey
    );
    ContractWizardFieldService.applyCustomFields(
      toUpdate,
      toApply,
      ContractWizardFieldService.WizardTarget.ContractService
    );

    Boolean previousWrite = ContractServiceWriteGuard.isPackageWriteAllowed();
    ContractServiceWriteGuard.allowPackageWrite(true);
    try {
      SystemContextAccess.updateRecords(
        new List<ContractService__c>{ toUpdate }
      );
    } catch (Exception ex) {
      throw handled(
        String.isNotBlank(ex.getMessage())
          ? ex.getMessage()
          : '契約サービスを保存できませんでした。'
      );
    } finally {
      ContractServiceWriteGuard.allowPackageWrite(previousWrite);
    }
    SaveResult result = new SaveResult();
    result.recordId = recordId;
    result.businessOperationKey = operationKey;
    ContractOperationLogService.write(
      'EditService',
      operationKey,
      'ContractService__c',
      String.valueOf(recordId)
    );
    return result;
  }

  /** 仕様: Core 第3.4.1節・第4.3.3節 */
  private static List<BillingAccountOptionDto> loadRelatedBillingAccounts(
    Id accountId
  ) {
    List<BillingAccountOptionDto> options = new List<BillingAccountOptionDto>();
    if (accountId == null) {
      return options;
    }
    for (BillingAccount__c row : [
      SELECT Id, Name
      FROM BillingAccount__c
      WHERE Account__c = :accountId
      WITH SYSTEM_MODE
      ORDER BY Name ASC
      LIMIT 200
    ]) {
      BillingAccountOptionDto option = new BillingAccountOptionDto();
      option.id = row.Id;
      option.name = row.Name;
      options.add(option);
    }
    return options;
  }

  private static AuraHandledException handled(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
