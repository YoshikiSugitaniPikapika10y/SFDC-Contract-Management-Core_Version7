public without sharing class GlAccountInstallService implements InstallHandler {
  @TestVisible
  private static Boolean forceUpgradeSeedPath;

  /** 仕様: Accounting 第4.1節、第10.2節、第13.5節、Core 第11.3.2節、第11.4.2節、第11.6節 */
  public void onInstall(InstallContext context) {
    seedOnInstall(context != null && context.isUpgrade());
  }

  /** 仕様: Accounting 第4.1節、第10.2節、第13.5節、Core 第11.3.2節、第11.4.2節、第11.6節 */
  public static void seedOnInstall() {
    seedOnInstall(forceUpgradeSeedPath == true);
  }

  private static void seedOnInstall(Boolean isUpgrade) {
    // 仕様: Core 第11.4.2節・第11.6節。コピー見本と組織設定・ロック除外は初回だけ。アップグレードでは消した行を戻さない。
    if (isUpgrade != true) {
      seedFieldCopySamples();
      seedInvoiceLockExemptFields();
      seedPaymentLockExemptFields();
      seedJournalLockExemptFields();
      seedContractDocumentSetting();
    }
    if ([SELECT COUNT() FROM GlAccountingPolicy__c WITH SYSTEM_MODE] == 0) {
      insert GlAccountingPolicyService.newOrgDefault();
    }
    // 仕様: Accounting 第4.1節・第10.2節。科目・手動仕訳は Core 第11.6節の対象外。アップグレードでは削除後を再作成しない。
    if (isUpgrade == true) {
      return;
    }
    if (
      [SELECT COUNT() FROM GlManualJournalSetting__c WHERE SettingKey__c != NULL WITH SYSTEM_MODE] > 0
    ) {
      return;
    }
    Map<String, Id> accountIds = seedAccounts();
    seedManualSettings(accountIds);
  }

  /** 仕様: Core 第11.4.2節。初回インストールだけ。削除後のアップグレードでは戻さない。 */
  private static void seedFieldCopySamples() {
    if ([SELECT COUNT() FROM FieldCopyDefinition__c WITH SYSTEM_MODE] > 0) {
      return;
    }
    insert new List<FieldCopyDefinition__c>{
      new FieldCopyDefinition__c(
        Name = 'Sample_Inv_AccountName',
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c',
        TargetObject__c = 'Invoice__c'
      ),
      new FieldCopyDefinition__c(
        Name = 'Sample_Line_ProductCode',
        SourceObject__c = 'Product2',
        SourceFieldApiName__c = 'ProductCode',
        TargetFieldApiName__c = 'ProductCodeSnapShot__c',
        TargetObject__c = 'InvoiceLine__c'
      ),
      // 仕様: Core 第11.4.2節。From=Product2.ProductCode、To=商品コード SnapShot、コンテキスト=明細仕訳。
      new FieldCopyDefinition__c(
        Name = 'Sample_Journal_ProductCode',
        SourceObject__c = 'Product2',
        SourceFieldApiName__c = 'ProductCode',
        TargetFieldApiName__c = 'ProductCodeSnapShot__c',
        TargetObject__c = 'GlJournal__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL
      )
    };
  }

  /** 仕様: Core 第11.6節。無ければ初回インストールだけ。人が消したあとのアップグレードでは戻さない。 */
  private static void seedInvoiceLockExemptFields() {
    InvoiceLockExemptFields__c existing = InvoiceLockExemptFields__c.getOrgDefaults();
    if (existing != null && existing.Id != null) {
      return;
    }
    insert new InvoiceLockExemptFields__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      FieldApiNames__c = InvoiceLockUtil.SEED_LOCK_EXEMPT_FIELDS
    );
  }

  /** 仕様: Core 第11.6節。無ければ初回インストールだけ。人が消したあとのアップグレードでは戻さない。 */
  private static void seedPaymentLockExemptFields() {
    InvoicePaymentLockExemptFields__c existing = InvoicePaymentLockExemptFields__c.getOrgDefaults();
    if (existing != null && existing.Id != null) {
      return;
    }
    insert new InvoicePaymentLockExemptFields__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      FieldApiNames__c = InvoicePaymentLockUtil.SEED_LOCK_EXEMPT_FIELDS
    );
  }

  /** 仕様: Core 第11.6節。無ければ初回インストールだけ。人が消したあとのアップグレードでは戻さない。 */
  private static void seedJournalLockExemptFields() {
    GlJournalLockExemptFields__c existing = GlJournalLockExemptFields__c.getOrgDefaults();
    if (existing != null && existing.Id != null) {
      return;
    }
    insert new GlJournalLockExemptFields__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      FieldApiNames__c = JournalLockService.SEED_LOCK_EXEMPT_FIELDS
    );
  }

  /** 仕様: Core 第4.10節、第11.3.2節、第11.5節、第11.6節、第11.8節。無ければ初回だけ。アップグレードでは消した組織既定を戻さない。既定帳票・既定メールは持たない。IsDefault は post-install では書かない。 */
  private static void seedContractDocumentSetting() {
    ContractDocumentSetting__c existing = ContractDocumentSetting__c.getOrgDefaults();
    if (existing != null && existing.Id != null) {
      return;
    }
    insert new ContractDocumentSetting__c(
      Name = 'OrgDefault',
      SetupOwnerId = UserInfo.getOrganizationId(),
      EstimateSendMode__c = ContractDocumentSettingService.MODE_PDF_ONLY,
      InvoiceSendMode__c = ContractDocumentSettingService.MODE_PDF_ONLY,
      DefaultMonthlyCycles__c = 12,
      EstimateValidMonths__c = 1,
      RenewOpportunityEnabled__c = false
    );
  }

  private static Map<String, Id> seedAccounts() {
    Map<String, String> typesByName = new Map<String, String>{
      '売掛金' => 'Asset',
      '仮受金' => 'Liability',
      '為替差益' => 'Revenue',
      '為替差損' => 'Expense',
      '支払手数料' => 'Expense',
      '雑収入' => 'Revenue',
      '貸倒損失' => 'Expense'
    };
    Map<String, Id> existing = new Map<String, Id>();
    for (GlAccount__c account : [
      SELECT Id, Name
      FROM GlAccount__c
      WHERE Name IN :typesByName.keySet()
      WITH SYSTEM_MODE
    ]) {
      existing.put(account.Name, account.Id);
    }
    List<GlAccount__c> inserts = new List<GlAccount__c>();
    for (String name : typesByName.keySet()) {
      if (!existing.containsKey(name)) {
        inserts.add(
          new GlAccount__c(
            Name = name,
            AccountType__c = typesByName.get(name),
            IsActive__c = true
          )
        );
      }
    }
    if (!inserts.isEmpty()) {
      insert inserts;
      for (GlAccount__c account : inserts) {
        existing.put(account.Name, account.Id);
      }
    }
    return existing;
  }

  private static void seedManualSettings(Map<String, Id> accountIds) {
    List<GlManualJournalSetting__c> settings = new List<GlManualJournalSetting__c>{
      setting(
        'FX_LOSS',
        '為替差損の計上',
        'FxLoss',
        accountIds.get('為替差損'),
        'AccountsReceivable',
        accountIds.get('売掛金'),
        '入金不足が為替変動による場合',
        10
      ),
      setting(
        'FX_GAIN',
        '為替差益の計上',
        'UnappliedCash',
        accountIds.get('仮受金'),
        'FxGain',
        accountIds.get('為替差益'),
        '入金超過が為替変動による場合',
        20
      ),
      setting(
        'BANK_FEE_ABSORBED',
        '振込手数料の当社負担',
        'OtherExpense',
        accountIds.get('支払手数料'),
        'AccountsReceivable',
        accountIds.get('売掛金'),
        '手数料差引分を当社負担する場合',
        30
      ),
      setting(
        'OVERPAYMENT_INCOME',
        '過入金の収益化',
        'UnappliedCash',
        accountIds.get('仮受金'),
        'OtherIncome',
        accountIds.get('雑収入'),
        '過入金を返さず収益化する場合',
        40
      ),
      setting(
        'BAD_DEBT',
        '貸倒の計上',
        'OtherExpense',
        accountIds.get('貸倒損失'),
        'AccountsReceivable',
        accountIds.get('売掛金'),
        '回収不能が確定した場合',
        50
      )
    };
    insert settings;
  }

  private static GlManualJournalSetting__c setting(
    String key,
    String name,
    String debitSlot,
    Id debitAccountId,
    String creditSlot,
    Id creditAccountId,
    String description,
    Integer sortOrder
  ) {
    return new GlManualJournalSetting__c(
      Name = name,
      SettingKey__c = key,
      DebitSlotKey__c = debitSlot,
      DebitAccount__c = debitAccountId,
      CreditSlotKey__c = creditSlot,
      CreditAccount__c = creditAccountId,
      Description__c = description,
      SortOrder__c = sortOrder,
      IsActive__c = true
    );
  }
}
