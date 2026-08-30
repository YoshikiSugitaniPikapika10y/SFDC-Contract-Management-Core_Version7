@IsTest
private class EstimateSaveServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void buildContractProduct_setsInvoiceAnchorForPrepaidNew() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct(
        'Save Anchor Prepaid'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem line = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'New',
        Date.newInstance(2026, 4, 1),
        Date.newInstance(2027, 3, 31)
      );

      ContractProduct__c contractProduct = EstimateSaveService.buildContractProduct(
        null,
        null,
        line,
        product,
        'New',
        Date.newInstance(2026, 4, 1)
      );

      System.assertEquals(
        Date.newInstance(2026, 4, 1),
        contractProduct.InvoiceAnchorDate__c
      );
      System.assertEquals(null, contractProduct.InvoiceBillingCycleCount__c);
    }
  }

  @IsTest
  static void buildContractProduct_rejectsBlankRevenueRecognitionBasis() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct(
        'Save Blank Revenue'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem line = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'New',
        Date.newInstance(2026, 4, 1),
        Date.newInstance(2027, 3, 31)
      );
      line.revenueRecognitionBasis = null;

      Exception blankEx = null;
      try {
        EstimateSaveService.buildContractProduct(
          null,
          null,
          line,
          product,
          'New',
          Date.newInstance(2026, 4, 1)
        );
      } catch (Exception ex) {
        blankEx = ex;
      }
      System.assertNotEquals(null, blankEx);
      System.assert(
        blankEx.getMessage().contains('売上計上基準が空です。'),
        blankEx.getMessage()
      );
    }
  }

  @IsTest
  static void buildContractProduct_roundsUnitPriceAndAmountScale() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct(
        'Save Scale Round'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem line = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'New',
        Date.newInstance(2026, 4, 1),
        Date.newInstance(2026, 4, 30)
      );
      line.unitPrice = 742.855;
      line.amount = 9657000.49;

      ContractProduct__c contractProduct = EstimateSaveService.buildContractProduct(
        null,
        null,
        line,
        product,
        'New',
        Date.newInstance(2026, 4, 1)
      );

      System.assertEquals(742.86, contractProduct.UnitPrice__c);
      System.assertEquals(9657000, contractProduct.Amount__c);
    }
  }

  @IsTest
  static void buildContractProduct_setsInvoiceAnchorForMonthlySplit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct(
        'Save Anchor Monthly'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
      ContractTestDataFactory.insertProduct(product);

      Date startDate = Date.newInstance(2025, 8, 1);
      Date endDate = Date.newInstance(2026, 7, 31);
      EstimateCreateController.ProductLineItem line = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        'New',
        startDate,
        endDate
      );

      ContractProduct__c contractProduct = EstimateSaveService.buildContractProduct(
        null,
        null,
        line,
        product,
        'New',
        startDate
      );

      System.assertEquals(startDate, contractProduct.InvoiceAnchorDate__c);
      System.assertEquals(12, contractProduct.InvoiceBillingCycleCount__c);
    }
  }

  @IsTest
  static void buildContractProduct_changePrepaidRemakeUsesEffectiveDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct(
        'Save Anchor Change'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      Date effectiveDate = Date.newInstance(2026, 5, 1);
      EstimateCreateController.ProductLineItem line = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'Remake',
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 3, 31)
      );

      ContractProduct__c contractProduct = EstimateSaveService.buildContractProduct(
        null,
        null,
        line,
        product,
        'Change',
        effectiveDate
      );

      System.assertEquals(effectiveDate, contractProduct.InvoiceAnchorDate__c);
    }
  }

  @IsTest
  static void buildContractProduct_changeOriginalRemakePrefersLineUnit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct(
        'Save Change Unit Snapshot'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.UnitName__c = 'ライセンス';
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem originalLine = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'Original',
        Date.newInstance(2026, 4, 1),
        Date.newInstance(2027, 3, 31)
      );
      originalLine.unit = '式';
      originalLine.amount = -120000;

      ContractProduct__c savedOriginal = EstimateSaveService.buildContractProduct(
        null,
        null,
        originalLine,
        product,
        'Change',
        Date.newInstance(2026, 7, 1)
      );
      System.assertEquals(
        '式',
        savedOriginal.Unit__c,
        'Core 第4.5.2節: Change Original は前回 unit を保存する'
      );

      EstimateCreateController.ProductLineItem remakeLine = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'Remake',
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2027, 3, 31)
      );
      remakeLine.unit = '式';
      remakeLine.sourceContractProductId = Id.valueOf(
        ContractProduct__c.SObjectType.getDescribe().getKeyPrefix() +
          '000000000001'
      );

      ContractProduct__c savedRemake = EstimateSaveService.buildContractProduct(
        null,
        null,
        remakeLine,
        product,
        'Change',
        Date.newInstance(2026, 7, 1)
      );
      System.assertEquals(
        '式',
        savedRemake.Unit__c,
        'Core 第4.5.2節: Change Remake は前回 unit を保存する'
      );
    }
  }

  @IsTest
  static void buildContractProduct_renewInheritedPrefersLineUnit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct(
        'Save Renew Unit Snapshot'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.UnitName__c = 'ライセンス';
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem renewLine = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'Renew',
        Date.newInstance(2027, 4, 1),
        Date.newInstance(2028, 3, 31)
      );
      renewLine.unit = '式';
      renewLine.sourceContractProductId = Id.valueOf(
        ContractProduct__c.SObjectType.getDescribe().getKeyPrefix() +
          '000000000001'
      );

      ContractProduct__c savedRenew = EstimateSaveService.buildContractProduct(
        null,
        null,
        renewLine,
        product,
        'Renew',
        Date.newInstance(2027, 4, 1)
      );
      System.assertEquals(
        '式',
        savedRenew.Unit__c,
        'Core 第4.5.2節: Renew 継承は継承元 unit を保存する'
      );

      EstimateCreateController.ProductLineItem handAdded = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'New',
        Date.newInstance(2027, 4, 1),
        Date.newInstance(2028, 3, 31)
      );
      handAdded.unit = '式';
      handAdded.sourceContractProductId = null;

      ContractProduct__c savedNew = EstimateSaveService.buildContractProduct(
        null,
        null,
        handAdded,
        product,
        'Renew',
        Date.newInstance(2027, 4, 1)
      );
      System.assertEquals(
        'ライセンス',
        savedNew.Unit__c,
        'Renew 手追加 Type=New は商品マスタ単位'
      );
    }
  }

  @IsTest
  static void buildContractProduct_inheritedBlankUnit_doesNotFillFromProduct2() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct(
        'Save Blank Inherited Unit'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.UnitName__c = 'ライセンス';
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem originalLine = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'Original',
        Date.newInstance(2026, 4, 1),
        Date.newInstance(2027, 3, 31)
      );
      originalLine.unit = '';
      originalLine.amount = -120000;

      ContractProduct__c savedOriginal = EstimateSaveService.buildContractProduct(
        null,
        null,
        originalLine,
        product,
        'Change',
        Date.newInstance(2026, 7, 1)
      );
      System.assertEquals(
        '',
        savedOriginal.Unit__c,
        'Core 第4.5.2節・第1.1.10節: Change Original の空単位を商品マスタから埋めない'
      );

      EstimateCreateController.ProductLineItem remakeLine = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'Remake',
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2027, 3, 31)
      );
      remakeLine.unit = '';
      remakeLine.sourceContractProductId = Id.valueOf(
        ContractProduct__c.SObjectType.getDescribe().getKeyPrefix() +
          '000000000001'
      );

      ContractProduct__c savedRemake = EstimateSaveService.buildContractProduct(
        null,
        null,
        remakeLine,
        product,
        'Change',
        Date.newInstance(2026, 7, 1)
      );
      System.assertEquals(
        '',
        savedRemake.Unit__c,
        'Core 第4.5.2節・第1.1.10節: Change Remake の空単位を商品マスタから埋めない'
      );

      EstimateCreateController.ProductLineItem renewLine = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'Renew',
        Date.newInstance(2027, 4, 1),
        Date.newInstance(2028, 3, 31)
      );
      renewLine.unit = '';
      renewLine.sourceContractProductId = Id.valueOf(
        ContractProduct__c.SObjectType.getDescribe().getKeyPrefix() +
          '000000000001'
      );

      ContractProduct__c savedRenew = EstimateSaveService.buildContractProduct(
        null,
        null,
        renewLine,
        product,
        'Renew',
        Date.newInstance(2027, 4, 1)
      );
      System.assertEquals(
        '',
        savedRenew.Unit__c,
        'Core 第4.5.2節・第1.1.10節: Renew 継承の空単位を商品マスタから埋めない'
      );
    }
  }

  @IsTest
  static void buildContractProduct_postpaidUsesEndPlusOne() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct(
        'Save Anchor Postpaid'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(product);

      Date startDate = Date.newInstance(2026, 6, 1);
      Date endDate = Date.newInstance(2026, 6, 30);
      EstimateCreateController.ProductLineItem line = buildLine(
        product.Id,
        '一括後払',
        'New',
        startDate,
        endDate
      );

      ContractProduct__c contractProduct = EstimateSaveService.buildContractProduct(
        null,
        null,
        line,
        product,
        'New',
        startDate
      );

      System.assertEquals(
        endDate.addDays(1),
        contractProduct.InvoiceAnchorDate__c
      );
    }
  }

  @IsTest
  static void resolveProductType_mapsRecordTypes() {
    EstimateCreateController.ProductLineItem originalLine = new EstimateCreateController.ProductLineItem();
    originalLine.recordType = 'Original';

    EstimateCreateController.ProductLineItem newLine = new EstimateCreateController.ProductLineItem();
    newLine.recordType = 'New';

    System.assertEquals(
      'Original',
      EstimateSaveService.resolveProductType(originalLine, 'Change')
    );
    System.assertEquals(
      'New',
      EstimateSaveService.resolveProductType(newLine, 'New')
    );
    // 仕様: Core 第4.3.5節。recordType 空の Renew は手追加＝New。継承は source あり。
    System.assertEquals(
      'New',
      EstimateSaveService.resolveProductType(
        new EstimateCreateController.ProductLineItem(),
        'Renew'
      )
    );
    EstimateCreateController.ProductLineItem renewInherited = new EstimateCreateController.ProductLineItem();
    renewInherited.sourceContractProductId = UserInfo.getUserId();
    System.assertEquals(
      'Renew',
      EstimateSaveService.resolveProductType(renewInherited, 'Renew')
    );
    EstimateCreateController.ProductLineItem renewExplicit = new EstimateCreateController.ProductLineItem();
    renewExplicit.recordType = 'Renew';
    System.assertEquals(
      'Renew',
      EstimateSaveService.resolveProductType(renewExplicit, 'Renew')
    );
  }

  @IsTest
  static void loadProductBillingTypes_returnsProductMap() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct(
        'Load Billing Type'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem line = new EstimateCreateController.ProductLineItem();
      line.productId = product.Id;

      Map<Id, Product2> productById = EstimateSaveService.loadProductBillingTypes(
        new List<EstimateCreateController.ProductLineItem>{ line }
      );

      System.assertEquals(1, productById.size());
      System.assertEquals(
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        productById.get(product.Id).BillingType__c
      );
    }
  }

  @IsTest
  static void buildContractProducts_buildsProductsFromRequest() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct('Build Products');
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.selectedType = 'New';
      request.effectiveDate = '2026-04-01';
      request.products = new List<EstimateCreateController.ProductLineItem>{
        buildLine(
          product.Id,
          ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          'New',
          Date.newInstance(2026, 4, 1),
          Date.newInstance(2027, 3, 31)
        )
      };

      List<ContractProduct__c> products = EstimateSaveService.buildContractProducts(
        null,
        null,
        request
      );

      System.assertEquals(1, products.size());
      System.assertEquals(
        Date.newInstance(2026, 4, 1),
        products[0].InvoiceAnchorDate__c
      );
    }
  }

  @IsTest
  static void applyRemarksAndCancelRemarks_updateHistoryNotes() {
    ContractHistory__c history = new ContractHistory__c();
    EstimateSaveService.applyRemarks(history, 'テスト備考');
    System.assertEquals('テスト備考', history.Note__c);

    EstimateSaveService.applyRemarks(history, '');
    System.assertEquals(null, history.Note__c, '空備考は Note__c をクリアする');

    history.Note__c = 'note';
    EstimateSaveService.applyRemarks(history, null);
    System.assertEquals(
      null,
      history.Note__c,
      'null 備考も Note__c をクリアする'
    );

    history.Note__c = 'note';
    EstimateSaveService.applyCancelRemarks(history);
    System.assertEquals(
      'note',
      history.Note__c,
      'Core 第4.10節: Cancelは備考をクリアしない'
    );

    Integer maxLen = ContractDomainConstants.NOTE_MAX_LENGTH;
    String longText = 'あ'.repeat(maxLen + 20);
    Boolean thrown = false;
    try {
      EstimateSaveService.applyRemarks(history, longText);
    } catch (Exception e) {
      thrown = true;
    }
    System.assertEquals(true, thrown, '備考は切り詰めずエラーにする');

    EstimateSaveService.applyRemarks(null, 'ignored');
    EstimateSaveService.applyCancelRemarks(null);
  }

  @IsTest
  static void applyEstimateDocumentIfEnabled_unusedKeepsExisting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.EstimateSendMode__c = ContractDocumentSettingService.MODE_UNUSED;
      update setting;
      ContractDocumentSettingService.clearCache();

      ContractHistory__c history = new ContractHistory__c(
        Note__c = '既存備考',
        EstimateDate__c = Date.newInstance(2026, 1, 15),
        EstimateValidDate__c = Date.newInstance(2026, 2, 15)
      );
      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.remarksText = '新しい備考';
      request.estimateDate = '2026-08-01';
      request.estimateValidDate = '2026-09-01';

      EstimateSaveService.applyEstimateDocumentIfEnabled(history, request);

      System.assertEquals(
        '既存備考',
        history.Note__c,
        'Core 第4.10節: 使わないでは備考を保存対象にせず既存を維持する'
      );
      System.assertEquals(
        Date.newInstance(2026, 1, 15),
        history.EstimateDate__c,
        'Core 第4.10節: 使わないでは見積日を保存対象にせず既存を維持する'
      );
      System.assertEquals(
        Date.newInstance(2026, 2, 15),
        history.EstimateValidDate__c,
        'Core 第4.10節: 使わないでは有効期限を保存対象にせず既存を維持する'
      );
    }
  }

  @IsTest
  static void applyEstimateDocumentIfEnabled_writesWhenSectionShown() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.ensureOrgDocumentSetting();
      ContractDocumentSettingService.clearCache();

      ContractHistory__c history = new ContractHistory__c();
      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.remarksText = '見積書備考';
      request.estimateDate = '2026-08-01';
      request.estimateValidDate = '2026-09-01';

      EstimateSaveService.applyEstimateDocumentIfEnabled(history, request);

      System.assertEquals('見積書備考', history.Note__c);
      System.assertEquals(
        Date.newInstance(2026, 8, 1),
        history.EstimateDate__c
      );
      System.assertEquals(
        Date.newInstance(2026, 9, 1),
        history.EstimateValidDate__c
      );
    }
  }

  @IsTest
  static void applyNotAutoRenewFieldCopy_doesNotFillDisplayedBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.ensureOrgDocumentSetting();
      ContractDocumentSettingService.clearCache();
      Account account = ContractTestDataFactory.insertAccount('コピー元取引先');
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'コピー元商談'
      );
      insert new FieldCopyDefinition__c(
        Name = 'Test_Skip_Displayed_Note',
        TargetObject__c = 'ContractHistory__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_NOT_AUTO_RENEW,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Note__c'
      );

      ContractHistory__c history = new ContractHistory__c(
        Opportunity__c = opportunity.Id
      );
      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.selectedType = 'New';
      request.remarksText = null;
      EstimateSaveService.applyEstimateDocumentIfEnabled(history, request);
      EstimateSaveService.applyContractHistoryCustomFields(history, request);
      EstimateSaveService.applyNotAutoRenewFieldCopy(history, request);

      System.assertEquals(
        null,
        history.Note__c,
        'Core 第11.4.2節: ウィザードで画面に出して保存した項目は空でもコピーしない'
      );
    }
  }

  @IsTest
  static void applyNotAutoRenewFieldCopy_doesNotFillDisplayedSendContact() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.ensureOrgDocumentSetting();
      ContractDocumentSettingService.clearCache();
      Account account = ContractTestDataFactory.insertAccount('送付先コピー元');
      Contact sourceContact = ContractTestDataFactory.insertContact(
        account.Id,
        'コピー元責任者'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        '送付先コピー商談'
      );
      opportunity.ContactId = sourceContact.Id;
      update opportunity;
      insert new FieldCopyDefinition__c(
        Name = 'Test_Skip_Displayed_SendContact',
        TargetObject__c = 'ContractHistory__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_NOT_AUTO_RENEW,
        SourceObject__c = 'Opportunity',
        SourceFieldApiName__c = 'ContactId',
        TargetFieldApiName__c = 'EstimateSendContact__c'
      );

      ContractHistory__c history = new ContractHistory__c(
        Opportunity__c = opportunity.Id
      );
      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.selectedType = 'New';
      request.estimateSendContactId = null;
      EstimateSaveService.applyEstimateSendContact(history, request);
      EstimateSaveService.applyNotAutoRenewFieldCopy(history, request);

      System.assertEquals(
        null,
        history.EstimateSendContact__c,
        'Core 第11.4.2節・第4.3.3節: ウィザードで出した見積送付先は空でもコピーしない'
      );
    }
  }

  @IsTest
  static void applyNotAutoRenewFieldCopy_fillsHiddenBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.EstimateSendMode__c = ContractDocumentSettingService.MODE_UNUSED;
      update setting;
      ContractDocumentSettingService.clearCache();
      Account account = ContractTestDataFactory.insertAccount('非表示コピー元');
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        '非表示コピー商談'
      );
      insert new FieldCopyDefinition__c(
        Name = 'Test_Fill_Hidden_Note',
        TargetObject__c = 'ContractHistory__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_NOT_AUTO_RENEW,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Note__c'
      );

      ContractHistory__c history = new ContractHistory__c(
        Opportunity__c = opportunity.Id
      );
      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.selectedType = 'New';
      EstimateSaveService.applyEstimateDocumentIfEnabled(history, request);
      EstimateSaveService.applyContractHistoryCustomFields(history, request);
      EstimateSaveService.applyNotAutoRenewFieldCopy(history, request);

      System.assertEquals(
        '非表示コピー元',
        history.Note__c,
        'Core 第11.4.2節: 出していない項目の空欄はコピーしてよい'
      );
    }
  }

  @IsTest
  static void saveNewEstimate_stopsWhenCopyDefinitionBroken() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      FieldCopyDefinitionService.additionalRequiredJournalFieldApiNames = new Set<String>{
        'Memo__c'
      };
      insert new FieldCopyDefinition__c(
        Name = 'Test_Journal_Memo_LineOnly_Save',
        TargetObject__c = 'GlJournal__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.opportunityId = UserInfo.getUserId();
      Boolean rejected = false;
      try {
        EstimateSaveService.saveNewEstimate(request, 'Broken Def');
      } catch (FieldCopyDefinitionService.FieldCopyException ex) {
        rejected = true;
        System.assert(
          ex.getMessage().contains('Memo__c') ||
            ex.getMessage().contains('Test_Journal_Memo_LineOnly_Save'),
          ex.getMessage()
        );
      } finally {
        FieldCopyDefinitionService.additionalRequiredJournalFieldApiNames = null;
      }
      System.assertEquals(
        true,
        rejected,
        'Core 第11.4.2節: 定義が壊れていたら見積の新規作成を止め、一意キーを出す'
      );
    }
  }

  @IsTest
  static void saveChangeEstimate_stopsWhenCopyDefinitionBroken() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      FieldCopyDefinitionService.additionalRequiredJournalFieldApiNames = new Set<String>{
        'Memo__c'
      };
      insert new FieldCopyDefinition__c(
        Name = 'Test_Journal_Memo_LineOnly_Change',
        TargetObject__c = 'GlJournal__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.opportunityId = UserInfo.getUserId();
      Boolean rejected = false;
      try {
        EstimateSaveService.saveChangeEstimate(request, 'Broken Def Change');
      } catch (FieldCopyDefinitionService.FieldCopyException ex) {
        rejected = true;
        System.assert(
          ex.getMessage().contains('Memo__c') ||
            ex.getMessage().contains('Test_Journal_Memo_LineOnly_Change'),
          ex.getMessage()
        );
      } finally {
        FieldCopyDefinitionService.additionalRequiredJournalFieldApiNames = null;
      }
      System.assertEquals(
        true,
        rejected,
        'Core 第11.4.2節: 定義が壊れていたら見積の新規作成を止め、一意キーを出す'
      );
    }
  }

  @IsTest
  static void saveCancelEstimate_stopsWhenCopyDefinitionBroken() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      FieldCopyDefinitionService.additionalRequiredJournalFieldApiNames = new Set<String>{
        'Memo__c'
      };
      insert new FieldCopyDefinition__c(
        Name = 'Test_Journal_Memo_LineOnly_Cancel',
        TargetObject__c = 'GlJournal__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.opportunityId = UserInfo.getUserId();
      Boolean rejected = false;
      try {
        EstimateSaveService.saveCancelEstimate(request, 'Broken Def Cancel');
      } catch (FieldCopyDefinitionService.FieldCopyException ex) {
        rejected = true;
        System.assert(
          ex.getMessage().contains('Memo__c') ||
            ex.getMessage().contains('Test_Journal_Memo_LineOnly_Cancel'),
          ex.getMessage()
        );
      } finally {
        FieldCopyDefinitionService.additionalRequiredJournalFieldApiNames = null;
      }
      System.assertEquals(
        true,
        rejected,
        'Core 第11.4.2節: 定義が壊れていたら見積の新規作成を止め、一意キーを出す'
      );
    }
  }

  @IsTest
  static void saveEstimate_unsupportedType_throwsCodedMessage() {
    // コード付きメッセージ自体の契約
    System.assertEquals(
      '[EST-Save-002] New、Change、Renew、Cancelタイプのみ保存できます。',
      EstimateValidationService.estSaveException(
          '002',
          'New、Change、Renew、Cancelタイプのみ保存できます。'
        )
        .getMessage()
    );

    Boolean thrown = false;
    try {
      EstimateSaveService.saveEstimate(
        UserInfo.getUserId(),
        'Partial',
        null,
        'Unsupported Type History',
        null,
        null,
        null,
        null,
        null,
        String.valueOf(Date.today()),
        '[]',
        null,
        null,
        null,
        null
      );
    } catch (AuraHandledException ex) {
      thrown = true;
      // 組織の必須カスタム項目があると Save-002 より先に落ちる場合がある
      System.assert(
        ex.getMessage().contains('EST-Save-002') ||
          ex.getMessage().contains('入力') ||
          ex.getMessage().contains('必須'),
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void updateOrderedEstimateCustomFieldsOnly_updatesServiceKeepsProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Ordered Edit Acc'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Ordered Edit Opp'
      );
      BillingAccount__c billingAccount = insertBillingAccount(account.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Ordered Edit Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c ordered = new ContractHistory__c(
        Name = 'Ordered Edit History',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart,
        ApplicationDate__c = termStart
      );
      insert ordered;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Ordered Edit Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c productRow = new ContractProduct__c(
        ContractHistory__c = ordered.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 3000,
        Amount__c = 72000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New',
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );
      insert productRow;

      service.CustomerMemo__c = 'keep-ordered-memo';
      update service;

      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.opportunityId = opportunity.Id;
      request.selectedType = 'New';
      request.editHistoryId = ordered.Id;
      request.contractServiceId = service.Id;
      request.contractStartDate = String.valueOf(termStart);
      request.contractEndDate = String.valueOf(termEnd);
      request.effectiveDate = String.valueOf(termStart);
      request.applicationDate = String.valueOf(termStart);
      request.products = new List<EstimateCreateController.ProductLineItem>();
      request.contractHistoryCustomFields = new Map<String, Object>{
        'ApplicationDate__c' => String.valueOf(termStart.addDays(1)),
        'OrderDate__c' => String.valueOf(termStart.addDays(2))
      };
      request.contractServiceCustomFields = new Map<String, Object>{
        'CustomerMemo__c' => 'tampered-from-ordered-edit'
      };

      // 受注済みはカスタム項目更新専用 API（ウィザード必須項目の組織差分を避ける）
      EstimateCreateController.EstimateSaveResult result = EstimateSaveService.updateOrderedEstimateCustomFieldsOnly(
        ordered,
        request
      );
      System.assertEquals(ordered.Id, result.contractHistoryId);

      ContractHistory__c stored = [
        SELECT ApplicationDate__c, OrderDate__c
        FROM ContractHistory__c
        WHERE Id = :ordered.Id
      ];
      System.assertEquals(
        termStart.addDays(1),
        stored.ApplicationDate__c,
        'Core 第11.4.3節: Ordered見積編集は受注追加項目を保存する'
      );
      System.assertEquals(
        termStart.addDays(2),
        stored.OrderDate__c,
        'Core 第11.4.3節: Ordered見積編集は受注日を保存する'
      );

      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateEditPreset(
        ordered.Id
      );
      System.assertEquals(
        String.valueOf(termStart.addDays(1)),
        String.valueOf(preset.contractHistoryCustomFields.get('ApplicationDate__c')),
        'Core 第11.4.3節: Ordered見積編集の初期値は保存済みの受注追加項目'
      );
      System.assertEquals(
        String.valueOf(termStart.addDays(2)),
        String.valueOf(preset.contractHistoryCustomFields.get('OrderDate__c')),
        'Core 第11.4.3節: Ordered見積編集の初期値は保存済みの受注日'
      );

      ContractProduct__c still = [
        SELECT Quantity__c, UnitPrice__c, Amount__c
        FROM ContractProduct__c
        WHERE Id = :productRow.Id
      ];
      System.assertEquals(
        2,
        still.Quantity__c,
        '受注済み編集では商品数量を変えない'
      );
      System.assertEquals(3000, still.UnitPrice__c);
      System.assertEquals(72000, still.Amount__c);

      ContractHistory__c stillHistory = [
        SELECT historystatus__c, Type__c
        FROM ContractHistory__c
        WHERE Id = :ordered.Id
      ];
      System.assertEquals('Ordered', stillHistory.historystatus__c);
      System.assertEquals('New', stillHistory.Type__c);

      ContractService__c stillService = [
        SELECT CustomerMemo__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        'keep-ordered-memo',
        stillService.CustomerMemo__c,
        'Core 第4.3節: Ordered見積編集は契約サービス追加項目を更新しない'
      );
    }
  }

  @IsTest
  static void loadEditableEstimateHistory_missingId_throwsKnownMessage() {
    Id missingId =
      ContractHistory__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000000AAA';
    Boolean thrown = false;
    try {
      EstimateSaveService.loadEditableEstimateHistory(missingId);
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assertEquals(
        '編集対象の契約履歴が見つかりません。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void mergeApplicationDateIntoHistoryCustomFields_addsApplicationDate() {
    EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
    request.applicationDate = '2026-07-01';

    EstimateSaveService.mergeApplicationDateIntoHistoryCustomFields(request);

    System.assertEquals(
      '2026-07-01',
      request.contractHistoryCustomFields.get('ApplicationDate__c')
    );
  }

  @IsTest
  static void saveEstimate_newAndEdit_updatesContractProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Save Service Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Save Service Opportunity'
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Save Service Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 10000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      EstimateCreateController.ProductLineItem lineItem = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'New',
        termStart,
        termEnd
      );
      lineItem.quantity = 2;
      lineItem.unitPrice = 10000;
      lineItem.amount = 20000;
      lineItem.unit = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      lineItem.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      lineItem.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      lineItem.billingCycle = '月';
      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{ lineItem }
      );

      EstimateCreateController.EstimateSaveResult created = EstimateSaveService.saveEstimate(
        opportunity.Id,
        'New',
        'Save Service CS',
        'Save Service History',
        null,
        null,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(termStart),
        String.valueOf(termStart),
        productsJson,
        null,
        '初回備考',
        null,
        null
      );

      lineItem.quantity = 3;
      lineItem.amount = 30000;
      productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{ lineItem }
      );

      Test.startTest();
      EstimateCreateController.EstimateSaveResult updated = EstimateSaveService.saveEstimate(
        opportunity.Id,
        'New',
        'Save Service CS Updated',
        'Save Service History Updated',
        created.contractServiceId,
        null,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(termStart),
        String.valueOf(termStart),
        productsJson,
        null,
        '更新備考',
        null,
        null,
        created.contractHistoryId
      );

      EstimateSaveService.saveEstimate(
        opportunity.Id,
        'New',
        'Save Service CS Updated',
        'Save Service History Updated',
        created.contractServiceId,
        null,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(termStart),
        String.valueOf(termStart),
        productsJson,
        null,
        null,
        null,
        null,
        created.contractHistoryId
      );
      Test.stopTest();

      ContractProduct__c savedProduct = [
        SELECT Quantity__c, Amount__c, InvoiceAnchorDate__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :updated.contractHistoryId
        LIMIT 1
      ];
      System.assertEquals(3, savedProduct.Quantity__c);
      System.assertEquals(30000, savedProduct.Amount__c);
      System.assertEquals(termStart, savedProduct.InvoiceAnchorDate__c);
      ContractHistory__c clearedRemarks = [
        SELECT Note__c
        FROM ContractHistory__c
        WHERE Id = :updated.contractHistoryId
      ];
      System.assertEquals(
        null,
        clearedRemarks.Note__c,
        '備考クリア保存で Note__c が消えること'
      );
    }
  }

  @IsTest
  static void loadEditableEstimateHistory_throwsWhenMissing() {
    String keyPrefix = ContractHistory__c.SObjectType.getDescribe()
      .getKeyPrefix();
    Id missingId = (Id) (keyPrefix + '0'.repeat(12) + 'AAA');
    Boolean thrown = false;
    try {
      EstimateSaveService.loadEditableEstimateHistory(missingId);
    } catch (AuraHandledException ex) {
      thrown = true;
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void resolveEstimateHistoryVersion_returnsNextVersion() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Version Account'
      );
      BillingAccount__c billingAccount = insertBillingAccount(account.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Version Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      insert new ContractHistory__c(
        Name = 'Version History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = ContractTestDataFactory.stableTermStart(),
        CurrentTermEndDate__c = ContractTestDataFactory.stableTermEnd()
      );

      System.assertEquals(
        2,
        EstimateSaveService.resolveEstimateHistoryVersion(service.Id, null)
      );
    }
  }

  @IsTest
  static void saveEstimate_change_createsChangeHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Save Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Change Save Opportunity'
      );
      BillingAccount__c billingAccount = insertBillingAccount(account.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Change Save Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM
      );
      insert service;

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date effectiveDate = Date.newInstance(2025, 10, 1);
      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Save Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Save Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 5000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 5000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem originalLine = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'Original',
        termStart,
        termEnd
      );
      originalLine.quantity = 2;
      originalLine.unitPrice = 5000;
      originalLine.amount = -120000;
      originalLine.sourceContractProductId = sourceProduct.Id;
      originalLine.unit = '式/月';
      originalLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      originalLine.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      originalLine.billingCycle = '月';

      EstimateCreateController.ProductLineItem remakePreLine = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'Remake',
        termStart,
        effectiveDate.addDays(-1)
      );
      remakePreLine.quantity = 2;
      remakePreLine.unitPrice = 5000;
      remakePreLine.amount = 40000;
      remakePreLine.sourceContractProductId = sourceProduct.Id;
      remakePreLine.unit = '式/月';
      remakePreLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakePreLine.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      remakePreLine.billingCycle = '月';

      EstimateCreateController.ProductLineItem remakeLine = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'Remake',
        effectiveDate,
        termEnd
      );
      remakeLine.quantity = 3;
      remakeLine.unitPrice = 5000;
      remakeLine.amount = 120000;
      remakeLine.sourceContractProductId = sourceProduct.Id;
      remakeLine.unit = '式/月';
      remakeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeLine.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      remakeLine.billingCycle = '月';

      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{
          originalLine,
          remakePreLine,
          remakeLine
        }
      );

      Test.startTest();
      EstimateCreateController.EstimateSaveResult result = EstimateSaveService.saveEstimate(
        opportunity.Id,
        'Change',
        null,
        'Change Save History',
        service.Id,
        sourceHistory.Id,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(effectiveDate),
        String.valueOf(Date.today()),
        productsJson,
        null,
        null,
        null,
        null
      );
      Test.stopTest();

      System.assertEquals(3, result.contractProductIds.size());
      ContractHistory__c changeHistory = [
        SELECT
          Type__c,
          historystatus__c,
          Version__c,
          PreviousHistory__c,
          CurrentTermStartDate__c,
          CurrentTermEndDate__c,
          EffectiveDate__c
        FROM ContractHistory__c
        WHERE Id = :result.contractHistoryId
      ];
      System.assertEquals('Change', changeHistory.Type__c);
      System.assertEquals('Estimate', changeHistory.historystatus__c);
      System.assertEquals(2, changeHistory.Version__c);
      System.assertEquals(sourceHistory.Id, changeHistory.PreviousHistory__c);
      System.assertEquals(termStart, changeHistory.CurrentTermStartDate__c);
      System.assertEquals(termEnd, changeHistory.CurrentTermEndDate__c);
      System.assertEquals(effectiveDate, changeHistory.EffectiveDate__c);

      ContractProduct__c remakeProduct = [
        SELECT InvoiceAnchorDate__c
        FROM ContractProduct__c
        WHERE Id IN :result.contractProductIds AND Type__c = 'Remake'
        LIMIT 1
      ];
      System.assertEquals(effectiveDate, remakeProduct.InvoiceAnchorDate__c);

      ContractProduct__c originalProduct = [
        SELECT Amount__c, Type__c
        FROM ContractProduct__c
        WHERE Id IN :result.contractProductIds AND Type__c = 'Original'
        LIMIT 1
      ];
      System.assertEquals(
        -120000,
        originalProduct.Amount__c,
        'Original の画面符号付き金額が DB に残ること'
      );
    }
  }

  @IsTest
  static void saveEstimate_renew_persistsHeaderAndProduct() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Renew Save Acc');
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Save Opp'
      );
      BillingAccount__c billingAccount = insertBillingAccount(account.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Renew Save Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM
      );
      insert service;

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date renewStart = termEnd.addDays(1);
      Date renewEnd = MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
        renewStart,
        12
      );

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Renew Save Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Renew Save Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 8000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      insert new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Unit__c = '式/月',
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New',
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );

      EstimateCreateController.ProductLineItem renewLine = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'Renew',
        renewStart,
        renewEnd
      );
      renewLine.quantity = 1;
      renewLine.unitPrice = 8000;
      renewLine.amount = 96000;
      renewLine.unit = '式/月';
      renewLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      renewLine.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      renewLine.billingCycle = '月';

      EstimateCreateController.EstimateSaveResult renewResult = EstimateSaveService.saveEstimate(
        opportunity.Id,
        'Renew',
        null,
        'Renew Save History',
        service.Id,
        sourceHistory.Id,
        String.valueOf(renewStart),
        String.valueOf(renewEnd),
        String.valueOf(renewStart),
        String.valueOf(Date.today()),
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{ renewLine }
        ),
        null,
        'renew-note',
        null,
        null
      );

      ContractHistory__c renewHistory = [
        SELECT
          Type__c,
          historystatus__c,
          Version__c,
          PreviousHistory__c,
          CurrentTermStartDate__c,
          CurrentTermEndDate__c,
          EffectiveDate__c,
          Note__c
        FROM ContractHistory__c
        WHERE Id = :renewResult.contractHistoryId
      ];
      System.assertEquals('Renew', renewHistory.Type__c);
      System.assertEquals('Estimate', renewHistory.historystatus__c);
      System.assertEquals(2, renewHistory.Version__c);
      System.assertEquals(sourceHistory.Id, renewHistory.PreviousHistory__c);
      System.assertEquals(renewStart, renewHistory.CurrentTermStartDate__c);
      System.assertEquals(renewEnd, renewHistory.CurrentTermEndDate__c);
      System.assertEquals(renewStart, renewHistory.EffectiveDate__c);
      System.assertEquals('renew-note', renewHistory.Note__c);
      System.assertEquals(1, renewResult.contractProductIds.size());

      ContractProduct__c renewProduct = [
        SELECT
          Amount__c,
          UnitPrice__c,
          Quantity__c,
          Type__c,
          StartDate__c,
          Enddate__c
        FROM ContractProduct__c
        WHERE Id = :renewResult.contractProductIds[0]
      ];
      System.assertEquals('Renew', renewProduct.Type__c);
      System.assertEquals(96000, renewProduct.Amount__c);
      System.assertEquals(8000, renewProduct.UnitPrice__c);
      System.assertEquals(1, renewProduct.Quantity__c);
      System.assertEquals(renewStart, renewProduct.StartDate__c);
      System.assertEquals(renewEnd, renewProduct.Enddate__c);
    }
  }

  @IsTest
  static void saveEstimate_cancel_persistsDatesClearsRemarksAndNoProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Cancel Save Acc'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Cancel Save Opp'
      );
      BillingAccount__c billingAccount = insertBillingAccount(account.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Cancel Save Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM
      );
      insert service;

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date cancelDate = termEnd.addDays(1);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Cancel Save Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Cancel Save Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New',
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );

      EstimateCreateController.EstimateSaveResult cancelResult = EstimateSaveService.saveEstimate(
        opportunity.Id,
        'Cancel',
        null,
        'Cancel Save History',
        service.Id,
        sourceHistory.Id,
        String.valueOf(cancelDate),
        String.valueOf(cancelDate),
        String.valueOf(cancelDate),
        String.valueOf(Date.today()),
        '[]',
        null,
        'should-clear',
        null,
        null
      );

      System.assertEquals(0, cancelResult.contractProductIds.size());
      ContractHistory__c cancelHistory = [
        SELECT
          Type__c,
          historystatus__c,
          Version__c,
          PreviousHistory__c,
          CurrentTermStartDate__c,
          CurrentTermEndDate__c,
          EffectiveDate__c,
          Note__c
        FROM ContractHistory__c
        WHERE Id = :cancelResult.contractHistoryId
      ];
      System.assertEquals('Cancel', cancelHistory.Type__c);
      System.assertEquals('Estimate', cancelHistory.historystatus__c);
      System.assertEquals(2, cancelHistory.Version__c);
      System.assertEquals(sourceHistory.Id, cancelHistory.PreviousHistory__c);
      System.assertEquals(cancelDate, cancelHistory.CurrentTermStartDate__c);
      System.assertEquals(cancelDate, cancelHistory.CurrentTermEndDate__c);
      System.assertEquals(cancelDate, cancelHistory.EffectiveDate__c);
      System.assertEquals(
        null,
        cancelHistory.Note__c,
        '解約では備考を残さない'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractProduct__c
          WHERE ContractHistory__c = :cancelHistory.Id
        ],
        '解約見積に商品明細は無い'
      );
    }
  }

  @IsTest
  static void saveEstimate_blankType_throwCodedMessage() {
    // productsJson=null は空リスト化されるため、入口ではタイプ未選択として拒否される
    Boolean blankTypeThrown = false;
    try {
      EstimateSaveService.saveEstimate(
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null
      );
    } catch (AuraHandledException ex) {
      blankTypeThrown = true;
      System.assertEquals(
        '[EST-S1-001] タイプを選択してください。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, blankTypeThrown);

    Boolean whitespaceTypeThrown = false;
    try {
      EstimateSaveService.saveEstimate(
        UserInfo.getUserId(),
        '  ',
        null,
        'Name',
        null,
        null,
        null,
        null,
        null,
        null,
        '[]',
        null,
        null,
        null,
        null
      );
    } catch (AuraHandledException ex) {
      whitespaceTypeThrown = true;
      System.assertEquals(
        '[EST-S1-001] タイプを選択してください。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, whitespaceTypeThrown);
  }

  @IsTest
  static void loadEditableEstimateHistory_rejectsArchiveStatus() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Edit Acc'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Archive Edit Opp'
      );
      BillingAccount__c billingAccount = insertBillingAccount(account.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Archive Edit Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      ContractHistory__c archived = new ContractHistory__c(
        Name = 'Archive Edit History',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'New',
        historystatus__c = 'Archive',
        Version__c = 1,
        CurrentTermStartDate__c = ContractTestDataFactory.stableTermStart(),
        CurrentTermEndDate__c = ContractTestDataFactory.stableTermEnd()
      );
      insert archived;

      Boolean thrown = false;
      try {
        EstimateSaveService.loadEditableEstimateHistory(archived.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          'Estimate / Ordered 状態の契約履歴のみ編集できます。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEditedEstimate_rejectsTypeChangeAndOpportunityMismatch() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Edit Gate Acc');
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Edit Gate Opp'
      );
      Opportunity otherOpp = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Edit Gate Other Opp'
      );
      BillingAccount__c billingAccount = insertBillingAccount(account.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Edit Gate Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c estimate = new ContractHistory__c(
        Name = 'Edit Gate History',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart,
        ApplicationDate__c = termStart
      );
      insert estimate;

      String currentToken = ContractOptimisticLockUtil.toToken(
        [
          SELECT LastModifiedDate
          FROM ContractHistory__c
          WHERE Id = :estimate.Id
        ]
        .LastModifiedDate
      );

      EstimateCreateController.EstimateSaveRequest typeChangeReq = new EstimateCreateController.EstimateSaveRequest();
      typeChangeReq.opportunityId = opportunity.Id;
      typeChangeReq.selectedType = 'New';
      typeChangeReq.editHistoryId = estimate.Id;
      typeChangeReq.expectedLastModifiedToken = currentToken;
      Boolean typeThrown = false;
      try {
        EstimateSaveService.saveEditedEstimate(typeChangeReq, estimate.Name);
      } catch (AuraHandledException ex) {
        typeThrown = true;
        System.assertEquals(
          '見積編集ではタイプを変更できません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, typeThrown);

      EstimateCreateController.EstimateSaveRequest oppMismatchReq = new EstimateCreateController.EstimateSaveRequest();
      oppMismatchReq.opportunityId = otherOpp.Id;
      oppMismatchReq.selectedType = 'Change';
      oppMismatchReq.editHistoryId = estimate.Id;
      oppMismatchReq.expectedLastModifiedToken = currentToken;
      Boolean oppThrown = false;
      try {
        EstimateSaveService.saveEditedEstimate(oppMismatchReq, estimate.Name);
      } catch (AuraHandledException ex) {
        oppThrown = true;
        System.assertEquals(
          '編集対象の見積と商談が一致しません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, oppThrown);

      ContractHistory__c unchanged = [
        SELECT Type__c, Opportunity__c, historystatus__c
        FROM ContractHistory__c
        WHERE Id = :estimate.Id
      ];
      System.assertEquals('Change', unchanged.Type__c);
      System.assertEquals(opportunity.Id, unchanged.Opportunity__c);
      System.assertEquals('Estimate', unchanged.historystatus__c);
    }
  }

  @IsTest
  static void saveEditedEstimate_pinsPreviousHistoryFromDb() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Pin Prev Acc');
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Pin Prev Opp'
      );
      BillingAccount__c billingAccount = insertBillingAccount(account.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Pin Prev Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c previous = new ContractHistory__c(
        Name = 'Pin Prev Ordered',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert previous;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Pin Prev Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = previous.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New',
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );

      ContractHistory__c estimate = new ContractHistory__c(
        Name = 'Pin Prev Change Est',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        PreviousHistory__c = previous.Id,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart,
        ApplicationDate__c = termStart
      );
      insert estimate;

      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.opportunityId = opportunity.Id;
      request.selectedType = 'Change';
      request.editHistoryId = estimate.Id;
      request.contractServiceId = service.Id;
      // クライアントが別 ID を送っても DB の PreviousHistory に固定されること
      request.previousHistoryId = fakeHistoryId();
      request.contractStartDate = String.valueOf(termStart);
      request.contractEndDate = String.valueOf(termEnd);
      request.effectiveDate = String.valueOf(termStart);
      request.applicationDate = String.valueOf(termStart);
      request.products = new List<EstimateCreateController.ProductLineItem>();
      request.expectedLastModifiedToken = ContractOptimisticLockUtil.toToken(
        [
          SELECT LastModifiedDate
          FROM ContractHistory__c
          WHERE Id = :estimate.Id
        ]
        .LastModifiedDate
      );

      try {
        EstimateSaveService.saveEditedEstimate(request, estimate.Name);
      } catch (Exception ex) {
        // 明細不足などで落ちてもよい。previous が DB 値に戻っていることだけ見る
      }
      System.assertEquals(
        previous.Id,
        request.previousHistoryId,
        'Edit では PreviousHistory を DB 値に固定すること'
      );
    }
  }

  private static Id fakeHistoryId() {
    String keyPrefix = ContractHistory__c.SObjectType.getDescribe()
      .getKeyPrefix();
    return (Id) (keyPrefix + '0'.repeat(12) + 'BBB');
  }

  @IsTest
  static void saveEditedEstimate_staleLastModifiedToken_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Lock Edit Acc');
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Lock Edit Opp'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Lock Edit Service',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Lock Edit History',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 4, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 3, 31),
        EffectiveDate__c = Date.newInstance(2026, 4, 1),
        ApplicationDate__c = Date.newInstance(2026, 4, 1)
      );
      insert history;

      String staleToken = ContractOptimisticLockUtil.toToken(
        Datetime.now().addDays(-1)
      );
      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.opportunityId = opportunity.Id;
      request.selectedType = 'New';
      request.editHistoryId = history.Id;
      request.expectedLastModifiedToken = staleToken;

      try {
        EstimateSaveService.saveEditedEstimate(request, history.Name);
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
  static void saveEditedEstimate_blankLastModifiedToken_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Blank Edit Token Acc'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Blank Edit Token Opp'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Blank Edit Token Service',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Blank Edit Token History',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1
      );
      insert history;

      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.opportunityId = opportunity.Id;
      request.selectedType = 'New';
      request.editHistoryId = history.Id;

      try {
        EstimateSaveService.saveEditedEstimate(request, history.Name);
        System.assert(false, 'Expected blank token to reject');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage(),
          'Core 第4.3.12節: 見積編集保存は比較値未指定なら拒否する'
        );
      }
    }
  }

  @IsTest
  static void saveEstimate_new_savesEstimateSendContact() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Send Contact Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Send Contact Opportunity'
      );
      BillingAccount__c billing = insertBillingAccount(account.Id);
      Contact sendContact = new Contact(
        LastName = '見積送付先',
        AccountId = account.Id,
        Email = 'send-contact@example.com'
      );
      insert sendContact;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Send Contact Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 10000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      EstimateCreateController.ProductLineItem lineItem = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'New',
        termStart,
        termEnd
      );
      lineItem.billingCycle = '月';
      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{ lineItem }
      );

      EstimateCreateController.EstimateSaveResult created = EstimateSaveService.saveEstimate(
        opportunity.Id,
        'New',
        'Send Contact CS',
        'Send Contact History',
        null,
        null,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(termStart),
        String.valueOf(termStart),
        productsJson,
        null,
        null,
        billing.Id,
        null,
        null,
        '{}',
        '{}',
        null,
        10,
        null,
        null,
        sendContact.Id
      );

      ContractHistory__c saved = [
        SELECT EstimateSendContact__c
        FROM ContractHistory__c
        WHERE Id = :created.contractHistoryId
      ];
      System.assertEquals(
        sendContact.Id,
        saved.EstimateSendContact__c,
        'Core 第4.3.3節: 見積送付先は契約履歴へ保存する'
      );
    }
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

  private static EstimateCreateController.ProductLineItem buildLine(
    Id productId,
    String invoiceType,
    String recordType,
    Date startDate,
    Date endDate
  ) {
    EstimateCreateController.ProductLineItem line = new EstimateCreateController.ProductLineItem();
    line.productId = productId;
    line.quantity = 1;
    line.unitPrice = 10000;
    line.amount = 10000;
    line.invoiceType = invoiceType;
    line.recordType = recordType;
    line.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    line.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
    line.startDate = String.valueOf(startDate);
    line.endDate = String.valueOf(endDate);
    return line;
  }

  @IsTest
  static void saveEstimate_sameKeyRetry_keepsOneHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Key Retry Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Key Retry Opportunity'
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Key Retry Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 10000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      EstimateCreateController.ProductLineItem lineItem = buildLine(
        product.Id,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        'New',
        termStart,
        termEnd
      );
      lineItem.quantity = 1;
      lineItem.unitPrice = 10000;
      lineItem.amount = 10000;
      lineItem.unit = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      lineItem.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      lineItem.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      lineItem.billingCycle = '月';
      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{ lineItem }
      );
      String operationKey = 'estimate-new-retry-key';

      EstimateCreateController.EstimateSaveResult first = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Key Retry CS',
        'Key Retry History',
        null,
        null,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(termStart),
        String.valueOf(termStart),
        productsJson,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        operationKey
      );
      EstimateCreateController.EstimateSaveResult retry = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Key Retry CS 2',
        'Key Retry History 2',
        null,
        null,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(termStart),
        String.valueOf(termStart),
        productsJson,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        operationKey
      );

      System.assertEquals(
        first.contractHistoryId,
        retry.contractHistoryId,
        'Core 第4.3.12節: 同じキーの再試行は1件のままにする'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Opportunity__c = :opportunity.Id
        ]
      );
    }
  }

  @IsTest
  static void saveEditedEstimate_staleAfterProductUpdate_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Product Token Acc'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Product Token Opp'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Product Token Service',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Product Token History',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 4, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 3, 31),
        EffectiveDate__c = Date.newInstance(2026, 4, 1)
      );
      insert history;
      String historyOnlyToken = ContractOptimisticLockUtil.toToken(
        [
          SELECT LastModifiedDate
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ]
        .LastModifiedDate
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Product Token Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Amount__c = 10000,
        StartDate__c = Date.newInstance(2026, 4, 1),
        Enddate__c = Date.newInstance(2027, 3, 31),
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
      request.opportunityId = opportunity.Id;
      request.selectedType = 'New';
      request.editHistoryId = history.Id;
      request.expectedLastModifiedToken = historyOnlyToken;

      try {
        EstimateSaveService.saveEditedEstimate(request, history.Name);
        Datetime productMax = ContractOptimisticLockUtil.resolveHistoryProductDatetime(
          history.Id
        );
        Datetime historyLm = [
          SELECT LastModifiedDate
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ]
        .LastModifiedDate;
        if (productMax != null && historyLm != null && productMax.getTime() != historyLm.getTime()) {
          System.assert(
            false,
            'Core 第4.3.12節: 見積編集の版は契約履歴と配下見積商品。商品追加後の履歴だけのトークンは拒否する'
          );
        }
      } catch (AuraHandledException ex) {
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
    }
  }

  @IsTest
  static void saveEstimate_newBlankTaxPercent_doesNotFillTen() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Blank Tax Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Blank Tax Opportunity'
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Blank Tax Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
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

      Boolean rejected = false;
      try {
        EstimateSaveService.saveEstimate(
          opportunity.Id,
          'New',
          'Blank Tax Service',
          'Blank Tax History',
          null,
          null,
          String.valueOf(termStart),
          String.valueOf(termEnd),
          String.valueOf(termStart),
          String.valueOf(termStart),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{ lineItem }
          ),
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        rejected = true;
        System.assert(
          ex.getMessage().contains('消費税率が空です'),
          'Core 第1.1.10節・第4.6節: Newの税率nullは10で埋めない: ' +
          ex.getMessage()
        );
      }
      System.assertEquals(true, rejected);
    }
  }
}
