@IsTest
private class RenewOpportunityCreateServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void assertCreatedForHistory_rejectsMissingAndMismatch() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean missingRejected = false;
      try {
        RenewOpportunityCreateService.assertCreatedForHistory(null, null);
      } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
        missingRejected =
          ex.getMessage() ==
          RenewOpportunityCreateService.MISSING_RENEW_OPPORTUNITY_MESSAGE;
      }
      System.assertEquals(true, missingRejected);

      Account account = ContractTestDataFactory.insertAccount('Renew Assert Acct');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
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
      ContractService__c service = new ContractService__c(
        Name = 'Renew Assert Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Renew Assert History',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1
      );
      insert history;
      history = [
        SELECT Id, ContractService__c, ContractService__r.Account__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];

      Opportunity other = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Other Opp'
      );

      Boolean mismatchRejected = false;
      try {
        RenewOpportunityCreateService.assertCreatedForHistory(history, other.Id);
      } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
        mismatchRejected =
          ex.getMessage() ==
          RenewOpportunityCreateService.MISMATCH_RENEW_OPPORTUNITY_MESSAGE;
      }
      System.assertEquals(true, mismatchRejected);
    }
  }

  @IsTest
  static void deleteBySourceHistory_decrementsCountAndClearsArchivedOpportunity() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Delete Count Acct'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
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
      ContractService__c service = new ContractService__c(
        Name = 'Renew Delete Count Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      Opportunity quoteOpp = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Delete Quote Opp'
      );
      ContractHistory__c source = new ContractHistory__c(
        Name = 'Renew Delete Source',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1,
        Opportunity__c = quoteOpp.Id,
        RenewOpportunityRequestCount__c = 2
      );
      insert source;
      Opportunity renewOpp = ContractTestDataFactory.buildOpportunity(
        account.Id,
        'Renew Delete Opp',
        quoteOpp.Id,
        false,
        service.Id
      );
      ContractTestDataFactory.applyOpportunityDefaults(renewOpp);
      insert renewOpp;
      renewOpp.SourceContractHistory__c = source.Id;
      update renewOpp;
      source.RenewalOpportunity__c = renewOpp.Id;
      update source;
      ContractHistory__c archived = new ContractHistory__c(
        Name = 'Renew Delete Archived',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_RENEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ARCHIVE,
        Version__c = 2,
        Opportunity__c = renewOpp.Id
      );
      insert archived;

      Test.startTest();
      RenewOpportunityCreateService.deleteBySourceHistory(source.Id);
      Test.stopTest();

      System.assertEquals(
        0,
        [SELECT COUNT() FROM Opportunity WHERE Id = :renewOpp.Id],
        '第11.5節: 削除選択ONならパッケージが商談を削除する'
      );
      ContractHistory__c reloadedSource = [
        SELECT RenewalOpportunity__c, RenewOpportunityRequestCount__c
        FROM ContractHistory__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(
        null,
        reloadedSource.RenewalOpportunity__c,
        '第11.5節: 参照をnullにする'
      );
      System.assertEquals(
        1,
        reloadedSource.RenewOpportunityRequestCount__c,
        '第11.5節: 差し戻し削除ONで1減らす'
      );
      System.assertEquals(
        null,
        [
            SELECT Opportunity__c
            FROM ContractHistory__c
            WHERE Id = :archived.Id
          ]
          .Opportunity__c,
        '第4.9節・第5.3節: Archiveした見積のOpportunity__cを外してから商談を削除する'
      );
    }
  }

  @IsTest
  static void deleteBySourceHistory_doesNotDecrementBelowZero() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Delete Floor Acct'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
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
      ContractService__c service = new ContractService__c(
        Name = 'Renew Delete Floor Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      Opportunity quoteOpp = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Delete Floor Quote'
      );
      ContractHistory__c source = new ContractHistory__c(
        Name = 'Renew Delete Floor Source',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1,
        Opportunity__c = quoteOpp.Id,
        RenewOpportunityRequestCount__c = 0
      );
      insert source;

      Test.startTest();
      RenewOpportunityCreateService.deleteBySourceHistory(source.Id);
      Test.stopTest();

      System.assertEquals(
        0,
        [
            SELECT RenewOpportunityRequestCount__c
            FROM ContractHistory__c
            WHERE Id = :source.Id
          ]
          .RenewOpportunityRequestCount__c,
        '第11.5節: 差し戻し削除ONで1減らす（0未満にしない）'
      );
    }
  }

  @IsTest
  static void deleteBySourceHistory_switchOffDoesNotChangeCount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.RenewOpportunityEnabled__c = false;
      update setting;
      ContractDocumentSettingService.clearCache();
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Off Count Acct'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
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
      ContractService__c service = new ContractService__c(
        Name = 'Renew Off Count Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      Opportunity quoteOpp = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Off Quote Opp'
      );
      ContractHistory__c source = new ContractHistory__c(
        Name = 'Renew Off Source',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1,
        Opportunity__c = quoteOpp.Id,
        RenewOpportunityRequestCount__c = 2
      );
      insert source;
      Opportunity renewOpp = ContractTestDataFactory.buildOpportunity(
        account.Id,
        'Renew Off Opp',
        quoteOpp.Id,
        false,
        service.Id
      );
      ContractTestDataFactory.applyOpportunityDefaults(renewOpp);
      insert renewOpp;
      renewOpp.SourceContractHistory__c = source.Id;
      update renewOpp;
      source.RenewalOpportunity__c = renewOpp.Id;
      update source;

      Test.startTest();
      RenewOpportunityCreateService.deleteBySourceHistory(source.Id);
      Test.stopTest();

      System.assertEquals(
        1,
        [SELECT COUNT() FROM Opportunity WHERE Id = :renewOpp.Id],
        'Core 第5.6節: OFFなら商談削除もしない'
      );
      ContractHistory__c reloadedSource = [
        SELECT RenewalOpportunity__c, RenewOpportunityRequestCount__c
        FROM ContractHistory__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(
        renewOpp.Id,
        reloadedSource.RenewalOpportunity__c,
        'Core 第5.6節: OFFならLookupも動かない'
      );
      System.assertEquals(
        2,
        reloadedSource.RenewOpportunityRequestCount__c,
        'Core 第5.6節・第11.5節: OFFならカウントを変えない'
      );
    }
  }
}
