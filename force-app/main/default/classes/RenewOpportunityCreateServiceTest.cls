@IsTest
private class RenewOpportunityCreateServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  private static void enableRenewOpportunity() {
    ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
    setting.RenewOpportunityEnabled__c = true;
    update setting;
    ContractDocumentSettingService.clearCache();
  }

  @IsTest
  static void assertCreatedForHistory_rejectsMissingAndMismatch() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      try {
        RenewOpportunityCreateService.assertCreatedForHistory(null, null);
        System.assert(false, '欠落は例外になる');
      } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
        System.assertEquals(
          RenewOpportunityCreateService.MISSING_RENEW_OPPORTUNITY_MESSAGE,
          ex.getMessage(),
          '第11.5節: 更新商談が無い'
        );
      }

      Account account = ContractTestDataFactory.insertAccount('Renew Assert Acct');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew Assert Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Renew Assert History',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1
      );
      ContractTestDataFactory.applyRequiredFields(history);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
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

      try {
        RenewOpportunityCreateService.assertCreatedForHistory(history, other.Id);
        System.assert(false, '不一致は例外になる');
      } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
        System.assertEquals(
          RenewOpportunityCreateService.MISMATCH_RENEW_OPPORTUNITY_MESSAGE,
          ex.getMessage(),
          '第11.5節: 更新商談の元契約履歴・契約サービス・取引先が一致しない'
        );
      }

      try {
        RenewOpportunityCreateService.assertCreatedForHistory(
          history,
          account.Id
        );
        System.assert(false, '商談欠落は例外になる');
      } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
        System.assertEquals(
          RenewOpportunityCreateService.MISSING_RENEW_OPPORTUNITY_MESSAGE,
          ex.getMessage(),
          '第11.5節: 更新商談が無い受注取消と同じ欠落文'
        );
      }
      System.assertEquals(
        null,
        RenewOpportunityCreateService.findBySourceHistory(null),
        '第11.5節: 元契約履歴が無ければ更新商談 Id は返さない'
      );
      System.assertEquals(
        null,
        RenewOpportunityCreateService.findBySourceHistory(history.Id),
        '第11.5節: 元契約履歴に更新商談が無ければ Id は返さない'
      );
      RenewOpportunityCreateService.deleteBySourceHistory(null);
    }
  }

  @IsTest
  static void deleteBySourceHistory_decrementsCountAndClearsArchivedOpportunity() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableRenewOpportunity();
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Delete Count Acct'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew Delete Count Service'
      );
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
      ContractTestDataFactory.applyRequiredFields(source);
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
      ContractTestDataFactory.applyRequiredFields(archived);
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
      enableRenewOpportunity();
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Delete Floor Acct'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew Delete Floor Service'
      );
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
      ContractTestDataFactory.applyRequiredFields(source);
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
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew Off Count Service'
      );
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
      ContractTestDataFactory.applyRequiredFields(source);
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

  @IsTest
  static void assertCreatedForHistory_acceptsMatchingOpportunity() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Match Acct'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew Match Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Renew Match History',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1
      );
      ContractTestDataFactory.applyRequiredFields(history);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
      insert history;
      history = [
        SELECT Id, ContractService__c, ContractService__r.Account__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      Opportunity quoteOpp = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Match Quote'
      );
      Opportunity renewOpp = ContractTestDataFactory.buildOpportunity(
        account.Id,
        'Renew Match Opp',
        quoteOpp.Id,
        false,
        service.Id
      );
      ContractTestDataFactory.applyOpportunityDefaults(renewOpp);
      insert renewOpp;
      renewOpp.SourceContractHistory__c = history.Id;
      update renewOpp;
      RenewOpportunityCreateService.assertCreatedForHistory(
        history,
        renewOpp.Id
      );
      System.assertEquals(
        renewOpp.Id,
        RenewOpportunityCreateService.findBySourceHistory(history.Id),
        'Core 第11.5節: 元契約履歴から作成した更新商談 Id を返す'
      );
    }
  }

  @IsTest
  static void deleteBySourceHistory_missingHistory_doesNotThrow() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableRenewOpportunity();
      RenewOpportunityCreateService.deleteBySourceHistory(UserInfo.getUserId());
      System.assertEquals(
        null,
        RenewOpportunityCreateService.findBySourceHistory(UserInfo.getUserId()),
        'Core 第11.5節: 元契約履歴が無ければ更新商談 Id は返さない'
      );
    }
  }

  @IsTest
  static void deleteByLockedHistory_nullDoesNotThrow() {
    RenewOpportunityCreateService.deleteByLockedHistory(null);
    ContractHistory__c blank = new ContractHistory__c();
    RenewOpportunityCreateService.deleteByLockedHistory(blank);
    System.assertEquals(
      null,
      RenewOpportunityCreateService.findBySourceHistory(null),
      'Core 第11.5節: 元契約履歴が無ければ更新商談 Id は返さない'
    );
  }

  @IsTest
  static void deleteByLockedHistory_switchOffDoesNotDelete() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.RenewOpportunityEnabled__c = false;
      update setting;
      ContractDocumentSettingService.clearCache();
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Locked Off Acct'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew Locked Off Service'
      );
      Opportunity quoteOpp = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Locked Off Quote'
      );
      ContractHistory__c source = new ContractHistory__c(
        Name = 'Renew Locked Off Source',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1,
        Opportunity__c = quoteOpp.Id,
        RenewOpportunityRequestCount__c = 2
      );
      ContractTestDataFactory.applyRequiredFields(source);
      insert source;
      Opportunity renewOpp = ContractTestDataFactory.buildOpportunity(
        account.Id,
        'Renew Locked Off Opp',
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
      source = [
        SELECT Id, RenewalOpportunity__c, RenewOpportunityRequestCount__c
        FROM ContractHistory__c
        WHERE Id = :source.Id
      ];
      RenewOpportunityCreateService.deleteByLockedHistory(source);
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Opportunity WHERE Id = :renewOpp.Id],
        'Core 第5.6節: OFFなら商談削除もしない'
      );
    }
  }

  @IsTest
  static void deleteByLockedHistory_findsOpportunityWhenLookupBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableRenewOpportunity();
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Lookup Blank Acct'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew Lookup Blank Service'
      );
      Opportunity quoteOpp = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Lookup Blank Quote'
      );
      ContractHistory__c source = new ContractHistory__c(
        Name = 'Renew Lookup Blank Source',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1,
        Opportunity__c = quoteOpp.Id,
        RenewOpportunityRequestCount__c = 1
      );
      ContractTestDataFactory.applyRequiredFields(source);
      insert source;
      Opportunity renewOpp = ContractTestDataFactory.buildOpportunity(
        account.Id,
        'Renew Lookup Blank Opp',
        quoteOpp.Id,
        false,
        service.Id
      );
      ContractTestDataFactory.applyOpportunityDefaults(renewOpp);
      insert renewOpp;
      renewOpp.SourceContractHistory__c = source.Id;
      update renewOpp;
      source = [
        SELECT Id, RenewalOpportunity__c, RenewOpportunityRequestCount__c
        FROM ContractHistory__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(null, source.RenewalOpportunity__c);
      Test.startTest();
      RenewOpportunityCreateService.deleteByLockedHistory(source);
      Test.stopTest();
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Opportunity WHERE Id = :renewOpp.Id],
        'Core 第5.6節・第11.5節: Lookupが空でも元契約履歴から作成した更新商談を削除する'
      );
      System.assertEquals(
        null,
        [
            SELECT RenewalOpportunity__c
            FROM ContractHistory__c
            WHERE Id = :source.Id
          ]
          .RenewalOpportunity__c,
        'Core 第5.6節: 削除ONなら RenewalOpportunity を空にする'
      );
    }
  }

  @IsTest
  static void buildDealName_showsVersionAndPeriod() {
    System.assertEquals(
      '【更新】更新名取引先｜Version3｜2027/06/01〜2028/05/31',
      RenewOpportunityCreateService.buildDealName(
        '更新',
        '更新名取引先',
        3,
        Date.newInstance(2027, 6, 1),
        Date.newInstance(2028, 5, 31)
      )
    );
    System.assertEquals(
      '【解約】更新名取引先｜Version4｜2028/05/31',
      RenewOpportunityCreateService.buildDealName(
        '解約',
        '更新名取引先',
        4,
        Date.newInstance(2028, 5, 31),
        null
      )
    );
  }

  @IsTest
  static void ensureForOrderedHistory_namesNextVersion() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableRenewOpportunity();
      Account account = ContractTestDataFactory.insertAccount('更新名取引先');
      Opportunity quote = ContractTestDataFactory.insertOpportunity(
        account.Id,
        '新規商談'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        '更新名サービス'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      ContractHistory__c source = new ContractHistory__c(
        Name = '更新名の元履歴',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = quote.Id
      );
      ContractTestDataFactory.applyRequiredFields(source);
      insert source;
      Product2 product = ContractTestDataFactory.buildProduct('更新名商品');
      product.UnitName__c = 'ID';
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c line = new ContractProduct__c(
        ContractHistory__c = source.Id,
        Product__c = product.Id,
        Account__c = account.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 96000,
        Unit__c = 'ID',
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = product.BillingType__c,
        Type__c = 'New',
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
      );
      ContractTestDataFactory.applyRequiredFields(line);
      insert line;
      source.historystatus__c = ContractDomainConstants.HISTORY_STATUS_ORDERED;
      update source;

      Test.startTest();
      Id createdId = RenewOpportunityCreateService.ensureForOrderedHistory(
        source.Id
      );
      Test.stopTest();

      Opportunity created = [
        SELECT Name, SourceContractHistory__c, ContractService__c, AccountId
        FROM Opportunity
        WHERE Id = :createdId
      ];
      Account stored = [SELECT Name FROM Account WHERE Id = :account.Id];
      System.assertEquals(
        RenewOpportunityCreateService.buildDealName(
          '更新',
          stored.Name,
          3,
          Date.newInstance(2027, 6, 1),
          Date.newInstance(2028, 5, 31)
        ),
        created.Name
      );
      System.assertEquals(source.Id, created.SourceContractHistory__c);
      System.assertEquals(service.Id, created.ContractService__c);
      System.assertEquals(account.Id, created.AccountId);
      System.assertEquals(
        createdId,
        [
          SELECT RenewalOpportunity__c
          FROM ContractHistory__c
          WHERE Id = :source.Id
        ]
        .RenewalOpportunity__c
      );
    }
  }

  @IsTest
  static void applyCancelNames_renamesEstimateOpportunity() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('更新名取引先');
      Opportunity quote = ContractTestDataFactory.insertOpportunity(
        account.Id,
        '解約前の商談'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        '解約名サービス'
      );
      ContractHistory__c cancelHistory = new ContractHistory__c(
        Name = '解約見積',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_CANCEL,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 4,
        EffectiveDate__c = Date.newInstance(2028, 5, 31),
        Opportunity__c = quote.Id
      );
      ContractTestDataFactory.applyRequiredFields(cancelHistory);
      insert cancelHistory;

      Account stored = [SELECT Name FROM Account WHERE Id = :account.Id];
      System.assertEquals(
        RenewOpportunityCreateService.buildDealName(
          '解約',
          stored.Name,
          4,
          Date.newInstance(2028, 5, 31),
          null
        ),
        [SELECT Name FROM Opportunity WHERE Id = :quote.Id].Name
      );
    }
  }
}
