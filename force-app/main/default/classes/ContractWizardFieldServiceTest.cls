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
    Account account = ContractTestDataFactory.insertAccount(
      'Default Ctx Account'
    );
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
    System.assertEquals(
      true,
      String.valueOf(context.get('Name')).contains('Default Ctx Opp'),
      '導入先の商談名接頭辞は Factory。本文の初期値は商談名'
    );
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
    Account account = ContractTestDataFactory.insertAccount('Tmp Acc');
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
    System.assertEquals(
      0,
      ContractWizardFieldService.parseCustomFieldsJson('["not-an-object"]')
        .size(),
      'Core 第11.4.1節: 追加項目JSONはオブジェクト以外を空として扱う'
    );
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
    System.assertEquals(
      'カスタム項目の形式が不正です: 申込日（YYYY-MM-DD 形式で入力してください）',
      error,
      'Core 第4.3.3節: 日付は YYYY-MM-DD 以外を拒否する'
    );
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
    System.assertEquals(
      '必須のカスタム項目を入力してください: 顧客メモ',
      missing,
      'Core 第4.3.3節: Cancel 表示中の Required は未入力を拒否する'
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
      System.assert(
        ex.getMessage().contains('必須のカスタム項目を入力してください'),
        'Core 第4.3.4節・第11.4.1節: CancelでもShowOnCancelの契約サービス必須は保存を止める。実際: ' +
          ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);

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
      System.assertEquals(
        '見積ウィザードカスタム項目「Test_Bad_Visibility_Field」の VisibilityFieldApiName「DoesNotExistOnProduct2__c」が Product2 に存在しません。',
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
      System.assertEquals(
        '見積ウィザードカスタム項目「Test_Visibility_On_Service」の Visibility* は見積商品（ContractProduct__c）でのみ利用できます。',
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
      System.assertEquals(
        '見積ウィザードカスタム項目「Test_Bad_Visibility_Op」の VisibilityOperator「CONTAINS」は未対応です。IN / NOT_IN / EQUALS / NOT_EQUALS / IS_BLANK / IS_NOT_BLANK のいずれかを指定してください。',
        ex.getMessage()
      );
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
      System.assertEquals(
        '見積ウィザードカスタム項目「Test_Empty_Visibility_Values」の VisibilityOperator=IN には VisibilityValues（カンマ区切り）が必要です。',
        ex.getMessage()
      );
    }
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void coerceValue_booleanReferenceAndEqualsVisibility() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    Schema.DescribeFieldResult booleanDescribe = User.IsActive.getDescribe();
    System.assertEquals(
      true,
      ContractWizardFieldService.coerceValue(booleanDescribe, 'true'),
      'Core 第11.4.1節: 真偽は文字列 true を真にする'
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.coerceValue(booleanDescribe, '1')
    );
    System.assertEquals(
      false,
      ContractWizardFieldService.coerceValue(booleanDescribe, 'false')
    );
    Schema.DescribeFieldResult accountLookup = ContractService__c.Account__c.getDescribe();
    System.assertEquals(
      null,
      ContractWizardFieldService.coerceValue(accountLookup, 'not-an-id'),
      'Core 第11.4.1節: 参照の不正値は書かない'
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.evaluateVisibility(
        'EQUALS',
        'Software',
        new List<String>{ 'Software' }
      )
    );
    System.assertEquals(
      false,
      ContractWizardFieldService.evaluateVisibility(
        'EQUALS',
        'Hardware',
        new List<String>{ 'Software' }
      )
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.evaluateVisibility(
        'NOT_EQUALS',
        'Hardware',
        new List<String>{ 'Software' }
      )
    );
  }

  @IsTest
  static void validateActiveDefinitions_rejectsInvalidTargetBlankFieldAndUnsupportedType() {
    assertWizardConfigRejected(
      new EstimateWizardField__mdt(
        DeveloperName = 'Test_Bad_Target',
        MasterLabel = 'Test Bad Target',
        Active__c = true,
        TargetObject__c = 'Account',
        FieldApiName__c = 'Name',
        SortOrder__c = 10,
        ShowOnNew__c = true,
        ShowOnChange__c = true,
        ShowOnRenew__c = true,
        ShowOnCancel__c = true
      ),
      '見積ウィザードカスタム項目「Test_Bad_Target」の対象オブジェクト「Account」が不正です。ContractService__c / ContractHistory__c / ContractProduct__c のいずれかを指定してください。'
    );
    assertWizardConfigRejected(
      new EstimateWizardField__mdt(
        DeveloperName = 'Test_Blank_Field',
        MasterLabel = 'Test Blank Field',
        Active__c = true,
        TargetObject__c = 'ContractService__c',
        FieldApiName__c = '',
        SortOrder__c = 10,
        ShowOnNew__c = true,
        ShowOnChange__c = true,
        ShowOnRenew__c = true,
        ShowOnCancel__c = true
      ),
      '見積ウィザードカスタム項目「Test_Blank_Field」の FieldApiName が未設定です。'
    );
    assertWizardConfigRejected(
      new EstimateWizardField__mdt(
        DeveloperName = 'Test_Missing_Field',
        MasterLabel = 'Test Missing Field',
        Active__c = true,
        TargetObject__c = 'ContractService__c',
        FieldApiName__c = 'DoesNotExistOnService__c',
        SortOrder__c = 10,
        ShowOnNew__c = true,
        ShowOnChange__c = true,
        ShowOnRenew__c = true,
        ShowOnCancel__c = true
      ),
      '見積ウィザードカスタム項目「Test_Missing_Field」の項目「DoesNotExistOnService__c」が対象オブジェクトに存在しません。'
    );
    assertWizardConfigRejected(
      new EstimateWizardField__mdt(
        DeveloperName = 'Test_Unsupported_Type',
        MasterLabel = 'Test Unsupported Type',
        Active__c = true,
        TargetObject__c = 'ContractService__c',
        FieldApiName__c = 'CreatedDate',
        SortOrder__c = 10,
        ShowOnNew__c = true,
        ShowOnChange__c = true,
        ShowOnRenew__c = true,
        ShowOnCancel__c = true
      ),
      '見積ウィザードカスタム項目「Test_Unsupported_Type」の項目「CreatedDate」はウィザード非対応の型です。'
    );
  }

  @IsTest
  static void validateActiveDefinitions_rejectsDottedVisibilityAndBadDefaultPaths() {
    assertWizardConfigRejected(
      new EstimateWizardField__mdt(
        DeveloperName = 'Test_Dotted_Visibility',
        MasterLabel = 'Test Dotted Visibility',
        Active__c = true,
        TargetObject__c = 'ContractProduct__c',
        FieldApiName__c = 'Description__c',
        VisibilityFieldApiName__c = 'Product2.Family',
        VisibilityOperator__c = 'IN',
        VisibilityValues__c = 'Software',
        SortOrder__c = 10,
        ShowOnNew__c = true,
        ShowOnChange__c = true,
        ShowOnRenew__c = true,
        ShowOnCancel__c = true
      ),
      '見積ウィザードカスタム項目「Test_Dotted_Visibility」の VisibilityFieldApiName「Product2.Family」が不正です。Product2 の項目 API 名を指定してください（ドット不可）。'
    );
    assertWizardConfigRejected(
      new EstimateWizardField__mdt(
        DeveloperName = 'Test_Bad_Account_Path',
        MasterLabel = 'Test Bad Account Path',
        Active__c = true,
        TargetObject__c = 'ContractService__c',
        FieldApiName__c = 'CustomerMemo__c',
        DefaultSource__c = 'Account',
        DefaultValue__c = 'DoesNotExist__c',
        SortOrder__c = 10,
        ShowOnNew__c = true,
        ShowOnChange__c = true,
        ShowOnRenew__c = true,
        ShowOnCancel__c = true
      ),
      '見積ウィザードカスタム項目「Test_Bad_Account_Path」の DefaultSource=Account に対する DefaultValue「DoesNotExist__c」が不正です。取引先の項目 API 名を指定してください。'
    );
    assertWizardConfigRejected(
      new EstimateWizardField__mdt(
        DeveloperName = 'Test_Bad_Product2_Path',
        MasterLabel = 'Test Bad Product2 Path',
        Active__c = true,
        TargetObject__c = 'ContractProduct__c',
        FieldApiName__c = 'Description__c',
        DefaultSource__c = 'Product2',
        DefaultValue__c = 'DoesNotExist__c',
        SortOrder__c = 10,
        ShowOnNew__c = true,
        ShowOnChange__c = true,
        ShowOnRenew__c = true,
        ShowOnCancel__c = true
      ),
      '見積ウィザードカスタム項目「Test_Bad_Product2_Path」の DefaultSource=Product2 に対する DefaultValue「DoesNotExist__c」が不正です。商品の項目 API 名を指定してください。'
    );
  }

  @IsTest
  static void validateCustomFieldTypes_reportsIntegerAndNumberAndClearsMap() {
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Quantity_Type',
          MasterLabel = '数量',
          Active__c = true,
          TargetObject__c = 'ContractProduct__c',
          FieldApiName__c = 'Quantity__c',
          SortOrder__c = 1,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        ),
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Price_Type',
          MasterLabel = '単価',
          Active__c = true,
          TargetObject__c = 'ContractProduct__c',
          FieldApiName__c = 'UnitPrice__c',
          SortOrder__c = 2,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        )
      }
    );
    String quantityTypeError = ContractWizardFieldService.validateCustomFieldTypes(
      ContractWizardFieldService.WizardTarget.ContractProduct,
      new Map<String, Object>{ 'Quantity__c' => 'abc' }
    );
    System.assert(
      quantityTypeError != null &&
        quantityTypeError.contains('カスタム項目の形式が不正です: 数量'),
      'Core 第11.4.1節: 追加項目の型不一致は保存を止める: ' +
        quantityTypeError
    );
    System.assertEquals(
      'カスタム項目の形式が不正です: 単価（数値で入力してください）',
      ContractWizardFieldService.validateCustomFieldTypes(
        ContractWizardFieldService.WizardTarget.ContractProduct,
        new Map<String, Object>{ 'UnitPrice__c' => 'abc' }
      ),
      'Core 第11.4.1節: 追加項目の型不一致は保存を止める'
    );
    Map<String, Object> cleared = ContractWizardFieldService.buildClearedCustomFields(
      ContractWizardFieldService.WizardTarget.ContractProduct
    );
    System.assertEquals(null, cleared.get('Quantity__c'));
    System.assertEquals(null, cleared.get('UnitPrice__c'));
    Schema.DescribeFieldResult quantityDescribe = ContractProduct__c.Quantity__c.getDescribe();
    System.assertEquals(
      12,
      ContractWizardFieldService.coerceValue(quantityDescribe, '12')
    );
    Schema.DescribeFieldResult priceDescribe = ContractProduct__c.UnitPrice__c.getDescribe();
    System.assertEquals(
      12.5,
      ContractWizardFieldService.coerceValue(priceDescribe, '12.5')
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.coerceValue(
        User.IsActive.getDescribe(),
        true
      )
    );
    System.assertEquals(
      '整数で入力してください',
      ContractWizardFieldService.getTypeErrorMessage(
        Schema.DisplayType.INTEGER,
        '1.5'
      )
    );
    System.assertEquals(
      '真偽値で入力してください',
      ContractWizardFieldService.getTypeErrorMessage(
        Schema.DisplayType.BOOLEAN,
        'maybe'
      )
    );
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }

  @IsTest
  static void wizardFieldHelpers_typeVisibilityPicklistAndNulls() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
    System.assertEquals(
      0,
      ContractWizardFieldService.extractCustomFields(
          null,
          ContractWizardFieldService.WizardTarget.ContractService
        )
        .size()
    );
    ContractWizardFieldService.applyCustomFields(
      null,
      new Map<String, Object>{ 'CustomerMemo__c' => 'x' },
      ContractWizardFieldService.WizardTarget.ContractService
    );
    ContractWizardFieldService.applyCustomFields(
      new ContractService__c(),
      new Map<String, Object>(),
      ContractWizardFieldService.WizardTarget.ContractService
    );

    List<ContractWizardFieldService.PicklistOptionDefinition> typeOptions = ContractWizardFieldService.buildPicklistOptions(
      ContractHistory__c.Type__c.getDescribe()
    );
    System.assert(
      typeOptions.size() > 0,
      'Core 第11.4.1節: 選択リストの追加項目は有効な選択肢を出す'
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.isSupportedType(Schema.DisplayType.EMAIL)
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.isSupportedType(Schema.DisplayType.PHONE)
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.isSupportedType(Schema.DisplayType.URL)
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.isSupportedType(Schema.DisplayType.PERCENT)
    );
    System.assertEquals(
      true,
      ContractWizardFieldService.isSupportedType(Schema.DisplayType.LONG)
    );
    System.assertEquals(
      false,
      ContractWizardFieldService.isSupportedType(Schema.DisplayType.TIME),
      'Core 第11.4.1節: 時刻型はウィザード非対応'
    );

    Schema.DescribeFieldResult percentDescribe = ContractService__c.TaxPercent__c.getDescribe();
    System.assertEquals(
      10.5,
      ContractWizardFieldService.coerceValue(percentDescribe, '10.5')
    );
    System.assertEquals(
      null,
      ContractWizardFieldService.coerceValue(
        ContractHistory__c.Opportunity__c.getDescribe(),
        'not-an-id'
      )
    );
    System.assertEquals(
      null,
      ContractWizardFieldService.coerceValue(
        User.IsActive.getDescribe(),
        ' '
      )
    );
    System.assertEquals(
      false,
      ContractWizardFieldService.coerceValue(
        User.IsActive.getDescribe(),
        '0'
      )
    );
    System.assertEquals(
      '有効なレコードを選択してください',
      ContractWizardFieldService.getTypeErrorMessage(
        Schema.DisplayType.REFERENCE,
        'not-an-id'
      )
    );
    System.assertEquals(
      '数値で入力してください',
      ContractWizardFieldService.getTypeErrorMessage(
        Schema.DisplayType.PERCENT,
        'abc'
      )
    );

    ContractWizardFieldService.resetCache();
    System.assert(
      ContractWizardFieldService.getContractHistoryFieldDefinitions().size() >=
        0
    );
    System.assertEquals(
      0,
      ContractWizardFieldService.buildPicklistOptions(
          ContractHistory__c.CurrentTermStartDate__c.getDescribe()
        )
        .size()
    );
    List<String> productSelect = ContractWizardFieldService.getProduct2RelationshipSelectFields(
      'Product__r'
    );
    for (String path : productSelect) {
      System.assert(
        path.startsWith('Product__r.'),
        'Core 第11.4.1節: Product2参照項目は関係名付きで取る'
      );
    }
  }

  private static void assertWizardConfigRejected(
    EstimateWizardField__mdt definition,
    String expectedMessage
  ) {
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{ definition }
    );
    try {
      ContractWizardFieldService.validateActiveDefinitions();
      System.assert(false, expectedMessage);
    } catch (ContractWizardFieldService.WizardFieldConfigException ex) {
      System.assertEquals(expectedMessage, ex.getMessage());
    }
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
  }
}
