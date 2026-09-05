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
        'Core 第4.3.12節: 受注入口は契約履歴の版トークンを返す'
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

      Test.startTest();
      OrderCreateController.confirmOrder(context.history.Id, null, false);
      Test.stopTest();

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
      update invoices[0];
      InvoiceTransactionStatusService.allowStatusWrite = false;
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
      System.assertNotEquals(null, beforeRevert.OrderDate__c);

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
        'Core 第5.3節: 画面外の差し戻しは受注日以外を触らない'
      );
      System.assertEquals(
        null,
        updated.OrderDate__c,
        'Core 第5.3節: 画面外の差し戻しも受注日は空'
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
        'Core 第5.3節: 画面外の差し戻しは受注日以外を触らない'
      );
      System.assertEquals(
        null,
        updated.OrderDate__c,
        'Core 第5.3節: 画面外の差し戻しも受注日は空'
      );
    }
  }

  @IsTest
  static void revertOrder_writesHistoryFieldsAndClearsOrderDate() {
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
            'ApplicationDate__c' => String.valueOf(nextApplication)
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
        null,
        updated.OrderDate__c,
        'Core 第5.3節: 差し戻し後の受注日は空'
      );
      System.assertEquals(
        false,
        updated.CreateRenewOpportunity__c,
        'Core 第5.3節: 差し戻し画面では更新商談要求を落とす'
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
      System.assertEquals(true, dto.canRevert);
      System.assertEquals(null, dto.revertBlockedReason);

      Test.startTest();
      OrderCreateController.revertOrder(context.history.Id, false);
      Test.stopTest();
      System.assertEquals(
        'Estimate',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .historystatus__c,
        '?????????????????E Archive'
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
        '第0.1節: 画面に Version と出す箇所は「版」とする'
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
      System.assertEquals(12, periodLines.size(), '??: 12???E?????');

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
            '???????????????????E amount=' +
              row.amount +
              ' delta=' +
              row.amountDeltaFromSource +
              ' source=' +
              row.sourceAmountTotal
          );
          System.assertEquals(
            0,
            row.amountDeltaFromSource,
            '?E????????E'
          );
        }
      }
      System.assertEquals(2, sawSplitLines, '240000/360000 ?2???????');
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

    // ???????????????Epot ????E?E
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
    OrderTestContext context = new OrderTestContext();
    context.account = ContractTestDataFactory.insertAccount(
      'Order Wizard Account'
    );
    context.service = ContractTestDataFactory.insertContractService(
      context.account.Id,
      'Order Wizard Service'
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
}
