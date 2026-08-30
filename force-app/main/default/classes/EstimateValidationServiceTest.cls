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
              InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
              InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
              InvoiceDateDayOfMonth__c = 25,
              InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
        PaymentTermMonthOffset__c = 0,
        PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
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
          ex.getMessage() != null && ex.getMessage().contains('最新の受注'),
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
      false,
      EstimateValidationService.requiresChangeEffectiveDateOnBillingPeriodStart(
        null
      ),
      '課金イベント0件（null）は切替日必須にしない'
    );
    System.assertEquals(
      false,
      EstimateValidationService.requiresChangeEffectiveDateOnBillingPeriodStart(
        new List<EstimateCreateController.ProductLineItem>()
      ),
      '課金イベント0件は切替日必須にしない（Renew誘導・カスタム専用へ進ませる）'
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

    System.assertEquals(
      false,
      EstimateValidationService.requiresChangeEffectiveDateOnBillingPeriodStart(
        new List<EstimateCreateController.ProductLineItem>{ original, remake }
      ),
      'CHANGE-241: 課金イベント0件は切替日必須にしない'
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
      EstimateValidationService.validateHistoryMetaDates(
        request,
        termStart,
        termEnd
      );

      Id remakeSourceId = fakeId(ContractProduct__c.SObjectType, 88);
      EstimateCreateController.ProductLineItem original = new EstimateCreateController.ProductLineItem();
      original.productId = fakeId(Product2.SObjectType, 99);
      original.quantity = 1;
      original.unitPrice = 8000;
      original.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      original.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      original.startDate = '2026-06-01';
      original.endDate = '2027-05-31';
      original.recordType = 'Original';
      original.sourceContractProductId = remakeSourceId;

      EstimateCreateController.ProductLineItem remakeOffCycle = new EstimateCreateController.ProductLineItem();
      remakeOffCycle.productId = original.productId;
      remakeOffCycle.quantity = 1;
      remakeOffCycle.unitPrice = 9000;
      remakeOffCycle.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeOffCycle.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeOffCycle.startDate = '2026-10-15';
      remakeOffCycle.endDate = '2027-05-31';
      remakeOffCycle.recordType = 'Remake';
      remakeOffCycle.sourceContractProductId = remakeSourceId;

      request.products = new List<EstimateCreateController.ProductLineItem>{
        original,
        remakeOffCycle
      };
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
          '元明細開始日起点から外れた課金イベント日は日割り不可として拒否'
        );
      }
      System.assertEquals(
        true,
        rejected,
        '元明細サイクル外の課金イベント日は拒否'
      );
    }
  }

  @IsTest
  static void validateChangeBillingEventsOnSourceCycle_ignoresHeaderStart() {
    Id fakeProductId = fakeId(Product2.SObjectType, 11);
    Id fakeSourceId = fakeId(ContractProduct__c.SObjectType, 22);

    EstimateCreateController.ProductLineItem original = new EstimateCreateController.ProductLineItem();
    original.productId = fakeProductId;
    original.quantity = 1;
    original.unitPrice = 8000;
    original.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    original.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    original.startDate = '2026-03-01';
    original.endDate = '2027-01-14';
    original.recordType = 'Original';
    original.sourceContractProductId = fakeSourceId;

    EstimateCreateController.ProductLineItem remake = new EstimateCreateController.ProductLineItem();
    remake.productId = fakeProductId;
    remake.quantity = 1;
    remake.unitPrice = 9000;
    remake.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    remake.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    remake.startDate = '2026-05-01';
    remake.endDate = '2027-01-14';
    remake.recordType = 'Remake';
    remake.sourceContractProductId = fakeSourceId;

    List<EstimateCreateController.ProductLineItem> onSourceCycle = new List<EstimateCreateController.ProductLineItem>{
      original,
      remake
    };
    System.assertEquals(
      null,
      EstimateValidationService.validateChangeBillingEventsOnSourceCycle(
        onSourceCycle
      ),
      'ヘッダー1/15基準では5/1は境界外でも、元明細3/1起点なら許可'
    );

    remake.startDate = '2026-05-15';
    System.assertEquals(
      EstimateValidationService.CHANGE_EFFECTIVE_DATE_BILLING_PERIOD_START_MESSAGE,
      EstimateValidationService.validateChangeBillingEventsOnSourceCycle(
        onSourceCycle
      ),
      'ヘッダー1/15基準では5/15は境界でも、元明細3/1起点なら拒否'
    );
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
      '変更後は変更前の期間を重複や隙間なく埋める必要があります。',
      EstimateValidationService.CHANGE_REMAKE_COVERAGE_MESSAGE,
      'Core 第0.1節: 期間カバーの画面文言は変更後／変更前'
    );
    System.assertEquals(
      '変更後の商品明細を1行以上入力してください。',
      EstimateValidationService.validateChangeReconstitutionCoverage(
        original,
        new List<EstimateCreateController.ProductLineItem>()
      ),
      'Core 第0.1節・第4.3.13節: Remake欠落の画面文言は変更後'
    );
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
  static void validateChangeMidTermRemakeSplit_requiresPrePeriodSameAsOriginal() {
    EstimateCreateController.ProductLineItem original = new EstimateCreateController.ProductLineItem();
    original.productId = fakeId(Product2.SObjectType, 31);
    original.quantity = 1;
    original.unitPrice = 30000;
    original.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    original.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
    original.startDate = '2026-04-01';
    original.endDate = '2027-03-31';

    EstimateCreateController.ProductLineItem remakeFullWash = new EstimateCreateController.ProductLineItem();
    remakeFullWash.productId = original.productId;
    remakeFullWash.recordType = 'Remake';
    remakeFullWash.quantity = 1;
    remakeFullWash.unitPrice = 50000;
    remakeFullWash.billingType = original.billingType;
    remakeFullWash.invoiceType = original.invoiceType;
    remakeFullWash.startDate = '2026-04-01';
    remakeFullWash.endDate = '2027-03-31';
    System.assertEquals(
      null,
      EstimateValidationService.validateChangeMidTermRemakeSplit(
        original,
        new List<EstimateCreateController.ProductLineItem>{ remakeFullWash }
      ),
      '全期間1本の単価変更は洗替として許容'
    );

    EstimateCreateController.ProductLineItem remakePost = new EstimateCreateController.ProductLineItem();
    remakePost.productId = original.productId;
    remakePost.recordType = 'Remake';
    remakePost.quantity = 1;
    remakePost.unitPrice = 50000;
    remakePost.billingType = original.billingType;
    remakePost.invoiceType = original.invoiceType;
    remakePost.startDate = '2026-05-01';
    remakePost.endDate = '2027-03-31';

    System.assertEquals(
      '期中切替では、切替日前は変更前と同条件の変更後と、切替日以降の変更後に分けてください。',
      EstimateValidationService.CHANGE_MID_TERM_REMAKE_SPLIT_MESSAGE,
      'Core 第0.1節: 期中切替の画面文言は変更前／変更後'
    );
    System.assertEquals(
      EstimateValidationService.CHANGE_MID_TERM_REMAKE_SPLIT_MESSAGE,
      EstimateValidationService.validateChangeMidTermRemakeSplit(
        original,
        new List<EstimateCreateController.ProductLineItem>{ remakePost }
      ),
      '切替日前 Remake が無い期中差分は拒否'
    );

    EstimateCreateController.ProductLineItem remakePreSame = new EstimateCreateController.ProductLineItem();
    remakePreSame.productId = original.productId;
    remakePreSame.recordType = 'Remake';
    remakePreSame.quantity = 1;
    remakePreSame.unitPrice = 30000;
    remakePreSame.billingType = original.billingType;
    remakePreSame.invoiceType = original.invoiceType;
    remakePreSame.startDate = '2026-04-01';
    remakePreSame.endDate = '2026-04-30';

    System.assertEquals(
      null,
      EstimateValidationService.validateChangeMidTermRemakeSplit(
        original,
        new List<EstimateCreateController.ProductLineItem>{
          remakePreSame,
          remakePost
        }
      ),
      '切替日前同条件＋切替日以降 Remake は通る'
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
    assertRejected('期間開始日は期間終了日以前の日付を入力してください', ex);

    request.contractEndDate = '2027-05-31';
    request.effectiveDate = '2026-06-15';
    ex = null;
    try {
      EstimateValidationService.validateNewSaveRequest(request, 'Name');
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('切替日は期間開始日と一致している必要があります', ex);

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
    assertRejected('開始日は期間開始日以降の日付を入力してください', ex);

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
    EstimateValidationService.validateNewProductPeriodOverlap(
      new List<EstimateCreateController.ProductLineItem>{ left, right }
    );

    EstimateCreateController.ProductLineItem recurringLeft = new EstimateCreateController.ProductLineItem();
    recurringLeft.productId = left.productId;
    recurringLeft.quantity = 1;
    recurringLeft.unitPrice = 1000;
    recurringLeft.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    recurringLeft.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    recurringLeft.startDate = '2026-06-01';
    recurringLeft.endDate = '2026-06-30';
    recurringLeft.recordType = 'New';
    EstimateCreateController.ProductLineItem recurringRight = new EstimateCreateController.ProductLineItem();
    recurringRight.productId = left.productId;
    recurringRight.quantity = 1;
    recurringRight.unitPrice = 1000;
    recurringRight.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    recurringRight.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    recurringRight.startDate = '2026-06-15';
    recurringRight.endDate = '2026-07-15';
    recurringRight.recordType = 'New';
    ex = null;
    try {
      EstimateValidationService.validateNewProductPeriodOverlap(
        new List<EstimateCreateController.ProductLineItem>{
          recurringLeft,
          recurringRight
        }
      );
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('同一商品の契約期間が重複しています', ex);

    EstimateCreateController.ProductLineItem mixedOneTime = new EstimateCreateController.ProductLineItem();
    mixedOneTime.productId = left.productId;
    mixedOneTime.quantity = 1;
    mixedOneTime.unitPrice = 1000;
    mixedOneTime.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    mixedOneTime.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    mixedOneTime.startDate = '2026-06-01';
    mixedOneTime.endDate = '2026-06-30';
    mixedOneTime.recordType = 'New';
    ex = null;
    try {
      EstimateValidationService.validateNewProductPeriodOverlap(
        new List<EstimateCreateController.ProductLineItem>{
          recurringLeft,
          mixedOneTime
        }
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

    EstimateCreateController.ProductLineItem recurringOverlap = new EstimateCreateController.ProductLineItem();
    recurringOverlap.productId = continuation.productId;
    recurringOverlap.quantity = 1;
    recurringOverlap.unitPrice = 1;
    recurringOverlap.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    recurringOverlap.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    recurringOverlap.startDate = '2026-06-01';
    recurringOverlap.endDate = '2026-06-01';
    recurringOverlap.recordType = 'New';
    EstimateCreateController.ProductLineItem recurringOverlapRight = new EstimateCreateController.ProductLineItem();
    recurringOverlapRight.productId = continuation.productId;
    recurringOverlapRight.quantity = 1;
    recurringOverlapRight.unitPrice = 1;
    recurringOverlapRight.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    recurringOverlapRight.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    recurringOverlapRight.startDate = '2026-06-01';
    recurringOverlapRight.endDate = '2026-06-01';
    recurringOverlapRight.recordType = 'New';
    ex = null;
    try {
      EstimateValidationService.validateChangeProductPeriodOverlap(
        new List<EstimateCreateController.ProductLineItem>{
          recurringOverlap,
          recurringOverlapRight
        }
      );
    } catch (Exception e) {
      ex = e;
    }
    assertRejected('同一商品の契約期間が重複しています', ex);

    EstimateValidationService.validateChangeProductPeriodOverlap(
      new List<EstimateCreateController.ProductLineItem>{
        continuation,
        continuation
      }
    );

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
    assertRejected('開始日は期間開始日以降の日付を入力してください', ex);

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
    assertRejected('終了日は期間終了日以前の日付を入力してください', ex);
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

      mismatch.recordType = 'Remake';
      mismatch.sourceContractProductId = available.Id;
      Exception remakeOverrideEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{ mismatch },
          true,
          'EST-S3-New',
          true
        );
      } catch (Exception ex) {
        remakeOverrideEx = ex;
      }
      System.assertEquals(
        null,
        remakeOverrideEx,
        '第4.4.1節: Remakeの課金形態はProduct2へ追従しない'
      );

      mismatch.recordType = 'Renew';
      Exception renewOverrideEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{ mismatch },
          false,
          'EST-S3-Renew',
          true
        );
      } catch (Exception ex) {
        renewOverrideEx = ex;
      }
      System.assertEquals(
        null,
        renewOverrideEx,
        '第4.4.1節: Renewは継続マスタの一回切替を許可する'
      );

      mismatch.recordType = 'Original';
      Exception originalOverrideEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{ mismatch },
          true,
          null,
          true
        );
      } catch (Exception ex) {
        originalOverrideEx = ex;
      }
      System.assertEquals(
        null,
        originalOverrideEx,
        '第4.4.1節: Originalの課金形態はProduct2へ追従しない'
      );

      EstimateCreateController.ProductLineItem renewOneTimeMaster = new EstimateCreateController.ProductLineItem();
      Product2 oneTimeMaster = ContractTestDataFactory.buildProduct('OneTimeMaster');
      oneTimeMaster.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      oneTimeMaster.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(oneTimeMaster);
      renewOneTimeMaster.productId = oneTimeMaster.Id;
      renewOneTimeMaster.quantity = 1;
      renewOneTimeMaster.unitPrice = 1000;
      renewOneTimeMaster.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      renewOneTimeMaster.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      renewOneTimeMaster.startDate = '2026-06-01';
      renewOneTimeMaster.endDate = '2027-05-31';
      renewOneTimeMaster.recordType = 'Renew';
      Exception renewOneTimeMasterEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{
            renewOneTimeMaster
          },
          false,
          'EST-S3-Renew',
          true
        );
      } catch (Exception ex) {
        renewOneTimeMasterEx = ex;
      }
      assertRejected(
        '課金種別が商品マスタと一致しません',
        renewOneTimeMasterEx
      );

      EstimateCreateController.ProductLineItem zeroQty = new EstimateCreateController.ProductLineItem();
      zeroQty.productId = available.Id;
      zeroQty.quantity = 0;
      zeroQty.unitPrice = 1000;
      zeroQty.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      zeroQty.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      zeroQty.startDate = '2026-06-01';
      zeroQty.endDate = '2027-05-31';
      zeroQty.recordType = 'New';
      Exception zeroQtyEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{ zeroQty },
          false,
          'EST-S3-New'
        );
      } catch (Exception ex) {
        zeroQtyEx = ex;
      }
      assertRejected(
        EstimateValidationService.QUANTITY_MIN_MESSAGE,
        zeroQtyEx
      );
      System.assert(
        zeroQtyEx.getMessage()
          .contains(EstimateValidationService.QUANTITY_MIN_MESSAGE),
        '第4.3.9節: 数量0は指定メッセージで拒否する'
      );

      zeroQty.quantity = 0.009;
      Exception belowMinEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{ zeroQty },
          false,
          'EST-S3-New'
        );
      } catch (Exception ex) {
        belowMinEx = ex;
      }
      assertRejected(
        EstimateValidationService.QUANTITY_MIN_MESSAGE,
        belowMinEx
      );
      System.assert(
        belowMinEx.getMessage()
          .contains(EstimateValidationService.QUANTITY_MIN_MESSAGE),
        '第4.3.9節: 数量0.01未満は拒否する'
      );

      zeroQty.quantity = 0;
      zeroQty.recordType = 'Original';
      Exception originalZeroEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{ zeroQty },
          true
        );
      } catch (Exception ex) {
        originalZeroEx = ex;
      }
      assertRejected(
        EstimateValidationService.QUANTITY_MIN_MESSAGE,
        originalZeroEx
      );
      System.assert(
        originalZeroEx.getMessage()
          .contains(EstimateValidationService.QUANTITY_MIN_MESSAGE),
        '第4.3.9節: Originalを含め数量0を保存しない'
      );

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
      service.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
      update service;
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
        '解約済みの契約履歴から解約は作成できません',
        cancelEligEx
      );

      Exception renewEligEx = null;
      try {
        EstimateValidationService.validateRenewEligibility(previous.Id);
      } catch (Exception ex) {
        renewEligEx = ex;
      }
      assertRejected(
        '前回の版の期間終了日と一致する継続課金商品がないため更新できません',
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
        '期間開始日は前回の版の期間終了日の翌日である必要があります',
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
        '解約日は前回の版の期間終了日の翌日である必要があります',
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
        '更新では継続課金商品を1行以上指定してください。一回課金のみの更新はできません。',
        renewOneTimeEx
      );

      Product2 renewSourceProduct = ContractTestDataFactory.buildProduct(
        'Renew Source Locked'
      );
      renewSourceProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      renewSourceProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(renewSourceProduct);
      Product2 renewOtherProduct = ContractTestDataFactory.buildProduct(
        'Renew Other Locked'
      );
      renewOtherProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      renewOtherProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(renewOtherProduct);
      ContractProduct__c renewSourceCp = new ContractProduct__c(
        ContractHistory__c = previous.Id,
        Product__c = renewSourceProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME,
        Type__c = ContractDomainConstants.PRODUCT_TYPE_NEW
      );
      insert renewSourceCp;
      EstimateCreateController.ProductLineItem renewSwapped = new EstimateCreateController.ProductLineItem();
      renewSwapped.productId = renewOtherProduct.Id;
      renewSwapped.quantity = 1;
      renewSwapped.unitPrice = 1000;
      renewSwapped.amount = 12000;
      renewSwapped.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      renewSwapped.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      renewSwapped.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      renewSwapped.startDate = String.valueOf(termEnd.addDays(1));
      renewSwapped.endDate = String.valueOf(
        termEnd.addDays(1).addYears(1).addDays(-1)
      );
      renewSwapped.recordType = 'Renew';
      renewSwapped.sourceContractProductId = renewSourceCp.Id;
      Exception renewProductEx = null;
      try {
        EstimateValidationService.validateRenewProductLineRules(
          new List<EstimateCreateController.ProductLineItem>{ renewSwapped },
          String.valueOf(termEnd.addDays(1)),
          String.valueOf(termEnd.addDays(1).addYears(1).addDays(-1))
        );
      } catch (Exception ex) {
        renewProductEx = ex;
      }
      assertRejected(
        EstimateValidationService.RENEW_PRODUCT_LOCKED_MESSAGE,
        renewProductEx
      );

      Exception cancelProductsEx = null;
      try {
        EstimateValidationService.validateCancelNoProducts(
          new List<EstimateCreateController.ProductLineItem>{ oneTimeOnly }
        );
      } catch (Exception ex) {
        cancelProductsEx = ex;
      }
      assertRejected('解約では商品明細を入力できません', cancelProductsEx);

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
        '解約済みの契約履歴から追加変更は作成できません',
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
        '前回の版の期間終了日と一致する継続課金商品がないため追加変更できません',
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
        '変更前の行に元の見積商品が指定されていません',
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
        '変更後の行の商品は変更前（前回の版）と同じ商品にしてください',
        badRemakeEx
      );

      ContractProduct__c sourceForMatch = new ContractProduct__c(
        Product__c = available.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 96000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
      );
      EstimateCreateController.ProductLineItem mismatchOriginal = new EstimateCreateController.ProductLineItem();
      mismatchOriginal.productId = available.Id;
      mismatchOriginal.quantity = 2;
      mismatchOriginal.unitPrice = 8000;
      mismatchOriginal.amount = -96000;
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
        '変更前の行は前回の版の見積商品と一致している必要があります',
        originalMatchEx
      );

      ContractProduct__c sourceRevenue = new ContractProduct__c(
        Product__c = available.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 96000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
      );
      EstimateCreateController.ProductLineItem revenueMismatch = new EstimateCreateController.ProductLineItem();
      revenueMismatch.productId = available.Id;
      revenueMismatch.quantity = 1;
      revenueMismatch.unitPrice = 8000;
      revenueMismatch.amount = -96000;
      revenueMismatch.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      revenueMismatch.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME;
      revenueMismatch.startDate = String.valueOf(termStart);
      revenueMismatch.endDate = String.valueOf(termEnd);
      Exception revenueMatchEx = null;
      try {
        EstimateValidationService.validateOriginalMatchesSource(
          revenueMismatch,
          sourceRevenue,
          1
        );
      } catch (Exception ex) {
        revenueMatchEx = ex;
      }
      assertRejected(
        '変更前の行は前回の版の見積商品と一致している必要があります',
        revenueMatchEx
      );

      ContractProduct__c sourceAmount = new ContractProduct__c(
        Product__c = available.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 96000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
      );
      EstimateCreateController.ProductLineItem amountMismatch = new EstimateCreateController.ProductLineItem();
      amountMismatch.productId = available.Id;
      amountMismatch.quantity = 1;
      amountMismatch.unitPrice = 8000;
      amountMismatch.amount = 96000;
      amountMismatch.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      amountMismatch.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      amountMismatch.startDate = String.valueOf(termStart);
      amountMismatch.endDate = String.valueOf(termEnd);
      Exception amountMatchEx = null;
      try {
        EstimateValidationService.validateOriginalMatchesSource(
          amountMismatch,
          sourceAmount,
          1
        );
      } catch (Exception ex) {
        amountMatchEx = ex;
      }
      assertRejected(
        '変更前の行は前回の版の見積商品と一致している必要があります',
        amountMatchEx
      );

      ContractProduct__c sourceBilling = new ContractProduct__c(
        Product__c = available.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 96000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );
      EstimateCreateController.ProductLineItem billingMismatch = new EstimateCreateController.ProductLineItem();
      billingMismatch.productId = available.Id;
      billingMismatch.quantity = 1;
      billingMismatch.unitPrice = 8000;
      billingMismatch.amount = -96000;
      billingMismatch.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      billingMismatch.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      billingMismatch.startDate = String.valueOf(termStart);
      billingMismatch.endDate = String.valueOf(termEnd);
      Exception billingMatchEx = null;
      try {
        EstimateValidationService.validateOriginalMatchesSource(
          billingMismatch,
          sourceBilling,
          1
        );
      } catch (Exception ex) {
        billingMatchEx = ex;
      }
      assertRejected(
        '変更前の行は前回の版の見積商品と一致している必要があります',
        billingMatchEx
      );

      EstimateCreateController.ProductLineItem remakeBillingMismatch = new EstimateCreateController.ProductLineItem();
      remakeBillingMismatch.productId = available.Id;
      remakeBillingMismatch.quantity = 1;
      remakeBillingMismatch.unitPrice = 8000;
      remakeBillingMismatch.amount = 96000;
      remakeBillingMismatch.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      remakeBillingMismatch.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeBillingMismatch.startDate = String.valueOf(termStart);
      remakeBillingMismatch.endDate = String.valueOf(termEnd);
      remakeBillingMismatch.recordType = 'Remake';
      remakeBillingMismatch.sourceContractProductId = sourceProduct.Id;
      EstimateCreateController.ProductLineItem remakeOriginal = new EstimateCreateController.ProductLineItem();
      remakeOriginal.productId = available.Id;
      remakeOriginal.quantity = 1;
      remakeOriginal.unitPrice = 8000;
      remakeOriginal.amount = null;
      remakeOriginal.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeOriginal.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeOriginal.startDate = String.valueOf(termStart);
      remakeOriginal.endDate = String.valueOf(termEnd);
      remakeOriginal.recordType = 'Original';
      remakeOriginal.sourceContractProductId = sourceProduct.Id;
      changeReq.products = new List<EstimateCreateController.ProductLineItem>{
        remakeOriginal,
        remakeBillingMismatch
      };
      Exception remakeBillingEx = null;
      try {
        EstimateValidationService.validateChangeProductLineRules(changeReq);
      } catch (Exception ex) {
        remakeBillingEx = ex;
      }
      assertRejected(
        EstimateValidationService.REMAKE_BILLING_TYPE_LOCKED_MESSAGE,
        remakeBillingEx
      );
    }
  }

  @IsTest
  static void assertChangeHistoriesReadyForInvoice_blocksTermOriginalAmountMismatch() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Inv Change Cover Acc'
      );
      ContractService__c service = insertServiceWithBilling(
        account.Id,
        'Inv Change Cover Service'
      );
      service.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
      update service;
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      ContractHistory__c previous = new ContractHistory__c(
        Name = 'Inv Change Cover Previous',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      insert previous;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Inv Change Cover Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c previousProduct = new ContractProduct__c(
        ContractHistory__c = previous.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert previousProduct;
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Inv Change Cover Bad Original',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        PreviousHistory__c = previous.Id,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert changeHistory;
      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 1000,
          Amount__c = 12000,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Original',
          PreviousContractProduct__c = previousProduct.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 2,
          UnitPrice__c = 1000,
          Amount__c = 24000,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = previousProduct.Id
        )
      };

      Exception thrown = null;
      try {
        EstimateValidationService.assertChangeHistoriesReadyForInvoice(
          new Set<Id>{ changeHistory.Id }
        );
      } catch (Exception ex) {
        thrown = ex;
      }
      assertRejected(
        '変更前の行は前回の版の見積商品と一致している必要があります',
        thrown
      );
    }
  }

  @IsTest
  static void assertChangeHistoriesReadyForInvoice_blocksSpotChangeRecurring() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Inv Spot Change Acc'
      );
      ContractService__c service = insertServiceWithBilling(
        account.Id,
        'Inv Spot Change Service'
      );
      service.Lifecycle__c = ContractDomainConstants.LIFECYCLE_SPOT;
      update service;
      ContractHistory__c previous = new ContractHistory__c(
        Name = 'Inv Spot Change Previous',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1
      );
      insert previous;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Inv Spot Change Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(product);
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Inv Spot Change Bad',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        PreviousHistory__c = previous.Id
      );
      insert changeHistory;
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 3000,
        Amount__c = 3000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 1),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      Exception thrown = null;
      try {
        EstimateValidationService.assertChangeHistoriesReadyForInvoice(
          new Set<Id>{ changeHistory.Id }
        );
      } catch (Exception ex) {
        thrown = ex;
      }
      assertRejected(
        EstimateValidationService.SPOT_CHANGE_ONE_TIME_ONLY_MESSAGE,
        thrown
      );
    }
  }

  @IsTest
  static void validateSpotChangeAndSpotNew_pathsCoverLifecycleRules() {
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
      oneTimeLine.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME;

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
      recurringLine.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;

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

      EstimateCreateController.EstimateSaveRequest spotChangeMeta = new EstimateCreateController.EstimateSaveRequest();
      spotChangeMeta.selectedType = ContractDomainConstants.HISTORY_TYPE_CHANGE;
      spotChangeMeta.effectiveDate = String.valueOf(termStart);
      spotChangeMeta.products = new List<EstimateCreateController.ProductLineItem>{
        oneTimeLine
      };
      EstimateValidationService.validateHistoryMetaDates(
        spotChangeMeta,
        termStart,
        termEnd
      );
      System.assertEquals(null, spotChangeMeta.effectiveDate);

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
      newOneTimeOnly.billingAccountId = spotService.BiilingAcccount__c;
      newOneTimeOnly.taxPercent = 10;
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
      downgradeLine.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME;
      EstimateValidationService.validateProductLines(
        new List<EstimateCreateController.ProductLineItem>{ downgradeLine },
        false,
        'EST-S3-New',
        true
      );

      EstimateCreateController.EstimateSaveRequest spotChangeOk = new EstimateCreateController.EstimateSaveRequest();
      spotChangeOk.opportunityId = opportunity.Id;
      spotChangeOk.contractServiceId = spotService.Id;
      spotChangeOk.previousHistoryId = spotOrdered.Id;
      spotChangeOk.selectedType = ContractDomainConstants.HISTORY_TYPE_CHANGE;
      spotChangeOk.contractStartDate = String.valueOf(termStart);
      spotChangeOk.contractEndDate = String.valueOf(termEnd);
      spotChangeOk.effectiveDate = String.valueOf(termStart);
      spotChangeOk.products = new List<EstimateCreateController.ProductLineItem>{
        oneTimeLine
      };
      Test.startTest();
      EstimateValidationService.validateChangeSaveRequest(
        spotChangeOk,
        'Spot Change History'
      );
      Test.stopTest();
      System.assertEquals(null, spotChangeOk.contractStartDate);
      System.assertEquals(null, spotChangeOk.contractEndDate);
      System.assertEquals(null, spotChangeOk.effectiveDate);

      Exception termExpectedSpotEx = null;
      try {
        EstimateValidationService.assertLoadedLifecycle(
          ContractDomainConstants.LIFECYCLE_TERM,
          ContractDomainConstants.LIFECYCLE_SPOT,
          'Change'
        );
      } catch (Exception ex) {
        termExpectedSpotEx = ex;
      }
      assertRejected(
        '都度契約の後続見積は一回課金だけの Change',
        termExpectedSpotEx
      );

      EstimateCreateController.EstimateSaveRequest spotChangeRecurring = new EstimateCreateController.EstimateSaveRequest();
      spotChangeRecurring.opportunityId = opportunity.Id;
      spotChangeRecurring.contractServiceId = spotService.Id;
      spotChangeRecurring.previousHistoryId = spotOrdered.Id;
      spotChangeRecurring.selectedType = ContractDomainConstants.HISTORY_TYPE_CHANGE;
      spotChangeRecurring.products = new List<EstimateCreateController.ProductLineItem>{
        recurringLine
      };
      Exception recurringEx = null;
      try {
        EstimateValidationService.validateChangeSaveRequest(
          spotChangeRecurring,
          'Spot Change Recurring'
        );
      } catch (Exception ex) {
        recurringEx = ex;
      }
      assertRejected('都度契約の Change は一回課金だけです', recurringEx);

      Exception noServiceEx = null;
      try {
        EstimateValidationService.validateChangeSaveRequest(
          new EstimateCreateController.EstimateSaveRequest(),
          'Spot Change No Service'
        );
      } catch (Exception ex) {
        noServiceEx = ex;
      }
      assertRejected('契約サービスを選択してください', noServiceEx);

      EstimateCreateController.EstimateSaveRequest blankName = new EstimateCreateController.EstimateSaveRequest();
      blankName.opportunityId = opportunity.Id;
      blankName.contractServiceId = spotService.Id;
      blankName.previousHistoryId = spotOrdered.Id;
      Exception blankNameEx = null;
      try {
        EstimateValidationService.validateChangeSaveRequest(blankName, '');
      } catch (Exception ex) {
        blankNameEx = ex;
      }
      assertRejected('契約履歴名を入力してください', blankNameEx);

      EstimateCreateController.EstimateSaveRequest noOpp = new EstimateCreateController.EstimateSaveRequest();
      noOpp.contractServiceId = spotService.Id;
      noOpp.previousHistoryId = spotOrdered.Id;
      Exception noOppEx = null;
      try {
        EstimateValidationService.validateChangeSaveRequest(
          noOpp,
          'Spot Change No Opp'
        );
      } catch (Exception ex) {
        noOppEx = ex;
      }
      assertRejected('商談IDが指定されていません', noOppEx);

      EstimateCreateController.EstimateSaveRequest noProducts = new EstimateCreateController.EstimateSaveRequest();
      noProducts.opportunityId = opportunity.Id;
      noProducts.contractServiceId = spotService.Id;
      noProducts.previousHistoryId = spotOrdered.Id;
      noProducts.products = new List<EstimateCreateController.ProductLineItem>();
      Exception noProductsEx = null;
      try {
        EstimateValidationService.validateChangeSaveRequest(
          noProducts,
          'Spot Change No Products'
        );
      } catch (Exception ex) {
        noProductsEx = ex;
      }
      assertRejected('商品明細を1行以上入力してください', noProductsEx);

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

  @IsTest
  static void assertContinuationDoesNotMutateService_rejectsBlankServiceTax() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Blank Tax Continuation Account'
      );
      ContractService__c service = insertServiceWithBilling(
        account.Id,
        'Blank Tax Continuation Service'
      );
      service.TaxPercent__c = null;
      update service;

      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.contractServiceId = service.Id;
      request.selectedType = 'Change';

      Exception ex = null;
      try {
        EstimateValidationService.assertContinuationDoesNotMutateService(
          request
        );
      } catch (Exception caught) {
        ex = caught;
      }
      assertRejected('消費税率が空です', ex);
    }
  }

  @IsTest
  static void assertContinuationDoesNotMutateService_rejectsBlankServiceBillingAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Blank BA Continuation Account'
      );
      ContractService__c service = insertServiceWithBilling(
        account.Id,
        'Blank BA Continuation Service'
      );
      service.BiilingAcccount__c = null;
      update service;

      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.contractServiceId = service.Id;
      request.selectedType = 'Change';

      Exception ex = null;
      try {
        EstimateValidationService.assertContinuationDoesNotMutateService(
          request
        );
      } catch (Exception caught) {
        ex = caught;
      }
      assertRejected('請求アカウントを入力してください', ex);
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
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 25,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
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

      Exception termExpectedSpotEx = null;
      try {
        EstimateValidationService.assertLoadedLifecycle(
          ContractDomainConstants.LIFECYCLE_TERM,
          ContractDomainConstants.LIFECYCLE_SPOT,
          'Change'
        );
      } catch (Exception ex) {
        termExpectedSpotEx = ex;
      }
      assertRejected(
        '都度契約の後続見積は一回課金だけの Change',
        termExpectedSpotEx
      );

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
      assertRejected(
        '都度契約では Change は使えません。一回課金だけの Change を使ってください。',
        changeOnSpotEx
      );
    }
  }

  @IsTest
  static void validateProductLines_rejectsCustomFieldOnlyChange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account account = ContractTestDataFactory.insertAccount(
        'Custom Field Only Change Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Custom Field Only Change Opp'
      );
      ContractService__c service = insertServiceWithBilling(
        account.Id,
        'Custom Field Only Change Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c previousHistory = new ContractHistory__c(
        Name = 'Custom Field Only Previous',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1,
        Opportunity__c = opportunity.Id,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      insert previousHistory;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Custom Field Only Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c previousProduct = new ContractProduct__c(
        ContractHistory__c = previousHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = ContractDomainConstants.PRODUCT_TYPE_NEW,
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME,
        Description__c = 'previous-memo'
      );
      insert previousProduct;

      EstimateCreateController.ProductLineItem original = new EstimateCreateController.ProductLineItem();
      original.productId = product.Id;
      original.quantity = 1;
      original.unitPrice = 1000;
      original.amount = 12000;
      original.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      original.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      original.startDate = String.valueOf(termStart);
      original.endDate = String.valueOf(termEnd);
      original.recordType = 'Original';
      original.sourceContractProductId = previousProduct.Id;
      original.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;

      EstimateCreateController.ProductLineItem remakeCustomOnly = new EstimateCreateController.ProductLineItem();
      remakeCustomOnly.productId = product.Id;
      remakeCustomOnly.quantity = 1;
      remakeCustomOnly.unitPrice = 1000;
      remakeCustomOnly.amount = 12000;
      remakeCustomOnly.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeCustomOnly.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeCustomOnly.startDate = String.valueOf(termStart);
      remakeCustomOnly.endDate = String.valueOf(termEnd);
      remakeCustomOnly.recordType = 'Remake';
      remakeCustomOnly.sourceContractProductId = previousProduct.Id;
      remakeCustomOnly.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      remakeCustomOnly.customFields = new Map<String, Object>{
        'Description__c' => 'changed-memo'
      };

      Exception customOnlyEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{
            original,
            remakeCustomOnly
          },
          true
        );
      } catch (Exception ex) {
        customOnlyEx = ex;
      }
      assertRejected(
        EstimateValidationService.CHANGE_CUSTOM_FIELDS_ONLY_MESSAGE,
        customOnlyEx
      );
      System.assert(
        customOnlyEx.getMessage()
          .contains(EstimateValidationService.CHANGE_CUSTOM_FIELDS_ONLY_MESSAGE),
        '第4.5.2節: カスタム項目だけ変えたChangeは成立させない'
      );

      EstimateCreateController.ProductLineItem remakeWithPrice = new EstimateCreateController.ProductLineItem();
      remakeWithPrice.productId = product.Id;
      remakeWithPrice.quantity = 1;
      remakeWithPrice.unitPrice = 2000;
      remakeWithPrice.amount = 24000;
      remakeWithPrice.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeWithPrice.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeWithPrice.startDate = String.valueOf(termStart);
      remakeWithPrice.endDate = String.valueOf(termEnd);
      remakeWithPrice.recordType = 'Remake';
      remakeWithPrice.sourceContractProductId = previousProduct.Id;
      remakeWithPrice.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      remakeWithPrice.customFields = new Map<String, Object>{
        'Description__c' => 'changed-memo'
      };
      EstimateValidationService.validateProductLines(
        new List<EstimateCreateController.ProductLineItem>{
          original,
          remakeWithPrice
        },
        true
      );
    }
  }

  @IsTest
  static void validateProductLines_rejectsBlankAndInvalidRevenueRecognitionBasis() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct(
        'Validate Revenue Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem blank = new EstimateCreateController.ProductLineItem();
      blank.productId = product.Id;
      blank.quantity = 1;
      blank.unitPrice = 1000;
      blank.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      blank.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      blank.startDate = '2026-06-01';
      blank.endDate = '2027-05-31';
      blank.amount = 12000;
      blank.revenueRecognitionBasis = null;
      Exception blankEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{ blank },
          false,
          'EST-S3-New'
        );
      } catch (Exception ex) {
        blankEx = ex;
      }
      assertRejected('売上計上基準が空です', blankEx);

      blank.revenueRecognitionBasis = 'UnknownBasis';
      Exception invalidEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{ blank },
          false,
          'EST-S3-New'
        );
      } catch (Exception ex) {
        invalidEx = ex;
      }
      assertRejected('売上計上基準は月次計上または一括計上です', invalidEx);

      blank.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      EstimateValidationService.validateProductLines(
        new List<EstimateCreateController.ProductLineItem>{ blank },
        false,
        'EST-S3-New'
      );
    }
  }

  @IsTest
  static void validateProductLines_rejectsRemakeInvoiceOrRevenueMismatch() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Remake Lock Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Remake Lock Opp'
      );
      ContractService__c service = insertServiceWithBilling(
        account.Id,
        'Remake Lock Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c previousHistory = new ContractHistory__c(
        Name = 'Remake Lock Previous',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1,
        Opportunity__c = opportunity.Id,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      insert previousHistory;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Remake Lock Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c previousProduct = new ContractProduct__c(
        ContractHistory__c = previousHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME,
        Type__c = ContractDomainConstants.PRODUCT_TYPE_NEW
      );
      insert previousProduct;

      EstimateCreateController.ProductLineItem original = new EstimateCreateController.ProductLineItem();
      original.productId = product.Id;
      original.quantity = 1;
      original.unitPrice = 1000;
      original.amount = 12000;
      original.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      original.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      original.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      original.startDate = String.valueOf(termStart);
      original.endDate = String.valueOf(termEnd);
      original.recordType = 'Original';
      original.sourceContractProductId = previousProduct.Id;

      EstimateCreateController.ProductLineItem remakeInvoiceChanged = new EstimateCreateController.ProductLineItem();
      remakeInvoiceChanged.productId = product.Id;
      remakeInvoiceChanged.quantity = 1;
      remakeInvoiceChanged.unitPrice = 2000;
      remakeInvoiceChanged.amount = 24000;
      remakeInvoiceChanged.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeInvoiceChanged.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
      remakeInvoiceChanged.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      remakeInvoiceChanged.startDate = String.valueOf(termStart);
      remakeInvoiceChanged.endDate = String.valueOf(termEnd);
      remakeInvoiceChanged.recordType = 'Remake';
      remakeInvoiceChanged.sourceContractProductId = previousProduct.Id;

      Exception invoiceEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{
            original,
            remakeInvoiceChanged
          },
          true
        );
      } catch (Exception ex) {
        invoiceEx = ex;
      }
      assertRejected(
        EstimateValidationService.REMAKE_INVOICE_LOCKED_MESSAGE,
        invoiceEx
      );

      EstimateCreateController.ProductLineItem remakeRevenueChanged = new EstimateCreateController.ProductLineItem();
      remakeRevenueChanged.productId = product.Id;
      remakeRevenueChanged.quantity = 1;
      remakeRevenueChanged.unitPrice = 2000;
      remakeRevenueChanged.amount = 24000;
      remakeRevenueChanged.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeRevenueChanged.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeRevenueChanged.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME;
      remakeRevenueChanged.startDate = String.valueOf(termStart);
      remakeRevenueChanged.endDate = String.valueOf(termEnd);
      remakeRevenueChanged.recordType = 'Remake';
      remakeRevenueChanged.sourceContractProductId = previousProduct.Id;

      Exception revenueEx = null;
      try {
        EstimateValidationService.validateProductLines(
          new List<EstimateCreateController.ProductLineItem>{
            original,
            remakeRevenueChanged
          },
          true
        );
      } catch (Exception ex) {
        revenueEx = ex;
      }
      assertRejected(
        EstimateValidationService.REMAKE_REVENUE_LOCKED_MESSAGE,
        revenueEx
      );
    }
  }

  @IsTest
  static void validateBillingAccount_rejectsBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      Exception ex = null;
      try {
        EstimateValidationService.validateBillingAccount(request);
      } catch (Exception caught) {
        ex = caught;
      }
      assertRejected('請求アカウントを入力してください', ex);
    }
  }
}
