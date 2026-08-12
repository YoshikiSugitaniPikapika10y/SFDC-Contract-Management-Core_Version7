@IsTest
private class RenewOpportunityCreateServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void createFromOrderedHistory_setsRelationsAndCmdtFields() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createOrderedHistoryData();
      stubStandardDefinitions();

      Test.startTest();
      Id renewOppId = RenewOpportunityCreateService.createFromOrderedHistory(
        data.history.Id
      );
      Test.stopTest();

      Opportunity created = [
        SELECT
          Id,
          Name,
          AccountId,
          StageName,
          CloseDate,
          PreviousOpportunity__c,
          SourceContractHistory__c,
          OwnerId
        FROM Opportunity
        WHERE Id = :renewOppId
      ];
      System.assertEquals(data.account.Id, created.AccountId);
      System.assertEquals(
        data.opportunity.Id,
        created.PreviousOpportunity__c
      );
      System.assertEquals(
        data.history.Id,
        created.SourceContractHistory__c
      );
      System.assertEquals(data.account.Name + ' 更新', created.Name);
      System.assertEquals(
        data.history.CurrentTermEndDate__c,
        created.CloseDate
      );
      System.assertEquals(firstActiveStageName(), created.StageName);
      System.assertEquals(UserInfo.getUserId(), created.OwnerId);
    }
  }

  @IsTest
  static void createFromOrderedHistory_appliesOwnerFromFieldDefinition() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createOrderedHistoryData();
      User ownerUser = ContractTestDataFactory.getAdminUser();
      RenewOpportunityCreateService.resetCache();
      List<RenewOpportunityField__mdt> definitions = baseCreateDefinitions();
      definitions.add(
        new RenewOpportunityField__mdt(
          DeveloperName = 'OwnerId',
          Active__c = true,
          TargetFieldApiName__c = 'OwnerId',
          ValueType__c = 'Constant',
          Value__c = String.valueOf(ownerUser.Id)
        )
      );
      RenewOpportunityCreateService.cachedDefinitions = definitions;

      Test.startTest();
      Id renewOppId = RenewOpportunityCreateService.createFromOrderedHistory(
        data.history.Id
      );
      Test.stopTest();

      Opportunity created = [
        SELECT OwnerId
        FROM Opportunity
        WHERE Id = :renewOppId
      ];
      System.assertEquals(ownerUser.Id, created.OwnerId);
    }
  }

  @IsTest
  static void deleteBySourceHistory_removesCreatedOpportunity() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createOrderedHistoryData();
      stubStandardDefinitions();
      Id renewOppId = RenewOpportunityCreateService.createFromOrderedHistory(
        data.history.Id
      );
      System.assertNotEquals(null, renewOppId);

      Test.startTest();
      RenewOpportunityCreateService.deleteBySourceHistory(data.history.Id);
      Test.stopTest();

      System.assertEquals(
        0,
        [SELECT COUNT() FROM Opportunity WHERE Id = :renewOppId]
      );
      System.assertEquals(
        null,
        RenewOpportunityCreateService.findBySourceHistory(data.history.Id)
      );
    }
  }

  @IsTest
  static void createFromOrderedHistory_templateUsesTokenAndRowDateFormats() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createOrderedHistoryData();
      RenewOpportunityCreateService.resetCache();
      List<RenewOpportunityField__mdt> definitions = baseCreateDefinitions();
      for (Integer i = 0; i < definitions.size(); i++) {
        if (definitions[i].TargetFieldApiName__c == 'Name') {
          definitions[i] = new RenewOpportunityField__mdt(
            DeveloperName = 'Name',
            Active__c = true,
            TargetFieldApiName__c = 'Name',
            ValueType__c = 'Template',
            Value__c = '{ContractHistory__c.CurrentTermEndDate__c:yy/MM}/{ContractHistory__c.CurrentTermEndDate__c}',
            DateFormat__c = 'yyyy/MM/dd'
          );
        }
      }
      RenewOpportunityCreateService.cachedDefinitions = definitions;

      Id renewOppId = RenewOpportunityCreateService.createFromOrderedHistory(
        data.history.Id
      );
      Opportunity created = [
        SELECT Name
        FROM Opportunity
        WHERE Id = :renewOppId
      ];
      System.assertEquals('26/05/2026/05/31', created.Name);
    }
  }

  @IsTest
  static void createFromOrderedHistory_existing_unlinksAndRecreates() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createOrderedHistoryData();
      stubStandardDefinitions();
      Id firstId = RenewOpportunityCreateService.createFromOrderedHistory(
        data.history.Id
      );

      Test.startTest();
      Id secondId = RenewOpportunityCreateService.createFromOrderedHistory(
        data.history.Id
      );
      Test.stopTest();

      System.assertNotEquals(firstId, secondId);
      Opportunity first = [
        SELECT SourceContractHistory__c
        FROM Opportunity
        WHERE Id = :firstId
      ];
      Opportunity second = [
        SELECT SourceContractHistory__c, PreviousOpportunity__c
        FROM Opportunity
        WHERE Id = :secondId
      ];
      System.assertEquals(
        null,
        first.SourceContractHistory__c,
        '旧商談の紐づけは外す（削除はしない）'
      );
      System.assertEquals(data.history.Id, second.SourceContractHistory__c);
      System.assertEquals(
        data.opportunity.Id,
        second.PreviousOpportunity__c
      );
      System.assertEquals(
        secondId,
        RenewOpportunityCreateService.findBySourceHistory(data.history.Id)
      );
    }
  }

  @IsTest
  static void createFromOrderedHistory_cancel_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createOrderedHistoryData();
      data.history.Type__c = ContractDomainConstants.HISTORY_TYPE_CANCEL;
      update data.history;
      stubStandardDefinitions();

      Boolean thrown = false;
      try {
        RenewOpportunityCreateService.createFromOrderedHistory(data.history.Id);
      } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
        thrown = true;
        System.assertEquals(
          'Cancel の契約履歴からは更新商談を作成できません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void createFromOrderedHistory_spot_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      // 受注後は Lifecycle 変更不可のため、受注前に Spot をセットする
      TestData data = createOrderedHistoryData(
        ContractDomainConstants.LIFECYCLE_SPOT
      );
      stubStandardDefinitions();

      Boolean thrown = false;
      try {
        RenewOpportunityCreateService.createFromOrderedHistory(data.history.Id);
      } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('Spot'),
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void createFromOrderedHistory_estimate_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createOrderedHistoryData();
      data.history.historystatus__c = 'Estimate';
      update data.history;
      stubStandardDefinitions();

      Boolean thrown = false;
      try {
        RenewOpportunityCreateService.createFromOrderedHistory(data.history.Id);
      } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
        thrown = true;
        System.assertEquals(
          '更新商談は受注済み（Ordered）の契約履歴からのみ作成できます。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void validateActiveDefinitions_rejectsForbiddenTarget() {
    RenewOpportunityCreateService.resetCache();
    RenewOpportunityCreateService.cachedDefinitions = new List<RenewOpportunityField__mdt>{
      new RenewOpportunityField__mdt(
        DeveloperName = 'BadAccount',
        Active__c = true,
        TargetFieldApiName__c = 'AccountId',
        ValueType__c = 'Field',
        Value__c = 'Opportunity.AccountId'
      )
    };

    Boolean thrown = false;
    try {
      RenewOpportunityCreateService.validateActiveDefinitions();
    } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
      thrown = true;
      System.assertEquals(
        '更新商談項目「BadAccount」: セット先項目「AccountId」はコード固定のためカスタムメタデータでは指定できません。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void findBySourceHistory_returnsCreatedId() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createOrderedHistoryData();
      stubStandardDefinitions();
      Id renewOppId = RenewOpportunityCreateService.createFromOrderedHistory(
        data.history.Id
      );
      System.assertEquals(
        renewOppId,
        RenewOpportunityCreateService.findBySourceHistory(data.history.Id)
      );
      System.assertEquals(
        null,
        RenewOpportunityCreateService.findBySourceHistory(null)
      );
    }
  }

  @IsTest
  static void createFromOrderedHistory_templateWithDateFormat() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createOrderedHistoryData();
      RenewOpportunityCreateService.resetCache();
      List<RenewOpportunityField__mdt> definitions = baseCreateDefinitions();
      for (Integer i = 0; i < definitions.size(); i++) {
        if (definitions[i].TargetFieldApiName__c == 'Name') {
          definitions[i] = new RenewOpportunityField__mdt(
            DeveloperName = 'Name',
            Active__c = true,
            TargetFieldApiName__c = 'Name',
            ValueType__c = 'Template',
            Value__c = '{Account.Name}_{ContractHistory__c.CurrentTermEndDate__c:yyyyMM} 更新',
            DateFormat__c = 'yyyy-MM-dd'
          );
        }
      }
      RenewOpportunityCreateService.cachedDefinitions = definitions;

      Test.startTest();
      Id renewOppId = RenewOpportunityCreateService.createFromOrderedHistory(
        data.history.Id
      );
      Test.stopTest();

      Opportunity created = [
        SELECT Name
        FROM Opportunity
        WHERE Id = :renewOppId
      ];
      System.assertEquals(
        data.account.Name + '_202605 更新',
        created.Name
      );
    }
  }

  @IsTest
  static void createFromOrderedHistory_nullId_throws() {
    Boolean thrown = false;
    try {
      RenewOpportunityCreateService.createFromOrderedHistory(null);
    } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
      thrown = true;
      System.assertEquals(
        '契約履歴 Id が指定されていません。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void validateActiveDefinitions_rejectsBadFieldPath() {
    RenewOpportunityCreateService.resetCache();
    RenewOpportunityCreateService.cachedDefinitions = new List<RenewOpportunityField__mdt>{
      new RenewOpportunityField__mdt(
        DeveloperName = 'BadPath',
        Active__c = true,
        TargetFieldApiName__c = 'Name',
        ValueType__c = 'Field',
        Value__c = 'Account'
      )
    };
    Boolean thrown = false;
    try {
      RenewOpportunityCreateService.validateActiveDefinitions();
    } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
      thrown = true;
      System.assertEquals(
        '更新商談項目「BadPath」: 参照パス「Account」は ObjectApiName.FieldApiName 形式（ドット1つ）である必要があります。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void validateActiveDefinitions_rejectsDuplicateTarget() {
    RenewOpportunityCreateService.resetCache();
    RenewOpportunityCreateService.cachedDefinitions = new List<RenewOpportunityField__mdt>{
      stageDefinition(),
      new RenewOpportunityField__mdt(
        DeveloperName = 'StageName2',
        Active__c = true,
        TargetFieldApiName__c = 'StageName',
        ValueType__c = 'Constant',
        Value__c = firstActiveStageName()
      )
    };
    Boolean thrown = false;
    try {
      RenewOpportunityCreateService.validateActiveDefinitions();
    } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
      thrown = true;
      System.assertEquals(
        '更新商談項目「StageName2」: セット先項目「StageName」の Active 定義が重複しています。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void validateActiveDefinitions_rejectsBadDateFormatAndTemplate() {
    RenewOpportunityCreateService.resetCache();
    RenewOpportunityCreateService.cachedDefinitions = new List<RenewOpportunityField__mdt>{
      new RenewOpportunityField__mdt(
        DeveloperName = 'BadDateFormat',
        Active__c = true,
        TargetFieldApiName__c = 'Name',
        ValueType__c = 'Template',
        Value__c = '{Account.Name}',
        DateFormat__c = 'yyyyMMdd'
      )
    };
    Boolean thrown = false;
    try {
      RenewOpportunityCreateService.validateActiveDefinitions();
    } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
      thrown = true;
      System.assertEquals(
        '更新商談項目「BadDateFormat」: 日付書式「yyyyMMdd」は許可されていません。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);

    RenewOpportunityCreateService.cachedDefinitions = new List<RenewOpportunityField__mdt>{
      new RenewOpportunityField__mdt(
        DeveloperName = 'BadToken',
        Active__c = true,
        TargetFieldApiName__c = 'Name',
        ValueType__c = 'Template',
        Value__c = '{Account.Name'
      )
    };
    thrown = false;
    try {
      RenewOpportunityCreateService.validateActiveDefinitions();
    } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
      thrown = true;
      System.assertEquals(
        '更新商談項目「BadToken」: テンプレートのトークン形式が不正です（{ObjectApiName.FieldApiName} または {ObjectApiName.FieldApiName:日付書式}）。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void createFromOrderedHistory_blankOwner_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createOrderedHistoryData();
      RenewOpportunityCreateService.resetCache();
      RenewOpportunityCreateService.cachedDefinitions = new List<RenewOpportunityField__mdt>{
        nameDefinition(),
        closeDateDefinition(),
        stageDefinition(),
        new RenewOpportunityField__mdt(
          DeveloperName = 'OwnerId',
          Active__c = true,
          TargetFieldApiName__c = 'OwnerId',
          ValueType__c = 'Field',
          Value__c = 'Account.Description'
        )
      };

      Boolean thrown = false;
      try {
        RenewOpportunityCreateService.createFromOrderedHistory(data.history.Id);
      } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
        thrown = true;
        System.assertEquals(
          '更新商談項目「OwnerId」: OwnerId にセットするユーザIDが空です。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void createFromOrderedHistory_fieldDateToTextUsesDateFormat() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createOrderedHistoryData();
      RenewOpportunityCreateService.resetCache();
      List<RenewOpportunityField__mdt> definitions = baseCreateDefinitions();
      for (Integer i = 0; i < definitions.size(); i++) {
        if (definitions[i].TargetFieldApiName__c == 'Name') {
          definitions[i] = new RenewOpportunityField__mdt(
            DeveloperName = 'Name',
            Active__c = true,
            TargetFieldApiName__c = 'Name',
            ValueType__c = 'Field',
            Value__c = 'ContractHistory__c.CurrentTermEndDate__c',
            DateFormat__c = 'yyyy/MM'
          );
        }
      }
      RenewOpportunityCreateService.cachedDefinitions = definitions;

      Test.startTest();
      Id renewOppId = RenewOpportunityCreateService.createFromOrderedHistory(
        data.history.Id
      );
      Test.stopTest();

      Opportunity created = [
        SELECT Name
        FROM Opportunity
        WHERE Id = :renewOppId
      ];
      System.assertEquals('2026/05', created.Name);
    }
  }

  private class TestData {
    public Account account;
    public Opportunity opportunity;
    public ContractService__c service;
    public ContractHistory__c history;
  }

  private static TestData createOrderedHistoryData() {
    return createOrderedHistoryData(ContractDomainConstants.LIFECYCLE_TERM);
  }

  private static TestData createOrderedHistoryData(String lifecycle) {
    TestData data = new TestData();
    data.account = ContractTestDataFactory.insertAccount('更新商談テスト取引先');
    data.opportunity = ContractTestDataFactory.insertOpportunity(
      data.account.Id,
      'Source Opportunity'
    );
    data.service = ContractTestDataFactory.insertContractService(
      data.account.Id,
      'Renew Opp Source Service'
    );
    // 受注後の Lifecycle 変更は VR で不可。更新商談テストは Term、Spot 拒否テストは Spot。
    if (String.isNotBlank(lifecycle)) {
      update new ContractService__c(
        Id = data.service.Id,
        Lifecycle__c = lifecycle
      );
    }

    Date termStart = Date.newInstance(2025, 6, 1);
    Date termEnd = Date.newInstance(2026, 5, 31);
    data.history = new ContractHistory__c(
      Name = 'Ordered History',
      ContractService__c = data.service.Id,
      Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
      historystatus__c = ContractDomainConstants.HISTORY_STATUS_ORDERED,
      Version__c = 1,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      Opportunity__c = data.opportunity.Id
    );
    insert data.history;
    return data;
  }

  private static void stubStandardDefinitions() {
    RenewOpportunityCreateService.resetCache();
    RenewOpportunityCreateService.cachedDefinitions = baseCreateDefinitions();
  }

  /** テナント VR（Contact 必須等）を満たすよう元商談からコピーする定義込み */
  private static List<RenewOpportunityField__mdt> baseCreateDefinitions() {
    List<RenewOpportunityField__mdt> definitions = new List<RenewOpportunityField__mdt>{
      nameDefinition(),
      closeDateDefinition(),
      stageDefinition(),
      fieldCopyDefinition('ContactId', 'Opportunity.ContactId')
    };
    Map<String, Schema.SObjectField> fields = Schema.SObjectType.Opportunity.fields.getMap();
    if (fields.containsKey('RecordTypeId')) {
      definitions.add(
        fieldCopyDefinition('RecordTypeId', 'Opportunity.RecordTypeId')
      );
    }
    if (fields.containsKey('OpportunityCreater__c')) {
      definitions.add(
        fieldCopyDefinition(
          'OpportunityCreater',
          'Opportunity.OpportunityCreater__c'
        )
      );
    }
    if (fields.containsKey('CustomFieldDefinition9__c')) {
      definitions.add(
        fieldCopyDefinition(
          'CustomFieldDefinition9',
          'Opportunity.CustomFieldDefinition9__c'
        )
      );
    }
    return definitions;
  }

  private static RenewOpportunityField__mdt fieldCopyDefinition(
    String developerName,
    String fieldPath
  ) {
    String targetField = fieldPath.substringAfter('.');
    return new RenewOpportunityField__mdt(
      DeveloperName = developerName,
      Active__c = true,
      TargetFieldApiName__c = targetField,
      ValueType__c = 'Field',
      Value__c = fieldPath
    );
  }

  private static RenewOpportunityField__mdt nameDefinition() {
    return new RenewOpportunityField__mdt(
      DeveloperName = 'Name',
      Active__c = true,
      TargetFieldApiName__c = 'Name',
      ValueType__c = 'Template',
      Value__c = '{Account.Name} 更新'
    );
  }

  private static RenewOpportunityField__mdt closeDateDefinition() {
    return new RenewOpportunityField__mdt(
      DeveloperName = 'CloseDate',
      Active__c = true,
      TargetFieldApiName__c = 'CloseDate',
      ValueType__c = 'Field',
      Value__c = 'ContractHistory__c.CurrentTermEndDate__c'
    );
  }

  private static RenewOpportunityField__mdt stageDefinition() {
    return new RenewOpportunityField__mdt(
      DeveloperName = 'StageName',
      Active__c = true,
      TargetFieldApiName__c = 'StageName',
      ValueType__c = 'Constant',
      Value__c = firstActiveStageName()
    );
  }

  private static String firstActiveStageName() {
    for (
      Schema.PicklistEntry entry : Opportunity.StageName.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive()) {
        return entry.getValue();
      }
    }
    return 'Prospecting';
  }
}
