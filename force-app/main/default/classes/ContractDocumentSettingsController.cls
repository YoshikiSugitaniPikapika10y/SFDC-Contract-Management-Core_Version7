/**
 * 契約帳票・送付設定の組織既定値と選択候補を提供する。
 */
public without sharing class ContractDocumentSettingsController {
  private static final String MANAGE_PERMISSION =
    ContractPermissionUtil.ORG_SETTINGS;

  public class SelectOptionDto {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
  }

  public class SettingsDto {
    @AuraEnabled public String estimateSendMode;
    @AuraEnabled public String invoiceSendMode;
    @AuraEnabled public String estimateOrgWideEmailAddress;
    @AuraEnabled public String invoiceOrgWideEmailAddress;
    @AuraEnabled public String companyName;
    @AuraEnabled public String address;
    @AuraEnabled public String invoiceRegistrationNumber;
    @AuraEnabled public String bankTransferInfo;
    @AuraEnabled public String documentFooter;
    @AuraEnabled public String privacyPolicyUrl;
    @AuraEnabled public Boolean accountingEnabled;
    @AuraEnabled public String revenueRecognitionBasis;
    @AuraEnabled public String taxRecognitionTiming;
    @AuraEnabled public String monthlyBucketMethod;
    @AuraEnabled public String monthlyRecognitionDatePosition;
    @AuraEnabled public String roundingTargetBucket;
    @AuraEnabled public Boolean policyFrozen;
    @AuraEnabled public String frozenAtLabel;
    @AuraEnabled public String frozenByName;
    @AuraEnabled public Decimal estimateValidMonths;
    @AuraEnabled public Decimal defaultMonthlyCycles;
    @AuraEnabled public Boolean renewOpportunityEnabled;
    @AuraEnabled public String taxRoundingMode;
    @AuraEnabled public String quantityUnitPriceRoundingMode;
    @AuraEnabled public String amountRoundingMode;
    @AuraEnabled public String taxLineAllocationMethod;
    @AuraEnabled public String allocationTieBreak;
    @AuraEnabled public String monthlyBucketAmountMethod;
    @AuraEnabled public String taxScheduleAllocationMethod;
    @AuraEnabled public String paymentLineAllocationMethod;
    @AuraEnabled public String accountBalanceAllocationMethod;
    @AuraEnabled public String documentGroupTaxAllocationMethod;
    @AuraEnabled public Boolean validationEnforce;
    @AuraEnabled public String lockExemptFieldApiNames;
    @AuraEnabled public String paymentLockExemptFieldApiNames;
    @AuraEnabled public String journalLockExemptFieldApiNames;
    /** 仕様: Core 第11.6節、第4.3.12節。開いたときの各レコード更新時刻。 */
    @AuraEnabled public String documentSettingToken;
    @AuraEnabled public String accountingPolicyToken;
    @AuraEnabled public String validationEnforceToken;
    @AuraEnabled public String lockExemptToken;
    @AuraEnabled public String paymentLockExemptToken;
    @AuraEnabled public String journalLockExemptToken;
    @AuraEnabled public String amountCalculationToken;
    @AuraEnabled public String businessOperationKey;
  }

  public class DiagnosisDto {
    @AuraEnabled public String heading;
    @AuraEnabled public String message;
    @AuraEnabled public String linkLabel;
    @AuraEnabled public String linkUrl;
  }

  public class PageDataDto {
    @AuraEnabled public SettingsDto settings;
    @AuraEnabled public List<SelectOptionDto> estimateDocumentTemplates;
    @AuraEnabled public List<SelectOptionDto> invoiceDocumentTemplates;
    @AuraEnabled public List<SelectOptionDto> estimateEmailTemplates;
    @AuraEnabled public List<SelectOptionDto> invoiceEmailTemplates;
    @AuraEnabled public List<SelectOptionDto> orgWideEmailAddresses;
    @AuraEnabled public List<DiagnosisDto> diagnoses;
  }

  /** 仕様: Core 第11.3節・第11.6節・第11.9節、Accounting 第3.1節 */
  @AuraEnabled
  public static PageDataDto getSettings() {
    assertCanManage();
    PageDataDto result = new PageDataDto();
    ContractDocumentSetting__c setting = loadOrganizationSetting();
    GlAccountingPolicy__c policy = loadPolicy();
    result.settings = toDto(setting, policy);
    try {
      applyAmountCalculationToDto(
        result.settings,
        AmountCalculationSettingService.requireOrgDefault()
      );
    } catch (AmountCalculationSettingService.SettingException ex) {
      // 仕様: Core 第11.6節。OrgDefault無しは診断。読込全体は止めない。
    }
    applyInputSystemToDto(result.settings);
    applyVersionTokens(result.settings, setting, policy);
    result.estimateDocumentTemplates = documentTemplateOptions(
      ContractDocumentTemplateService.TYPE_ESTIMATE
    );
    result.invoiceDocumentTemplates = documentTemplateOptions(
      ContractDocumentTemplateService.TYPE_INVOICE
    );
    result.estimateEmailTemplates = emailTemplateOptions(
      ContractEmailTemplateService.TYPE_ESTIMATE
    );
    result.invoiceEmailTemplates = emailTemplateOptions(
      ContractEmailTemplateService.TYPE_INVOICE
    );
    result.orgWideEmailAddresses = orgWideEmailAddressOptions();
    result.diagnoses = buildDiagnoses(setting, policy);
    return result;
  }

  /** 仕様: Core 第11.6節、第4.3.12節 */
  @AuraEnabled
  public static String issueOrgSettingsOperationKey() {
    assertCanManage();
    return AccountingCauseLockService.issueOperationKey();
  }

  /** 仕様: Core 第11.3節・第11.5節・第11.6節・第11.9節、日付仕様 第2.5節・第2.6節、Accounting 第3.1節 */
  @AuraEnabled
  public static SettingsDto saveSettings(SettingsDto input) {
    assertCanManage();
    if (input == null) {
      throw handled('保存する設定が指定されていません。');
    }
    String estimateMode = requireSendMode(input.estimateSendMode, '見積書');
    String invoiceMode = requireSendMode(input.invoiceSendMode, '請求書');
    Integer estimateValidMonths = requireEstimateValidMonths(input.estimateValidMonths);
    Integer defaultMonthlyCycles = requireDefaultCycles(input.defaultMonthlyCycles);
    String estimateOrgWideEmailAddress = normalize(
      input.estimateOrgWideEmailAddress
    );
    String invoiceOrgWideEmailAddress = normalize(
      input.invoiceOrgWideEmailAddress
    );
    try {
      List<ContractEmailTemplateService.EmailTemplateDefinition> estimateEmails =
        ContractEmailTemplateService.getActiveTemplates(
          ContractEmailTemplateService.TYPE_ESTIMATE
        );
      List<ContractEmailTemplateService.EmailTemplateDefinition> invoiceEmails =
        ContractEmailTemplateService.getActiveTemplates(
          ContractEmailTemplateService.TYPE_INVOICE
        );
      ContractDocumentSettingService.assertModeCatalogRequirements(
        estimateMode,
        estimateEmails.size(),
        estimateOrgWideEmailAddress,
        false
      );
      ContractDocumentSettingService.assertModeCatalogRequirements(
        invoiceMode,
        invoiceEmails.size(),
        invoiceOrgWideEmailAddress,
        true
      );
      ContractDocumentSettingService.assertRequiredCompanyFields(
        toCompanyCheckSetting(input, estimateMode, invoiceMode)
      );
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      throw handled(ex.getMessage());
    } catch (ContractDocumentSettingService.SettingException ex) {
      throw handled(ex.getMessage());
    }
    validateOrgWideEmailAddress(estimateOrgWideEmailAddress);
    validateOrgWideEmailAddress(invoiceOrgWideEmailAddress);

    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      input.businessOperationKey
    );
    LockedOrgSettings locked = lockWritableOrgSettings();
    if (
      locked.documentSetting != null &&
      locked.documentSetting.Id != null &&
      locked.documentSetting.BusinessOperationKey__c == operationKey
    ) {
      return buildSettingsDto(locked.documentSetting, locked.policy);
    }
    assertOrgSettingsVersions(input, locked);

    ContractDocumentSetting__c setting = locked.documentSetting == null
      ? new ContractDocumentSetting__c()
      : locked.documentSetting;
    setting.SetupOwnerId = UserInfo.getOrganizationId();
    setting.EstimateSendMode__c = estimateMode;
    setting.InvoiceSendMode__c = invoiceMode;
    // 仕様: Core 第11.3.2節。見積用と請求用を別アドレスで持つ。単一のOrgWideEmailAddress__cは持たない。
    setting.EstimateOrgWideEmailAddress__c = estimateOrgWideEmailAddress;
    setting.InvoiceOrgWideEmailAddress__c = invoiceOrgWideEmailAddress;
    setting.CompanyName__c = normalize(input.companyName);
    setting.Address__c = normalize(input.address);
    setting.InvoiceRegistrationNumber__c =
      normalize(input.invoiceRegistrationNumber);
    setting.BankTransferInfo__c = normalize(input.bankTransferInfo);
    setting.DocumentFooter__c = normalize(input.documentFooter);
    setting.PrivacyPolicyUrl__c = normalize(input.privacyPolicyUrl);
    setting.EstimateValidMonths__c = estimateValidMonths;
    setting.DefaultMonthlyCycles__c = defaultMonthlyCycles;
    setting.RenewOpportunityEnabled__c = input.renewOpportunityEnabled == true;
    Boolean previousOrgLog = ContractOperationLogService.orgSettingsWriteInProgress;
    ContractOperationLogService.orgSettingsWriteInProgress = true;
    try {
      upsert setting;
      saveAccountingPolicy(input, locked.policy);
      SettingsDto savedInner = toDto(setting, loadPolicy());
      overlayAndSaveAmountCalculation(savedInner, input);
      saveValidationEnforce(input, locked.validationEnforce);
      saveLockExemptFields(input, locked.lockExempt);
      savePaymentLockExemptFields(input, locked.paymentLockExempt);
      saveJournalLockExemptFields(input, locked.journalLockExempt);
      deleteNonOrgHierarchyRows();
      setting.BusinessOperationKey__c = operationKey;
      update setting;
      applyInputSystemToDto(savedInner);
      applyVersionTokens(savedInner, setting, loadPolicy());
      savedInner.businessOperationKey = operationKey;
      ContractOperationLogService.write(
        'SaveOrgSettings',
        operationKey,
        'ContractDocumentSetting__c',
        String.valueOf(setting.Id)
      );
      return savedInner;
    } finally {
      ContractOperationLogService.orgSettingsWriteInProgress = previousOrgLog;
    }
  }

  /** 仕様: Accounting 第3.1節・第11.3節、Core 第11.6節・第11.4.2節 */
  @AuraEnabled
  public static String validateFieldCopyDefinitions() {
    assertCanManage();
    try {
      FieldCopyDefinitionService.validateAllDefinitions();
    } catch (FieldCopyDefinitionService.FieldCopyException ex) {
      throw handled(ex.getMessage());
    }
    return 'コピー設定に不備はありません。';
  }

  private static void assertCanManage() {
    ContractPermissionUtil.assertOrgSettings();
  }

  private static ContractDocumentSetting__c loadOrganizationSetting() {
    List<ContractDocumentSetting__c> records = [
      SELECT
        Id, EstimateSendMode__c, InvoiceSendMode__c,
        EstimateOrgWideEmailAddress__c, InvoiceOrgWideEmailAddress__c,
        CompanyName__c, Address__c, InvoiceRegistrationNumber__c,
        BankTransferInfo__c, DocumentFooter__c, PrivacyPolicyUrl__c,
        EstimateValidMonths__c, DefaultMonthlyCycles__c, RenewOpportunityEnabled__c,
        BusinessOperationKey__c, LastModifiedDate
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return records.isEmpty() ? new ContractDocumentSetting__c() : records[0];
  }

  private static SettingsDto toDto(
    ContractDocumentSetting__c setting,
    GlAccountingPolicy__c policy
  ) {
    SettingsDto result = new SettingsDto();
    result.estimateSendMode = setting.EstimateSendMode__c;
    result.invoiceSendMode = setting.InvoiceSendMode__c;
    result.estimateOrgWideEmailAddress = setting.EstimateOrgWideEmailAddress__c;
    result.invoiceOrgWideEmailAddress = setting.InvoiceOrgWideEmailAddress__c;
    result.companyName = setting.CompanyName__c;
    result.address = setting.Address__c;
    result.invoiceRegistrationNumber = setting.InvoiceRegistrationNumber__c;
    result.bankTransferInfo = setting.BankTransferInfo__c;
    result.documentFooter = setting.DocumentFooter__c;
    result.privacyPolicyUrl = setting.PrivacyPolicyUrl__c;
    result.estimateValidMonths = setting.EstimateValidMonths__c;
    result.defaultMonthlyCycles = setting.DefaultMonthlyCycles__c;
    result.renewOpportunityEnabled = setting.RenewOpportunityEnabled__c == true;
    applyPolicyToDto(result, policy);
    return result;
  }

  /** 仕様: Core 第11.9節 */
  private static void applyAmountCalculationToDto(
    SettingsDto result,
    GlAccountingSetting__mdt setting
  ) {
    if (setting == null) {
      return;
    }
    result.taxRoundingMode = setting.TaxRoundingMode__c;
    result.quantityUnitPriceRoundingMode =
      setting.QuantityUnitPriceRoundingMode__c;
    result.amountRoundingMode = setting.AmountRoundingMode__c;
    result.taxLineAllocationMethod = setting.TaxLineAllocationMethod__c;
    result.allocationTieBreak = setting.AllocationTieBreak__c;
    result.monthlyBucketAmountMethod = setting.MonthlyBucketAmountMethod__c;
    result.taxScheduleAllocationMethod = setting.TaxScheduleAllocationMethod__c;
    result.paymentLineAllocationMethod = setting.PaymentLineAllocationMethod__c;
    result.accountBalanceAllocationMethod =
      setting.AccountBalanceAllocationMethod__c;
    result.documentGroupTaxAllocationMethod =
      setting.DocumentGroupTaxAllocationMethod__c;
  }

  private static GlAccountingSetting__mdt requireAmountCalculation() {
    try {
      return AmountCalculationSettingService.requireOrgDefault();
    } catch (AmountCalculationSettingService.SettingException ex) {
      throw handled(ex.getMessage());
    }
  }

  /** 仕様: Core 第11.6節・第11.9節、第1.1.10節 */
  private static void overlayAndSaveAmountCalculation(
    SettingsDto dto,
    SettingsDto input
  ) {
    GlAccountingSetting__mdt current;
    try {
      current = AmountCalculationSettingService.requireOrgDefault();
    } catch (AmountCalculationSettingService.SettingException ex) {
      return;
    }
    dto.taxRoundingMode = requireAmountCalcValue(
      input.taxRoundingMode,
      current.TaxRoundingMode__c,
      new Set<String>{
        AmountCalculationSettingService.TAX_ROUND_DOWN,
        AmountCalculationSettingService.TAX_ROUND_HALF_UP,
        AmountCalculationSettingService.TAX_ROUND_UP
      },
      '税額丸め'
    );
    dto.quantityUnitPriceRoundingMode = requireAmountCalcValue(
      input.quantityUnitPriceRoundingMode,
      current.QuantityUnitPriceRoundingMode__c,
      new Set<String>{ AmountCalculationSettingService.QUANTITY_HALF_UP_2 },
      '数量・単価の丸め'
    );
    dto.amountRoundingMode = requireAmountCalcValue(
      input.amountRoundingMode,
      current.AmountRoundingMode__c,
      new Set<String>{ AmountCalculationSettingService.AMOUNT_HALF_UP_0 },
      '税抜金額の丸め'
    );
    dto.taxLineAllocationMethod = requireAmountCalcValue(
      input.taxLineAllocationMethod,
      current.TaxLineAllocationMethod__c,
      new Set<String>{ AmountCalculationSettingService.TAX_LINE_SIGNED_REMAINDER },
      'ヘッダ税の明細配分'
    );
    dto.allocationTieBreak = requireAmountCalcValue(
      input.allocationTieBreak,
      current.AllocationTieBreak__c,
      new Set<String>{ AmountCalculationSettingService.TIE_BREAK_LINE_ORDER },
      '同率の決定順'
    );
    dto.monthlyBucketAmountMethod = requireAmountCalcValue(
      input.monthlyBucketAmountMethod,
      current.MonthlyBucketAmountMethod__c,
      new Set<String>{ AmountCalculationSettingService.MONTHLY_EQUAL_SPLIT },
      '月次バケットの金額'
    );
    dto.taxScheduleAllocationMethod = requireAmountCalcValue(
      input.taxScheduleAllocationMethod,
      current.TaxScheduleAllocationMethod__c,
      new Set<String>{ AmountCalculationSettingService.TAX_SCHEDULE_SIGNED_RATIO },
      '税のスケジュール配分'
    );
    dto.paymentLineAllocationMethod = requireAmountCalcValue(
      input.paymentLineAllocationMethod,
      current.PaymentLineAllocationMethod__c,
      new Set<String>{ AmountCalculationSettingService.PAYMENT_OPEN_RATIO },
      '一部入返金の初期配分'
    );
    dto.accountBalanceAllocationMethod = requireAmountCalcValue(
      input.accountBalanceAllocationMethod,
      current.AccountBalanceAllocationMethod__c,
      new Set<String>{ AmountCalculationSettingService.ACCOUNT_SAME_RATE },
      '複数実勘定への配分'
    );
    dto.documentGroupTaxAllocationMethod = requireAmountCalcValue(
      input.documentGroupTaxAllocationMethod,
      current.DocumentGroupTaxAllocationMethod__c,
      new Set<String>{ AmountCalculationSettingService.DOCUMENT_EXCL_RATIO },
      '帳票グループ税込'
    );
    deployOrgDefaultIfChanged(current, dto);
  }

  private static String requireAmountCalcValue(
    String raw,
    String currentValue,
    Set<String> allowed,
    String label
  ) {
    String value = normalize(raw);
    if (value == null) {
      return currentValue;
    }
    if (!allowed.contains(value)) {
      throw handled(label + 'の設定が無い、空、または不正です。');
    }
    return value;
  }

  /**
   * CMDTはApex DMLできない。テストではMetadataデプロイが使えない。
   */
  private static void deployOrgDefaultIfChanged(
    GlAccountingSetting__mdt current,
    SettingsDto resolved
  ) {
    if (
      resolved.taxRoundingMode == current.TaxRoundingMode__c &&
      resolved.quantityUnitPriceRoundingMode ==
        current.QuantityUnitPriceRoundingMode__c &&
      resolved.amountRoundingMode == current.AmountRoundingMode__c &&
      resolved.taxLineAllocationMethod == current.TaxLineAllocationMethod__c &&
      resolved.allocationTieBreak == current.AllocationTieBreak__c &&
      resolved.monthlyBucketAmountMethod ==
        current.MonthlyBucketAmountMethod__c &&
      resolved.taxScheduleAllocationMethod ==
        current.TaxScheduleAllocationMethod__c &&
      resolved.paymentLineAllocationMethod ==
        current.PaymentLineAllocationMethod__c &&
      resolved.accountBalanceAllocationMethod ==
        current.AccountBalanceAllocationMethod__c &&
      resolved.documentGroupTaxAllocationMethod ==
        current.DocumentGroupTaxAllocationMethod__c
    ) {
      return;
    }
    if (Test.isRunningTest()) {
      return;
    }
    Metadata.CustomMetadata record = new Metadata.CustomMetadata();
    record.fullName = 'GlAccountingSetting.OrgDefault';
    record.label = 'OrgDefault';
    addMetadataValue(record, 'TaxRoundingMode__c', resolved.taxRoundingMode);
    addMetadataValue(
      record,
      'QuantityUnitPriceRoundingMode__c',
      resolved.quantityUnitPriceRoundingMode
    );
    addMetadataValue(record, 'AmountRoundingMode__c', resolved.amountRoundingMode);
    addMetadataValue(
      record,
      'TaxLineAllocationMethod__c',
      resolved.taxLineAllocationMethod
    );
    addMetadataValue(record, 'AllocationTieBreak__c', resolved.allocationTieBreak);
    addMetadataValue(
      record,
      'MonthlyBucketAmountMethod__c',
      resolved.monthlyBucketAmountMethod
    );
    addMetadataValue(
      record,
      'TaxScheduleAllocationMethod__c',
      resolved.taxScheduleAllocationMethod
    );
    addMetadataValue(
      record,
      'PaymentLineAllocationMethod__c',
      resolved.paymentLineAllocationMethod
    );
    addMetadataValue(
      record,
      'AccountBalanceAllocationMethod__c',
      resolved.accountBalanceAllocationMethod
    );
    addMetadataValue(
      record,
      'DocumentGroupTaxAllocationMethod__c',
      resolved.documentGroupTaxAllocationMethod
    );
    Metadata.DeployContainer container = new Metadata.DeployContainer();
    container.addMetadata(record);
    Metadata.Operations.enqueueDeployment(container, null);
  }

  private static void addMetadataValue(
    Metadata.CustomMetadata record,
    String fieldName,
    String fieldValue
  ) {
    Metadata.CustomMetadataValue item = new Metadata.CustomMetadataValue();
    item.field = fieldName;
    item.value = fieldValue;
    record.values.add(item);
  }

  /** 仕様: Core 第11.6節 */
  private static void applyInputSystemToDto(SettingsDto result) {
    ContractValidationEnforce__c enforce =
      ContractValidationEnforce__c.getOrgDefaults();
    result.validationEnforce = enforce != null && enforce.Enforce__c == true;
    InvoiceLockExemptFields__c lockExempt =
      InvoiceLockExemptFields__c.getOrgDefaults();
    result.lockExemptFieldApiNames =
      lockExempt == null || lockExempt.Id == null
        ? null
        : lockExempt.FieldApiNames__c;
    InvoicePaymentLockExemptFields__c paymentLockExempt =
      InvoicePaymentLockExemptFields__c.getOrgDefaults();
    result.paymentLockExemptFieldApiNames =
      paymentLockExempt == null || paymentLockExempt.Id == null
        ? null
        : paymentLockExempt.FieldApiNames__c;
    GlJournalLockExemptFields__c journalLockExempt =
      GlJournalLockExemptFields__c.getOrgDefaults();
    result.journalLockExemptFieldApiNames =
      journalLockExempt == null || journalLockExempt.Id == null
        ? null
        : journalLockExempt.FieldApiNames__c;
  }

  private class LockedOrgSettings {
    ContractDocumentSetting__c documentSetting;
    GlAccountingPolicy__c policy;
    ContractValidationEnforce__c validationEnforce;
    InvoiceLockExemptFields__c lockExempt;
    InvoicePaymentLockExemptFields__c paymentLockExempt;
    GlJournalLockExemptFields__c journalLockExempt;
    Datetime amountCalculationModified;
  }

  /** 仕様: Core 第11.6節。この保存が書くカスタムオブジェクトとカスタム設定を行ロックする。 */
  private static LockedOrgSettings lockWritableOrgSettings() {
    LockedOrgSettings locked = new LockedOrgSettings();
    List<Id> lockOrder = new List<Id>();
    ContractDocumentSetting__c setting = loadOrganizationSetting();
    if (setting.Id != null) {
      lockOrder.add(setting.Id);
    }
    GlAccountingPolicy__c policy = loadPolicy();
    if (policy != null && policy.Id != null) {
      lockOrder.add(policy.Id);
    }
    ContractValidationEnforce__c enforce =
      ContractValidationEnforce__c.getOrgDefaults();
    if (enforce != null && enforce.Id != null) {
      lockOrder.add(enforce.Id);
    }
    InvoiceLockExemptFields__c lockExempt =
      InvoiceLockExemptFields__c.getOrgDefaults();
    if (lockExempt != null && lockExempt.Id != null) {
      lockOrder.add(lockExempt.Id);
    }
    InvoicePaymentLockExemptFields__c paymentLockExempt =
      InvoicePaymentLockExemptFields__c.getOrgDefaults();
    if (paymentLockExempt != null && paymentLockExempt.Id != null) {
      lockOrder.add(paymentLockExempt.Id);
    }
    GlJournalLockExemptFields__c journalLockExempt =
      GlJournalLockExemptFields__c.getOrgDefaults();
    if (journalLockExempt != null && journalLockExempt.Id != null) {
      lockOrder.add(journalLockExempt.Id);
    }
    lockOrder.sort();
    Map<Id, SObject> lockedById = new Map<Id, SObject>();
    String documentPrefix = ContractDocumentSetting__c.SObjectType.getDescribe()
      .getKeyPrefix();
    String policyPrefix = GlAccountingPolicy__c.SObjectType.getDescribe()
      .getKeyPrefix();
    String enforcePrefix = ContractValidationEnforce__c.SObjectType.getDescribe()
      .getKeyPrefix();
    String lockExemptPrefix = InvoiceLockExemptFields__c.SObjectType.getDescribe()
      .getKeyPrefix();
    String paymentLockExemptPrefix = InvoicePaymentLockExemptFields__c.SObjectType.getDescribe()
      .getKeyPrefix();
    String journalLockExemptPrefix = GlJournalLockExemptFields__c.SObjectType.getDescribe()
      .getKeyPrefix();
    for (Id recordId : lockOrder) {
      String prefix = String.valueOf(recordId).substring(0, 3);
      if (prefix == documentPrefix) {
        List<ContractDocumentSetting__c> rows = [
          SELECT
            Id, EstimateSendMode__c, InvoiceSendMode__c,
            EstimateOrgWideEmailAddress__c, InvoiceOrgWideEmailAddress__c,
            CompanyName__c, Address__c, InvoiceRegistrationNumber__c,
            BankTransferInfo__c, DocumentFooter__c, PrivacyPolicyUrl__c,
            EstimateValidMonths__c, DefaultMonthlyCycles__c,
            RenewOpportunityEnabled__c, BusinessOperationKey__c, LastModifiedDate
          FROM ContractDocumentSetting__c
          WHERE Id = :recordId
          WITH SYSTEM_MODE
          FOR UPDATE
        ];
        if (!rows.isEmpty()) {
          lockedById.put(recordId, rows[0]);
        }
      } else if (prefix == policyPrefix) {
        List<GlAccountingPolicy__c> rows = [
          SELECT
            Id, AccountingEnabled__c, RevenueRecognitionBasis__c,
            TaxRecognitionTiming__c, MonthlyBucketMethod__c,
            MonthlyRecognitionDatePosition__c, RoundingTargetBucket__c,
            FrozenAt__c, FrozenBy__c, FrozenBy__r.Name, LastModifiedDate
          FROM GlAccountingPolicy__c
          WHERE Id = :recordId
          WITH SYSTEM_MODE
          FOR UPDATE
        ];
        if (!rows.isEmpty()) {
          lockedById.put(recordId, rows[0]);
        }
      } else if (prefix == enforcePrefix) {
        List<ContractValidationEnforce__c> rows = [
          SELECT Id, Enforce__c, LastModifiedDate
          FROM ContractValidationEnforce__c
          WHERE Id = :recordId
          WITH SYSTEM_MODE
          FOR UPDATE
        ];
        if (!rows.isEmpty()) {
          lockedById.put(recordId, rows[0]);
        }
      } else if (prefix == lockExemptPrefix) {
        List<InvoiceLockExemptFields__c> rows = [
          SELECT Id, FieldApiNames__c, LastModifiedDate
          FROM InvoiceLockExemptFields__c
          WHERE Id = :recordId
          WITH SYSTEM_MODE
          FOR UPDATE
        ];
        if (!rows.isEmpty()) {
          lockedById.put(recordId, rows[0]);
        }
      } else if (prefix == paymentLockExemptPrefix) {
        List<InvoicePaymentLockExemptFields__c> rows = [
          SELECT Id, FieldApiNames__c, LastModifiedDate
          FROM InvoicePaymentLockExemptFields__c
          WHERE Id = :recordId
          WITH SYSTEM_MODE
          FOR UPDATE
        ];
        if (!rows.isEmpty()) {
          lockedById.put(recordId, rows[0]);
        }
      } else if (prefix == journalLockExemptPrefix) {
        List<GlJournalLockExemptFields__c> rows = [
          SELECT Id, FieldApiNames__c, LastModifiedDate
          FROM GlJournalLockExemptFields__c
          WHERE Id = :recordId
          WITH SYSTEM_MODE
          FOR UPDATE
        ];
        if (!rows.isEmpty()) {
          lockedById.put(recordId, rows[0]);
        }
      }
    }
    locked.documentSetting = setting.Id == null
      ? setting
      : (ContractDocumentSetting__c) lockedById.get(setting.Id);
    if (locked.documentSetting == null) {
      locked.documentSetting = setting;
    }
    locked.policy = policy == null || policy.Id == null
      ? policy
      : (GlAccountingPolicy__c) lockedById.get(policy.Id);
    if (locked.policy == null) {
      locked.policy = policy;
    }
    locked.validationEnforce = enforce == null || enforce.Id == null
      ? enforce
      : (ContractValidationEnforce__c) lockedById.get(enforce.Id);
    if (locked.validationEnforce == null) {
      locked.validationEnforce = enforce;
    }
    locked.lockExempt = lockExempt == null || lockExempt.Id == null
      ? lockExempt
      : (InvoiceLockExemptFields__c) lockedById.get(lockExempt.Id);
    if (locked.lockExempt == null) {
      locked.lockExempt = lockExempt;
    }
    locked.paymentLockExempt = paymentLockExempt == null ||
      paymentLockExempt.Id == null
      ? paymentLockExempt
      : (InvoicePaymentLockExemptFields__c) lockedById.get(paymentLockExempt.Id);
    if (locked.paymentLockExempt == null) {
      locked.paymentLockExempt = paymentLockExempt;
    }
    locked.journalLockExempt = journalLockExempt == null ||
      journalLockExempt.Id == null
      ? journalLockExempt
      : (GlJournalLockExemptFields__c) lockedById.get(journalLockExempt.Id);
    if (locked.journalLockExempt == null) {
      locked.journalLockExempt = journalLockExempt;
    }
    locked.amountCalculationModified = resolveAmountCalculationModified();
    return locked;
  }

  /** 仕様: Core 第11.6節。Custom Metadata は行ロックせず更新時刻の比較だけ。 */
  private static Datetime resolveAmountCalculationModified() {
    List<GlAccountingSetting__mdt> rows = [
      SELECT SystemModstamp
      FROM GlAccountingSetting__mdt
      WHERE DeveloperName = 'OrgDefault'
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].SystemModstamp;
  }

  /** 仕様: Core 第11.6節、第4.3.12節 */
  private static void applyVersionTokens(
    SettingsDto dto,
    ContractDocumentSetting__c setting,
    GlAccountingPolicy__c policy
  ) {
    dto.documentSettingToken = ContractOptimisticLockUtil.toToken(
      setting == null || setting.Id == null ? null : setting.LastModifiedDate
    );
    dto.accountingPolicyToken = ContractOptimisticLockUtil.toToken(
      policy == null ? null : policy.LastModifiedDate
    );
    ContractValidationEnforce__c enforce =
      ContractValidationEnforce__c.getOrgDefaults();
    dto.validationEnforceToken = ContractOptimisticLockUtil.toToken(
      enforce == null || enforce.Id == null ? null : enforce.LastModifiedDate
    );
    InvoiceLockExemptFields__c lockExempt =
      InvoiceLockExemptFields__c.getOrgDefaults();
    dto.lockExemptToken = ContractOptimisticLockUtil.toToken(
      lockExempt == null || lockExempt.Id == null
        ? null
        : lockExempt.LastModifiedDate
    );
    InvoicePaymentLockExemptFields__c paymentLockExempt =
      InvoicePaymentLockExemptFields__c.getOrgDefaults();
    dto.paymentLockExemptToken = ContractOptimisticLockUtil.toToken(
      paymentLockExempt == null || paymentLockExempt.Id == null
        ? null
        : paymentLockExempt.LastModifiedDate
    );
    GlJournalLockExemptFields__c journalLockExempt =
      GlJournalLockExemptFields__c.getOrgDefaults();
    dto.journalLockExemptToken = ContractOptimisticLockUtil.toToken(
      journalLockExempt == null || journalLockExempt.Id == null
        ? null
        : journalLockExempt.LastModifiedDate
    );
    dto.amountCalculationToken = ContractOptimisticLockUtil.toToken(
      resolveAmountCalculationModified()
    );
  }

  /** 仕様: Core 第11.6節、第4.3.12節。比較値未指定なら拒否する。 */
  private static void assertOrgSettingsVersions(
    SettingsDto input,
    LockedOrgSettings locked
  ) {
    assertOptionalRecordUnchanged(
      locked.documentSetting == null || locked.documentSetting.Id == null
        ? null
        : locked.documentSetting.LastModifiedDate,
      input.documentSettingToken,
      '組織設定'
    );
    assertOptionalRecordUnchanged(
      locked.policy == null ? null : locked.policy.LastModifiedDate,
      input.accountingPolicyToken,
      'Accounting方針'
    );
    assertOptionalRecordUnchanged(
      locked.validationEnforce == null || locked.validationEnforce.Id == null
        ? null
        : locked.validationEnforce.LastModifiedDate,
      input.validationEnforceToken,
      '入力強制'
    );
    assertOptionalRecordUnchanged(
      locked.lockExempt == null || locked.lockExempt.Id == null
        ? null
        : locked.lockExempt.LastModifiedDate,
      input.lockExemptToken,
      '請求ロック除外'
    );
    assertOptionalRecordUnchanged(
      locked.paymentLockExempt == null || locked.paymentLockExempt.Id == null
        ? null
        : locked.paymentLockExempt.LastModifiedDate,
      input.paymentLockExemptToken,
      '入出金ロック除外'
    );
    assertOptionalRecordUnchanged(
      locked.journalLockExempt == null || locked.journalLockExempt.Id == null
        ? null
        : locked.journalLockExempt.LastModifiedDate,
      input.journalLockExemptToken,
      '仕訳ロック除外'
    );
    assertOptionalRecordUnchanged(
      locked.amountCalculationModified,
      input.amountCalculationToken,
      '金額計算'
    );
  }

  private static void assertOptionalRecordUnchanged(
    Datetime actualLastModified,
    String expectedToken,
    String entityLabel
  ) {
    if (String.isBlank(expectedToken) && actualLastModified == null) {
      return;
    }
    try {
      ContractOptimisticLockUtil.assertRequiredUnchanged(
        actualLastModified,
        expectedToken,
        entityLabel
      );
    } catch (AuraHandledException ex) {
      throw handled(ex.getMessage());
    }
  }

  private static SettingsDto buildSettingsDto(
    ContractDocumentSetting__c setting,
    GlAccountingPolicy__c policy
  ) {
    GlAccountingPolicy__c resolvedPolicy = policy == null
      ? loadPolicy()
      : policy;
    SettingsDto saved = toDto(setting, resolvedPolicy);
    try {
      applyAmountCalculationToDto(
        saved,
        AmountCalculationSettingService.requireOrgDefault()
      );
    } catch (AmountCalculationSettingService.SettingException ex) {
      // 仕様: Core 第11.6節。OrgDefault無しは診断。
    }
    applyInputSystemToDto(saved);
    applyVersionTokens(saved, setting, resolvedPolicy);
    saved.businessOperationKey = setting.BusinessOperationKey__c;
    return saved;
  }

  /** 仕様: Core 第11.6節。組織既定だけを読み書きし、ユーザー／プロファイル行を残さない。 */
  private static void saveValidationEnforce(
    SettingsDto input,
    ContractValidationEnforce__c locked
  ) {
    if (input.validationEnforce == null) {
      return;
    }
    ContractValidationEnforce__c row = locked;
    if (row == null || row.Id == null) {
      row = new ContractValidationEnforce__c();
    }
    Id organizationId = UserInfo.getOrganizationId();
    row.SetupOwnerId = organizationId;
    row.Enforce__c = input.validationEnforce;
    upsert row;
  }

  /** 仕様: Core 第11.6節。ユーザー単位の階層切替は持たない。保存時に Org 以外を削除する。 */
  private static void deleteNonOrgHierarchyRows() {
    Id organizationId = UserInfo.getOrganizationId();
    List<ContractDocumentSetting__c> documentOverrides = [
      SELECT Id
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId != :organizationId
      WITH SYSTEM_MODE
    ];
    if (!documentOverrides.isEmpty()) {
      delete documentOverrides;
    }
    List<ContractValidationEnforce__c> enforceOverrides = [
      SELECT Id
      FROM ContractValidationEnforce__c
      WHERE SetupOwnerId != :organizationId
      WITH SYSTEM_MODE
    ];
    if (!enforceOverrides.isEmpty()) {
      delete enforceOverrides;
    }
    List<InvoiceLockExemptFields__c> invoiceLockOverrides = [
      SELECT Id
      FROM InvoiceLockExemptFields__c
      WHERE SetupOwnerId != :organizationId
      WITH SYSTEM_MODE
    ];
    if (!invoiceLockOverrides.isEmpty()) {
      delete invoiceLockOverrides;
    }
    List<InvoicePaymentLockExemptFields__c> paymentLockOverrides = [
      SELECT Id
      FROM InvoicePaymentLockExemptFields__c
      WHERE SetupOwnerId != :organizationId
      WITH SYSTEM_MODE
    ];
    if (!paymentLockOverrides.isEmpty()) {
      delete paymentLockOverrides;
    }
    List<GlJournalLockExemptFields__c> journalLockOverrides = [
      SELECT Id
      FROM GlJournalLockExemptFields__c
      WHERE SetupOwnerId != :organizationId
      WITH SYSTEM_MODE
    ];
    if (!journalLockOverrides.isEmpty()) {
      delete journalLockOverrides;
    }
  }

  /** 仕様: Core 第11.6節、第1.1.10節。空でもシードへ落とさない。 */
  private static void saveLockExemptFields(
    SettingsDto input,
    InvoiceLockExemptFields__c locked
  ) {
    if (input.lockExemptFieldApiNames == null) {
      return;
    }
    InvoiceLockExemptFields__c row = locked;
    if (row == null || row.Id == null) {
      row = new InvoiceLockExemptFields__c();
    }
    row.SetupOwnerId = UserInfo.getOrganizationId();
    row.FieldApiNames__c = input.lockExemptFieldApiNames.trim();
    upsert row;
  }

  /** 仕様: Core 第11.6節、第1.1.10節。空でもシードへ落とさない。定義から自動では書かない。 */
  private static void savePaymentLockExemptFields(
    SettingsDto input,
    InvoicePaymentLockExemptFields__c locked
  ) {
    if (input.paymentLockExemptFieldApiNames == null) {
      return;
    }
    InvoicePaymentLockExemptFields__c row = locked;
    if (row == null || row.Id == null) {
      row = new InvoicePaymentLockExemptFields__c();
    }
    row.SetupOwnerId = UserInfo.getOrganizationId();
    row.FieldApiNames__c = input.paymentLockExemptFieldApiNames.trim();
    upsert row;
  }

  /** 仕様: Core 第11.6節、第1.1.10節。空でもシードへ落とさない。定義から自動では書かない。 */
  private static void saveJournalLockExemptFields(
    SettingsDto input,
    GlJournalLockExemptFields__c locked
  ) {
    if (input.journalLockExemptFieldApiNames == null) {
      return;
    }
    GlJournalLockExemptFields__c row = locked;
    if (row == null || row.Id == null) {
      row = new GlJournalLockExemptFields__c();
    }
    row.SetupOwnerId = UserInfo.getOrganizationId();
    row.FieldApiNames__c = input.journalLockExemptFieldApiNames.trim();
    upsert row;
  }

  /** 仕様: Accounting 第3.1節、Core 第1.1.10節・第11.6節。0件はOFFと埋めない。 */
  private static void applyPolicyToDto(
    SettingsDto result,
    GlAccountingPolicy__c policy
  ) {
    if (policy == null) {
      return;
    }
    result.accountingEnabled = policy.AccountingEnabled__c == true;
    result.revenueRecognitionBasis = policy.RevenueRecognitionBasis__c;
    result.taxRecognitionTiming = policy.TaxRecognitionTiming__c;
    result.monthlyBucketMethod = policy.MonthlyBucketMethod__c;
    result.monthlyRecognitionDatePosition =
      policy.MonthlyRecognitionDatePosition__c;
    result.roundingTargetBucket = policy.RoundingTargetBucket__c;
    result.policyFrozen = GlAccountingPolicyService.isPolicyLocked(policy);
    result.frozenAtLabel = policy.FrozenAt__c == null
      ? null
      : policy.FrozenAt__c.format();
    result.frozenByName = policy.FrozenBy__r == null
      ? null
      : policy.FrozenBy__r.Name;
  }

  private static GlAccountingPolicy__c loadPolicy() {
    List<GlAccountingPolicy__c> rows = [
      SELECT
        Id,
        AccountingEnabled__c,
        RevenueRecognitionBasis__c,
        TaxRecognitionTiming__c,
        MonthlyBucketMethod__c,
        MonthlyRecognitionDatePosition__c,
        RoundingTargetBucket__c,
        FrozenAt__c,
        FrozenBy__c,
        FrozenBy__r.Name,
        LastModifiedDate
      FROM GlAccountingPolicy__c
      WITH SYSTEM_MODE
      LIMIT 2
    ];
    if (rows.size() > 1) {
      throw handled('Accounting会計方針は組織内1件だけです。');
    }
    return rows.isEmpty() ? null : rows[0];
  }

  /** 仕様: Accounting 第3.1節。固定後および確定／取消済み請求があるときは画面から書き換えない。Core 第11.6節・第11.8節。 */
  private static void saveAccountingPolicy(
    SettingsDto input,
    GlAccountingPolicy__c locked
  ) {
    GlAccountingPolicy__c current = locked;
    if (GlAccountingPolicyService.isPolicyLocked(current)) {
      return;
    }
    if (
      current == null &&
      String.isBlank(input.revenueRecognitionBasis) &&
      String.isBlank(input.taxRecognitionTiming) &&
      String.isBlank(input.monthlyBucketMethod) &&
      String.isBlank(input.monthlyRecognitionDatePosition) &&
      String.isBlank(input.roundingTargetBucket)
    ) {
      return;
    }
    String previousMonthlyMethod = current == null
      ? null
      : current.MonthlyBucketMethod__c;
    GlAccountingPolicy__c policy = current == null
      ? GlAccountingPolicyService.newOrgDefault()
      : current;
    if (input.accountingEnabled != null) {
      policy.AccountingEnabled__c = input.accountingEnabled;
    }
    policy.RevenueRecognitionBasis__c = requirePolicyPicklist(
      input.revenueRecognitionBasis,
      policy.RevenueRecognitionBasis__c,
      new Set<String>{ 'BillingBasis', 'CashBasis' },
      '売上計上方針'
    );
    policy.TaxRecognitionTiming__c = requirePolicyPicklist(
      input.taxRecognitionTiming,
      policy.TaxRecognitionTiming__c,
      new Set<String>{ 'AtInvoice', 'AtRecognition' },
      '税認識方針'
    );
    policy.MonthlyBucketMethod__c = requirePolicyPicklist(
      input.monthlyBucketMethod,
      policy.MonthlyBucketMethod__c,
      new Set<String>{ 'Auto', 'ContractAnchor', 'CalendarMonth' },
      '月次バケットの刻み方'
    );
    policy.MonthlyRecognitionDatePosition__c = requirePolicyPicklist(
      input.monthlyRecognitionDatePosition,
      policy.MonthlyRecognitionDatePosition__c,
      new Set<String>{ 'BucketStart', 'BucketEnd', 'MonthEnd' },
      '月次計上の計上日位置'
    );
    policy.RoundingTargetBucket__c = requirePolicyPicklist(
      input.roundingTargetBucket,
      policy.RoundingTargetBucket__c,
      new Set<String>{ 'Last', 'First' },
      '端数の寄せ先'
    );
    // 仕様: Accounting 第5.7節。保存時に許可集合を検証する。
    GlAccountingPolicyService.deriveAllowedPatternKeys(policy);
    upsert policy;
    // 仕様: Accounting 第3.2節。月次方式の変更は未固定のときだけ起き、組織内の請求明細を書き直す。
    if (previousMonthlyMethod != policy.MonthlyBucketMethod__c) {
      GlAccountingPolicyService.rewriteRecognitionBucketCounts();
    }
  }

  private static String requirePolicyPicklist(
    String raw,
    String currentValue,
    Set<String> allowed,
    String label
  ) {
    String value = normalize(raw);
    if (value == null) {
      return currentValue;
    }
    if (!allowed.contains(value)) {
      throw handled(label + 'が不正です。');
    }
    return value;
  }

  private static List<SelectOptionDto> documentTemplateOptions(String typeName) {
    List<SelectOptionDto> result = new List<SelectOptionDto>();
    for (
      ContractDocumentTemplateService.TemplateDefinition definition :
      ContractDocumentTemplateService.getActiveTemplates(typeName)
    ) {
      result.add(option(definition.label, definition.templateKey));
    }
    return result;
  }

  /** 仕様: Core 第11.3.2節 */
  private static List<SelectOptionDto> emailTemplateOptions(String documentType) {
    List<SelectOptionDto> result = new List<SelectOptionDto>();
    try {
      for (
        ContractEmailTemplateService.EmailTemplateDefinition definition :
        ContractEmailTemplateService.getActiveTemplates(documentType)
      ) {
        result.add(option(definition.label, definition.apiName));
      }
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      return result;
    }
    return result;
  }

  private static List<SelectOptionDto> orgWideEmailAddressOptions() {
    List<SelectOptionDto> result = new List<SelectOptionDto>();
    for (OrgWideEmailAddress record : [
      SELECT Id, Address, DisplayName
      FROM OrgWideEmailAddress
      WITH SYSTEM_MODE
      ORDER BY DisplayName, Address
    ]) {
      String label = String.isBlank(record.DisplayName)
        ? record.Address
        : record.DisplayName;
      result.add(option(label, record.Address));
    }
    return result;
  }

  private static String requireSendMode(String raw, String label) {
    String mode = normalize(raw);
    if (
      mode != ContractDocumentSettingService.MODE_UNUSED &&
      mode != ContractDocumentSettingService.MODE_PDF_ONLY &&
      mode != ContractDocumentSettingService.MODE_PDF_AND_EMAIL
    ) {
      throw handled(label + 'の3択が無い、空、または不正です。');
    }
    return mode;
  }

  /** 仕様: Core 第11.6節、日付仕様 第2.6節 */
  private static Integer requireEstimateValidMonths(Decimal raw) {
    if (raw == null || raw != raw.intValue() || raw < 1 || raw > 12) {
      throw handled(
        ContractDocumentSettingService.INVALID_ESTIMATE_VALID_MONTHS_MESSAGE
      );
    }
    return raw.intValue();
  }

  /** 仕様: Core 第11.6節、日付仕様 第2.5節 */
  private static Integer requireDefaultCycles(Decimal raw) {
    if (raw == null || raw != raw.intValue() || raw < 1 || raw > 36) {
      throw handled(
        ContractDocumentSettingService.INVALID_DEFAULT_CYCLES_MESSAGE
      );
    }
    return raw.intValue();
  }

  private static ContractDocumentSetting__c toCompanyCheckSetting(
    SettingsDto input,
    String estimateMode,
    String invoiceMode
  ) {
    ContractDocumentSetting__c setting = new ContractDocumentSetting__c();
    setting.EstimateSendMode__c = estimateMode;
    setting.InvoiceSendMode__c = invoiceMode;
    setting.CompanyName__c = normalize(input.companyName);
    setting.Address__c = normalize(input.address);
    setting.InvoiceRegistrationNumber__c =
      normalize(input.invoiceRegistrationNumber);
    setting.BankTransferInfo__c = normalize(input.bankTransferInfo);
    return setting;
  }

  /** 仕様: Core 第11.3.2節。空でよいときは引かない。値があれば検証済みOWEを1件に限る。 */
  private static void validateOrgWideEmailAddress(String savedAddress) {
    String value = normalize(savedAddress);
    if (value == null) {
      return;
    }
    try {
      ContractEmailTemplateService.resolveOrgWide(value);
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      throw handled(ex.getMessage());
    }
  }

  private static Id parseId(String value, String label) {
    if (!Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', value)) {
      throw handled(label + 'の形式が不正です。');
    }
    try {
      return Id.valueOf(value);
    } catch (Exception ex) {
      throw handled(label + 'の形式が不正です。');
    }
  }

  private static String normalize(String value) {
    return String.isBlank(value) ? null : value.trim();
  }

  private static SelectOptionDto option(String label, String value) {
    SelectOptionDto result = new SelectOptionDto();
    result.label = label;
    result.value = value;
    return result;
  }

  /** 仕様: Core 第11.6節。無い／0件だけ。効く／効かないは書かない。 */
  private static List<DiagnosisDto> buildDiagnoses(
    ContractDocumentSetting__c setting,
    GlAccountingPolicy__c policy
  ) {
    List<DiagnosisDto> rows = new List<DiagnosisDto>();
    Boolean missingOrgSetting = setting == null || setting.Id == null;
    if (missingOrgSetting) {
      rows.add(diagnosis('帳票・送付', '組織の既定がありません。', null, null));
      rows.add(diagnosis('契約', '組織の既定がありません。', null, null));
    }
    if (countTemplates(ContractDocumentTemplateService.TYPE_ESTIMATE) == 0) {
      rows.add(
        diagnosis(
          '帳票・送付',
          '見積の帳票カタログがありません。',
          '帳票カタログ',
          cmdtListUrl('ContractDocumentTemplate__mdt', 'Estimate')
        )
      );
    }
    if (countTemplates(ContractDocumentTemplateService.TYPE_INVOICE) == 0) {
      rows.add(
        diagnosis(
          '帳票・送付',
          '請求の帳票カタログがありません。',
          '帳票カタログ',
          cmdtListUrl('ContractDocumentTemplate__mdt', 'Invoice')
        )
      );
    }
    if (countEmailCatalog(ContractEmailTemplateService.TYPE_ESTIMATE) == 0) {
      rows.add(
        diagnosis(
          '帳票・送付',
          '見積の送付メールカタログがありません。',
          '送付メールカタログ',
          cmdtListUrl('ContractEmailTemplate__mdt', 'Estimate')
        )
      );
    }
    if (countEmailCatalog(ContractEmailTemplateService.TYPE_INVOICE) == 0) {
      rows.add(
        diagnosis(
          '帳票・送付',
          '請求の送付メールカタログがありません。',
          '送付メールカタログ',
          cmdtListUrl('ContractEmailTemplate__mdt', 'Invoice')
        )
      );
    }
    if (
      ContractPermissionUtil.has(ContractPermissionUtil.ESTIMATE) &&
      [
        SELECT COUNT()
        FROM EstimateNoteMaster__c
        WITH SYSTEM_MODE
        LIMIT 1
      ] == 0
    ) {
      rows.add(
        diagnosis(
          '帳票・送付',
          '見積備考マスタがありません。',
          '見積備考マスタ',
          '/lightning/o/EstimateNoteMaster__c/list'
        )
      );
    }
    if (resolveAmountCalculationModified() == null) {
      rows.add(
        diagnosis(
          '金額計算',
          '金額計算の組織既定がありません。',
          '金額計算',
          cmdtListUrl('GlAccountingSetting__mdt', 'All')
        )
      );
    }
    if (policy == null) {
      rows.add(diagnosis('Accounting方針', '会計方針がありません。', null, null));
    }
    if (hasAccountingMasterSet()) {
      if ([SELECT COUNT() FROM GlAccount__c WITH SYSTEM_MODE LIMIT 1] == 0) {
        rows.add(
          diagnosis(
            'Accounting方針',
            '勘定科目がありません。',
            '勘定科目',
            '/lightning/o/GlAccount__c/list'
          )
        );
      }
      if ([SELECT COUNT() FROM GlAccountMap__c WITH SYSTEM_MODE LIMIT 1] == 0) {
        rows.add(
          diagnosis(
            'Accounting方針',
            '勘定科目割当がありません。',
            '割当',
            '/lightning/o/GlAccountMap__c/list'
          )
        );
      }
    }
    ContractValidationEnforce__c enforce =
      ContractValidationEnforce__c.getOrgDefaults();
    if (enforce == null || enforce.Id == null) {
      rows.add(diagnosis('入力', '入力強制の組織既定がありません。', null, null));
    }
    InvoiceLockExemptFields__c invoiceLock =
      InvoiceLockExemptFields__c.getOrgDefaults();
    if (invoiceLock == null || invoiceLock.Id == null) {
      rows.add(diagnosis('システム', '請求ロック除外項目の組織既定がありません。', null, null));
    }
    InvoicePaymentLockExemptFields__c paymentLock =
      InvoicePaymentLockExemptFields__c.getOrgDefaults();
    if (paymentLock == null || paymentLock.Id == null) {
      rows.add(diagnosis('システム', '入出金ロック除外項目の組織既定がありません。', null, null));
    }
    GlJournalLockExemptFields__c journalLock =
      GlJournalLockExemptFields__c.getOrgDefaults();
    if (journalLock == null || journalLock.Id == null) {
      rows.add(diagnosis('システム', '仕訳ロック除外項目の組織既定がありません。', null, null));
    }
    return rows;
  }

  private static Integer countTemplates(String documentType) {
    return [
      SELECT COUNT()
      FROM ContractDocumentTemplate__mdt
      WHERE DocumentType__c = :documentType
    ];
  }

  private static Integer countEmailCatalog(String documentType) {
    return [
      SELECT COUNT()
      FROM ContractEmailTemplate__mdt
      WHERE DocumentType__c = :documentType
    ];
  }

  private static Boolean hasAccountingMasterSet() {
    return [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE AssigneeId = :UserInfo.getUserId()
          AND PermissionSet.Name = 'Loop_21_AccountingMaster'
      ] > 0;
  }

  private static String cmdtListUrl(String objectApiName, String filterName) {
    return '/lightning/o/' +
      objectApiName +
      '/list?filterName=' +
      filterName;
  }

  private static DiagnosisDto diagnosis(
    String heading,
    String message,
    String linkLabel,
    String linkUrl
  ) {
    DiagnosisDto row = new DiagnosisDto();
    row.heading = heading;
    row.message = message;
    row.linkLabel = linkLabel;
    row.linkUrl = linkUrl;
    return row;
  }

  private static AuraHandledException handled(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
