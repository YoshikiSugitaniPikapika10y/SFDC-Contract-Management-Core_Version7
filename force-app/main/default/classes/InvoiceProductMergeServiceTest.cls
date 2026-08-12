@IsTest
private class InvoiceProductMergeServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void buildPeriodLabel_mergesContinuousRecurringRanges() {
    List<InvoiceProduct__c> products = new List<InvoiceProduct__c>{
      new InvoiceProduct__c(
        StartDate__c = Date.newInstance(2026, 7, 1),
        Enddate__c = Date.newInstance(2026, 7, 31)
      ),
      new InvoiceProduct__c(
        StartDate__c = Date.newInstance(2026, 8, 1),
        Enddate__c = Date.newInstance(2026, 8, 31)
      ),
      new InvoiceProduct__c(
        StartDate__c = Date.newInstance(2026, 10, 1),
        Enddate__c = Date.newInstance(2026, 10, 31)
      )
    };

    String label = InvoiceProductMergeService.buildPeriodLabel(products, true);
    System.assertEquals(
      '2026-07-01～2026-08-31、2026-10-01～2026-10-31',
      label
    );
  }

  @IsTest
  static void buildPeriodLabel_doesNotMergeWhenNotRecurring() {
    List<InvoiceProduct__c> products = new List<InvoiceProduct__c>{
      new InvoiceProduct__c(
        StartDate__c = Date.newInstance(2026, 7, 1),
        Enddate__c = Date.newInstance(2026, 7, 31)
      ),
      new InvoiceProduct__c(
        StartDate__c = Date.newInstance(2026, 8, 1),
        Enddate__c = Date.newInstance(2026, 8, 31)
      )
    };

    String label = InvoiceProductMergeService.buildPeriodLabel(products, false);
    System.assertEquals(
      '2026-07-01～2026-07-31、2026-08-01～2026-08-31',
      label
    );
  }

  @IsTest
  static void buildMergedInvoices_handlesEmptyAndRequiresBucketKey() {
    System.assertEquals(
      0,
      InvoiceProductMergeService.buildMergedInvoices(null).size()
    );
    System.assertEquals(
      0,
      InvoiceProductMergeService.buildMergedInvoices(
          new List<InvoiceProduct__c>()
        )
        .size()
    );

    InvoiceProduct__c product = new InvoiceProduct__c(
      StartDate__c = Date.newInstance(2026, 1, 1),
      Enddate__c = Date.newInstance(2026, 1, 31),
      Amount__c = 1000,
      TaxPercent__c = 0.1,
      Quantity__c = 2,
      UnitPrice__c = 500,
      InvoiceBucketKey__c = 'INV|BA=x|CH=y|DT=2026-01-01',
      LineBucketKey__c = 'LINE|CP=z'
    );
    List<InvoiceProductMergeService.MergedInvoice> invoices = InvoiceProductMergeService.buildMergedInvoices(
      new List<InvoiceProduct__c>{ product }
    );
    System.assertEquals(1, invoices.size());
    System.assertEquals(1, invoices[0].lines.size());
    System.assertEquals(1000, invoices[0].amountTotal);
    System.assertEquals(
      100,
      invoices[0].taxTotal,
      '税額は税抜合計×税率を1回切り捨て'
    );
    System.assertEquals(1000, invoices[0].openAmount);
    System.assertEquals(
      'INV|BA=x|CH=y|DT=2026-01-01',
      invoices[0].mergeKey
    );

    Boolean missingKeyFailed = false;
    try {
      InvoiceProductMergeService.buildMergedInvoices(
        new List<InvoiceProduct__c>{
          new InvoiceProduct__c(
            StartDate__c = Date.newInstance(2026, 1, 1),
            Enddate__c = Date.newInstance(2026, 1, 31),
            Amount__c = 1
          )
        }
      );
    } catch (InvoiceProductMergeService.MergeKeyException ex) {
      missingKeyFailed = true;
      System.assertEquals(
        '請求マージキー（InvoiceBucketKey）がありません。請求生成をやり直してください。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, missingKeyFailed, 'キー欠落は Fail closed');
    System.assertEquals(
      '2026-01-01～2026-01-31',
      invoices[0].lines[0].periodLabel
    );
    System.assertEquals(
      '',
      InvoiceProductMergeService.buildPeriodLabel(
        new List<InvoiceProduct__c>(),
        true
      )
    );
    System.assertEquals(
      '2026-01-01',
      InvoiceProductMergeService.formatPeriod(
        Date.newInstance(2026, 1, 1),
        null
      )
    );
    System.assertEquals(
      '2026-01-31',
      InvoiceProductMergeService.formatPeriod(
        null,
        Date.newInstance(2026, 1, 31)
      )
    );
    System.assertEquals(
      'V3',
      InvoiceProductMergeService.formatHistoryVersionLabel(3)
    );
    System.assertEquals(
      '',
      InvoiceProductMergeService.formatHistoryVersionLabel(null)
    );
  }

  @IsTest
  static void buildMergedInvoices_ignoresLegacyLineTaxAmount() {
    // 過去データに行税額があっても参照せず、税抜×税率を切り捨てる。
    InvoiceProduct__c product = new InvoiceProduct__c(
      StartDate__c = Date.newInstance(2026, 1, 1),
      Enddate__c = Date.newInstance(2026, 1, 31),
      Amount__c = 15,
      TaxPercent__c = 0.1,
      TaxAmount__c = 999,
      InvoiceBucketKey__c = 'INV|BA=x|CH=y|DT=2026-01-01',
      LineBucketKey__c = 'LINE|CP=z'
    );
    List<InvoiceProductMergeService.MergedInvoice> invoices = InvoiceProductMergeService.buildMergedInvoices(
      new List<InvoiceProduct__c>{ product }
    );
    System.assertEquals(1, invoices.size());
    System.assertEquals(15, invoices[0].amountTotal);
    System.assertEquals(1, invoices[0].taxTotal);
    System.assertEquals(0, invoices[0].lines[0].taxAmount);
    System.assertEquals(
      3,
      TaxCalculationUtil.calculateTaxAmount(30, 10),
      '行切捨て合計(1+1)ではなく税抜合計30なら税額3になる'
    );
  }

  @IsTest
  static void buildMergedInvoices_groupsByInvoiceAndLineKeys() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Merge Service Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
        AdjustInvoiceDateToBusinessDay__c = false
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;

      ContractService__c service = new ContractService__c(
        Name = 'Merge Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Merge History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 8, 31)
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct('Merge Product');
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Unit__c = 'ID',
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 8, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert contractProduct;

      Date invoiceDate = Date.newInstance(2026, 6, 1);
      Date paymentDate = Date.newInstance(2026, 6, 30);
      String exportMergeKey = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
        billingAccount.Id,
        history.Id,
        invoiceDate,
        paymentDate
      );
      String lineMergeKey = InvoiceMergeKeyConfigService.buildLineBucketKey(
        contractProduct.Id,
        10000,
        1,
        null,
        product.Id
      );
      List<InvoiceProduct__c> invoiceProducts = new List<InvoiceProduct__c>{
        new InvoiceProduct__c(
          ContractHistory__c = history.Id,
          ContractProduct__c = contractProduct.Id,
          StartDate__c = Date.newInstance(2026, 6, 1),
          Enddate__c = Date.newInstance(2026, 6, 30),
          InvoiceBucketKey__c = exportMergeKey,
          LineBucketKey__c = lineMergeKey,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 10000,
          TaxPercent__c = 0.1
        ),
        new InvoiceProduct__c(
          ContractHistory__c = history.Id,
          ContractProduct__c = contractProduct.Id,
          StartDate__c = Date.newInstance(2026, 7, 1),
          Enddate__c = Date.newInstance(2026, 7, 31),
          InvoiceBucketKey__c = exportMergeKey,
          LineBucketKey__c = lineMergeKey,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 10000,
          TaxPercent__c = 0.1
        ),
        new InvoiceProduct__c(
          ContractHistory__c = history.Id,
          ContractProduct__c = contractProduct.Id,
          StartDate__c = Date.newInstance(2026, 8, 1),
          Enddate__c = Date.newInstance(2026, 8, 31),
          InvoiceBucketKey__c = exportMergeKey,
          LineBucketKey__c = lineMergeKey,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 10000,
          TaxPercent__c = 0.1
        )
      };
      insert invoiceProducts;

      List<InvoiceProduct__c> queried = [
        SELECT
          Id,
          Name,
          InvoiceBucketKey__c,
          LineBucketKey__c,
          UnitPrice__c,
          Quantity__c,
          StartDate__c,
          Enddate__c,
          Amount__c,
          TaxPercent__c,
          ContractProduct__r.Product__r.Name,
          ContractProduct__r.Product__r.BillingType__c,
          ContractProduct__r.BillingType__c,
          ContractHistory__r.Version__c,
          ContractHistory__r.ContractService__r.Name,
          ContractHistory__r.ContractService__r.BiilingAcccount__r.Name
        FROM InvoiceProduct__c
        WHERE Id IN :invoiceProducts
      ];

      List<InvoiceProductMergeService.MergedInvoice> invoices = InvoiceProductMergeService.buildMergedInvoices(
        queried
      );

      System.assertEquals(1, invoices.size(), 'Same invoice key should merge');
      System.assertEquals(
        1,
        invoices[0].lines.size(),
        'Same line key should merge'
      );
      System.assertEquals(30000, invoices[0].amountTotal);
      System.assertEquals(
        3000,
        invoices[0].taxTotal,
        '同一請求の税抜合計に対して税額を1回計算'
      );
      System.assertEquals(0, invoices[0].lines[0].taxAmount);
      System.assertEquals(
        0,
        invoices[0].integratedAmount,
        '連携額の正は Invoice__c（期間明細からは集計しない）'
      );
      System.assertEquals(30000, invoices[0].openAmount);
      System.assertEquals(
        '2026-06-01～2026-08-31',
        invoices[0].lines[0].periodLabel
      );
      System.assertEquals('V1', invoices[0].lines[0].historyVersionLabel);
      System.assertEquals(
        3,
        invoices[0].lines[0].sourceInvoiceProductIds.size()
      );
    }
  }
}
