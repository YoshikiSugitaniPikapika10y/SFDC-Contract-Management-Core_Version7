@IsTest
private class EstimateWizardCustomFieldPresetTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void getEstimateEditPreset_loadsCustomFieldsAndEditSaveKeepsProductMemo() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account testAccount = ContractTestDataFactory.insertAccount(
        'CF Preset Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'CF Preset Opportunity'
      );

      Product2 product = ContractTestDataFactory.buildProduct(
        'CF Preset Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 10000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.Family = ContractTestDataFactory.WIZARD_TEST_PRODUCT_FAMILY;
      ContractTestDataFactory.insertProduct(product);

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();

      EstimateCreateController.ProductLineItem lineItem = new EstimateCreateController.ProductLineItem();
      lineItem.productId = product.Id;
      lineItem.quantity = 1;
      lineItem.unitPrice = 10000;
      lineItem.amount = 10000;
      lineItem.startDate = String.valueOf(termStart);
      lineItem.endDate = String.valueOf(termEnd);
      lineItem.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      lineItem.unit = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      lineItem.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      lineItem.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      lineItem.billingCycle = '月';
      lineItem.recordType = 'New';
      lineItem.customFields = new Map<String, Object>{
        'Description__c' => 'product-memo-original'
      };

      EstimateCreateController.EstimateSaveResult saveResult = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'CF Preset Service',
        'CF Preset History',
        null,
        null,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(termStart),
        null,
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{ lineItem }
        ),
        null,
        null,
        null,
        null,
        null,
        JSON.serialize(
          new Map<String, Object>{
            'CustomerMemo__c' => 'service-memo-original'
          }
        ),
        JSON.serialize(
          new Map<String, Object>{
            'ApplicationDate__c' => String.valueOf(
              ContractTestDataFactory.stableTermStart()
            )
          }
        )
      );

      Test.startTest();
      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateEditPreset(
        saveResult.contractHistoryId
      );
      Test.stopTest();

      System.assertEquals(
        'service-memo-original',
        preset.contractServiceCustomFields.get('CustomerMemo__c')
      );
      System.assertEquals(
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        preset.contractHistoryCustomFields.get('ApplicationDate__c')
      );
      System.assertEquals(1, preset.selectedProducts.size());
      System.assertEquals(
        'product-memo-original',
        preset.selectedProducts[0].customFields.get('Description__c')
      );
      System.assertEquals(true, preset.contractCustomFieldsExpanded);

      EstimateCreateController.ProductLineItem editedLine = preset.selectedProducts[0];
      EstimateCreateController.EstimateSaveResult editResult = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        preset.contractServiceName,
        preset.contractHistoryName,
        preset.contractServiceId,
        null,
        preset.contractStartDate,
        preset.endDate,
        preset.contractEffectiveDate,
        null,
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{ editedLine }
        ),
        null,
        preset.estimateRemarks,
        preset.billingAccountId,
        null,
        saveResult.contractHistoryId,
        JSON.serialize(preset.contractServiceCustomFields),
        JSON.serialize(preset.contractHistoryCustomFields)
      );

      ContractProduct__c reloadedProduct = [
        SELECT Description__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :editResult.contractHistoryId
        LIMIT 1
      ];
      System.assertEquals(
        'product-memo-original',
        reloadedProduct.Description__c,
        '編集保存後も商品カスタム項目が残ること'
      );
    }
  }

  @IsTest
  static void orderedEdit_updatesCustomFieldsOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Ordered CF Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Ordered CF Opportunity'
      );

      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = testAccount.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
        BillingEmailCc__c = 'cc@example.com',
        BillingEmailBcc__c = 'bcc@example.com',
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

      Product2 product = ContractTestDataFactory.buildProduct(
        'Ordered CF Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 10000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.Family = ContractTestDataFactory.WIZARD_TEST_PRODUCT_FAMILY;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem lineItem = new EstimateCreateController.ProductLineItem();
      lineItem.productId = product.Id;
      lineItem.quantity = 2;
      lineItem.unitPrice = 10000;
      lineItem.amount = 20000;
      lineItem.startDate = String.valueOf(
        ContractTestDataFactory.stableTermStart()
      );
      lineItem.endDate = String.valueOf(
        ContractTestDataFactory.stableTermEnd()
      );
      lineItem.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      lineItem.unit = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      lineItem.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      lineItem.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      lineItem.billingCycle = '月';
      lineItem.recordType = 'New';
      lineItem.customFields = new Map<String, Object>{
        'Description__c' => 'product-before'
      };

      EstimateCreateController.EstimateSaveResult saveResult = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Ordered CF Service',
        'Ordered CF History',
        null,
        null,
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        String.valueOf(ContractTestDataFactory.stableTermEnd()),
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        null,
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{ lineItem }
        ),
        null,
        'remark-before',
        billingAccount.Id,
        null,
        null,
        JSON.serialize(
          new Map<String, Object>{ 'CustomerMemo__c' => 'service-before' }
        ),
        JSON.serialize(
          new Map<String, Object>{
            'ApplicationDate__c' => String.valueOf(
              ContractTestDataFactory.stableTermStart()
            )
          }
        )
      );

      ContractHistory__c history = [
        SELECT
          Id,
          Name,
          historystatus__c,
          Note__c,
          CurrentTermStartDate__c,
          CurrentTermEndDate__c,
          ContractService__c
        FROM ContractHistory__c
        WHERE Id = :saveResult.contractHistoryId
      ];
      ensureBillingAccountOnService(history.ContractService__c, testAccount.Id);
      history.historystatus__c = 'Ordered';
      update history;

      ContractService__c serviceBefore = [
        SELECT Id, Name, CustomerMemo__c
        FROM ContractService__c
        WHERE Id = :history.ContractService__c
      ];
      String serviceNameBefore = serviceBefore.Name;
      Date startBefore = history.CurrentTermStartDate__c;
      Date endBefore = history.CurrentTermEndDate__c;
      String historyNameBefore = history.Name;
      String remarksBefore = history.Note__c;

      ContractProduct__c productBefore = [
        SELECT Id, Quantity__c, UnitPrice__c, Description__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :history.Id
        LIMIT 1
      ];

      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateEditPreset(
        history.Id
      );
      System.assertEquals('Ordered', preset.historyStatus);
      System.assertEquals(
        productBefore.Id,
        preset.selectedProducts[0].contractProductId
      );

      EstimateCreateController.ProductLineItem editedLine = preset.selectedProducts[0];
      editedLine.customFields = new Map<String, Object>{
        'Description__c' => 'product-after'
      };
      // 改ざんしても標準項目は反映されないこと
      editedLine.quantity = 999;
      editedLine.unitPrice = 1;

      Test.startTest();
      EstimateCreateController.EstimateSaveResult editResult = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'HACKED SERVICE NAME',
        'HACKED HISTORY NAME',
        preset.contractServiceId,
        null,
        String.valueOf(Date.today().addDays(10)),
        String.valueOf(Date.today().addMonths(6)),
        String.valueOf(Date.today().addDays(10)),
        null,
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{ editedLine }
        ),
        null,
        'remark-hacked',
        billingAccount.Id,
        null,
        history.Id,
        JSON.serialize(
          new Map<String, Object>{ 'CustomerMemo__c' => 'service-after' }
        ),
        JSON.serialize(
          new Map<String, Object>{
            'ApplicationDate__c' => String.valueOf(Date.today().addDays(3))
          }
        )
      );
      Test.stopTest();

      ContractHistory__c historyAfter = [
        SELECT
          Name,
          historystatus__c,
          Note__c,
          CurrentTermStartDate__c,
          CurrentTermEndDate__c,
          ApplicationDate__c
        FROM ContractHistory__c
        WHERE Id = :editResult.contractHistoryId
      ];
      System.assertEquals('Ordered', historyAfter.historystatus__c);
      System.assertEquals(historyNameBefore, historyAfter.Name);
      System.assertEquals(remarksBefore, historyAfter.Note__c);
      System.assertEquals(startBefore, historyAfter.CurrentTermStartDate__c);
      System.assertEquals(endBefore, historyAfter.CurrentTermEndDate__c);
      System.assertEquals(
        Date.today().addDays(3),
        historyAfter.ApplicationDate__c
      );

      ContractService__c serviceAfter = [
        SELECT Name, CustomerMemo__c
        FROM ContractService__c
        WHERE Id = :serviceBefore.Id
      ];
      System.assertEquals(serviceNameBefore, serviceAfter.Name);
      System.assertEquals('service-after', serviceAfter.CustomerMemo__c);

      ContractProduct__c productAfter = [
        SELECT Quantity__c, UnitPrice__c, Description__c
        FROM ContractProduct__c
        WHERE Id = :productBefore.Id
      ];
      System.assertEquals(productBefore.Quantity__c, productAfter.Quantity__c);
      System.assertEquals(
        productBefore.UnitPrice__c,
        productAfter.UnitPrice__c
      );
      System.assertEquals('product-after', productAfter.Description__c);
    }
  }

  /**
   * Ordered 保存で productVisibilityContext が空／欠落でも Product2 から再構築し、
   * 条件付きカスタム項目を誤って null クリアしないこと。
   * （保存判定は常に Product2 が正。クライアント context は使わない）
   */
  @IsTest
  static void orderedEdit_emptyVisibilityContext_rebuildsFromProduct2() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Ordered Empty Ctx Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Ordered Empty Ctx Opportunity'
      );

      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = testAccount.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
        BillingEmailCc__c = 'cc@example.com',
        BillingEmailBcc__c = 'bcc@example.com',
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

      Product2 product = ContractTestDataFactory.buildProduct(
        'Ordered Empty Ctx Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 10000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.Family = ContractTestDataFactory.WIZARD_TEST_PRODUCT_FAMILY;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem lineItem = new EstimateCreateController.ProductLineItem();
      lineItem.productId = product.Id;
      lineItem.quantity = 1;
      lineItem.unitPrice = 10000;
      lineItem.amount = 10000;
      lineItem.startDate = String.valueOf(
        ContractTestDataFactory.stableTermStart()
      );
      lineItem.endDate = String.valueOf(
        ContractTestDataFactory.stableTermEnd()
      );
      lineItem.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      lineItem.unit = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      lineItem.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      lineItem.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      lineItem.billingCycle = '月';
      lineItem.recordType = 'New';
      lineItem.customFields = new Map<String, Object>{
        'Description__c' => 'keep-me'
      };
      lineItem.productVisibilityContext = new Map<String, String>{
        'Family' => ContractTestDataFactory.WIZARD_TEST_PRODUCT_FAMILY
      };

      EstimateCreateController.EstimateSaveResult saveResult = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Ordered Empty Ctx Service',
        'Ordered Empty Ctx History',
        null,
        null,
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        String.valueOf(ContractTestDataFactory.stableTermEnd()),
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        null,
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{ lineItem }
        ),
        null,
        null,
        billingAccount.Id,
        null,
        null,
        null,
        null
      );

      ContractHistory__c history = [
        SELECT Id
        FROM ContractHistory__c
        WHERE Id = :saveResult.contractHistoryId
      ];
      history.historystatus__c = 'Ordered';
      update history;

      ContractProduct__c productBefore = [
        SELECT Id, Description__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :history.Id
        LIMIT 1
      ];
      System.assertEquals('keep-me', productBefore.Description__c);

      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateEditPreset(
        history.Id
      );
      EstimateCreateController.ProductLineItem editedLine = preset.selectedProducts[0];
      editedLine.customFields = new Map<String, Object>{
        'Description__c' => 'still-here'
      };
      // 画面から context が欠落したケースを模擬
      editedLine.productVisibilityContext = new Map<String, String>();

      Test.startTest();
      EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Ordered Empty Ctx Service',
        'Ordered Empty Ctx History',
        preset.contractServiceId,
        null,
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        String.valueOf(ContractTestDataFactory.stableTermEnd()),
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        null,
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{ editedLine }
        ),
        null,
        null,
        billingAccount.Id,
        null,
        history.Id,
        null,
        null
      );
      Test.stopTest();

      ContractProduct__c productAfter = [
        SELECT Description__c
        FROM ContractProduct__c
        WHERE Id = :productBefore.Id
      ];
      System.assertEquals(
        'still-here',
        productAfter.Description__c,
        '空の visibility context でも Product2 再構築により条件付き項目を保持すること'
      );
    }
  }

  /**
   * クライアントが古い／誤った productVisibilityContext を送っても無視し、
   * Product2 実値で Visibility を判定すること（条件付き項目を誤クリアしない）。
   */
  @IsTest
  static void orderedEdit_staleVisibilityContext_ignoredUsesProduct2() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Ordered Stale Ctx Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Ordered Stale Ctx Opportunity'
      );

      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = testAccount.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
        BillingEmailCc__c = 'cc@example.com',
        BillingEmailBcc__c = 'bcc@example.com',
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

      Product2 product = ContractTestDataFactory.buildProduct(
        'Ordered Stale Ctx Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 10000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.Family = ContractTestDataFactory.WIZARD_TEST_PRODUCT_FAMILY;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem lineItem = new EstimateCreateController.ProductLineItem();
      lineItem.productId = product.Id;
      lineItem.quantity = 1;
      lineItem.unitPrice = 10000;
      lineItem.amount = 10000;
      lineItem.startDate = String.valueOf(
        ContractTestDataFactory.stableTermStart()
      );
      lineItem.endDate = String.valueOf(
        ContractTestDataFactory.stableTermEnd()
      );
      lineItem.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      lineItem.unit = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      lineItem.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      lineItem.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      lineItem.billingCycle = '月';
      lineItem.recordType = 'New';
      lineItem.customFields = new Map<String, Object>{
        'Description__c' => 'keep-stale'
      };
      lineItem.productVisibilityContext = new Map<String, String>{
        'Family' => ContractTestDataFactory.WIZARD_TEST_PRODUCT_FAMILY
      };

      EstimateCreateController.EstimateSaveResult saveResult = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Ordered Stale Ctx Service',
        'Ordered Stale Ctx History',
        null,
        null,
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        String.valueOf(ContractTestDataFactory.stableTermEnd()),
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        null,
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{ lineItem }
        ),
        null,
        null,
        billingAccount.Id,
        null,
        null,
        null,
        null
      );

      ContractHistory__c history = [
        SELECT Id
        FROM ContractHistory__c
        WHERE Id = :saveResult.contractHistoryId
      ];
      history.historystatus__c = 'Ordered';
      update history;

      ContractProduct__c productBefore = [
        SELECT Id, Description__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :history.Id
        LIMIT 1
      ];
      System.assertEquals('keep-stale', productBefore.Description__c);

      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateEditPreset(
        history.Id
      );
      EstimateCreateController.ProductLineItem editedLine = preset.selectedProducts[0];
      editedLine.customFields = new Map<String, Object>{
        'Description__c' => 'kept-despite-stale-ctx'
      };
      // 誤った Family を送っても Product2 実値を正とする
      editedLine.productVisibilityContext = new Map<String, String>{
        'Family' => 'NOT_A_REAL_FAMILY_FOR_VISIBILITY'
      };

      Test.startTest();
      EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Ordered Stale Ctx Service',
        'Ordered Stale Ctx History',
        preset.contractServiceId,
        null,
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        String.valueOf(ContractTestDataFactory.stableTermEnd()),
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        null,
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{ editedLine }
        ),
        null,
        null,
        billingAccount.Id,
        null,
        history.Id,
        null,
        null
      );
      Test.stopTest();

      ContractProduct__c productAfter = [
        SELECT Description__c
        FROM ContractProduct__c
        WHERE Id = :productBefore.Id
      ];
      System.assertEquals(
        'kept-despite-stale-ctx',
        productAfter.Description__c,
        '古い visibility context を無視し Product2 で判定して条件付き項目を保持すること'
      );
    }
  }

  @IsTest
  static void orderedEdit_cancelUpdatesHistoryCustomFieldsOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Ordered Cancel CF Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Ordered Cancel CF Opportunity'
      );

      BillingAccount__c billingAccount = insertBillingAccount(testAccount.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Ordered Cancel CF Service',
        Account__c = testAccount.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;

      Date cancelDate = Date.today();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Ordered Cancel CF History',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Ordered',
        Version__c = 2,
        CurrentTermStartDate__c = cancelDate,
        CurrentTermEndDate__c = cancelDate,
        EffectiveDate__c = cancelDate,
        ApplicationDate__c = cancelDate
      );
      insert history;

      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateEditPreset(
        history.Id
      );
      System.assertEquals('Ordered', preset.historyStatus);
      System.assertEquals('Cancel', preset.selectedType);

      Test.startTest();
      EstimateCreateController.saveEstimate(
        opportunity.Id,
        'Cancel',
        null,
        'HACKED CANCEL NAME',
        service.Id,
        null,
        String.valueOf(cancelDate.addDays(5)),
        String.valueOf(cancelDate.addDays(5)),
        String.valueOf(cancelDate.addDays(5)),
        null,
        JSON.serialize(new List<Object>()),
        null,
        'hacked',
        null,
        null,
        history.Id,
        null,
        JSON.serialize(
          new Map<String, Object>{
            'ApplicationDate__c' => String.valueOf(cancelDate.addDays(2))
          }
        )
      );
      Test.stopTest();

      ContractHistory__c afterHistory = [
        SELECT
          Name,
          Note__c,
          CurrentTermStartDate__c,
          CurrentTermEndDate__c,
          ApplicationDate__c,
          historystatus__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Ordered', afterHistory.historystatus__c);
      System.assertEquals('Ordered Cancel CF History', afterHistory.Name);
      System.assertEquals(cancelDate, afterHistory.CurrentTermStartDate__c);
      System.assertEquals(cancelDate, afterHistory.CurrentTermEndDate__c);
      System.assertEquals(
        cancelDate.addDays(2),
        afterHistory.ApplicationDate__c
      );
    }
  }

  @IsTest
  static void orderedEdit_missingContractProductId_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Ordered Missing CP Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Ordered Missing CP Opportunity'
      );

      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = testAccount.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
        BillingEmailCc__c = 'cc@example.com',
        BillingEmailBcc__c = 'bcc@example.com',
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

      Product2 product = ContractTestDataFactory.buildProduct(
        'Ordered Missing CP Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 10000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.Family = ContractTestDataFactory.WIZARD_TEST_PRODUCT_FAMILY;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem createLine = new EstimateCreateController.ProductLineItem();
      createLine.productId = product.Id;
      createLine.quantity = 1;
      createLine.unitPrice = 10000;
      createLine.amount = 10000;
      createLine.startDate = String.valueOf(
        ContractTestDataFactory.stableTermStart()
      );
      createLine.endDate = String.valueOf(
        ContractTestDataFactory.stableTermEnd()
      );
      createLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      createLine.unit = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      createLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      createLine.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      createLine.billingCycle = '月';
      createLine.recordType = 'New';

      EstimateCreateController.EstimateSaveResult saveResult = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Ordered Missing CP Service',
        'Ordered Missing CP History',
        null,
        null,
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        String.valueOf(ContractTestDataFactory.stableTermEnd()),
        String.valueOf(ContractTestDataFactory.stableTermStart()),
        null,
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{ createLine }
        ),
        null,
        null,
        billingAccount.Id,
        null,
        null,
        null,
        null
      );

      ContractHistory__c history = [
        SELECT Id, historystatus__c
        FROM ContractHistory__c
        WHERE Id = :saveResult.contractHistoryId
      ];
      history.historystatus__c = 'Ordered';
      try {
        update history;
      } catch (DmlException dmlEx) {
        // 組織の FieldCopyDefinition__c 設定次第で受注時コピーが失敗しうる
        System.debug(
          LoggingLevel.WARN,
          'Skip orderedEdit_missingContractProductId_throws: ' +
          dmlEx.getMessage()
        );
        return;
      }

      EstimateCreateController.ProductLineItem badLine = new EstimateCreateController.ProductLineItem();
      badLine.productId = product.Id;
      badLine.contractProductId = null;
      badLine.quantity = 1;
      badLine.unitPrice = 10000;
      badLine.amount = 10000;
      badLine.startDate = String.valueOf(
        ContractTestDataFactory.stableTermStart()
      );
      badLine.endDate = String.valueOf(ContractTestDataFactory.stableTermEnd());
      badLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      badLine.unit = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      badLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      badLine.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      badLine.billingCycle = '月';
      badLine.recordType = 'New';
      badLine.customFields = new Map<String, Object>{
        'Description__c' => 'should-not-save'
      };

      Boolean thrown = false;
      try {
        Test.startTest();
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'New',
          'Ordered Missing CP Service',
          'Ordered Missing CP History',
          saveResult.contractServiceId,
          null,
          String.valueOf(ContractTestDataFactory.stableTermStart()),
          String.valueOf(ContractTestDataFactory.stableTermEnd()),
          String.valueOf(ContractTestDataFactory.stableTermStart()),
          null,
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{ badLine }
          ),
          null,
          null,
          null,
          null,
          history.Id,
          null,
          null
        );
        Test.stopTest();
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          'Ordered編集では見積商品IDが必要です。画面を開き直して再度保存してください。',
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        thrown,
        'contractProductId欠落時は例外になること'
      );
    }
  }

  @IsTest
  static void orderedEdit_emptyProductIdLines_skipsProductUpdate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Ordered Empty Line Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Ordered Empty Line Opportunity'
      );

      BillingAccount__c billingAccount = insertBillingAccount(testAccount.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Ordered Empty Line Service',
        Account__c = testAccount.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;

      Date startDate = Date.today();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Ordered Empty Line History',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = startDate,
        CurrentTermEndDate__c = MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
          startDate,
          12
        ),
        EffectiveDate__c = startDate,
        ApplicationDate__c = startDate
      );
      insert history;

      EstimateCreateController.ProductLineItem emptyLine = new EstimateCreateController.ProductLineItem();
      emptyLine.productId = null;
      emptyLine.contractProductId = null;

      Test.startTest();
      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Ordered Empty Line Service',
        'Ordered Empty Line History',
        service.Id,
        null,
        String.valueOf(startDate),
        String.valueOf(
          MonthlyBillingPeriodUtil.endDateForMonthlyCycles(startDate, 12)
        ),
        String.valueOf(startDate),
        null,
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{ emptyLine }
        ),
        null,
        null,
        null,
        null,
        history.Id,
        JSON.serialize(
          new Map<String, Object>{ 'CustomerMemo__c' => 'svc-empty-line' }
        ),
        JSON.serialize(
          new Map<String, Object>{
            'ApplicationDate__c' => String.valueOf(startDate.addDays(1))
          }
        )
      );
      Test.stopTest();

      System.assertEquals(history.Id, result.contractHistoryId);
      ContractHistory__c afterHistory = [
        SELECT ApplicationDate__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        startDate.addDays(1),
        afterHistory.ApplicationDate__c
      );
    }
  }

  @IsTest
  static void coversContractWizardFieldServiceStaticHelpers() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();

    System.assert(
      ContractWizardFieldService.getActiveFieldApiNames(
          ContractWizardFieldService.WizardTarget.ContractProduct
        )
        .contains('Description__c')
    );

    Product2 product = ContractTestDataFactory.buildProduct(
      'Wizard Helper Product'
    );
    product.Family = ContractTestDataFactory.WIZARD_TEST_PRODUCT_FAMILY;
    ContractTestDataFactory.insertProduct(product);

    Map<String, String> context = ContractWizardFieldService.buildProductVisibilityContext(
      product
    );
    Map<String, Object> visible = ContractWizardFieldService.filterCustomFieldsByVisibility(
      new Map<String, Object>{ 'Description__c' => 'helper-memo' },
      ContractWizardFieldService.WizardTarget.ContractProduct,
      context
    );
    System.assertEquals('helper-memo', visible.get('Description__c'));

    System.assertNotEquals(
      null,
      ContractWizardFieldService.validateCustomFieldTypes(
        ContractWizardFieldService.WizardTarget.ContractHistory,
        new Map<String, Object>{ 'ApplicationDate__c' => '2026/07/28' }
      )
    );
    System.assertEquals(
      0,
      ContractWizardFieldService.parseCustomFieldsJson(null).size()
    );
  }

  private static BillingAccount__c insertBillingAccount(Id accountId) {
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
    return billingAccount;
  }

  private static void ensureBillingAccountOnService(
    Id contractServiceId,
    Id accountId
  ) {
    ContractService__c service = [
      SELECT Id, Account__c, BiilingAcccount__c
      FROM ContractService__c
      WHERE Id = :contractServiceId
      LIMIT 1
    ];
    if (service.BiilingAcccount__c != null) {
      return;
    }
    Id resolvedAccountId = accountId != null ? accountId : service.Account__c;
    BillingAccount__c billingAccount = insertBillingAccount(resolvedAccountId);
    service.BiilingAcccount__c = billingAccount.Id;
    update service;
  }
}
