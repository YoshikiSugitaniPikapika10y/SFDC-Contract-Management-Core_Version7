@IsTest
private class OrderCreateControllerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void getOrderContext_returnsEstimateHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();

      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );

      System.assertEquals(context.history.Id, dto.contractHistoryId);
      System.assertEquals('Estimate', dto.historyStatus);
      System.assertEquals(true, dto.canOrder);
      System.assertEquals(false, dto.isOrdered);
      System.assertEquals(1, dto.products.size());
      System.assertEquals(context.billingAccount.Id, dto.billingAccountId);
      System.assertNotEquals(
        null,
        dto.lastModifiedToken,
        '受注コンテキストに楽観ロックトークンが付くこと'
      );
      System.assertEquals(
        ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        dto.billingCustomFields.get('PaymentTerm__c')
      );
      System.assertEquals(
        '25',
        dto.billingCustomFields.get('BillingDayOfMonth__c')
      );
      System.assertEquals(
        false,
        dto.billingCustomFields.get('AdjustInvoiceDateToBusinessDay__c')
      );
    }
  }

  @IsTest
  static void saveOrderStep1_ignoresNoteField() {
    // 受注ウィザードStep1はNote__cを扱わない（見積の備考をそのまま引き継ぐため）。
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      String fieldsJson = '{"Note__c":"受注時備考"}';

      OrderCreateController.saveOrderStep1(context.history.Id, fieldsJson);

      ContractHistory__c updated = [
        SELECT Note__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals(null, updated.Note__c);
    }
  }

  @IsTest
  static void saveOrderStep2_isDisabled() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      try {
        OrderCreateController.saveOrderStep2(context.history.Id, '{}');
        System.assert(false, 'saveOrderStep2 は廃止のため失敗するべき');
      } catch (AuraHandledException ex) {
        System.assert(
          ex.getMessage().contains('請求アカウント更新は廃止'),
          ex.getMessage()
        );
      }
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
          ex.getMessage()
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
        System.assertEquals('契約履歴が見つかりません。', ex.getMessage());
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getOrderContext_orderedHistory_exposesRevertFlags() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      // 受注後: 受注ボタン不可／差し戻しは権限ありなら可／更新商談作成は受注確認画面のみ
      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );

      System.assertEquals(true, dto.isOrdered);
      System.assertEquals(false, dto.canOrder, '受注後は受注ボタンを出せない');
      System.assertEquals(
        true,
        dto.canRevert,
        '差し戻し権限がありロック等がなければ差し戻し可能'
      );
      System.assertEquals(null, dto.revertBlockedReason);
      System.assertEquals(
        false,
        dto.showCreateRenewOpportunity,
        '更新商談作成は受注ボタン押下時の画面だけ'
      );
      System.assert(
        dto.products != null && !dto.products.isEmpty(),
        '受注後も商品行が載ること'
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
          '差し戻しカスタム権限が無いと差し戻し不可'
        );
      } finally {
        OrderCreateController.testHasRevertPermission = true;
      }
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
          '見積（Estimate）状態の契約履歴のみ編集できます。',
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
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveOrderStep1_withoutPermission_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.testHasOrderPermission = false;
      Boolean thrown = false;
      try {
        OrderCreateController.saveOrderStep1(context.history.Id, '{}');
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
        '権限不足の差し戻しは状態を変えない'
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
  static void getInvoicePreview_withoutViewPermission_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.VIEW_INVOICE_PREVIEW => false
      };
      Boolean thrown = false;
      try {
        OrderCreateController.getInvoicePreview(context.history.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '請求プレビューを表示する権限がありません。',
          ex.getMessage()
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getBillingAccountOptionsForPreview_returnsAccountBillingAccounts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      BillingAccount__c second = new BillingAccount__c(
        Account__c = context.account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'second@example.com',
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_1,
        AdjustInvoiceDateToBusinessDay__c = false
      );
      ContractTestDataFactory.applyRequiredFields(second);
      insert second;

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

      Boolean thrown = false;
      try {
        OrderCreateController.resetLatestVersionInvoicesToPostOrder(
          context.history.Id,
          '',
          null
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          OrderCreateController.RESET_POST_ORDER_VERSION_REQUIRED_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void resetLatestVersionInvoicesToPostOrder_unknownVersion_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Boolean thrown = false;
      try {
        OrderCreateController.resetLatestVersionInvoicesToPostOrder(
          context.history.Id,
          '99',
          null
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          OrderCreateController.RESET_POST_ORDER_VERSION_NOT_FOUND_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
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
      OrderCreateController.confirmOrder(
        context.history.Id,
        null,
        false,
        dto.lastModifiedToken
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
  static void updateInvoiceLineAmounts_staleContentVersion_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      System.assertNotEquals(null, preview.contentVersion);
      System.assert(preview.invoices != null && !preview.invoices.isEmpty());
      Id lineId = null;
      for (OrderCreateController.InvoiceGroupDto inv : preview.invoices) {
        if (inv.lines != null && !inv.lines.isEmpty()) {
          lineId = inv.lines[0].lineId;
          break;
        }
      }
      System.assertNotEquals(null, lineId, '更新対象の請求明細があること');

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
    }
  }

  @IsTest
  static void confirmOrder_usesBillingAccountMasterForInvoiceGeneration() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      context.billingAccount.BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_15;
      update context.billingAccount;

      OrderCreateController.confirmOrder(context.history.Id, null, false);

      BillingAccount__c updatedBillingAccount = [
        SELECT BillingDayOfMonth__c
        FROM BillingAccount__c
        WHERE Id = :context.billingAccount.Id
      ];
      System.assertEquals('15', updatedBillingAccount.BillingDayOfMonth__c);

      // 請求日・BA SnapShot の正は Invoice__c（期間明細側は生成後クリア）
      List<Invoice__c> invoices = [
        SELECT InvoiceDate__c, BillingDayOfMonthSnapShot__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        ORDER BY InvoiceDate__c ASC NULLS LAST
      ];
      System.assert(invoices.size() > 0);
      System.assertEquals('15', invoices[0].BillingDayOfMonthSnapShot__c);
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

      context.billingAccount.BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_5;
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
          '一括前払でも請求日ルール（5日）が請求日に反映される'
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

      OrderCreateController.confirmOrder(context.history.Id, null, false);

      ContractHistory__c updated = [
        SELECT historystatus__c, Type__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Ordered', updated.historystatus__c);
      System.assertEquals('Cancel', updated.Type__c);

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
        '拒否時は請求が作られない'
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
        '拒否時は請求が作られない'
      );
    }
  }

  @IsTest
  static void confirmOrder_blocksDuplicateOrderedVersion() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      // 先に正規経路で V1 を受注しておき、同じ Version の別 Estimate を拒否させる
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
        '二重 Ordered 拒否時は請求が作られない'
      );
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
      update invoices[0];
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
      try {
        OrderCreateController.revertOrder(context.history.Id, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .historystatus__c,
        'ロック拒否時は Ordered のまま'
      );
      System.assertEquals(
        invoiceCountBefore,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :context.history.Id
        ],
        '拒否時は請求件数が変わらない'
      );
    }
  }

  @IsTest
  static void updateInvoiceDatesAndBillingHeader_persistsPreviewEdits() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      // 受注生成は startTest 前。3引数 confirmOrder オーバーロードも通す
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      Invoice__c invoice = [
        SELECT Id, InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];

      Date paymentDue = Date.newInstance(2026, 7, 31);
      Test.startTest();
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      OrderCreateController.InvoicePreviewDto datesPreview = OrderCreateController.updateInvoiceDates(
        context.history.Id,
        invoice.Id,
        invoice.InvoiceDate__c,
        paymentDue
      );
      System.assert(datesPreview.invoiceCount >= 1);

      Invoice__c afterDates = [
        SELECT PaymentScheduledDate__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        paymentDue,
        afterDates.PaymentScheduledDate__c,
        '入金予定日が保存されること'
      );
      System.assertEquals(
        true,
        afterDates.IsManuallyAdjusted__c,
        '日付編集後は手動調整フラグが立つこと'
      );

      OrderCreateController.InvoicePreviewDto headerPreview = OrderCreateController.updateInvoiceBillingHeader(
        context.history.Id,
        invoice.Id,
        context.billingAccount.Id,
        'プレビュー宛名 御中',
        'preview-to@example.com',
        null,
        null,
        ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        10
      );
      System.assert(headerPreview.invoiceCount >= 1);

      Invoice__c afterHeader = [
        SELECT
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          TaxPercent__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        'プレビュー宛名 御中',
        afterHeader.BillingAddresseeSnapShot__c
      );
      System.assertEquals(
        'preview-to@example.com',
        afterHeader.BillingEmailToSnapShot__c
      );

      Date combinedDue = Date.newInstance(2026, 8, 31);
      OrderCreateController.InvoicePreviewDto combinedPreview = OrderCreateController.updateInvoiceHeaderAndDates(
        context.history.Id,
        invoice.Id,
        invoice.InvoiceDate__c,
        combinedDue,
        '一体保存宛名 御中',
        'combined-to@example.com',
        null,
        null,
        8,
        null
      );
      System.assert(combinedPreview.invoiceCount >= 1);
      Test.stopTest();

      Invoice__c afterCombined = [
        SELECT
          PaymentScheduledDate__c,
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(combinedDue, afterCombined.PaymentScheduledDate__c);
      System.assertEquals(
        '一体保存宛名 御中',
        afterCombined.BillingAddresseeSnapShot__c
      );
      System.assertEquals(
        'combined-to@example.com',
        afterCombined.BillingEmailToSnapShot__c
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
        '分割先候補の請求アカウントがあること'
      );

      BillingAccount__c otherBa = new BillingAccount__c(
        Account__c = context.account.Id,
        BillingAddressee__c = '別請求先 御中',
        BillingEmailTo__c = 'other-ba@example.com',
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_20,
        AdjustInvoiceDateToBusinessDay__c = false
      );
      ContractTestDataFactory.applyRequiredFields(otherBa);
      insert otherBa;

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
      Integer invoiceCountBefore = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
      ];
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 1;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.splitInvoiceByBillingAccount(
        context.history.Id,
        source.Id,
        otherBa.Id,
        null,
        null,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      System.assertEquals(
        invoiceCountBefore + 1,
        preview.invoiceCount,
        'BA分割で請求が1件増えること'
      );
      System.assertEquals(
        true,
        OrderCreateController.hasManualInvoiceAdjustment(context.history.Id),
        '分割後は手動調整ありになること'
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
        '分割先BAの SnapShot を持つ請求が1件あること'
      );
    }
  }

  @IsTest
  static void revertOrder_returnsHistoryToEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      ContractService__c orderedService = [
        SELECT Lifecycle__c
        FROM ContractService__c
        WHERE Id = :context.service.Id
      ];
      System.assertEquals(
        ContractDomainConstants.LIFECYCLE_TERM,
        orderedService.Lifecycle__c
      );

      OrderCreateController.revertOrder(context.history.Id, false);

      ContractHistory__c updated = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.history.Id
      ];
      System.assertEquals('Estimate', updated.historystatus__c);

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
  static void confirmOrder_createsRenewOpportunityWhenRequested() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContextWithOpportunity();
      stubRenewOpportunityDefinitions();

      OrderCreateController.OrderContextDto beforeOrder = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(true, beforeOrder.showCreateRenewOpportunity);
      System.assertEquals(false, beforeOrder.hasRenewOpportunity);

      Test.startTest();
      OrderCreateController.OrderSaveResult result = OrderCreateController.confirmOrder(
        context.history.Id,
        null,
        true
      );
      Test.stopTest();

      System.assertNotEquals(null, result.renewOpportunityId);
      Opportunity renewOpp = [
        SELECT PreviousOpportunity__c, SourceContractHistory__c, AccountId
        FROM Opportunity
        WHERE Id = :result.renewOpportunityId
      ];
      System.assertEquals(
        context.opportunity.Id,
        renewOpp.PreviousOpportunity__c
      );
      System.assertEquals(
        context.history.Id,
        renewOpp.SourceContractHistory__c
      );
      System.assertEquals(context.account.Id, renewOpp.AccountId);

      OrderCreateController.OrderContextDto afterOrder = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(true, afterOrder.hasRenewOpportunity);
      System.assertEquals(
        result.renewOpportunityId,
        afterOrder.renewOpportunityId
      );

      OrderCreateController.revertOrder(context.history.Id, true);
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Opportunity
          WHERE Id = :result.renewOpportunityId
        ]
      );
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
    }
  }

  @IsTest
  static void getOrderContext_hidesCreateRenewForSpotAndSkipsCreate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createSpotEstimateContextWithOpportunity();
      stubRenewOpportunityDefinitions();

      OrderCreateController.OrderContextDto beforeOrder = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(
        false,
        beforeOrder.showCreateRenewOpportunity,
        'Spot では更新商談チェックを出さない'
      );

      Test.startTest();
      OrderCreateController.OrderSaveResult result = OrderCreateController.confirmOrder(
        context.history.Id,
        null,
        true
      );
      Test.stopTest();

      System.assertEquals(
        null,
        result.renewOpportunityId,
        'Spot では createRenewOpportunity=true でも更新商談を作らない'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Opportunity
          WHERE SourceContractHistory__c = :context.history.Id
        ],
        'Spot 受注後も更新商談は存在しない'
      );
    }
  }

  @IsTest
  static void revertOrder_blocksWhenNewerOrderedVersionExists() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      ContractProduct__c v1Product = [
        SELECT Id, Product__c
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
      insert newerHistory;

      insert new ContractProduct__c(
        ContractHistory__c = newerHistory.Id,
        Product__c = v1Product.Product__c,
        Quantity__c = 10,
        UnitPrice__c = 5000,
        Amount__c = -200000,
        Unit__c = 'ID',
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 9, 30),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original',
        PreviousContractProduct__c = v1Product.Id
      );

      insert new ContractProduct__c(
        ContractHistory__c = newerHistory.Id,
        Product__c = v1Product.Product__c,
        Quantity__c = 10,
        UnitPrice__c = 6000,
        Amount__c = 720000,
        Unit__c = 'ID',
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = v1Product.Id
      );

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
        '後続受注がある差し戻し拒否後も Ordered'
      );
    }
  }

  @IsTest
  static void revertOrder_blocksWhenNewerEstimateVersionExists() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      insert new ContractHistory__c(
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

      OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
        context.history.Id
      );
      System.assertEquals(false, dto.canRevert);
      System.assertEquals(
        EstimateRevertInvoiceService.NEWER_ESTIMATE_REVERT_MESSAGE,
        dto.revertBlockedReason
      );

      Boolean thrown = false;
      try {
        OrderCreateController.revertOrder(context.history.Id, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          EstimateRevertInvoiceService.NEWER_ESTIMATE_REVERT_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .historystatus__c,
        '後続見積がある差し戻し拒否後も Ordered'
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
          '受注済み（Ordered）状態の契約履歴のみ差し戻しできます。',
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
        '権限不足の受注は状態を変えない'
      );

      OrderCreateController.testHasOrderPermission = false;
      try {
        OrderCreateController.OrderContextDto dto = OrderCreateController.getOrderContext(
          context.history.Id
        );
        System.assertEquals(false, dto.canOrder);
        System.assertEquals(true, dto.showCreateRenewOpportunity);
      } finally {
        OrderCreateController.testHasOrderPermission = true;
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

      // ロックは請求正本（Invoice__c）側。期間明細の連携日更新だけではプレビューに反映されない。
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
        '受注後に請求正本が生成されていること'
      );
      invoices[0].SystemIntegrationDate__c = Date.today();
      update invoices[0];

      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );

      System.assertEquals(
        invoices[0].Amount__c,
        preview.integratedAmount,
        '連携のみの請求は請求済（未消込）に全額'
      );
      System.assert(preview.openAmount >= 0);
      System.assert(preview.invoices.size() > 0);
      System.assert(preview.lineCount > 0);
      System.assert(preview.totalTaxAmount > 0);
      System.assertEquals(
        false,
        preview.versionEditBlocked,
        'プレビュー編集は請求書単位のため Version 一括ブロックしない'
      );

      Boolean foundIntegrated = false;
      Boolean foundLocked = false;
      Boolean foundUnlocked = false;
      for (OrderCreateController.InvoiceGroupDto invoice : preview.invoices) {
        if (invoice.integratedAmount == invoices[0].Amount__c) {
          foundIntegrated = true;
          System.assertEquals(true, invoice.locked, '連携済請求は locked=true');
          System.assertEquals(0, invoice.openAmount, '連携後は請求前0');
          System.assertEquals(0, invoice.clearedAmount, '未消込なら入金消込0');
          foundLocked = true;
        } else if (invoice.locked != true) {
          foundUnlocked = true;
        }
      }
      System.assertEquals(true, foundIntegrated);
      System.assertEquals(true, foundLocked);
      // 月次で複数請求がある前提。1件だけの場合は unlocked が無くてもよい
      if (preview.invoices.size() > 1) {
        System.assertEquals(
          true,
          foundUnlocked,
          '同 Version の未ロック請求は編集対象として残る'
        );
      }
    }
  }

  @IsTest
  static void getInvoicePreview_returnsServiceWideMergedInvoicesAfterOrder() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );

      System.assert(preview.invoiceCount > 0);
      System.assert(preview.lineCount > 0);
      System.assert(preview.invoices.size() > 0);
      System.assert(preview.invoices[0].lines.size() > 0);
      System.assertNotEquals(null, preview.invoices[0].lines[0].periodLabel);
      System.assert(preview.totalAmount > 0);
      System.assert(preview.totalTaxAmount > 0);
      System.assertNotEquals(null, preview.versionOptions);
      System.assertEquals(1, preview.versionOptions.size());
      System.assertEquals(
        String.valueOf(context.history.Version__c.intValue()),
        preview.versionOptions[0].value
      );
      System.assertEquals(
        String.valueOf(context.history.Version__c.intValue()),
        preview.sourceHistoryVersion,
        'プレビュー起点の契約履歴 Version をフィルタ初期値として返すこと'
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
        '全月請求済みなら見積バーは契約商品 Amount 合計と一致すること'
      );
      System.assertEquals(
        preview.periodLineAmountTotal,
        preview.versionOptions[0].periodLineAmountTotal,
        '単一 Version では版別見積合計と全体が見合っていること'
      );
      System.assertEquals(
        preview.invoiceAmountTotal,
        preview.versionOptions[0].invoiceAmountTotal,
        '単一 Version では版別請求合計と全体が見合っていること'
      );
      System.assertEquals(
        preview.amountDifference,
        preview.versionOptions[0].amountDifference,
        '単一 Version では版別ずれと全体が見合っていること'
      );
      System.assertNotEquals(null, preview.invoices[0].taxTotal);
      System.assertNotEquals(
        null,
        preview.invoices[0].lines[0].historyVersions
      );
    }
  }

  @IsTest
  static void confirmOrder_blocksWhenContractProductAmountIsNull() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      ContractProduct__c product = [
        SELECT Id, Amount__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      product.Amount__c = null;
      update product;

      Boolean thrown = false;
      try {
        OrderCreateController.confirmOrder(context.history.Id, null, false);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOrderValidationService.AMOUNT_MISSING_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown, 'Amount null のまま受注できないこと');
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
        '拒否時は請求が作られない'
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

      // 同 Version の並存見積（受注時に Archive される）
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
        '負け見積は Archive になること'
      );

      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Test.stopTest();

      System.assertEquals(
        600000,
        preview.periodLineAmountTotal,
        '見積バーは Ordered のみ。Archive の 999999 を混ぜない'
      );
      System.assertEquals(
        600000,
        preview.versionOptions[0].periodLineAmountTotal,
        'Version 別見積も Ordered のみ'
      );
      System.assert(
        preview.periodLineAmountTotal != 600000 + 999999,
        'Archive 混入がないこと'
      );
    }
  }

  @IsTest
  static void getPeriodSplitCandidates_returnsSourcePeriodMonths() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      Invoice__c invoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];

      Test.startTest();
      List<OrderCreateController.PeriodSplitCandidateDto> rows = OrderCreateController.getPeriodSplitCandidates(
        invoice.Id
      );
      Test.stopTest();

      System.assert(rows.size() > 0, '利用月候補が1件以上返ること');
      System.assertNotEquals(null, rows[0].periodLineId);
      System.assertNotEquals(null, rows[0].invoiceLineId);
      System.assertNotEquals(null, rows[0].periodLabel);
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
      List<InvoiceCanonicalService.SplitThresholdLineOptions> options = OrderCreateController.getSplitThresholdDateOptions(
        invoice.Id
      );
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.splitLinesInPlace(
        context.history.Id,
        invoice.Id,
        new List<InvoiceCanonicalService.SplitLineInput>{ split },
        null
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
      System.assertEquals(1, invoiceCount, '同一請求のまま');
      System.assert(lineCount >= 2, '明細が分割されて増えていること');
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
      OrderCreateController.updateInvoiceLineAmount(
        context.history.Id,
        line.Id,
        originalAmount + 1,
        null
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

      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.resetLatestVersionInvoicesToPostOrder(
        context.history.Id,
        '1',
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
        '受注直後リセットで手動調整が消えること'
      );
    }
  }

  @IsTest
  static void resetLatestVersionInvoicesToPostOrder_resolveBlocksNonLatest() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      // 後続 Ordered Version を軽量に差し、resolve だけ検証（Change 再受注の SOQL を避ける）
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
        '過去 Version は resolve で拒否すること'
      );

      Id latestId = OrderCreateController.resolveLatestOrderedHistoryIdForReset(
        newerHistory.Id,
        '2'
      );
      System.assertEquals(newerHistory.Id, latestId);

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
        '過去 Version の請求は resolve だけでは変わらないこと'
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
      update invoices;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Boolean thrown = false;
      try {
        Test.startTest();
        OrderCreateController.resetLatestVersionInvoicesToPostOrder(
          context.history.Id,
          '1',
          null
        );
        Test.stopTest();
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        thrown,
        'ロック請求がある Version はリセット不可'
      );
    }
  }

  @IsTest
  static void splitInvoiceByPeriod_returnsRefreshedPreview() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderTestContext context = createEstimateContext();
      OrderCreateController.confirmOrder(context.history.Id, null, false);

      Invoice__c invoice = [
        SELECT Id, Amount__c
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
        LIMIT 1
      ];
      List<OrderCreateController.PeriodSplitCandidateDto> candidates = OrderCreateController.getPeriodSplitCandidates(
        invoice.Id
      );
      System.assert(candidates.size() >= 1, '利用月候補があること');

      Decimal moveAmount = candidates[0].amount == null
        ? 0
        : candidates[0].amount;
      Date newInvoiceDate = Date.newInstance(2026, 7, 1);

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.splitInvoiceByPeriod(
        context.history.Id,
        invoice.Id,
        newInvoiceDate,
        Date.newInstance(2026, 7, 31),
        new List<Id>{ candidates[0].periodLineId },
        null
      );
      Test.stopTest();

      System.assertNotEquals(null, preview);
      System.assert(
        preview.invoiceCount > 0,
        '分割後も請求プレビューが返ること'
      );
      Boolean foundMoved = false;
      for (OrderCreateController.InvoiceGroupDto row : preview.invoices) {
        if (
          row.invoiceDate == String.valueOf(newInvoiceDate) &&
          row.amountTotal == moveAmount
        ) {
          foundMoved = true;
          break;
        }
      }
      System.assertEquals(
        true,
        foundMoved,
        '移した利用月の金額で新請求が作られていること'
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
      System.assertEquals(12, periodLines.size(), '前提: 12ヶ月分の期間明細');
      delete new List<InvoiceProduct__c>{ periodLines[10], periodLines[11] };
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ context.history.Id }
      );

      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        context.history.Id
      );
      Test.stopTest();

      // CP.Amount 600000（12ヶ月）× 10/12 = 500000
      System.assertEquals(
        500000,
        preview.periodLineAmountTotal,
        '見積額は請求に載った月数で按分すること'
      );
      System.assertEquals(
        500000,
        preview.invoiceAmountTotal,
        '請求合計は残った10ヶ月分'
      );
      System.assertEquals(
        0,
        preview.amountDifference,
        '按分後はヘッダーずれが0であること'
      );
      System.assertEquals(
        500000,
        preview.versionOptions[0].periodLineAmountTotal,
        'Version 別見積も同じ按分定義であること'
      );

      Boolean sawLine = false;
      for (OrderCreateController.InvoiceGroupDto invoice : preview.invoices) {
        for (OrderCreateController.InvoiceMergedLineDto line : invoice.lines) {
          sawLine = true;
          System.assertEquals(
            false,
            line.hasAmountDrift,
            '明細ずれも0であること: ' + line.amountDeltaFromSource
          );
          System.assertEquals(
            0,
            line.amountDeltaFromSource,
            '明細の amountDeltaFromSource が0'
          );
        }
      }
      System.assertEquals(true, sawLine, '明細が1件以上あること');
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
        '全月請求済みなら見積額は手入力 Amount 全額'
      );
      System.assertEquals(
        600000,
        preview.invoiceAmountTotal,
        '請求は数量×単価×月数のまま'
      );
      System.assertEquals(
        -20,
        preview.amountDifference,
        '手入力端数のずれが残ること'
      );
      System.assertEquals(
        -20,
        preview.versionOptions[0].amountDifference,
        'Version 別ずれも同値'
      );
    }
  }

  /**
   * 金額／単価分割で全期間 ID を持つ明細と、しきい日分割で一部期間だけの明細が混在すると、
   * 期間金額比では行だけ数千円の偽ずれになる。共有 ID があるときは明細金額比へフォールバックする。
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
      System.assertEquals(12, periodLines.size(), '前提: 12ヶ月');
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

      // 単価分割 → 両明細が全期間 ID を共有
      InvoiceCanonicalService.SplitLineInput factor = new InvoiceCanonicalService.SplitLineInput();
      factor.lineId = anchor.Id;
      factor.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      factor.moveUnitPrice = 2000;
      factor.remainUnitPrice = 3000;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
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

      // 大きい方だけしきい日分割 → 全期間ID行と部分期間行が混在
      InvoiceCanonicalService.SplitLineInput periodSplit = new InvoiceCanonicalService.SplitLineInput();
      periodSplit.lineId = afterFactor[0].Id;
      periodSplit.splitMode = InvoiceCanonicalService.SPLIT_MODE_PERIOD;
      periodSplit.thresholdDate = Date.newInstance(2026, 12, 1);
      InvoiceCanonicalService.splitLinesInPlace(
        keepInvoiceId,
        new List<InvoiceCanonicalService.SplitLineInput>{ periodSplit }
      );

      Test.startTest();
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
            '共有ID混在でも行ずれはヘッダ級（±2円以内）: amount=' +
              row.amount +
              ' delta=' +
              delta +
              ' src=' +
              row.sourceAmountTotal
          );
        }
      }
      System.assert(saw >= 3, '分割後明細が3行以上あること');
      System.assertEquals(
        preview.amountDifference,
        lineDeltaSum,
        '行ずれ合計はヘッダずれと一致'
      );
    }
  }

  /**
   * 月ごとの InvoiceProduct 金額が不均等な複数月明細を期間分割すると、
   * 旧・月数比配分はヘッダ端数なしなのに行だけ ±偽ずれになる。
   * 由来期間金額比なら行ずれも0のまま。
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
      System.assertEquals(12, periodLines.size(), '前提: 12ヶ月分の期間明細');

      List<InvoiceProduct__c> periodUpdates = new List<InvoiceProduct__c>();
      List<String> allPeriodIdTexts = new List<String>();
      for (Integer i = 0; i < periodLines.size(); i++) {
        periodUpdates.add(
          new InvoiceProduct__c(
            Id = periodLines[i].Id,
            Amount__c = i < 6 ? 40000 : 60000
          )
        );
        allPeriodIdTexts.add(String.valueOf(periodLines[i].Id));
      }
      update periodUpdates;

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
      System.assert(!allLines.isEmpty(), '前提: 請求明細があること');

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

      System.assertEquals(0, preview.amountDifference, 'ヘッダずれは0');

      Integer sawSplitLines = 0;
      Decimal deltaSum = 0;
      for (OrderCreateController.InvoiceGroupDto invoice : preview.invoices) {
        for (OrderCreateController.InvoiceMergedLineDto row : invoice.lines) {
          if (row.amount != 240000 && row.amount != 360000) {
            continue;
          }
          sawSplitLines++;
          deltaSum += row.amountDeltaFromSource == null
            ? 0
            : row.amountDeltaFromSource;
          System.assertEquals(
            false,
            row.hasAmountDrift,
            '不均等月でも期間金額比なら偽ずれなし: amount=' +
              row.amount +
              ' delta=' +
              row.amountDeltaFromSource +
              ' source=' +
              row.sourceAmountTotal
          );
          System.assertEquals(
            0,
            row.amountDeltaFromSource,
            '分割明細のずれも0'
          );
        }
      }
      System.assertEquals(2, sawSplitLines, '240000/360000 の2明細があること');
      System.assertEquals(0, deltaSum, '行ずれ合計も0');
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
      System.assert(line.Amount__c > 1, '前提: 分割できる金額があること');
      System.assert(
        String.isNotBlank(line.SourcePeriodLineIds__c),
        '前提: 期間 ID が載っていること'
      );

      Decimal moveAmount = (line.Amount__c / 2)
        .setScale(0, System.RoundingMode.DOWN);
      Decimal remainAmount = line.Amount__c - moveAmount;
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = moveAmount;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.splitInvoiceByDate(
        context.history.Id,
        source.Id,
        Date.newInstance(2026, 8, 1),
        Date.newInstance(2026, 8, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      System.assertEquals(
        600000,
        preview.periodLineAmountTotal,
        'ヘッダー見積額は変わらないこと'
      );
      System.assertEquals(
        600000,
        preview.invoiceAmountTotal,
        '請求合計も変わらないこと'
      );
      System.assertEquals(0, preview.amountDifference, 'ヘッダーずれは0');
      System.assertEquals(
        0,
        preview.manualAdjustmentAmount,
        '金額分割だけでは端数調整実績も0（由来ID重複で偽マイナスにしない）'
      );
      if (preview.versionOptions != null && !preview.versionOptions.isEmpty()) {
        System.assertEquals(
          0,
          preview.versionOptions[0].manualAdjustmentAmount,
          'Version 別の端数調整実績も0であること'
        );
      }

      Integer sawSplitLines = 0;
      for (OrderCreateController.InvoiceGroupDto invoice : preview.invoices) {
        for (OrderCreateController.InvoiceMergedLineDto row : invoice.lines) {
          if (row.amount != moveAmount && row.amount != remainAmount) {
            // 分割していない月次明細も含め、全体で偽ずれがないこと
            System.assertEquals(
              false,
              row.hasAmountDrift,
              '未分割明細にも偽ずれが出ないこと: amount=' +
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
            '金額分割だけでは偽ずれが出ないこと: amount=' +
              row.amount +
              ' delta=' +
              row.amountDeltaFromSource
          );
          System.assertEquals(
            0,
            row.amountDeltaFromSource,
            '分割明細のずれも0であること'
          );
        }
      }
      System.assertEquals(2, sawSplitLines, '残す／移すの2明細があること');
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
      System.assert(line.Amount__c > 1, '前提: 分割できる金額があること');

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = (line.Amount__c / 2)
        .setScale(0, System.RoundingMode.DOWN);

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      OrderCreateController.InvoicePreviewDto afterSplit = OrderCreateController.splitInvoiceByDate(
        context.history.Id,
        source.Id,
        Date.newInstance(2026, 9, 1),
        Date.newInstance(2026, 9, 30),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      System.assert(
        afterSplit.invoices.size() >= 2,
        '前提: 分割で請求が2件以上あること'
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
      System.assertNotEquals(null, createdId, '分割先請求があること');

      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.moveLinesToExistingInvoice(
        context.history.Id,
        createdId,
        source.Id,
        new List<Id>{ createdLineId },
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
      System.assertEquals(true, sourceExists, '移動先請求は残ること');
      System.assertEquals(
        false,
        createdExists,
        '全明細移動後は移動元が消えること'
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
    OrderTestContext context = createEstimateContext();
    context.opportunity = ContractTestDataFactory.insertOpportunity(
      context.account.Id,
      'Order Spot Source Opportunity'
    );
    context.history.Opportunity__c = context.opportunity.Id;
    update context.history;

    // 継続課金を一回課金に差し替え（Spot 見込み）
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

  private static void stubRenewOpportunityDefinitions() {
    RenewOpportunityCreateService.resetCache();
    List<RenewOpportunityField__mdt> definitions = new List<RenewOpportunityField__mdt>{
      new RenewOpportunityField__mdt(
        DeveloperName = 'Name',
        Active__c = true,
        TargetFieldApiName__c = 'Name',
        ValueType__c = 'Template',
        Value__c = '{Account.Name} 更新'
      ),
      new RenewOpportunityField__mdt(
        DeveloperName = 'CloseDate',
        Active__c = true,
        TargetFieldApiName__c = 'CloseDate',
        ValueType__c = 'Field',
        Value__c = 'ContractHistory__c.CurrentTermEndDate__c'
      ),
      new RenewOpportunityField__mdt(
        DeveloperName = 'StageName',
        Active__c = true,
        TargetFieldApiName__c = 'StageName',
        ValueType__c = 'Constant',
        Value__c = firstActiveOpportunityStage()
      ),
      new RenewOpportunityField__mdt(
        DeveloperName = 'ContactId',
        Active__c = true,
        TargetFieldApiName__c = 'ContactId',
        ValueType__c = 'Field',
        Value__c = 'Opportunity.ContactId'
      )
    };
    Map<String, Schema.SObjectField> fields = Schema.SObjectType.Opportunity.fields.getMap();
    if (fields.containsKey('RecordTypeId')) {
      definitions.add(
        new RenewOpportunityField__mdt(
          DeveloperName = 'RecordTypeId',
          Active__c = true,
          TargetFieldApiName__c = 'RecordTypeId',
          ValueType__c = 'Field',
          Value__c = 'Opportunity.RecordTypeId'
        )
      );
    }
    if (fields.containsKey('OpportunityCreater__c')) {
      definitions.add(
        new RenewOpportunityField__mdt(
          DeveloperName = 'OpportunityCreater',
          Active__c = true,
          TargetFieldApiName__c = 'OpportunityCreater__c',
          ValueType__c = 'Field',
          Value__c = 'Opportunity.OpportunityCreater__c'
        )
      );
    }
    if (fields.containsKey('CustomFieldDefinition9__c')) {
      definitions.add(
        new RenewOpportunityField__mdt(
          DeveloperName = 'CustomFieldDefinition9',
          Active__c = true,
          TargetFieldApiName__c = 'CustomFieldDefinition9__c',
          ValueType__c = 'Field',
          Value__c = 'Opportunity.CustomFieldDefinition9__c'
        )
      );
    }
    RenewOpportunityCreateService.cachedDefinitions = definitions;
  }

  private static String firstActiveOpportunityStage() {
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

  private static OrderTestContext createEstimateContext() {
    OrderTestContext context = new OrderTestContext();
    context.account = ContractTestDataFactory.insertAccount(
      'Order Wizard Account'
    );

    context.billingAccount = new BillingAccount__c(
      Account__c = context.account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      BillingEmailCc__c = 'cc@example.com',
      BillingEmailBcc__c = 'bcc@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
      AdjustInvoiceDateToBusinessDay__c = false
    );
    ContractTestDataFactory.applyRequiredFields(context.billingAccount);
    insert context.billingAccount;

    context.service = new ContractService__c(
      Name = 'Order Wizard Service',
      Account__c = context.account.Id,
      BiilingAcccount__c = context.billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    insert context.service;

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
    insert context.history;

    Product2 product = ContractTestDataFactory.buildProduct(
      'Order Wizard Product'
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProduct(product);

    insert new ContractProduct__c(
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

    return context;
  }

  private static OrderTestContext createCancelEstimateContext() {
    OrderTestContext context = new OrderTestContext();
    context.account = ContractTestDataFactory.insertAccount(
      'Order Cancel Account'
    );

    context.billingAccount = new BillingAccount__c(
      Account__c = context.account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      BillingEmailCc__c = 'cc@example.com',
      BillingEmailBcc__c = 'bcc@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
      AdjustInvoiceDateToBusinessDay__c = false
    );
    ContractTestDataFactory.applyRequiredFields(context.billingAccount);
    insert context.billingAccount;

    context.service = new ContractService__c(
      Name = 'Order Cancel Service',
      Account__c = context.account.Id,
      BiilingAcccount__c = context.billingAccount.Id
    );
    insert context.service;

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
    insert context.history;

    return context;
  }
}
