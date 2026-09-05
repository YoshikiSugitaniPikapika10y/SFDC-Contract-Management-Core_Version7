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
      System.assertEquals(
        '受注ウィザード追加項目「Bad_Product2」の DefaultSource=Product2 は設定できません。',
        ex.getMessage(),
        'Core 第11.4.3節: Product2 初期値は設定できない'
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
      System.assertEquals(
        '受注ウィザード追加項目「Bad_TodayValue」の DefaultSource=Today に DefaultValue は指定できません。',
        ex.getMessage(),
        'Core 第11.4.3節: Today に DefaultValue は付けない'
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
    System.assertEquals(
      '請求アカウントの必須項目が未設定です。請求アカウントの正規編集画面で設定してください: 請求先宛名、請求書送付先（To）、請求日の計算方式、支払条件の計算方式、支払条件の補正',
      error,
      'Core 第5.2節: 請求アカウント確認の必須はハードコード'
    );
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
    System.assertEquals(
      '請求アカウントの必須項目が未設定です。請求アカウントの正規編集画面で設定してください: 請求先宛名、請求書送付先（To）',
      error,
      'Core 第5.2節: 請求先宛名と送付先Toは必須'
    );
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
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderWizardFieldService.resetCache();
      System.assert(
        OrderWizardFieldService.getActiveOrderHistoryFieldApiNames()
          .contains('ApplicationDate__c')
      );

      Account account = ContractTestDataFactory.insertAccount(
        'Order Wizard Field Label Account'
      );
      BillingAccount__c billingAccount = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );

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
      System.assertEquals(
        '新宛名',
        billingAccount.BillingAddressee__c,
        'Core 第5.2節: 請求アカウント確認の必須はハードコード'
      );
      System.assertEquals('new@example.com', billingAccount.BillingEmailTo__c);
      System.assertEquals('cc@example.com', billingAccount.BillingEmailCc__c);
      System.assertEquals(25, billingAccount.InvoiceDateDayOfMonth__c);
      System.assertEquals(
        BillingScheduleService.ADJUST_NEXT,
        billingAccount.InvoiceDateAdjust__c
      );
      System.assertNotEquals(
        'ignored',
        billingAccount.Name,
        'Core 第11.4.3節: 請求アカウントは受注追加項目の対象外'
      );

      ContractService__c service = new ContractService__c(
        Name = 'Order Wizard Field Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      ContractTestDataFactory.applyRequiredFields(service);
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
      ContractTestDataFactory.applyRequiredFields(history);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      insert history;

      Map<String, Object> historyValues = OrderWizardFieldService.buildHistoryFieldValuesForWizard(
        history
      );
      System.assertEquals(
        String.valueOf(InvoiceTransactionStatusService.organizationToday()),
        historyValues.get('OrderDate__c'),
        'Core 第11.4.3節: 受注日の初期値は操作日'
      );
      System.assertEquals(
        null,
        historyValues.get('ApplicationDate__c'),
        'Core 第11.4.3節: 申込日は初期値なし。前Versionからもコピーしない'
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
      System.assertEquals(
        null,
        history.Note__c,
        'Core 第11.4.3節: 定義に無い項目は保存対象にしない'
      );

      Map<String, Object> saved = OrderWizardFieldService.querySavedHistoryFieldValues(
        history.Id
      );
      System.assertEquals(
        null,
        saved.get('ApplicationDate__c'),
        'Core 第11.4.3節: 保存済みだけ。未保存の申込日へ初期値は載せない'
      );
      System.assertEquals(
        null,
        saved.get('OrderDate__c'),
        'Core 第11.4.3節: 保存済みだけ。空の受注日へ操作日は載せない'
      );
      history.ApplicationDate__c = Date.newInstance(2026, 6, 15);
      update history;
      saved = OrderWizardFieldService.querySavedHistoryFieldValues(history.Id);
      System.assertEquals(
        String.valueOf(Date.newInstance(2026, 6, 15)),
        saved.get('ApplicationDate__c'),
        'Core 第11.4.3節: 既に契約履歴へ保存済みの値がある場合はそれを表示し、初期値で上書きしない'
      );

      OrderWizardFieldService.applyHistoryFields(
        history,
        new Map<String, Object>{ 'ApplicationDate__c' => '' }
      );
      System.assertEquals(
        null,
        history.ApplicationDate__c,
        'Core 第11.4.3節: 表示中の項目を空欄で受注した場合は空を保存する'
      );
    }
  }

  @IsTest
  static void querySavedHistoryFieldValues_nullId_returnsEmpty() {
    Map<String, Object> saved = OrderWizardFieldService.querySavedHistoryFieldValues(
      null
    );
    System.assertEquals(true, saved.isEmpty());
  }

  @IsTest
  static void getDefinitions_changeAndCancel_includeApplicationDate() {
    OrderWizardFieldService.resetCache();
    Set<String> changeApis = new Set<String>();
    for (
      ContractWizardFieldService.WizardFieldDefinition definition : OrderWizardFieldService.getDefinitions(
        'Change'
      )
    ) {
      changeApis.add(definition.apiName);
    }
    Set<String> cancelApis = new Set<String>();
    for (
      ContractWizardFieldService.WizardFieldDefinition definition : OrderWizardFieldService.getDefinitions(
        'Cancel'
      )
    ) {
      cancelApis.add(definition.apiName);
    }
    System.assertEquals(
      true,
      changeApis.contains('ApplicationDate__c'),
      'Core 第11.4.3節: 標準定義は全種別'
    );
    System.assertEquals(
      true,
      cancelApis.contains('ApplicationDate__c'),
      'Core 第11.4.3節: Cancelでも表示対象の項目を出す'
    );
  }

  @IsTest
  static void applyHistoryFields_hiddenType_keepsExisting() {
    OrderWizardFieldService.setCachedDefinitionsForTest(
      new List<OrderWizardField__mdt>{
        new OrderWizardField__mdt(
          DeveloperName = 'Order_ApplicationDate',
          MasterLabel = '申込日',
          FieldApiName__c = 'ApplicationDate__c',
          Required__c = true,
          Active__c = true,
          ShowOnNew__c = true,
          ShowOnChange__c = false
        )
      }
    );
    ContractHistory__c history = new ContractHistory__c(
      Type__c = 'Change',
      ApplicationDate__c = Date.newInstance(2026, 1, 10)
    );
    OrderWizardFieldService.applyHistoryFields(
      history,
      new Map<String, Object>{ 'ApplicationDate__c' => '2026-06-15' }
    );
    System.assertEquals(
      Date.newInstance(2026, 1, 10),
      history.ApplicationDate__c,
      'Core 第11.4.3節: 見積種別により非表示となった項目は保存対象にせず既存値を維持する'
    );
    String requiredError = OrderWizardFieldService.validateRequiredHistoryFields(
      new Map<String, Object>(),
      'Change'
    );
    System.assertEquals(
      null,
      requiredError,
      'Core 第11.4.3節: 必須は画面に表示されている場合だけ'
    );
    OrderWizardFieldService.resetCache();
  }

  @IsTest
  static void buildHistoryFieldValuesForWizard_usesOpportunityDefaultWhenBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderWizardFieldService.setCachedDefinitionsForTest(
        new List<OrderWizardField__mdt>{
          new OrderWizardField__mdt(
            DeveloperName = 'Order_EstimateTitle',
            MasterLabel = '見積件名',
            FieldApiName__c = 'EstimateTitleName__c',
            Active__c = true,
            DefaultSource__c = 'Opportunity',
            DefaultValue__c = 'Name',
            ShowOnNew__c = true
          )
        }
      );
      Account account = ContractTestDataFactory.insertAccount(
        'Order Wizard Opportunity Default Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        '商談件名の初期値'
      );
      opportunity = [SELECT Id, Name FROM Opportunity WHERE Id = :opportunity.Id];
      ContractService__c service = new ContractService__c(
        Name = 'Order Wizard Opportunity Default Service',
        Account__c = account.Id
      );
      ContractTestDataFactory.applyRequiredFields(service);
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Order Wizard Opportunity Default History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        Opportunity__c = opportunity.Id,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      ContractTestDataFactory.applyRequiredFields(history);
      insert history;
      history = [
        SELECT Id, Type__c, Opportunity__c, EstimateTitleName__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      Map<String, Object> values = OrderWizardFieldService.buildHistoryFieldValuesForWizard(
        history
      );
      System.assertEquals(
        opportunity.Name,
        values.get('EstimateTitleName__c'),
        'Core 第11.4.3節: 初期値 Opportunity は商談の項目。保存済みが空のときだけ'
      );
      OrderWizardFieldService.resetCache();
    }
  }

  @IsTest
  static void validateActiveDefinitions_unknownSource_includesDeveloperName() {
    OrderWizardFieldService.setCachedDefinitionsForTest(
      new List<OrderWizardField__mdt>{
        new OrderWizardField__mdt(
          DeveloperName = 'Bad_Source',
          MasterLabel = '不正',
          FieldApiName__c = 'ApplicationDate__c',
          Active__c = true,
          DefaultSource__c = 'Unknown',
          ShowOnNew__c = true
        )
      }
    );
    Boolean failed = false;
    try {
      OrderWizardFieldService.getDefinitions('New');
    } catch (AuraHandledException ex) {
      failed = true;
      System.assertEquals(
        '受注ウィザード追加項目「Bad_Source」の DefaultSource「Unknown」は未対応です。空欄（静的）/ Today / Opportunity / Account のいずれかを指定してください。',
        ex.getMessage(),
        'Core 第11.4.3節: 未対応 DefaultSource は DeveloperName を含める'
      );
    }
    System.assertEquals(true, failed);
    OrderWizardFieldService.resetCache();
  }

  @IsTest
  static void validateRequiredHistoryFields_nullMap_requiresApplicationDate() {
    OrderWizardFieldService.resetCache();
    String error = OrderWizardFieldService.validateRequiredHistoryFields(
      null,
      'New'
    );
    System.assertNotEquals(null, error);
    System.assert(error.contains('申込日'), error);
  }

  @IsTest
  static void applyHistoryFields_nullHistory_doesNotThrow() {
    OrderWizardFieldService.applyHistoryFields(null, new Map<String, Object>());
    OrderWizardFieldService.applyBillingFields(
      null,
      new Map<String, Object>{ 'BillingAddressee__c' => 'x' }
    );
    String billingError = OrderWizardFieldService.validateBillingCustomFields(
      null
    );
    System.assertEquals(
      '請求アカウントの必須項目が未設定です。請求アカウントの正規編集画面で設定してください: 請求先宛名、請求書送付先（To）、請求日の計算方式、請求日の補正、支払条件の計算方式、支払条件の補正',
      billingError,
      'Core 第5.2節: 未入力は正規編集へ誘導する'
    );
  }
}
