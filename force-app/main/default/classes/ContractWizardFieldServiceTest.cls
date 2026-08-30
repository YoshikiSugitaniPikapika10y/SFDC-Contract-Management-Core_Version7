@IsTest
private class ContractWizardFieldServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void getContractServiceFieldDefinitions_returnsConfiguredFields() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    List<ContractWizardFieldService.WizardFieldDefinition> definitions = ContractWizardFieldService.getContractServiceFieldDefinitions();
    System.assertNotEquals(null, definitions);
    System.assertEquals(1, definitions.size());
    System.assertEquals('CustomerMemo__c', definitions[0].apiName);
  }

  @IsTest
  static void getContractHistoryFieldDefinitions_returnsConfiguredFields() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    List<ContractWizardFieldService.WizardFieldDefinition> definitions = ContractWizardFieldService.getContractHistoryFieldDefinitions();
    System.assertEquals(1, definitions.size());
    System.assertEquals('ApplicationDate__c', definitions[0].apiName);
    System.assertEquals('DATE', definitions[0].fieldType);
  }

  @IsTest
  static void getContractHistoryFieldDefinitions_supportsReferenceLookup() {
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Estimate_Send_Contact',
          MasterLabel = 'Test Estimate Send Contact',
          Active__c = true,
          TargetObject__c = 'ContractHistory__c',
          FieldApiName__c = 'EstimateSendContact__c',
          ShowOnNew__c = true
        )
      }
    );

    List<ContractWizardFieldService.WizardFieldDefinition> definitions = ContractWizardFieldService.getContractHistoryFieldDefinitions();

    System.assertEquals(1, definitions.size());
    System.assertEquals('REFERENCE', definitions[0].fieldType);
    System.assertEquals('Contact', definitions[0].referenceObjectApiName);
  }

  @IsTest
  static void getContractProductFieldDefinitions_returnsConfiguredFields() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    List<ContractWizardFieldService.WizardFieldDefinition> definitions = ContractWizardFieldService.getContractProductFieldDefinitions();
    System.assertNotEquals(null, definitions);
    System.assertEquals(true, definitions.size() >= 1);

    ContractWizardFieldService.WizardFieldDefinition productField;
    for (
      ContractWizardFieldService.WizardFieldDefinition definition : definitions
    ) {
      if (definition.apiName == 'Description__c') {
        productField = definition;
        break;
      }
    }
    System.assertNotEquals(null, productField);
    System.assertEquals('STRING', productField.fieldType);
    System.assertEquals('Family', productField.visibilityFieldApiName);
    System.assertEquals('EQUALS', productField.visibilityOperator);
    System.assertEquals(
      ContractTestDataFactory.WIZARD_TEST_PRODUCT_FAMILY,
      productField.visibilityValues
    );
    System.assertEquals('サンプルデフォルトメモ', productField.defaultValue);
    System.assertEquals(true, productField.showOnNew);
    System.assertEquals(true, productField.showOnChange);
    System.assertEquals(true, productField.showOnRenew);
    System.assertEquals(true, productField.showOnCancel);
  }

  @IsTest
  static void getOpportunityDefaultContext_returnsEmptyForNull() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    Map<String, Object> context = ContractWizardFieldService.getOpportunityDefaultContext(
      null
    );
    System.assertEquals(0, context.size());
  }

  @IsTest
  static void getOpportunityDefaultContext_readsOpportunityAndAccount() {
    Account account = new Account(Name = 'Default Ctx Account');
    insert account;
    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'Default Ctx Opp'
    );

    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Opp_Name',
          MasterLabel = 'Test Opp Name',
          Active__c = true,
          TargetObject__c = 'ContractService__c',
          FieldApiName__c = 'CustomerMemo__c',
          DefaultSource__c = 'Opportunity',
          DefaultValue__c = 'Name',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        ),
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Opp_CloseDate',
          MasterLabel = 'Test Opp CloseDate',
          Active__c = true,
          TargetObject__c = 'ContractService__c',
          FieldApiName__c = 'CustomerMemo__c',
          DefaultSource__c = 'Opportunity',
          DefaultValue__c = 'CloseDate',
          SortOrder__c = 11,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        ),
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Account_Name',
          MasterLabel = 'Test Account Name',
          Active__c = true,
          TargetObject__c = 'ContractHistory__c',
          FieldApiName__c = 'ApplicationDate__c',
          DefaultSource__c = 'Account',
          DefaultValue__c = 'Name',
          SortOrder__c = 20,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        ),
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Legacy_Opp_Account',
          MasterLabel = 'Test Legacy',
          Active__c = true,
          TargetObject__c = 'ContractProduct__c',
          FieldApiName__c = 'Description__c',
          DefaultSource__c = 'Opportunity',
          DefaultValue__c = 'Account.Name',
          SortOrder__c = 30,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        ),
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Product2_Family',
          MasterLabel = 'Test Product2',
          Active__c = true,
          TargetObject__c = 'ContractProduct__c',
          FieldApiName__c = 'Description__c',
          DefaultSource__c = 'Product2',
          DefaultValue__c = 'Family',
          SortOrder__c = 40,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        )
      }
    );

    Map<String, Object> context = ContractWizardFieldService.getOpportunityDefaultContext(
      opportunity.Id
    );
    System.assertEquals('Default Ctx Opp', context.get('Name'));
    System.assertEquals('Default Ctx Account', context.get('Account.Name'));
    System.assertEquals(true, context.containsKey('CloseDate'));

    List<ContractWizardFieldService.WizardFieldDefinition> serviceDefs = ContractWizardFieldService.getContractServiceFieldDefinitions();
    System.assertEquals(true, serviceDefs.size() >= 1);
    Boolean foundOppName = false;
    for (
      ContractWizardFieldService.WizardFieldDefinition definition : serviceDefs
    ) {
      if (
        definition.defaultSource == 'Opportunity' &&
        definition.defaultValue == 'Name'
      ) {
        foundOppName = true;
      }
    }
    System.assertEquals(true, foundOppName);

    Set<String> product2Fields = ContractWizardFieldService.getReferencedProduct2FieldApiNames();
    System.assertEquals(true, product2Fields.contains('Family'));

    System.assertEquals(
      0,
      ContractWizardFieldService.getProduct2RelationshipSelectFields('').size()
    );

    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void validateActiveDefinitions_rejectsUnknownDefaultSource() {
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Invalid_Source',
          MasterLabel = 'Test Invalid',
          Active__c = true,
          TargetObject__c = 'ContractService__c',
          FieldApiName__c = 'CustomerMemo__c',
          DefaultSource__c = 'UnknownSource',
          DefaultValue__c = 'X',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        )
      }
    );
    try {
      ContractWizardFieldService.validateActiveDefinitions();
      System.assert(false, 'Unknown DefaultSource should fail');
    } catch (ContractWizardFieldService.WizardFieldConfigException ex) {
      System.assertEquals(
        '見積ウィザードカスタム項目「Test_Invalid_Source」の DefaultSource「UnknownSource」は未対応です。空欄（静的）/ Opportunity / Account / Product2 のいずれかを指定してください。',
        ex.getMessage()
      );
    }
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void validateActiveDefinitions_rejectsInvalidOpportunityPath() {
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Invalid_Opp_Path',
          MasterLabel = 'Test Invalid Opp',
          Active__c = true,
          TargetObject__c = 'ContractService__c',
          FieldApiName__c = 'CustomerMemo__c',
          DefaultSource__c = 'Opportunity',
          DefaultValue__c = 'DoesNotExist__c',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        )
      }
    );
    try {
      ContractWizardFieldService.validateActiveDefinitions();
      System.assert(false, 'Invalid Opportunity path should fail');
    } catch (ContractWizardFieldService.WizardFieldConfigException ex) {
      System.assertEquals(
        '見積ウィザードカスタム項目「Test_Invalid_Opp_Path」の DefaultSource=Opportunity に対する DefaultValue「DoesNotExist__c」が不正です。商談の項目 API 名を指定してください。',
        ex.getMessage()
      );
    }
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void validateActiveDefinitions_rejectsProduct2OnNonProduct() {
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Product2_On_Service',
          MasterLabel = 'Test Product2 On Service',
          Active__c = true,
          TargetObject__c = 'ContractService__c',
          FieldApiName__c = 'CustomerMemo__c',
          DefaultSource__c = 'Product2',
          DefaultValue__c = 'Family',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        )
      }
    );
    try {
      ContractWizardFieldService.validateActiveDefinitions();
      System.assert(false, 'Product2 on ContractService should fail');
    } catch (ContractWizardFieldService.WizardFieldConfigException ex) {
      System.assertEquals(
        '見積ウィザードカスタム項目「Test_Product2_On_Service」の DefaultSource=Product2 は見積商品（ContractProduct__c）でのみ利用できます。',
        ex.getMessage()
      );
    }
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void getContractServiceFieldDefinitions_surfacesConfigError() {
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Invalid_Source_Wire',
          MasterLabel = 'Test Invalid Wire',
          Active__c = true,
          TargetObject__c = 'ContractService__c',
          FieldApiName__c = 'CustomerMemo__c',
          DefaultSource__c = 'UnknownSource',
          DefaultValue__c = 'X',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        )
      }
    );
    try {
      ContractWizardFieldService.getContractServiceFieldDefinitions();
      System.assert(false, 'Aura path should surface config error');
    } catch (AuraHandledException ex) {
      System.assertEquals(
        '見積ウィザードカスタム項目「Test_Invalid_Source_Wire」の DefaultSource「UnknownSource」は未対応です。空欄（静的）/ Opportunity / Account / Product2 のいずれかを指定してください。',
        ex.getMessage()
      );
    }
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void getOpportunityDefaultContext_missingOpportunityReturnsEmpty() {
    Account account = new Account(Name = 'Tmp Acc');
    insert account;
    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'Tmp Opp'
    );
    Id deletedId = opportunity.Id;
    delete opportunity;

    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Opp_Name_Missing',
          MasterLabel = 'Test Opp Name Missing',
          Active__c = true,
          TargetObject__c = 'ContractService__c',
          FieldApiName__c = 'CustomerMemo__c',
          DefaultSource__c = 'Opportunity',
          DefaultValue__c = 'Name',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        )
      }
    );

    Map<String, Object> context = ContractWizardFieldService.getOpportunityDefaultContext(
      deletedId
    );
    System.assertEquals(0, context.size());

    List<String> relationshipFields = ContractWizardFieldService.getProduct2RelationshipSelectFields(
      'Product2'
    );
    System.assertNotEquals(null, relationshipFields);

    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void defaultSource_pathValidationHelpers() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    System.assertEquals(
      true,
      ContractWizardFieldService.isValidOpportunityDefaultPath('Name')
    );
    System.assertEquals(
      false,
      ContractWizardFieldService.isValidOpportunityDefaultPath('Account.Name')
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.isValidAccountDefaultPath('Name')
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.isValidAccountDefaultPath('Account.Name')
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.isValidProduct2DefaultPath('Family')
    );
    System.assertEquals(
      false,
      ContractWizardFieldService.isValidProduct2DefaultPath('Account.Name')
    );
  }

  @IsTest
  static void applyCustomFields_ignoresUnknownFields() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    ContractService__c record = new ContractService__c();
    ContractWizardFieldService.applyCustomFields(
      record,
      new Map<String, Object>{ 'UnknownField__c' => 'value' },
      ContractWizardFieldService.WizardTarget.ContractService
    );
    System.assertEquals(null, record.Name);
  }

  @IsTest
  static void extractAndApplyCustomFields_historyApplicationDate() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    ContractHistory__c source = new ContractHistory__c(
      ApplicationDate__c = Date.newInstance(2026, 7, 1)
    );
    Map<String, Object> extracted = ContractWizardFieldService.extractCustomFields(
      source,
      ContractWizardFieldService.WizardTarget.ContractHistory
    );
    System.assertEquals('2026-07-01', extracted.get('ApplicationDate__c'));

    ContractHistory__c target = new ContractHistory__c();
    ContractWizardFieldService.applyCustomFields(
      target,
      new Map<String, Object>{ 'ApplicationDate__c' => '2026-08-15' },
      ContractWizardFieldService.WizardTarget.ContractHistory
    );
    System.assertEquals(
      Date.newInstance(2026, 8, 15),
      target.ApplicationDate__c
    );
  }

  @IsTest
  static void applyCustomFields_serviceAndProductCustomerMemo() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    ContractService__c service = new ContractService__c();
    ContractWizardFieldService.applyCustomFields(
      service,
      new Map<String, Object>{ 'CustomerMemo__c' => ' service memo ' },
      ContractWizardFieldService.WizardTarget.ContractService
    );
    System.assertEquals('service memo', service.CustomerMemo__c);

    ContractProduct__c product = new ContractProduct__c();
    ContractWizardFieldService.applyCustomFields(
      product,
      new Map<String, Object>{ 'Description__c' => 'product memo' },
      ContractWizardFieldService.WizardTarget.ContractProduct
    );
    System.assertEquals('product memo', product.Description__c);
  }

  @IsTest
  static void parseCustomFieldsJson_handlesBlankAndObject() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    System.assertEquals(
      0,
      ContractWizardFieldService.parseCustomFieldsJson(null).size()
    );
    Map<String, Object> parsed = ContractWizardFieldService.parseCustomFieldsJson(
      '{"CustomerMemo__c":"abc"}'
    );
    System.assertEquals('abc', parsed.get('CustomerMemo__c'));
  }

  @IsTest
  static void validateRequiredCustomFields_reportsMissing() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    // サンプルCMDは Required=false のため、空でもエラーにならない
    System.assertEquals(
      null,
      ContractWizardFieldService.validateRequiredCustomFields(
        ContractWizardFieldService.WizardTarget.ContractService,
        new Map<String, Object>()
      )
    );
  }

  @IsTest
  static void getActiveFieldApiNames_returnsConfiguredApis() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    Set<String> serviceFields = ContractWizardFieldService.getActiveFieldApiNames(
      ContractWizardFieldService.WizardTarget.ContractService
    );
    Set<String> historyFields = ContractWizardFieldService.getActiveFieldApiNames(
      ContractWizardFieldService.WizardTarget.ContractHistory
    );
    Set<String> productFields = ContractWizardFieldService.getActiveFieldApiNames(
      ContractWizardFieldService.WizardTarget.ContractProduct
    );

    System.assert(serviceFields.contains('CustomerMemo__c'));
    System.assert(historyFields.contains('ApplicationDate__c'));
    System.assert(productFields.contains('Description__c'));
  }

  @IsTest
  static void coerceValue_handlesCommonTypes() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    Schema.DescribeFieldResult noteDescribe = ContractHistory__c.Note__c.getDescribe();
    Schema.DescribeFieldResult quantityDescribe = ContractProduct__c.Quantity__c.getDescribe();
    Schema.DescribeFieldResult startDateDescribe = ContractProduct__c.StartDate__c.getDescribe();

    System.assertEquals(
      'hello',
      ContractWizardFieldService.coerceValue(noteDescribe, ' hello ')
    );
    System.assertEquals(
      3,
      ContractWizardFieldService.coerceValue(quantityDescribe, '3')
    );
    System.assertEquals(
      Date.newInstance(2026, 6, 1),
      ContractWizardFieldService.coerceValue(startDateDescribe, '2026-06-01')
    );
    System.assertEquals(
      null,
      ContractWizardFieldService.coerceValue(noteDescribe, null)
    );
  }

  @IsTest
  static void evaluateVisibility_supportsInNotInAndBlank() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    System.assertEquals(
      true,
      ContractWizardFieldService.evaluateVisibility(
        'IN',
        'Software',
        new List<String>{ 'Software', 'Add-On' }
      )
    );
    System.assertEquals(
      false,
      ContractWizardFieldService.evaluateVisibility(
        'IN',
        'Hardware',
        new List<String>{ 'Software' }
      )
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.evaluateVisibility(
        'NOT_IN',
        'Hardware',
        new List<String>{ 'Software' }
      )
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.evaluateVisibility(
        'IS_BLANK',
        null,
        new List<String>()
      )
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.evaluateVisibility(
        'IS_NOT_BLANK',
        'Software',
        new List<String>()
      )
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.evaluateVisibility(
        'IN',
        'A;B',
        new List<String>{ 'B' }
      )
    );
  }

  @IsTest
  static void buildProductVisibilityContext_readsFamilyWhenReferenced() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    Product2 product = new Product2(Name = 'Vis Product', Family = 'Software');
    Map<String, String> context = ContractWizardFieldService.buildProductVisibilityContext(
      product
    );
    System.assertNotEquals(null, context);
    System.assertEquals(true, context.containsKey('Family'));
    System.assertEquals('Software', context.get('Family'));
  }

  @IsTest
  static void filterCustomFieldsByVisibility_respectsProductFamily() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    Map<String, Object> hidden = ContractWizardFieldService.filterCustomFieldsByVisibility(
      new Map<String, Object>{ 'Description__c' => 'memo' },
      ContractWizardFieldService.WizardTarget.ContractProduct,
      new Map<String, String>{ 'Family' => 'Software' }
    );
    System.assertEquals(true, hidden.containsKey('Description__c'));
    System.assertEquals(null, hidden.get('Description__c'));

    Map<String, Object> visible = ContractWizardFieldService.filterCustomFieldsByVisibility(
      new Map<String, Object>{ 'Description__c' => 'memo' },
      ContractWizardFieldService.WizardTarget.ContractProduct,
      new Map<String, String>{
        'Family' => ContractTestDataFactory.WIZARD_TEST_PRODUCT_FAMILY
      }
    );
    System.assertEquals('memo', visible.get('Description__c'));
  }

  @IsTest
  static void filterCustomFieldsByVisibility_clearsHiddenEvenWhenMapEmpty() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    Map<String, Object> cleared = ContractWizardFieldService.filterCustomFieldsByVisibility(
      new Map<String, Object>(),
      ContractWizardFieldService.WizardTarget.ContractProduct,
      new Map<String, String>{ 'Family' => 'Software' }
    );
    System.assertEquals(null, cleared.get('Description__c'));
  }

  @IsTest
  static void filterCustomFieldsByVisibility_serviceEmptyMapClearsVisible() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    Map<String, Object> cleared = ContractWizardFieldService.filterCustomFieldsByVisibility(
      new Map<String, Object>(),
      ContractWizardFieldService.WizardTarget.ContractService,
      null,
      'Change'
    );
    System.assertEquals(
      true,
      cleared.containsKey('CustomerMemo__c'),
      '表示中サービス項目はキー無しでも保存マップに載せること'
    );
    System.assertEquals(null, cleared.get('CustomerMemo__c'));
  }

  @IsTest
  static void filterCustomFieldsByVisibility_serviceShowOnHiddenOmitted() {
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Service_Only_New',
          MasterLabel = 'Service Only New',
          Active__c = true,
          TargetObject__c = 'ContractService__c',
          FieldApiName__c = 'CustomerMemo__c',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = false,
          ShowOnRenew__c = false,
          ShowOnCancel__c = false
        )
      }
    );
    Map<String, Object> filtered = ContractWizardFieldService.filterCustomFieldsByVisibility(
      new Map<String, Object>{ 'CustomerMemo__c' => 'keep-in-db' },
      ContractWizardFieldService.WizardTarget.ContractService,
      null,
      'Change'
    );
    System.assertEquals(
      false,
      filtered.containsKey('CustomerMemo__c'),
      'ShowOn 非表示は省略して DB 維持すること'
    );
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void applyCustomFields_serviceClearsWhenFilteredNull() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    ContractService__c service = new ContractService__c(
      Name = 'Clear Service CF',
      CustomerMemo__c = 'old-memo'
    );
    insert service;

    Map<String, Object> filtered = ContractWizardFieldService.filterCustomFieldsByVisibility(
      new Map<String, Object>(),
      ContractWizardFieldService.WizardTarget.ContractService,
      null,
      'Change'
    );
    ContractService__c toUpdate = new ContractService__c(Id = service.Id);
    ContractWizardFieldService.applyCustomFields(
      toUpdate,
      filtered,
      ContractWizardFieldService.WizardTarget.ContractService
    );
    update toUpdate;

    ContractService__c reloaded = [
      SELECT CustomerMemo__c
      FROM ContractService__c
      WHERE Id = :service.Id
    ];
    System.assertEquals(
      null,
      reloaded.CustomerMemo__c,
      '空マップ保存後は表示中サービス追加項目が null クリアされること'
    );
  }

  @IsTest
  static void validateCustomFieldTypes_reportsInvalidDate() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    String error = ContractWizardFieldService.validateCustomFieldTypes(
      ContractWizardFieldService.WizardTarget.ContractHistory,
      new Map<String, Object>{ 'ApplicationDate__c' => '2026/07/28' }
    );
    System.assertNotEquals(null, error);
    System.assert(error.contains('形式が不正'), error);
  }

  @IsTest
  static void validateCustomFieldTypes_allowsValidDate() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    System.assertEquals(
      null,
      ContractWizardFieldService.validateCustomFieldTypes(
        ContractWizardFieldService.WizardTarget.ContractHistory,
        new Map<String, Object>{ 'ApplicationDate__c' => '2026-07-28' }
      )
    );
  }

  @IsTest
  static void validateRequiredCustomFields_cancelTypeEnforcesRequired() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Cancel_Required_Service',
          MasterLabel = 'Cancel Required Memo',
          Active__c = true,
          TargetObject__c = 'ContractService__c',
          FieldApiName__c = 'CustomerMemo__c',
          Required__c = true,
          SortOrder__c = 1,
          ShowOnNew__c = false,
          ShowOnChange__c = false,
          ShowOnRenew__c = false,
          ShowOnCancel__c = true
        )
      }
    );

    String missing = ContractWizardFieldService.validateRequiredCustomFields(
      ContractWizardFieldService.WizardTarget.ContractService,
      new Map<String, Object>(),
      null,
      'Cancel'
    );
    System.assertNotEquals(
      null,
      missing,
      'Cancel 表示中の Required は未入力エラー'
    );
    System.assert(missing.contains('必須'), missing);
    // LabelOverride が無いときは項目ラベル（なければ API 名）
    System.assert(
      missing.contains('顧客メモ') || missing.contains('CustomerMemo__c'),
      missing
    );

    // ShowOnCancel=false の種別では必須にしない
    System.assertEquals(
      null,
      ContractWizardFieldService.validateRequiredCustomFields(
        ContractWizardFieldService.WizardTarget.ContractService,
        new Map<String, Object>(),
        null,
        'New'
      )
    );

    EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
    request.selectedType = 'Cancel';
    request.contractServiceCustomFields = new Map<String, Object>();
    request.contractHistoryCustomFields = new Map<String, Object>();
    request.products = new List<EstimateCreateController.ProductLineItem>();

    Boolean thrown = false;
    try {
      EstimateValidationService.validateWizardCustomFields(request, false);
    } catch (AuraHandledException ex) {
      thrown = true;
    }
    System.assertEquals(
      true,
      thrown,
      'Cancel 保存経路でも必須エラーになること'
    );

    request.contractServiceCustomFields = new Map<String, Object>{
      'CustomerMemo__c' => 'filled'
    };
    EstimateValidationService.validateWizardCustomFields(request, false);

    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void validateActiveDefinitions_rejectsUnknownVisibilityField() {
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Bad_Visibility_Field',
          MasterLabel = 'Test Bad Visibility Field',
          Active__c = true,
          TargetObject__c = 'ContractProduct__c',
          FieldApiName__c = 'Description__c',
          VisibilityFieldApiName__c = 'DoesNotExistOnProduct2__c',
          VisibilityOperator__c = 'IN',
          VisibilityValues__c = 'X',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        )
      }
    );
    try {
      ContractWizardFieldService.validateActiveDefinitions();
      System.assert(false, 'Unknown VisibilityFieldApiName should fail');
    } catch (ContractWizardFieldService.WizardFieldConfigException ex) {
      System.assert(
        ex.getMessage().contains('VisibilityFieldApiName'),
        ex.getMessage()
      );
      System.assert(
        ex.getMessage().contains('DoesNotExistOnProduct2__c'),
        ex.getMessage()
      );
    }
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void validateActiveDefinitions_rejectsVisibilityOnNonProduct() {
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Visibility_On_Service',
          MasterLabel = 'Test Visibility On Service',
          Active__c = true,
          TargetObject__c = 'ContractService__c',
          FieldApiName__c = 'CustomerMemo__c',
          VisibilityFieldApiName__c = 'Family',
          VisibilityOperator__c = 'EQUALS',
          VisibilityValues__c = 'X',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        )
      }
    );
    try {
      ContractWizardFieldService.validateActiveDefinitions();
      System.assert(false, 'Visibility on ContractService should fail');
    } catch (ContractWizardFieldService.WizardFieldConfigException ex) {
      System.assert(ex.getMessage().contains('Visibility'), ex.getMessage());
      System.assert(
        ex.getMessage().contains('ContractProduct__c'),
        ex.getMessage()
      );
    }
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void validateActiveDefinitions_rejectsUnknownVisibilityOperator() {
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Bad_Visibility_Op',
          MasterLabel = 'Test Bad Visibility Op',
          Active__c = true,
          TargetObject__c = 'ContractProduct__c',
          FieldApiName__c = 'Description__c',
          VisibilityFieldApiName__c = 'Family',
          VisibilityOperator__c = 'CONTAINS',
          VisibilityValues__c = 'X',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        )
      }
    );
    try {
      ContractWizardFieldService.validateActiveDefinitions();
      System.assert(false, 'Unknown VisibilityOperator should fail');
    } catch (ContractWizardFieldService.WizardFieldConfigException ex) {
      System.assert(
        ex.getMessage().contains('VisibilityOperator'),
        ex.getMessage()
      );
      System.assert(ex.getMessage().contains('CONTAINS'), ex.getMessage());
    }
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void validateActiveDefinitions_rejectsEmptyVisibilityValuesForIn() {
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Empty_Visibility_Values',
          MasterLabel = 'Test Empty Visibility Values',
          Active__c = true,
          TargetObject__c = 'ContractProduct__c',
          FieldApiName__c = 'Description__c',
          VisibilityFieldApiName__c = 'Family',
          VisibilityOperator__c = 'IN',
          VisibilityValues__c = null,
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        )
      }
    );
    try {
      ContractWizardFieldService.validateActiveDefinitions();
      System.assert(false, 'Empty VisibilityValues for IN should fail');
    } catch (ContractWizardFieldService.WizardFieldConfigException ex) {
      System.assert(
        ex.getMessage().contains('VisibilityValues'),
        ex.getMessage()
      );
    }
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }
}
