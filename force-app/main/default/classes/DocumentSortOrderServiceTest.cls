@IsTest
private class DocumentSortOrderServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void copiesProductOrderOnInsertAndDoesNotOverwrite() {
    Account account = ContractTestDataFactory.insertAccount('Sort Order Account');
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      'Sort Order Service'
    );
    Date termStart = ContractTestDataFactory.stableTermStart();
    Date termEnd = ContractTestDataFactory.stableTermEnd();
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Sort Order History',
      ContractService__c = service.Id,
      historystatus__c = 'Ordered',
      Type__c = 'New',
      Version__c = 1,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
    insert history;

    Product2 later = ContractTestDataFactory.buildProduct('Sort Later');
    later.DocumentSortOrder__c = 20;
    later.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    Product2 earlier = ContractTestDataFactory.buildProduct('Sort Earlier');
    earlier.DocumentSortOrder__c = 10;
    earlier.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProducts(new List<Product2>{ later, earlier });

    ContractProduct__c copied = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Product__c = later.Id,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      Type__c = 'New',
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
    );
    ContractProduct__c kept = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Product__c = earlier.Id,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      Type__c = 'Original',
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      DocumentSortOrder__c = 4
    );
    insert new List<ContractProduct__c>{ copied, kept };

    Map<Id, ContractProduct__c> stored = new Map<Id, ContractProduct__c>([
      SELECT DocumentSortOrder__c
      FROM ContractProduct__c
      WHERE Id IN :new Set<Id>{ copied.Id, kept.Id }
    ]);
    System.assertEquals(20, stored.get(copied.Id).DocumentSortOrder__c);
    System.assertEquals(4, stored.get(kept.Id).DocumentSortOrder__c);

    kept.Quantity__c = 2;
    update kept;
    ContractProduct__c afterUpdate = [
      SELECT DocumentSortOrder__c
      FROM ContractProduct__c
      WHERE Id = :kept.Id
    ];
    System.assertEquals(4, afterUpdate.DocumentSortOrder__c);

    List<ContractProduct__c> queried = [
      SELECT Name, Type__c, StartDate__c, DocumentSortOrder__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :history.Id
    ];
    DocumentSortOrderService.sortContractProducts(queried);
    System.assertEquals(4, queried[0].DocumentSortOrder__c);
    System.assertEquals(20, queried[1].DocumentSortOrder__c);

    InvoiceLine__c copiedLine = new InvoiceLine__c(
      ContractProduct__c = copied.Id
    );
    InvoiceLine__c keptLine = new InvoiceLine__c(
      ContractProduct__c = kept.Id,
      DocumentSortOrder__c = 7
    );
    DocumentSortOrderService.fillInvoiceLines(
      new List<InvoiceLine__c>{ copiedLine, keptLine }
    );
    System.assertEquals(20, copiedLine.DocumentSortOrder__c);
    System.assertEquals(7, keptLine.DocumentSortOrder__c);
  }

  @IsTest
  static void sortsQueriedContractProductsBySpec() {
    ContractProduct__c blank = contractProductRow(
      'CP-000003',
      'New',
      null,
      Date.newInstance(2026, 1, 1)
    );
    ContractProduct__c remake = contractProductRow(
      'CP-000002',
      'Remake',
      10,
      Date.newInstance(2026, 1, 1)
    );
    ContractProduct__c original = contractProductRow(
      'CP-000001',
      'Original',
      10,
      Date.newInstance(2026, 6, 1)
    );
    List<ContractProduct__c> rows = new List<ContractProduct__c>{
      blank,
      remake,
      original
    };
    DocumentSortOrderService.sortContractProducts(rows);
    System.assertEquals('Original', rows[0].Type__c);
    System.assertEquals('Remake', rows[1].Type__c);
    System.assertEquals(null, rows[2].DocumentSortOrder__c);

    ContractProduct__c earlyNew = contractProductRow(
      'CP-000004',
      'New',
      10,
      Date.newInstance(2026, 1, 1)
    );
    ContractProduct__c laterOriginal = contractProductRow(
      'CP-000005',
      'Original',
      10,
      Date.newInstance(2026, 6, 1)
    );
    ContractProduct__c sameDayRemake = contractProductRow(
      'CP-000006',
      'Remake',
      10,
      Date.newInstance(2026, 6, 1)
    );
    List<ContractProduct__c> mixed = new List<ContractProduct__c>{
      sameDayRemake,
      laterOriginal,
      earlyNew
    };
    DocumentSortOrderService.sortContractProducts(mixed);
    System.assertEquals('CP-000004', mixed[0].Name);
    System.assertEquals('Original', mixed[1].Type__c);
    System.assertEquals('Remake', mixed[2].Type__c);

    ContractProduct__c laterName = contractProductRow(
      'CP-000008',
      'Original',
      10,
      Date.newInstance(2026, 6, 1)
    );
    ContractProduct__c earlierName = contractProductRow(
      'CP-000007',
      'Original',
      10,
      Date.newInstance(2026, 6, 1)
    );
    List<ContractProduct__c> names = new List<ContractProduct__c>{
      laterName,
      earlierName
    };
    DocumentSortOrderService.sortContractProducts(names);
    System.assertEquals('CP-000007', names[0].Name);
    System.assertEquals('CP-000008', names[1].Name);

    InvoiceLine__c later = invoiceLineRow(
      'IL-000002',
      10,
      Date.newInstance(2026, 4, 1)
    );
    InvoiceLine__c earlier = invoiceLineRow(
      'IL-000001',
      10,
      Date.newInstance(2026, 1, 1)
    );
    InvoiceLine__c emptyDate = invoiceLineRow('IL-000000', 10, null);
    List<InvoiceLine__c> lines = new List<InvoiceLine__c>{
      emptyDate,
      later,
      earlier
    };
    DocumentSortOrderService.sortInvoiceLines(lines);
    System.assertEquals('IL-000001', lines[0].Name);
    System.assertEquals('IL-000002', lines[1].Name);
    System.assertEquals('IL-000000', lines[2].Name);
  }

  private static ContractProduct__c contractProductRow(
    String lineName,
    String typeValue,
    Decimal sortOrder,
    Date startDate
  ) {
    ContractProduct__c row = (ContractProduct__c) JSON.deserialize(
      '{"attributes":{"type":"ContractProduct__c"},"Name":"' + lineName + '"}',
      ContractProduct__c.class
    );
    row.Type__c = typeValue;
    row.DocumentSortOrder__c = sortOrder;
    row.StartDate__c = startDate;
    return row;
  }

  private static InvoiceLine__c invoiceLineRow(
    String lineName,
    Decimal sortOrder,
    Date startDate
  ) {
    InvoiceLine__c row = (InvoiceLine__c) JSON.deserialize(
      '{"attributes":{"type":"InvoiceLine__c"},"Name":"' + lineName + '"}',
      InvoiceLine__c.class
    );
    row.DocumentSortOrder__c = sortOrder;
    row.ServicePeriodStartDate__c = startDate;
    return row;
  }
}
