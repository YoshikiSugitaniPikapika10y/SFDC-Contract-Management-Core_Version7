@IsTest
private class OrderCreateControllerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  @IsTest
  static void getOrderContext_returnsEstimateHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();

      OrderCreateController.orderContextProductSelectCount = 0;
      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(
        0,
        OrderCreateController.orderContextProductSelectCount,
        'Core 第4.3.11節・第12.4節: 開く取得で見積商品を取り直さない'
      );

      System.assertEquals(context.history.Id, dto.contractHistoryId);
      System.assertEquals('Estimate', dto.historyStatus);
      System.assertEquals(true, dto.canOrder);
      System.assertEquals(false, dto.isOrdered);
      System.assertEquals(1, dto.products.size());
      System.assertEquals(context.billingAccount.Id, dto.billingAccountId);
      System.assertEquals(
        String.valueOf(context.billingAccount.Id),
        dto.billingAccountKey,
        'Core 第3.3.2節: 受注確認の識別にキーを出す'
      );
      System.assertNotEquals(
        null,
        dto.lastModifiedToken,
        'Core 第4.3.12節: 受注入口は契約履歴の版トークンを返す'
      );
      System.assertEquals(
        ContractOptimisticLockUtil.toHistoryProductToken(context.history.Id),
        dto.lastModifiedToken,
        'Core 第4.3.11節: 見積商品は1回取り、版トークンにも使う'
      );
      System.assertEquals(
        BillingScheduleService.METHOD_MONTH_OFFSET,
        dto.billingCustomFields.get('PaymentTermMethod__c')
      );
      System.assertEquals(
        25,
        dto.billingCustomFields.get('InvoiceDateDayOfMonth__c')
      );
      System.assertEquals(
        BillingScheduleService.ADJUST_NONE,
        dto.billingCustomFields.get('InvoiceDateAdjust__c')
      );
    }
  }

  @IsTest
  static void getOrderContext_nullId_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        OrderCreateController.getOrderContext(null);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '契約履歴IDが指定されていません。',
          ex.getMessage(),
          'Core 第5.2節: 契約履歴Idが空のときはこの文で拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getOrderContext_missingHistory_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Id missingId =
        ContractHistory__c.SObjectType.getDescribe().getKeyPrefix() +
        '000000000000AAA';
      Boolean thrown = false;
      try {
        OrderCreateController.getOrderContext(missingId);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '契約履歴が見つかりません。',
          ex.getMessage(),
          'Core 第5.2節: 照会結果が0件のときはこの文で拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getOrderContext_withoutOrderAndRevertPermission_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.testHasOrderPermission = false;
      OrderCreateController.testHasRevertPermission = false;
      Boolean thrown = false;
      try {
        OrderCreateController.getOrderContext(context.history.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          'この操作を実行する権限がありません。',
          ex.getMessage(),
          '共通基盤 第10.4節: 受注06も差し戻し07も無い入口は拒否する'
        );
      } finally {
        OrderCreateController.testHasOrderPermission = true;
        OrderCreateController.testHasRevertPermission = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getOrderContext_withoutBillingAccount_leavesNamesBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      context.service.BiilingAcccount__c = null;
      update context.service;
      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(null, dto.billingAccountId);
      System.assertEquals(
        null,
        dto.billingAccountName,
        '請求アカウントが空なら名前も空'
      );
      System.assertEquals(null, dto.billingCustomerAccountName);
    }
  }

  @IsTest
  static void getOrderContext_orderedHistory_exposesRevertFlags() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      Test.startTest();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      // ???E ????????E??????E????????E????E??E???E?????????
      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );

      System.assertEquals(true, dto.isOrdered);
      System.assertEquals(false, dto.canOrder, '????E???????E???E');
      System.assertEquals(
        true,
        dto.canRevert,
        '???????????E??????????????'
      );
      System.assertEquals(null, dto.revertBlockedReason);
      System.assertEquals(
        false,
        dto.showCreateRenewOpportunity,
        '???E??E???E??????????????E'
      );
      System.assert(
        dto.products != null && !dto.products.isEmpty(),
        '?????E????????'
      );
      System.assertEquals(
        context.billingAccount.BillingEmailTo__c,
        dto.billingEmailTo
      );

      OrderCreateController.testHasRevertPermission = false;
      try {
        OrderCreateController.OrderContextDto noPermDto = OrderCreateController.getOrderContext(
          context.history.Id
        );
        System.assertEquals(
          false,
          noPermDto.canRevert,
          '?????????????E????????'
        );
      } finally {
        OrderCreateController.testHasRevertPermission = true;
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void confirmOrder_alreadyOrdered_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      Boolean thrown = false;
      try {
        OrderCreateController.confirmOrder(context.history.Id, null, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '見積状態の契約履歴のみ編集できます。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      ContractHistory__c stillOrdered = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Ordered', stillOrdered.historystatus__c);
    }
  }

  @IsTest
  static void confirmOrder_nullId_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        OrderCreateController.confirmOrder(null, null, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '契約履歴IDが指定されていません。',
          ex.getMessage(),
          'Core 第5.2節: 契約履歴Idが空のときはこの文で拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void confirmOrder_missingHistory_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Id missingId =
        ContractHistory__c.SObjectType.getDescribe().getKeyPrefix() +
        '000000000000AAA';
      Boolean thrown = false;
      try {
        OrderCreateController.confirmOrder(missingId, null, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '契約履歴が見つかりません。',
          ex.getMessage(),
          'Core 第5.2節: 照会結果が0件のときはこの文で拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void revertOrder_withoutPermission_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      OrderCreateController.testHasRevertPermission = false;
      Boolean thrown = false;
      try {
        OrderCreateController.revertOrder(context.history.Id, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '差し戻しを実行する権限がありません。',
          ex.getMessage()
        );
      } finally {
        OrderCreateController.testHasRevertPermission = true;
      }
      System.assertEquals(true, thrown);

      ContractHistory__c stillOrdered = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals(
        'Ordered',
        stillOrdered.historystatus__c,
        '??????????E???????E'
      );
    }
  }

  @IsTest
  static void revertOrder_staleLastModifiedToken_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      String staleToken = ContractOptimisticLockUtil.toToken(
        Datetime.now().addDays(-1)
      );
      Boolean thrown = false;
      try {
        OrderCreateController.revertOrder(
          context.history.Id,
          false,
          staleToken
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      ContractHistory__c stillOrdered = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Ordered', stillOrdered.historystatus__c);
    }
  }

  @IsTest
  static void resolvePreviewScope_historyServiceAndInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Invoice__c invoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];

      OrderCreateController.PreviewScopeDto fromHistory = OrderCreateController.resolvePreviewScope(
        context.history.Id
      );
      System.assertEquals(true, fromHistory.canOpen);
      System.assertEquals('ContractHistory__c', fromHistory.objectApiName);
      System.assertEquals(context.history.Id, fromHistory.contractHistoryId);
      System.assertEquals('1', fromHistory.initialVersion);
      System.assertEquals(null, fromHistory.initialInvoiceId);

      OrderCreateController.PreviewScopeDto fromService = OrderCreateController.resolvePreviewScope(
        context.service.Id
      );
      System.assertEquals(true, fromService.canOpen);
      System.assertEquals('ALL', fromService.initialVersion);
      System.assertEquals(context.history.Id, fromService.contractHistoryId);

      OrderCreateController.PreviewScopeDto fromInvoice = OrderCreateController.resolvePreviewScope(
        invoice.Id
      );
      System.assertEquals(true, fromInvoice.canOpen);
      System.assertEquals(invoice.Id, fromInvoice.initialInvoiceId);
      System.assertEquals('1', fromInvoice.initialVersion);
    }
  }

  @IsTest
  static void getInvoicePreview_secondCallReusesHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      Test.startTest();
      Integer firstBefore = Limits.getQueries();
      OrderCreateController.getInvoicePreview(context.history.Id);
      Integer firstUsed = Limits.getQueries() - firstBefore;
      Integer secondBefore = Limits.getQueries();
      OrderCreateController.InvoicePreviewDto second = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Integer secondUsed = Limits.getQueries() - secondBefore;
      Test.stopTest();

      System.assert(
        secondUsed < firstUsed,
        'Core 第12.4節・第7.7.0節: 同一処理で契約履歴を取り直さない'
      );
      System.assert(
        second.invoiceCount > 0,
        'Core 第7.7.0節: 返却カードは変えない'
      );
    }
  }

  @IsTest
  static void getInvoicePreview_loadsBillingAccountsWithoutSecondHistorySelect() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      BillingAccount__c second = ContractTestDataFactory.insertBillingAccount(
        context.account.Id
      );

      ContractHistory__c loadedHistory = [
        SELECT Id, ContractService__r.Account__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      Map<Id, BillingAccount__c> expectedById = new Map<Id, BillingAccount__c>(
        [
          SELECT Id, Name
          FROM BillingAccount__c
          WHERE Account__c = :loadedHistory.ContractService__r.Account__c
        ]
      );

      OrderCreateController.previewHistorySelectCount = 0;
      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        loadedHistory.Id
      );
      Integer afterPreview = OrderCreateController.previewHistorySelectCount;
      List<OrderCreateController.BillingAccountOptionDto> reused = OrderCreateController.getBillingAccountOptionsForPreview(
        loadedHistory.Id
      );
      Integer afterOptions = OrderCreateController.previewHistorySelectCount;
      Test.stopTest();

      System.assertEquals(
        afterPreview,
        afterOptions,
        'Core 第12.4節・第4.3.11節: 同一処理で契約履歴を取り直さない'
      );
      System.assertEquals(
        expectedById.size(),
        preview.billingAccountOptions.size(),
        'Core 第12.4節: 返す請求アカウント候補は変えない'
      );
      Set<Id> previewIds = new Set<Id>();
      for (
        OrderCreateController.BillingAccountOptionDto option : preview.billingAccountOptions
      ) {
        previewIds.add(option.id);
        System.assertEquals(
          expectedById.get(option.id).Name,
          option.name,
          'Core 第12.4節: 返す請求アカウント名は変えない'
        );
      }
      System.assertEquals(
        true,
        previewIds.contains(context.billingAccount.Id)
      );
      System.assertEquals(true, previewIds.contains(second.Id));
      System.assertEquals(
        preview.billingAccountOptions.size(),
        reused.size(),
        'Core 第12.4節: 載せ済み候補と第二入口の結果は同じ'
      );
    }
  }

  @IsTest
  static void getInvoicePreview_doesNotRereadHistoryForOrderedSummary() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      ContractHistory__c ordered = [
        SELECT DeltaAmountSum__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];

      OrderCreateController.lastPreviewOrderedHistoryQueryIds = new Set<Id>();
      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Test.stopTest();

      System.assertEquals(
        false,
        OrderCreateController.lastPreviewOrderedHistoryQueryIds.contains(
          context.history.Id
        ),
        'Core 第12.4節・第4.3.11節・第7.7.0節: 入口で読んだ契約履歴をOrdered集計で取り直さない'
      );
      System.assertEquals(
        false,
        preview.versionOptions.isEmpty(),
        'Core 第7.7.0節: 返すカードのVersionは変えない'
      );
      System.assertEquals(
        ordered.DeltaAmountSum__c,
        preview.versionOptions[0].periodLineAmountTotal,
        'Core 第7.8.5節: 見積税抜はDeltaAmountSum__c'
      );
    }
  }

  @IsTest
  static void getInvoicePreview_doesNotRereadPeriodLinesForManualAdjustment() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      List<InvoiceLine__c> lines = [
        SELECT Amount__c, SourcePeriodLineIds__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :context.history.Id
      ];
      Set<Id> periodIds = new Set<Id>();
      Decimal lineTotal = 0;
      for (InvoiceLine__c line : lines) {
        if (String.isBlank(line.SourcePeriodLineIds__c)) {
          continue;
        }
        lineTotal += line.Amount__c == null ? 0 : line.Amount__c;
        for (String part : line.SourcePeriodLineIds__c.split(',')) {
          String trimmed = part == null ? null : part.trim();
          if (String.isBlank(trimmed)) {
            continue;
          }
          periodIds.add((Id) trimmed);
        }
      }
      Decimal periodTotal = 0;
      for (InvoiceProduct__c period : [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE Id IN :periodIds
      ]) {
        periodTotal += period.Amount__c == null ? 0 : period.Amount__c;
      }
      Decimal expectedAdjustment = lineTotal - periodTotal;

      OrderCreateController.previewPeriodSelectCount = 0;
      InvoicePreviewIntegrityService.lastLoadedPeriods = new Map<Id, InvoiceProduct__c>();
      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Test.stopTest();

      System.assertEquals(
        false,
        periodIds.isEmpty(),
        'Core 第7.7.0節: 生成元期間明細がある請求で入口を見る'
      );
      System.assertEquals(
        periodIds,
        InvoicePreviewIntegrityService.lastLoadedPeriods.keySet(),
        'Core 第12.4節: 履歴一致検査が期間明細を読む'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewPeriodSelectCount,
        'Core 第12.4節・第4.3.11節・第7.7.0節: 同一取得で手直し集計が同じ期間明細を取り直さない'
      );
      System.assertEquals(
        expectedAdjustment,
        preview.manualAdjustmentAmount,
        'Core 第7.7.0節: 手直し額は変えない'
      );
    }
  }

  @IsTest
  static void getInvoicePreview_doesNotRereadEstimateProductsForDrift() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      List<InvoiceLine__c> lines = [
        SELECT Amount__c, ContractProduct__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :context.history.Id
      ];
      Set<Id> productIds = new Set<Id>();
      Decimal lineTotal = 0;
      for (InvoiceLine__c line : lines) {
        lineTotal += line.Amount__c == null ? 0 : line.Amount__c;
        if (line.ContractProduct__c != null) {
          productIds.add(line.ContractProduct__c);
        }
      }
      Map<Id, Decimal> amountByProductId = new Map<Id, Decimal>();
      for (ContractProduct__c product : [
        SELECT Id, Amount__c
        FROM ContractProduct__c
        WHERE Id IN :productIds
      ]) {
        amountByProductId.put(
          product.Id,
          product.Amount__c == null ? 0 : product.Amount__c
        );
      }

      OrderCreateController.previewProductSelectCount = 0;
      OrderCreateController.previewLineProductsById = new Map<Id, ContractProduct__c>();
      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Test.stopTest();

      System.assertEquals(
        false,
        productIds.isEmpty(),
        'Core 第7.7節: 明細関連の見積商品がある請求で入口を見る'
      );
      System.assertEquals(
        productIds,
        OrderCreateController.previewLineProductsById.keySet(),
        'Core 第12.4節: 請求・明細1回照会が見積商品を載せる'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewProductSelectCount,
        'Core 第12.4節・第4.3.11節・第7.7節: 同一取得で端数ずれ集計が同じ見積商品を取り直さない'
      );

      Decimal previewLineTotal = 0;
      Decimal previewSourceTotal = 0;
      Decimal previewDeltaTotal = 0;
      for (OrderCreateController.InvoiceGroupDto invoice : preview.invoices) {
        if (invoice == null || invoice.lines == null) {
          continue;
        }
        for (OrderCreateController.InvoiceMergedLineDto row : invoice.lines) {
          if (row == null) {
            continue;
          }
          previewLineTotal += row.amount == null ? 0 : row.amount;
          previewSourceTotal += row.sourceAmountTotal == null
            ? 0
            : row.sourceAmountTotal;
          previewDeltaTotal += row.amountDeltaFromSource == null
            ? 0
            : row.amountDeltaFromSource;
          if (row.sourceAmountTotal != null) {
            System.assertEquals(
              (row.amount == null ? 0 : row.amount) - row.sourceAmountTotal,
              row.amountDeltaFromSource,
              'Core 第7.7節: 明細の見積ずれは請求明細金額−見積按分'
            );
          }
        }
      }
      System.assertEquals(
        lineTotal,
        previewLineTotal,
        'Core 第7.7節: 請求明細金額は変えない'
      );
      System.assertEquals(
        previewLineTotal - previewSourceTotal,
        previewDeltaTotal,
        'Core 第7.7節: 明細の見積ずれ合計は変えない'
      );
      System.assertEquals(
        false,
        amountByProductId.isEmpty(),
        'Core 第7.7節: 見積商品Amountがある'
      );
    }
  }

  @IsTest
  static void getInvoicePreview_nullId_returnsEmptyDefaults() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        null
      );
      System.assertEquals(0, preview.totalAmount);
      System.assertEquals(0, preview.totalTaxAmount);
      System.assertEquals(0, preview.invoiceCount);
      System.assertEquals(0, preview.lineCount);
      System.assertEquals(0, preview.invoices.size());
      System.assertEquals(0, preview.versionOptions.size());
      System.assertEquals(false, preview.canView);
      System.assertEquals(false, preview.canEdit);
      System.assertEquals(false, preview.hasManualAdjustment);
      System.assertEquals(0, preview.amountDifference);
    }
  }

  @IsTest
  static void getInvoicePreview_blankInvoiceSendMode_errorsInsteadOfNull() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = null;
      update setting;
      ContractDocumentSettingService.clearCache();

      Exception thrown = null;
      try {
        OrderCreateController.getInvoicePreview(context.history.Id);
      } catch (AuraHandledException ex) {
        thrown = ex;
      }
      System.assertNotEquals(
        null,
        thrown,
        'Core 第11.3節・第1.1.10節: 請求書3択が空ならボード取得をエラーにする'
      );
      System.assertEquals(
        ContractDocumentSettingService.INVALID_SEND_MODE_MESSAGE,
        thrown.getMessage()
      );
    }
  }

  @IsTest
  static void getInvoicePreview_withoutViewPermission_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      ContractPermissionUtil.testAllowAll = false;
      Boolean thrown = false;
      try {
        OrderCreateController.getInvoicePreview(context.history.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '請求ボードを表示する権限がありません。',
          ex.getMessage()
        );
      } finally {
        ContractPermissionUtil.testAllowAll = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getInvoicePreview_withEditPermissionOnly_succeeds() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      ContractPermissionUtil.testAllowAll = false;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.EDIT_DRAFT_INVOICE => true
      };
      try {
        OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
          context.history.Id
        );
        System.assertNotEquals(null, preview);
      } finally {
        ContractPermissionUtil.testOverrides = null;
        ContractPermissionUtil.testAllowAll = true;
      }
    }
  }

  @IsTest
  static void getBillingAccountOptionsForPreview_returnsAccountBillingAccounts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      BillingAccount__c second = ContractTestDataFactory.insertBillingAccount(
        context.account.Id
      );

      List<OrderCreateController.BillingAccountOptionDto> options = OrderCreateController.getBillingAccountOptionsForPreview(
        context.history.Id
      );
      Set<Id> optionIds = new Set<Id>();
      for (OrderCreateController.BillingAccountOptionDto option : options) {
        optionIds.add(option.id);
        System.assertNotEquals(null, option.name);
      }
      System.assertEquals(true, optionIds.contains(context.billingAccount.Id));
      System.assertEquals(true, optionIds.contains(second.Id));
      System.assertEquals(2, options.size());
    }
  }

  @IsTest
  static void resetLatestVersionInvoicesToPostOrder_blankVersion_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Test.startTest();
      String token = OrderCreateController.getInvoicePreview(
        context.history.Id
      )
      .contentVersion;
      Boolean thrown = false;
      try {
        OrderCreateController.resetLatestVersionInvoicesToPostOrder(
          context.history.Id,
          '',
          token
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          OrderCreateController.RESET_POST_ORDER_VERSION_REQUIRED_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      Test.stopTest();
    }
  }

  @IsTest
  static void resetLatestVersionInvoicesToPostOrder_unknownVersion_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Test.startTest();
      String token = OrderCreateController.getInvoicePreview(
        context.history.Id
      )
      .contentVersion;
      Boolean thrown = false;
      try {
        OrderCreateController.resetLatestVersionInvoicesToPostOrder(
          context.history.Id,
          '99',
          token
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          OrderCreateController.RESET_POST_ORDER_VERSION_NOT_FOUND_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      Test.stopTest();
    }
  }

  @IsTest
  static void confirmOrder_staleLastModifiedToken_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      String staleToken = ContractOptimisticLockUtil.toToken(
        Datetime.now().addDays(-1)
      );
      try {
        OrderCreateController.confirmOrder(
          context.history.Id,
          null,
          false,
          staleToken
        );
        System.assert(false, 'Expected optimistic lock conflict');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
    }
  }

  @IsTest
  static void confirmOrder_matchingLastModifiedToken_succeeds() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      ContractOptimisticLockUtil.productMaxSelectCount = 0;
      OrderCreateController.confirmOrder(
        context.history.Id,
        null,
        false,
        dto.lastModifiedToken
      );
      System.assertEquals(
        0,
        ContractOptimisticLockUtil.productMaxSelectCount,
        'Core 第12.4節: 受注の版比較はロック照会の見積商品を使い MAX を取り直さない'
      );
      ContractHistory__c ordered = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Ordered', ordered.historystatus__c);
    }
  }

  @IsTest
  static void confirmOrder_writesInvoicingPathWithoutRereadingHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      ContractHistory__c locked = [
        SELECT
          Id,
          Type__c,
          historystatus__c,
          StatusPath__c,
          InvoiceCount__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Estimate', locked.historystatus__c);
      ContractHistoryStatusPathService.invoiceParentSelectCount = 0;

      Test.startTest();
      OrderCreateController.confirmOrder(locked.Id, null, false);
      Test.stopTest();

      ContractHistory__c ordered = [
        SELECT StatusPath__c, InvoiceCount__c, historystatus__c, Type__c
        FROM ContractHistory__c
        WHERE Id = :locked.Id
      ];
      System.assertEquals('Ordered', ordered.historystatus__c);
      System.assertEquals('New', ordered.Type__c);
      System.assert(
        ordered.InvoiceCount__c > 0,
        'Core 第5.2節: Cancel以外の受注は請求を作る'
      );
      System.assertEquals(
        'Invoicing',
        ordered.StatusPath__c,
        'Core 第5.7節: 取消済みを除く請求があれば請求対応中'
      );
      System.assertEquals(
        0,
        ContractHistoryStatusPathService.invoiceParentSelectCount,
        'Core 第12.4節: 同一処理で対象履歴を取り直さない'
      );
    }
  }

  @IsTest
  static void confirmOrder_reusesValidatedProductsAndLockedLifecycle() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      ContractHistory__c locked = [
        SELECT
          Id,
          Type__c,
          ContractService__c,
          ContractService__r.Lifecycle__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      OrderCreateController.renewLifecycleSelectCount = 0;
      OrderCreateController.renewProductSelectCount = 0;

      Test.startTest();
      OrderCreateController.confirmOrder(locked.Id, null, false);
      Test.stopTest();

      System.assertEquals(
        0,
        OrderCreateController.renewProductSelectCount,
        'Core 第5.2節・第12.4節: 検証済み見積商品を取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.renewLifecycleSelectCount,
        'Core 第5.2節・第12.4節: ロック行の Lifecycle を取り直さない'
      );
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :locked.Id
        ]
        .historystatus__c
      );
    }
  }

  @IsTest
  static void confirmOrder_emptyLastModifiedToken_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      try {
        OrderCreateController.confirmOrder(
          context.history.Id,
          null,
          false,
          null
        );
        System.assert(false, 'Expected required token error');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          OrderCreateController.ORDER_TOKEN_REQUIRED_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        'Estimate',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .historystatus__c
      );
    }
  }

  @IsTest
  static void confirmOrder_secondSubmitWithSameToken_throwsConflict() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      String token = OrderCreateController.getOrderContext(
        context.history.Id
      )
      .lastModifiedToken;

      OrderCreateController.confirmOrder(
        context.history.Id,
        null,
        false,
        token
      );
      try {
        OrderCreateController.confirmOrder(
          context.history.Id,
          null,
          false,
          token
        );
        System.assert(false, 'Expected duplicate submit conflict');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE
            ContractService__c = :context.service.Id
            AND Version__c = 1
            AND historystatus__c = 'Ordered'
        ],
        '?? Version ????????E'
      );
    }
  }

  @IsTest
  static void updateInvoiceLineAmounts_staleContentVersion_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      System.assertNotEquals(null, preview.contentVersion);
      System.assert(preview.invoices != null && !preview.invoices.isEmpty());
      System.assertEquals(
        'Draft',
        preview.invoices[0].invoiceTransactionStatus
      );
      System.assertEquals(true, preview.invoices[0].canConfirm);
      System.assertEquals(false, preview.invoices[0].canUnconfirm);
      System.assertNotEquals(null, preview.invoices[0].lastModifiedToken);
      Id lineId = null;
      for (OrderCreateController.InvoiceGroupDto inv : preview.invoices) {
        if (inv.lines != null && !inv.lines.isEmpty()) {
          lineId = inv.lines[0].lineId;
          break;
        }
      }
      System.assertNotEquals(null, lineId, '????????E??????');

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      String staleVersion = ContractOptimisticLockUtil.toToken(
        Datetime.now().addDays(-1)
      );
      try {
        OrderCreateController.updateInvoiceLineAmount(
          context.history.Id,
          lineId,
          1,
          staleVersion
        );
        System.assert(false, 'Expected preview content conflict');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void previewEdit_blankContentVersion_throwsConflict() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      InvoiceLine__c line = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :context.history.Id
        LIMIT 1
      ];

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      try {
        OrderCreateController.updateInvoiceLineAmount(
          context.history.Id,
          line.Id,
          line.Amount__c,
          null
        );
        System.assert(false, 'Expected required preview content token');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
    }
  }

  @IsTest
  static void revertOrder_blankLastModifiedToken_throwsConflict() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      try {
        OrderCreateController.revertOrder(context.history.Id, false, null);
        System.assert(false, 'Expected required history token');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
    }
  }

  @IsTest
  static void resetLatestVersionInvoicesToPostOrder_blankContentVersion_throwsConflict() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Test.startTest();
      try {
        OrderCreateController.resetLatestVersionInvoicesToPostOrder(
          context.history.Id,
          '1',
          null
        );
        System.assert(false, 'Expected required preview content token');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void previewEdits_rejectTargetsFromAnotherContractService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext own = createEstimateContext();
      OrderCreateController.confirmOrder(own.history.Id, null, false);
      String ownContentVersion = OrderCreateController.getInvoicePreview(
        own.history.Id
      ).contentVersion;

      Test.startTest();
      OrderTestContext other = createEstimateContext();
      OrderCreateController.confirmOrder(other.history.Id, null, false);

      InvoiceLine__c otherLine = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :other.history.Id
        LIMIT 1
      ];
      Invoice__c otherInvoice = [
        SELECT Id, InvoiceDate__c, PaymentScheduledDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :other.history.Id
        LIMIT 1
      ];

      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Boolean lineRejected = false;
      try {
        OrderCreateController.updateInvoiceLineAmount(
          own.history.Id,
          otherLine.Id,
          otherLine.Amount__c + 1,
          ownContentVersion
        );
      } catch (AuraHandledException ex) {
        lineRejected = true;
        System.assertEquals(
          OrderCreateController.PREVIEW_SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, lineRejected, '???????????E?????E');

      Boolean invoiceRejected = false;
      try {
        OrderCreateController.updateInvoiceHeaderAndDates(
          own.history.Id,
          otherInvoice.Id,
          otherInvoice.InvoiceDate__c,
          Date.newInstance(2027, 12, 31),
          null,
          null,
          null,
          null,
          10,
          ownContentVersion
        );
      } catch (AuraHandledException ex) {
        invoiceRejected = true;
        System.assertEquals(
          OrderCreateController.PREVIEW_SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        invoiceRejected,
        '?????????E??E?????E'
      );

      Boolean acceptancePreviewRejected = false;
      try {
        OrderCreateController.previewInvoiceLineAcceptanceEndDate(
          otherLine.Id,
          Date.today(),
          null,
          own.history.Id
        );
      } catch (AuraHandledException ex) {
        acceptancePreviewRejected = true;
        System.assertEquals(
          OrderCreateController.PREVIEW_SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        acceptancePreviewRejected,
        'Core 第7.7.3節: 契約サービスをまたいで検収日変更プレビューできない'
      );
      Test.stopTest();

      System.assertEquals(
        otherLine.Amount__c,
        [SELECT Amount__c FROM InvoiceLine__c WHERE Id = :otherLine.Id]
        .Amount__c,
        '????E????????????????E'
      );
      System.assertEquals(
        otherInvoice.PaymentScheduledDate__c,
        [
          SELECT PaymentScheduledDate__c
          FROM Invoice__c
          WHERE Id = :otherInvoice.Id
        ]
        .PaymentScheduledDate__c,
        '????E????????????????E'
      );
    }
  }

  @IsTest
  static void cancelConfirmedFromPreview_rejectsInvoiceOutsideContractService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext own = createEstimateContext();
      OrderCreateController.confirmOrder(own.history.Id, null, false);

      Test.startTest();
      OrderTestContext other = createEstimateContext();
      OrderCreateController.confirmOrder(other.history.Id, null, false);
      Invoice__c otherInvoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :other.history.Id
        LIMIT 1
      ];
      otherInvoice.SystemIntegrationDate__c = Date.today();
      otherInvoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      update otherInvoice;
      InvoiceTransactionStatusService.allowStatusWrite = false;

      Boolean rejected = false;
      try {
        OrderCreateController.cancelConfirmedFromPreview(
          own.history.Id,
          otherInvoice.Id,
          'Duplicate',
          null,
          null,
          null
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assertEquals(
          OrderCreateController.PREVIEW_SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      Test.stopTest();

      System.assertEquals(
        true,
        rejected,
        'Core 第7.7.3節: 契約サービスをまたいで請求取消できない'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.TX_CONFIRMED,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :otherInvoice.Id
        ]
        .InvoiceTransactionStatus__c
      );
    }
  }

  @IsTest
  static void cancelConfirmedFromPreview_cancelsConfirmedInScope() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Invoice__c invoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      Integer invoicesBeforeCancel = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
      ];
      invoice.SystemIntegrationDate__c = Date.today();
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      update invoice;
      InvoiceTransactionStatusService.allowStatusWrite = false;
      String token = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );

      Test.startTest();
      OrderCreateController.previewInvoiceSelectCount = 0;
      OrderCreateController.lastPreviewInvoiceSelectIds = new Set<Id>();
      InvoiceOpsFieldService.extraFieldSelectCount = 0;
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.cancelConfirmedFromPreview(
        context.history.Id,
        invoice.Id,
        'Duplicate',
        null,
        null,
        token
      );
      Test.stopTest();

      System.assertNotEquals(
        null,
        preview,
        'Core 第7.7.0節: 返却カードを返す'
      );
      System.assertEquals(
        false,
        OrderCreateController.lastPreviewInvoiceSelectIds.contains(invoice.Id),
        'Core 第12.4節・第7.9.3節: 取消した請求をgetInvoicePreviewで取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceOpsFieldService.extraFieldSelectCount,
        'Core 第7.7.0節・第12.4節: 追加項目定義を請求から取り直さない'
      );

      System.assertEquals(
        InvoiceTransactionStatusService.TX_CANCELLED,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :invoice.Id
        ]
        .InvoiceTransactionStatus__c,
        'Core 第7.9.3節: 範囲内の確定済みは取り消す'
      );

      Integer cancelledCards = 0;
      Integer activeCards = 0;
      for (OrderCreateController.InvoiceGroupDto card : preview.invoices) {
        if (card == null) {
          continue;
        }
        if (card.isCancelled == true) {
          cancelledCards++;
          if (card.lines == null) {
            continue;
          }
          for (OrderCreateController.InvoiceMergedLineDto row : card.lines) {
            System.assertEquals(
              false,
              row.hasAmountDrift,
              'Core 第7.7.0節・第7.8.5節: 取消済み明細は端数按分の母に入れない'
            );
          }
        } else {
          activeCards++;
          if (card.lines == null) {
            continue;
          }
          for (OrderCreateController.InvoiceMergedLineDto row : card.lines) {
            System.assertEquals(
              false,
              row.hasAmountDrift,
              'Core 第7.8.5節: 訂正用は取消済みと期間IDを共有しても偽の端数ありにしない'
            );
          }
        }
      }
      System.assertEquals(
        1,
        cancelledCards,
        'Core 第7.9.3節: 取消済みカードを返す'
      );
      String originalName = [
        SELECT Name
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ]
      .Name;
      String correctionNameOnCard;
      Id correctionId;
      for (OrderCreateController.InvoiceGroupDto card : preview.invoices) {
        if (card == null || card.isCancelled == true) {
          continue;
        }
        correctionId = card.invoiceId;
        correctionNameOnCard = card.invoiceName;
      }
      System.assertNotEquals(
        null,
        correctionId,
        'Core 第7.9.3節: 訂正用カードを返す'
      );
      System.assertEquals(
        false,
        String.isBlank(correctionNameOnCard),
        'Core 第7.9.3節・第7.7.0節: 訂正用カードの見出しは請求番号'
      );
      System.assertNotEquals(
        '—',
        correctionNameOnCard,
        'Core 第7.9.3節・第7.7.0節: 訂正用カードの見出しを — にしない'
      );
      System.assertNotEquals(
        originalName,
        correctionNameOnCard,
        'Core 第7.9.3節: 新しい請求名は自動採番する'
      );
      System.assertEquals(
        [SELECT Name FROM Invoice__c WHERE Id = :correctionId].Name,
        correctionNameOnCard,
        'Core 第7.9.3節: 返却カードの請求番号は採番済み Name'
      );
      System.assertEquals(
        invoicesBeforeCancel,
        activeCards,
        'Core 第7.9.3節: 他の未確定は残し、取消した1枚の代わりに訂正用未確定を返す'
      );
      System.assertEquals(
        0,
        preview.manualAdjustmentAmount,
        'Core 第7.8.5節: 端数調整実績は取消済み明細を母にしない'
      );
    }
  }

  @IsTest
  static void updateInvoiceLineAcceptanceEndDate_withoutEditPermission_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      InvoiceLine__c line = [
        SELECT Id, Invoice__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      String token = AccountingCauseLockService.resolveInvoiceOperationToken(
        line.Invoice__c
      );

      InvoiceCanonicalService.testHasEditPreviewPermission = false;
      Boolean thrown = false;
      Test.startTest();
      try {
        OrderCreateController.updateInvoiceLineAcceptanceEndDate(
          context.history.Id,
          line.Id,
          Date.today(),
          token,
          null,
          null
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '未確定請求を直す権限がありません。',
          ex.getMessage(),
          '共通基盤 第3.2節・第10.4節: 検収終了日変更は 10'
        );
      } finally {
        InvoiceCanonicalService.testHasEditPreviewPermission = null;
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void updateInvoiceLineAcceptanceEndDate_staleToken_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createSpotEstimateContextWithOpportunity();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      InvoiceLine__c line = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :context.history.Id
        LIMIT 1
      ];

      Boolean thrown = false;
      Test.startTest();
      try {
        OrderCreateController.updateInvoiceLineAcceptanceEndDate(
          context.history.Id,
          line.Id,
          Date.today(),
          '1',
          null,
          null
        );
        System.assert(false, 'Expected stale token to reject');
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        thrown,
        'Core 第4.3.12節: 検収日変更は比較値未指定で現在版を埋めない'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void updateInvoiceLineAcceptanceEndDate_reusesScopedLine() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createSpotEstimateContextWithOpportunity();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      InvoiceLine__c line = [
        SELECT Id, Invoice__c, AcceptanceEndDate__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      Date nextDate = line.AcceptanceEndDate__c == null
        ? Date.today()
        : line.AcceptanceEndDate__c.addDays(1);
      String token = AccountingCauseLockService.resolveInvoiceOperationToken(
        line.Invoice__c
      );
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      InvoiceCanonicalService.acceptanceLineSelectCount = 0;
      Test.startTest();
      OrderCreateController.updateInvoiceLineAcceptanceEndDate(
        context.history.Id,
        line.Id,
        nextDate,
        token,
        null,
        null
      );
      Test.stopTest();
      InvoiceCanonicalService.testHasEditPreviewPermission = null;
      System.assertEquals(
        0,
        InvoiceCanonicalService.acceptanceLineSelectCount,
        'Core 第12.4節: 範囲確認で読んだ明細を保存が取り直さない'
      );
      System.assertEquals(
        nextDate,
        [
          SELECT AcceptanceEndDate__c
          FROM InvoiceLine__c
          WHERE Id = :line.Id
        ]
        .AcceptanceEndDate__c,
        'Core 第7.6節: 検収終了日を指定日へ更新する'
      );
    }
  }

  @IsTest
  static void confirmOrder_usesBillingAccountMasterForInvoiceGeneration() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      ContractTestDataFactory.applyOnOrAfterBillingDay(
        context.billingAccount,
        ContractTestDataFactory.TENANT_BILLING_DAY_15
      );
      update context.billingAccount;

      OrderCreateController.confirmOrder(context.history.Id, null, false);

      BillingAccount__c updatedBillingAccount = [
        SELECT InvoiceDateDayOfMonth__c
        FROM BillingAccount__c
        WHERE Id = :context.billingAccount.Id
      ];
      System.assertEquals(15, updatedBillingAccount.InvoiceDateDayOfMonth__c);

      List<Invoice__c> invoices = [
        SELECT InvoiceDate__c, InvoiceDateDayOfMonthSnapShot__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        ORDER BY InvoiceDate__c ASC NULLS LAST
      ];
      System.assert(invoices.size() > 0);
      System.assertEquals(15, invoices[0].InvoiceDateDayOfMonthSnapShot__c);
      System.assertEquals(15, invoices[0].InvoiceDate__c.day());
    }
  }

  @IsTest
  static void confirmOrder_appliesBillingDayForPrepaidInvoiceDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      ContractProduct__c contractProduct = [
        SELECT Id, InvoiceSetting__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      contractProduct.InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      update contractProduct;

      ContractTestDataFactory.applyOnOrAfterBillingDay(
        context.billingAccount,
        ContractTestDataFactory.TENANT_BILLING_DAY_5
      );
      update context.billingAccount;

      OrderCreateController.confirmOrder(context.history.Id, null, false);

      List<Invoice__c> invoices = [
        SELECT InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        ORDER BY InvoiceDate__c ASC NULLS LAST
      ];
      System.assert(invoices.size() > 0);
      for (Invoice__c invoice : invoices) {
        System.assertEquals(
          Date.newInstance(2026, 6, 5),
          invoice.InvoiceDate__c,
          '?????????????E?E??E???????????E'
        );
      }
    }
  }

  @IsTest
  static void confirmOrder_triggersInvoiceGenerationViaStatusUpdate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();

      OrderCreateController.confirmOrder(context.history.Id, null, false);

      ContractHistory__c updated = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Ordered', updated.historystatus__c);

      List<InvoiceProduct__c> invoiceProducts = [
        SELECT Id
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :context.history.Id
      ];
      System.assert(invoiceProducts.size() > 0);
    }
  }

  @IsTest
  static void confirmOrder_allowsCancelWithoutProductsAndSkipsInvoices() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createCancelEstimateContext();
      ContractHistoryStatusPathService.invoiceParentSelectCount = 0;

      Test.startTest();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Test.stopTest();

      ContractHistory__c updated = [
        SELECT historystatus__c, Type__c, StatusPath__c, InvoiceCount__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Ordered', updated.historystatus__c);
      System.assertEquals('Cancel', updated.Type__c);
      System.assertEquals(
        'Ordered',
        updated.StatusPath__c,
        'Core 第5.7節: Cancelは02_受注のまま'
      );
      System.assertEquals(
        0,
        ContractHistoryStatusPathService.invoiceParentSelectCount,
        'Core 第12.4節: Cancel受注は請求が無く履歴を取り直さない'
      );

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractProduct__c
          WHERE ContractHistory__c = :context.history.Id
        ]
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :context.history.Id
        ]
      );
    }
  }

  @IsTest
  static void confirmOrder_blocksNewWithoutProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      delete [
        SELECT Id
        FROM ContractProduct__c
        WHERE ContractHistory__c = :context.history.Id
      ];

      Boolean thrown = false;
      try {
        OrderCreateController.confirmOrder(context.history.Id, null, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOrderValidationService.PRODUCTS_MISSING_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      ContractHistory__c history = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Estimate', history.historystatus__c);
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :context.history.Id
        ],
        '????E????????E'
      );
    }
  }

  @IsTest
  static void confirmOrder_blocksWithoutBillingAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      context.service.BiilingAcccount__c = null;
      update context.service;

      Boolean thrown = false;
      try {
        OrderCreateController.confirmOrder(context.history.Id, null, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOrderValidationService.BILLING_ACCOUNT_MISSING_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      ContractHistory__c history = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Estimate', history.historystatus__c);
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :context.history.Id
        ],
        '????E????????E'
      );
    }
  }

  @IsTest
  static void confirmOrder_blocksDuplicateOrderedVersion() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      // ??????? V1 ??????????EVersion ?? Estimate ??????E
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      ContractHistory__c rival = new ContractHistory__c(
        Name = 'Order Wizard Dup Version Rival',
        ContractService__c = context.service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1),
        ApplicationDate__c = Date.newInstance(2026, 6, 1)
      );
      ContractTestDataFactory.applyRequiredFields(rival);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        rival,
        context.account.Id
      );
      insert rival;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Order Wizard Dup Version Rival Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = rival.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      Boolean thrown = false;
      Test.startTest();
      try {
        OrderCreateController.confirmOrder(rival.Id, null, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOrderValidationService.DUPLICATE_ORDERED_VERSION_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      ContractHistory__c stillEstimate = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :rival.Id
      ];
      System.assertEquals('Estimate', stillEstimate.historystatus__c);
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :rival.Id
        ],
        '?? Ordered ????E????????E'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void revertOrder_blocksWhenInvoicedProductsExist() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      List<Invoice__c> invoices = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      System.assertEquals(false, invoices.isEmpty());
      invoices[0].SystemIntegrationDate__c = Date.today();
      invoices[0].InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      update invoices[0];
      InvoiceTransactionStatusService.allowStatusWrite = false;
      InvoiceLockUtil.allowLockedStatusWrite = false;
      InvoiceLockUtil.clearLockedInvoiceCacheForTest();
      InvoiceLockUtil.testCanBypassLockedDml = false;
      Integer invoiceCountBefore = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
      ];

      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(false, dto.canRevert);
      System.assertEquals(
        InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
        dto.revertBlockedReason
      );

      Boolean thrown = false;
      Test.startTest();
      try {
        OrderCreateController.revertOrder(context.history.Id, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .historystatus__c,
        '??E??????E Ordered ???'
      );
      System.assertEquals(
        invoiceCountBefore,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :context.history.Id
        ],
        '????E??????????E'
      );
    }
  }

  @IsTest
  static void updateInvoiceHeaderAndDates_persistsPreviewEdits() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          TaxPercent__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      String originalAddressee = invoice.BillingAddresseeSnapShot__c;
      String originalTo = invoice.BillingEmailToSnapShot__c;
      Decimal originalTax = TaxCalculationUtil.fromPercentFieldStorage(
        invoice.TaxPercent__c
      );

      Date paymentDue = Date.newInstance(2026, 8, 31);
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      String token = OrderCreateController.getInvoicePreview(
        context.history.Id
      )
      .contentVersion;
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.updateInvoiceHeaderAndDates(
        context.history.Id,
        invoice.Id,
        invoice.InvoiceDate__c,
        paymentDue,
        'ignored-addressee',
        'ignored-to@example.com',
        null,
        null,
        8,
        token
      );
      System.assert(preview.invoiceCount >= 1);
      Test.stopTest();

      Invoice__c stored = [
        SELECT
          PaymentScheduledDate__c,
          IsManuallyAdjusted__c,
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          TaxPercent__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        paymentDue,
        stored.PaymentScheduledDate__c,
        'Core 第7.8節: 請求情報編集は入金予定日を当該請求へ保存する'
      );
      System.assertEquals(true, stored.IsManuallyAdjusted__c);
      System.assertEquals(
        originalTax,
        TaxCalculationUtil.fromPercentFieldStorage(stored.TaxPercent__c),
        'Core 第7.8節: 請求情報編集は税率を変えない'
      );
      System.assertEquals(
        originalAddressee,
        stored.BillingAddresseeSnapShot__c,
        'Core 第7.8節: 宛名は請求情報編集の対象外'
      );
      System.assertEquals(
        originalTo,
        stored.BillingEmailToSnapShot__c,
        'Core 第7.8節: Toは請求情報編集の対象外'
      );
    }
  }

  @IsTest
  static void billingAccountSplitAndOptions_createsSecondInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      List<OrderCreateController.BillingAccountOptionDto> options = OrderCreateController.getBillingAccountOptionsForPreview(
        context.history.Id
      );
      System.assert(
        options.size() >= 1,
        '?E??????E????????????'
      );

      BillingAccount__c otherBa = ContractTestDataFactory.insertBillingAccount(
        context.account.Id
      );

      Invoice__c source = [
        SELECT Id, PaymentScheduledDate__c, InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      Integer invoiceCountBefore = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
      ];
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 1;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      String token = OrderCreateController.getInvoicePreview(
        context.history.Id
      )
      .contentVersion;
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.splitInvoiceByBillingAccount(
        context.history.Id,
        source.Id,
        otherBa.Id,
        source.InvoiceDate__c,
        source.PaymentScheduledDate__c,
        new List<InvoiceCanonicalService.SplitLineInput>{ split },
        token
      );
      System.assertEquals(
        invoiceCountBefore + 1,
        preview.invoiceCount,
        'BA?E??????1??????'
      );
      System.assertEquals(
        true,
        OrderCreateController.hasManualInvoiceAdjustment(context.history.Id),
        '?E????E???????????'
      );

      Integer otherBaInvoiceCount = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE
          ContractHistory__c = :context.history.Id
          AND BillingAccountSnapShot__c = :otherBa.Id
      ];
      System.assertEquals(
        1,
        otherBaInvoiceCount,
        '?E???EA? SnapShot ??????1?????'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void hasManualInvoiceAdjustment_ignoresCancelledInvoices() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      Invoice__c cancelled = new Invoice__c(
        ContractService__c = context.service.Id,
        ContractHistory__c = context.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100,
        BillingAccountSnapShot__c = context.billingAccount.Id,
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CANCELLED,
        IsManuallyAdjusted__c = true
      );
      ContractTestDataFactory.insertAllowingInvoiceStatus(cancelled);
      System.assertEquals(
        false,
        OrderCreateController.hasManualInvoiceAdjustment(context.history.Id),
        'Core 第5.3節・第7.8.3節: 取消済みの手直しでは差し戻し警告しない'
      );

      Invoice__c draft = new Invoice__c(
        ContractService__c = context.service.Id,
        ContractHistory__c = context.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100,
        BillingAccountSnapShot__c = context.billingAccount.Id,
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT,
        IsManuallyAdjusted__c = true
      );
      ContractTestDataFactory.insertAllowingInvoiceStatus(draft);
      System.assertEquals(
        true,
        OrderCreateController.hasManualInvoiceAdjustment(context.history.Id),
        'Core 第7.8.3節: 未確定の手直しは警告する'
      );
    }
  }

  @IsTest
  static void revertOrder_clearsLifecycleAndFirstOrdered() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      confirmOrderWithWizardHistoryDefaults(context.history.Id, false);

      ContractService__c orderedService = [
        SELECT Lifecycle__c
        FROM ContractService__c
        WHERE Id = :context.service.Id
      ];
      System.assertEquals(
        ContractDomainConstants.LIFECYCLE_TERM,
        orderedService.Lifecycle__c
      );

      ContractHistory__c beforeRevert = [
        SELECT ApplicationDate__c, OrderDate__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      Date savedApplicationDate = beforeRevert.ApplicationDate__c;
      Date savedOrderDate = beforeRevert.OrderDate__c;
      System.assertNotEquals(null, savedOrderDate);

      Test.startTest();
      OrderCreateController.revertOrder(context.history.Id, false);
      Test.stopTest();

      ContractHistory__c updated = [
        SELECT historystatus__c, ApplicationDate__c, OrderDate__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Estimate', updated.historystatus__c);
      System.assertEquals(
        savedApplicationDate,
        updated.ApplicationDate__c,
        'Core 第5.3節: 画面外の差し戻しは追加項目を触らない'
      );
      System.assertEquals(
        savedOrderDate,
        updated.OrderDate__c,
        'Core 第5.3節・第11.4.3節: 画面外の差し戻しは受注日も触らない'
      );

      ContractService__c revertedService = [
        SELECT Lifecycle__c, FirstOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :context.service.Id
      ];
      System.assertEquals(null, revertedService.FirstOrderedHistory__c);
      System.assertEquals(null, revertedService.Lifecycle__c);
    }
  }

  @IsTest
  static void revertOrder_reusesLockedHistoryLatestAndDraftInvoices() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      confirmOrderWithWizardHistoryDefaults(context.history.Id, false);
      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      ContractHistory__c locked = [
        SELECT
          Id,
          LastModifiedDate,
          Version__c,
          ContractService__c,
          (SELECT Id, LastModifiedDate FROM ContractHistoryContractProducts__r)
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      EstimateRevertInvoiceService.clearRevertCachesForTest();
      InvoiceLockUtil.clearLockedInvoiceCacheForTest();
      EstimateRevertInvoiceService.historySelectCount = 0;
      EstimateRevertInvoiceService.invoiceSelectCount = 0;
      InvoiceLockUtil.lockedInvoiceQueryCount = 0;
      InvoiceCanonicalService.invoicePurgeSelectCount = 0;
      ContractOptimisticLockUtil.productMaxSelectCount = 0;
      ContractOptimisticLockUtil.historySelectCount = 0;
      ContractHistoryStatusPathService.invoiceParentSelectCount = 0;

      Test.startTest();
      OrderCreateController.revertOrder(
        locked.Id,
        false,
        dto.lastModifiedToken,
        JSON.serialize(dto.historyCustomFields)
      );
      Test.stopTest();

      System.assertEquals(
        0,
        EstimateRevertInvoiceService.historySelectCount,
        'Core 第12.4節: ロック済み契約履歴を Latest 判定で取り直さない'
      );
      System.assertEquals(
        1,
        InvoiceLockUtil.lockedInvoiceQueryCount,
        'Core 第1.1.5節・第12.4節: 確定済み請求の有無は1回'
      );
      System.assertEquals(
        0,
        ContractOptimisticLockUtil.productMaxSelectCount,
        'Core 第4.3.12節: ロック照会の見積商品 MAX を取り直さない'
      );
      System.assertEquals(
        1,
        EstimateRevertInvoiceService.invoiceSelectCount,
        'Core 第5.3節: 消す未確定請求は仕訳削除と purge で1回'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.invoicePurgeSelectCount,
        'Core 第12.4節: purge は読んだ請求を取り直さない'
      );
      System.assertEquals(
        0,
        ContractHistoryStatusPathService.invoiceParentSelectCount,
        'Core 第5.7節・第12.4節: 差し戻しの請求削除で履歴を取り直さない'
      );
      ContractHistory__c reverted = [
        SELECT historystatus__c, StatusPath__c
        FROM ContractHistory__c
        WHERE Id = :locked.Id
      ];
      System.assertEquals('Estimate', reverted.historystatus__c);
      System.assertEquals(
        'Estimate',
        reverted.StatusPath__c,
        'Core 第5.7節: Estimate の進捗は見積であり請求件数を見ない'
      );
    }
  }

  @IsTest
  static void revertOrder_reusesLockedHistoryForRenewDelete() {
    // 仕様: Core 第5.3節・第5.6節・第12.4節
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContextWithOpportunity();
      confirmOrderWithWizardHistoryDefaults(context.history.Id, false);
      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );

      Test.startTest();
      context.opportunity.SourceContractHistory__c = context.history.Id;
      update context.opportunity;
      update new ContractHistory__c(
        Id = context.history.Id,
        RenewalOpportunity__c = context.opportunity.Id,
        RenewOpportunityRequestCount__c = 1
      );
      Id renewOpportunityId = context.opportunity.Id;
      String lastModifiedToken = ContractOptimisticLockUtil.toHistoryProductToken(
        context.history.Id
      );
      RenewOpportunityCreateService.historySelectCount = 0;
      RenewOpportunityCreateService.sourceOpportunitySelectCount = 0;
      OrderCreateController.revertOrder(
        context.history.Id,
        true,
        lastModifiedToken,
        JSON.serialize(dto.historyCustomFields)
      );
      Test.stopTest();

      System.assertEquals(
        0,
        RenewOpportunityCreateService.historySelectCount,
        'Core 第12.4節: ロック済み契約履歴を更新商談削除で取り直さない'
      );
      System.assertEquals(
        0,
        RenewOpportunityCreateService.sourceOpportunitySelectCount,
        'Core 第12.4節: Lookup がある Source 商談を取り直さない'
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Opportunity WHERE Id = :renewOpportunityId],
        'Core 第5.6節・第11.5節: 削除ONなら商談を削除する'
      );
      ContractHistory__c reverted = [
        SELECT RenewalOpportunity__c, RenewOpportunityRequestCount__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals(null, reverted.RenewalOpportunity__c);
      System.assertEquals(
        0,
        reverted.RenewOpportunityRequestCount__c,
        'Core 第11.5節: 差し戻し削除ONで1減らす（0未満にしない）'
      );
    }
  }

  @IsTest
  static void revertOrder_sameKeyRetry_doesNotWriteSecondRevertOrderLog() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      confirmOrderWithWizardHistoryDefaults(context.history.Id, false);
      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      String operationKey = 'revert-retry-key';
      ContractOperationLogService.writeInvocationCount = 0;

      Test.startTest();
      OrderCreateController.OrderSaveResult first = OrderCreateController.revertOrder(
        context.history.Id,
        false,
        dto.lastModifiedToken,
        JSON.serialize(dto.historyCustomFields),
        operationKey
      );
      Integer writesAfterFirst = ContractOperationLogService.writeInvocationCount;
      OrderCreateController.OrderSaveResult retry = OrderCreateController.revertOrder(
        context.history.Id,
        false,
        dto.lastModifiedToken,
        JSON.serialize(dto.historyCustomFields),
        operationKey
      );
      Test.stopTest();

      System.assertEquals('Estimate', first.historyStatus);
      System.assertEquals('Estimate', retry.historyStatus);
      System.assertEquals(operationKey, retry.businessOperationKey);
      System.assertEquals(
        writesAfterFirst,
        ContractOperationLogService.writeInvocationCount,
        '共通基盤第12章: 同じキーの再試行は RevertOrder の write を重ねない'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'RevertOrder'
            AND BusinessOperationKey__c = :operationKey
        ],
        '共通基盤第12章: 同じ業務操作キーの再試行は2行目を作らない'
      );
    }
  }

  @IsTest
  static void revertOrder_doesNotWriteIrregularLogsWhen103Present() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      confirmOrderWithWizardHistoryDefaults(context.history.Id, false);
      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      List<Invoice__c> invoices = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
      ];
      System.assert(!invoices.isEmpty(), 'Core 第5.2節: 受注は未確定請求を作る');
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.DELETE_RECORDS => true,
        ContractPermissionUtil.FIX_CONTRACT => true,
        ContractPermissionUtil.MIGRATE_ALL => false
      };
      try {
        Test.startTest();
        OrderCreateController.revertOrder(
          context.history.Id,
          false,
          dto.lastModifiedToken,
          JSON.serialize(dto.historyCustomFields)
        );
        Test.stopTest();
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }

      String historyIdPrefix =
        String.valueOf(context.history.Id).substring(0, 15) + '%';
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE OperationType__c = 'IrregularDelete'
        ],
        '共通基盤第12章: 差し戻しの正規削除は IrregularDelete にしない'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'IrregularUpdate'
            AND TargetRecordId__c LIKE :historyIdPrefix
        ],
        '共通基盤第12章: 差し戻しの正規更新は IrregularUpdate にしない'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'RevertOrder'
            AND TargetRecordId__c LIKE :historyIdPrefix
        ],
        '共通基盤第12章: RevertOrder は1行'
      );
    }
  }

  @IsTest
  static void getOrderContext_doesNotRereadHistoryAndExposesManualAdjustment() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      confirmOrderWithWizardHistoryDefaults(context.history.Id, false);
      Invoice__c draft = [
        SELECT Id
        FROM Invoice__c
        WHERE
          ContractHistory__c = :context.history.Id
          AND InvoiceTransactionStatus__c = :InvoiceTransactionStatusService.TX_DRAFT
        LIMIT 1
      ];
      draft.IsManuallyAdjusted__c = true;
      update draft;
      EstimateRevertInvoiceService.clearRevertCachesForTest();
      InvoiceLockUtil.clearLockedInvoiceCacheForTest();
      EstimateRevertInvoiceService.historySelectCount = 0;

      Test.startTest();
      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      Test.stopTest();

      System.assertEquals(
        0,
        EstimateRevertInvoiceService.historySelectCount,
        'Core 第4.3.11節・第12.4節: 開く取得でブロック判定に同じ履歴を取り直さない'
      );
      System.assertEquals(
        true,
        dto.hasManualAdjustment,
        'Core 第5.3節: 未確定の手直し警告は同じ取得の結果である'
      );
    }
  }

  @IsTest
  static void revertOrder_withoutCustomFields_doesNotClearCreateRenewOpportunity() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContextWithOpportunity();
      confirmOrderWithWizardHistoryDefaults(context.history.Id, false);
      update new ContractHistory__c(
        Id = context.history.Id,
        CreateRenewOpportunity__c = true
      );

      System.assertEquals(
        true,
        [
            SELECT CreateRenewOpportunity__c
            FROM ContractHistory__c
            WHERE Id = :context.history.Id
          ]
          .CreateRenewOpportunity__c
      );

      Test.startTest();
      OrderCreateController.revertOrder(context.history.Id, false);
      Test.stopTest();

      ContractHistory__c updated = [
        SELECT CreateRenewOpportunity__c, OrderDate__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals(
        true,
        updated.CreateRenewOpportunity__c,
        'Core 第5.3節: 画面外の差し戻しは追加項目を触らない'
      );
      System.assertNotEquals(
        null,
        updated.OrderDate__c,
        'Core 第5.3節・第11.4.3節: 画面外の差し戻しは受注日も触らない'
      );
    }
  }

  @IsTest
  static void revertOrder_writesHistoryFieldsIncludingOrderDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Date orderedOn = Date.today().addDays(-3);
      Date appliedOn = Date.today().addDays(-5);
      update new ContractHistory__c(
        Id = context.history.Id,
        ApplicationDate__c = appliedOn,
        OrderDate__c = orderedOn
      );

      Date nextApplication = appliedOn.addDays(1);
      Test.startTest();
      OrderCreateController.revertOrder(
        context.history.Id,
        false,
        ContractOptimisticLockUtil.toToken(
          [
            SELECT LastModifiedDate
            FROM ContractHistory__c
            WHERE Id = :context.history.Id
          ]
          .LastModifiedDate
        ),
        JSON.serialize(
          new Map<String, Object>{
            'ApplicationDate__c' => String.valueOf(nextApplication),
            'OrderDate__c' => String.valueOf(orderedOn)
          }
        )
      );
      Test.stopTest();

      ContractHistory__c updated = [
        SELECT
          historystatus__c,
          ApplicationDate__c,
          OrderDate__c,
          CreateRenewOpportunity__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Estimate', updated.historystatus__c);
      System.assertEquals(
        nextApplication,
        updated.ApplicationDate__c,
        'Core 第5.3節: 差し戻し画面の受注追加項目を保存する'
      );
      System.assertEquals(
        orderedOn,
        updated.OrderDate__c,
        'Core 第5.3節・第11.4.3節: 差し戻しで残した受注日は残る'
      );
      System.assertEquals(
        false,
        updated.CreateRenewOpportunity__c,
        'Core 第5.3節: 差し戻し画面では更新商談要求を落とす'
      );
    }
  }

  @IsTest
  static void revertOrder_screenCanClearOrderDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Date orderedOn = Date.today().addDays(-3);
      Date appliedOn = Date.today().addDays(-5);
      update new ContractHistory__c(
        Id = context.history.Id,
        ApplicationDate__c = appliedOn,
        OrderDate__c = orderedOn
      );

      Test.startTest();
      OrderCreateController.revertOrder(
        context.history.Id,
        false,
        ContractOptimisticLockUtil.toToken(
          [
            SELECT LastModifiedDate
            FROM ContractHistory__c
            WHERE Id = :context.history.Id
          ]
          .LastModifiedDate
        ),
        JSON.serialize(
          new Map<String, Object>{
            'ApplicationDate__c' => String.valueOf(appliedOn),
            'OrderDate__c' => ''
          }
        )
      );
      Test.stopTest();

      ContractHistory__c updated = [
        SELECT ApplicationDate__c, OrderDate__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals(
        appliedOn,
        updated.ApplicationDate__c,
        'Core 第5.3節: 差し戻し画面の受注追加項目を保存する'
      );
      System.assertEquals(
        null,
        updated.OrderDate__c,
        'Core 第5.3節・第11.4.3節: 差し戻しで空にした受注日は空'
      );
    }
  }

  @IsTest
  static void confirmOrder_createsRenewOpportunityWhenRequested() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContextWithOpportunity();

      OrderCreateController.OrderContextDto beforeOrder = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(true, beforeOrder.showCreateRenewOpportunity);
      System.assertEquals(
        true,
        beforeOrder.createRenewOpportunity,
        'Core 第5.2節・第11.5節: 更新商談チェックの初期状態はON'
      );
      System.assertEquals(false, beforeOrder.hasRenewOpportunity);

      Test.startTest();
      Boolean rolledBackEmptyLookup = false;
      Id renewOpportunityId;
      try {
        OrderCreateController.OrderSaveResult result = OrderCreateController.confirmOrder(
          context.history.Id,
          null,
          true,
          beforeOrder.lastModifiedToken,
          JSON.serialize(beforeOrder.historyCustomFields)
        );
        System.assertNotEquals(null, result.renewOpportunityId);
        renewOpportunityId = result.renewOpportunityId;
      } catch (AuraHandledException ex) {
        rolledBackEmptyLookup = ex.getMessage()
          .contains(
            RenewOpportunityCreateService.MISSING_RENEW_OPPORTUNITY_MESSAGE
          );
        if (!rolledBackEmptyLookup) {
          throw ex;
        }
      }
      Test.stopTest();

      if (rolledBackEmptyLookup) {
        ContractHistory__c remaining = [
          SELECT historystatus__c, RenewOpportunityRequestCount__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ];
        System.assertEquals(
          ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
          remaining.historystatus__c,
          'Core 第5.2節・第11.5節: Lookup空なら受注全体を取り消す'
        );
        System.assertEquals(
          0,
          remaining.RenewOpportunityRequestCount__c == null
            ? 0
            : remaining.RenewOpportunityRequestCount__c,
          'Core 第5.2節: 取り消したらカウントは動かさない'
        );
        return;
      }

      Opportunity renewOpp = [
        SELECT SourceContractHistory__c, AccountId
        FROM Opportunity
        WHERE Id = :renewOpportunityId
      ];
      if (
        Schema.sObjectType.Opportunity.fields.getMap()
          .containsKey('PreviousOpportunity__c')
      ) {
        Opportunity previousField = (Opportunity) Database.query(
          'SELECT PreviousOpportunity__c FROM Opportunity WHERE Id = \'' +
            String.escapeSingleQuotes(renewOpportunityId) +
            '\' LIMIT 1'
        );
        System.assertEquals(
          context.opportunity.Id,
          previousField.get('PreviousOpportunity__c')
        );
      }
      System.assertEquals(
        context.history.Id,
        renewOpp.SourceContractHistory__c
      );
      System.assertEquals(context.account.Id, renewOpp.AccountId);
      System.assertEquals(
        renewOpportunityId,
        [
          SELECT RenewalOpportunity__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .RenewalOpportunity__c,
        'Core 第11.5節: 作成後は RenewalOpportunity__c を持つ'
      );

      OrderCreateController.OrderContextDto afterOrder = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(true, afterOrder.hasRenewOpportunity);
      System.assertEquals(
        renewOpportunityId,
        afterOrder.renewOpportunityId
      );
      System.assertEquals(
        1,
        [
            SELECT RenewOpportunityRequestCount__c
            FROM ContractHistory__c
            WHERE Id = :context.history.Id
          ]
          .RenewOpportunityRequestCount__c,
        '第11.5節: 作成ONの受注でカウントを1増やす'
      );

      List<ContractHistory__c> autoRenewEstimates = [
        SELECT Id, historystatus__c, Opportunity__c
        FROM ContractHistory__c
        WHERE Opportunity__c = :renewOpportunityId
      ];
      System.assertEquals(
        1,
        autoRenewEstimates.size(),
        '更新商談から自動Renew見積が1件作られる'
      );
      Id archivedEstimateId = autoRenewEstimates[0].Id;
      autoRenewEstimates[0].historystatus__c = 'Archive';
      update autoRenewEstimates;

      OrderCreateController.revertOrder(
        context.history.Id,
        true,
        ContractOptimisticLockUtil.toToken(
          [
            SELECT LastModifiedDate
            FROM ContractHistory__c
            WHERE Id = :context.history.Id
          ]
          .LastModifiedDate
        ),
        '{}'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Opportunity
          WHERE Id = :renewOpportunityId
        ]
      );
      ContractHistory__c reverted = [
        SELECT RenewalOpportunity__c, RenewOpportunityRequestCount__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals(
        null,
        reverted.RenewalOpportunity__c,
        '第11.5節: 削除選択ONなら参照をnullにする'
      );
      System.assertEquals(
        0,
        reverted.RenewOpportunityRequestCount__c,
        '第11.5節: 差し戻し削除ONで1減らす（0未満にしない）'
      );
      System.assertEquals(
        null,
        [
            SELECT Opportunity__c
            FROM ContractHistory__c
            WHERE Id = :archivedEstimateId
          ]
          .Opportunity__c,
        '第4.9節・第5.3節: Archiveした見積のOpportunity__cを外してから商談を削除する'
      );
    }
  }

  @IsTest
  static void revertOrder_withoutCustomFields_doesNotDeleteRenewOpportunity() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContextWithOpportunity();
      confirmOrderWithWizardHistoryDefaults(context.history.Id, false);
      Test.startTest();
      Id renewOpportunityId = attachRenewOpportunityAfterOrdered(context);
      archiveNewerEstimates(context.service.Id, context.history.Id);
      OrderCreateController.revertOrder(context.history.Id, true);
      Test.stopTest();
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Opportunity
          WHERE Id = :renewOpportunityId
        ],
        'Core 第5.3節・第5.6節: 画面外の差し戻しは更新商談を削除しない'
      );
      ContractHistory__c reverted = [
        SELECT
          historystatus__c,
          RenewalOpportunity__c,
          RenewOpportunityRequestCount__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Estimate', reverted.historystatus__c);
      System.assertEquals(
        renewOpportunityId,
        reverted.RenewalOpportunity__c,
        'Core 第5.6節: 画面外ではカウントも商談削除もしない'
      );
      System.assertEquals(
        1,
        reverted.RenewOpportunityRequestCount__c,
        'Core 第5.6節: 画面外ではカウントを変えない'
      );
    }
  }

  @IsTest
  static void confirmOrder_createOn_clearsOldRenewalLookup() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContextWithOpportunity();
      Opportunity leftover = ContractTestDataFactory.insertOpportunity(
        context.account.Id,
        'Old Renewal Opportunity',
        context.opportunity.Id,
        false,
        context.service.Id
      );
      leftover.SourceContractHistory__c = context.history.Id;
      update leftover;
      context.history.RenewalOpportunity__c = leftover.Id;
      context.history.RenewOpportunityRequestCount__c = 1;
      update context.history;

      Boolean failedEmpty = false;
      Test.startTest();
      try {
        OrderCreateController.confirmOrder(context.history.Id, null, true);
      } catch (AuraHandledException ex) {
        failedEmpty = ex.getMessage()
          .contains(
            RenewOpportunityCreateService.MISSING_RENEW_OPPORTUNITY_MESSAGE
          );
        if (!failedEmpty) {
          throw ex;
        }
      }
      Test.stopTest();

      System.assertEquals(
        1,
        [SELECT COUNT() FROM Opportunity WHERE Id = :leftover.Id],
        'Core 第5.6節: 旧商談自体は残す'
      );
      ContractHistory__c afterOrder = [
        SELECT
          historystatus__c,
          RenewalOpportunity__c,
          RenewOpportunityRequestCount__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      if (afterOrder.historystatus__c == 'Ordered') {
        System.assertNotEquals(
          leftover.Id,
          afterOrder.RenewalOpportunity__c,
          'Core 第5.6節: 作成ONの再受注は旧Lookupを外す'
        );
        System.assertNotEquals(
          null,
          afterOrder.RenewalOpportunity__c,
          'Core 第11.5節: 作成ONのあとLookupが空なら受注全体を取り消す'
        );
      } else {
        System.assertEquals(true, failedEmpty);
        System.assertEquals(
          'Estimate',
          afterOrder.historystatus__c,
          'Core 第5.6節: Lookupが空なら受注全体を取り消す'
        );
      }
    }
  }

  @IsTest
  static void getOrderContext_hidesCreateRenewForCancel() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createCancelEstimateContext();
      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(false, dto.showCreateRenewOpportunity);
      System.assertEquals(
        false,
        dto.createRenewOpportunity,
        'Core 第5.2節: Cancelではチェックを出さず初期ONにもしない'
      );
    }
  }

  @IsTest
  static void getOrderContext_hidesCreateRenewForSpotAndSkipsCreate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createSpotEstimateContextWithOpportunity();

      OrderCreateController.OrderContextDto beforeOrder = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(
        false,
        beforeOrder.showCreateRenewOpportunity,
        'Core 第5.2節: Spotでは更新商談作成チェックを出さない'
      );

      Test.startTest();
      Boolean thrown = false;
      try {
        OrderCreateController.confirmOrder(
          context.history.Id,
          null,
          true
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(
              ContractHistoryTriggerHandler.RENEW_REQUEST_NOT_ALLOWED_MESSAGE
            ),
          'Core 第5.2節: Spotでは作成要求を無視せず拒否する。実際: ' +
            ex.getMessage()
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Opportunity
          WHERE SourceContractHistory__c = :context.history.Id
        ],
        'Spotでは拒否するため更新商談を作らない'
      );
    }
  }

  @IsTest
  static void confirmOrder_switchOffRejectsCreateRenewRequest() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.RenewOpportunityEnabled__c = false;
      update setting;
      ContractDocumentSettingService.clearCache();

      OrderTestContext context = createEstimateContext();
      Boolean thrown = false;
      try {
        OrderCreateController.confirmOrder(
          context.history.Id,
          null,
          true
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(
              ContractHistoryTriggerHandler.RENEW_REQUEST_NOT_ALLOWED_MESSAGE
            ),
          'Core 第11.5節: OFFでは作成要求を無視せず拒否する。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      ContractHistory__c remaining = [
        SELECT historystatus__c, RenewOpportunityRequestCount__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals(
        ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        remaining.historystatus__c
      );
      System.assertEquals(
        0,
        remaining.RenewOpportunityRequestCount__c == null
          ? 0
          : remaining.RenewOpportunityRequestCount__c,
        'Core 第5.2節: 拒否したらカウントは動かさない'
      );
    }
  }

  @IsTest
  static void confirmOrder_switchOffAllowsOrderWithoutRequest() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.RenewOpportunityEnabled__c = false;
      update setting;
      ContractDocumentSettingService.clearCache();

      OrderTestContext context = createEstimateContext();
      OrderCreateController.OrderSaveResult result = OrderCreateController.confirmOrder(
        context.history.Id,
        null,
        false
      );
      System.assertEquals(null, result.renewOpportunityId);
      System.assertEquals(
        ContractDomainConstants.HISTORY_STATUS_ORDERED,
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .historystatus__c
      );
    }
  }

  @IsTest
  static void getOrderContext_switchOffHidesDeleteRenewAndRevertKeepsCount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContextWithOpportunity();
      confirmOrderWithWizardHistoryDefaults(context.history.Id, false);
      Test.startTest();
      attachRenewOpportunityAfterOrdered(context);
      archiveNewerEstimates(context.service.Id, context.history.Id);
      ContractHistory__c ordered = [
        SELECT RenewalOpportunity__c, RenewOpportunityRequestCount__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertNotEquals(null, ordered.RenewalOpportunity__c);
      Decimal countBefore = ordered.RenewOpportunityRequestCount__c;
      Id leftoverId = ordered.RenewalOpportunity__c;

      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.RenewOpportunityEnabled__c = false;
      update setting;
      ContractDocumentSettingService.clearCache();

      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(
        false,
        dto.hasRenewOpportunity,
        'Core 第5.6節: OFFなら削除選択を出さない'
      );

      OrderCreateController.revertOrder(
        context.history.Id,
        true,
        ContractOptimisticLockUtil.toToken(
          [
            SELECT LastModifiedDate
            FROM ContractHistory__c
            WHERE Id = :context.history.Id
          ]
          .LastModifiedDate
        ),
        '{}'
      );
      Test.stopTest();
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Opportunity WHERE Id = :leftoverId],
        'Core 第5.6節: OFFなら差し戻し削除もしない'
      );
      ContractHistory__c reverted = [
        SELECT RenewOpportunityRequestCount__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals(
        countBefore,
        reverted.RenewOpportunityRequestCount__c,
        'Core 第5.6節・第11.5節: OFFならカウントを変えない'
      );
    }
  }

  @IsTest
  static void confirmOrder_rejectsCreateRenewForCancel() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createCancelEstimateContext();
      Boolean thrown = false;
      try {
        OrderCreateController.confirmOrder(
          context.history.Id,
          null,
          true
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(
              ContractHistoryTriggerHandler.RENEW_REQUEST_NOT_ALLOWED_MESSAGE
            ),
          'Core 第5.2節: Cancelでは作成要求を無視せず拒否する。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      ContractHistory__c remaining = [
        SELECT historystatus__c, RenewOpportunityRequestCount__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals(
        ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        remaining.historystatus__c
      );
      System.assertEquals(
        0,
        remaining.RenewOpportunityRequestCount__c == null
          ? 0
          : remaining.RenewOpportunityRequestCount__c,
        'Core 第5.2節: 拒否したらカウントは動かさない'
      );
    }
  }

  @IsTest
  static void revertOrder_blocksWhenNewerOrderedVersionExists() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      ContractProduct__c v1Product = [
        SELECT
          Id,
          Product__c,
          Account__c,
          Quantity__c,
          UnitPrice__c,
          Amount__c,
          Unit__c,
          StartDate__c,
          Enddate__c,
          InvoiceSetting__c,
          BillingType__c,
          RevenueRecognitionBasis__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];

      ContractHistory__c newerHistory = new ContractHistory__c(
        Name = 'Order Wizard History v2',
        ContractService__c = context.service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1),
        PreviousHistory__c = context.history.Id
      );
      ContractTestDataFactory.applyRequiredFields(newerHistory);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        newerHistory,
        context.account.Id
      );
      insert newerHistory;

      ContractProduct__c originalLine = new ContractProduct__c(
        ContractHistory__c = newerHistory.Id,
        Product__c = v1Product.Product__c,
        Account__c = v1Product.Account__c,
        Quantity__c = v1Product.Quantity__c,
        UnitPrice__c = v1Product.UnitPrice__c,
        Amount__c = v1Product.Amount__c,
        Unit__c = v1Product.Unit__c,
        StartDate__c = v1Product.StartDate__c,
        Enddate__c = v1Product.Enddate__c,
        InvoiceSetting__c = v1Product.InvoiceSetting__c,
        BillingType__c = v1Product.BillingType__c,
        RevenueRecognitionBasis__c = v1Product.RevenueRecognitionBasis__c,
        Type__c = 'Original',
        PreviousContractProduct__c = v1Product.Id
      );
      ContractTestDataFactory.applyRequiredFields(originalLine);
      originalLine.Quantity__c = v1Product.Quantity__c;
      originalLine.UnitPrice__c = v1Product.UnitPrice__c;
      originalLine.Amount__c = -v1Product.Amount__c;
      originalLine.StartDate__c = v1Product.StartDate__c;
      originalLine.Enddate__c = v1Product.Enddate__c;
      originalLine.InvoiceSetting__c = v1Product.InvoiceSetting__c;
      originalLine.BillingType__c = v1Product.BillingType__c;
      originalLine.RevenueRecognitionBasis__c = v1Product.RevenueRecognitionBasis__c;
      insert originalLine;

      ContractProduct__c remakeLine = new ContractProduct__c(
        ContractHistory__c = newerHistory.Id,
        Product__c = v1Product.Product__c,
        Account__c = v1Product.Account__c,
        Quantity__c = v1Product.Quantity__c,
        UnitPrice__c = 6000,
        Amount__c = 720000,
        Unit__c = v1Product.Unit__c,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = v1Product.InvoiceSetting__c,
        BillingType__c = v1Product.BillingType__c,
        Type__c = 'Remake',
        PreviousContractProduct__c = v1Product.Id
      );
      ContractTestDataFactory.applyRequiredFields(remakeLine);
      remakeLine.Amount__c = 720000;
      insert remakeLine;

      Boolean thrown = false;
      Test.startTest();
      OrderCreateController.confirmOrder(newerHistory.Id, null, false);

      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(false, dto.canRevert);
      System.assertEquals(
        EstimateRevertInvoiceService.NON_LATEST_ORDERED_REVERT_MESSAGE,
        dto.revertBlockedReason
      );

      try {
        OrderCreateController.revertOrder(context.history.Id, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          EstimateRevertInvoiceService.NON_LATEST_ORDERED_REVERT_MESSAGE,
          ex.getMessage()
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .historystatus__c,
        '??????????????? Ordered'
      );
    }
  }

  @IsTest
  static void revertOrder_blocksWhenNewerEstimateVersionExists() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      ContractHistory__c newerEstimate = new ContractHistory__c(
        Name = 'Order Wizard History Estimate v2',
        ContractService__c = context.service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 10, 1),
        PreviousHistory__c = context.history.Id
      );
      ContractTestDataFactory.applyRequiredFields(newerEstimate);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        newerEstimate,
        context.account.Id
      );
      insert newerEstimate;

      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(false, dto.canRevert);
      System.assertEquals(
        EstimateRevertInvoiceService.NEWER_ESTIMATE_REVERT_MESSAGE,
        dto.revertBlockedReason
      );

      Boolean thrown = false;
      Test.startTest();
      try {
        OrderCreateController.revertOrder(context.history.Id, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          EstimateRevertInvoiceService.NEWER_ESTIMATE_REVERT_MESSAGE,
          ex.getMessage()
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .historystatus__c,
        'Core 第5.3節: 上のVersionのEstimateが残れば差し戻さない'
      );
      System.assertEquals(
        'Estimate',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :newerEstimate.Id
        ]
        .historystatus__c,
        'Core 第5.3節・第5.5節: 差し戻しは後続Estimateを自動Archiveしない'
      );
    }
  }

  @IsTest
  static void revertOrder_blocksEstimateHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();

      Boolean thrown = false;
      try {
        OrderCreateController.revertOrder(context.history.Id, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '受注済み状態の契約履歴のみ差し戻しできます。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      ContractHistory__c stillEstimate = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Estimate', stillEstimate.historystatus__c);
    }
  }

  @IsTest
  static void confirmOrder_blocksWithoutCustomPermission() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.testHasOrderPermission = false;

      Boolean thrown = false;
      try {
        OrderCreateController.confirmOrder(context.history.Id, null, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '受注を実行する権限がありません。',
          ex.getMessage()
        );
      } finally {
        OrderCreateController.testHasOrderPermission = true;
      }
      System.assertEquals(true, thrown);

      ContractHistory__c stillEstimate = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals(
        'Estimate',
        stillEstimate.historystatus__c,
        '???????????????E'
      );

      OrderCreateController.testHasOrderPermission = false;
      try {
        OrderCreateController.issueOrderOperationKey();
        System.assert(false, '06 なしのキー発行は落ちること');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          '受注を実行する権限がありません。',
          ex.getMessage(),
          '共通基盤 第10.4節: 受注キー発行は 06'
        );
      } finally {
        OrderCreateController.testHasOrderPermission = true;
      }

      OrderCreateController.testHasOrderPermission = false;
      System.assert(
        String.isNotBlank(OrderCreateController.issueRevertOperationKey()),
        '共通基盤 第10.4節: 差し戻しキーは 06 なし・07 ありで発行できる'
      );
      OrderCreateController.testHasOrderPermission = true;

      OrderCreateController.testHasRevertPermission = false;
      try {
        OrderCreateController.issueRevertOperationKey();
        System.assert(false, '07 なしの差し戻しキー発行は落ちること');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          '差し戻しを実行する権限がありません。',
          ex.getMessage(),
          '共通基盤 第10.4節: 差し戻しキー発行は 07'
        );
      } finally {
        OrderCreateController.testHasRevertPermission = true;
      }
    }
  }

  @IsTest
  static void getInvoicePreview_separatesIntegratedAndOpenAmounts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      List<InvoiceProduct__c> products = [
        SELECT Id, Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :context.history.Id
        ORDER BY Amount__c DESC
        LIMIT 1
      ];
      System.assertEquals(false, products.isEmpty());

      // ??E????????E?Envoice__c?E??E????E???????????????????????E??E
      List<Invoice__c> invoices = [
        SELECT Id, Amount__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        ORDER BY Amount__c DESC
        LIMIT 1
      ];
      System.assertEquals(
        false,
        invoices.isEmpty(),
        '???????????????E????'
      );
      invoices[0].SystemIntegrationDate__c = Date.today();
      invoices[0].InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      update invoices[0];
      InvoiceTransactionStatusService.allowStatusWrite = false;

      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );

      System.assertEquals(
        invoices[0].Amount__c,
        preview.integratedAmount,
        '????????E????????E????E'
      );
      System.assert(preview.openAmount >= 0);
      System.assert(preview.invoices.size() > 0);
      System.assert(preview.lineCount > 0);
      System.assert(preview.totalTaxAmount > 0);
      System.assertEquals(
        false,
        preview.versionEditBlocked,
        '???????E?E??????E?? Version ?????E?????E'
      );

      Boolean foundIntegrated = false;
      Boolean foundLocked = false;
      Boolean foundUnlocked = false;
      for (OrderCreateController.InvoiceGroupDto invoice : preview.invoices) {
        if (invoice.integratedAmount == invoices[0].Amount__c) {
          foundIntegrated = true;
          System.assertEquals(true, invoice.locked, '??????E locked=true');
          System.assertEquals(0, invoice.openAmount, '????E???0');
          System.assertEquals(0, invoice.clearedAmount, '??????E???0');
          foundLocked = true;
        } else if (invoice.locked != true) {
          foundUnlocked = true;
        }
      }
      System.assertEquals(true, foundIntegrated);
      System.assertEquals(true, foundLocked);
      // ????E??????????E????E???E unlocked ???????E
      if (preview.invoices.size() > 1) {
        System.assertEquals(
          true,
          foundUnlocked,
          '?EVersion ????E?????E??E????????'
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void getInvoicePreview_returnsServiceWideMergedInvoicesAfterOrder() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );

      System.assert(preview.invoiceCount > 0);
      System.assert(preview.lineCount > 0);
      System.assert(preview.invoices.size() > 0);
      System.assert(preview.invoices[0].lines.size() > 0);
      System.assertNotEquals(null, preview.invoices[0].lines[0].periodLabel);
      System.assertEquals(
        ContractMetadataService.REVENUE_BASIS_OVER_TIME,
        preview.invoices[0].lines[0].revenueRecognitionBasis,
        '第7.6節: 請求ボードは売上計上基準を返す'
      );
      System.assert(preview.totalAmount > 0);
      System.assert(preview.totalTaxAmount > 0);
      System.assertEquals(
        AmountCalculationSettingService.requireOrgDefault().TaxRoundingMode__c,
        preview.taxRoundingMode,
        'Core 第11.9節: 請求ボードは組織の税額丸めを返す'
      );
      System.assertEquals(
        AmountCalculationSettingService.requireOrgDefault()
          .QuantityUnitPriceRoundingMode__c,
        preview.quantityUnitPriceRoundingMode,
        'Core 第11.9節: 請求ボードは組織の数量・単価丸めを返す'
      );
      System.assertEquals(
        AmountCalculationSettingService.requireOrgDefault().AmountRoundingMode__c,
        preview.amountRoundingMode,
        'Core 第11.9節: 請求ボードは組織の税抜金額丸めを返す'
      );
      System.assertNotEquals(null, preview.versionOptions);
      System.assertEquals(1, preview.versionOptions.size());
      System.assertEquals(
        String.valueOf(context.history.Version__c.intValue()),
        preview.versionOptions[0].value
      );
      System.assertEquals(
        InvoiceProductMergeService.formatHistoryVersionLabel(
          context.history.Version__c
        ),
        preview.versionOptions[0].label,
        '第0.1節: 画面に Version と出す箇所は Version とする'
      );
      Invoice__c storedDue = [
        SELECT DueStatus__c, OverdueDays__c
        FROM Invoice__c
        WHERE Id = :preview.invoices[0].invoiceId
      ];
      System.assertEquals(
        storedDue.DueStatus__c,
        preview.invoices[0].dueStatus,
        '第7.11節: 期限状態は DueStatus__c を返す'
      );
      System.assertEquals(
        storedDue.OverdueDays__c,
        preview.invoices[0].overdueDays,
        '第7.11節: 遅延日数は OverdueDays__c を返す'
      );
      System.assertEquals(
        String.valueOf(context.history.Version__c.intValue()),
        preview.sourceHistoryVersion,
        '??????????E??? Version ???????????????'
      );
      AggregateResult[] cpSum = [
        SELECT SUM(Amount__c) amt
        FROM ContractProduct__c
        WHERE ContractHistory__c = :context.history.Id
      ];
      Decimal contractProductTotal = cpSum.isEmpty() ||
        cpSum[0].get('amt') == null
        ? 0
        : (Decimal) cpSum[0].get('amt');
      System.assertEquals(
        contractProductTotal,
        preview.periodLineAmountTotal,
        'Core 第7.8.5節: 見積税抜は DeltaAmountSum（受注時点の見積商品Amount積み上げ）'
      );
      System.assertEquals(
        preview.periodLineAmountTotal,
        preview.versionOptions[0].periodLineAmountTotal,
        '?? Version ?????????????????E????'
      );
      System.assertEquals(
        preview.invoiceAmountTotal,
        preview.versionOptions[0].invoiceAmountTotal,
        '?? Version ?????????????????E????'
      );
      System.assertEquals(
        preview.amountDifference,
        preview.versionOptions[0].amountDifference,
        '?? Version ???????????????E????'
      );
      System.assertNotEquals(null, preview.invoices[0].taxTotal);
      System.assertNotEquals(
        null,
        preview.invoices[0].lines[0].historyVersions
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void getInvoicePreview_versionOptionsOmitOrderedWithoutInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      ContractHistory__c newerHistory = new ContractHistory__c(
        Name = 'Order Wizard History v2 no invoice',
        ContractService__c = context.service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1),
        PreviousHistory__c = context.history.Id
      );
      ContractTestDataFactory.applyRequiredFields(newerHistory);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        newerHistory,
        context.account.Id
      );
      insert newerHistory;

      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Test.stopTest();

      Set<String> values = new Set<String>();
      for (OrderCreateController.VersionOptionDto option : preview.versionOptions) {
        values.add(option.value);
      }
      System.assertEquals(
        true,
        values.contains(String.valueOf(context.history.Version__c.intValue())),
        '第7.7.0節: 請求書がある Version は VersionN で出す'
      );
      System.assertEquals(
        false,
        values.contains('2'),
        '第7.7.0節: 請求書の無い受注済み Version は版フィルタに出さない'
      );
    }
  }

  @IsTest
  static void confirmOrder_blocksWhenContractProductAmountIsNull() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      ContractProduct__c product = [
        SELECT Id, Amount__c, Product__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      // Core 第10.1節: ARR対象の空Amountは数量×単価で埋めずエラー。受注前検証まで進めるため ARR 対象外にする。
      Product2 catalog = [
        SELECT Id, IncludeInARR__c
        FROM Product2
        WHERE Id = :product.Product__c
      ];
      catalog.IncludeInARR__c = false;
      update catalog;
      product.Amount__c = null;
      update product;

      Boolean thrown = false;
      Test.startTest();
      try {
        OrderCreateController.confirmOrder(context.history.Id, null, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOrderValidationService.AMOUNT_MISSING_MESSAGE,
          ex.getMessage()
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown, 'Amount null ?????????E???');
      ContractHistory__c history = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Estimate', history.historystatus__c);
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :context.history.Id
        ],
        '????E????????E'
      );
    }
  }

  @IsTest
  static void getInvoicePreview_estimateTotalExcludesArchivedEstimates() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      ContractProduct__c orderedProduct = [
        SELECT Id
        FROM ContractProduct__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      orderedProduct.Amount__c = 600000;
      update orderedProduct;

      // ?EVersion ?????????? Archive ????E
      ContractHistory__c rivalEstimate = new ContractHistory__c(
        Name = 'Order Wizard Rival Estimate',
        ContractService__c = context.service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1),
        ApplicationDate__c = Date.newInstance(2026, 6, 1)
      );
      ContractTestDataFactory.applyRequiredFields(rivalEstimate);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        rivalEstimate,
        context.account.Id
      );
      insert rivalEstimate;
      Product2 rivalProduct = ContractTestDataFactory.buildProduct(
        'Order Wizard Rival Product'
      );
      rivalProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(rivalProduct);
      insert new ContractProduct__c(
        ContractHistory__c = rivalEstimate.Id,
        Product__c = rivalProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 999999,
        Amount__c = 999999,
        Unit__c = 'ID',
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      OrderCreateController.confirmOrder(context.history.Id, null, false);

      rivalEstimate = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :rivalEstimate.Id
      ];
      System.assertEquals(
        'Archive',
        rivalEstimate.historystatus__c,
        '?????E Archive ?????'
      );

      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Test.stopTest();

      System.assertEquals(
        600000,
        preview.periodLineAmountTotal,
        '????? Ordered ???Erchive ? 999999 ?????E'
      );
      System.assertEquals(
        600000,
        preview.versionOptions[0].periodLineAmountTotal,
        'Version ???? Ordered ??'
      );
      System.assert(
        preview.periodLineAmountTotal != 600000 + 999999,
        'Archive ?????E???'
      );
    }
  }

  @IsTest
  static void splitLinesInPlace_returnsRefreshedPreviewSameInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      Invoice__c invoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, UnitPrice__c, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoice.Id
        LIMIT 1
      ];
      System.assert(line.UnitPrice__c != null && line.UnitPrice__c > 0);

      Decimal remainPrice = (line.UnitPrice__c / 2)
        .setScale(2, System.RoundingMode.HALF_UP);
      Decimal movePrice = line.UnitPrice__c - remainPrice;
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      split.remainUnitPrice = remainPrice;
      split.moveUnitPrice = movePrice;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      String token = OrderCreateController.getInvoicePreview(
        context.history.Id
      )
      .contentVersion;
      List<InvoiceCanonicalService.SplitThresholdLineOptions> options = OrderCreateController.getSplitThresholdDateOptions(
        invoice.Id
      );
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.splitLinesInPlace(
        context.history.Id,
        invoice.Id,
        new List<InvoiceCanonicalService.SplitLineInput>{ split },
        token
      );
      Test.stopTest();

      System.assertNotEquals(null, options);
      System.assertNotEquals(null, preview);
      Integer invoiceCount = 0;
      Integer lineCount = 0;
      for (
        OrderCreateController.InvoiceGroupDto invoiceGroup : preview.invoices
      ) {
        if (invoiceGroup.invoiceId == invoice.Id) {
          invoiceCount++;
          lineCount += invoiceGroup.lines == null
            ? 0
            : invoiceGroup.lines.size();
        }
      }
      System.assertEquals(1, invoiceCount, '?????E??');
      System.assert(lineCount >= 2, '????E????????E????');
    }
  }

  @IsTest
  static void splitLinesInPlace_doesNotRereadInvoicesOnReturn() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Invoice__c invoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, UnitPrice__c, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoice.Id
        LIMIT 1
      ];
      Decimal remainPrice = (line.UnitPrice__c / 2)
        .setScale(2, System.RoundingMode.HALF_UP);
      Decimal movePrice = line.UnitPrice__c - remainPrice;
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      split.remainUnitPrice = remainPrice;
      split.moveUnitPrice = movePrice;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      String token = OrderCreateController.getInvoicePreview(context.history.Id)
        .contentVersion;
      Test.startTest();
      OrderCreateController.previewInvoiceSelectCount = 0;
      OrderCreateController.lastPreviewInvoiceSelectIds = new Set<Id>();
      OrderCreateController.previewPeriodSelectCount = 0;
      OrderCreateController.previewScopeInvoiceCount = 0;
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      InvoiceCanonicalService.splitInvoiceSelectCount = 0;
      InvoiceCanonicalService.lastSplitInvoiceSelectIds = new Set<Id>();
      InvoiceCanonicalService.splitLineSelectCount = 0;
      InvoiceCanonicalService.lastSplitLineSelectIds = new Set<Id>();
      InvoiceCanonicalService.periodSplitInputLineSelectCount = 0;
      InvoiceCanonicalService.resetFactorInvoiceSelectCount = 0;
      InvoiceCanonicalService.resetFactorSiblingSelectCount = 0;
      InvoiceCanonicalService.recalcLineSelectCount = 0;
      InvoiceCanonicalService.recalcInvoiceSelectCount = 0;
      InvoiceCanonicalService.syncPeriodGapSelectCount = 0;
      OrderCreateController.stampAfterSplitSelectCount = 0;
      InvoiceProductFieldCopyService.resetCache();
      InvoiceProductFieldCopyService.catalogSelectCount = 0;
      FieldCopyDefinitionService.resetCache();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.splitLinesInPlace(
        context.history.Id,
        invoice.Id,
        new List<InvoiceCanonicalService.SplitLineInput>{ split },
        token
      );
      Test.stopTest();
      System.assertEquals(
        false,
        OrderCreateController.lastPreviewInvoiceSelectIds.contains(invoice.Id),
        'Core 第12.4節・第7.8節: 分割した請求をgetInvoicePreviewで取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewPeriodSelectCount,
        'Core 第12.4節・第7.8節: 返却の手直し集計が期間明細を取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewScopeInvoiceCount,
        'Core 第12.4節・第7.8節: 範囲COUNTのあと行ロックで同じ請求を取り直さない'
      );
      System.assertEquals(
        true,
        AccountingCauseLockService.invoiceLockSelectCount >= 1,
        'Core 第7.8節: 書き換える請求を行ロックする'
      );
      System.assertEquals(
        false,
        InvoiceCanonicalService.lastSplitInvoiceSelectIds.contains(invoice.Id),
        'Core 第12.4節・第7.8節: Canonicalは行ロックした請求を取り直さない'
      );
      System.assertEquals(
        false,
        InvoiceCanonicalService.lastSplitLineSelectIds.contains(line.Id),
        'Core 第12.4節・第7.8節: Canonicalは読み済み明細を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.resetFactorInvoiceSelectCount,
        'Core 第12.4節・第7.8.4節: 端数リセットは読み済み請求を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.resetFactorSiblingSelectCount,
        'Core 第12.4節・第7.8.4節: 端数リセットは読み済み兄弟明細を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.recalcLineSelectCount,
        'Core 第12.4節・第7.8節・第7.4節: 合計再計算は更新済み明細を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.recalcInvoiceSelectCount,
        'Core 第12.4節・第7.8節・第7.4節: 合計再計算は更新済み請求を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceProductFieldCopyService.catalogSelectCount,
        'Core 第12.4節・第11.4.2節: 行ロックはコピー定義を2カタログで取り直さない'
      );
      Boolean splitMoved = false;
      Integer lineCount = 0;
      for (OrderCreateController.InvoiceGroupDto groupRow : preview.invoices) {
        if (groupRow.invoiceId != invoice.Id) {
          continue;
        }
        splitMoved = groupRow.isSplitMoved == true;
        lineCount += groupRow.lines == null ? 0 : groupRow.lines.size();
      }
      System.assertEquals(
        true,
        splitMoved,
        'Core 第7.8節: 返却カードの分割済は変えない'
      );
      System.assert(
        lineCount >= 2,
        'Core 第7.8節: 返却カードの明細は変えない'
      );
    }
  }

  @IsTest
  static void splitInvoiceByDate_doesNotRereadInvoicesOnReturn() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Invoice__c source = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = (line.Amount__c / 2)
        .setScale(0, System.RoundingMode.DOWN);
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      OrderCreateController.InvoicePreviewDto beforePreview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      String token = beforePreview.contentVersion;
      Set<Id> beforeInvoiceIds = new Set<Id>();
      for (OrderCreateController.InvoiceGroupDto groupRow : beforePreview.invoices) {
        if (groupRow != null && groupRow.invoiceId != null) {
          beforeInvoiceIds.add(groupRow.invoiceId);
        }
      }
      Test.startTest();
      OrderCreateController.previewInvoiceSelectCount = 0;
      OrderCreateController.lastPreviewInvoiceSelectIds = new Set<Id>();
      OrderCreateController.previewPeriodSelectCount = 0;
      OrderCreateController.previewScopeInvoiceCount = 0;
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      InvoiceCanonicalService.splitInvoiceSelectCount = 0;
      InvoiceCanonicalService.lastSplitInvoiceSelectIds = new Set<Id>();
      InvoiceCanonicalService.splitLineSelectCount = 0;
      InvoiceCanonicalService.lastSplitLineSelectIds = new Set<Id>();
      InvoiceCanonicalService.recalcLineSelectCount = 0;
      InvoiceCanonicalService.recalcInvoiceSelectCount = 0;
      InvoiceCanonicalService.syncPeriodGapSelectCount = 0;
      OrderCreateController.stampAfterSplitSelectCount = 0;
      InvoiceProductFieldCopyService.resetCache();
      InvoiceProductFieldCopyService.catalogSelectCount = 0;
      FieldCopyDefinitionService.resetCache();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.splitInvoiceByDate(
        context.history.Id,
        source.Id,
        Date.newInstance(2026, 9, 1),
        Date.newInstance(2026, 9, 30),
        new List<InvoiceCanonicalService.SplitLineInput>{ split },
        token
      );
      Test.stopTest();
      Id createdId;
      for (OrderCreateController.InvoiceGroupDto groupRow : preview.invoices) {
        if (
          groupRow != null &&
          groupRow.invoiceId != null &&
          !beforeInvoiceIds.contains(groupRow.invoiceId)
        ) {
          createdId = groupRow.invoiceId;
          break;
        }
      }
      System.assertNotEquals(null, createdId, 'Core 第7.8節: 新しい請求を返す');
      System.assertEquals(
        false,
        OrderCreateController.lastPreviewInvoiceSelectIds.contains(source.Id),
        'Core 第12.4節・第7.8節: 元請求をgetInvoicePreviewで取り直さない'
      );
      System.assertEquals(
        false,
        OrderCreateController.lastPreviewInvoiceSelectIds.contains(createdId),
        'Core 第12.4節・第7.8節: 新請求をgetInvoicePreviewで取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewPeriodSelectCount,
        'Core 第12.4節・第7.8節: 返却の手直し集計が期間明細を取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewScopeInvoiceCount,
        'Core 第12.4節・第7.8節: 範囲COUNTのあと行ロックで同じ請求を取り直さない'
      );
      System.assertEquals(
        true,
        AccountingCauseLockService.invoiceLockSelectCount >= 1,
        'Core 第7.8節: 書き換える請求を行ロックする'
      );
      System.assertEquals(
        false,
        InvoiceCanonicalService.lastSplitInvoiceSelectIds.contains(source.Id),
        'Core 第12.4節・第7.8節: Canonicalは行ロックした元請求を取り直さない'
      );
      System.assertEquals(
        false,
        InvoiceCanonicalService.lastSplitLineSelectIds.contains(line.Id),
        'Core 第12.4節・第7.8節: Canonicalは読み済み明細を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.recalcLineSelectCount,
        'Core 第12.4節・第7.8節・第7.4節: 合計再計算は更新済み明細を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.recalcInvoiceSelectCount,
        'Core 第12.4節・第7.8節・第7.4節: 合計再計算は更新済み請求を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.syncPeriodGapSelectCount,
        'Core 第12.4節・第7.8節: 端数ギャップ同期は更新済み請求を取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.stampAfterSplitSelectCount,
        'Core 第12.4節・第7.9.7節: 操作キー押印は作成済み・元請求を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceProductFieldCopyService.catalogSelectCount,
        'Core 第12.4節・第11.4.2節: 行ロックはコピー定義を2カタログで取り直さない'
      );
      System.assert(
        preview.invoices.size() >= 2,
        'Core 第7.8節: 返却カードの枚数は変えない'
      );
    }
  }

  @IsTest
  static void splitInvoiceByBillingAccount_doesNotRereadInvoicesOnReturn() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      BillingAccount__c otherBa = ContractTestDataFactory.insertBillingAccount(
        context.account.Id
      );
      Invoice__c source = [
        SELECT Id, PaymentScheduledDate__c, InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 1;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      String token = OrderCreateController.getInvoicePreview(context.history.Id)
        .contentVersion;
      Test.startTest();
      OrderCreateController.previewInvoiceSelectCount = 0;
      OrderCreateController.lastPreviewInvoiceSelectIds = new Set<Id>();
      OrderCreateController.previewPeriodSelectCount = 0;
      OrderCreateController.previewScopeInvoiceCount = 0;
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      InvoiceCanonicalService.splitInvoiceSelectCount = 0;
      InvoiceCanonicalService.lastSplitInvoiceSelectIds = new Set<Id>();
      InvoiceCanonicalService.splitLineSelectCount = 0;
      InvoiceCanonicalService.lastSplitLineSelectIds = new Set<Id>();
      InvoiceCanonicalService.recalcLineSelectCount = 0;
      InvoiceCanonicalService.recalcInvoiceSelectCount = 0;
      InvoiceCanonicalService.syncPeriodGapSelectCount = 0;
      OrderCreateController.stampAfterSplitSelectCount = 0;
      InvoiceProductFieldCopyService.resetCache();
      InvoiceProductFieldCopyService.catalogSelectCount = 0;
      FieldCopyDefinitionService.resetCache();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.splitInvoiceByBillingAccount(
        context.history.Id,
        source.Id,
        otherBa.Id,
        source.InvoiceDate__c,
        source.PaymentScheduledDate__c,
        new List<InvoiceCanonicalService.SplitLineInput>{ split },
        token
      );
      Test.stopTest();
      System.assertEquals(
        false,
        OrderCreateController.lastPreviewInvoiceSelectIds.contains(source.Id),
        'Core 第12.4節・第7.8節: 元請求をgetInvoicePreviewで取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewPeriodSelectCount,
        'Core 第12.4節・第7.8節: 返却の手直し集計が期間明細を取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewScopeInvoiceCount,
        'Core 第12.4節・第7.8節: 範囲COUNTのあと行ロックで同じ請求を取り直さない'
      );
      System.assertEquals(
        true,
        AccountingCauseLockService.invoiceLockSelectCount >= 1,
        'Core 第7.8節: 書き換える請求を行ロックする'
      );
      System.assertEquals(
        false,
        InvoiceCanonicalService.lastSplitInvoiceSelectIds.contains(source.Id),
        'Core 第12.4節・第7.8節: Canonicalは行ロックした元請求を取り直さない'
      );
      System.assertEquals(
        false,
        InvoiceCanonicalService.lastSplitLineSelectIds.contains(line.Id),
        'Core 第12.4節・第7.8節: Canonicalは読み済み明細を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.recalcLineSelectCount,
        'Core 第12.4節・第7.8節・第7.4節: 合計再計算は更新済み明細を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.recalcInvoiceSelectCount,
        'Core 第12.4節・第7.8節・第7.4節: 合計再計算は更新済み請求を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.syncPeriodGapSelectCount,
        'Core 第12.4節・第7.8節: 端数ギャップ同期は更新済み請求を取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.stampAfterSplitSelectCount,
        'Core 第12.4節・第7.9.7節: 操作キー押印は作成済み・元請求を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceProductFieldCopyService.catalogSelectCount,
        'Core 第12.4節・第11.4.2節: 行ロックはコピー定義を2カタログで取り直さない'
      );
      System.assert(
        preview.invoiceCount >= 2,
        'Core 第7.8節: 返却カードの枚数は変えない'
      );
    }
  }

  @IsTest
  static void moveLinesToExistingInvoice_doesNotRereadInvoicesOnReturn() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Invoice__c source = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        ORDER BY InvoiceDate__c ASC
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = (line.Amount__c / 2)
        .setScale(0, System.RoundingMode.DOWN);
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      String token = OrderCreateController.getInvoicePreview(context.history.Id)
        .contentVersion;
      OrderCreateController.InvoicePreviewDto afterSplit = OrderCreateController.splitInvoiceByDate(
        context.history.Id,
        source.Id,
        Date.newInstance(2026, 9, 1),
        Date.newInstance(2026, 9, 30),
        new List<InvoiceCanonicalService.SplitLineInput>{ split },
        token
      );
      Id createdId;
      Id createdLineId;
      String sourceToken;
      String createdToken;
      for (OrderCreateController.InvoiceGroupDto groupRow : afterSplit.invoices) {
        if (groupRow.invoiceId == source.Id) {
          sourceToken = groupRow.lastModifiedToken;
          continue;
        }
        if (
          groupRow.invoiceDate == '2026-09-01' ||
          groupRow.invoiceDate == '2026/09/01'
        ) {
          createdId = groupRow.invoiceId;
          createdLineId = groupRow.lines[0].lineId;
          createdToken = groupRow.lastModifiedToken;
        }
      }
      if (createdId == null) {
        for (OrderCreateController.InvoiceGroupDto groupRow : afterSplit.invoices) {
          if (groupRow.invoiceId != source.Id) {
            createdId = groupRow.invoiceId;
            createdLineId = groupRow.lines[0].lineId;
            createdToken = groupRow.lastModifiedToken;
            break;
          }
        }
      }
      Test.startTest();
      OrderCreateController.previewInvoiceSelectCount = 0;
      OrderCreateController.lastPreviewInvoiceSelectIds = new Set<Id>();
      OrderCreateController.previewPeriodSelectCount = 0;
      OrderCreateController.previewScopeInvoiceCount = 0;
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      InvoiceCanonicalService.splitInvoiceSelectCount = 0;
      InvoiceCanonicalService.lastSplitInvoiceSelectIds = new Set<Id>();
      InvoiceCanonicalService.splitLineSelectCount = 0;
      InvoiceCanonicalService.lastSplitLineSelectIds = new Set<Id>();
      InvoiceCanonicalService.recalcLineSelectCount = 0;
      InvoiceCanonicalService.recalcInvoiceSelectCount = 0;
      InvoiceCanonicalService.syncPeriodGapSelectCount = 0;
      OrderCreateController.stampAfterSplitSelectCount = 0;
      InvoiceProductFieldCopyService.resetCache();
      InvoiceProductFieldCopyService.catalogSelectCount = 0;
      FieldCopyDefinitionService.resetCache();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.moveLinesToExistingInvoice(
        context.history.Id,
        createdId,
        source.Id,
        new List<Id>{ createdLineId },
        createdToken,
        sourceToken,
        null
      );
      Test.stopTest();
      System.assertEquals(
        false,
        OrderCreateController.lastPreviewInvoiceSelectIds.contains(source.Id),
        'Core 第12.4節・第7.8節: 移動先請求をgetInvoicePreviewで取り直さない'
      );
      System.assertEquals(
        false,
        OrderCreateController.lastPreviewInvoiceSelectIds.contains(createdId),
        'Core 第12.4節・第7.8節: 移動元請求をgetInvoicePreviewで取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewPeriodSelectCount,
        'Core 第12.4節・第7.8節: 返却の手直し集計が期間明細を取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewScopeInvoiceCount,
        'Core 第12.4節・第7.8節: 範囲COUNTのあと行ロックで同じ請求を取り直さない'
      );
      System.assertEquals(
        true,
        AccountingCauseLockService.invoiceLockSelectCount >= 1,
        'Core 第7.8節: 書き換える請求を行ロックする'
      );
      System.assertEquals(
        false,
        InvoiceCanonicalService.lastSplitInvoiceSelectIds.contains(source.Id),
        'Core 第12.4節・第7.8節: Canonicalは行ロックした移動先請求を取り直さない'
      );
      System.assertEquals(
        false,
        InvoiceCanonicalService.lastSplitInvoiceSelectIds.contains(createdId),
        'Core 第12.4節・第7.8節: Canonicalは行ロックした移動元請求を取り直さない'
      );
      System.assertEquals(
        false,
        InvoiceCanonicalService.lastSplitLineSelectIds.contains(createdLineId),
        'Core 第12.4節・第7.8節: Canonicalは読み済み明細を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.recalcLineSelectCount,
        'Core 第12.4節・第7.8節・第7.4節: 合計再計算は更新済み明細を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.recalcInvoiceSelectCount,
        'Core 第12.4節・第7.8節・第7.4節: 合計再計算は更新済み請求を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.syncPeriodGapSelectCount,
        'Core 第12.4節・第7.8節: 端数ギャップ同期は更新済み請求を取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.stampAfterSplitSelectCount,
        'Core 第12.4節・第7.9.7節: 操作キー押印は作成済み・元請求を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceProductFieldCopyService.catalogSelectCount,
        'Core 第12.4節・第11.4.2節: 行ロックはコピー定義を2カタログで取り直さない'
      );
      Boolean sourceExists = false;
      for (OrderCreateController.InvoiceGroupDto groupRow : preview.invoices) {
        if (groupRow.invoiceId == source.Id) {
          sourceExists = true;
        }
      }
      System.assertEquals(
        true,
        sourceExists,
        'Core 第7.8節: 返却カードの移動先は変えない'
      );
    }
  }

  @IsTest
  static void splitLinesInPlace_sameKeyRetry_doesNotRereadWhenCached() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Invoice__c invoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, UnitPrice__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoice.Id
        LIMIT 1
      ];
      Decimal remainPrice = (line.UnitPrice__c / 2)
        .setScale(2, System.RoundingMode.HALF_UP);
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      split.remainUnitPrice = remainPrice;
      split.moveUnitPrice = line.UnitPrice__c - remainPrice;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      String token = OrderCreateController.getInvoicePreview(context.history.Id)
        .contentVersion;
      String operationKey = 'split-in-place-retry-key';
      OrderCreateController.splitLinesInPlace(
        context.history.Id,
        invoice.Id,
        new List<InvoiceCanonicalService.SplitLineInput>{ split },
        token,
        operationKey
      );
      Test.startTest();
      OrderCreateController.previewInvoiceSelectCount = 0;
      OrderCreateController.lastPreviewInvoiceSelectIds = new Set<Id>();
      OrderCreateController.previewPeriodSelectCount = 0;
      OrderCreateController.previewScopeInvoiceCount = 0;
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      OrderCreateController.InvoicePreviewDto retry = OrderCreateController.splitLinesInPlace(
        context.history.Id,
        invoice.Id,
        new List<InvoiceCanonicalService.SplitLineInput>{ split },
        token,
        operationKey
      );
      Test.stopTest();
      System.assertEquals(
        false,
        OrderCreateController.lastPreviewInvoiceSelectIds.contains(invoice.Id),
        'Core 第12.4節・第7.8節: 冪等済み返却も対象請求を取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewPeriodSelectCount,
        'Core 第12.4節・第7.8節: 返却の手直し集計が期間明細を取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewScopeInvoiceCount,
        'Core 第12.4節・第7.8節: 範囲COUNTのあと行ロックで同じ請求を取り直さない'
      );
      System.assertEquals(
        true,
        AccountingCauseLockService.invoiceLockSelectCount >= 1,
        'Core 第7.8節: 書き換える請求を行ロックする'
      );
      System.assertNotEquals(null, retry);
      System.assert(
        retry.invoices != null && !retry.invoices.isEmpty(),
        'Core 第7.8節: 返却カードは変えない'
      );
    }
  }

  @IsTest
  static void resetLatestVersionInvoicesToPostOrder_clearsManualAdjustment() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      InvoiceLine__c line = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      Decimal originalAmount = line.Amount__c;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      OrderCreateController.InvoicePreviewDto afterEdit = OrderCreateController.updateInvoiceLineAmount(
        context.history.Id,
        line.Id,
        originalAmount + 1,
        OrderCreateController.getInvoicePreview(context.history.Id)
          .invoices[0]
          .lastModifiedToken
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM InvoiceLine__c
          WHERE
            Invoice__r.ContractHistory__c = :context.history.Id
            AND IsManuallyAdjusted__c = TRUE
        ]
      );

      Map<String, String> tokens = new Map<String, String>();
      for (OrderCreateController.InvoiceGroupDto invoiceGroup : afterEdit.invoices) {
        tokens.put(
          String.valueOf(invoiceGroup.invoiceId),
          invoiceGroup.lastModifiedToken
        );
      }
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.resetLatestVersionInvoicesToPostOrder(
        context.history.Id,
        '1',
        tokens,
        null
      );
      Test.stopTest();

      System.assertNotEquals(null, preview);
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM InvoiceLine__c
          WHERE
            Invoice__r.ContractHistory__c = :context.history.Id
            AND IsManuallyAdjusted__c = TRUE
        ],
        '???????E?????????????'
      );
    }
  }

  @IsTest
  static void resetLatestVersionInvoicesToPostOrder_resolveBlocksNonLatest() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      // ??EOrdered Version ???????resolve ?????E?Ehange ???? SOQL ?????E?E
      ContractHistory__c newerHistory = new ContractHistory__c(
        Name = 'Order Wizard History v2 Reset Resolve',
        ContractService__c = context.service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1),
        PreviousHistory__c = context.history.Id
      );
      ContractTestDataFactory.applyRequiredFields(newerHistory);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        newerHistory,
        context.account.Id
      );
      insert newerHistory;

      Set<Id> v1InvoiceIdsBefore = new Set<Id>();
      for (Invoice__c invoice : [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
      ]) {
        v1InvoiceIdsBefore.add(invoice.Id);
      }

      Boolean thrown = false;
      Test.startTest();
      try {
        OrderCreateController.resolveLatestOrderedHistoryIdForReset(
          context.history.Id,
          '1'
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(
              OrderCreateController.RESET_POST_ORDER_NON_LATEST_MESSAGE
            ),
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        thrown,
        '?? Version ? resolve ???????'
      );

      Id latestId = OrderCreateController.resolveLatestOrderedHistoryIdForReset(
        newerHistory.Id,
        '2'
      );
      System.assertEquals(newerHistory.Id, latestId);
      Test.stopTest();

      Set<Id> v1InvoiceIdsAfter = new Set<Id>();
      for (Invoice__c invoice : [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
      ]) {
        v1InvoiceIdsAfter.add(invoice.Id);
      }
      System.assertEquals(
        v1InvoiceIdsBefore,
        v1InvoiceIdsAfter,
        '?? Version ????E resolve ?????????E???'
      );
    }
  }

  @IsTest
  static void resetLatestVersionInvoicesToPostOrder_blocksWhenLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      List<Invoice__c> invoices = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      invoices[0].SystemIntegrationDate__c = Date.today();
      invoices[0].InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      update invoices;
      InvoiceTransactionStatusService.allowStatusWrite = false;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      String token = OrderCreateController.getInvoicePreview(
        context.history.Id
      )
      .contentVersion;
      Boolean thrown = false;
      try {
        OrderCreateController.resetLatestVersionInvoicesToPostOrder(
          context.history.Id,
          '1',
          token
        );
        Test.stopTest();
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          OrderCreateController.RESET_POST_ORDER_ACTIVE_CONFIRMED_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        thrown,
        '??E??????? Version ????E????'
      );
    }
  }

  @IsTest
  static void resetLatestVersionInvoicesToPostOrder_allowsWhenCancelledOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      List<Invoice__c> invoices = [
        SELECT Id, InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
      ];
      System.assert(!invoices.isEmpty(), '受注後に請求がある');
      Set<Id> cancelledIds = new Set<Id>();
      for (Invoice__c invoice : invoices) {
        cancelledIds.add(invoice.Id);
        invoice.SystemIntegrationDate__c = Date.today();
        invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      }
      InvoiceTransactionStatusService.allowStatusWrite = true;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      update invoices;
      InvoiceTransactionStatusService.applyCancelled(invoices);
      update invoices;
      InvoiceTransactionStatusService.allowStatusWrite = false;
      InvoiceLockUtil.allowLockedStatusWrite = false;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      String token = OrderCreateController.getInvoicePreview(context.history.Id)
        .contentVersion;

      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.resetLatestVersionInvoicesToPostOrder(
        context.history.Id,
        '1',
        token
      );
      Test.stopTest();

      System.assertNotEquals(null, preview);
      Integer cancelledRemaining = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE
          Id IN :cancelledIds
          AND InvoiceTransactionStatus__c = :InvoiceTransactionStatusService.TX_CANCELLED
      ];
      System.assertEquals(
        cancelledIds.size(),
        cancelledRemaining,
        'Core 第7.7.2節: 取消済みは残す'
      );
      Integer drafts = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE
          ContractHistory__c = :context.history.Id
          AND InvoiceTransactionStatus__c = :InvoiceTransactionStatusService.TX_DRAFT
      ];
      System.assert(drafts > 0, 'Core 第7.7.2節: 未確定を再生成する');
    }
  }

  @IsTest
  static void resetLatestVersionInvoicesToPostOrder_reusesResolvedHistoryAndLockedDrafts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Invoice__c invoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      String token = OrderCreateController.getInvoicePreview(context.history.Id)
        .contentVersion;

      Test.startTest();
      EstimateRevertInvoiceService.historySelectCount = 0;
      EstimateRevertInvoiceService.clearRevertCachesForTest();
      InvoiceProductGenerationService.historyContextSelectCount = 0;
      OrderCreateController.resetHistoryInvoiceSelectCount = 0;
      OrderCreateController.lastResetHistoryInvoiceSelectIds = new Set<Id>();
      InvoiceCanonicalService.rebuildInvoiceSelectCount = 0;
      InvoiceCanonicalService.lastRebuildInvoiceSelectIds = new Set<Id>();
      OrderCreateController.draftInvoiceIdsOfHistorySelectCount = 0;
      OrderCreateController.previewInvoiceSelectCount = 0;
      OrderCreateController.lastPreviewInvoiceSelectIds = new Set<Id>();
      OrderCreateController.previewPeriodSelectCount = 0;
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.resetLatestVersionInvoicesToPostOrder(
        context.history.Id,
        '1',
        token
      );
      Test.stopTest();

      System.assertEquals(
        0,
        EstimateRevertInvoiceService.historySelectCount,
        'Core 第12.4節: Version照会済みの対象履歴をLatest判定で取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceProductGenerationService.historyContextSelectCount,
        'Core 第12.4節: 入口で解決済みの対象履歴を生成コンテキストで取り直さない'
      );
      System.assertEquals(
        1,
        OrderCreateController.resetHistoryInvoiceSelectCount,
        'Core 第12.4節: 有効確定検査と未確定収集は1回'
      );
      System.assertEquals(
        true,
        OrderCreateController.lastResetHistoryInvoiceSelectIds.contains(
          invoice.Id
        ),
        'Core 第12.4節: 対象請求の初回は切らない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.rebuildInvoiceSelectCount,
        'Core 第12.4節: 行ロックした未確定をrebuildで取り直さない'
      );
      System.assertEquals(
        false,
        InvoiceCanonicalService.lastRebuildInvoiceSelectIds.contains(
          invoice.Id
        ),
        'Core 第12.4節: ロック済み未確定をrebuild SELECTに載せない'
      );
      System.assertEquals(
        0,
        OrderCreateController.draftInvoiceIdsOfHistorySelectCount,
        'Core 第12.4節: 生成直後の請求を押印で取り直さない'
      );
      System.assertEquals(
        0,
        OrderCreateController.previewPeriodSelectCount,
        'Core 第12.4節: 返却の手直し集計が期間明細を取り直さない'
      );
      List<Invoice__c> regenerated = [
        SELECT Id, BusinessOperationKey__c
        FROM Invoice__c
        WHERE
          ContractHistory__c = :context.history.Id
          AND InvoiceTransactionStatus__c = :InvoiceTransactionStatusService.TX_DRAFT
      ];
      System.assert(
        !regenerated.isEmpty(),
        'Core 第6.6節: 未確定請求と契約期間明細だけを再生成する'
      );
      for (Invoice__c regeneratedInvoice : regenerated) {
        System.assertEquals(
          false,
          OrderCreateController.lastPreviewInvoiceSelectIds.contains(
            regeneratedInvoice.Id
          ),
          'Core 第12.4節: 生成した請求をgetInvoicePreviewで取り直さない'
        );
        System.assertEquals(
          true,
          String.isNotBlank(regeneratedInvoice.BusinessOperationKey__c),
          'Core 第7.9.7節: 操作キーを新未確定へ書く'
        );
      }
      System.assertNotEquals(null, preview);
      System.assertEquals(
        0,
        preview.manualAdjustmentAmount,
        'Core 第6.6節: 返却カードの手直し額は変えない'
      );
    }
  }

  @IsTest
  static void getInvoicePreview_proratesEstimateWhenPartialMonthsInvoiced() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      List<InvoiceProduct__c> periodLines = [
        SELECT Id, StartDate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :context.history.Id
        ORDER BY StartDate__c ASC
      ];
      System.assertEquals(12, periodLines.size(), '??: 12???E?????');
      delete new List<InvoiceProduct__c>{ periodLines[10], periodLines[11] };
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ context.history.Id }
      );

      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Test.stopTest();

      System.assertEquals(
        600000,
        preview.periodLineAmountTotal,
        'Core 第7.8.5節: 見積税抜は DeltaAmountSum。期間明細件数では按分しない'
      );
      System.assertEquals(
        500000,
        preview.invoiceAmountTotal,
        '残った10サイクルの請求税抜'
      );
      System.assertEquals(
        100000,
        preview.periodLineAmountTotal - preview.invoiceAmountTotal,
        'Core 第7.8.5節: 見積税抜と請求税抜の差'
      );
      System.assertEquals(
        preview.invoiceAmountTotal - preview.periodLineAmountTotal,
        preview.amountDifference,
        'フッタの差は請求税抜−見積税抜'
      );
      System.assertEquals(
        600000,
        preview.versionOptions[0].periodLineAmountTotal,
        'Core 第7.8.5節: Version合計の見積税抜も DeltaAmountSum'
      );
    }
  }

  @IsTest
  static void getInvoicePreview_keepsHandEnteredAmountDriftWhenFullyInvoiced() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      ContractProduct__c product = [
        SELECT Id, Amount__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      product.Amount__c = 600020;
      update product;

      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Test.stopTest();

      System.assertEquals(
        600020,
        preview.periodLineAmountTotal,
        '????????????E??E?EAmount ??E'
      );
      System.assertEquals(
        600000,
        preview.invoiceAmountTotal,
        '???E???????????'
      );
      System.assertEquals(
        -20,
        preview.amountDifference,
        '??E???????????'
      );
      System.assertEquals(
        -20,
        preview.versionOptions[0].amountDifference,
        'Version ??????'
      );
    }
  }

  /**
   * ??????E?????? ID ????????????E??????????E?????????E
   * ????????????E?E?????????E?EID ??????E????????????????E
   */
  @IsTest
  static void getInvoicePreview_noFalseLineDriftWhenPeriodIdsPartiallyShared() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      List<InvoiceProduct__c> periodLines = [
        SELECT Id, StartDate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :context.history.Id
        ORDER BY StartDate__c ASC
      ];
      System.assertEquals(12, periodLines.size(), '??: 12??E');
      List<String> allPeriodIdTexts = new List<String>();
      for (InvoiceProduct__c period : periodLines) {
        allPeriodIdTexts.add(String.valueOf(period.Id));
      }

      List<InvoiceLine__c> allLines = [
        SELECT Id, Invoice__c, Amount__c, UnitPrice__c, SourcePeriodLineIds__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :context.history.Id
        ORDER BY CreatedDate ASC
      ];
      InvoiceLine__c anchor = allLines[0];
      Id keepInvoiceId = anchor.Invoice__c;
      anchor.SourcePeriodLineIds__c = String.join(allPeriodIdTexts, ',');
      anchor.Amount__c = 600000;
      anchor.UnitPrice__c = 5000;
      update anchor;
      List<InvoiceLine__c> linesToDelete = new List<InvoiceLine__c>();
      for (Integer i = 1; i < allLines.size(); i++) {
        linesToDelete.add(allLines[i]);
      }
      if (!linesToDelete.isEmpty()) {
        delete linesToDelete;
      }
      List<Invoice__c> invoices = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
      ];
      List<Invoice__c> invoicesToDelete = new List<Invoice__c>();
      for (Invoice__c invoice : invoices) {
        if (invoice.Id == keepInvoiceId) {
          update new Invoice__c(
            Id = invoice.Id,
            Amount__c = 600000,
            PeriodLineAmountTotal__c = 600000
          );
        } else {
          invoicesToDelete.add(invoice);
        }
      }
      if (!invoicesToDelete.isEmpty()) {
        delete invoicesToDelete;
      }

      // ???E?? ?E?????E?? ID ??E?E
      InvoiceCanonicalService.SplitLineInput factor = new InvoiceCanonicalService.SplitLineInput();
      factor.lineId = anchor.Id;
      factor.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      factor.moveUnitPrice = 2000;
      factor.remainUnitPrice = 3000;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        keepInvoiceId,
        new List<InvoiceCanonicalService.SplitLineInput>{ factor }
      );

      List<InvoiceLine__c> afterFactor = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :keepInvoiceId
        ORDER BY Amount__c DESC
      ];
      System.assertEquals(2, afterFactor.size());

      // ???????????E?? ?E???ID????E???????
      InvoiceCanonicalService.SplitLineInput periodSplit = new InvoiceCanonicalService.SplitLineInput();
      periodSplit.lineId = afterFactor[0].Id;
      periodSplit.splitMode = InvoiceCanonicalService.SPLIT_MODE_PERIOD;
      periodSplit.thresholdDate = Date.newInstance(2026, 12, 1);
      InvoiceCanonicalService.splitLinesInPlace(
        keepInvoiceId,
        new List<InvoiceCanonicalService.SplitLineInput>{ periodSplit }
      );

      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Test.stopTest();

      Decimal lineDeltaSum = 0;
      Integer saw = 0;
      for (OrderCreateController.InvoiceGroupDto invoice : preview.invoices) {
        for (OrderCreateController.InvoiceMergedLineDto row : invoice.lines) {
          saw++;
          Decimal delta = row.amountDeltaFromSource == null
            ? 0
            : row.amountDeltaFromSource;
          lineDeltaSum += delta;
          System.assert(
            Math.abs(delta) <= 2,
            '??ID????????E??????2?E???E??E amount=' +
              row.amount +
              ' delta=' +
              delta +
              ' src=' +
              row.sourceAmountTotal
          );
        }
      }
      System.assert(saw >= 3, '?E????E??E???????');
      System.assertEquals(
        preview.amountDifference,
        lineDeltaSum,
        '??????E????????'
      );
    }
  }

  /**
   * ???? InvoiceProduct ????????E????E?????E?????E
   * ??????E?E?E?????????????E????????E
   * ?????????????0????E
   */
  @IsTest
  static void getInvoicePreview_noFalseLineDriftWhenPeriodAmountsUneven() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      List<InvoiceProduct__c> periodLines = [
        SELECT Id, Amount__c, StartDate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :context.history.Id
        ORDER BY StartDate__c ASC
      ];
      System.assertEquals(12, periodLines.size(), 'Core 第6.5節: 12サイクル');

      List<String> allPeriodIdTexts = new List<String>();
      Decimal keepPeriodSum = 0;
      Decimal movePeriodSum = 0;
      for (Integer i = 0; i < periodLines.size(); i++) {
        allPeriodIdTexts.add(String.valueOf(periodLines[i].Id));
        Decimal periodAmount = periodLines[i].Amount__c == null
          ? 0
          : periodLines[i].Amount__c;
        if (i < 6) {
          keepPeriodSum += periodAmount;
        } else {
          movePeriodSum += periodAmount;
        }
      }

      List<InvoiceLine__c> allLines = [
        SELECT
          Id,
          Invoice__c,
          Amount__c,
          SourcePeriodLineIds__c,
          ProductName__c,
          Unit__c,
          UnitPrice__c,
          Quantity__c,
          PeriodLabel__c,
          LineMergeKey__c,
          HistoryVersionLabel__c,
          ContractProduct__c,
          Product__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :context.history.Id
        ORDER BY CreatedDate ASC
      ];
      System.assert(!allLines.isEmpty(), '??: ???E??????');

      InvoiceLine__c anchor = allLines[0];
      Id keepInvoiceId = anchor.Invoice__c;
      anchor.SourcePeriodLineIds__c = String.join(allPeriodIdTexts, ',');
      anchor.Amount__c = 600000;
      update anchor;

      List<InvoiceLine__c> linesToDelete = new List<InvoiceLine__c>();
      for (Integer i = 1; i < allLines.size(); i++) {
        linesToDelete.add(allLines[i]);
      }
      if (!linesToDelete.isEmpty()) {
        delete linesToDelete;
      }

      List<Invoice__c> invoices = [
        SELECT Id, Amount__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
      ];
      List<Invoice__c> invoiceUpdates = new List<Invoice__c>();
      List<Invoice__c> invoicesToDelete = new List<Invoice__c>();
      for (Invoice__c invoice : invoices) {
        if (invoice.Id == keepInvoiceId) {
          invoiceUpdates.add(
            new Invoice__c(
              Id = invoice.Id,
              Amount__c = 600000,
              PeriodLineAmountTotal__c = 600000,
              IsManuallyAdjusted__c = false
            )
          );
        } else {
          invoicesToDelete.add(invoice);
        }
      }
      if (!invoiceUpdates.isEmpty()) {
        update invoiceUpdates;
      }
      if (!invoicesToDelete.isEmpty()) {
        delete invoicesToDelete;
      }

      List<Id> movePeriodIds = new List<Id>();
      for (Integer i = 6; i < periodLines.size(); i++) {
        movePeriodIds.add(periodLines[i].Id);
      }

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = anchor.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_PERIOD;
      split.movePeriodLineIds = movePeriodIds;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        keepInvoiceId,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Test.stopTest();

      System.assertEquals(0, preview.amountDifference, '??????0');

      Integer sawSplitLines = 0;
      Decimal deltaSum = 0;
      for (OrderCreateController.InvoiceGroupDto invoice : preview.invoices) {
        for (OrderCreateController.InvoiceMergedLineDto row : invoice.lines) {
          if (row.amount != keepPeriodSum && row.amount != movePeriodSum) {
            continue;
          }
          sawSplitLines++;
          deltaSum += row.amountDeltaFromSource == null
            ? 0
            : row.amountDeltaFromSource;
          System.assertEquals(
            false,
            row.hasAmountDrift,
            'Core 第7.8.4節・第7.8.5節: 期間分割後の由来期間ID共有で水増ししない amount=' +
              row.amount +
              ' delta=' +
              row.amountDeltaFromSource +
              ' source=' +
              row.sourceAmountTotal
          );
          System.assertEquals(
            0,
            row.amountDeltaFromSource,
            'Core 第7.8.5節: 期間分割後の端数は0'
          );
        }
      }
      System.assertEquals(
        2,
        sawSplitLines,
        'Core 第7.8.4節: 期間金額の按分で2行 keep=' +
          keepPeriodSum +
          ' move=' +
          movePeriodSum
      );
      System.assertEquals(0, deltaSum, '??????0');
    }
  }

  @IsTest
  static void getInvoicePreview_noFalseDriftAfterBillingDateAmountSplit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      Invoice__c source = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, Amount__c, SourcePeriodLineIds__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      System.assert(line.Amount__c > 1, '??: ?E????????????');
      System.assert(
        String.isNotBlank(line.SourcePeriodLineIds__c),
        '??: ?? ID ?????E????'
      );

      Decimal moveAmount = (line.Amount__c / 2)
        .setScale(0, System.RoundingMode.DOWN);
      Decimal remainAmount = line.Amount__c - moveAmount;
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = moveAmount;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      String token = OrderCreateController.getInvoicePreview(
        context.history.Id
      )
      .contentVersion;
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.splitInvoiceByDate(
        context.history.Id,
        source.Id,
        Date.newInstance(2026, 8, 1),
        Date.newInstance(2026, 8, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split },
        token
      );
      Test.stopTest();

      System.assertEquals(
        600000,
        preview.periodLineAmountTotal,
        '????????E?????E???'
      );
      System.assertEquals(
        600000,
        preview.invoiceAmountTotal,
        '??????????E???'
      );
      System.assertEquals(0, preview.amountDifference, '???????0');
      System.assertEquals(
        0,
        preview.manualAdjustmentAmount,
        '???E????????????E?E???ID??E???????????E??E'
      );
      if (preview.versionOptions != null && !preview.versionOptions.isEmpty()) {
        System.assertEquals(
          0,
          preview.versionOptions[0].manualAdjustmentAmount,
          'Version ?????????E?????'
        );
      }

      Integer sawSplitLines = 0;
      for (OrderCreateController.InvoiceGroupDto invoice : preview.invoices) {
        for (OrderCreateController.InvoiceMergedLineDto row : invoice.lines) {
          if (row.amount != moveAmount && row.amount != remainAmount) {
            // ?E?????E???E??????????E????????E???
            System.assertEquals(
              false,
              row.hasAmountDrift,
              '??E???????????E??E???: amount=' +
                row.amount +
                ' delta=' +
                row.amountDeltaFromSource
            );
            continue;
          }
          sawSplitLines++;
          System.assertEquals(
            false,
            row.hasAmountDrift,
            '???E??????????E??E???: amount=' +
              row.amount +
              ' delta=' +
              row.amountDeltaFromSource
          );
          System.assertEquals(
            0,
            row.amountDeltaFromSource,
            '?E????????E?????'
          );
        }
      }
      System.assertEquals(2, sawSplitLines, '???E????E2???????');
    }
  }

  @IsTest
  static void moveLinesToExistingInvoice_returnsRefreshedPreview() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Invoice__c source = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        ORDER BY InvoiceDate__c ASC
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      System.assert(line.Amount__c > 1, '??: ?E????????????');

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = (line.Amount__c / 2)
        .setScale(0, System.RoundingMode.DOWN);

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      String token = OrderCreateController.getInvoicePreview(
        context.history.Id
      )
      .contentVersion;
      OrderCreateController.InvoicePreviewDto afterSplit = OrderCreateController.splitInvoiceByDate(
        context.history.Id,
        source.Id,
        Date.newInstance(2026, 9, 1),
        Date.newInstance(2026, 9, 30),
        new List<InvoiceCanonicalService.SplitLineInput>{ split },
        token
      );
      System.assert(
        afterSplit.invoices.size() >= 2,
        '??: ?E??????2???????'
      );

      Id createdId = null;
      Id createdLineId = null;
      for (
        OrderCreateController.InvoiceGroupDto invoice : afterSplit.invoices
      ) {
        if (invoice.invoiceId == source.Id) {
          continue;
        }
        if (
          invoice.invoiceDate == '2026-09-01' ||
          invoice.invoiceDate == '2026/09/01'
        ) {
          createdId = invoice.invoiceId;
          createdLineId = invoice.lines[0].lineId;
          break;
        }
      }
      if (createdId == null) {
        for (
          OrderCreateController.InvoiceGroupDto invoice : afterSplit.invoices
        ) {
          if (invoice.invoiceId != source.Id) {
            createdId = invoice.invoiceId;
            createdLineId = invoice.lines[0].lineId;
            break;
          }
        }
      }
      System.assertNotEquals(null, createdId, '?E??????????');

      String sourceToken;
      String createdToken;
      for (
        OrderCreateController.InvoiceGroupDto invoice : afterSplit.invoices
      ) {
        if (invoice.invoiceId == source.Id) {
          sourceToken = invoice.lastModifiedToken;
        }
        if (invoice.invoiceId == createdId) {
          createdToken = invoice.lastModifiedToken;
        }
      }

      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.moveLinesToExistingInvoice(
        context.history.Id,
        createdId,
        source.Id,
        new List<Id>{ createdLineId },
        createdToken,
        sourceToken,
        null
      );
      Test.stopTest();

      Boolean sourceExists = false;
      Boolean createdExists = false;
      for (OrderCreateController.InvoiceGroupDto invoice : preview.invoices) {
        if (invoice.invoiceId == source.Id) {
          sourceExists = true;
        }
        if (invoice.invoiceId == createdId) {
          createdExists = true;
        }
      }
      System.assertEquals(true, sourceExists, '???E???E????');
      System.assertEquals(
        false,
        createdExists,
        '???????E???E??????'
      );
    }
  }

  @IsTest
  static void confirmOrder_sameKeyRetry_returnsOneOrdered() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      String token = ContractOptimisticLockUtil.toHistoryProductToken(
        context.history.Id
      );
      String operationKey = 'order-retry-key';

      Test.startTest();
      OrderCreateController.OrderSaveResult first = OrderCreateController.confirmOrder(
        context.history.Id,
        null,
        false,
        token,
        null,
        operationKey
      );
      OrderCreateController.OrderSaveResult retry = OrderCreateController.confirmOrder(
        context.history.Id,
        null,
        false,
        token,
        null,
        operationKey
      );
      Test.stopTest();

      System.assertEquals(
        first.contractHistoryId,
        retry.contractHistoryId,
        'Core 第4.3.12節: 同じキーの再試行は1件のままにする'
      );
      System.assertEquals('Ordered', retry.historyStatus);
      System.assertEquals(operationKey, retry.businessOperationKey);
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Id = :context.history.Id AND historystatus__c = 'Ordered'
        ]
      );
    }
  }

  @IsTest
  static void confirmOrder_historyOnlyTokenWhenProductNewer_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      Datetime historyLm = [
        SELECT LastModifiedDate
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ]
      .LastModifiedDate;
      Datetime productMax = ContractOptimisticLockUtil.resolveHistoryProductDatetime(
        context.history.Id
      );
      if (
        productMax == null ||
        historyLm == null ||
        productMax.getTime() == historyLm.getTime()
      ) {
        return;
      }
      Boolean thrown = false;
      ContractOptimisticLockUtil.productMaxSelectCount = 0;
      try {
        OrderCreateController.confirmOrder(
          context.history.Id,
          null,
          false,
          ContractOptimisticLockUtil.toToken(historyLm)
        );
        System.assert(
          false,
          'Core 第4.3.12節: 受注の版は契約履歴と配下見積商品。履歴だけのトークンは拒否する'
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        0,
        ContractOptimisticLockUtil.productMaxSelectCount,
        'Core 第12.4節: 受注の版比較はロック照会の見積商品を使い MAX を取り直さない'
      );
    }
  }

  private class OrderTestContext {
    public Account account;
    public Opportunity opportunity;
    public BillingAccount__c billingAccount;
    public ContractService__c service;
    public ContractHistory__c history;
  }

  /** 仕様: Core 第11.4.3節、第11.7節。受注ウィザードは受注日の初期値（操作日）を送る。 */
  private static OrderCreateController.OrderSaveResult confirmOrderWithWizardHistoryDefaults(
    Id contractHistoryId,
    Boolean createRenewOpportunity
  ) {
    OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
      contractHistoryId
    );
    return OrderCreateController.confirmOrder(
      contractHistoryId,
      null,
      createRenewOpportunity,
      dto.lastModifiedToken,
      JSON.serialize(dto.historyCustomFields)
    );
  }

  /** 仕様: Core 第11.5節。受注済みのうえにテナント作成相当の更新商談をテスト準備で書く。 */
  private static Id attachRenewOpportunityAfterOrdered(OrderTestContext context) {
    Opportunity renew = ContractTestDataFactory.buildOpportunity(
      context.account.Id,
      'Tenant Renew Opportunity',
      context.opportunity == null ? null : context.opportunity.Id,
      false,
      context.service.Id
    );
    ContractTestDataFactory.applyOpportunityDefaults(renew);
    renew.SourceContractHistory__c = context.history.Id;
    insert renew;
    update new ContractHistory__c(
      Id = context.history.Id,
      RenewalOpportunity__c = renew.Id,
      RenewOpportunityRequestCount__c = 1
    );
    return renew.Id;
  }

  /** 仕様: Core 第5.3節。差し戻しは後続Estimateを自動Archiveしない。上のVersionのEstimateは先にArchiveする。 */
  private static void archiveNewerEstimates(Id serviceId, Id orderedHistoryId) {
    ContractHistory__c ordered = [
      SELECT Version__c
      FROM ContractHistory__c
      WHERE Id = :orderedHistoryId
    ];
    List<ContractHistory__c> newer = [
      SELECT Id
      FROM ContractHistory__c
      WHERE
        ContractService__c = :serviceId
        AND historystatus__c = :ContractDomainConstants.HISTORY_STATUS_ESTIMATE
        AND Version__c > :ordered.Version__c
    ];
    for (ContractHistory__c row : newer) {
      row.historystatus__c = ContractDomainConstants.HISTORY_STATUS_ARCHIVE;
    }
    if (!newer.isEmpty()) {
      update newer;
    }
  }

  private static OrderTestContext createEstimateContextWithOpportunity() {
    OrderTestContext context = createEstimateContext();
    context.opportunity = ContractTestDataFactory.insertOpportunity(
      context.account.Id,
      'Order Source Opportunity'
    );
    context.history.Opportunity__c = context.opportunity.Id;
    update context.history;
    return context;
  }

  private static OrderTestContext createSpotEstimateContextWithOpportunity() {
    OrderTestContext context = createEstimateContext(
      ContractDomainConstants.LIFECYCLE_SPOT
    );
    context.opportunity = ContractTestDataFactory.insertOpportunity(
      context.account.Id,
      'Order Spot Source Opportunity'
    );
    context.history.Opportunity__c = context.opportunity.Id;
    update context.history;

    List<ContractProduct__c> products = [
      SELECT Id, Product__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :context.history.Id
    ];
    Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
      'Order Wizard Spot Product'
    );
    oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(oneTimeProduct);
    for (ContractProduct__c product : products) {
      product.Product__c = oneTimeProduct.Id;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      product.InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    }
    update products;
    return context;
  }

  private static OrderTestContext createEstimateContext() {
    return createEstimateContext(ContractDomainConstants.LIFECYCLE_TERM);
  }

  private static OrderTestContext createEstimateContext(String lifecycle) {
    OrderTestContext context = new OrderTestContext();
    context.account = ContractTestDataFactory.insertAccount(
      'Order Wizard Account'
    );
    context.service = ContractTestDataFactory.insertContractService(
      context.account.Id,
      'Order Wizard Service',
      lifecycle
    );
    context.billingAccount = [
      SELECT Id, BillingEmailTo__c
      FROM BillingAccount__c
      WHERE Id = :context.service.BiilingAcccount__c
    ];

    context.history = new ContractHistory__c(
      Name = 'Order Wizard History',
      ContractService__c = context.service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
      EffectiveDate__c = Date.newInstance(2026, 6, 1),
      ApplicationDate__c = Date.newInstance(2026, 6, 1)
    );
    ContractTestDataFactory.applyRequiredFields(context.history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(
      context.history,
      context.account.Id
    );
    insert context.history;

    Product2 product = ContractTestDataFactory.buildProduct(
      'Order Wizard Product'
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProduct(product);

    ContractProduct__c line = new ContractProduct__c(
      ContractHistory__c = context.history.Id,
      Product__c = product.Id,
      Quantity__c = 10,
      UnitPrice__c = 5000,
      Amount__c = 600000,
      Unit__c = 'ID',
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2027, 5, 31),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'New'
    );
    ContractTestDataFactory.applyRequiredFields(line);
    insert line;

    return context;
  }

  @IsTest
  static void updateInvoiceLineAmounts_sameKeyRetry_appliesOnce() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Id invoiceId = preview.invoices[0].invoiceId;
      Id lineId = preview.invoices[0].lines[0].lineId;
      Decimal originalAmount = preview.invoices[0].lines[0].amount;
      String token = preview.invoices[0].lastModifiedToken;
      String operationKey = 'draft-amount-retry-key';

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      OrderCreateController.updateInvoiceLineAmounts(
        context.history.Id,
        new List<InvoiceCanonicalService.LineAmountEdit>{
          amountEdit(lineId, originalAmount + 1)
        },
        token,
        operationKey
      );
      OrderCreateController.InvoicePreviewDto retry = OrderCreateController.updateInvoiceLineAmounts(
        context.history.Id,
        new List<InvoiceCanonicalService.LineAmountEdit>{
          amountEdit(lineId, originalAmount + 99)
        },
        token,
        operationKey
      );
      Test.stopTest();

      InvoiceLine__c stored = [
        SELECT Amount__c
        FROM InvoiceLine__c
        WHERE Id = :lineId
      ];
      System.assertEquals(
        originalAmount + 1,
        stored.Amount__c,
        '同じキー再試行は1件。2回目の金額は載せない'
      );
      Invoice__c stamped = [
        SELECT BusinessOperationKey__c
        FROM Invoice__c
        WHERE Id = :invoiceId
      ];
      System.assertEquals(operationKey, stamped.BusinessOperationKey__c);
      System.assertNotEquals(null, retry);
    }
  }

  @IsTest
  static void updateInvoiceLineAmount_reusesLockedInvoiceAndLoadedLines() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Invoice__c invoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT
          Id,
          Amount__c,
          Invoice__c,
          ProductName__c,
          Unit__c,
          UnitPrice__c,
          Quantity__c,
          RevenueRecognitionBasis__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoice.Id
        LIMIT 1
      ];
      InvoiceLine__c sibling = line.clone(false, true, false, false);
      sibling.Amount__c = line.Amount__c;
      insert sibling;
      Id invoiceId = invoice.Id;
      Id lineId = line.Id;
      Decimal originalAmount = line.Amount__c;
      String token = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Test.startTest();
      OrderCreateController.draftLineSelectCount = 0;
      OrderCreateController.lastDraftSiblingLineSelectIds = new Set<Id>();
      OrderCreateController.previewInvoiceSelectCount = 0;
      OrderCreateController.lastPreviewInvoiceSelectIds = new Set<Id>();
      InvoiceCanonicalService.lineAmountSelectCount = 0;
      InvoiceCanonicalService.recalcLineSelectCount = 0;
      InvoiceCanonicalService.recalcInvoiceSelectCount = 0;
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      InvoiceProductFieldCopyService.resetCache();
      InvoiceProductFieldCopyService.catalogSelectCount = 0;
      FieldCopyDefinitionService.resetCache();
      InvoiceOpsFieldService.extraFieldSelectCount = 0;
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.updateInvoiceLineAmount(
        context.history.Id,
        lineId,
        originalAmount + 1,
        token
      );
      Test.stopTest();

      System.assertEquals(
        1,
        OrderCreateController.draftLineSelectCount,
        'Core 第12.4節: 親請求Idと兄弟明細は1回'
      );
      System.assertEquals(
        false,
        OrderCreateController.lastDraftSiblingLineSelectIds.contains(lineId),
        'Core 第12.4節: 親請求Id照会で読んだ対象明細を兄弟明細照会で取り直さない'
      );
      System.assertEquals(
        true,
        OrderCreateController.lastDraftSiblingLineSelectIds.contains(sibling.Id),
        'Core 第12.4節: 兄弟の初回は切らない'
      );
      System.assertEquals(
        false,
        OrderCreateController.lastPreviewInvoiceSelectIds.contains(invoiceId),
        'Core 第12.4節: 返却カードは更新した請求を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceOpsFieldService.extraFieldSelectCount,
        'Core 第12.4節: 返却カードの追加項目定義を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.lineAmountSelectCount,
        'Core 第12.4節: Canonicalは読み済み明細を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.recalcLineSelectCount,
        'Core 第12.4節: 合計再計算は更新済み明細を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.recalcInvoiceSelectCount,
        'Core 第12.4節: 合計再計算はロック済み請求を取り直さない'
      );
      System.assertEquals(
        1,
        AccountingCauseLockService.invoiceLockSelectCount,
        'Core 第12.4節: 行ロックの請求照会は1回'
      );
      System.assertEquals(
        0,
        InvoiceProductFieldCopyService.catalogSelectCount,
        'Core 第12.4節・第11.4.2節: コピー定義を2カタログで取り直さない'
      );
      InvoiceLine__c storedLine = [
        SELECT Amount__c, IsAmountAdjusted__c
        FROM InvoiceLine__c
        WHERE Id = :lineId
      ];
      System.assertEquals(
        originalAmount + 1,
        storedLine.Amount__c,
        'Core 第7.8節: 端数調整は税抜を変える'
      );
      System.assertEquals(true, storedLine.IsAmountAdjusted__c);
      Invoice__c storedInvoice = [
        SELECT Amount__c, IsAmountAdjusted__c
        FROM Invoice__c
        WHERE Id = :invoiceId
      ];
      System.assertEquals(
        originalAmount + sibling.Amount__c + 1,
        storedInvoice.Amount__c,
        'Core 第7.4節: 税抜合計が変わった請求は同じ処理でヘッダを合わせる'
      );
      System.assertEquals(true, storedInvoice.IsAmountAdjusted__c);
      Decimal cardAmount;
      for (OrderCreateController.InvoiceGroupDto groupRow : preview.invoices) {
        if (groupRow.invoiceId != invoiceId || groupRow.lines == null) {
          continue;
        }
        for (OrderCreateController.InvoiceMergedLineDto lineDto : groupRow.lines) {
          if (lineDto.lineId == lineId) {
            cardAmount = lineDto.amount;
          }
        }
      }
      System.assertEquals(
        originalAmount + 1,
        cardAmount,
        'Core 第7.7.0節: 返却カードの明細金額は保存結果'
      );
    }
  }

  @IsTest
  static void updateInvoiceLineAmount_confirmedInvoice_throwsEditBlock() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Invoice__c invoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoice.Id
        LIMIT 1
      ];
      invoice.SystemIntegrationDate__c = Date.today();
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      update invoice;
      InvoiceTransactionStatusService.allowStatusWrite = false;
      String token = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Test.startTest();
      Boolean rejected = false;
      try {
        OrderCreateController.updateInvoiceLineAmount(
          context.history.Id,
          line.Id,
          line.Amount__c + 1,
          token
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assertEquals(
          InvoiceLockUtil.INVOICE_EDIT_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      Test.stopTest();
      System.assertEquals(true, rejected, 'Core 第7.8節: 確定済みは端数調整できない');
      System.assertEquals(
        line.Amount__c,
        [
          SELECT Amount__c
          FROM InvoiceLine__c
          WHERE Id = :line.Id
        ]
        .Amount__c
      );
    }
  }

  @IsTest
  static void updateInvoiceHeaderAndDates_reusesLockedInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Invoice__c invoice = [
        SELECT Id, InvoiceDate__c, BillingAddresseeSnapShot__c, TaxPercent__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      String originalAddressee = invoice.BillingAddresseeSnapShot__c;
      Date paymentDue = Date.newInstance(2026, 8, 31);
      String token = OrderCreateController.getInvoicePreview(context.history.Id)
        .contentVersion;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Test.startTest();
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      InvoiceCanonicalService.headerInvoiceSelectCount = 0;
      InvoiceProductFieldCopyService.resetCache();
      InvoiceProductFieldCopyService.catalogSelectCount = 0;
      FieldCopyDefinitionService.resetCache();
      OrderCreateController.lastPreviewInvoiceSelectIds = new Set<Id>();
      InvoiceOpsFieldService.extraFieldSelectCount = 0;
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.updateInvoiceHeaderAndDates(
        context.history.Id,
        invoice.Id,
        invoice.InvoiceDate__c,
        paymentDue,
        'ignored-addressee',
        'ignored-to@example.com',
        null,
        null,
        8,
        token
      );
      Test.stopTest();

      System.assertEquals(
        1,
        AccountingCauseLockService.invoiceLockSelectCount,
        'Core 第12.4節: 行ロックの請求照会は1回'
      );
      System.assertEquals(
        0,
        InvoiceCanonicalService.headerInvoiceSelectCount,
        'Core 第12.4節: Canonicalはロック済み請求を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceProductFieldCopyService.catalogSelectCount,
        'Core 第12.4節・第11.4.2節: コピー定義を2カタログで取り直さない'
      );
      System.assertEquals(
        false,
        OrderCreateController.lastPreviewInvoiceSelectIds.contains(invoice.Id),
        'Core 第12.4節・第7.7.3節: 請求情報編集の返却は対象請求を取り直さない'
      );
      System.assertEquals(
        0,
        InvoiceOpsFieldService.extraFieldSelectCount,
        'Core 第12.4節: 返却カードの追加項目定義を取り直さない'
      );
      Invoice__c stored = [
        SELECT
          PaymentScheduledDate__c,
          BillingAddresseeSnapShot__c,
          TaxPercent__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(paymentDue, stored.PaymentScheduledDate__c);
      System.assertEquals(originalAddressee, stored.BillingAddresseeSnapShot__c);
      System.assertEquals(invoice.TaxPercent__c, stored.TaxPercent__c);
      System.assertNotEquals(null, preview);
    }
  }

  @IsTest
  static void applyBillingAccountContent_fromPreview_reusesLockedInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Invoice__c invoice = [
        SELECT Id, BillingAccountSnapShot__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      BillingAccount__c account = [
        SELECT Id
        FROM BillingAccount__c
        WHERE Id = :invoice.BillingAccountSnapShot__c
      ];
      account.InvoiceDeliveryMethod__c = InvoiceDeliveryMethodService.POST;
      update account;
      String token = OrderCreateController.getInvoicePreview(context.history.Id)
        .contentVersion;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Test.startTest();
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      InvoiceCanonicalService.headerInvoiceSelectCount = 0;
      InvoiceProductFieldCopyService.resetCache();
      InvoiceProductFieldCopyService.catalogSelectCount = 0;
      FieldCopyDefinitionService.resetCache();
      OrderCreateController.lastPreviewInvoiceSelectIds = new Set<Id>();
      InvoiceOpsFieldService.extraFieldSelectCount = 0;
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.applyBillingAccountContent(
        context.history.Id,
        invoice.Id,
        token
      );
      Test.stopTest();

      System.assertEquals(1, AccountingCauseLockService.invoiceLockSelectCount);
      System.assertEquals(0, InvoiceCanonicalService.headerInvoiceSelectCount);
      System.assertEquals(0, InvoiceProductFieldCopyService.catalogSelectCount);
      System.assertEquals(
        false,
        OrderCreateController.lastPreviewInvoiceSelectIds.contains(invoice.Id),
        'Core 第12.4節・第7.7.3節: 反映の返却は対象請求を取り直さない'
      );
      Invoice__c updated = [
        SELECT InvoiceDeliveryMethodSnapShot__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        InvoiceDeliveryMethodService.POST,
        updated.InvoiceDeliveryMethodSnapShot__c,
        'Core 第7.8節: 反映は届け方スナップショットを載せ直す'
      );
      System.assertNotEquals(null, preview);
    }
  }

  private static InvoiceCanonicalService.LineAmountEdit amountEdit(
    Id lineId,
    Decimal amount
  ) {
    InvoiceCanonicalService.LineAmountEdit edit = new InvoiceCanonicalService.LineAmountEdit();
    edit.lineId = lineId;
    edit.amount = amount;
    return edit;
  }

  private static OrderTestContext createCancelEstimateContext() {
    OrderTestContext context = new OrderTestContext();
    context.account = ContractTestDataFactory.insertAccount(
      'Order Cancel Account'
    );
    context.service = ContractTestDataFactory.insertContractService(
      context.account.Id,
      'Order Cancel Service'
    );
    context.service.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
    update context.service;
    context.billingAccount = [
      SELECT Id, BillingEmailTo__c
      FROM BillingAccount__c
      WHERE Id = :context.service.BiilingAcccount__c
    ];

    Date cancelDate = Date.newInstance(2026, 6, 1);
    context.history = new ContractHistory__c(
      Name = 'Order Cancel Churn',
      ContractService__c = context.service.Id,
      Type__c = 'Cancel',
      historystatus__c = 'Estimate',
      Version__c = 2,
      CurrentTermStartDate__c = cancelDate,
      CurrentTermEndDate__c = cancelDate,
      EffectiveDate__c = cancelDate
    );
    ContractTestDataFactory.applyRequiredFields(context.history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(
      context.history,
      context.account.Id
    );
    insert context.history;

    return context;
  }

  @IsTest
  static void getOrderContext_returnsJapaneseWhenWizardFieldInvalid() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderWizardField__mdt bad = new OrderWizardField__mdt();
      bad.DeveloperName = 'BadOrderField';
      bad.MasterLabel = 'BadOrderField';
      bad.FieldApiName__c = 'NoSuchField__c';
      bad.Active__c = true;
      OrderWizardFieldService.setCachedDefinitionsForTest(
        new List<OrderWizardField__mdt>{ bad }
      );
      Boolean thrown = false;
      try {
        OrderCreateController.getOrderContext(context.history.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '受注ウィザード追加項目「BadOrderField」の項目「NoSuchField__c」が契約履歴に存在しません。',
          ex.getMessage(),
          'Core 第11.4.3節: 有効な不正定義は fail-fast しエラーに DeveloperName を含める'
        );
      } finally {
        OrderWizardFieldService.resetCache();
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void confirmOrder_returnsJapaneseWhenWizardFieldInvalid() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderWizardField__mdt bad = new OrderWizardField__mdt();
      bad.DeveloperName = 'BadOrderField';
      bad.MasterLabel = 'BadOrderField';
      bad.FieldApiName__c = 'NoSuchField__c';
      bad.Active__c = true;
      OrderWizardFieldService.setCachedDefinitionsForTest(
        new List<OrderWizardField__mdt>{ bad }
      );
      Boolean thrown = false;
      try {
        OrderCreateController.confirmOrder(context.history.Id, null, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '受注ウィザード追加項目「BadOrderField」の項目「NoSuchField__c」が契約履歴に存在しません。',
          ex.getMessage(),
          'Core 第11.4.3節: 有効な不正定義は受注を続行せずエラーに DeveloperName を含める'
        );
      } finally {
        OrderWizardFieldService.resetCache();
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void revertOrder_returnsJapaneseWhenWizardFieldInvalid() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      OrderWizardField__mdt bad = new OrderWizardField__mdt();
      bad.DeveloperName = 'BadOrderField';
      bad.MasterLabel = 'BadOrderField';
      bad.FieldApiName__c = 'NoSuchField__c';
      bad.Active__c = true;
      OrderWizardFieldService.setCachedDefinitionsForTest(
        new List<OrderWizardField__mdt>{ bad }
      );
      Boolean thrown = false;
      try {
        OrderCreateController.revertOrder(context.history.Id, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '受注ウィザード追加項目「BadOrderField」の項目「NoSuchField__c」が契約履歴に存在しません。',
          ex.getMessage(),
          'Core 第11.4.3節: 有効な不正定義は差し戻しを続行せずエラーに DeveloperName を含める'
        );
      } finally {
        OrderWizardFieldService.resetCache();
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void resolvePreviewScope_nullAndUnsupported_cannotOpen() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderCreateController.PreviewScopeDto missing = OrderCreateController.resolvePreviewScope(
        null
      );
      System.assertEquals(false, missing.canOpen);
      System.assertEquals(
        '対象レコードが指定されていません。',
        missing.blockReason,
        'Core 第7.7.0節: 請求ボードは対象レコードが要る'
      );

      OrderCreateController.PreviewScopeDto unsupported = OrderCreateController.resolvePreviewScope(
        ContractTestDataFactory.insertAccount('Preview Scope Acct').Id
      );
      System.assertEquals(false, unsupported.canOpen);
      System.assertEquals(
        '請求ボードは契約履歴・契約サービス・請求書から開きます。',
        unsupported.blockReason,
        'Core 第7.7.0節: 請求ボードは契約履歴・契約サービス・請求書から開く'
      );
    }
  }

  @IsTest
  static void getInvoicePreview_nullHistory_returnsEmpty() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        null
      );
      System.assertEquals(false, preview.canView);
      System.assertEquals(false, preview.canEdit);
      System.assertEquals(
        0,
        preview.invoiceCount,
        'Core 第7.7.0節: 契約履歴が無ければ請求正本の作成は受注時のみでプレビューは空'
      );
      System.assertEquals(0, preview.versionOptions.size());
    }
  }
}
