/**
 * 契約横断の左一覧取得。業務結果は既存手続き。
 * 仕様: 横断画面.md 第5節 取得、Core 第9章
 */
public with sharing class ContractCrossQueryService {
  public static final Integer ROW_LIMIT = 500;
  public static final String TRUNCATED_MESSAGE = '500件だけを取得しています。条件を狭めてリロードしてください。';
  public static final String LOCK_UNLOCKED = 'Unlocked';
  public static final String LOCK_LOCKED = 'Locked';
  public static final String INVOICE_STATUS_DRAFT = 'Draft';
  public static final String INVOICE_STATUS_CONFIRMED = 'Confirmed';
  public static final String INVOICE_STATUS_BOTH = 'Both';

  public class QueryException extends Exception {
  }

  public class DateRange {
    public Date dateFrom;
    public Date dateTo;
  }

  private static Date cachedOrganizationToday;

  /** 仕様: 横断画面.md 第5節 取得、日付仕様 第8章、Core 第12.4節・第4.3.11節 */
  public static Date organizationToday() {
    if (cachedOrganizationToday == null) {
      cachedOrganizationToday = InvoiceTransactionStatusService.organizationToday();
    }
    return cachedOrganizationToday;
  }

  public static DateRange defaultEstimateCloseDates() {
    return defaultEstimateCloseDates(organizationToday());
  }

  public static DateRange defaultEstimateCloseDates(Date today) {
    DateRange range = new DateRange();
    range.dateFrom = today.addDays(-90);
    range.dateTo = today.toStartOfMonth().addMonths(1).addDays(-1);
    return range;
  }

  public static DateRange defaultJournalPostingDates() {
    return defaultJournalPostingDates(organizationToday());
  }

  public static DateRange defaultJournalPostingDates(Date today) {
    DateRange range = new DateRange();
    range.dateFrom = today.toStartOfMonth().addMonths(-1);
    range.dateTo = today.toStartOfMonth().addDays(-1);
    return range;
  }

  private static List<ContractCrossController.TagRuleDto> cachedTagRules;
  private static Boolean tagRulesResolved;

  /** 仕様: Core 第1.1.10節、Accounting 第3.1節。0件はOFFと埋めない。 */
  public static Boolean isAccountingEnabled() {
    return GlAccountingPolicyService.requireOrgPolicy().AccountingEnabled__c ==
      true;
  }

  public static List<ContractCrossController.TagRuleDto> loadEnabledTagRules() {
    if (tagRulesResolved == true) {
      return cachedTagRules;
    }
    List<ContractCrossController.TagRuleDto> rows = new List<ContractCrossController.TagRuleDto>();
    if (!isAccountingEnabled()) {
      tagRulesResolved = true;
      cachedTagRules = rows;
      return rows;
    }
    for (GlAccountingTagRule__c rule : [
      SELECT TagLabel__c, TargetFieldApiName__c, TagKey__c
      FROM GlAccountingTagRule__c
      WHERE IsEnabled__c = TRUE
      WITH USER_MODE
      ORDER BY CreatedDate ASC, Name ASC
    ]) {
      ContractCrossController.TagRuleDto dto = new ContractCrossController.TagRuleDto();
      dto.label = rule.TagLabel__c;
      dto.fieldApiName = rule.TargetFieldApiName__c;
      dto.tagKey = rule.TagKey__c;
      rows.add(dto);
    }
    tagRulesResolved = true;
    cachedTagRules = rows;
    return rows;
  }

  public static ContractCrossController.ListResultDto queryEstimates(
    ContractCrossController.EstimateFilterDto filter
  ) {
    if (filter == null || filter.closeDateFrom == null || filter.closeDateTo == null) {
      throw new QueryException('完了予定日の FROM と TO は空にできません。');
    }
    String soql =
      'SELECT Id, Name, Version__c, Type__c, ' +
      'RenewEstimateAutoCreated__c, DeltaAmountSum__c, EstimateValidDate__c, ' +
      'EstimateSentAt__c, EstimateIssueDate__c, ' +
      'Opportunity__c, Opportunity__r.Name, Opportunity__r.CloseDate, ' +
      'Opportunity__r.AccountId, Opportunity__r.Account.Name, ' +
      'ContractService__c, ContractService__r.Name ' +
      'FROM ContractHistory__c ' +
      'WHERE historystatus__c = \'Estimate\' ' +
      'AND Opportunity__r.CloseDate >= :closeFrom ' +
      'AND Opportunity__r.CloseDate <= :closeTo';
    Date closeFrom = filter.closeDateFrom;
    Date closeTo = filter.closeDateTo;
    Id accountId = filter.accountId;
    Id serviceId = filter.serviceId;
    String typeValue = filter.estimateType;
    if (accountId != null) {
      soql += ' AND Opportunity__r.AccountId = :accountId';
    }
    if (serviceId != null) {
      soql += ' AND ContractService__c = :serviceId';
    }
    if (String.isNotBlank(typeValue)) {
      soql += ' AND Type__c = :typeValue';
    }
    if (filter.sent == true) {
      soql += ' AND EstimateSentAt__c != null';
    } else if (filter.sent == false) {
      soql += ' AND EstimateSentAt__c = null';
    }
    if (filter.issued == true) {
      soql += ' AND EstimateIssueDate__c != null';
    } else if (filter.issued == false) {
      soql += ' AND EstimateIssueDate__c = null';
    }
    if (filter.autoRenew == true) {
      soql += ' AND RenewEstimateAutoCreated__c = true';
    } else if (filter.autoRenew == false) {
      soql += ' AND RenewEstimateAutoCreated__c = false';
    }
    if (filter.validDateFrom != null) {
      soql += ' AND EstimateValidDate__c >= :validFrom';
    }
    if (filter.validDateTo != null) {
      soql += ' AND EstimateValidDate__c <= :validTo';
    }
    Date validFrom = filter.validDateFrom;
    Date validTo = filter.validDateTo;
    soql +=
      ' ORDER BY Opportunity__r.CloseDate ASC NULLS LAST, Opportunity__r.Account.Name ASC NULLS LAST, Name ASC';
    soql += ' LIMIT 501';
    List<ContractHistory__c> rows = Database.query(soql, AccessLevel.USER_MODE);
    ContractCrossController.ListResultDto result = newListResult(rows.size());
    Integer take = Math.min(rows.size(), ROW_LIMIT);
    for (Integer i = 0; i < take; i++) {
      ContractHistory__c history = rows[i];
      ContractCrossController.EstimateRowDto dto = new ContractCrossController.EstimateRowDto();
      dto.id = history.Id;
      dto.version = history.Version__c;
      dto.estimateType = history.Type__c;
      dto.estimateTypeLabel = (String) history.get('Type__c');
      dto.autoRenew = history.RenewEstimateAutoCreated__c == true;
      dto.opportunityId = history.Opportunity__c;
      dto.opportunityName = history.Opportunity__r == null
        ? null
        : history.Opportunity__r.Name;
      dto.closeDate = history.Opportunity__r == null
        ? null
        : history.Opportunity__r.CloseDate;
      dto.accountId = history.Opportunity__r == null
        ? null
        : history.Opportunity__r.AccountId;
      dto.accountName = history.Opportunity__r == null ||
        history.Opportunity__r.Account == null
        ? null
        : history.Opportunity__r.Account.Name;
      dto.serviceId = history.ContractService__c;
      dto.serviceName = history.ContractService__r == null
        ? null
        : history.ContractService__r.Name;
      dto.historyName = history.Name;
      dto.amount = history.DeltaAmountSum__c;
      dto.validDate = history.EstimateValidDate__c;
      dto.sent = history.EstimateSentAt__c != null;
      dto.issued = history.EstimateIssueDate__c != null;
      result.estimates.add(dto);
    }
    applyTypeLabels(result.estimates, rows, take);
    return result;
  }

  public static ContractCrossController.ListResultDto queryInvoices(
    ContractCrossController.InvoiceFilterDto filter
  ) {
    if (filter == null || String.isBlank(filter.invoiceStatus)) {
      throw new QueryException('請求状態は未確定／確定／両方のいずれかです。');
    }
    if (
      filter.invoiceStatus != INVOICE_STATUS_DRAFT &&
      filter.invoiceStatus != INVOICE_STATUS_CONFIRMED &&
      filter.invoiceStatus != INVOICE_STATUS_BOTH
    ) {
      throw new QueryException('請求状態は未確定／確定／両方のいずれかです。');
    }
    Boolean accountingOn = isAccountingEnabled();
    List<ContractCrossController.TagRuleDto> tagRules = accountingOn
      ? loadEnabledTagRules()
      : new List<ContractCrossController.TagRuleDto>();
    Set<String> fieldNames = new Set<String>{
      'Id',
      'Name',
      'InvoiceDate__c',
      'PaymentScheduledDate__c',
      'Amount__c',
      'Memo__c',
      'DeliveryStatus__c',
      'DueStatus__c',
      'CollectionRefundStatus__c',
      'InvoiceTransactionStatus__c',
      'BillingAccountSnapShot__c',
      'ContractHistory__c',
      'ContractService__c'
    };
    for (ContractCrossController.TagRuleDto rule : tagRules) {
      if (String.isNotBlank(rule.fieldApiName)) {
        fieldNames.add(rule.fieldApiName);
      }
    }
    String soql =
      'SELECT Id, Name, InvoiceDate__c, PaymentScheduledDate__c, Amount__c, Memo__c, ' +
      'DeliveryStatus__c, DueStatus__c, CollectionRefundStatus__c, InvoiceTransactionStatus__c, ' +
      'BillingAccountSnapShot__c, BillingAccountSnapShot__r.Name, ' +
      'ContractHistory__c, ContractHistory__r.Name, ContractHistory__r.Version__c, ' +
      'ContractHistory__r.DeltaAmountSum__c, ContractHistory__r.Opportunity__c, ' +
      'ContractHistory__r.Opportunity__r.Name, ContractHistory__r.Opportunity__r.CloseDate, ' +
      'ContractHistory__r.Opportunity__r.AccountId, ContractHistory__r.Opportunity__r.Account.Name, ' +
      'ContractService__c, ContractService__r.Name, ContractService__r.Account__c, ' +
      'ContractService__r.Account__r.Name';
    for (ContractCrossController.TagRuleDto rule : tagRules) {
      if (String.isNotBlank(rule.fieldApiName) && rule.fieldApiName != 'Id') {
        soql += ', ' + String.escapeSingleQuotes(rule.fieldApiName);
      }
    }
    soql += ' FROM Invoice__c WHERE Id != null';
    Boolean includeCancelled = filter.includeCancelled == true;
    if (filter.invoiceStatus == INVOICE_STATUS_DRAFT) {
      soql += includeCancelled
        ? ' AND InvoiceTransactionStatus__c IN (\'Draft\', \'Cancelled\')'
        : ' AND InvoiceTransactionStatus__c = \'Draft\'';
    } else if (filter.invoiceStatus == INVOICE_STATUS_CONFIRMED) {
      soql += includeCancelled
        ? ' AND InvoiceTransactionStatus__c IN (\'Confirmed\', \'Cancelled\')'
        : ' AND InvoiceTransactionStatus__c = \'Confirmed\'';
    } else {
      soql += includeCancelled
        ? ' AND InvoiceTransactionStatus__c IN (\'Draft\', \'Confirmed\', \'Cancelled\')'
        : ' AND InvoiceTransactionStatus__c IN (\'Draft\', \'Confirmed\')';
    }
    String nameLike;
    if (String.isNotBlank(filter.invoiceName)) {
      nameLike = '%' + filter.invoiceName.trim() + '%';
      soql += ' AND Name LIKE :nameLike';
    }
    Id billingAccountId = filter.billingAccountId;
    Id accountId = filter.accountId;
    if (billingAccountId != null) {
      soql += ' AND BillingAccountSnapShot__c = :billingAccountId';
    }
    if (accountId != null) {
      soql += ' AND ContractService__r.Account__c = :accountId';
    }
    Date invoiceFrom = filter.invoiceDateFrom;
    Date invoiceTo = filter.invoiceDateTo;
    Date closeFrom = filter.closeDateFrom;
    Date closeTo = filter.closeDateTo;
    Date nextFrom = filter.nextAcceptanceFrom;
    Date nextTo = filter.nextAcceptanceTo;
    // 仕様: 横断画面.md 第5節。FROM・TOは空の請求日を消さない。
    if (invoiceFrom != null) {
      soql += ' AND (InvoiceDate__c = null OR InvoiceDate__c >= :invoiceFrom)';
    }
    if (invoiceTo != null) {
      soql += ' AND (InvoiceDate__c = null OR InvoiceDate__c <= :invoiceTo)';
    }
    if (closeFrom != null) {
      soql += ' AND ContractHistory__r.Opportunity__r.CloseDate >= :closeFrom';
    }
    if (closeTo != null) {
      soql += ' AND ContractHistory__r.Opportunity__r.CloseDate <= :closeTo';
    }
    if (filter.sent == true) {
      soql += ' AND DeliveryStatus__c = \'Sent\'';
    } else if (filter.sent == false) {
      soql += ' AND DeliveryStatus__c = \'Unsent\'';
    }
    if (filter.overdue == true) {
      soql += ' AND DueStatus__c = \'遅延\'';
    } else if (filter.overdue == false) {
      soql += ' AND DueStatus__c != \'遅延\'';
    }
    if (String.isNotBlank(filter.collectionStatus)) {
      soql += ' AND CollectionRefundStatus__c = :collectionStatus';
    }
    String collectionStatus = filter.collectionStatus;
    // 仕様: 横断画面.md 第5節取得。発行・次の検収はフィルタ後に500件。
    lastLatestIssuedReloadedIssuedFiles = false;
    IssuedInvoiceFiles issuedFiles = new IssuedInvoiceFiles();
    Set<Id> issuedInvoiceIds = new Set<Id>();
    Boolean issuedFilterOn = filter.issued == true || filter.issued == false;
    if (issuedFilterOn) {
      issuedFiles = loadAllIssuedInvoiceIds();
      issuedInvoiceIds = issuedFiles.issuedInvoiceIds;
      if (filter.issued == true) {
        soql += ' AND Id IN :issuedInvoiceIds';
      } else if (!issuedInvoiceIds.isEmpty()) {
        soql += ' AND Id NOT IN :issuedInvoiceIds';
      }
    }
    lastInvoiceLineAggReloadedLines = false;
    NextAcceptanceLines nextAcceptanceLines = new NextAcceptanceLines();
    Boolean nextAcceptanceFilterOn =
      accountingOn && (nextFrom != null || nextTo != null);
    Set<Id> nextAcceptanceInvoiceIds = new Set<Id>();
    if (nextAcceptanceFilterOn) {
      nextAcceptanceLines = loadInvoiceIdsMatchingNextAcceptance(
        nextFrom,
        nextTo
      );
      nextAcceptanceInvoiceIds = nextAcceptanceLines.invoiceIds;
      soql += ' AND Id IN :nextAcceptanceInvoiceIds';
    }
    if (filter.tagFilters != null) {
      Map<String, Schema.SObjectField> invoiceFields = Invoice__c.SObjectType.getDescribe()
        .fields.getMap();
      for (ContractCrossController.TagFilterDto tagFilter : filter.tagFilters) {
        if (
          tagFilter == null ||
          String.isBlank(tagFilter.fieldApiName) ||
          String.isBlank(tagFilter.state) ||
          tagFilter.state == 'Unset' ||
          !invoiceFields.containsKey(tagFilter.fieldApiName)
        ) {
          continue;
        }
        String field = String.escapeSingleQuotes(tagFilter.fieldApiName);
        if (tagFilter.state == 'True') {
          soql += ' AND ' + field + ' = true';
        } else if (tagFilter.state == 'False') {
          soql += ' AND ' + field + ' = false';
        }
      }
    }
    soql +=
      ' ORDER BY InvoiceDate__c ASC NULLS FIRST, ContractService__r.Account__r.Name ASC NULLS LAST, Name ASC';
    soql += ' LIMIT 501';
    List<Invoice__c> rows = Database.query(soql, AccessLevel.USER_MODE);
    ContractCrossController.ListResultDto result = newListResult(rows.size());
    Integer take = Math.min(rows.size(), ROW_LIMIT);
    List<Invoice__c> taken = new List<Invoice__c>();
    for (Integer i = 0; i < take; i++) {
      taken.add(rows[i]);
    }
    Set<Id> invoiceIds = new Map<Id, Invoice__c>(taken).keySet();
    // 仕様: Core 第12.4節・第4.3.11節、横断画面.md 第5節取得。発行フィルタONの発行ファイルは取り直さない。
    Map<Id, Id> latestIssuedByInvoice;
    if (issuedFilterOn) {
      latestIssuedByInvoice = issuedFiles.latestIssuedByInvoice;
    } else {
      lastLatestIssuedReloadedIssuedFiles = true;
      latestIssuedByInvoice = loadLatestIssuedDocumentIds(invoiceIds);
    }
    // 仕様: Core 第12.4節・第4.3.11節、横断画面.md 第5節取得。次の検収フィルタONの明細は取り直さない。
    Map<Id, LineAgg> lineAgg;
    if (!accountingOn) {
      lineAgg = new Map<Id, LineAgg>();
    } else if (nextAcceptanceFilterOn) {
      lineAgg = nextAcceptanceLines.lineAgg;
    } else {
      lastInvoiceLineAggReloadedLines = true;
      lineAgg = loadInvoiceLineAgg(invoiceIds);
    }
    Map<Id, Decimal> versionInvoiceTotals = loadVersionInvoiceTotals(taken);
    for (Invoice__c invoice : taken) {
      ContractCrossController.InvoiceRowDto dto = new ContractCrossController.InvoiceRowDto();
      dto.id = invoice.Id;
      dto.invoiceName = invoice.Name;
      dto.historyId = invoice.ContractHistory__c;
      dto.historyName = invoice.ContractHistory__r == null
        ? null
        : invoice.ContractHistory__r.Name;
      dto.version = invoice.ContractHistory__r == null
        ? null
        : invoice.ContractHistory__r.Version__c;
      dto.serviceName = invoice.ContractService__r == null
        ? null
        : invoice.ContractService__r.Name;
      dto.opportunityId = invoice.ContractHistory__r == null
        ? null
        : invoice.ContractHistory__r.Opportunity__c;
      dto.opportunityName = invoice.ContractHistory__r == null ||
        invoice.ContractHistory__r.Opportunity__r == null
        ? null
        : invoice.ContractHistory__r.Opportunity__r.Name;
      dto.closeDate = invoice.ContractHistory__r == null ||
        invoice.ContractHistory__r.Opportunity__r == null
        ? null
        : invoice.ContractHistory__r.Opportunity__r.CloseDate;
      dto.accountId = invoice.ContractService__r == null
        ? null
        : invoice.ContractService__r.Account__c;
      if (dto.accountId == null && invoice.ContractHistory__r != null &&
        invoice.ContractHistory__r.Opportunity__r != null) {
        dto.accountId = invoice.ContractHistory__r.Opportunity__r.AccountId;
        dto.accountName = invoice.ContractHistory__r.Opportunity__r.Account ==
          null
          ? null
          : invoice.ContractHistory__r.Opportunity__r.Account.Name;
      } else {
        dto.accountName = invoice.ContractService__r == null ||
          invoice.ContractService__r.Account__r == null
          ? null
          : invoice.ContractService__r.Account__r.Name;
      }
      dto.billingAccountId = invoice.BillingAccountSnapShot__c;
      dto.billingAccountName = invoice.BillingAccountSnapShot__r == null
        ? null
        : invoice.BillingAccountSnapShot__r.Name;
      dto.invoiceDate = invoice.InvoiceDate__c;
      dto.paymentScheduledDate = invoice.PaymentScheduledDate__c;
      dto.amount = invoice.Amount__c;
      dto.estimateAmount = invoice.ContractHistory__r == null
        ? null
        : invoice.ContractHistory__r.DeltaAmountSum__c;
      dto.versionInvoiceAmount = versionInvoiceTotals.get(invoice.ContractHistory__c);
      dto.sent = invoice.DeliveryStatus__c == 'Sent';
      dto.issued = latestIssuedByInvoice.containsKey(invoice.Id);
      dto.latestIssuedContentDocumentId = latestIssuedByInvoice.get(invoice.Id);
      dto.overdue = invoice.DueStatus__c == '遅延';
      dto.collectionStatus = invoice.CollectionRefundStatus__c;
      dto.invoiceStatus = invoice.InvoiceTransactionStatus__c;
      dto.memo = invoice.Memo__c;
      dto.cancelled = invoice.InvoiceTransactionStatus__c == 'Cancelled';
      LineAgg agg = lineAgg.get(invoice.Id);
      if (accountingOn && agg != null) {
        dto.hasMonthly = agg.hasMonthly;
        dto.hasLump = agg.hasLump;
        dto.nextAcceptance = agg.nextAcceptance;
      }
      dto.trueTagLabels = new List<String>();
      // 仕様: Core 第8.10節・第7.7.3節、Accounting 第7.6節、共通基盤操作31。取消済みの行は空。評価・保存は変えない。
      if (accountingOn && dto.cancelled != true) {
        for (ContractCrossController.TagRuleDto rule : tagRules) {
          if (String.isBlank(rule.fieldApiName)) {
            continue;
          }
          Object value = invoice.get(rule.fieldApiName);
          if (value == true) {
            dto.trueTagLabels.add(rule.label);
          }
        }
      }
      result.invoices.add(dto);
    }
    return result;
  }

  public static ContractCrossController.ListResultDto queryJournals(
    ContractCrossController.JournalFilterDto filter
  ) {
    if (!isAccountingEnabled()) {
      throw new QueryException('AccountingがOFFのときは仕訳一覧を出せません。');
    }
    if (filter == null || filter.postingDateFrom == null || filter.postingDateTo == null) {
      throw new QueryException('計上日の FROM と TO は空にできません。');
    }
    if (filter.lockState != LOCK_UNLOCKED && filter.lockState != LOCK_LOCKED) {
      throw new QueryException('Lockは未Lock／Lock済みです。');
    }
    Set<String> listedJournalFields = new Set<String>{
      'Id',
      'LastModifiedDate',
      'Amount__c',
      'PostingDate__c',
      'Memo__c',
      'ConfirmationText__c',
      'IsLocked__c',
      'TransactionStatus__c',
      'AccountingEventKey__c',
      'JournalPatternKey__c',
      'GlManualJournalSetting__c',
      'DebitSlotKey__c',
      'CreditSlotKey__c',
      'DebitAccount__c',
      'CreditAccount__c',
      'Invoice__c'
    };
    String soql =
      'SELECT Id, LastModifiedDate, Amount__c, PostingDate__c, Memo__c, ConfirmationText__c, ' +
      'IsLocked__c, TransactionStatus__c, AccountingEventKey__c, JournalPatternKey__c, ' +
      'GlManualJournalSetting__c, GlManualJournalSetting__r.Name, ' +
      'DebitSlotKey__c, CreditSlotKey__c, DebitAccount__c, DebitAccount__r.Name, CreditAccount__c, CreditAccount__r.Name, ' +
      'Invoice__c, Invoice__r.Name, Invoice__r.ContractHistory__c, Invoice__r.LastModifiedDate, ' +
      'Invoice__r.InvoiceTransactionStatus__c, ' +
      'Invoice__r.BillingAccountSnapShot__c, Invoice__r.BillingAccountSnapShot__r.Name, ' +
      'Invoice__r.ContractService__r.Account__c, Invoice__r.ContractService__r.Account__r.Name';
    // 仕様: Core 第12.4節・第4.3.11節、横断画面.md 第5節 取得。追加項目は一覧SELECTへ重ね、対象仕訳を取り直さない。
    for (String apiName : InvoiceOpsFieldService.fieldApiNames('GlJournal__c')) {
      if (String.isBlank(apiName) || listedJournalFields.contains(apiName)) {
        continue;
      }
      soql += ', ' + String.escapeSingleQuotes(apiName);
      listedJournalFields.add(apiName);
    }
    soql +=
      ' FROM GlJournal__c ' +
      'WHERE TransactionStatus__c != \'LogicallyDeleted\' ' +
      'AND PostingDate__c >= :postingFrom AND PostingDate__c <= :postingTo';
    Date postingFrom = filter.postingDateFrom;
    Date postingTo = filter.postingDateTo;
    Boolean locked = filter.lockState == LOCK_LOCKED;
    soql += ' AND IsLocked__c = :locked';
    String eventKey = filter.eventKey;
    Id billingAccountId = filter.billingAccountId;
    Id accountId = filter.accountId;
    Id invoiceId = filter.invoiceId;
    Id manualSettingId;
    if (String.isNotBlank(eventKey)) {
      if (JournalPatternFixedCatalog.isKnownKey(eventKey)) {
        soql += ' AND JournalPatternKey__c = :eventKey';
      } else {
        try {
          manualSettingId = Id.valueOf(eventKey);
          soql += ' AND GlManualJournalSetting__c = :manualSettingId';
        } catch (Exception ignore) {
          soql += ' AND JournalPatternKey__c = :eventKey';
        }
      }
    }
    if (billingAccountId != null) {
      soql += ' AND Invoice__r.BillingAccountSnapShot__c = :billingAccountId';
    }
    if (accountId != null) {
      soql += ' AND Invoice__r.ContractService__r.Account__c = :accountId';
    }
    if (invoiceId != null) {
      soql += ' AND Invoice__c = :invoiceId';
    }
    soql +=
      ' ORDER BY PostingDate__c ASC NULLS LAST, Invoice__r.Name ASC NULLS LAST, Id ASC';
    soql += ' LIMIT 501';
    List<GlJournal__c> rows = Database.query(soql, AccessLevel.USER_MODE);
    ContractCrossController.ListResultDto result = newListResult(rows.size());
    Integer take = Math.min(rows.size(), ROW_LIMIT);
    for (Integer i = 0; i < take; i++) {
      GlJournal__c journal = rows[i];
      ContractCrossController.JournalRowDto dto = new ContractCrossController.JournalRowDto();
      dto.id = journal.Id;
      dto.invoiceId = journal.Invoice__c;
      dto.historyId = journal.Invoice__r == null
        ? null
        : journal.Invoice__r.ContractHistory__c;
      dto.invoiceName = journal.Invoice__r == null ? null : journal.Invoice__r.Name;
      dto.invoiceToken = null;
      dto.debitName = AccountingSlotFixedCatalog.slotAndAccount(
        journal.DebitSlotKey__c,
        journal.DebitAccount__r == null ? null : journal.DebitAccount__r.Name
      );
      dto.creditName = AccountingSlotFixedCatalog.slotAndAccount(
        journal.CreditSlotKey__c,
        journal.CreditAccount__r == null ? null : journal.CreditAccount__r.Name
      );
      dto.amount = journal.Amount__c;
      dto.confirmationText = journal.ConfirmationText__c;
      dto.memo = journal.Memo__c;
      dto.postingDate = journal.PostingDate__c;
      dto.isLocked = journal.IsLocked__c == true;
      dto.transactionStatus = journal.TransactionStatus__c;
      dto.eventKey = String.isNotBlank(journal.JournalPatternKey__c)
        ? journal.JournalPatternKey__c
        : (journal.GlManualJournalSetting__c == null
            ? null
            : String.valueOf(journal.GlManualJournalSetting__c));
      dto.eventName = JournalPatternFixedCatalog.listDisplayName(
        journal.JournalPatternKey__c
      );
      if (String.isBlank(dto.eventName)) {
        dto.eventName = journal.GlManualJournalSetting__r == null
          ? null
          : journal.GlManualJournalSetting__r.Name;
      }
      dto.billingAccountId = journal.Invoice__r == null
        ? null
        : journal.Invoice__r.BillingAccountSnapShot__c;
      dto.billingAccountName = journal.Invoice__r == null ||
        journal.Invoice__r.BillingAccountSnapShot__r == null
        ? null
        : journal.Invoice__r.BillingAccountSnapShot__r.Name;
      dto.accountId = journal.Invoice__r == null ||
        journal.Invoice__r.ContractService__r == null
        ? null
        : journal.Invoice__r.ContractService__r.Account__c;
      dto.accountName = journal.Invoice__r == null ||
        journal.Invoice__r.ContractService__r == null ||
        journal.Invoice__r.ContractService__r.Account__r == null
        ? null
        : journal.Invoice__r.ContractService__r.Account__r.Name;
      dto.invoiceCancelled = InvoiceTransactionStatusService.isCancelled(
        journal.Invoice__r
      );
      // 仕様: Core 第11.4.4節、横断画面.md 第2.4節。列モード用の仕訳追加項目は一覧行から重ねる。
      dto.extraFieldValues = InvoiceOpsFieldService.readValues(
        journal,
        'GlJournal__c'
      );
      result.journals.add(dto);
    }
    fillJournalInvoiceTokens(result.journals, rows, take);
    return result;
  }

  /**
   * 仕様: Core 第7.9.7節、第12.4節、第4.3.11節。横断のLock／Unlockは対象請求と配下の入出金・手動仕訳・仕訳の最大。
   * 一覧で読んだ仕訳の更新日時は版比較で取り直さない。
   */
  private static void fillJournalInvoiceTokens(
    List<ContractCrossController.JournalRowDto> journals,
    List<GlJournal__c> rows,
    Integer take
  ) {
    Set<Id> invoiceIds = new Set<Id>();
    Map<Id, Datetime> knownInvoiceModified = new Map<Id, Datetime>();
    List<GlJournal__c> listedJournals = new List<GlJournal__c>();
    Integer bound = Math.min(take, rows.size());
    for (Integer i = 0; i < bound; i++) {
      GlJournal__c journal = rows[i];
      listedJournals.add(journal);
      if (journal.Invoice__c == null) {
        continue;
      }
      invoiceIds.add(journal.Invoice__c);
      if (journal.Invoice__r != null) {
        knownInvoiceModified.put(journal.Invoice__c, journal.Invoice__r.LastModifiedDate);
      }
    }
    Map<Id, Datetime> actuals = AccountingCauseLockService.resolveInvoiceOperationDatetimes(
      invoiceIds,
      knownInvoiceModified,
      listedJournals
    );
    for (ContractCrossController.JournalRowDto dto : journals) {
      dto.invoiceToken = ContractOptimisticLockUtil.toToken(actuals.get(dto.invoiceId));
    }
  }

  /** 仕様: 横断画面.md 第5節 見積書タイル。Core 第4.6節。Estimateだけ出す。Ordered・Archiveは出さない。 */
  public static ContractCrossController.EstimateTileDto getEstimateTile(Id historyId) {
    if (historyId == null) {
      throw new QueryException('契約履歴が指定されていません。');
    }
    List<ContractHistory__c> histories = [
      SELECT
        Id,
        Name,
        Type__c,
        RenewEstimateAutoCreated__c,
        DeltaAmountSum__c,
        EstimateDate__c,
        EstimateValidDate__c,
        EstimateSentAt__c,
        EstimateSendContact__c,
        EstimateSendContact__r.Name,
        CreatedDate,
        CreatedBy.Name,
        LastModifiedBy.Name,
        historystatus__c,
        ContractService__r.TaxPercent__c
      FROM ContractHistory__c
      WHERE Id = :historyId
      WITH USER_MODE
      LIMIT 1
    ];
    if (histories.isEmpty()) {
      throw new QueryException('契約履歴が見つかりません。');
    }
    ContractHistory__c history = histories[0];
    ContractCrossController.EstimateTileDto tile = new ContractCrossController.EstimateTileDto();
    tile.id = history.Id;
    tile.historyName = history.Name;
    tile.estimateType = history.Type__c;
    tile.estimateTypeLabel = (String) history.get('Type__c');
    Schema.DescribeFieldResult typeDescribe = ContractHistory__c.Type__c.getDescribe();
    for (Schema.PicklistEntry entry : typeDescribe.getPicklistValues()) {
      if (entry.getValue() == history.Type__c) {
        tile.estimateTypeLabel = entry.getLabel();
        break;
      }
    }
    tile.autoRenew = history.RenewEstimateAutoCreated__c == true;
    tile.amount = history.DeltaAmountSum__c;
    // 仕様: 横断画面.md 第5節 見積書タイル。税込はフッタ。Core 第4.6節は税抜合計へ税率を1回。
    tile.taxInclusiveAmount = taxInclusiveForEstimate(
      history.DeltaAmountSum__c,
      history.ContractService__r == null
        ? null
        : history.ContractService__r.TaxPercent__c
    );
    tile.estimateDate = history.EstimateDate__c;
    tile.validDate = history.EstimateValidDate__c;
    tile.sendContactId = history.EstimateSendContact__c;
    tile.sendContactName = history.EstimateSendContact__r == null
      ? null
      : history.EstimateSendContact__r.Name;
    tile.sentAt = history.EstimateSentAt__c;
    tile.createdDate = history.CreatedDate;
    tile.createdByName = history.CreatedBy == null ? null : history.CreatedBy.Name;
    tile.lastModifiedByName = history.LastModifiedBy == null
      ? null
      : history.LastModifiedBy.Name;
    tile.isEstimate = history.historystatus__c == 'Estimate';
    tile.lines = new List<ContractCrossController.EstimateProductDto>();
    if (tile.isEstimate != true) {
      return tile;
    }
    // 仕様: 横断画面.md 第5節。印付き最新。0件は空。請求カードの「最新のPDFを見る」と同じ。
    tile.latestIssuedContentDocumentId = EstimateDocumentService.latestIssuedContentDocumentId(
      history.Id
    );
    Boolean accountingOn = isAccountingEnabled();
    for (ContractProduct__c product : [
      SELECT
        Id,
        Type__c,
        Product__r.Name,
        UnitPrice__c,
        Unit__c,
        Quantity__c,
        StartDate__c,
        Enddate__c,
        BillingType__c,
        InvoiceSetting__c,
        RevenueRecognitionBasis__c,
        Amount__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :historyId
      WITH USER_MODE
      ORDER BY StartDate__c ASC NULLS LAST, Product__r.Name ASC
    ]) {
      ContractCrossController.EstimateProductDto line = new ContractCrossController.EstimateProductDto();
      line.id = product.Id;
      line.typeValue = product.Type__c;
      line.typeLabel = typeLabel(product.Type__c);
      line.productName = product.Product__r == null ? null : product.Product__r.Name;
      line.unitPrice = product.UnitPrice__c;
      line.unit = product.Unit__c;
      line.quantity = product.Quantity__c;
      line.startDate = product.StartDate__c;
      line.endDate = product.Enddate__c;
      line.cycleCount = recurringCycleCount(
        product.BillingType__c,
        product.StartDate__c,
        product.Enddate__c
      );
      line.cycleCountLabel = cycleCountLabel(
        product.BillingType__c,
        line.cycleCount
      );
      line.invoiceSetting = product.InvoiceSetting__c;
      line.revenueBasis = accountingOn ? product.RevenueRecognitionBasis__c : null;
      line.amount = product.Amount__c;
      tile.lines.add(line);
    }
    return tile;
  }

  /** 仕様: Core 第4.6節。見積税込は税抜合計に税率を1回。空の税率は埋めない。 */
  private static Decimal taxInclusiveForEstimate(
    Decimal amountExcl,
    Decimal storedTaxPercent
  ) {
    Decimal displayPercent = TaxCalculationUtil.fromPercentFieldStorage(
      storedTaxPercent
    );
    if (displayPercent == null) {
      return null;
    }
    try {
      return TaxCalculationUtil.calculateAmountInclTax(
        amountExcl,
        displayPercent
      );
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      return null;
    }
  }

  /** 仕様: Core 第4.6節。検算はサービス期間からサイクル数を取る。 */
  private static Decimal recurringCycleCount(
    String billingType,
    Date startDate,
    Date endDate
  ) {
    if (!ContractMetadataService.isRecurringBillingType(billingType)) {
      return null;
    }
    Integer cycles = MonthlyBillingPeriodUtil.countMonthlyCycles(
      startDate,
      endDate
    );
    if (cycles == null || cycles < 1) {
      return null;
    }
    return cycles;
  }

  /** 仕様: 横断画面.md 第5節 見積書タイル。継続は期間のサイクル数。一回は `-`。 */
  private static String cycleCountLabel(String billingType, Decimal cycleCount) {
    if (String.isBlank(billingType)) {
      return '';
    }
    if (cycleCount != null && cycleCount >= 1) {
      return String.valueOf(cycleCount.intValue());
    }
    return '-';
  }

  private static void applyTypeLabels(
    List<ContractCrossController.EstimateRowDto> dtos,
    List<ContractHistory__c> rows,
    Integer take
  ) {
    Map<String, String> labels = new Map<String, String>();
    for (Schema.PicklistEntry entry : ContractHistory__c.Type__c.getDescribe()
      .getPicklistValues()) {
      labels.put(entry.getValue(), entry.getLabel());
    }
    for (Integer i = 0; i < take; i++) {
      dtos[i].estimateTypeLabel = labels.containsKey(rows[i].Type__c)
        ? labels.get(rows[i].Type__c)
        : rows[i].Type__c;
    }
  }

  private static String typeLabel(String value) {
    for (Schema.PicklistEntry entry : ContractProduct__c.Type__c.getDescribe()
      .getPicklistValues()) {
      if (entry.getValue() == value) {
        return entry.getLabel();
      }
    }
    return value;
  }

  private static ContractCrossController.ListResultDto newListResult(Integer queried) {
    ContractCrossController.ListResultDto result = new ContractCrossController.ListResultDto();
    result.truncated = queried > ROW_LIMIT;
    result.truncatedMessage = result.truncated ? TRUNCATED_MESSAGE : null;
    result.estimates = new List<ContractCrossController.EstimateRowDto>();
    result.invoices = new List<ContractCrossController.InvoiceRowDto>();
    result.journals = new List<ContractCrossController.JournalRowDto>();
    return result;
  }

  /** 仕様: 横断画面.md 操作23。印付きのうち作成日時が最も新しい1つ。フィルタOFFの初回。 */
  private static Map<Id, Id> loadLatestIssuedDocumentIds(Set<Id> linkedIds) {
    return EstimateDocumentService.latestIssuedContentDocumentIds(linkedIds);
  }

  private class IssuedInvoiceFiles {
    public Set<Id> issuedInvoiceIds = new Set<Id>();
    public Map<Id, Id> latestIssuedByInvoice = new Map<Id, Id>();
  }

  @TestVisible
  static Boolean lastLatestIssuedReloadedIssuedFiles = false;

  private class NextAcceptanceLines {
    public Set<Id> invoiceIds = new Set<Id>();
    public Map<Id, LineAgg> lineAgg = new Map<Id, LineAgg>();
  }

  @TestVisible
  static Boolean lastInvoiceLineAggReloadedLines = false;

  /**
   * 仕様: 横断画面.md 第5節取得・請求一覧、Core 第12.4節・第4.3.11節。
   * 次の検収はフィルタ後に500件。同じ明細から印と次の検収も組み立てる。
   */
  private static NextAcceptanceLines loadInvoiceIdsMatchingNextAcceptance(
    Date nextFrom,
    Date nextTo
  ) {
    NextAcceptanceLines loaded = new NextAcceptanceLines();
    for (InvoiceLine__c line : [
      SELECT Invoice__c, RevenueRecognitionBasis__c, AcceptanceEndDate__c
      FROM InvoiceLine__c
      WHERE RevenueRecognitionBasis__c IN ('月次計上', '一括計上')
      WITH USER_MODE
    ]) {
      applyInvoiceLineToAgg(loaded.lineAgg, line);
    }
    for (Id invoiceId : loaded.lineAgg.keySet()) {
      Date nextAcceptance = loaded.lineAgg.get(invoiceId).nextAcceptance;
      if (nextAcceptance == null) {
        continue;
      }
      if (nextFrom != null && nextAcceptance < nextFrom) {
        continue;
      }
      if (nextTo != null && nextAcceptance > nextTo) {
        continue;
      }
      loaded.invoiceIds.add(invoiceId);
    }
    return loaded;
  }

  /**
   * 仕様: 横断画面.md 第5節取得・操作23、Core 第12.4節・第4.3.11節。
   * 発行フィルタは500件窓の前。同じ発行ファイルから最新発行も組み立てる。
   */
  private static IssuedInvoiceFiles loadAllIssuedInvoiceIds() {
    IssuedInvoiceFiles loaded = new IssuedInvoiceFiles();
    List<ContentVersion> versions = [
      SELECT Id, ContentDocumentId, CreatedDate, IsLatest
      FROM ContentVersion
      WHERE ContractDocumentIssued__c = TRUE
      WITH SYSTEM_MODE
    ];
    if (versions.isEmpty()) {
      return loaded;
    }
    Set<Id> documentIds = new Set<Id>();
    for (ContentVersion version : versions) {
      documentIds.add(version.ContentDocumentId);
    }
    Map<Id, List<Id>> documentToInvoices = new Map<Id, List<Id>>();
    for (ContentDocumentLink link : [
      SELECT LinkedEntityId, ContentDocumentId
      FROM ContentDocumentLink
      WHERE ContentDocumentId IN :documentIds
      WITH SYSTEM_MODE
    ]) {
      if (
        link.LinkedEntityId == null ||
        link.LinkedEntityId.getSObjectType() != Invoice__c.SObjectType
      ) {
        continue;
      }
      loaded.issuedInvoiceIds.add(link.LinkedEntityId);
      if (!documentToInvoices.containsKey(link.ContentDocumentId)) {
        documentToInvoices.put(link.ContentDocumentId, new List<Id>());
      }
      documentToInvoices.get(link.ContentDocumentId).add(link.LinkedEntityId);
    }
    Map<Id, ContentVersion> latestVersionByInvoice = new Map<Id, ContentVersion>();
    for (ContentVersion version : versions) {
      if (version.IsLatest != true) {
        continue;
      }
      List<Id> invoiceIds = documentToInvoices.get(version.ContentDocumentId);
      if (invoiceIds == null) {
        continue;
      }
      for (Id invoiceId : invoiceIds) {
        ContentVersion current = latestVersionByInvoice.get(invoiceId);
        if (current == null || isLaterIssuedVersion(version, current)) {
          latestVersionByInvoice.put(invoiceId, version);
        }
      }
    }
    for (Id invoiceId : latestVersionByInvoice.keySet()) {
      loaded.latestIssuedByInvoice.put(
        invoiceId,
        latestVersionByInvoice.get(invoiceId).ContentDocumentId
      );
    }
    return loaded;
  }

  /** 仕様: 横断画面.md 操作23。作成日時が最も新しい1つ。同日時は Id 降順。 */
  private static Boolean isLaterIssuedVersion(
    ContentVersion candidate,
    ContentVersion current
  ) {
    if (candidate.CreatedDate > current.CreatedDate) {
      return true;
    }
    if (candidate.CreatedDate < current.CreatedDate) {
      return false;
    }
    return candidate.Id > current.Id;
  }

  private class LineAgg {
    public Boolean hasMonthly;
    public Boolean hasLump;
    public Date nextAcceptance;
  }

  private static void applyInvoiceLineToAgg(
    Map<Id, LineAgg> byInvoice,
    InvoiceLine__c line
  ) {
    LineAgg agg = byInvoice.get(line.Invoice__c);
    if (agg == null) {
      agg = new LineAgg();
      agg.hasMonthly = false;
      agg.hasLump = false;
      byInvoice.put(line.Invoice__c, agg);
    }
    if (line.RevenueRecognitionBasis__c == '月次計上') {
      agg.hasMonthly = true;
    } else if (line.RevenueRecognitionBasis__c == '一括計上') {
      agg.hasLump = true;
      if (
        line.AcceptanceEndDate__c != null &&
        (agg.nextAcceptance == null ||
        line.AcceptanceEndDate__c < agg.nextAcceptance)
      ) {
        agg.nextAcceptance = line.AcceptanceEndDate__c;
      }
    }
  }

  /** 仕様: 横断画面.md 第5節 請求一覧。期間なしの初回明細集計。 */
  private static Map<Id, LineAgg> loadInvoiceLineAgg(Set<Id> invoiceIds) {
    Map<Id, LineAgg> byInvoice = new Map<Id, LineAgg>();
    if (invoiceIds == null || invoiceIds.isEmpty()) {
      return byInvoice;
    }
    for (InvoiceLine__c line : [
      SELECT Invoice__c, RevenueRecognitionBasis__c, AcceptanceEndDate__c
      FROM InvoiceLine__c
      WHERE Invoice__c IN :invoiceIds
      WITH USER_MODE
    ]) {
      applyInvoiceLineToAgg(byInvoice, line);
    }
    return byInvoice;
  }

  @TestVisible
  static Set<Id> lastVersionTotalRemainderInvoiceIds = new Set<Id>();

  /** 仕様: 横断画面.md 第5節 請求一覧、Core 第12.4節・第4.3.11節。Versionの数字。取得行の足し算ではない。一覧済み請求は取り直さない。 */
  private static Map<Id, Decimal> loadVersionInvoiceTotals(
    List<Invoice__c> knownInvoices
  ) {
    Map<Id, Decimal> totals = new Map<Id, Decimal>();
    lastVersionTotalRemainderInvoiceIds = new Set<Id>();
    if (knownInvoices == null || knownInvoices.isEmpty()) {
      return totals;
    }
    Set<Id> historyIds = new Set<Id>();
    Set<Id> knownIds = new Set<Id>();
    for (Invoice__c invoice : knownInvoices) {
      if (invoice.Id != null) {
        knownIds.add(invoice.Id);
      }
      if (invoice.ContractHistory__c == null) {
        continue;
      }
      historyIds.add(invoice.ContractHistory__c);
      if (invoice.InvoiceTransactionStatus__c == 'Cancelled') {
        continue;
      }
      addVersionInvoiceAmount(
        totals,
        invoice.ContractHistory__c,
        invoice.Amount__c
      );
    }
    if (historyIds.isEmpty() || knownIds.isEmpty()) {
      return totals;
    }
    for (Invoice__c remainder : [
      SELECT Id, ContractHistory__c, Amount__c
      FROM Invoice__c
      WHERE
        ContractHistory__c IN :historyIds
        AND InvoiceTransactionStatus__c != 'Cancelled'
        AND Id NOT IN :knownIds
      WITH USER_MODE
    ]) {
      lastVersionTotalRemainderInvoiceIds.add(remainder.Id);
      addVersionInvoiceAmount(
        totals,
        remainder.ContractHistory__c,
        remainder.Amount__c
      );
    }
    return totals;
  }

  private static void addVersionInvoiceAmount(
    Map<Id, Decimal> totals,
    Id historyId,
    Decimal amount
  ) {
    if (historyId == null || amount == null) {
      return;
    }
    Decimal current = totals.get(historyId);
    totals.put(historyId, current == null ? amount : current + amount);
  }

}
