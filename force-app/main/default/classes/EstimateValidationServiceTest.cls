@IsTest
private class EstimateValidationServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void rejectBranches_commonSaveRequestPaths() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      EstimateValidationService.validateContractServiceAccountMatchesOpportunity(
        request
      );

      Boolean missingPreviousHistory = false;
      try {
        EstimateValidationService.validatePreviousHistory(request);
      } catch (AuraHandledException ex) {
        missingPreviousHistory = true;
      }
      System.assertEquals(true, missingPreviousHistory);

      Boolean missingOpp = false;
      try {
        EstimateValidationService.validateCommonSaveRequest(
          request,
          'History Name',
          true
        );
      } catch (AuraHandledException ex) {
        missingOpp = true;
      }
      System.assertEquals(true, missingOpp);

      Account account = ContractTestDataFactory.insertAccount(
        'Validation Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Validation Opportunity'
      );
      request.opportunityId = opportunity.Id;

      Boolean missingDates = false;
      try {
        EstimateValidationService.validateCommonSaveRequest(
          request,
          'History Name',
          true
        );
      } catch (AuraHandledException ex) {
        missingDates = true;
      }
      System.assertEquals(true, missingDates);

      request.contractStartDate = '2027-06-01';
      request.contractEndDate = '2026-06-01';
      Boolean invertedDates = false;
      try {
        EstimateValidationService.validateCommonSaveRequest(
          request,
          'History Name',
          true
        );
      } catch (AuraHandledException ex) {
        invertedDates = true;
      }
      System.assertEquals(true, invertedDates);

      request.contractStartDate = '2026-06-01';
      request.contractEndDate = '2027-05-31';
      request.products = new List<EstimateCreateController.ProductLineItem>();
      Boolean missingProducts = false;
      try {
        EstimateValidationService.validateCommonSaveRequest(
          request,
          'History Name',
          true
        );
      } catch (AuraHandledException ex) {
        missingProducts = true;
      }
      System.assertEquals(true, missingProducts);

      EstimateValidationService.validateProductLines(
        new List<EstimateCreateController.ProductLineItem>(),
        false
      );

      Boolean blankHistoryName = false;
      try {
        EstimateValidationService.validateCommonSaveRequest(request, '', true);
      } catch (AuraHandledException ex) {
        blankHistoryName = true;
      }
      System.assertEquals(true, blankHistoryName);
    }
  }

  @IsTest
  static void rejectBranches_previousHistoryAndAccountMatch() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account serviceAccount = ContractTestDataFactory.insertAccount(
        'Service Account'
      );
      Account opportunityAccount = ContractTestDataFactory.insertAccount(
        'Opportunity Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = serviceAccount.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
        AdjustInvoiceDateToBusinessDay__c = false
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Validation Service',
        Account__c = serviceAccount.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        opportunityAccount.Id,
        'Mismatch Opportunity'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Previous History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1
      );
      insert history;

      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.contractServiceId = service.Id;
      request.opportunityId = opportunity.Id;
      request.previousHistoryId = history.Id;

      Boolean accountMismatch = false;
      try {
        EstimateValidationService.validateContractServiceAccountMatchesOpportunity(
          request
        );
      } catch (AuraHandledException ex) {
        accountMismatch = true;
      }
      System.assertEquals(true, accountMismatch);

      EstimateValidationService.validatePreviousHistory(request);

      request.previousHistoryId = fakeId(ContractHistory__c.SObjectType, 999);
      Boolean historyNotFound = false;
      try {
        EstimateValidationService.validatePreviousHistory(request);
      } catch (AuraHandledException ex) {
        historyNotFound = true;
      }
      System.assertEquals(true, historyNotFound);

      ContractHistory__c newerOrdered = new ContractHistory__c(
        Name = 'Newer Ordered',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 2
      );
      insert newerOrdered;
      request.previousHistoryId = history.Id;
      Boolean stalePrevious = false;
      try {
        EstimateValidationService.validatePreviousHistory(request);
      } catch (AuraHandledException ex) {
        stalePrevious = true;
        System.assert(
          ex.getMessage() != null &&
            ex.getMessage().contains('最新の受注'),
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        stalePrevious,
        '古い Ordered を previous にするとエラー'
      );
    }
  }

  @IsTest
  static void requiresChangeEffectiveDateOnBillingPeriodStart_oneTimeOnlyExempt() {
    Id fakeProductId = fakeId(Product2.SObjectType, 11);
    Id fakeSourceId = fakeId(ContractProduct__c.SObjectType, 22);

    EstimateCreateController.ProductLineItem original = new EstimateCreateController.ProductLineItem();
    original.productId = fakeProductId;
    original.quantity = 1;
    original.unitPrice = 8000;
    original.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    original.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    original.startDate = '2026-06-01';
    original.endDate = '2027-05-31';
    original.recordType = 'Original';
    original.sourceContractProductId = fakeSourceId;

    EstimateCreateController.ProductLineItem remake = new EstimateCreateController.ProductLineItem();
    remake.productId = fakeProductId;
    remake.quantity = 1;
    remake.unitPrice = 8000;
    remake.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    remake.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    remake.startDate = '2026-06-01';
    remake.endDate = '2027-05-31';
    remake.recordType = 'Remake';
    remake.sourceContractProductId = fakeSourceId;

    EstimateCreateController.ProductLineItem oneTime = new EstimateCreateController.ProductLineItem();
    oneTime.productId = fakeId(Product2.SObjectType, 33);
    oneTime.quantity = 1;
    oneTime.unitPrice = 50000;
    oneTime.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    oneTime.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    oneTime.startDate = '2026-10-15';
    oneTime.endDate = '2026-10-31';
    oneTime.recordType = 'New';

    List<EstimateCreateController.ProductLineItem> oneTimeOnly = new List<EstimateCreateController.ProductLineItem>{
      original,
      remake,
      oneTime
    };
    System.assertEquals(
      false,
      EstimateValidationService.requiresChangeEffectiveDateOnBillingPeriodStart(
        oneTimeOnly
      ),
      '一回課金 New のみの課金イベントなら請求境界制約を免除'
    );
    System.assertEquals(
      1,
      EstimateValidationService.collectChangeBillingEventDates(oneTimeOnly)
        .size()
    );
    System.assertEquals(
      null,
      EstimateValidationService.getEarliestChangeBillingThresholdDate(
        oneTimeOnly,
        Date.newInstance(2026, 6, 1)
      ),
      '一回課金イベントは切替日（最早日）計算から除外'
    );
    System.assertEquals(
      true,
      EstimateValidationService.hasChangeBillingEventWithinPreviousTerm(
        oneTimeOnly,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31)
      )
    );
    System.assertEquals(
      true,
      EstimateValidationService.requiresChangeEffectiveDateOnBillingPeriodStart(
        null
      )
    );
    System.assertEquals(
      0,
      EstimateValidationService.collectChangeBillingEventEntries(null).size()
    );

    EstimateCreateController.ProductLineItem changedRemake = new EstimateCreateController.ProductLineItem();
    changedRemake.productId = fakeProductId;
    changedRemake.quantity = 1;
    changedRemake.unitPrice = 9000;
    changedRemake.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    changedRemake.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    changedRemake.startDate = '2026-10-15';
    changedRemake.endDate = '2027-05-31';
    changedRemake.recordType = 'Remake';
    changedRemake.sourceContractProductId = fakeSourceId;

    System.assertEquals(
      true,
      EstimateValidationService.requiresChangeEffectiveDateOnBillingPeriodStart(
        new List<EstimateCreateController.ProductLineItem>{
          original,
          changedRemake,
          oneTime
        }
      ),
      '継続課金 Remake 差分があるときは請求境界制約を維持'
    );

    EstimateCreateController.ProductLineItem midStartRemake = new EstimateCreateController.ProductLineItem();
    midStartRemake.productId = fakeProductId;
    midStartRemake.quantity = 1;
    midStartRemake.unitPrice = 8000;
    midStartRemake.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    midStartRemake.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    midStartRemake.startDate = '2026-10-01';
    midStartRemake.endDate = '2027-05-31';
    midStartRemake.recordType = 'Remake';
    midStartRemake.sourceContractProductId = fakeSourceId;
    System.assertEquals(
      true,
      EstimateValidationService.requiresChangeEffectiveDateOnBillingPeriodStart(
        new List<EstimateCreateController.ProductLineItem>{
          original,
          midStartRemake
        }
      )
    );

    EstimateCreateController.ProductLineItem extendedRemake = new EstimateCreateController.ProductLineItem();
    extendedRemake.productId = fakeProductId;
    extendedRemake.quantity = 1;
    extendedRemake.unitPrice = 8000;
    extendedRemake.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    extendedRemake.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    extendedRemake.startDate = '2026-06-01';
    extendedRemake.endDate = '2027-06-30';
    extendedRemake.recordType = 'Remake';
    extendedRemake.sourceContractProductId = fakeSourceId;
    System.assertEquals(
      true,
      EstimateValidationService.requiresChangeEffectiveDateOnBillingPeriodStart(
        new List<EstimateCreateController.ProductLineItem>{
          original,
          extendedRemake
        }
      )
    );

    EstimateCreateController.ProductLineItem recurringNew = new EstimateCreateController.ProductLineItem();
    recurringNew.productId = fakeId(Product2.SObjectType, 44);
    recurringNew.quantity = 1;
    recurringNew.unitPrice = 1000;
    recurringNew.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    recurringNew.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    recurringNew.startDate = '2026-10-01';
    recurringNew.endDate = '2027-05-31';
    recurringNew.recordType = 'New';
    System.assertEquals(
      true,
      EstimateValidationService.requiresChangeEffectiveDateOnBillingPeriodStart(
        new List<EstimateCreateController.ProductLineItem>{ recurringNew }
      )
    );
  }

  @IsTest
  static void validateHistoryMetaDates_changeAllowsOneTimeMidPeriodEffectiveDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'History Meta OneTime Account'
      );
      ContractService__c service = insertServiceWithBilling(
        account.Id,
        'History Meta OneTime Service'
      );

      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      Date addonStart = Date.newInstance(2026, 10, 15);

      ContractHistory__c previous = new ContractHistory__c(
        Name = 'History Meta Previous',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert previous;

      EstimateCreateController.ProductLineItem oneTime = new EstimateCreateController.ProductLineItem();
      oneTime.productId = fakeId(Product2.SObjectType, 55);
      oneTime.quantity = 1;
      oneTime.unitPrice = 10000;
      oneTime.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      oneTime.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      oneTime.startDate = String.valueOf(addonStart);
      oneTime.endDate = '2026-10-31';
      oneTime.recordType = 'New';

      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.selectedType = 'Change';
      request.previousHistoryId = previous.Id;
      request.effectiveDate = String.valueOf(addonStart);
      request.products = new List<EstimateCreateController.ProductLineItem>{
        oneTime
      };

      EstimateValidationService.validateHistoryMetaDates(
        request,
        termStart,
        termEnd
      );

      EstimateCreateController.ProductLineItem recurringAddon = new EstimateCreateController.ProductLineItem();
      recurringAddon.productId = fakeId(Product2.SObjectType, 77);
      recurringAddon.quantity = 1;
      recurringAddon.unitPrice = 8000;
      recurringAddon.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      recurringAddon.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      recurringAddon.startDate = '2026-10-15';
      recurringAddon.endDate = '2027-05-31';
      recurringAddon.recordType = 'New';

      request.effectiveDate = '2026-10-15';
      request.products = new List<EstimateCreateController.ProductLineItem>{
        recurringAddon
      };
      System.assertEquals(
        true,
        EstimateValidationService.requiresChangeEffectiveDateOnBillingPeriodStart(
          request.products
        )
      );
      Boolean rejected = false;
      try {
        EstimateValidationService.validateHistoryMetaDates(
          request,
          termStart,
          termEnd
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assertEquals(
          EstimateValidationService.CHANGE_EFFECTIVE_DATE_BILLING_PERIOD_START_MESSAGE,
          ex.getMessage(),
          '継続課金の期中有効日は日割り不可として拒否'
        );
      }
      System.assertEquals(
        true,
        rejected,
        '継続課金イベントがある期中有効日は拒否'
      );
    }
  }

  @IsTest
  static void validateChangeReconstitutionCoverage_detectsGapAndAcceptsContiguous() {
    EstimateCreateController.ProductLineItem original = new EstimateCreateController.ProductLineItem();
    original.startDate = '2026-06-01';
    original.endDate = '2027-05-31';

    EstimateCreateController.ProductLineItem remakeEarly = new EstimateCreateController.ProductLineItem();
    remakeEarly.productId = fakeId(Product2.SObjectType, 11);
    remakeEarly.recordType = 'Remake';
    remakeEarly.quantity = 1;
    remakeEarly.unitPrice = 1000;
    remakeEarly.startDate = '2026-06-01';
    remakeEarly.endDate = '2026-09-30';

    EstimateCreateController.ProductLineItem remakeLate = new EstimateCreateController.ProductLineItem();
    remakeLate.productId = fakeId(Product2.SObjectType, 12);
    remakeLate.recordType = 'Remake';
    remakeLate.quantity = 1;
    remakeLate.unitPrice = 1000;
    remakeLate.startDate = '2026-11-01';
    remakeLate.endDate = '2027-05-31';

    System.assertEquals(
      EstimateValidationService.CHANGE_REMAKE_COVERAGE_MESSAGE,
      EstimateValidationService.validateChangeReconstitutionCoverage(
        original,
        new List<EstimateCreateController.ProductLineItem>{
          remakeEarly,
          remakeLate
        }
      ),
      'Remake に隙間があると拒否'
    );

    remakeLate.startDate = '2026-10-01';
    System.assertEquals(
      null,
      EstimateValidationService.validateChangeReconstitutionCoverage(
        original,
        new List<EstimateCreateController.ProductLineItem>{
          remakeEarly,
          remakeLate
        }
      ),
      '隣接する Remake は通る'
    );
  }

  @IsTest
  static void validateChangeHasBillingEventInPreviousTerm_extensionOnlyRequiresRenew() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Renew Gate Account'
      );
      ContractService__c service = insertServiceWithBilling(
        account.Id,
        'Change Renew Gate Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date extendedEnd = MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
        termStart,
        18
      );
      ContractHistory__c previous = new ContractHistory__c(
        Name = 'Change Renew Gate Previous',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      insert previous;

      Id sourceProductId = fakeId(ContractProduct__c.SObjectType, 21);
      EstimateCreateController.ProductLineItem original = new EstimateCreateController.ProductLineItem();
      original.productId = fakeId(Product2.SObjectType, 22);
      original.sourceContractProductId = sourceProductId;
      original.recordType = 'Original';
      original.quantity = 1;
      original.unitPrice = 5000;
      original.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      original.startDate = String.valueOf(termStart);
      original.endDate = String.valueOf(termEnd);

      // 内容同一のまま期間延長のみ → 前回期間内に課金イベント無し
      EstimateCreateController.ProductLineItem remake = new EstimateCreateController.ProductLineItem();
      remake.productId = original.productId;
      remake.sourceContractProductId = sourceProductId;
      remake.recordType = 'Remake';
      remake.quantity = 1;
      remake.unitPrice = 5000;
      remake.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remake.startDate = String.valueOf(termStart);
      remake.endDate = String.valueOf(extendedEnd);

      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.previousHistoryId = previous.Id;
      request.products = new List<EstimateCreateController.ProductLineItem>{
        original,
        remake
      };

      System.assertEquals(
        false,
        EstimateValidationService.hasChangeBillingEventWithinPreviousTerm(
          request.products,
          termStart,
          termEnd
        ),
        '延長だけの Remake は前回期間内の課金イベントにならない'
      );

      Boolean thrown = false;
      try {
        EstimateValidationService.validateChangeHasBillingEventInPreviousTerm(
          request
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          EstimateValidationService.CHANGE_REQUIRES_BILLING_EVENT_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void rejectBranches_newSaveAndProductLineRules() {
    EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
    Exception ex;

    ex = null;
    try {
      EstimateValidationService.validateNewSaveRequest(request, '');
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('商談IDが指定されていません', ex);

    request.opportunityId = fakeId(Opportunity.SObjectType, 1);
    ex = null;
    try {
      EstimateValidationService.validateNewSaveRequest(request, '');
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('契約履歴名を入力してください', ex);

    ex = null;
    try {
      EstimateValidationService.validateNewSaveRequest(request, 'Name');
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('契約サービス名を入力してください', ex);

    request.contractServiceName = 'Service';
    request.products = new List<EstimateCreateController.ProductLineItem>();
    ex = null;
    try {
      EstimateValidationService.validateNewSaveRequest(request, 'Name');
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('商品明細を1行以上入力してください', ex);

    EstimateCreateController.ProductLineItem dateProbe = new EstimateCreateController.ProductLineItem();
    dateProbe.productId = fakeId(Product2.SObjectType, 9);
    dateProbe.quantity = 1;
    dateProbe.unitPrice = 1000;
    dateProbe.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    dateProbe.recordType = 'New';
    dateProbe.startDate = '2026-06-01';
    dateProbe.endDate = '2027-05-31';
    dateProbe.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    request.products = new List<EstimateCreateController.ProductLineItem>{
      dateProbe
    };
    request.contractStartDate = '2026-06-01';
    request.contractEndDate = '2025-06-01';
    ex = null;
    try {
      EstimateValidationService.validateNewSaveRequest(request, 'Name');
    } catch (Exception e) {
      ex = e;
    }
    assertRejected(
      '期間開始日は期間終了日以前の日付を入力してください',
      ex
    );

    request.contractEndDate = '2027-05-31';
    request.effectiveDate = '2026-06-15';
    ex = null;
    try {
      EstimateValidationService.validateNewSaveRequest(request, 'Name');
    } catch (Exception e) {
      ex = e;
    }
    assertRejected(
      '切替日は期間開始日と一致している必要があります',
      ex
    );

    request.effectiveDate = '2026-06-01';

    EstimateCreateController.ProductLineItem recurring = new EstimateCreateController.ProductLineItem();
    recurring.productId = fakeId(Product2.SObjectType, 2);
    recurring.quantity = 1;
    recurring.unitPrice = 1000;
    recurring.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    recurring.recordType = 'New';
    ex = null;
    try {
      EstimateValidationService.validateNewProductLineRules(
        new List<EstimateCreateController.ProductLineItem>{ recurring },
        '2026-06-01',
        '2027-05-31',
        false
      );
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('開始日と終了日を入力してください', ex);

    recurring.startDate = '2026-05-01';
    recurring.endDate = '2027-05-31';
    recurring.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    ex = null;
    try {
      EstimateValidationService.validateNewProductLineRules(
        new List<EstimateCreateController.ProductLineItem>{ recurring },
        '2026-06-01',
        '2027-05-31',
        false
      );
    } catch (Exception e) {
      ex = e;
    }
    assertRejected(
      '開始日は期間開始日以降の日付を入力してください',
      ex
    );

    recurring.startDate = '2026-06-01';
    recurring.endDate = '2027-04-30';
    ex = null;
    try {
      EstimateValidationService.validateNewProductLineRules(
        new List<EstimateCreateController.ProductLineItem>{ recurring },
        '2026-06-01',
        '2027-05-31',
        false
      );
    } catch (Exception e) {
      ex = e;
    }
    // 継続課金はヘッダー終了日と揃える必要がある
    assertRejected(
      '期間終了日と一致する終了日の継続課金明細が1件以上必要です',
      ex
    );

    EstimateCreateController.ProductLineItem left = new EstimateCreateController.ProductLineItem();
    left.productId = fakeId(Product2.SObjectType, 3);
    left.quantity = 1;
    left.unitPrice = 1000;
    left.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    left.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    left.startDate = '2026-06-01';
    left.endDate = '2026-06-30';
    left.recordType = 'New';
    EstimateCreateController.ProductLineItem right = new EstimateCreateController.ProductLineItem();
    right.productId = left.productId;
    right.quantity = 1;
    right.unitPrice = 1000;
    right.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    right.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    right.startDate = '2026-06-15';
    right.endDate = '2026-07-15';
    right.recordType = 'New';
    ex = null;
    try {
      EstimateValidationService.validateNewProductPeriodOverlap(
        new List<EstimateCreateController.ProductLineItem>{ left, right }
      );
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('同一商品の契約期間が重複しています', ex);

    System.assertNotEquals(
      null,
      EstimateValidationService.validateBillingTypeRequired(
        new EstimateCreateController.ProductLineItem(),
        1,
        null
      ),
      '課金種別未入力はエラー文言を返す'
    );
    EstimateCreateController.ProductLineItem badBilling = new EstimateCreateController.ProductLineItem();
    badBilling.billingType = '不明';
    System.assertNotEquals(
      null,
      EstimateValidationService.validateBillingTypeRequired(
        badBilling,
        1,
        null
      ),
      '不明な課金種別はエラー文言を返す'
    );

    EstimateCreateController.ProductLineItem remakeShort = new EstimateCreateController.ProductLineItem();
    remakeShort.productId = fakeId(Product2.SObjectType, 4);
    remakeShort.quantity = 1;
    remakeShort.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    remakeShort.recordType = 'Remake';
    remakeShort.sourceContractProductId = fakeId(
      ContractProduct__c.SObjectType,
      5
    );
    remakeShort.startDate = '2026-06-01';
    remakeShort.endDate = '2027-04-30';
    ex = null;
    try {
      EstimateValidationService.validateChangeRecurringEndEndpointCoverage(
        new List<EstimateCreateController.ProductLineItem>{ remakeShort },
        '2027-05-31'
      );
    } catch (Exception e) {
      ex = e;
    }
    assertRejected(
      '期間終了日と一致する終了日の継続課金明細が1件以上必要です',
      ex
    );

    EstimateCreateController.ProductLineItem continuation = new EstimateCreateController.ProductLineItem();
    continuation.recordType = 'New';
    continuation.sourceContractProductId = null;
    System.assertEquals(
      true,
      EstimateValidationService.isChangeContinuationLine(continuation)
    );
    EstimateCreateController.ProductLineItem orphanRemake = new EstimateCreateController.ProductLineItem();
    orphanRemake.recordType = 'Remake';
    orphanRemake.sourceContractProductId = null;
    System.assertEquals(
      true,
      EstimateValidationService.isChangeContinuationLine(orphanRemake)
    );

    continuation.productId = fakeId(Product2.SObjectType, 9);
    continuation.quantity = 1;
    continuation.unitPrice = 1;
    continuation.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    continuation.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    continuation.startDate = '2026-06-01';
    continuation.endDate = '2026-06-01';
    List<EstimateCreateController.ProductLineItem> normalized = EstimateValidationService.normalizeChangeProductsForSave(
      new List<EstimateCreateController.ProductLineItem>{
        null,
        new EstimateCreateController.ProductLineItem(),
        continuation
      }
    );
    System.assert(normalized.size() >= 1, '正規化後に有効行が残ること');

    EstimateCreateController.EstimateSaveRequest changeDates = new EstimateCreateController.EstimateSaveRequest();
    changeDates.contractStartDate = '2026-06-01';
    changeDates.contractEndDate = '2027-05-31';
    ex = null;
    try {
      EstimateValidationService.validateChangePeriodDates(changeDates);
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('前回契約履歴が見つかりません', ex);

    ex = null;
    try {
      EstimateValidationService.validateChangeProductPeriodOverlap(
        new List<EstimateCreateController.ProductLineItem>{
          continuation,
          continuation
        }
      );
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('同一商品の契約期間が重複しています', ex);

    // 一回課金・日付ありは Change 編集行バリデーションを通る想定
    EstimateValidationService.validateChangeEditableLine(
      continuation,
      1,
      Date.newInstance(2026, 6, 1),
      Date.newInstance(2027, 5, 31)
    );

    EstimateCreateController.ProductLineItem blankDates = new EstimateCreateController.ProductLineItem();
    blankDates.productId = fakeId(Product2.SObjectType, 12);
    blankDates.quantity = 1;
    blankDates.unitPrice = 1000;
    blankDates.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    blankDates.recordType = 'New';
    ex = null;
    try {
      EstimateValidationService.validateChangeEditableLine(
        blankDates,
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31)
      );
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('開始日と終了日を入力してください', ex);

    blankDates.startDate = '2027-01-01';
    blankDates.endDate = '2026-12-01';
    blankDates.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    ex = null;
    try {
      EstimateValidationService.validateChangeEditableLine(
        blankDates,
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31)
      );
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('開始日は終了日以前の日付を入力してください', ex);

    blankDates.startDate = '2026-05-01';
    blankDates.endDate = '2027-05-31';
    ex = null;
    try {
      EstimateValidationService.validateChangeEditableLine(
        blankDates,
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31)
      );
    } catch (Exception e) {
      ex = e;
    }
    assertRejected(
      '開始日は期間開始日以降の日付を入力してください',
      ex
    );

    blankDates.startDate = '2026-06-01';
    blankDates.endDate = '2027-06-30';
    ex = null;
    try {
      EstimateValidationService.validateChangeEditableLine(
        blankDates,
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31)
      );
    } catch (Exception e) {
      ex = e;
    }
    assertRejected(
      '終了日は期間終了日以前の日付を入力してください',
      ex
    );
  }

  @IsTest
  static void rejectBranches_productLinesAndHistoryMeta() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 unavailable = ContractTestDataFactory.buildProduct(
        'Unavailable'
      );
      unavailable.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(unavailable);
      unavailable.AvailableForContract__c = false;
      update unavailable;

      Product2 available = ContractTestDataFactory.buildProduct('Available');
      available.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      available.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(available);

      EstimateCreateController.ProductLineItem unavailableLine = new EstimateCreateController.ProductLineItem();
      unavailableLine.productId = unavailable.Id;
      unavailableLine.quantity = 1;
      unavailableLine.unitPrice = 1000;
      unavailableLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      unavailableLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      unavailableLine.startDate = '2026-06-01';
      unavailableLine.endDate = '2027-05-31';
      Exception unavailableEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{ unavailableLine },
          false,
          'EST-S3-New'
        );
      } catch (Exception ex) {
        unavailableEx = ex;
      }
      assertRejected('契約管理で利用可能な商品のみ', unavailableEx);

      EstimateCreateController.ProductLineItem mismatch = new EstimateCreateController.ProductLineItem();
      mismatch.productId = available.Id;
      mismatch.quantity = 1;
      mismatch.unitPrice = 1000;
      mismatch.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      mismatch.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      mismatch.startDate = '2026-06-01';
      mismatch.endDate = '2026-06-01';
      Exception mismatchEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{ mismatch },
          false,
          'EST-S3-New'
        );
      } catch (Exception ex) {
        mismatchEx = ex;
      }
      assertRejected('課金種別が商品マスタと一致しません', mismatchEx);

      EstimateCreateController.ProductLineItem noPrice = new EstimateCreateController.ProductLineItem();
      noPrice.productId = available.Id;
      noPrice.quantity = 1;
      noPrice.unitPrice = null;
      noPrice.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      noPrice.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      noPrice.startDate = '2026-06-01';
      noPrice.endDate = '2027-05-31';
      Exception noPriceEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{ noPrice },
          false,
          'EST-S3-New'
        );
      } catch (Exception ex) {
        noPriceEx = ex;
      }
      assertRejected('単価を入力してください', noPriceEx);

      Account account = ContractTestDataFactory.insertAccount(
        'Coverage Meta Account'
      );
      ContractService__c service = insertServiceWithBilling(
        account.Id,
        'Coverage Meta Service'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      ContractHistory__c previous = new ContractHistory__c(
        Name = 'Coverage Meta Previous',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert previous;
      ContractHistory__c cancelHistory = new ContractHistory__c(
        Name = 'Coverage Meta Cancel',
        ContractService__c = service.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Ordered',
        Version__c = 2,
        CurrentTermStartDate__c = termEnd.addDays(1),
        CurrentTermEndDate__c = termEnd.addDays(1),
        EffectiveDate__c = termEnd.addDays(1),
        PreviousHistory__c = previous.Id
      );
      insert cancelHistory;

      EstimateCreateController.EstimateSaveRequest newReq = new EstimateCreateController.EstimateSaveRequest();
      newReq.selectedType = 'New';
      newReq.effectiveDate = '2026-06-15';
      Exception newMetaEx = null;
      try {
        EstimateValidationService.validateHistoryMetaDates(
          newReq,
          termStart,
          termEnd
        );
      } catch (Exception ex) {
        newMetaEx = ex;
      }
      assertRejected(
        '切替日は期間開始日と一致している必要があります',
        newMetaEx
      );

      EstimateCreateController.EstimateSaveRequest renewReq = new EstimateCreateController.EstimateSaveRequest();
      renewReq.selectedType = 'Renew';
      renewReq.previousHistoryId = previous.Id;
      renewReq.effectiveDate = String.valueOf(termStart);
      Exception renewMetaEx = null;
      try {
        EstimateValidationService.validateHistoryMetaDates(
          renewReq,
          termStart,
          termEnd
        );
      } catch (Exception ex) {
        renewMetaEx = ex;
      }
      assertRejected(
        '切替日は前回契約履歴の契約終了日の翌日である必要があります',
        renewMetaEx
      );

      Exception cancelEligEx = null;
      try {
        EstimateValidationService.validateCancelEligibility(cancelHistory.Id);
      } catch (Exception ex) {
        cancelEligEx = ex;
      }
      assertRejected(
        'Churn（解約）済みの契約履歴からCancelは作成できません',
        cancelEligEx
      );

      Exception renewEligEx = null;
      try {
        EstimateValidationService.validateRenewEligibility(previous.Id);
      } catch (Exception ex) {
        renewEligEx = ex;
      }
      assertRejected(
        '前回Versionの期間終了日と一致する継続課金商品がないためRenewできません',
        renewEligEx
      );

      Exception missingHistEx = null;
      try {
        EstimateValidationService.validateRecurringSourceEligibility(
          fakeId(ContractHistory__c.SObjectType, 99),
          'Cancel'
        );
      } catch (Exception ex) {
        missingHistEx = ex;
      }
      assertRejected('前回契約履歴が見つかりません', missingHistEx);

      EstimateCreateController.EstimateSaveRequest renewPeriod = new EstimateCreateController.EstimateSaveRequest();
      renewPeriod.previousHistoryId = previous.Id;
      renewPeriod.contractStartDate = String.valueOf(termStart);
      Exception renewPeriodEx = null;
      try {
        EstimateValidationService.validateRenewPeriodStartDate(renewPeriod);
      } catch (Exception ex) {
        renewPeriodEx = ex;
      }
      assertRejected(
        '期間開始日は前回Versionの期間終了日の翌日である必要があります',
        renewPeriodEx
      );

      EstimateCreateController.EstimateSaveRequest cancelPeriod = new EstimateCreateController.EstimateSaveRequest();
      cancelPeriod.previousHistoryId = previous.Id;
      cancelPeriod.contractStartDate = String.valueOf(termStart);
      cancelPeriod.contractEndDate = String.valueOf(termStart);
      Exception cancelPeriodEx = null;
      try {
        EstimateValidationService.validateCancelPeriodDates(cancelPeriod);
      } catch (Exception ex) {
        cancelPeriodEx = ex;
      }
      assertRejected(
        '解約日は前回Versionの期間終了日の翌日である必要があります',
        cancelPeriodEx
      );

      EstimateCreateController.ProductLineItem oneTimeOnly = new EstimateCreateController.ProductLineItem();
      oneTimeOnly.productId = available.Id;
      oneTimeOnly.quantity = 1;
      oneTimeOnly.unitPrice = 1000;
      oneTimeOnly.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      oneTimeOnly.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      oneTimeOnly.startDate = String.valueOf(termEnd.addDays(1));
      oneTimeOnly.endDate = String.valueOf(
        termEnd.addDays(1).addYears(1).addDays(-1)
      );
      oneTimeOnly.recordType = 'New';
      Exception renewOneTimeEx = null;
      try {
        EstimateValidationService.validateRenewProductLineRules(
          new List<EstimateCreateController.ProductLineItem>{ oneTimeOnly },
          String.valueOf(termEnd.addDays(1)),
          String.valueOf(termEnd.addDays(1).addYears(1).addDays(-1))
        );
      } catch (Exception ex) {
        renewOneTimeEx = ex;
      }
      assertRejected(
        'Renewでは継続課金商品を1行以上指定してください',
        renewOneTimeEx
      );

      Exception cancelProductsEx = null;
      try {
        EstimateValidationService.validateCancelNoProducts(
          new List<EstimateCreateController.ProductLineItem>{ oneTimeOnly }
        );
      } catch (Exception ex) {
        cancelProductsEx = ex;
      }
      assertRejected('Cancelでは商品明細を入力できません', cancelProductsEx);

      ContractHistory__c changeNoPrev = new ContractHistory__c(
        Name = 'Coverage Change NoPrev',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 3,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert changeNoPrev;
      Exception changeNoPrevEx = null;
      try {
        EstimateValidationService.assertChangeHistoriesReadyForInvoice(
          new Set<Id>{ changeNoPrev.Id }
        );
      } catch (Exception ex) {
        changeNoPrevEx = ex;
      }
      assertRejected(
        'Change の前回契約履歴が設定されていないため請求を生成できません',
        changeNoPrevEx
      );

      ContractHistory__c changeFromCancel = new ContractHistory__c(
        Name = 'Coverage Change FromCancel',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 4,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart,
        PreviousHistory__c = cancelHistory.Id
      );
      insert changeFromCancel;
      Exception changeFromCancelEx = null;
      try {
        EstimateValidationService.assertChangeHistoriesReadyForInvoice(
          new Set<Id>{ changeFromCancel.Id }
        );
      } catch (Exception ex) {
        changeFromCancelEx = ex;
      }
      assertRejected(
        'Churn（解約）済みの契約履歴からChangeは作成できません',
        changeFromCancelEx
      );

      ContractHistory__c changeBadEnd = new ContractHistory__c(
        Name = 'Coverage Change BadEnd',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 5,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd.addDays(-10),
        EffectiveDate__c = termStart,
        PreviousHistory__c = previous.Id
      );
      insert changeBadEnd;
      Exception changeBadEndEx = null;
      try {
        EstimateValidationService.assertChangeHistoriesReadyForInvoice(
          new Set<Id>{ changeBadEnd.Id }
        );
      } catch (Exception ex) {
        changeBadEndEx = ex;
      }
      // この時点では previous に継続課金商品が未作成のため、期間終了日不一致より先に資格エラーになる
      assertRejected(
        '前回Versionの期間終了日と一致する継続課金商品がないためChangeできません',
        changeBadEndEx
      );

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = previous.Id,
        Product__c = available.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.EstimateSaveRequest changeReq = new EstimateCreateController.EstimateSaveRequest();
      changeReq.previousHistoryId = previous.Id;
      changeReq.contractStartDate = String.valueOf(termStart);
      changeReq.contractEndDate = String.valueOf(termEnd);
      changeReq.effectiveDate = String.valueOf(termStart);
      EstimateCreateController.ProductLineItem badOriginal = new EstimateCreateController.ProductLineItem();
      badOriginal.productId = available.Id;
      badOriginal.quantity = 1;
      badOriginal.unitPrice = 8000;
      badOriginal.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      badOriginal.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      badOriginal.startDate = String.valueOf(termStart);
      badOriginal.endDate = String.valueOf(termEnd);
      badOriginal.recordType = 'Original';
      changeReq.products = new List<EstimateCreateController.ProductLineItem>{
        badOriginal
      };
      Exception badOriginalEx = null;
      try {
        EstimateValidationService.validateChangeProductLineRules(changeReq);
      } catch (Exception ex) {
        badOriginalEx = ex;
      }
      assertRejected(
        'Original行に元の見積商品が指定されていません',
        badOriginalEx
      );

      badOriginal.sourceContractProductId = sourceProduct.Id;
      EstimateCreateController.ProductLineItem badRemake = new EstimateCreateController.ProductLineItem();
      badRemake.productId = fakeId(Product2.SObjectType, 8);
      badRemake.quantity = 1;
      badRemake.unitPrice = 8000;
      badRemake.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      badRemake.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      badRemake.startDate = String.valueOf(termStart);
      badRemake.endDate = String.valueOf(termEnd);
      badRemake.recordType = 'Remake';
      badRemake.sourceContractProductId = sourceProduct.Id;
      changeReq.products = new List<EstimateCreateController.ProductLineItem>{
        badOriginal,
        badRemake
      };
      Exception badRemakeEx = null;
      try {
        EstimateValidationService.validateChangeProductLineRules(changeReq);
      } catch (Exception ex) {
        badRemakeEx = ex;
      }
      assertRejected(
        'Remake行の商品はOriginal（前回Version）と同じ商品にしてください',
        badRemakeEx
      );

      ContractProduct__c sourceForMatch = new ContractProduct__c(
        Product__c = available.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
      );
      EstimateCreateController.ProductLineItem mismatchOriginal = new EstimateCreateController.ProductLineItem();
      mismatchOriginal.productId = available.Id;
      mismatchOriginal.quantity = 2;
      mismatchOriginal.unitPrice = 8000;
      mismatchOriginal.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      mismatchOriginal.startDate = String.valueOf(termStart);
      mismatchOriginal.endDate = String.valueOf(termEnd);
      Exception originalMatchEx = null;
      try {
        EstimateValidationService.validateOriginalMatchesSource(
          mismatchOriginal,
          sourceForMatch,
          1
        );
      } catch (Exception ex) {
        originalMatchEx = ex;
      }
      assertRejected(
        'Original行は前回Versionの見積商品と一致している必要があります',
        originalMatchEx
      );
    }
  }

  @IsTest
  static void validateAddAndSpotNew_pathsCoverLifecycleRules() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Add Spot Acc');
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Add Spot Opp'
      );
      ContractService__c spotService = insertServiceWithBilling(
        account.Id,
        'Add Spot Service'
      );
      spotService.Lifecycle__c = ContractDomainConstants.LIFECYCLE_SPOT;
      update spotService;

      ContractService__c termService = insertServiceWithBilling(
        account.Id,
        'Add Term Service'
      );
      termService.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
      update termService;

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c spotOrdered = new ContractHistory__c(
        Name = 'Add Spot V1',
        ContractService__c = spotService.Id,
        Opportunity__c = opportunity.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ORDERED,
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert spotOrdered;

      ContractHistory__c termOrdered = new ContractHistory__c(
        Name = 'Add Term V1',
        ContractService__c = termService.Id,
        Opportunity__c = opportunity.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ORDERED,
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert termOrdered;

      Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
        'Add OneTime Prod'
      );
      oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      oneTimeProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(oneTimeProduct, false);

      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Add Recurring Prod'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      recurringProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(recurringProduct);

      EstimateCreateController.ProductLineItem oneTimeLine = new EstimateCreateController.ProductLineItem();
      oneTimeLine.productId = oneTimeProduct.Id;
      oneTimeLine.quantity = 1;
      oneTimeLine.unitPrice = 5000;
      oneTimeLine.amount = 5000;
      oneTimeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      oneTimeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      oneTimeLine.startDate = String.valueOf(termStart.addMonths(1));
      oneTimeLine.endDate = String.valueOf(termStart.addMonths(1));
      oneTimeLine.recordType = 'New';

      EstimateCreateController.ProductLineItem recurringLine = new EstimateCreateController.ProductLineItem();
      recurringLine.productId = recurringProduct.Id;
      recurringLine.quantity = 1;
      recurringLine.unitPrice = 8000;
      recurringLine.amount = 96000;
      recurringLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      recurringLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      recurringLine.startDate = String.valueOf(termStart);
      recurringLine.endDate = String.valueOf(termEnd);
      recurringLine.recordType = 'New';

      System.assertEquals(
        true,
        EstimateValidationService.isChangeOneTimeAddOnly(
          new List<EstimateCreateController.ProductLineItem>{ oneTimeLine }
        )
      );
      System.assertEquals(
        false,
        EstimateValidationService.isChangeOneTimeAddOnly(
          new List<EstimateCreateController.ProductLineItem>{ recurringLine }
        )
      );

      EstimateCreateController.EstimateSaveRequest addMeta = new EstimateCreateController.EstimateSaveRequest();
      addMeta.selectedType = ContractDomainConstants.HISTORY_TYPE_ADD;
      addMeta.effectiveDate = String.valueOf(termStart);
      addMeta.products = new List<EstimateCreateController.ProductLineItem>{
        oneTimeLine
      };
      EstimateValidationService.validateHistoryMetaDates(
        addMeta,
        termStart,
        termEnd
      );
      System.assertEquals(null, addMeta.effectiveDate);

      EstimateCreateController.EstimateSaveRequest changeOneTimeOnly = new EstimateCreateController.EstimateSaveRequest();
      changeOneTimeOnly.selectedType = ContractDomainConstants.HISTORY_TYPE_CHANGE;
      changeOneTimeOnly.effectiveDate = String.valueOf(termStart.addDays(10));
      changeOneTimeOnly.products = new List<EstimateCreateController.ProductLineItem>{
        oneTimeLine
      };
      EstimateValidationService.validateHistoryMetaDates(
        changeOneTimeOnly,
        termStart,
        termEnd
      );
      System.assertEquals(null, changeOneTimeOnly.effectiveDate);

      EstimateCreateController.EstimateSaveRequest newOneTimeOnly = new EstimateCreateController.EstimateSaveRequest();
      newOneTimeOnly.opportunityId = opportunity.Id;
      newOneTimeOnly.contractServiceName = 'Spot New Service';
      newOneTimeOnly.contractStartDate = String.valueOf(termStart);
      newOneTimeOnly.contractEndDate = String.valueOf(termEnd);
      newOneTimeOnly.effectiveDate = String.valueOf(termStart);
      newOneTimeOnly.products = new List<EstimateCreateController.ProductLineItem>{
        oneTimeLine
      };
      EstimateValidationService.validateNewSaveRequest(
        newOneTimeOnly,
        'Spot New History'
      );
      System.assertEquals(null, newOneTimeOnly.contractStartDate);
      System.assertEquals(null, newOneTimeOnly.contractEndDate);
      System.assertEquals(null, newOneTimeOnly.effectiveDate);

      EstimateCreateController.ProductLineItem downgradeLine = new EstimateCreateController.ProductLineItem();
      downgradeLine.productId = recurringProduct.Id;
      downgradeLine.quantity = 1;
      downgradeLine.unitPrice = 1000;
      downgradeLine.amount = 1000;
      downgradeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      downgradeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      downgradeLine.startDate = String.valueOf(termStart);
      downgradeLine.endDate = String.valueOf(termStart);
      downgradeLine.recordType = 'New';
      EstimateValidationService.validateProductLines(
        new List<EstimateCreateController.ProductLineItem>{ downgradeLine },
        false,
        'EST-S3-New',
        true
      );

      EstimateCreateController.EstimateSaveRequest addOk = new EstimateCreateController.EstimateSaveRequest();
      addOk.opportunityId = opportunity.Id;
      addOk.contractServiceId = spotService.Id;
      addOk.previousHistoryId = spotOrdered.Id;
      addOk.selectedType = ContractDomainConstants.HISTORY_TYPE_ADD;
      addOk.contractStartDate = String.valueOf(termStart);
      addOk.contractEndDate = String.valueOf(termEnd);
      addOk.effectiveDate = String.valueOf(termStart);
      addOk.products = new List<EstimateCreateController.ProductLineItem>{
        oneTimeLine
      };
      Test.startTest();
      EstimateValidationService.validateAddSaveRequest(addOk, 'Add History');
      Test.stopTest();
      System.assertEquals(null, addOk.contractStartDate);
      System.assertEquals(null, addOk.contractEndDate);
      System.assertEquals(null, addOk.effectiveDate);

      EstimateCreateController.EstimateSaveRequest addOnTerm = new EstimateCreateController.EstimateSaveRequest();
      addOnTerm.opportunityId = opportunity.Id;
      addOnTerm.contractServiceId = termService.Id;
      addOnTerm.previousHistoryId = termOrdered.Id;
      addOnTerm.selectedType = ContractDomainConstants.HISTORY_TYPE_ADD;
      addOnTerm.products = new List<EstimateCreateController.ProductLineItem>{
        oneTimeLine
      };
      Exception termEx = null;
      try {
        EstimateValidationService.validateAddSaveRequest(
          addOnTerm,
          'Add On Term'
        );
      } catch (Exception ex) {
        termEx = ex;
      }
      assertRejected('都度契約（Spot）', termEx);

      EstimateCreateController.EstimateSaveRequest addRecurring = new EstimateCreateController.EstimateSaveRequest();
      addRecurring.opportunityId = opportunity.Id;
      addRecurring.contractServiceId = spotService.Id;
      addRecurring.previousHistoryId = spotOrdered.Id;
      addRecurring.selectedType = ContractDomainConstants.HISTORY_TYPE_ADD;
      addRecurring.products = new List<EstimateCreateController.ProductLineItem>{
        recurringLine
      };
      Exception recurringEx = null;
      try {
        EstimateValidationService.validateAddSaveRequest(
          addRecurring,
          'Add Recurring'
        );
      } catch (Exception ex) {
        recurringEx = ex;
      }
      assertRejected('一回課金商品のみ', recurringEx);

      Exception addNoOppEx = null;
      try {
        EstimateValidationService.validateAddSaveRequest(
          new EstimateCreateController.EstimateSaveRequest(),
          'Add No Opp'
        );
      } catch (Exception ex) {
        addNoOppEx = ex;
      }
      assertRejected('商談IDが指定されていません', addNoOppEx);

      EstimateCreateController.EstimateSaveRequest addBlankName = new EstimateCreateController.EstimateSaveRequest();
      addBlankName.opportunityId = opportunity.Id;
      Exception addBlankNameEx = null;
      try {
        EstimateValidationService.validateAddSaveRequest(addBlankName, '');
      } catch (Exception ex) {
        addBlankNameEx = ex;
      }
      assertRejected('契約履歴名を入力してください', addBlankNameEx);

      EstimateCreateController.EstimateSaveRequest addNoService = new EstimateCreateController.EstimateSaveRequest();
      addNoService.opportunityId = opportunity.Id;
      Exception addNoServiceEx = null;
      try {
        EstimateValidationService.validateAddSaveRequest(
          addNoService,
          'Add No Service'
        );
      } catch (Exception ex) {
        addNoServiceEx = ex;
      }
      assertRejected('契約サービスを選択してください', addNoServiceEx);

      EstimateCreateController.EstimateSaveRequest addNoProducts = new EstimateCreateController.EstimateSaveRequest();
      addNoProducts.opportunityId = opportunity.Id;
      addNoProducts.contractServiceId = spotService.Id;
      addNoProducts.previousHistoryId = spotOrdered.Id;
      addNoProducts.products = new List<EstimateCreateController.ProductLineItem>();
      Exception addNoProductsEx = null;
      try {
        EstimateValidationService.validateAddSaveRequest(
          addNoProducts,
          'Add No Products'
        );
      } catch (Exception ex) {
        addNoProductsEx = ex;
      }
      assertRejected('商品明細を1行以上入力してください', addNoProductsEx);

      EstimateCreateController.EstimateSaveRequest newMetaOneTime = new EstimateCreateController.EstimateSaveRequest();
      newMetaOneTime.selectedType = ContractDomainConstants.HISTORY_TYPE_NEW;
      newMetaOneTime.effectiveDate = String.valueOf(termStart);
      newMetaOneTime.products = new List<EstimateCreateController.ProductLineItem>{
        oneTimeLine
      };
      EstimateValidationService.validateHistoryMetaDates(
        newMetaOneTime,
        termStart,
        termEnd
      );
      System.assertEquals(null, newMetaOneTime.effectiveDate);

      // 一回課金はヘッダ期間外でも可
      EstimateCreateController.ProductLineItem outsideOneTime = new EstimateCreateController.ProductLineItem();
      outsideOneTime.productId = oneTimeProduct.Id;
      outsideOneTime.quantity = 1;
      outsideOneTime.unitPrice = 1000;
      outsideOneTime.amount = 1000;
      outsideOneTime.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      outsideOneTime.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      outsideOneTime.startDate = String.valueOf(termStart.addYears(-1));
      outsideOneTime.endDate = String.valueOf(termStart.addYears(-1));
      outsideOneTime.recordType = 'New';
      EstimateValidationService.validateChangeEditableLine(
        outsideOneTime,
        1,
        termStart,
        termEnd
      );
      EstimateValidationService.validateNewProductLineRules(
        new List<EstimateCreateController.ProductLineItem>{ outsideOneTime },
        String.valueOf(termStart),
        String.valueOf(termEnd),
        true,
        'EST-S3-New'
      );
    }
  }

  @IsTest
  static void validateWizardCustomFields_withTestDefinitions() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();

    EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
    request.selectedType = 'New';
    request.contractServiceCustomFields = new Map<String, Object>{
      'CustomerMemo__c' => 'memo'
    };
    request.contractHistoryCustomFields = new Map<String, Object>{
      'ApplicationDate__c' => '2026-07-01'
    };
    request.products = new List<EstimateCreateController.ProductLineItem>();

    EstimateValidationService.validateWizardCustomFields(request, false);
    System.assertEquals(
      'memo',
      request.contractServiceCustomFields.get('CustomerMemo__c')
    );
  }

  @IsTest
  static void rejectBranches_latestOrderedAndHistoryMeta() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Val Boost Acc');
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Val Boost Opp'
      );
      ContractService__c emptyService = insertServiceWithBilling(
        account.Id,
        'Val Boost Empty Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();

      ContractHistory__c estimateOnly = new ContractHistory__c(
        Name = 'Val Boost Estimate Only',
        ContractService__c = emptyService.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert estimateOnly;

      Test.startTest();
      EstimateCreateController.EstimateSaveRequest noLatest = new EstimateCreateController.EstimateSaveRequest();
      noLatest.contractServiceId = emptyService.Id;
      noLatest.previousHistoryId = estimateOnly.Id;
      Exception noLatestEx = null;
      try {
        EstimateValidationService.validatePreviousHistory(noLatest);
      } catch (Exception ex) {
        noLatestEx = ex;
      }
      assertRejected('前回契約履歴（最新の受注）が見つかりません', noLatestEx);

      EstimateCreateController.EstimateSaveRequest badMeta = new EstimateCreateController.EstimateSaveRequest();
      badMeta.selectedType = 'New';
      badMeta.effectiveDate = 'not-a-date';
      Exception badEffectiveEx = null;
      try {
        EstimateValidationService.validateHistoryMetaDates(
          badMeta,
          termStart,
          termEnd
        );
      } catch (Exception ex) {
        badEffectiveEx = ex;
      }
      // parseDate は不正文字列で TypeException（Invalid date: ...）を投げる。
      // null 返却→日本語 AuraHandledException には到達しない（本番挙動に合わせる）。
      assertRejected('Invalid date', badEffectiveEx);

      badMeta.effectiveDate = String.valueOf(termStart);
      EstimateValidationService.validateHistoryMetaDates(
        badMeta,
        termStart,
        termEnd
      );

      badMeta.selectedType = 'Renew';
      badMeta.effectiveDate = String.valueOf(termEnd.addDays(1));
      badMeta.previousHistoryId = null;
      Exception renewPrevEx = null;
      try {
        EstimateValidationService.validateHistoryMetaDates(
          badMeta,
          termStart,
          termEnd
        );
      } catch (Exception ex) {
        renewPrevEx = ex;
      }
      assertRejected('前回契約履歴が指定されていません', renewPrevEx);
      Test.stopTest();
    }
  }

  /**
   * 拒否系アサート。例外必須かつ業務メッセージを含むこと（Script-thrown のみは不合格）。
   */
  private static void assertRejected(String expectedSnippet, Exception ex) {
    System.assertNotEquals(null, ex, '例外が発生する想定: ' + expectedSnippet);
    String message = ex.getMessage();
    System.assertNotEquals(null, message, '例外メッセージが空');
    System.assert(
      !message.contains('Script-thrown exception'),
      'setMessage されていない Aura 例外: ' + expectedSnippet
    );
    System.assert(
      message.contains(expectedSnippet),
      '想定「' + expectedSnippet + '」を含むこと。実際: ' + message
    );
  }

  private static Id fakeId(Schema.SObjectType sobjectType, Integer n) {
    String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
    String suffix = String.valueOf(n).leftPad(12, '0');
    return Id.valueOf(keyPrefix + suffix);
  }

  private static ContractService__c insertServiceWithBilling(
    Id accountId,
    String name
  ) {
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = accountId,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
      AdjustInvoiceDateToBusinessDay__c = false
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    ContractService__c service = new ContractService__c(
      Name = name,
      Account__c = accountId,
      BiilingAcccount__c = billingAccount.Id
    );
    insert service;
    return service;
  }

  @IsTest
  static void assertLoadedLifecycle_rejectsBlankAndMismatch() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Exception blankEx = null;
      try {
        EstimateValidationService.assertLoadedLifecycle(
          null,
          ContractDomainConstants.LIFECYCLE_TERM,
          'Change'
        );
      } catch (Exception ex) {
        blankEx = ex;
      }
      assertRejected('バックフィル', blankEx);

      EstimateValidationService.assertLoadedLifecycle(
        ContractDomainConstants.LIFECYCLE_TERM,
        ContractDomainConstants.LIFECYCLE_TERM,
        'Change'
      );

      Exception addOnTermEx = null;
      try {
        EstimateValidationService.assertLoadedLifecycle(
          ContractDomainConstants.LIFECYCLE_TERM,
          ContractDomainConstants.LIFECYCLE_SPOT,
          'Add'
        );
      } catch (Exception ex) {
        addOnTermEx = ex;
      }
      assertRejected('都度契約（Spot）', addOnTermEx);

      Exception changeOnSpotEx = null;
      try {
        EstimateValidationService.assertLoadedLifecycle(
          ContractDomainConstants.LIFECYCLE_SPOT,
          ContractDomainConstants.LIFECYCLE_TERM,
          'Change'
        );
      } catch (Exception ex) {
        changeOnSpotEx = ex;
      }
      assertRejected('Add を選んでください', changeOnSpotEx);
    }
  }
}
