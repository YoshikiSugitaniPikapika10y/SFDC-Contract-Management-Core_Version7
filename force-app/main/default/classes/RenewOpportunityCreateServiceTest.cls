@IsTest
private class RenewOpportunityCreateServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
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

      Boolean mismatchRejected = false;
      try {
        RenewOpportunityCreateService.assertCreatedForHistory(history, other.Id);
      } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
        mismatchRejected =
          ex.getMessage() ==
          RenewOpportunityCreateService.MISMATCH_RENEW_OPPORTUNITY_MESSAGE;
      }
      System.assertEquals(true, mismatchRejected);

      Boolean missingOpportunityRejected = false;
      try {
        RenewOpportunityCreateService.assertCreatedForHistory(
          history,
          account.Id
        );
      } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
        missingOpportunityRejected =
          ex.getMessage() ==
          RenewOpportunityCreateService.MISSING_RENEW_OPPORTUNITY_MESSAGE;
      }
      System.assertEquals(
        true,
        missingOpportunityRejected,
        '第11.5節: 更新商談が無い受注取消と同じ欠落文'
      );
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
}
