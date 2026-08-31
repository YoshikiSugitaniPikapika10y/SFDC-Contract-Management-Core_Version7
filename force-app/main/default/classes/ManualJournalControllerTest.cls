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
        System.assert(
          ex.getMessage().contains('0より大きい整数'),
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
        System.assert(
          ex.getMessage().contains('AccountingがOFFのときは手動仕訳を登録できません'),
          'Accounting 第10.3節: OFFなら登録しない'
        );
      }
      System.assertEquals(true, thrown);
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
        System.assert(
          ex.getMessage().contains('確定済みの請求にだけ手動仕訳を登録できます'),
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
        System.assert(
          ex.getMessage().contains('取消理由を入力してください'),
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
        System.assert(
          ex.getMessage().contains('その他のときは内容を入力してください'),
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
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'mj@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 1,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'MJ Opp'
    );
    ContractService__c service = new ContractService__c(
      Name = 'MJ Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'MJ History',
      ContractService__c = service.Id,
      Opportunity__c = opportunity.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1
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
