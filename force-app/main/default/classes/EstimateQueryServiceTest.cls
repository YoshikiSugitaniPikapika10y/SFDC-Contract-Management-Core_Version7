@IsTest
private class EstimateQueryServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void getRecurringContractProducts_nullId_returnsEmpty() {
    List<EstimateCreateController.ContractProductLineDto> results = EstimateQueryService.getRecurringContractProducts(
      null
    );
    System.assertEquals(
      0,
      results.size(),
      'Core 第4.3節: 契約履歴Idが無い継続課金照会は空'
    );
  }

  @IsTest
  static void getRecurringContractProducts_blankUnit_doesNotFillFromProduct2() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractProductFixture fixture = insertBlankUnitProduct('Remake');
      List<EstimateCreateController.ContractProductLineDto> results = EstimateQueryService.getRecurringContractProducts(
        fixture.history.Id
      );
      System.assertEquals(1, results.size());
      System.assertEquals(
        null,
        results[0].unit,
        'Core 第4.5.2節・第4.7節・第1.1.10節: 空の単位を商品マスタから埋めない'
      );
      System.assertEquals('ライセンス', results[0].unitName);
    }
  }

  @IsTest
  static void toCopyProductLineItem_originalBlankUnit_doesNotFillFromProduct2() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractProduct__c product = blankUnitInMemoryProduct('Original');
      EstimateCreateController.ProductLineItem line = EstimateQueryService.toCopyProductLineItem(
        product,
        'Change',
        new Map<Id, String>()
      );
      System.assertEquals(
        null,
        line.unit,
        'Core 第4.5.2節・第4.7節・第1.1.10節: Originalの空単位を商品マスタから埋めない'
      );
    }
  }

  @IsTest
  static void toCopyProductLineItem_remakeBlankUnit_doesNotFillFromProduct2() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractProduct__c product = blankUnitInMemoryProduct('Remake');
      EstimateCreateController.ProductLineItem line = EstimateQueryService.toCopyProductLineItem(
        product,
        'Change',
        new Map<Id, String>()
      );
      System.assertEquals(
        null,
        line.unit,
        'Core 第4.5.2節・第4.7節・第1.1.10節: Remakeの空単位を商品マスタから埋めない'
      );
    }
  }

  @IsTest
  static void toCopyProductLineItem_renewBlankUnit_doesNotFillFromProduct2() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractProduct__c product = blankUnitInMemoryProduct('Renew');
      EstimateCreateController.ProductLineItem line = EstimateQueryService.toCopyProductLineItem(
        product,
        'Renew',
        new Map<Id, String>()
      );
      System.assertEquals(
        null,
        line.unit,
        'Core 第4.5.2節・第4.7節・第1.1.10節: Renewの空単位を商品マスタから埋めない'
      );
    }
  }

  @IsTest
  static void toContractProductLineDtos_keepsSavedBlankUnit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractProduct__c product = blankUnitInMemoryProduct('New');
      List<EstimateCreateController.ContractProductLineDto> lines = EstimateQueryService.toContractProductLineDtos(
        new List<ContractProduct__c>{ product }
      );
      System.assertEquals(1, lines.size());
      System.assertEquals(
        null,
        lines[0].unit,
        'Core 第4.5.2節・第4.7節・第1.1.10節: 照会DTOの空単位を商品マスタから埋めない'
      );
    }
  }

  @IsTest
  static void getRenewContractProducts_nullOrCancel_returnsEmpty() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        0,
        EstimateQueryService.getRenewContractProducts(null).size(),
        'Core 第4.3節: 契約サービスIdが無いRenew照会は空'
      );
      Account account = ContractTestDataFactory.insertAccount('Query Renew Acc');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query Renew Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c cancel = new ContractHistory__c(
        Name = 'Query Renew Cancel',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Type__c = 'Cancel',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(cancel, account.Id);
      insert cancel;
      System.assertEquals(
        0,
        EstimateQueryService.getRenewContractProducts(service.Id).size(),
        'Core 第4.3.3節: CancelのLatest OrderedはRenew継承元にしない'
      );
    }
  }

  @IsTest
  static void getLatestAndInfo_nullAndTermDates() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        null,
        EstimateQueryService.getLatestContractHistory(null),
        'Core 第4.3節: 契約サービスIdが無い最新履歴は空'
      );
      System.assertEquals(
        null,
        EstimateQueryService.getContractHistoryInfo(null),
        'Core 第4.3節: 契約履歴Idが無い照会は空'
      );
      Account account = ContractTestDataFactory.insertAccount('Query Info Acc');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query Info Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Query Info Ordered',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Type__c = 'New',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      insert history;
      EstimateCreateController.ContractHistoryDto latest = EstimateQueryService.getLatestContractHistory(
        service.Id
      );
      System.assertEquals(history.Id, latest.historyId);
      System.assertEquals(
        String.valueOf(termStart),
        latest.termStartDate,
        'Core 第4.3節: 最新受注の期間開始を返す'
      );
      System.assertEquals(
        String.valueOf(termEnd),
        latest.termEndDate,
        'Core 第4.3節: 最新受注の期間終了を返す'
      );
      EstimateCreateController.ContractHistoryDto info = EstimateQueryService.getContractHistoryInfo(
        history.Id
      );
      System.assertEquals(history.Id, info.historyId);
      System.assertEquals('Query Info Ordered', info.historyName);
    }
  }

  @IsTest
  static void getEstimateCopyPreset_nullAndMissing_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean nullThrown = false;
      try {
        EstimateQueryService.getEstimateCopyPreset(null);
      } catch (AuraHandledException ex) {
        nullThrown = true;
        System.assertEquals(
          'コピー元の契約履歴が指定されていません。',
          ex.getMessage(),
          'Core 第4.7節: コピー元Idが空なら指定なしで拒否'
        );
      }
      System.assertEquals(true, nullThrown);
      Boolean editNullThrown = false;
      try {
        EstimateQueryService.getEstimateEditPreset(null);
      } catch (AuraHandledException ex) {
        editNullThrown = true;
        System.assertEquals(
          '編集元の契約履歴が指定されていません。',
          ex.getMessage(),
          'Core 第4.7節: 編集元Idが空なら指定なしで拒否'
        );
      }
      System.assertEquals(true, editNullThrown);
      Boolean missingThrown = false;
      try {
        EstimateQueryService.getEstimateCopyPreset(
          ContractHistory__c.SObjectType.getDescribe().getKeyPrefix() +
            '000000000001'
        );
      } catch (AuraHandledException ex) {
        missingThrown = true;
        System.assertEquals(
          '契約履歴が見つかりません。',
          ex.getMessage(),
          'Core 第4.7節: 契約履歴が無ければ拒否'
        );
      }
      System.assertEquals(true, missingThrown);
    }
  }

  @IsTest
  static void getEstimateCopyPreset_newKeepsHistoryNameWithoutCopySuffix() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Query Copy Acc');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query Copy Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Query Copy Source',
        ContractService__c = service.Id,
        historystatus__c = 'Estimate',
        Type__c = 'New',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart,
        Note__c = 'コピー元備考'
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      insert history;
      EstimateCreateController.EstimateCopyPresetDto preset = EstimateQueryService.getEstimateCopyPreset(
        history.Id
      );
      System.assertEquals(
        'Query Copy Sourceのコピー',
        preset.contractHistoryName,
        'Core 第4.3.3節・第4.7節: コピーの履歴名は元名のコピー'
      );
      System.assertEquals(
        'Query Copy Serviceのコピー',
        preset.contractServiceName,
        'Core 第4.3.3節・第4.7節: Newコピーの契約サービス名は元名のコピー'
      );
      System.assertEquals(null, preset.contractServiceId);
      System.assertEquals(
        null,
        preset.serviceLifecycle,
        'Core 第4.7節: Newコピーは新しい契約サービスとして扱う'
      );
      System.assertEquals('コピー元備考', preset.estimateRemarks);
      System.assertEquals(
        true,
        preset.contractCustomFieldsExpanded,
        'Core 第4.3.4節: 契約のカスタム項目パネルはデフォルト開'
      );
    }
  }

  @IsTest
  static void getEstimateCopyPreset_changeNameEmpty_cancelNameIsCopyWithoutChurnSuffix() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Query Name Acc'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query Name Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c previous = new ContractHistory__c(
        Name = 'Query Name Ordered',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Type__c = 'New',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        previous,
        account.Id
      );
      insert previous;
      ContractHistory__c changeEstimate = new ContractHistory__c(
        Name = 'Query Name Change',
        ContractService__c = service.Id,
        historystatus__c = 'Estimate',
        Type__c = 'Change',
        Version__c = 2,
        PreviousHistory__c = previous.Id,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = null
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        changeEstimate,
        account.Id
      );
      insert changeEstimate;
      EstimateCreateController.EstimateCopyPresetDto changePreset = EstimateQueryService.getEstimateCopyPreset(
        changeEstimate.Id
      );
      System.assertEquals(
        'Query Name Changeのコピー',
        changePreset.contractHistoryName,
        'Core 第4.3.3節: コピーの履歴名は元名のコピー'
      );
      System.assertEquals(
        'Query Name Service',
        changePreset.contractServiceName,
        'Core 第4.3.3節: Changeコピーのサービス名は元名'
      );
      System.assertEquals(
        true,
        String.isBlank(changePreset.contractEffectiveDate),
        'Core 第4.7節・第1.1.10節: 空の切替日を開始日で埋めない'
      );
      System.assertEquals(service.Id, changePreset.contractServiceId);

      ContractHistory__c cancelEstimate = new ContractHistory__c(
        Name = 'Query Name Cancel Est',
        ContractService__c = service.Id,
        historystatus__c = 'Estimate',
        Type__c = 'Cancel',
        Version__c = 3,
        PreviousHistory__c = previous.Id,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        cancelEstimate,
        account.Id
      );
      insert cancelEstimate;
      EstimateCreateController.EstimateCopyPresetDto cancelPreset = EstimateQueryService.getEstimateCopyPreset(
        cancelEstimate.Id
      );
      System.assertEquals(
        'Query Name Cancel Estのコピー',
        cancelPreset.contractHistoryName,
        'Core 第4.3.3節: コピーの履歴名は元名のコピー'
      );
      System.assertEquals(
        'Query Name Service',
        cancelPreset.contractServiceName,
        'Core 第4.3.3節: Cancelコピーのサービス名は元名'
      );
      System.assertEquals(
        false,
        cancelPreset.contractHistoryName.contains('解約'),
        'Core 第4.3.3節: 作成・コピーの履歴名初期値に解約を付けない'
      );
    }
  }

  @IsTest
  static void getEstimateCopyPreset_rejectsNonEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Query Reject Acc'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query Reject Service'
      );
      ContractHistory__c ordered = new ContractHistory__c(
        Name = 'Query Reject Ordered',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Type__c = 'New',
        Version__c = 1
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        ordered,
        account.Id
      );
      insert ordered;
      Boolean thrown = false;
      try {
        EstimateQueryService.getEstimateCopyPreset(ordered.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '見積状態の契約履歴のみコピーできます。',
          ex.getMessage(),
          'Core 第4.7節: コピー元はEstimateだけ'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getEstimateEditPreset_rejectsArchive() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Query Edit Acc'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query Edit Service'
      );
      ContractHistory__c archived = new ContractHistory__c(
        Name = 'Query Edit Archive',
        ContractService__c = service.Id,
        historystatus__c = 'Archive',
        Type__c = 'New',
        Version__c = 1
      );
      insert archived;
      Boolean thrown = false;
      try {
        EstimateQueryService.getEstimateEditPreset(archived.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '見積／受注済み状態の契約履歴のみ編集できます。',
          ex.getMessage(),
          'Core 第4.7節: Archiveは編集できない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getEstimateEditPreset_estimateKeepsServiceAndVersion() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Query EditKeep Acc'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query EditKeep Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Query EditKeep Est',
        ContractService__c = service.Id,
        historystatus__c = 'Estimate',
        Type__c = 'New',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      insert history;
      EstimateCreateController.EstimateCopyPresetDto preset = EstimateQueryService.getEstimateEditPreset(
        history.Id
      );
      System.assertEquals(
        service.Id,
        preset.contractServiceId,
        'Core 第4.7節: Estimate編集は既存の契約サービスを維持する'
      );
      System.assertEquals(
        1,
        preset.nextHistoryVersion,
        'Core 第4.3.3節: 編集は既存Versionを維持する'
      );
      System.assertEquals('Query EditKeep Est', preset.contractHistoryName);
    }
  }

  @IsTest
  static void getEstimateEditPreset_orderedReusesLoadedHistoryForOrderFields() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Query OrderedPreset Acc'
      );
      ContractService__c estimateService = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query OrderedPreset Est Svc'
      );
      ContractService__c orderedService = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query OrderedPreset Ord Svc'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date applicationDate = termStart.addDays(1);
      Date orderDate = termStart.addDays(2);
      ContractHistory__c estimateHistory = new ContractHistory__c(
        Name = 'Query OrderedPreset Est',
        ContractService__c = estimateService.Id,
        historystatus__c = 'Estimate',
        Type__c = 'New',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        estimateHistory,
        account.Id
      );
      insert estimateHistory;
      ContractHistory__c orderedHistory = new ContractHistory__c(
        Name = 'Query OrderedPreset Ord',
        ContractService__c = orderedService.Id,
        historystatus__c = 'Ordered',
        Type__c = 'New',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart,
        ApplicationDate__c = applicationDate,
        OrderDate__c = orderDate
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        orderedHistory,
        account.Id
      );
      insert orderedHistory;

      Test.startTest();
      OrderWizardFieldService.getActiveOrderHistoryFieldApiNames();
      ContractWizardFieldService.getActiveFieldApiNames(
        ContractWizardFieldService.WizardTarget.ContractHistory
      );
      Integer estimateBefore = Limits.getQueries();
      EstimateCreateController.getEstimateEditPreset(estimateHistory.Id);
      Integer estimateUsed = Limits.getQueries() - estimateBefore;
      Integer orderedBefore = Limits.getQueries();
      EstimateCreateController.EstimateCopyPresetDto orderedPreset = EstimateCreateController.getEstimateEditPreset(
        orderedHistory.Id
      );
      Integer orderedUsed = Limits.getQueries() - orderedBefore;
      Test.stopTest();

      System.assertEquals(
        estimateUsed,
        orderedUsed,
        'Core 第4.3.11節・第12.4節: 1回の取得リクエストの内部で対象の契約履歴を取り直さない'
      );
      System.assertEquals(
        String.valueOf(applicationDate),
        String.valueOf(
          orderedPreset.contractHistoryCustomFields.get('ApplicationDate__c')
        ),
        'Core 第11.4.3節: Ordered見積編集の初期値は保存済みの受注追加項目'
      );
      System.assertEquals(
        String.valueOf(orderDate),
        String.valueOf(
          orderedPreset.contractHistoryCustomFields.get('OrderDate__c')
        ),
        'Core 第11.4.3節: Ordered見積編集の初期値は保存済みの受注日'
      );
    }
  }

  @IsTest
  static void getEstimateCopyPreset_changeReusesLoadedPreviousAsLatestOrdered() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Query LatestReuse Acc'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query LatestReuse Svc'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c previous = new ContractHistory__c(
        Name = 'Query LatestReuse Ordered',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Type__c = 'New',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        previous,
        account.Id
      );
      insert previous;
      Product2 catalog = ContractTestDataFactory.buildProduct(
        'Query LatestReuse Product'
      );
      catalog.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      catalog.UnitName__c = 'ライセンス';
      ContractTestDataFactory.insertProduct(catalog);
      insert new ContractProduct__c(
        ContractHistory__c = previous.Id,
        Product__c = catalog.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        Type__c = 'New',
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
      );
      ContractHistory__c changeEstimate = new ContractHistory__c(
        Name = 'Query LatestReuse Change',
        ContractService__c = service.Id,
        historystatus__c = 'Estimate',
        Type__c = 'Change',
        Version__c = 2,
        PreviousHistory__c = previous.Id,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        changeEstimate,
        account.Id
      );
      insert changeEstimate;

      Test.startTest();
      InvoiceProductFieldCopyService.getSourceFieldApiNames(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY
      );
      ContractWizardFieldService.getActiveFieldApiNames(
        ContractWizardFieldService.WizardTarget.ContractHistory
      );
      EstimateQueryService.lastLatestOrderedQueryIds = new Set<Id>();
      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateCopyPreset(
        changeEstimate.Id
      );
      Set<Id> queriedLatestIds = EstimateQueryService.lastLatestOrderedQueryIds;
      Test.stopTest();

      System.assertEquals(
        false,
        queriedLatestIds.contains(previous.Id),
        'Core 第4.3.11節・第12.4節: 1回の取得リクエストの内部で対象の契約履歴を取り直さない'
      );
      System.assertEquals(
        2,
        preset.nextHistoryVersion,
        'Core 第4.3節: コピーの Version は最新 Ordered + 1'
      );
      System.assertEquals(
        'Query LatestReuse Ordered',
        preset.autoHistoryName,
        'Core 第4.3.3節: Changeコピーの履歴名初期値は前回履歴'
      );
      System.assertEquals(
        true,
        preset.renewEligible,
        'Core 第4.3.3節: 期末継続課金があれば更新可'
      );
    }
  }

  @IsTest
  static void getEstimateEditPreset_changeReusesLoadedPreviousAsLatestOrdered() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Query LatestEdit Acc'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query LatestEdit Svc'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c previous = new ContractHistory__c(
        Name = 'Query LatestEdit Prev',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Type__c = 'New',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        previous,
        account.Id
      );
      insert previous;
      ContractHistory__c changeEstimate = new ContractHistory__c(
        Name = 'Query LatestEdit Change',
        ContractService__c = service.Id,
        historystatus__c = 'Estimate',
        Type__c = 'Change',
        Version__c = 2,
        PreviousHistory__c = previous.Id,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        changeEstimate,
        account.Id
      );
      insert changeEstimate;

      Test.startTest();
      InvoiceProductFieldCopyService.getSourceFieldApiNames(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY
      );
      ContractWizardFieldService.getActiveFieldApiNames(
        ContractWizardFieldService.WizardTarget.ContractHistory
      );
      EstimateQueryService.lastLatestOrderedQueryIds = new Set<Id>();
      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateEditPreset(
        changeEstimate.Id
      );
      Set<Id> queriedLatestIds = EstimateQueryService.lastLatestOrderedQueryIds;
      Test.stopTest();

      System.assertEquals(
        false,
        queriedLatestIds.contains(previous.Id),
        'Core 第4.3.11節・第12.4節: 1回の取得リクエストの内部で対象の契約履歴を取り直さない'
      );
      System.assertEquals(
        2,
        preset.nextHistoryVersion,
        'Core 第4.3.3節: 編集は既存Versionを維持する'
      );
      System.assertEquals(
        'Query LatestEdit Prev',
        preset.autoHistoryName,
        'Core 第4.3.3節: Change編集の履歴名初期値は前回履歴'
      );
    }
  }

  @IsTest
  static void getEstimateEditPreset_changeReusesCountedPreviousProductsForRenewEligible() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Query CountReuse Acc'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query CountReuse Svc'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c previous = new ContractHistory__c(
        Name = 'Query CountReuse Prev',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Type__c = 'New',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        previous,
        account.Id
      );
      insert previous;
      Product2 catalog = ContractTestDataFactory.buildProduct(
        'Query CountReuse Product'
      );
      catalog.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      catalog.UnitName__c = 'ライセンス';
      ContractTestDataFactory.insertProduct(catalog);
      insert new ContractProduct__c(
        ContractHistory__c = previous.Id,
        Product__c = catalog.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        Type__c = 'New',
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
      );
      ContractHistory__c changeEstimate = new ContractHistory__c(
        Name = 'Query CountReuse Change',
        ContractService__c = service.Id,
        historystatus__c = 'Estimate',
        Type__c = 'Change',
        Version__c = 2,
        PreviousHistory__c = previous.Id,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        changeEstimate,
        account.Id
      );
      insert changeEstimate;

      Test.startTest();
      InvoiceProductFieldCopyService.getSourceFieldApiNames(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY
      );
      ContractWizardFieldService.getActiveFieldApiNames(
        ContractWizardFieldService.WizardTarget.ContractHistory
      );
      EstimateQueryService.lastRenewEligibleProductLoadIds = new Set<Id>();
      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateEditPreset(
        changeEstimate.Id
      );
      Set<Id> loadedProductHistoryIds = EstimateQueryService.lastRenewEligibleProductLoadIds;
      Test.stopTest();

      System.assertEquals(
        false,
        loadedProductHistoryIds.contains(previous.Id),
        'Core 第4.3.11節・第12.4節: 1回の取得リクエストの内部で対象の見積商品を取り直さない'
      );
      System.assertEquals(
        true,
        preset.renewEligible,
        'Core 第4.3.3節: 期末継続課金があれば更新可'
      );
    }
  }

  @IsTest
  static void getEstimateEditPreset_orderedChangeReusesLoadedProductsForRenewEligible() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.ensureOrgAccountingPolicy();
      Account account = ContractTestDataFactory.insertAccount(
        'Query OrderedProdReuse Acc'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query OrderedProdReuse Svc'
      );
      service.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
      update service;
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c previous = new ContractHistory__c(
        Name = 'Query OrderedProdReuse Prev',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Type__c = 'New',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        previous,
        account.Id
      );
      insert previous;
      Product2 catalog = ContractTestDataFactory.buildProduct(
        'Query OrderedProdReuse Product'
      );
      catalog.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      catalog.UnitName__c = 'ライセンス';
      ContractTestDataFactory.insertProduct(catalog);
      ContractProduct__c previousProduct = new ContractProduct__c(
        ContractHistory__c = previous.Id,
        Product__c = catalog.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        Type__c = 'New',
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
      );
      insert previousProduct;
      ContractHistory__c orderedChange = new ContractHistory__c(
        Name = 'Query OrderedProdReuse Change',
        ContractService__c = service.Id,
        historystatus__c = 'Estimate',
        Type__c = 'Change',
        Version__c = 2,
        PreviousHistory__c = previous.Id,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        orderedChange,
        account.Id
      );
      insert orderedChange;
      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = orderedChange.Id,
          Product__c = catalog.Id,
          Quantity__c = 1,
          UnitPrice__c = 1000,
          Amount__c = -1000,
          Type__c = 'Original',
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          PreviousContractProduct__c = previousProduct.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = orderedChange.Id,
          Product__c = catalog.Id,
          Quantity__c = 1,
          UnitPrice__c = 2000,
          Amount__c = 2000,
          Type__c = 'Remake',
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          PreviousContractProduct__c = previousProduct.Id
        )
      };
      orderedChange.historystatus__c = 'Ordered';
      update orderedChange;

      Test.startTest();
      InvoiceProductFieldCopyService.getSourceFieldApiNames(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY
      );
      ContractWizardFieldService.getActiveFieldApiNames(
        ContractWizardFieldService.WizardTarget.ContractHistory
      );
      EstimateQueryService.lastRenewEligibleProductLoadIds = new Set<Id>();
      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateEditPreset(
        orderedChange.Id
      );
      Set<Id> loadedProductHistoryIds = EstimateQueryService.lastRenewEligibleProductLoadIds;
      Test.stopTest();

      System.assertEquals(
        false,
        loadedProductHistoryIds.contains(orderedChange.Id),
        'Core 第4.3.11節・第12.4節: 1回の取得リクエストの内部で対象の見積商品を取り直さない'
      );
      System.assertEquals(
        true,
        preset.renewEligible,
        'Core 第4.3.3節: 期末継続課金があれば更新可'
      );
      System.assertEquals(
        2,
        preset.selectedProducts.size(),
        'Core 第4.3.11節: 照会回数のために明細初期値を変えない'
      );
      System.assertEquals(
        'Query OrderedProdReuse Product',
        preset.selectedProducts[0].productName,
        'Core 第4.3.11節: 読んだ対象見積商品を初期値にする'
      );
    }
  }

  @IsTest
  static void getProductDefaults_rejectsUnavailable_andReturnsAvailable() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        null,
        EstimateQueryService.getProductDefaults(null),
        'Core 第4.3.7節: 商品Idが無い初期値は空'
      );
      Product2 unavailable = new Product2(
        Name = 'Query Unavailable Product',
        IsActive = true,
        AvailableForContract__c = false
      );
      insert unavailable;
      Boolean thrown = false;
      try {
        EstimateQueryService.getProductDefaults(unavailable.Id);
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          '[EST-S3-New-026] 契約管理で利用可能な商品のみ選択できます。',
          ex.getMessage(),
          'Core 第4.3.7節: 契約利用不可の商品は拒否する'
        );
      }
      System.assertEquals(true, thrown);

      Product2 available = ContractTestDataFactory.buildProduct(
        'Query Available Product'
      );
      available.UnitName__c = 'ライセンス';
      available.UnitPrice__c = 8000;
      available.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      available.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(available);
      EstimateCreateController.ProductDefaultDto dto = EstimateQueryService.getProductDefaults(
        available.Id
      );
      System.assertEquals('Query Available Product', dto.productName);
      System.assertEquals(
        'ライセンス',
        dto.unitName,
        'Core 第4.3.7節: 利用可能商品の単位を初期値にする'
      );
      System.assertEquals(8000, dto.unitPrice);
    }
  }

  @IsTest
  static void getActiveContractServicesByAccount_skipsBlankLifecycle() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        0,
        EstimateQueryService.getActiveContractServicesByAccount(null).size(),
        'Core 第4.3.3節: 取引先Idが無い契約サービス候補は空'
      );
      Account account = ContractTestDataFactory.insertAccount(
        'Query Lifecycle Acc'
      );
      ContractService__c estimateOnly = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query Estimate Only'
      );
      ContractService__c blankOrdered = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query Blank Lifecycle',
        null
      );
      ContractService__c termService = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query Term Lifecycle'
      );
      termService.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
      update termService;
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c estimateHistory = new ContractHistory__c(
        Name = 'Query Est Only V1',
        ContractService__c = estimateOnly.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        estimateHistory,
        account.Id
      );
      ContractHistory__c blankHistory = new ContractHistory__c(
        Name = 'Query Blank Ordered V1',
        ContractService__c = blankOrdered.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        blankHistory,
        account.Id
      );
      ContractHistory__c termHistory = new ContractHistory__c(
        Name = 'Query Term V1',
        ContractService__c = termService.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        termHistory,
        account.Id
      );
      insert new List<ContractHistory__c>{
        estimateHistory,
        blankHistory,
        termHistory
      };

      Product2 recurring = ContractTestDataFactory.buildProduct(
        'Query Current Product'
      );
      recurring.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(recurring);
      insert new ContractProduct__c(
        ContractHistory__c = termHistory.Id,
        Product__c = recurring.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        Type__c = 'New'
      );

      List<EstimateCreateController.ContractServiceOptionDto> services = EstimateQueryService.getActiveContractServicesByAccount(
        account.Id
      );
      Set<Id> ids = new Set<Id>();
      String currentNames = null;
      for (
        EstimateCreateController.ContractServiceOptionDto option : services
      ) {
        ids.add(option.id);
        if (option.id == termService.Id) {
          currentNames = option.currentProductNames;
        }
      }
      System.assertEquals(
        false,
        ids.contains(estimateOnly.Id),
        'Core 第4.3.3節: 未受注サービスは候補に出さない'
      );
      System.assertEquals(
        false,
        ids.contains(blankOrdered.Id),
        'Core 第4.3.3節: Lifecycle未設定の受注済みサービスは候補に出さない'
      );
      System.assertEquals(
        true,
        ids.contains(termService.Id),
        'Core 第4.3.3節: Lifecycle=Termの受注済みサービスを候補にする'
      );
      System.assertEquals(
        'Query Current Product',
        currentNames,
        'Core 第4.3.3節: 期間契約の現商品名を載せる'
      );
    }
  }

  @IsTest
  static void getBillingAccountInvoiceSettings_readsLatestMaster() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateCreateController.BillingAccountInvoiceSettingsDto empty = EstimateQueryService.getBillingAccountInvoiceSettings(
        (Id) null
      );
      System.assertEquals(
        true,
        empty.billingCustomFields.isEmpty() ||
          empty.billingCustomFields.get('BillingAddressee__c') == null,
        'Core 第5.2節: 請求アカウントIdが無い確認は空'
      );
      Account account = ContractTestDataFactory.insertAccount(
        'Query Billing Acc'
      );
      BillingAccount__c billing = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );
      billing.BillingAddressee__c = '照会宛名';
      billing.BillingEmailTo__c = 'query-to@example.com';
      update billing;
      EstimateCreateController.BillingAccountInvoiceSettingsDto dto = EstimateQueryService.getBillingAccountInvoiceSettings(
        billing.Id
      );
      System.assertEquals(
        '照会宛名',
        dto.billingCustomFields.get('BillingAddressee__c'),
        'Core 第5.2節: 受注画面は請求アカウントの最新の宛名を読む'
      );
      System.assertEquals(
        'query-to@example.com',
        dto.billingCustomFields.get('BillingEmailTo__c'),
        'Core 第5.2節: 受注画面は請求アカウントの最新のToを読む'
      );
      System.assertEquals(
        InvoiceDeliveryMethodService.EMAIL,
        dto.billingCustomFields.get('InvoiceDeliveryMethod__c'),
        'Core 第5.2節: 送付の届け方を読む'
      );
      System.assertEquals(
        String.valueOf(billing.Id),
        dto.billingCustomFields.get('BillingAccountKey__c'),
        'Core 第3.3.2節: 識別のキーを読む'
      );
    }
  }

  @IsTest
  static void getBillingAccountInvoiceSettings_loadedRecordSkipsReread() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Loaded Billing Acc'
      );
      BillingAccount__c billing = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );
      billing.BillingAddressee__c = '取込済宛名';
      update billing;
      billing = [
        SELECT
          BillingAddressee__c,
          BillingEmailTo__c,
          BillingEmailCc__c,
          BillingEmailBcc__c,
          InvoiceDeliveryMethod__c,
          BillingAccountKey__c,
          InvoiceDateMethod__c,
          InvoiceDateDayKind__c,
          InvoiceDateDayOfMonth__c,
          InvoiceDateMonthOffset__c,
          InvoiceDateDayOffset__c,
          InvoiceDateAdjust__c,
          PaymentTermMethod__c,
          PaymentTermDayKind__c,
          PaymentTermDayOfMonth__c,
          PaymentTermMonthOffset__c,
          PaymentTermDayOffset__c,
          PaymentTermAdjust__c
        FROM BillingAccount__c
        WHERE Id = :billing.Id
      ];
      Integer before = Limits.getQueries();
      EstimateCreateController.BillingAccountInvoiceSettingsDto dto = EstimateQueryService.getBillingAccountInvoiceSettingsFromLoaded(
        billing
      );
      System.assertEquals(
        before,
        Limits.getQueries(),
        'Core 第4.3.11節: 同一取得で請求アカウントを取り直さない'
      );
      System.assertEquals(
        '取込済宛名',
        dto.billingCustomFields.get('BillingAddressee__c')
      );
    }
  }

  @IsTest
  static void getBillingAccountsAndRemarkMaster_andInvoiceOptions() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        0,
        EstimateQueryService.getBillingAccountsByAccount(null).size(),
        'Core 第3.3節: 取引先Idが無い請求アカウント候補は空'
      );
      Account account = ContractTestDataFactory.insertAccount(
        'Query BA List Acc'
      );
      BillingAccount__c billing = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );
      List<EstimateCreateController.BillingAccountOptionDto> options = EstimateQueryService.getBillingAccountsByAccount(
        account.Id
      );
      System.assertEquals(
        1,
        options.size(),
        'Core 第3.3節: 自取引先の請求アカウント候補は1件'
      );
      Boolean found = false;
      for (
        EstimateCreateController.BillingAccountOptionDto option : options
      ) {
        if (option.id == billing.Id) {
          found = true;
        }
      }
      System.assertEquals(
        true,
        found,
        'Core 第3.3節: 自取引先の請求アカウントを候補にする'
      );
      System.assertEquals(
        '',
        EstimateQueryService.getEstimateRemarkMasterText(null),
        'Core 第4.10節: 備考マスタIdが無い本文は空'
      );
      EstimateNoteMaster__c master = ContractTestDataFactory.insertEstimateNoteMaster(
        'Query Remark',
        '照会用備考本文'
      );
      System.assertEquals(
        '照会用備考本文',
        EstimateQueryService.getEstimateRemarkMasterText(master.Id),
        'Core 第4.10節: 備考マスタの本文を返す'
      );
      List<ContractMetadataService.InvoiceSettingOption> invoiceOptions = EstimateQueryService.getInvoiceSettingOptions();
      System.assertEquals(
        false,
        invoiceOptions.isEmpty(),
        'Core 第4.3.7節: 有効な請求設定候補を返す'
      );
      System.assertEquals(
        false,
        String.isBlank(EstimateQueryService.getDefaultInvoiceSettingLabel()),
        'Core 第4.3.7節: 既定請求設定ラベルを返す'
      );
    }
  }

  @IsTest
  static void getRenewContractProducts_returnsTermEndRecurring() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Query RenewSrc Acc'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query RenewSrc Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c ordered = new ContractHistory__c(
        Name = 'Query RenewSrc Ordered',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Type__c = 'New',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        ordered,
        account.Id
      );
      insert ordered;
      Product2 catalog = ContractTestDataFactory.buildProduct(
        'Query RenewSrc Product'
      );
      catalog.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      catalog.UnitName__c = 'ライセンス';
      ContractTestDataFactory.insertProduct(catalog);
      insert new ContractProduct__c(
        ContractHistory__c = ordered.Id,
        Product__c = catalog.Id,
        Quantity__c = 2,
        UnitPrice__c = 3000,
        Amount__c = 6000,
        Unit__c = null,
        Type__c = 'New',
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
      );
      List<EstimateCreateController.ContractProductLineDto> lines = EstimateQueryService.getRenewContractProducts(
        service.Id
      );
      System.assertEquals(
        1,
        lines.size(),
        'Core 第4.5.2節: 期末へ届く継続課金をRenew継承する'
      );
      System.assertEquals(null, lines[0].unit);
      System.assertEquals(2, lines[0].quantity);
      EstimateCreateController.ContractHistoryDto latest = EstimateQueryService.getLatestContractHistory(
        service.Id
      );
      System.assertEquals(
        true,
        latest.renewEligible,
        'Core 第4.3.3節: 期末継続課金があれば更新可'
      );
    }
  }

  @IsTest
  static void queryMaxCancelOrderedVersion_andRenewEligibleFalseForCancel() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Query CancelVer Acc'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Query CancelVer Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c cancelled = new ContractHistory__c(
        Name = 'Query CancelVer Ordered',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Type__c = 'Cancel',
        Version__c = 3,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        cancelled,
        account.Id
      );
      insert cancelled;
      Map<Id, Decimal> versions = EstimateQueryService.queryMaxCancelOrderedVersionByServiceIds(
        new Set<Id>{ service.Id }
      );
      System.assertEquals(
        3,
        versions.get(service.Id),
        'Core 第4.3.3節: 前回CancelのOrdered Versionを後続判定に使う'
      );
      System.assertEquals(
        false,
        EstimateQueryService.isRenewEligibleHistory(cancelled),
        'Core 第4.3.3節: Cancelは更新不可'
      );
      System.assertEquals(
        0,
        EstimateQueryService.countRenewSourceRecurringProducts(null, termEnd)
      );
      ContractHistory__c latestOrdered = EstimateQueryService.queryLatestActiveOrderedHistory(
        service.Id
      );
      System.assertEquals(
        cancelled.Id,
        latestOrdered.Id,
        'Core 第5.4節: Latest OrderedはVersion最大のOrdered'
      );
    }
  }

  @IsTest
  static void buildCopyHistoryName_andCustomFieldPresence() {
    System.assertEquals(
      '元履歴のコピー',
      EstimateQueryService.buildCopyHistoryName('元履歴'),
      'Core 第4.3.3節・第4.7節: コピーの履歴名は元名のコピー'
    );
    System.assertEquals(
      '',
      EstimateQueryService.buildCopyHistoryName('  '),
      'Core 第4.3.3節: 空の元名にのコピーは付けない'
    );
    System.assertEquals(
      false,
      EstimateQueryService.hasCustomFieldMapValues(null),
      'Core 第4.3.4節: nullのカスタム項目Mapは値無し'
    );
    System.assertEquals(
      false,
      EstimateQueryService.hasCustomFieldMapValues(
        new Map<String, Object>{ 'Field__c' => '' }
      ),
      'Core 第4.3.4節: 空文字だけのカスタム項目Mapは値無し'
    );
    System.assertEquals(
      true,
      EstimateQueryService.hasCustomFieldMapValues(
        new Map<String, Object>{ 'Field__c' => '値' }
      ),
      'Core 第4.3.4節: 値ありのカスタム項目Mapは値有り'
    );
    EstimateCreateController.ProductLineItem line = new EstimateCreateController.ProductLineItem();
    line.customFields = new Map<String, Object>{ 'Field__c' => '値' };
    System.assertEquals(
      true,
      EstimateQueryService.hasProductCustomFieldValues(
        new List<EstimateCreateController.ProductLineItem>{ line }
      ),
      'Core 第4.3.4節: 明細のカスタム項目値を検出する'
    );
    System.assertEquals(
      false,
      EstimateQueryService.hasProductCustomFieldValues(null),
      'Core 第4.3.4節: 明細リストが無いときはカスタム項目値無し'
    );
  }

  private class ContractProductFixture {
    ContractHistory__c history;
  }

  private static ContractProductFixture insertBlankUnitProduct(String typeValue) {
    Account account = ContractTestDataFactory.insertAccount('Query Unit Account');
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      'Query Unit Service'
    );
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Query Unit History',
      ContractService__c = service.Id,
      historystatus__c = 'Estimate',
      Type__c = 'New',
      Version__c = 1
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(
      history,
      account.Id
    );
    insert history;

    Product2 catalog = ContractTestDataFactory.buildProduct('Query Unit Product');
    catalog.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    catalog.UnitName__c = 'ライセンス';
    catalog.UnitPrice__c = 5000;
    catalog.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    ContractTestDataFactory.insertProduct(catalog);

    insert new ContractProduct__c(
      ContractHistory__c = history.Id,
      Product__c = catalog.Id,
      Quantity__c = 1,
      UnitPrice__c = 5000,
      Amount__c = 5000,
      Unit__c = null,
      Type__c = typeValue,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      StartDate__c = ContractTestDataFactory.stableTermStart(),
      Enddate__c = ContractTestDataFactory.stableTermEnd(),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
    );

    ContractProductFixture fixture = new ContractProductFixture();
    fixture.history = history;
    return fixture;
  }

  private static ContractProduct__c blankUnitInMemoryProduct(String typeValue) {
    Product2 catalog = new Product2(
      Name = 'Query Unit Catalog',
      UnitName__c = 'ライセンス'
    );
    ContractProduct__c product = new ContractProduct__c(
      Quantity__c = 1,
      UnitPrice__c = 5000,
      Unit__c = null,
      Type__c = typeValue,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
    );
    product.Product__r = catalog;
    return product;
  }
}
