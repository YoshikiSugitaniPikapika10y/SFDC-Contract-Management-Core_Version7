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
        'Core 第4.5.2節・第5.2節・第1.1.10節: Renewの空単位を商品マスタから埋めない'
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
        'Core 第1.1.10節: 照会DTOの空単位を商品マスタから埋めない'
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
        System.assert(
          ex.getMessage().contains('コピー元の契約履歴が指定されていません') ||
            ex.getMessage().contains('Script-thrown exception'),
          'Core 第4.7節: コピー元Idが空なら指定なしで拒否'
        );
      }
      System.assertEquals(true, nullThrown);
      Boolean missingThrown = false;
      try {
        EstimateQueryService.getEstimateCopyPreset(
          ContractHistory__c.SObjectType.getDescribe().getKeyPrefix() +
            '000000000001'
        );
      } catch (AuraHandledException ex) {
        missingThrown = true;
      }
      System.assertEquals(
        true,
        missingThrown,
        'Core 第4.7節: 契約履歴が無ければ拒否'
      );
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
        'Query Copy Source',
        preset.contractHistoryName,
        'Core 第4.3.3節・第4.7節・第0.1節: コピーの履歴名に「のコピー」を付けない'
      );
      System.assertEquals(
        'Query Copy Serviceのコピー',
        preset.contractServiceName
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
  static void getEstimateCopyPreset_changeNameEmpty_cancelNameHasChurnSuffix() {
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
        '',
        changePreset.contractHistoryName,
        'Core 第4.3.3節: Changeの履歴名は空'
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
        'Query Name Ordered 解約',
        cancelPreset.contractHistoryName,
        'Core 第4.3.3節・第0.1節: Cancelの履歴名末尾は解約'
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
      }
      System.assertEquals(
        true,
        thrown,
        'Core 第4.7節: コピー元はEstimateだけ'
      );
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
      }
      System.assertEquals(
        true,
        thrown,
        'Core 第4.7節: Archiveは編集できない'
      );
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
        System.assert(
          ex.getMessage().contains('契約管理で利用可能な商品のみ選択できます') ||
            ex.getMessage().contains('Script-thrown exception'),
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
        'Query Blank Lifecycle'
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
      System.assertEquals(true, ids.contains(termService.Id));
      System.assert(
        String.isNotBlank(currentNames) &&
          currentNames.contains('Query Current Product'),
        'Core 第4.3.3節: 期間契約の現商品名を載せる'
      );
    }
  }

  @IsTest
  static void getBillingAccountInvoiceSettings_readsLatestMaster() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateCreateController.BillingAccountInvoiceSettingsDto empty = EstimateQueryService.getBillingAccountInvoiceSettings(
        null
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
      System.assertEquals(true, options.size() >= 1);
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
      System.assertNotEquals(
        null,
        EstimateQueryService.getInvoiceSettingOptions()
      );
      System.assertNotEquals(
        null,
        EstimateQueryService.getDefaultInvoiceSettingLabel()
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
