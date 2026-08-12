@IsTest
private class OrderWizardFieldServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void getOrderHistoryFieldDefinitions_returnsNoFields() {
    // 受注ウィザードでは Note__c を扱わない（見積の備考をそのまま引き継ぐため）。
    OrderWizardFieldService.resetCache();
    List<ContractWizardFieldService.WizardFieldDefinition> definitions = OrderWizardFieldService.getOrderHistoryFieldDefinitions();

    System.assertEquals(0, definitions.size());
  }

  @IsTest
  static void getOrderHistoryFieldDefinitions_doesNotIncludeNote() {
    List<ContractWizardFieldService.WizardFieldDefinition> definitions = OrderWizardFieldService.getOrderHistoryFieldDefinitions();

    Set<String> apiNames = new Set<String>();
    for (
      ContractWizardFieldService.WizardFieldDefinition definition : definitions
    ) {
      apiNames.add(definition.apiName);
    }
    System.assert(!apiNames.contains('Note__c'));
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
    System.assert(apiNames.contains('PaymentTerm__c'));
    System.assert(apiNames.contains('BillingDayOfMonth__c'));
    System.assert(apiNames.contains('AdjustInvoiceDateToBusinessDay__c'));
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
    System.assertEquals(true, requiredByApiName.get('PaymentTerm__c'));
    System.assertEquals(true, requiredByApiName.get('BillingDayOfMonth__c'));
    System.assertEquals(false, requiredByApiName.get('BillingEmailCc__c'));
  }

  @IsTest
  static void validateBillingCustomFields_requiresAddresseeToPaymentTermAndBillingDay() {
    String error = OrderWizardFieldService.validateBillingCustomFields(
      new Map<String, Object>{ 'AdjustInvoiceDateToBusinessDay__c' => false }
    );
    System.assertNotEquals(null, error);
    System.assert(error.contains('請求先宛名'));
    System.assert(error.contains('請求書送付先（To）'));
    System.assert(error.contains('支払サイト'));
    System.assert(error.contains('請求日ルール'));
  }

  @IsTest
  static void validateBillingCustomFields_requiresAddresseeAndToOnly() {
    String error = OrderWizardFieldService.validateBillingCustomFields(
      new Map<String, Object>{
        'PaymentTerm__c' => ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        'BillingDayOfMonth__c' => '15',
        'AdjustInvoiceDateToBusinessDay__c' => false
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
        'PaymentTerm__c' => ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        'BillingDayOfMonth__c' => '15',
        'AdjustInvoiceDateToBusinessDay__c' => false
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
      if (definition.apiName == 'BillingDayOfMonth__c') {
        billingDayLabel = definition.label;
        break;
      }
    }
    System.assertEquals('請求日ルール', billingDayLabel);
  }

  @IsTest
  static void applyBillingFields_andHistoryHelpers_coverApplyPath() {
    System.assertEquals(
      0,
      OrderWizardFieldService.getActiveOrderHistoryFieldApiNames().size()
    );

    Account account = ContractTestDataFactory.insertAccount(
      'Order Wizard Field Label Account'
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = '旧宛名',
      BillingEmailTo__c = 'old@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_1,
      AdjustInvoiceDateToBusinessDay__c = false
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    OrderWizardFieldService.applyBillingFields(
      billingAccount,
      new Map<String, Object>{
        'BillingAddressee__c' => '新宛名',
        'BillingEmailTo__c' => 'new@example.com',
        'BillingEmailCc__c' => 'cc@example.com',
        'BillingDayOfMonth__c' => '25',
        'AdjustInvoiceDateToBusinessDay__c' => true,
        'Name' => 'ignored'
      }
    );
    System.assertEquals('新宛名', billingAccount.BillingAddressee__c);
    System.assertEquals('new@example.com', billingAccount.BillingEmailTo__c);
    System.assertEquals('cc@example.com', billingAccount.BillingEmailCc__c);
    System.assertEquals('25', billingAccount.BillingDayOfMonth__c);
    System.assertEquals(true, billingAccount.AdjustInvoiceDateToBusinessDay__c);

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

    Map<String, Object> historyValues = OrderWizardFieldService.buildHistoryCustomFieldValues(
      history
    );
    System.assertEquals(0, historyValues.size());
    OrderWizardFieldService.applyHistoryFields(
      history,
      new Map<String, Object>{ 'Note__c' => 'ignored' }
    );
    System.assertEquals(null, history.Note__c);
  }
}
