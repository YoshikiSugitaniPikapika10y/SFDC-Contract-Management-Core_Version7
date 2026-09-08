public without sharing class InvoiceCancelService {
  public class CancelException extends Exception {
  }

  public class CancelRequest {
    public Id invoiceId;
    public String cancellationReason;
    public String cancellationReasonText;
    public Date cancellationDate;
    public String businessOperationKey;
    public String expectedToken;
    public Invoice__c knownLockedInvoice;
  }

  public class CancelResult {
    public Id cancelledInvoiceId;
    public Id correctionInvoiceId;
    public AccountingDiffService.CancelPreview journalPreview;
    public Boolean requiresCustomerNotice;
    public String businessOperationKey;
  }

  /**
   * 仕様: Core 第12.4節・第7.9.3節。
   * 取消が触った請求・明細。保存後返却は取り直さない。
   */
  public class CancelPreviewTouch {
    public Map<Id, Invoice__c> invoicesById = new Map<Id, Invoice__c>();
    public Map<Id, List<InvoiceLine__c>> linesByInvoiceId = new Map<Id, List<InvoiceLine__c>>();
  }

  private static CancelPreviewTouch cancelPreviewTouch;

  public static CancelPreviewTouch takeCancelPreviewTouch() {
    CancelPreviewTouch touch = cancelPreviewTouch;
    cancelPreviewTouch = null;
    return touch;
  }

  private static void rememberCancelPreviewTouch(
    Invoice__c original,
    List<InvoiceLine__c> originalLines,
    Invoice__c correction,
    List<InvoiceLine__c> correctionLines
  ) {
    CancelPreviewTouch touch = new CancelPreviewTouch();
    if (original != null && original.Id != null) {
      touch.invoicesById.put(original.Id, original);
      if (originalLines != null) {
        touch.linesByInvoiceId.put(original.Id, originalLines);
      }
    }
    if (correction != null && correction.Id != null) {
      touch.invoicesById.put(correction.Id, correction);
      if (correctionLines != null) {
        touch.linesByInvoiceId.put(correction.Id, correctionLines);
      }
    }
    cancelPreviewTouch = touch;
  }

  /** 仕様: Core 第7.9.3節、第7.9.6節、第7.10節、日付仕様 第7.3節、Accounting 第8.2節、第8.8節、Core 第12.4節 */
  public static CancelResult cancelConfirmed(CancelRequest request) {
    ContractPermissionUtil.assertCancelInvoice();
    if (request == null || request.invoiceId == null) {
      throw new CancelException('取消する請求が指定されていません。');
    }
    if (String.isBlank(request.cancellationReason)) {
      throw new CancelException('取消理由を入力してください。');
    }
    if (request.cancellationReason == 'Other' && String.isBlank(request.cancellationReasonText)) {
      throw new CancelException('取消理由がその他のときは内容を入力してください。');
    }
    Invoice__c invoice =
      request.knownLockedInvoice != null &&
      request.knownLockedInvoice.Id == request.invoiceId
        ? request.knownLockedInvoice
        : AccountingCauseLockService.lockInvoice(request.invoiceId);
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      request.businessOperationKey
    );
    if (
      InvoiceTransactionStatusService.isCancelled(invoice) &&
      invoice.BusinessOperationKey__c == operationKey
    ) {
      return existingCancelResult(invoice, request.cancellationDate, operationKey);
    }
    // 仕様: Core 第4.3.12節・第7.9.7節。比較値未指定は拒否。検査省略の互換は持たない。
    AccountingCauseLockService.assertInvoiceOperationUnchanged(
      request.invoiceId,
      request.expectedToken,
      invoice.LastModifiedDate
    );
    AccountingCurrentService.load(invoice.Id);
    if (!InvoiceTransactionStatusService.isConfirmed(invoice)) {
      throw new CancelException('確定済みの請求だけ取消できます。');
    }
    Integer activePayments = [
      SELECT COUNT()
      FROM InvoicePayment__c
      WHERE Invoice__c = :invoice.Id AND PaymentTransactionStatus__c = 'Active'
      WITH SYSTEM_MODE
    ];
    if (activePayments > 0) {
      throw new CancelException('有効な請求入出金がある請求は取消できません。');
    }
    Integer activeManuals = [
      SELECT COUNT()
      FROM GlManualJournalHeader__c
      WHERE Invoice__c = :invoice.Id AND TransactionStatus__c = 'Active'
      WITH SYSTEM_MODE
    ];
    if (activeManuals > 0) {
      throw new CancelException('有効な手動仕訳がある請求は取消できません。');
    }
    Invoice__c locked = invoice;
    Invoice__c original = correctionSourceInvoice(locked);
    List<InvoiceLine__c> originalLines = queryOriginalLinesForCorrection(
      original.Id
    );
    rememberCorrectionCopySources(original, originalLines);
    InvoiceTransactionStatusService.applyCancelled(new List<Invoice__c>{ original });
    // 仕様: Core 第7.9.3節手順5・第7.9.5節。理由は元請求へ保持。取消者・日時は監査項目。
    original.CancellationReason__c = request.cancellationReason;
    original.CancellationReasonText__c = request.cancellationReasonText;
    original.BusinessOperationKey__c = operationKey;
    AccountingDiffService.rememberInvoiceCancelReason(
      original.Id,
      request.cancellationReason,
      request.cancellationReasonText
    );
    Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
    Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
    InvoiceTransactionStatusService.allowStatusWrite = true;
    InvoiceLockUtil.allowLockedStatusWrite = true;
    try {
      SystemContextAccess.updateRecords(new List<Invoice__c>{ original });
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
      InvoiceLockUtil.allowLockedStatusWrite = previousLock;
    }
    // 仕様: Core 第7.9.3節・第11.4.2節。顧客追加項目は clone で載せ、insert の空欄スタンプに任せる。
    Invoice__c correction = original.clone(false, true, false, false);
    // 仕様: Core 第7.9.3節。MergeKeyはコピー対象に無い。Nameは自動採番。
    correction.MergeKey__c = null;
    correction.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT;
    correction.CollectionRefundStatus__c = null;
    correction.DeliveryStatus__c = null;
    InvoiceTransactionStatusService.seedDefaults(correction);
    correction.SystemIntegrationDate__c = null;
    correction.SentDate__c = null;
    correction.PaymentClearingCompletedDate__c = null;
    correction.InvoicePaymentNet__c = 0;
    correction.PaymentInclusiveTotal__c = 0;
    correction.AppliedTaxRoundingMode__c = null;
    // 仕様: Core 第7.9.3節手順3。取消情報は訂正用へ引き継がない。業務操作キーは手順5で両方へ。
    correction.CancellationReason__c = null;
    correction.CancellationReasonText__c = null;
    // 仕様: Core 第7.9.3節手順3、Accounting 第7.1節。会計タグは引き継がない。
    AccountingTagEvaluationService.clearEnabledTagTargets(correction);
    InvoiceTransactionStatusService.allowStatusWrite = true;
    InvoiceLockUtil.allowLockedStatusWrite = true;
    try {
      insert correction;
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
      InvoiceLockUtil.allowLockedStatusWrite = previousLock;
    }
    List<InvoiceLine__c> copies = new List<InvoiceLine__c>();
    for (InvoiceLine__c line : originalLines) {
      InvoiceLine__c copy = line.clone(false, true, false, false);
      copy.Invoice__c = correction.Id;
      copy.AllocatedTaxAmount__c = null;
      copies.add(copy);
    }
    if (!copies.isEmpty()) {
      insert copies;
    }
    AccountingDiffService.applyForInvoice(
      locked.Id,
      AccountingEventFixedCatalog.BILLING_CANCELLED.key,
      operationKey,
      request.cancellationDate,
      locked
    );
    ContractOperationLogService.write(
      'CancelInvoice',
      operationKey,
      'Invoice__c',
      String.valueOf(original.Id),
      request.cancellationReason,
      request.cancellationReasonText,
      null,
      null
    );
    CancelResult result = new CancelResult();
    result.cancelledInvoiceId = original.Id;
    result.correctionInvoiceId = correction.Id;
    result.journalPreview = AccountingDiffService.emptyConfirmPreview();
    result.businessOperationKey = operationKey;
    result.requiresCustomerNotice = InvoiceTransactionStatusService.DELIVERY_SENT.equals(
      original.DeliveryStatus__c
    );
    rememberCancelPreviewTouch(original, originalLines, correction, copies);
    return result;
  }

  /** 仕様: Core 第7.9.6節、Accounting 第8.5節、日付仕様 第7.3節、共通基盤 第10.4節 */
  public static AccountingDiffService.CancelPreview previewConfirmed(
    Id invoiceId,
    Date cancellationDate
  ) {
    ContractPermissionUtil.assertCancelInvoice();
    if (invoiceId == null) {
      throw new CancelException('取消する請求が指定されていません。');
    }
    return AccountingDiffService.previewCancel(
      invoiceId,
      AccountingEventFixedCatalog.BILLING_CANCELLED.key,
      cancellationDate,
      null,
      null
    );
  }

  @TestVisible
  static Integer correctionInvoiceSelectCount = 0;

  /** 仕様: Accounting 第8.2節、Core 第7.9.3節。ロック済み請求で訂正コピーできる項目があれば取り直さない。 */
  private static Invoice__c correctionSourceInvoice(Invoice__c locked) {
    if (hasCorrectionCloneFields(locked)) {
      return locked;
    }
    return queryOriginalInvoiceForCorrection(locked.Id);
  }

  private static Boolean hasCorrectionCloneFields(Invoice__c invoice) {
    if (invoice == null) {
      return false;
    }
    try {
      invoice.get('DeliveryStatus__c');
      invoice.get('MergeKey__c');
      invoice.get('Amount__c');
      invoice.get('TaxAmount__c');
      invoice.get('TaxPercent__c');
      invoice.get('ContractHistory__c');
      invoice.getSObject('BillingAccountSnapShot__r');
      ContractHistory__c history = (ContractHistory__c) invoice.getSObject(
        'ContractHistory__r'
      );
      if (history == null) {
        return false;
      }
      history.getSObject('Opportunity__r');
      ContractService__c service = (ContractService__c) history.getSObject(
        'ContractService__r'
      );
      if (service != null) {
        service.getSObject('Account__r');
      }
      return true;
    } catch (SObjectException ex) {
      return false;
    }
  }

  /**
   * 仕様: Core 第12.4節・第11.4.2節・第7.9.3節。
   * 訂正cloneとコピーFromはロックSELECTへ載せ、同じ請求を取り直さない。
   */
  public static void addCorrectionCloneSelectFields(Set<String> fields) {
    if (fields == null) {
      return;
    }
    fields.addAll(
      new Set<String>{
        'Id',
        'ContractService__c',
        'ContractHistory__c',
        'InvoiceDate__c',
        'PaymentScheduledDate__c',
        'Amount__c',
        'TaxAmount__c',
        'TaxPercent__c',
        'TaxInclusiveAmount__c',
        'BillingAccountSnapShot__c',
        'BillingAccountKeySnapShot__c',
        'BillingAddresseeSnapShot__c',
        'BillingEmailToSnapShot__c',
        'BillingEmailCcSnapShot__c',
        'BillingEmailBccSnapShot__c',
        'InvoiceDeliveryMethodSnapShot__c',
        'InvoiceDateMethodSnapShot__c',
        'InvoiceDateDayKindSnapShot__c',
        'InvoiceDateDayOfMonthSnapShot__c',
        'InvoiceDateMonthOffsetSnapShot__c',
        'InvoiceDateDayOffsetSnapShot__c',
        'InvoiceDateAdjustSnapShot__c',
        'PaymentTermMethodSnapShot__c',
        'PaymentTermDayKindSnapShot__c',
        'PaymentTermDayOfMonthSnapShot__c',
        'PaymentTermMonthOffsetSnapShot__c',
        'PaymentTermDayOffsetSnapShot__c',
        'PaymentTermAdjustSnapShot__c',
        'MergeKey__c',
        'SourcePeriodLineIds__c',
        'PeriodLineAmountTotal__c',
        'Memo__c',
        'InvoiceTransactionStatus__c',
        'IsAmountAdjusted__c',
        'IsSplitMoved__c',
        'IsManuallyAdjusted__c',
        'DeliveryStatus__c',
        'BusinessOperationKey__c',
        'BillingAccountSnapShot__r.Id',
        'ContractHistory__r.Opportunity__r.Id',
        'ContractHistory__r.ContractService__r.Id',
        'ContractHistory__r.ContractService__r.Account__r.Id'
      }
    );
    fields.addAll(
      extraCorrectionFieldApiNames(
        Invoice__c.SObjectType,
        InvoiceOpsFieldService.fieldApiNames('Invoice__c')
      )
    );
    fields.addAll(
      extraCorrectionFieldApiNames(
        Invoice__c.SObjectType,
        new Set<String>(FieldCopyDefinitionService.targetFieldApiNames('Invoice__c'))
      )
    );
    addPrefixedCopyFields(
      fields,
      'ContractHistory__r',
      historyCopySelectFields(),
      ContractHistory__c.SObjectType
    );
    addPrefixedCopyFields(
      fields,
      'ContractHistory__r.Opportunity__r',
      opportunityCopySelectFields(),
      Opportunity.SObjectType
    );
    addPrefixedCopyFields(
      fields,
      'ContractHistory__r.ContractService__r',
      new Set<String>{ 'Id', 'BiilingAcccount__c', 'Account__c' },
      ContractService__c.SObjectType
    );
    addPrefixedCopyFields(
      fields,
      'ContractHistory__r.ContractService__r.Account__r',
      accountCopySelectFields(),
      Account.SObjectType
    );
    addPrefixedCopyFields(
      fields,
      'BillingAccountSnapShot__r',
      billingAccountCopySelectFields(),
      BillingAccount__c.SObjectType
    );
  }

  /** 仕様: Core 第7.9.3節・第11.4.2節・第11.4.4節。訂正用は元の顧客追加項目をコピーし、空欄だけ定義スタンプする。 */
  private static Invoice__c queryOriginalInvoiceForCorrection(Id invoiceId) {
    correctionInvoiceSelectCount++;
    Set<String> fields = new Set<String>();
    addCorrectionCloneSelectFields(fields);
    String soql =
      'SELECT ' +
      String.join(new List<String>(fields), ',') +
      ' FROM Invoice__c WHERE Id = :invoiceId WITH SYSTEM_MODE LIMIT 1';
    return (Invoice__c) Database.query(soql);
  }

  /** 仕様: Core 第7.9.3節・第11.4.2節。訂正用明細は元の顧客追加項目をコピーし、空欄だけ定義スタンプする。 */
  private static List<InvoiceLine__c> queryOriginalLinesForCorrection(Id invoiceId) {
    Set<String> fields = new Set<String>{
      'Id',
      'ContractProduct__c',
      'Product__c',
      'ProductName__c',
      'ProductCodeSnapShot__c',
      'Quantity__c',
      'Unit__c',
      'UnitPrice__c',
      'Amount__c',
      'PeriodLabel__c',
      'ServicePeriodStartDate__c',
      'ServicePeriodEndDate__c',
      'AcceptanceEndDate__c',
      'RevenueRecognitionBasis__c',
      'LineMergeKey__c',
      'SourcePeriodLineIds__c',
      'HistoryVersionLabel__c',
      'IsSplitMoved__c',
      'IsManuallyAdjusted__c',
      'IsAmountAdjusted__c',
      'Invoice__c',
      'ContractProduct__r.Amount__c',
      'ContractProduct__r.Unit__c',
      'ContractProduct__r.BillingType__c',
      'ContractProduct__r.ContractHistory__c',
      'ContractProduct__r.StartDate__c',
      'ContractProduct__r.Enddate__c'
    };
    fields.addAll(
      extraCorrectionFieldApiNames(
        InvoiceLine__c.SObjectType,
        new Set<String>(
          FieldCopyDefinitionService.targetFieldApiNames('InvoiceLine__c')
        )
      )
    );
    addPrefixedCopyFields(
      fields,
      'ContractProduct__r',
      contractProductCopySelectFields(),
      ContractProduct__c.SObjectType
    );
    addPrefixedCopyFields(
      fields,
      'ContractProduct__r.Product__r',
      productCopySelectFields(),
      Product2.SObjectType
    );
    addPrefixedCopyFields(
      fields,
      'Product__r',
      productCopySelectFields(),
      Product2.SObjectType
    );
    String soql =
      'SELECT ' +
      String.join(new List<String>(fields), ',') +
      ' FROM InvoiceLine__c WHERE Invoice__c = :invoiceId WITH SYSTEM_MODE';
    return Database.query(soql);
  }

  /**
   * 仕様: Core 第11.4.2節・第12.4節。訂正用 insert のコピーFromは clone SELECT で載せ、取り直さない。
   */
  private static void rememberCorrectionCopySources(
    Invoice__c original,
    List<InvoiceLine__c> lines
  ) {
    if (original == null) {
      return;
    }
    ContractHistory__c history = (ContractHistory__c) original.getSObject(
      'ContractHistory__r'
    );
    if (history != null) {
      InvoiceProductFieldCopyService.rememberRecords(
        new List<SObject>{ history },
        historyCopySelectFields()
      );
      Opportunity opportunity = (Opportunity) history.getSObject('Opportunity__r');
      if (opportunity != null) {
        InvoiceProductFieldCopyService.rememberRecords(
          new List<SObject>{ opportunity },
          opportunityCopySelectFields()
        );
      }
      ContractService__c service = (ContractService__c) history.getSObject(
        'ContractService__r'
      );
      if (service != null) {
        InvoiceProductFieldCopyService.rememberRecords(
          new List<SObject>{ service },
          new Set<String>{ 'Id', 'BiilingAcccount__c', 'Account__c' }
        );
        Account account = (Account) service.getSObject('Account__r');
        if (account != null) {
          InvoiceProductFieldCopyService.rememberRecords(
            new List<SObject>{ account },
            accountCopySelectFields()
          );
        }
      }
    }
    BillingAccount__c billingAccount = (BillingAccount__c) original.getSObject(
      'BillingAccountSnapShot__r'
    );
    if (billingAccount != null) {
      InvoiceProductFieldCopyService.rememberRecords(
        new List<SObject>{ billingAccount },
        billingAccountCopySelectFields()
      );
    }
    if (lines == null || lines.isEmpty()) {
      return;
    }
    List<SObject> contractProducts = new List<SObject>();
    List<SObject> products = new List<SObject>();
    for (InvoiceLine__c line : lines) {
      ContractProduct__c contractProduct = (ContractProduct__c) line.getSObject(
        'ContractProduct__r'
      );
      if (contractProduct != null) {
        contractProducts.add(contractProduct);
        Product2 fromProduct = (Product2) contractProduct.getSObject('Product__r');
        if (fromProduct != null) {
          products.add(fromProduct);
        }
      }
      Product2 lineProduct = (Product2) line.getSObject('Product__r');
      if (lineProduct != null) {
        products.add(lineProduct);
      }
    }
    if (!contractProducts.isEmpty()) {
      InvoiceProductFieldCopyService.rememberRecords(
        contractProducts,
        contractProductCopySelectFields()
      );
    }
    if (!products.isEmpty()) {
      InvoiceProductFieldCopyService.rememberRecords(
        products,
        productCopySelectFields()
      );
    }
  }

  private static Set<String> historyCopySelectFields() {
    Set<String> names = InvoiceProductFieldCopyService.getSourceFieldApiNames(
      InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
      InvoiceProductFieldCopyService.TARGET_INVOICE
    );
    names.add('Opportunity__c');
    names.add('ContractService__c');
    return names;
  }

  private static Set<String> opportunityCopySelectFields() {
    return InvoiceProductFieldCopyService.getSourceFieldApiNames(
      InvoiceProductFieldCopyService.OBJECT_OPPORTUNITY,
      InvoiceProductFieldCopyService.TARGET_INVOICE
    );
  }

  private static Set<String> accountCopySelectFields() {
    return InvoiceProductFieldCopyService.getSourceFieldApiNames(
      InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
      InvoiceProductFieldCopyService.TARGET_INVOICE
    );
  }

  private static Set<String> billingAccountCopySelectFields() {
    return InvoiceProductFieldCopyService.getSourceFieldApiNames(
      InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT,
      InvoiceProductFieldCopyService.TARGET_INVOICE
    );
  }

  private static Set<String> contractProductCopySelectFields() {
    Set<String> names = InvoiceProductFieldCopyService.getSourceFieldApiNames(
      InvoiceProductFieldCopyService.OBJECT_CONTRACT_PRODUCT,
      InvoiceProductFieldCopyService.TARGET_INVOICE_LINE
    );
    names.add('Product__c');
    names.add('ContractHistory__c');
    names.add('Unit__c');
    return names;
  }

  private static Set<String> productCopySelectFields() {
    return InvoiceProductFieldCopyService.getSourceFieldApiNames(
      InvoiceProductFieldCopyService.OBJECT_PRODUCT,
      InvoiceProductFieldCopyService.TARGET_INVOICE_LINE
    );
  }

  private static void addPrefixedCopyFields(
    Set<String> fields,
    String relationshipPath,
    Set<String> relatedNames,
    Schema.SObjectType relatedType
  ) {
    if (
      fields == null ||
      String.isBlank(relationshipPath) ||
      relatedNames == null ||
      relatedType == null
    ) {
      return;
    }
    Map<String, Schema.SObjectField> fieldMap = relatedType.getDescribe()
      .fields.getMap();
    for (String relatedName : relatedNames) {
      if (String.isBlank(relatedName) || !fieldMap.containsKey(relatedName)) {
        continue;
      }
      fields.add(relationshipPath + '.' + fieldMap.get(relatedName).getDescribe().getName());
    }
  }

  private static Set<String> extraCorrectionFieldApiNames(
    Schema.SObjectType sobjectType,
    Set<String> candidates
  ) {
    Set<String> names = new Set<String>();
    if (sobjectType == null || candidates == null || candidates.isEmpty()) {
      return names;
    }
    Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe()
      .fields.getMap();
    for (String candidate : candidates) {
      if (String.isBlank(candidate) || !fieldMap.containsKey(candidate)) {
        continue;
      }
      Schema.DescribeFieldResult describe = fieldMap.get(candidate).getDescribe();
      if (!describe.isCreateable()) {
        continue;
      }
      names.add(describe.getName());
    }
    return names;
  }

  /** 仕様: Core 第7.9.3節、第7.9.7節 */
  private static CancelResult existingCancelResult(
    Invoice__c original,
    Date cancellationDate,
    String operationKey
  ) {
    List<Invoice__c> corrections = [
      SELECT Id, DeliveryStatus__c
      FROM Invoice__c
      WHERE
        BusinessOperationKey__c = :operationKey
        AND Id != :original.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    CancelResult result = new CancelResult();
    result.cancelledInvoiceId = original.Id;
    result.correctionInvoiceId = corrections.isEmpty()
      ? null
      : corrections[0].Id;
    result.journalPreview = AccountingDiffService.emptyConfirmPreview();
    result.businessOperationKey = operationKey;
    String deliveryStatus = null;
    try {
      deliveryStatus = (String) original.get('DeliveryStatus__c');
    } catch (SObjectException ex) {
      deliveryStatus = null;
    }
    result.requiresCustomerNotice = InvoiceTransactionStatusService.DELIVERY_SENT.equals(
      deliveryStatus
    );
    return result;
  }
}
