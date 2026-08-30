@IsTest
private class OrderWizardFieldServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void getDefinitions_returnsApplicationDateAndOrderDate() {
    OrderWizardFieldService.resetCache();
    List<ContractWizardFieldService.WizardFieldDefinition> definitions = OrderWizardFieldService.getDefinitions(
      'New'
    );

    Map<String, ContractWizardFieldService.WizardFieldDefinition> byApi = new Map<String, ContractWizardFieldService.WizardFieldDefinition>();
    for (
      ContractWizardFieldService.WizardFieldDefinition definition : definitions
    ) {
      byApi.put(definition.apiName, definition);
    }
    System.assertEquals(true, byApi.containsKey('ApplicationDate__c'));
    System.assertEquals(true, byApi.containsKey('OrderDate__c'));
    System.assertEquals(true, byApi.get('ApplicationDate__c').required);
    System.assertEquals(false, byApi.get('OrderDate__c').required);
    System.assertEquals('Today', byApi.get('OrderDate__c').defaultSource);
    System.assertEquals(true, byApi.get('ApplicationDate__c').showOnCancel);
    System.assert(!byApi.containsKey('Note__c'));
  }

  @IsTest
  static void buildHistoryFieldValuesForWizard_orderDateDefaultsToOrganizationToday() {
    OrderWizardFieldService.resetCache();
    ContractHistory__c history = new ContractHistory__c(Type__c = 'New');
    Map<String, Object> values = OrderWizardFieldService.buildHistoryFieldValuesForWizard(
      history
    );
    System.assertEquals(
      String.valueOf(InvoiceTransactionStatusService.organizationToday()),
      values.get('OrderDate__c'),
      'Core 第5.3節、日付仕様 第8章: 受注日初期値は組織TZの操作日'
    );
  }

  @IsTest
  static void getOrderHistoryFieldDefinitions_doesNotIncludeNote() {
    List<ContractWizardFieldService.WizardFieldDefinition> definitions = OrderWizardFieldService.getDefinitions(
      'New'
    );

    Set<String> apiNames = new Set<String>();
    for (
      ContractWizardFieldService.WizardFieldDefinition definition : definitions
    ) {
      apiNames.add(definition.apiName);
    }
    System.assert(!apiNames.contains('Note__c'));
    System.assert(apiNames.contains('ApplicationDate__c'));
  }

  @IsTest
  static void validateActiveDefinitions_product2_includesDeveloperName() {
    OrderWizardFieldService.setCachedDefinitionsForTest(
      new List<OrderWizardField__mdt>{
        new OrderWizardField__mdt(
          DeveloperName = 'Bad_Product2',
          MasterLabel = '不正',
          FieldApiName__c = 'ApplicationDate__c',
          Active__c = true,
          DefaultSource__c = 'Product2',
          ShowOnNew__c = true
        )
      }
    );
    Boolean failed = false;
    try {
      OrderWizardFieldService.getDefinitions('New');
    } catch (AuraHandledException ex) {
      failed = true;
      System.assert(
        ex.getMessage().contains('Bad_Product2'),
        ex.getMessage()
      );
      System.assert(
        ex.getMessage().contains('Product2'),
        ex.getMessage()
      );
    }
    System.assertEquals(true, failed);
    OrderWizardFieldService.resetCache();
  }

  @IsTest
  static void validateActiveDefinitions_todayWithDefaultValue_fails() {
    OrderWizardFieldService.setCachedDefinitionsForTest(
      new List<OrderWizardField__mdt>{
        new OrderWizardField__mdt(
          DeveloperName = 'Bad_TodayValue',
          MasterLabel = '不正',
          FieldApiName__c = 'OrderDate__c',
          Active__c = true,
          DefaultSource__c = 'Today',
          DefaultValue__c = '2026-01-01',
          ShowOnNew__c = true
        )
      }
    );
    Boolean failed = false;
    try {
      OrderWizardFieldService.getDefinitions('New');
    } catch (AuraHandledException ex) {
      failed = true;
      System.assert(
        ex.getMessage().contains('Bad_TodayValue'),
        ex.getMessage()
      );
    }
    System.assertEquals(true, failed);
    OrderWizardFieldService.resetCache();
  }

  @IsTest
  static void validateRequiredHistoryFields_requiresApplicationDate() {
    OrderWizardFieldService.resetCache();
    String error = OrderWizardFieldService.validateRequiredHistoryFields(
      new Map<String, Object>(),
      'New'
    );
    System.assertNotEquals(null, error);
    System.assert(error.contains('申込日'), error);
  }

  @IsTest
  static void getOrderBillingFieldDefinitions_returnsConfiguredFields() {
    List<ContractWizardFieldService.WizardFieldDefinition> definitions = OrderWizardFieldService.getOrderBillingFieldDefinitions();

    Set<String> apiNames = new Set<String>();
    for (
      ContractWizardFieldService.WizardFieldDefinition definition : definitions
    ) {
      apiNames.add(definition.apiName);
    }
    System.assert(apiNames.contains('InvoiceDateMethod__c'));
    System.assert(apiNames.contains('PaymentTermMethod__c'));
    System.assert(apiNames.contains('InvoiceDateAdjust__c'));
    System.assert(apiNames.contains('BillingAddressee__c'));
    System.assert(apiNames.contains('BillingEmailTo__c'));
    System.assert(apiNames.contains('BillingEmailCc__c'));
    System.assert(apiNames.contains('BillingEmailBcc__c'));
    System.assert(!apiNames.contains('Name'));
  }

  @IsTest
  static void getOrderBillingFieldDefinitions_marksRequiredFields() {
    List<ContractWizardFieldService.WizardFieldDefinition> definitions = OrderWizardFieldService.getOrderBillingFieldDefinitions();

    Map<String, Boolean> requiredByApiName = new Map<String, Boolean>();
    for (
      ContractWizardFieldService.WizardFieldDefinition definition : definitions
    ) {
      requiredByApiName.put(definition.apiName, definition.required);
    }
    System.assertEquals(true, requiredByApiName.get('BillingAddressee__c'));
    System.assertEquals(true, requiredByApiName.get('BillingEmailTo__c'));
    System.assertEquals(true, requiredByApiName.get('PaymentTermMethod__c'));
    System.assertEquals(true, requiredByApiName.get('InvoiceDateMethod__c'));
    System.assertEquals(false, requiredByApiName.get('BillingEmailCc__c'));
  }

  @IsTest
  static void validateBillingCustomFields_requiresAddresseeToPaymentTermAndBillingDay() {
    String error = OrderWizardFieldService.validateBillingCustomFields(
      new Map<String, Object>{ 'InvoiceDateAdjust__c' => BillingScheduleService.ADJUST_NONE }
    );
    System.assertNotEquals(null, error);
    System.assert(error.contains('請求先宛名'));
    System.assert(error.contains('請求書送付先（To）'));
    System.assert(error.contains('支払条件の計算方式'));
    System.assert(error.contains('請求日の計算方式'));
  }

  @IsTest
  static void validateBillingCustomFields_requiresAddresseeAndToOnly() {
    String error = OrderWizardFieldService.validateBillingCustomFields(
      new Map<String, Object>{
        'PaymentTermMethod__c' => BillingScheduleService.METHOD_MONTH_OFFSET,
        'PaymentTermAdjust__c' => BillingScheduleService.ADJUST_NONE,
        'InvoiceDateMethod__c' => BillingScheduleService.METHOD_ON_OR_AFTER,
        'InvoiceDateAdjust__c' => BillingScheduleService.ADJUST_NONE
      }
    );
    System.assertNotEquals(null, error);
    System.assert(error.contains('請求先宛名'));
    System.assert(error.contains('請求書送付先（To）'));
  }

  @IsTest
  static void validateBillingCustomFields_acceptsMinimalRequiredPayload() {
    String error = OrderWizardFieldService.validateBillingCustomFields(
      new Map<String, Object>{
        'BillingAddressee__c' => ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        'BillingEmailTo__c' => 'to@example.com',
        'PaymentTermMethod__c' => BillingScheduleService.METHOD_MONTH_OFFSET,
        'PaymentTermAdjust__c' => BillingScheduleService.ADJUST_NONE,
        'InvoiceDateMethod__c' => BillingScheduleService.METHOD_ON_OR_AFTER,
        'InvoiceDateAdjust__c' => BillingScheduleService.ADJUST_NONE
      }
    );
    System.assertEquals(null, error);
  }

  @IsTest
  static void getOrderBillingFieldDefinitions_usesBillingDayRuleLabel() {
    List<ContractWizardFieldService.WizardFieldDefinition> definitions = OrderWizardFieldService.getOrderBillingFieldDefinitions();
    String billingDayLabel = null;
    for (
      ContractWizardFieldService.WizardFieldDefinition definition : definitions
    ) {
      if (definition.apiName == 'InvoiceDateMethod__c') {
        billingDayLabel = definition.label;
        break;
      }
    }
    System.assertEquals('請求日の計算方式', billingDayLabel);
  }

  @IsTest
  static void applyBillingFields_andHistoryHelpers_coverApplyPath() {
    System.assert(
      OrderWizardFieldService.getActiveOrderHistoryFieldApiNames()
        .contains('ApplicationDate__c')
    );

    Account account = ContractTestDataFactory.insertAccount(
      'Order Wizard Field Label Account'
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = '旧宛名',
      BillingEmailTo__c = 'old@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 1,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    OrderWizardFieldService.applyBillingFields(
      billingAccount,
      new Map<String, Object>{
        'BillingAddressee__c' => '新宛名',
        'BillingEmailTo__c' => 'new@example.com',
        'BillingEmailCc__c' => 'cc@example.com',
        'InvoiceDateDayOfMonth__c' => 25,
        'InvoiceDateAdjust__c' => BillingScheduleService.ADJUST_NEXT,
        'Name' => 'ignored'
      }
    );
    System.assertEquals('新宛名', billingAccount.BillingAddressee__c);
    System.assertEquals('new@example.com', billingAccount.BillingEmailTo__c);
    System.assertEquals('cc@example.com', billingAccount.BillingEmailCc__c);
    System.assertEquals(25, billingAccount.InvoiceDateDayOfMonth__c);
    System.assertEquals(
      BillingScheduleService.ADJUST_NEXT,
      billingAccount.InvoiceDateAdjust__c
    );

    ContractService__c service = new ContractService__c(
      Name = 'Order Wizard Field Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Order Wizard Field History',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
      EffectiveDate__c = Date.newInstance(2026, 6, 1)
    );
    insert history;

    Map<String, Object> historyValues = OrderWizardFieldService.buildHistoryFieldValuesForWizard(
      history
    );
    System.assertEquals(
      String.valueOf(Date.today()),
      historyValues.get('OrderDate__c'),
      '受注日の初期値は操作日'
    );
    System.assertEquals(
      null,
      historyValues.get('ApplicationDate__c'),
      '申込日は黙って埋めない'
    );
    OrderWizardFieldService.applyHistoryFields(
      history,
      new Map<String, Object>{
        'ApplicationDate__c' => '2026-06-15',
        'Note__c' => 'ignored'
      }
    );
    System.assertEquals(
      Date.newInstance(2026, 6, 15),
      history.ApplicationDate__c
    );
    System.assertEquals(null, history.Note__c);
  }
}
