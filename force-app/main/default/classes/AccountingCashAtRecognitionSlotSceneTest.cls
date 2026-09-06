/**
 * 入金連動前受×売上計上時税（本Org方針）のスロット仕訳シーン。
 * 請求は必ず次の5明細（2024/1/1〜12/31・月次計上・税10%）。
 * 継続① 20,000×12、継続② 10,000×12、継続③ -5,000×12、
 * 一回① 10,000、一回② -5,000。
 * 仕様: Accounting 第3.1節・第4.6節・第5.2節・第5.6節。実勘定までは見ない。
 * 税込Netは正のため、過去日Invoice負額現預金（No.14）はこの請求では起きない。
 */
@IsTest
private class AccountingCashAtRecognitionSlotSceneTest {
  private static final Date PERIOD_START = Date.newInstance(2024, 1, 1);
  private static final Date PERIOD_END = Date.newInstance(2024, 12, 31);
  private static final Decimal BODY_NET = 305000;
  private static final Decimal TAX_NET = 30500;
  private static final Decimal INCLUSIVE_NET = 335500;
  private static final String NAME_REC_1 = '継続課金商品①';
  private static final String NAME_REC_2 = '継続課金商品②';
  private static final String NAME_REC_3 = '継続課金商品③';
  private static final String NAME_ONE_1 = '1回課金商品①';
  private static final String NAME_ONE_2 = '1回課金商品②';
  private static final Set<String> FORBIDDEN_BILLING_KEYS = new Set<String>{
    'BILLING_BASIS_INVOICE_BODY',
    'BILLING_TAX_AT_INVOICE',
    'BILLING_BASIS_INVOICE_TAX_DEFERRED',
    'BILLING_BASIS_REVENUE_BODY',
    'BILLING_BASIS_REVENUE_TAX'
  };

  @TestSetup
  static void setupOrgPolicyAndMaps() {
    ContractTestDataFactory.initTestContext();
    GlAccountingPolicy__c policy = ContractTestDataFactory.ensureOrgAccountingPolicy();
    policy.AccountingEnabled__c = true;
    policy.RevenueRecognitionBasis__c = 'CashBasis';
    policy.TaxRecognitionTiming__c = 'AtRecognition';
    policy.MonthlyBucketMethod__c = 'Auto';
    policy.MonthlyRecognitionDatePosition__c = 'BucketStart';
    policy.RoundingTargetBucket__c = 'Last';
    update policy;
    seedSlotMaps();
  }

  @IsTest
  static void policy_allowsOnlyCashAtRecognitionPatterns() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Set<String> keys = GlAccountingPolicyService.deriveAllowedPatternKeys(
        GlAccountingPolicyService.requireOrgPolicy()
      );
      System.assertEquals(true, keys.contains('CASH_BASIS_INVOICE_BODY_CTA_TRANSFER'));
      System.assertEquals(true, keys.contains('CASH_BASIS_INVOICE_TAX_CTA_TRANSFER'));
      System.assertEquals(true, keys.contains('CASH_BASIS_REVENUE_BODY'));
      System.assertEquals(true, keys.contains('CASH_BASIS_REVENUE_TAX'));
      System.assertEquals(true, keys.contains('PAYMENT_INVOICE_CURRENT'));
      System.assertEquals(true, keys.contains('PAYMENT_NON_INVOICE_POSITIVE'));
      System.assertEquals(true, keys.contains('PAYMENT_NON_INVOICE_NEGATIVE'));
      System.assertEquals(true, keys.contains('PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH'));
      System.assertEquals(true, keys.contains('PAYMENT_INVOICE_HISTORICAL_NEGATIVE_CASH'));
      System.assertEquals(true, keys.contains('PAYMENT_INVOICE_HISTORICAL_UAC_TRANSFER'));
      System.assertEquals(true, keys.contains('PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER'));
      for (String forbidden : FORBIDDEN_BILLING_KEYS) {
        System.assertEquals(false, keys.contains(forbidden), forbidden);
      }
    }
  }

  @IsTest
  static void confirm_onPeriodStart_revenueDebitsArWithoutCtaTransfer() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Scene scene = createFiveLineInvoice('Start', PERIOD_START);
      Test.startTest();
      confirm(scene);
      Test.stopTest();
      assertFiveLines(scene);
      assertNoBillingBasis(scene.invoice.Id);
      assertLineSlot(
        scene,
        NAME_REC_1,
        'CASH_BASIS_REVENUE_BODY',
        'AccountsReceivable',
        'Revenue',
        20000
      );
      assertLineSlot(
        scene,
        NAME_REC_1,
        'CASH_BASIS_REVENUE_TAX',
        'AccountsReceivable',
        'TaxPayable',
        2000
      );
      assertLineSlot(
        scene,
        NAME_REC_3,
        'CASH_BASIS_REVENUE_BODY',
        'Revenue',
        'AccountsReceivable',
        5000
      );
      System.assertEquals(
        0,
        countPattern(scene.invoice.Id, 'CASH_BASIS_INVOICE_BODY_CTA_TRANSFER'),
        'Accounting 第5.2.2節: 請求日前の認識が無ければ本体CTA振替仕訳は作らない'
      );
    }
  }

  @IsTest
  static void confirm_afterPeriod_ctaThenArTransferIncludingNegatives() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Scene scene = createFiveLineInvoice(
        'After',
        Date.newInstance(2025, 1, 15)
      );
      Test.startTest();
      confirm(scene);
      Test.stopTest();
      assertFiveLines(scene);
      assertNoBillingBasis(scene.invoice.Id);
      assertLineSlot(
        scene,
        NAME_REC_1,
        'CASH_BASIS_REVENUE_BODY',
        'ContractAsset',
        'Revenue',
        20000
      );
      assertLineSlot(
        scene,
        NAME_REC_1,
        'CASH_BASIS_INVOICE_BODY_CTA_TRANSFER',
        'AccountsReceivable',
        'ContractAsset',
        240000
      );
      assertLineSlot(
        scene,
        NAME_REC_1,
        'CASH_BASIS_INVOICE_TAX_CTA_TRANSFER',
        'AccountsReceivable',
        'ContractAsset',
        24000
      );
      assertLineSlot(
        scene,
        NAME_REC_3,
        'CASH_BASIS_INVOICE_BODY_CTA_TRANSFER',
        'ContractAsset',
        'AccountsReceivable',
        60000
      );
      assertLineSlot(
        scene,
        NAME_ONE_2,
        'CASH_BASIS_INVOICE_BODY_CTA_TRANSFER',
        'ContractAsset',
        'AccountsReceivable',
        5000
      );
    }
  }

  @IsTest
  static void confirm_midPeriod_ctaBeforeInvoiceAndArAfter() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Scene scene = createFiveLineInvoice(
        'Mid',
        Date.newInstance(2024, 6, 15)
      );
      Test.startTest();
      confirm(scene);
      Test.stopTest();
      assertFiveLines(scene);
      assertNoBillingBasis(scene.invoice.Id);
      System.assertEquals(
        true,
        hasSlot(
          scene.invoice.Id,
          'CASH_BASIS_REVENUE_BODY',
          'ContractAsset',
          'Revenue'
        )
      );
      System.assertEquals(
        true,
        hasSlot(
          scene.invoice.Id,
          'CASH_BASIS_REVENUE_BODY',
          'AccountsReceivable',
          'Revenue'
        ),
        'Accounting 第4.6節: 請求日後の未入金認識はAR'
      );
      System.assertEquals(
        5,
        countPattern(scene.invoice.Id, 'CASH_BASIS_INVOICE_BODY_CTA_TRANSFER')
      );
      System.assertEquals(
        5,
        countPattern(scene.invoice.Id, 'CASH_BASIS_INVOICE_TAX_CTA_TRANSFER')
      );
    }
  }

  @IsTest
  static void payment_afterLastBucket_cashToAr() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Scene scene = createFiveLineInvoice('PayAr', PERIOD_START);
      confirm(scene);
      Test.startTest();
      registerFullInvoicePayment(scene, Date.newInstance(2025, 1, 15));
      Test.stopTest();
      assertFiveLines(scene);
      System.assertEquals(
        true,
        hasSlot(
          scene.invoice.Id,
          'PAYMENT_INVOICE_CURRENT',
          'Cash',
          'AccountsReceivable'
        )
      );
      System.assertEquals(
        0,
        countSlot(
          scene.invoice.Id,
          'PAYMENT_INVOICE_CURRENT',
          'Cash',
          'DeferredRevenue'
        ),
        'Accounting 第4.6節: 認識済みならInvoice決済のDEF新設は0'
      );
    }
  }

  @IsTest
  static void payment_whileMonthsRemain_cashToDefThenRevenueDrawsDef() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Scene scene = createFiveLineInvoice('PayDef', PERIOD_START);
      confirm(scene);
      Test.startTest();
      registerFullInvoicePayment(scene, Date.newInstance(2024, 1, 15));
      Test.stopTest();
      assertFiveLines(scene);
      System.assertEquals(
        true,
        hasSlot(
          scene.invoice.Id,
          'PAYMENT_INVOICE_CURRENT',
          'Cash',
          'AccountsReceivable'
        ),
        'Accounting 第5.2.10節: 認識済み分はARへ'
      );
      System.assertEquals(
        true,
        hasSlot(
          scene.invoice.Id,
          'PAYMENT_INVOICE_CURRENT',
          'Cash',
          'DeferredRevenue'
        ),
        'Accounting 第4.6節・第5.2.10節: 未認識予定はDEFへ積む'
      );
      System.assertEquals(
        true,
        hasSlot(
          scene.invoice.Id,
          'CASH_BASIS_REVENUE_BODY',
          'DeferredRevenue',
          'Revenue'
        ),
        'Accounting 第5.2.7節・第5.2.9節: 入金後の売上は税込プールのDEFを取り崩す'
      );
    }
  }

  @IsTest
  static void payment_nonInvoicePositive_cashToUac() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Scene scene = createFiveLineInvoice(
        'NonPos',
        Date.newInstance(2024, 6, 15)
      );
      confirm(scene);
      Test.startTest();
      registerNonInvoice(scene, 4000, Date.newInstance(2024, 7, 1));
      Test.stopTest();
      assertFiveLines(scene);
      assertHasSlot(
        scene.invoice.Id,
        'PAYMENT_NON_INVOICE_POSITIVE',
        'Cash',
        'UnappliedCash',
        4000
      );
    }
  }

  @IsTest
  static void payment_nonInvoiceNegative_spToCash() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Scene scene = createFiveLineInvoice(
        'NonNeg',
        Date.newInstance(2024, 6, 15)
      );
      confirm(scene);
      Test.startTest();
      registerNonInvoice(scene, -2500, Date.newInstance(2024, 7, 1));
      Test.stopTest();
      assertFiveLines(scene);
      assertHasSlot(
        scene.invoice.Id,
        'PAYMENT_NON_INVOICE_NEGATIVE',
        'SuspensePayment',
        'Cash',
        2500
      );
    }
  }

  @IsTest
  static void payment_historicalPositive_uacCashThenUacToDef() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Scene scene = createFiveLineInvoice(
        'HistUac',
        Date.newInstance(2024, 6, 15)
      );
      confirm(scene);
      Test.startTest();
      registerFullInvoicePayment(scene, Date.newInstance(2024, 1, 10));
      Test.stopTest();
      assertFiveLines(scene);
      System.assertEquals(
        true,
        hasSlot(
          scene.invoice.Id,
          'PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH',
          'Cash',
          'UnappliedCash'
        )
      );
      System.assertEquals(
        true,
        hasSlot(
          scene.invoice.Id,
          'PAYMENT_INVOICE_HISTORICAL_UAC_TRANSFER',
          'UnappliedCash',
          'DeferredRevenue'
        )
      );
      System.assertEquals(
        0,
        countPattern(scene.invoice.Id, 'PAYMENT_INVOICE_CURRENT')
      );
    }
  }

  @IsTest
  static void payment_historicalPositive_spFirstThenSpTransfer() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Scene scene = createFiveLineInvoice(
        'HistSp',
        Date.newInstance(2024, 6, 15)
      );
      Test.startTest();
      confirm(scene);
      registerNonInvoice(scene, -80000, Date.newInstance(2024, 1, 5));
      registerInvoicePayment(scene, 80000, Date.newInstance(2024, 1, 10));
      Test.stopTest();
      assertFiveLines(scene);
      System.assertEquals(
        true,
        hasSlot(
          scene.invoice.Id,
          'PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH',
          'Cash',
          'SuspensePayment'
        ),
        'Accounting 第5.2.14節: 既存SPへ現預金を先に載せる'
      );
      System.assertEquals(
        true,
        hasSlot(
          scene.invoice.Id,
          'PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH',
          'Cash',
          'UnappliedCash'
        )
      );
      System.assertEquals(
        true,
        hasSlot(
          scene.invoice.Id,
          'PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER',
          'AccountsReceivable',
          'SuspensePayment'
        ) ||
        hasSlot(
          scene.invoice.Id,
          'PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER',
          'DeferredRevenue',
          'SuspensePayment'
        ),
        'Accounting 第5.2.16節: 過去日SPは請求日にARまたはDEFへ振り替える'
      );
    }
  }

  @IsTest
  static void manual_fxLoss_otherExpenseToAr() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Scene scene = createFiveLineInvoice(
        'Manual',
        Date.newInstance(2024, 6, 15)
      );
      confirm(scene);
      GlAccount__c debit = new GlAccount__c(
        Name = 'Scene FX Loss',
        AccountType__c = 'Expense',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'Scene FX AR',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlManualJournalSetting__c setting = new GlManualJournalSetting__c(
        Name = '為替差損の計上',
        DebitSlotKey__c = 'FxLoss',
        DebitAccount__c = debit.Id,
        CreditSlotKey__c = 'AccountsReceivable',
        CreditAccount__c = credit.Id,
        Description__c = '入金不足が為替変動による場合',
        IsActive__c = true
      );
      insert setting;
      Test.startTest();
      ManualJournalService.RegisterRequest request = new ManualJournalService.RegisterRequest();
      request.invoiceId = scene.invoice.Id;
      request.settingId = setting.Id;
      request.postingDate = Date.newInstance(2024, 7, 1);
      request.amount = 100;
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        scene.invoice.Id
      );
      ManualJournalService.register(request);
      Test.stopTest();
      assertFiveLines(scene);
      Boolean found = false;
      for (GlJournal__c row : activeJournals(scene.invoice.Id)) {
        if (
          row.DebitSlotKey__c == 'FxLoss' &&
          row.CreditSlotKey__c == 'AccountsReceivable' &&
          row.Amount__c == 100
        ) {
          found = true;
        }
      }
      System.assertEquals(
        true,
        found,
        'Accounting 第10章: 手動仕訳は設定の借貸スロットを載せる'
      );
    }
  }

  private class Scene {
    Invoice__c invoice;
    List<InvoiceLine__c> lines;
  }

  private class LineSpec {
    String productName;
    String billingType;
    Decimal amount;
    LineSpec(String productName, String billingType, Decimal amount) {
      this.productName = productName;
      this.billingType = billingType;
      this.amount = amount;
    }
  }

  private static List<LineSpec> fiveLineSpecs() {
    String recurring = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    String oneTime = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    return new List<LineSpec>{
      new LineSpec(NAME_REC_1, recurring, 240000),
      new LineSpec(NAME_REC_2, recurring, 120000),
      new LineSpec(NAME_REC_3, recurring, -60000),
      new LineSpec(NAME_ONE_1, oneTime, 10000),
      new LineSpec(NAME_ONE_2, oneTime, -5000)
    };
  }

  private static Scene createFiveLineInvoice(String suffix, Date invoiceDate) {
    Account account = ContractTestDataFactory.insertAccount('Scene ' + suffix);
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      'Scene ' + suffix
    );
    service.TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10);
    update service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Scene Hist ' + suffix,
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
    insert history;
    List<LineSpec> specs = fiveLineSpecs();
    List<Product2> products = new List<Product2>();
    for (LineSpec spec : specs) {
      Product2 product = ContractTestDataFactory.buildProduct(
        spec.productName + ' ' + suffix
      );
      product.BillingType__c = spec.billingType;
      product.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      products.add(product);
    }
    ContractTestDataFactory.insertProducts(products);
    List<ContractProduct__c> contractProducts = new List<ContractProduct__c>();
    for (Integer i = 0; i < specs.size(); i++) {
      LineSpec spec = specs[i];
      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Account__c = account.Id,
        Product__c = products[i].Id,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = spec.billingType,
        Quantity__c = 1,
        UnitPrice__c = spec.amount,
        Amount__c = spec.amount,
        StartDate__c = PERIOD_START,
        Enddate__c = PERIOD_END
      );
      ContractTestDataFactory.applyRequiredFields(contractProduct);
      contractProducts.add(contractProduct);
    }
    insert contractProducts;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = invoiceDate,
      Amount__c = BODY_NET,
      TaxAmount__c = TAX_NET,
      BillingAccountSnapShot__c = service.BiilingAcccount__c,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT
    );
    insert invoice;
    List<InvoiceLine__c> lines = new List<InvoiceLine__c>();
    for (Integer i = 0; i < specs.size(); i++) {
      LineSpec spec = specs[i];
      lines.add(
        new InvoiceLine__c(
          Invoice__c = invoice.Id,
          ContractProduct__c = contractProducts[i].Id,
          ProductName__c = spec.productName,
          Amount__c = spec.amount,
          Quantity__c = 1,
          UnitPrice__c = spec.amount,
          RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME,
          ServicePeriodStartDate__c = PERIOD_START,
          ServicePeriodEndDate__c = PERIOD_END
        )
      );
    }
    insert lines;
    Scene scene = new Scene();
    scene.invoice = invoice;
    scene.lines = lines;
    return scene;
  }

  private static void confirm(Scene scene) {
    InvoiceTransactionStatusService.applyConfirmed(
      new List<Invoice__c>{ scene.invoice },
      scene.invoice.InvoiceDate__c
    );
    Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
    Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
    InvoiceTransactionStatusService.allowStatusWrite = true;
    InvoiceLockUtil.allowLockedStatusWrite = true;
    try {
      update scene.invoice;
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
      InvoiceLockUtil.allowLockedStatusWrite = previousLock;
    }
    InvoiceTaxAllocationService.allocateOnConfirm(scene.invoice);
    scene.lines = [
      SELECT Id, ProductName__c, Amount__c, AllocatedTaxAmount__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :scene.invoice.Id
      ORDER BY Id
    ];
    AccountingDiffService.applyForInvoice(
      scene.invoice.Id,
      AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
      'SCENE_CONFIRM_' + String.valueOf(scene.invoice.Id),
      null
    );
    scene.invoice = [
      SELECT
        Id,
        InvoiceDate__c,
        Amount__c,
        TaxAmount__c,
        TaxInclusiveAmount__c,
        InvoicePaymentNet__c,
        BillingAccountSnapShot__c
      FROM Invoice__c
      WHERE Id = :scene.invoice.Id
    ];
  }

  private static void registerFullInvoicePayment(Scene scene, Date paymentDate) {
    Decimal amount = scene.invoice.TaxInclusiveAmount__c;
    if (amount == null) {
      amount = INCLUSIVE_NET;
    }
    registerInvoicePayment(scene, amount, paymentDate);
  }

  private static void registerInvoicePayment(
    Scene scene,
    Decimal amount,
    Date paymentDate
  ) {
    InvoicePaymentService.RegisterRequest request = new InvoicePaymentService.RegisterRequest();
    request.invoiceId = scene.invoice.Id;
    request.amount = amount;
    request.purpose = InvoicePaymentService.PURPOSE_INVOICE;
    request.paymentDate = paymentDate;
    request.allocations = InvoicePaymentAllocationService.proposeLines(
      scene.invoice.Id,
      amount
    );
    request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
      scene.invoice.Id
    );
    InvoicePaymentService.register(request);
  }

  private static void registerNonInvoice(
    Scene scene,
    Decimal amount,
    Date paymentDate
  ) {
    InvoicePaymentService.RegisterRequest request = new InvoicePaymentService.RegisterRequest();
    request.invoiceId = scene.invoice.Id;
    request.amount = amount;
    request.purpose = InvoicePaymentService.PURPOSE_NON_INVOICE;
    request.paymentDate = paymentDate;
    request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
      scene.invoice.Id
    );
    InvoicePaymentService.register(request);
  }

  private static List<GlJournal__c> activeJournals(Id invoiceId) {
    return [
      SELECT
        JournalPatternKey__c,
        DebitSlotKey__c,
        CreditSlotKey__c,
        Amount__c,
        PostingDate__c,
        TransactionStatus__c,
        InvoiceLine__c,
        InvoiceLine__r.ProductName__c
      FROM GlJournal__c
      WHERE Invoice__c = :invoiceId AND TransactionStatus__c = 'Active'
    ];
  }

  private static Integer countPattern(Id invoiceId, String patternKey) {
    Integer count = 0;
    for (GlJournal__c row : activeJournals(invoiceId)) {
      if (row.JournalPatternKey__c == patternKey) {
        count++;
      }
    }
    return count;
  }

  private static Integer countSlot(
    Id invoiceId,
    String patternKey,
    String debit,
    String credit
  ) {
    Integer count = 0;
    for (GlJournal__c row : activeJournals(invoiceId)) {
      if (
        row.JournalPatternKey__c == patternKey &&
        row.DebitSlotKey__c == debit &&
        row.CreditSlotKey__c == credit
      ) {
        count++;
      }
    }
    return count;
  }

  private static Boolean hasSlot(
    Id invoiceId,
    String patternKey,
    String debit,
    String credit
  ) {
    return countSlot(invoiceId, patternKey, debit, credit) > 0;
  }

  private static void assertHasSlot(
    Id invoiceId,
    String patternKey,
    String debit,
    String credit,
    Decimal amount
  ) {
    Boolean found = false;
    for (GlJournal__c row : activeJournals(invoiceId)) {
      if (
        row.JournalPatternKey__c == patternKey &&
        row.DebitSlotKey__c == debit &&
        row.CreditSlotKey__c == credit &&
        row.Amount__c == amount
      ) {
        found = true;
      }
    }
    System.assertEquals(
      true,
      found,
      patternKey + ' ' + debit + '/' + credit + ' ' + String.valueOf(amount)
    );
  }

  private static void assertLineSlot(
    Scene scene,
    String productName,
    String patternKey,
    String debit,
    String credit,
    Decimal amount
  ) {
    Boolean found = false;
    for (GlJournal__c row : activeJournals(scene.invoice.Id)) {
      if (
        row.InvoiceLine__r != null &&
        row.InvoiceLine__r.ProductName__c == productName &&
        row.JournalPatternKey__c == patternKey &&
        row.DebitSlotKey__c == debit &&
        row.CreditSlotKey__c == credit &&
        row.Amount__c == amount
      ) {
        found = true;
      }
    }
    System.assertEquals(
      true,
      found,
      productName +
        ' ' +
        patternKey +
        ' ' +
        debit +
        '/' +
        credit +
        ' ' +
        String.valueOf(amount)
    );
  }

  private static void assertFiveLines(Scene scene) {
    System.assertEquals(5, scene.lines.size());
    Set<String> names = new Set<String>();
    Map<String, Decimal> amounts = new Map<String, Decimal>();
    for (InvoiceLine__c line : scene.lines) {
      names.add(line.ProductName__c);
      amounts.put(line.ProductName__c, line.Amount__c);
    }
    System.assertEquals(
      new Set<String>{
        NAME_REC_1,
        NAME_REC_2,
        NAME_REC_3,
        NAME_ONE_1,
        NAME_ONE_2
      },
      names
    );
    System.assertEquals(240000, amounts.get(NAME_REC_1));
    System.assertEquals(120000, amounts.get(NAME_REC_2));
    System.assertEquals(-60000, amounts.get(NAME_REC_3));
    System.assertEquals(10000, amounts.get(NAME_ONE_1));
    System.assertEquals(-5000, amounts.get(NAME_ONE_2));
  }

  private static void assertNoBillingBasis(Id invoiceId) {
    for (GlJournal__c row : activeJournals(invoiceId)) {
      System.assertEquals(
        false,
        FORBIDDEN_BILLING_KEYS.contains(row.JournalPatternKey__c),
        row.JournalPatternKey__c
      );
    }
  }

  private static void seedSlotMaps() {
    Map<String, String> types = new Map<String, String>{
      'AR' => 'Asset',
      'CTA' => 'Asset',
      'DEF' => 'Liability',
      'TAX' => 'Liability',
      'REV' => 'Revenue',
      'CASH' => 'Asset',
      'UAC' => 'Liability',
      'SP' => 'Asset'
    };
    List<GlAccount__c> accounts = new List<GlAccount__c>();
    for (String name : types.keySet()) {
      accounts.add(
        new GlAccount__c(
          Name = 'Scene ' + name,
          AccountType__c = types.get(name),
          IsActive__c = true
        )
      );
    }
    insert accounts;
    Map<String, Id> accountIds = new Map<String, Id>();
    for (GlAccount__c account : accounts) {
      accountIds.put(account.Name.substringAfter('Scene '), account.Id);
    }
    Map<String, String> slots = new Map<String, String>{
      'AccountsReceivable' => 'AR',
      'ContractAsset' => 'CTA',
      'DeferredRevenue' => 'DEF',
      'TaxPayable' => 'TAX',
      'Revenue' => 'REV',
      'Cash' => 'CASH',
      'UnappliedCash' => 'UAC',
      'SuspensePayment' => 'SP'
    };
    List<String> contexts = new List<String>{
      'InvoiceLine',
      'InvoicePaymentAllocation',
      'InvoicePayment'
    };
    List<GlAccountMap__c> maps = new List<GlAccountMap__c>();
    for (String context : contexts) {
      for (String slot : slots.keySet()) {
        maps.add(
          new GlAccountMap__c(
            Name = 'Scene ' + context + ' ' + slot,
            Account__c = accountIds.get(slots.get(slot)),
            SlotKey__c = slot,
            EvaluationContext__c = context,
            ConditionSourceType__c = 'None',
            Priority__c = 10,
            IsActive__c = true
          )
        );
      }
    }
    insert maps;
  }
}
