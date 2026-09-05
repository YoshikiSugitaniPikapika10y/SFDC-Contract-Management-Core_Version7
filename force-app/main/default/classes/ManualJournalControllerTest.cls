@IsTest
private class ManualJournalControllerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void register_rejectsNegativeAmount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        ManualJournalController.register(
          UserInfo.getUserId(),
          UserInfo.getUserId(),
          Date.today(),
          -1
        );
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          '金額は0より大きい整数にしてください。',
          ex.getMessage(),
          'Accounting 第10.3節: 負数は自動反転せず拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_rejectsWhenAccountingOff() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      GlManualJournalSetting__c setting = insertActiveSetting();
      Boolean thrown = false;
      try {
        ManualJournalController.register(
          invoice.Id,
          setting.Id,
          Date.today(),
          100
        );
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          'AccountingがOFFのときは手動仕訳を登録できません。',
          ex.getMessage(),
          'Accounting 第10.3節: OFFなら登録しない'
        );
      }
      System.assertEquals(true, thrown);
      Boolean previewThrown = false;
      try {
        ManualJournalController.previewRegister(
          invoice.Id,
          setting.Id,
          Date.today(),
          100,
          null,
          null,
          invoice.ContractHistory__c
        );
      } catch (Exception ex) {
        previewThrown = true;
        System.assertEquals(
          'AccountingがOFFのときは手動仕訳を登録できません。',
          ex.getMessage(),
          'Accounting 第10.3節: OFFならプレビューもしない'
        );
      }
      System.assertEquals(true, previewThrown);
      Boolean scopedRegisterThrown = false;
      try {
        ManualJournalController.register(
          invoice.Id,
          setting.Id,
          Date.today(),
          100,
          null,
          null,
          null,
          invoice.ContractHistory__c
        );
      } catch (Exception ex) {
        scopedRegisterThrown = true;
        System.assertEquals(
          'AccountingがOFFのときは手動仕訳を登録できません。',
          ex.getMessage(),
          'Accounting 第10.3節: 契約履歴付き登録もOFFなら拒否'
        );
      }
      System.assertEquals(true, scopedRegisterThrown);
    }
  }

  @IsTest
  static void register_rejectsDraftInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertDraftInvoice();
      GlManualJournalSetting__c setting = insertActiveSetting();
      Boolean thrown = false;
      try {
        ManualJournalController.register(
          invoice.Id,
          setting.Id,
          Date.today(),
          100,
          AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id),
          null
        );
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          '確定済みの請求にだけ手動仕訳を登録できます。',
          ex.getMessage(),
          'Accounting 第10.3節: 確定前請求には登録できない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void cancel_requiresReason() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        ManualJournalController.cancel(UserInfo.getUserId(), null, null, null);
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          '取消理由を入力してください。',
          ex.getMessage(),
          'Accounting 第10.4節: 取消理由は必須'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_withoutManageInvoiceOps_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MANUAL_JOURNAL => false
      };
      Boolean thrown = false;
      try {
        ManualJournalController.register(
          UserInfo.getUserId(),
          UserInfo.getUserId(),
          Date.today(),
          100
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '手動仕訳を実行する権限がありません。',
          ex.getMessage(),
          'Core 第7.7.3節: 手動仕訳登録は請求ボード操作権限を見る'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void cancel_withoutManageInvoiceOps_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MANUAL_JOURNAL => false
      };
      Boolean thrown = false;
      try {
        ManualJournalController.cancel(
          UserInfo.getUserId(),
          'Duplicate',
          null,
          null
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '手動仕訳を実行する権限がありません。',
          ex.getMessage(),
          'Core 第7.7.3節: 手動仕訳取消は請求ボード操作権限を見る'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void cancel_otherRequiresText() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        ManualJournalController.cancel(
          UserInfo.getUserId(),
          'Other',
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          '取消理由がその他のときは内容を入力してください。',
          ex.getMessage(),
          'Accounting 第10.4節: Otherは内容必須'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void registerAndCancel_rejectInvoiceOutsideContractService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c own = insertConfirmedInvoice();
      Invoice__c other = insertConfirmedInvoice();
      GlManualJournalSetting__c setting = insertActiveSetting();
      GlManualJournalHeader__c otherHeader = new GlManualJournalHeader__c(
        Invoice__c = other.Id,
        GlManualJournalSetting__c = setting.Id,
        PostingDate__c = Date.today(),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      insert otherHeader;

      Boolean registerRejected = false;
      try {
        ManualJournalController.register(
          other.Id,
          setting.Id,
          Date.today(),
          100,
          null,
          null,
          null,
          own.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        registerRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        registerRejected,
        'Core 第7.7.3節: 契約サービスをまたいで手動仕訳を登録できない'
      );

      Boolean previewRejected = false;
      try {
        ManualJournalController.previewCancel(
          otherHeader.Id,
          Date.today(),
          own.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        previewRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        previewRejected,
        'Core 第7.7.3節: 契約サービスをまたいで手動仕訳取消プレビューできない'
      );

      Boolean cancelRejected = false;
      try {
        ManualJournalController.cancel(
          otherHeader.Id,
          'Duplicate',
          null,
          Date.today(),
          null,
          null,
          own.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        cancelRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        cancelRejected,
        'Core 第7.7.3節: 契約サービスをまたいで手動仕訳を取消できない'
      );
    }
  }

  @IsTest
  static void previewCancel_nullHeader_wrapsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        ManualJournalController.previewCancel(null, Date.today());
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '取消する手動仕訳が指定されていません。',
          ex.getMessage(),
          'Accounting 第10.4節: 取消対象の手動仕訳が無ければ始めない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void previewRegister_withoutManageInvoiceOps_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertConfirmedInvoice();
      GlManualJournalSetting__c setting = insertActiveSetting();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MANUAL_JOURNAL => false
      };
      Boolean thrown = false;
      try {
        ManualJournalController.previewRegister(
          invoice.Id,
          setting.Id,
          Date.today(),
          100,
          null,
          null,
          invoice.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '手動仕訳を実行する権限がありません。',
          ex.getMessage(),
          'Core 第7.7.3節: 手動仕訳プレビューは請求ボード操作権限を見る'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void previewRegister_rejectsWhenInvoiceOutsideContractService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c own = insertConfirmedInvoice();
      Invoice__c other = insertConfirmedInvoice();
      GlManualJournalSetting__c setting = insertActiveSetting();
      Boolean previewRejected = false;
      try {
        ManualJournalController.previewRegister(
          other.Id,
          setting.Id,
          Date.today(),
          100,
          null,
          null,
          own.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        previewRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage(),
          'Core 第7.7.3節: 契約サービスをまたいで手動仕訳登録プレビューできない'
        );
      }
      System.assertEquals(true, previewRejected);
    }
  }

  private static Invoice__c insertConfirmedInvoice() {
    return insertInvoice(true);
  }

  private static Invoice__c insertDraftInvoice() {
    return insertInvoice(false);
  }

  private static Invoice__c insertInvoice(Boolean confirmed) {
    Account account = ContractTestDataFactory.insertAccount(
      'MJ ' + String.valueOf(Crypto.getRandomInteger())
    );
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      'MJ Service'
    );
    BillingAccount__c billingAccount = [
      SELECT Id
      FROM BillingAccount__c
      WHERE Id = :service.BiilingAcccount__c
    ];
    ContractHistory__c history = new ContractHistory__c(
      Name = 'MJ History',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1
    );
    ContractTestDataFactory.applyRequiredFields(history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(
      history,
      account.Id
    );
    insert history;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      BillingAccountSnapShot__c = billingAccount.Id,
      InvoiceTransactionStatus__c = confirmed
        ? InvoiceTransactionStatusService.TX_CONFIRMED
        : InvoiceTransactionStatusService.TX_DRAFT,
      SystemIntegrationDate__c = confirmed ? Date.today() : null
    );
    ContractTestDataFactory.applyRequiredFields(invoice);
    ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
    if (confirmed) {
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
    } else {
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT;
      invoice.SystemIntegrationDate__c = null;
    }
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    return invoice;
  }

  private static GlManualJournalSetting__c insertActiveSetting() {
    GlAccount__c debit = new GlAccount__c(
      Name = 'MJ Debit',
      AccountType__c = 'Expense',
      IsActive__c = true
    );
    GlAccount__c credit = new GlAccount__c(
      Name = 'MJ Credit',
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    insert new List<GlAccount__c>{ debit, credit };
    GlManualJournalSetting__c setting = new GlManualJournalSetting__c(
      Name = '為替差損の計上',
      DebitSlotKey__c = 'FxLoss',
      DebitAccount__c = debit.Id,
      CreditSlotKey__c = 'AccountsReceivable',
      CreditAccount__c = credit.Id,
      IsActive__c = true
    );
    insert setting;
    return setting;
  }
}
