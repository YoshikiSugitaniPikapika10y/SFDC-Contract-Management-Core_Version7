/**
 * 契約期間明細（InvoiceProduct__c）から請求正本（Invoice__c / InvoiceLine__c）を生成・更新する。
 * プレビュー集約ロジック（InvoiceProductMergeService）と同じキーで永続化する。
 */
public without sharing class InvoiceCanonicalService {
  @TestVisible
  private static Boolean testHasEditPreviewPermission;

  public static final String SPLIT_AMOUNT_CONSERVE_MESSAGE = '分割後の金額合計が元の明細金額と一致しません。';

  /** 仕様: Core 第7.6節、第4.4.3節、Accounting 第3.2節 */
  @TestVisible
  private static final String EXISTING_BASIS_LOCKED_MESSAGE = '既存請求明細の売上計上基準は変更できません。';

  public class InvoiceEditException extends Exception {
  }

  /** 仕様: Core 第11.9節、第4.6節、第1.1.10節。無い・空はエラー。HALF_UP 直書きへ落とさない。 */
  private static Decimal roundInvoiceAmount(Decimal value) {
    try {
      return AmountCalculationSettingService.roundAmount(value);
    } catch (AmountCalculationSettingService.SettingException ex) {
      throw new InvoiceEditException(ex.getMessage());
    }
  }

  /** 仕様: Core 第11.9節、第4.6節、第1.1.10節 */
  private static Decimal roundInvoiceQuantityUnitPrice(Decimal value) {
    try {
      return AmountCalculationSettingService.roundQuantityUnitPrice(value);
    } catch (AmountCalculationSettingService.SettingException ex) {
      throw new InvoiceEditException(ex.getMessage());
    }
  }

  public class LineAmountEdit {
    @AuraEnabled
    public Id lineId { get; set; }
    @AuraEnabled
    public Decimal amount { get; set; }
  }

  public class SplitLineInput {
    @AuraEnabled
    public Id lineId { get; set; }
    /**
     * 統一分割のわけ方。
     * whole / unitPrice / quantity / period。未指定は従来の金額移動（moveAmount）。
     */
    @AuraEnabled
    public String splitMode { get; set; }
    @AuraEnabled
    public Decimal moveAmount { get; set; }
    /** 利用月分割時: 移す側の由来期間明細ID（カンマ区切り）。未指定なら従来どおり全コピー */
    @AuraEnabled
    public String moveSourcePeriodLineIds { get; set; }
    /** 利用月分割時: 残す側の由来期間明細ID（カンマ区切り） */
    @AuraEnabled
    public String remainSourcePeriodLineIds { get; set; }
    @AuraEnabled
    public String movePeriodLabel { get; set; }
    @AuraEnabled
    public String remainPeriodLabel { get; set; }
    /**
     * 残す金額。未指定なら current - move。
     * 指定時は move + remain == current 必須（不一致は合計保全エラー）。
     */
    @AuraEnabled
    public Decimal remainAmount { get; set; }
    /** ②-1 単価分割: 移す側単価 */
    @AuraEnabled
    public Decimal moveUnitPrice { get; set; }
    /** ②-1 単価分割: 残す側単価 */
    @AuraEnabled
    public Decimal remainUnitPrice { get; set; }
    /** ②-2 個数分割: 移す側数量 */
    @AuraEnabled
    public Decimal moveQuantity { get; set; }
    /** ②-2 個数分割: 残す側数量 */
    @AuraEnabled
    public Decimal remainQuantity { get; set; }
    /** ②-3 月分割（統一API）: この明細から移す契約期間明細ID */
    @AuraEnabled
    public List<Id> movePeriodLineIds { get; set; }
    /**
     * 同一請求内の月分割: しきい日（その明細の期間月 StartDate）。
     * 指定時は StartDate >= threshold の由来期間を move 側へ解決する。
     */
    @AuraEnabled
    public Date thresholdDate { get; set; }
  }

  /** 同一請求内月分割のしきい日候補（1明細分）。 */
  public class SplitThresholdDateOption {
    @AuraEnabled
    public String label { get; set; }
    /** yyyy-MM-dd */
    @AuraEnabled
    public String value { get; set; }
    /** 明細金額（金額列）ベースの分割元側（しきい日未満の期間按分）。 */
    @AuraEnabled
    public Decimal remainAmount { get; set; }
    /** 明細金額（金額列）ベースの分割先側（しきい日以降の期間按分）。 */
    @AuraEnabled
    public Decimal moveAmount { get; set; }
  }

  public class SplitThresholdLineOptions {
    @AuraEnabled
    public Id invoiceLineId { get; set; }
    @AuraEnabled
    public List<SplitThresholdDateOption> options { get; set; }
  }

  public static final String SPLIT_MODE_WHOLE = 'whole';
  public static final String SPLIT_MODE_UNIT_PRICE = 'unitPrice';
  public static final String SPLIT_MODE_QUANTITY = 'quantity';
  public static final String SPLIT_MODE_PERIOD = 'period';

  public static Boolean canEditInvoicePreview() {
    if (testHasEditPreviewPermission != null) {
      return testHasEditPreviewPermission;
    }
    return ContractPermissionUtil.has(
      ContractPermissionUtil.EDIT_DRAFT_INVOICE
    );
  }

  public static void assertCanEditInvoicePreview() {
    if (!canEditInvoicePreview()) {
      throw new InvoiceEditException(
        '未確定請求を直す権限がありません。'
      );
    }
  }

  /**
   * 対象 Version の請求正本を全削除してから、契約期間明細を集約して作り直す。
   * 手動調整済みでも呼び出し側が許可すれば上書きする（仕様: 警告のうえ全上書き可）。
   */
  /**
   * 期間明細・請求・請求明細は Ordered のみ。対象に非 Ordered が混ざったらエラー。
   */
  public static void assertHistoriesAreOrdered(Set<Id> contractHistoryIds) {
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return;
    }
    Set<Id> orderedIds = retainOrderedHistoryIds(contractHistoryIds);
    if (orderedIds.size() != contractHistoryIds.size()) {
      throw new InvoiceEditException(
        '期間明細・請求・請求明細は受注済みの契約履歴にのみ作成できます。'
      );
    }
  }

  /** 引数のうち historystatus = Ordered の履歴 ID だけ残す。 */
  public static Set<Id> retainOrderedHistoryIds(Set<Id> contractHistoryIds) {
    Set<Id> orderedIds = new Set<Id>();
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return orderedIds;
    }
    String orderedStatus = ContractDomainConstants.HISTORY_STATUS_ORDERED;
    for (ContractHistory__c history : [
      SELECT Id
      FROM ContractHistory__c
      WHERE Id IN :contractHistoryIds AND historystatus__c = :orderedStatus
      WITH SYSTEM_MODE
    ]) {
      orderedIds.add(history.Id);
    }
    return orderedIds;
  }

  /**
   * 契約履歴に紐づく請求正本（明細 MD 含む）と契約期間明細を削除する。
   * Ordered 以外へ落ちたとき／削除時の不変条件維持用。
   */
  public static void purgeBillingForHistories(Set<Id> contractHistoryIds) {
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return;
    }
    List<Invoice__c> invoices = [
      SELECT Id, InvoiceTransactionStatus__c
      FROM Invoice__c
      WHERE ContractHistory__c IN :contractHistoryIds
      WITH SYSTEM_MODE
    ];
    List<Invoice__c> deletable = new List<Invoice__c>();
    for (Invoice__c invoice : invoices) {
      if (InvoiceTransactionStatusService.isCancelled(invoice)) {
        continue;
      }
      deletable.add(invoice);
    }
    if (!deletable.isEmpty()) {
      SystemContextAccess.deleteRecords(deletable);
    }
    List<InvoiceProduct__c> invoiceProducts = [
      SELECT Id
      FROM InvoiceProduct__c
      WHERE ContractHistory__c IN :contractHistoryIds
      WITH SYSTEM_MODE
    ];
    if (!invoiceProducts.isEmpty()) {
      SystemContextAccess.deleteRecords(invoiceProducts);
    }
  }

  public static void rebuildForHistories(Set<Id> contractHistoryIds) {
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return;
    }
    ContractHistoryStatusPathService.beginPathSyncDefer();
    try {
      assertHistoriesAreOrdered(contractHistoryIds);
      // ロック判定と削除を1クエリにまとめ、受注時の SOQL 消費を抑える
      List<Invoice__c> existing = [
        SELECT
          Id,
          SystemIntegrationDate__c,
          PaymentClearingCompletedDate__c,
          InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE ContractHistory__c IN :contractHistoryIds
        WITH SYSTEM_MODE
      ];
      List<Invoice__c> deletable = new List<Invoice__c>();
      for (Invoice__c invoice : existing) {
        if (InvoiceTransactionStatusService.isCancelled(invoice)) {
          continue;
        }
        if (InvoiceLockUtil.isActiveConfirmed(invoice)) {
          throw new InvoiceLockUtil.InvoiceLockException(
            InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE
          );
        }
        deletable.add(invoice);
      }
      if (!deletable.isEmpty()) {
        SystemContextAccess.deleteRecords(deletable);
      }
      persistFromPeriodLines(contractHistoryIds);
    } finally {
      ContractHistoryStatusPathService.endPathSyncDefer();
    }
  }

  public static void deleteInvoicesForHistories(Set<Id> contractHistoryIds) {
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return;
    }
    ContractHistoryStatusPathService.beginPathSyncDefer();
    try {
      List<Invoice__c> invoices = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c IN :contractHistoryIds
        WITH SYSTEM_MODE
      ];
      if (!invoices.isEmpty()) {
        SystemContextAccess.deleteRecords(invoices);
      }
    } finally {
      ContractHistoryStatusPathService.endPathSyncDefer();
    }
  }

  private static void persistFromPeriodLines(Set<Id> contractHistoryIds) {
    // 非 Ordered には請求正本を作らない（バックフィル混入防止）
    contractHistoryIds = retainOrderedHistoryIds(contractHistoryIds);
    if (contractHistoryIds.isEmpty()) {
      return;
    }
    // 仕様: Core 第11.4.2節
    FieldCopyDefinitionService.validateAllDefinitions();
    List<InvoiceProduct__c> products = queryPeriodLinesForCanonical(
      contractHistoryIds
    );
    if (products.isEmpty()) {
      return;
    }

    Map<Id, BillingAccount__c> billingAccountById = loadBillingAccountsForProducts(
      products
    );

    List<InvoiceProductMergeService.MergedInvoice> merged = InvoiceProductMergeService.buildMergedInvoices(
      products
    );
    List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
    List<List<InvoiceProductMergeService.MergedLine>> linesByInvoiceIndex = new List<List<InvoiceProductMergeService.MergedLine>>();
    List<List<InvoiceProduct__c>> sourcesByInvoiceIndex = new List<List<InvoiceProduct__c>>();

    for (InvoiceProductMergeService.MergedInvoice mi : merged) {
      Invoice__c invoice = new Invoice__c();
      InvoiceProduct__c rep = mi.sourceProducts == null ||
        mi.sourceProducts.isEmpty()
        ? null
        : mi.sourceProducts[0];
      if (rep != null) {
        invoice.ContractHistory__c = rep.ContractHistory__c;
        invoice.ContractService__c = rep.ContractHistory__r == null
          ? null
          : rep.ContractHistory__r.ContractService__c;
      }
      invoice.MergeKey__c = mi.mergeKey;
      invoice.InvoiceDate__c = mi.invoiceDate;
      invoice.PaymentScheduledDate__c = mi.paymentScheduledDate;
      invoice.Amount__c = mi.amountTotal;
      invoice.TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(
        mi.taxPercent
      );
      invoice.TaxAmount__c = mi.taxTotal;
      invoice.PeriodLineAmountTotal__c = mi.amountTotal;
      clearInvoiceManualFlags(invoice);
      invoice.SourcePeriodLineIds__c = joinIds(
        collectSourceIds(mi.sourceProducts)
      );
      // 連携日／消込日は Ops が請求書に付与する。期間明細からはコピーしない。
      invoice.SystemIntegrationDate__c = null;
      invoice.PaymentClearingCompletedDate__c = null;

      // BA SnapShot（必須）はハードコード。CMDT は顧客／サンプル拡張のみ。
      Id billingAccountId = resolveBillingAccountId(rep);
      BillingAccount__c billingAccount = billingAccountById.get(
        billingAccountId
      );
      applyHardcodedBillingAccountSnapshot(invoice, billingAccount);
      FieldCopyDefinitionService.apply(
        invoice,
        InvoiceProductFieldCopyService.TARGET_INVOICE,
        null,
        buildCanonicalCopySources(rep, billingAccount)
      );

      invoicesToInsert.add(invoice);
      linesByInvoiceIndex.add(mi.lines);
      sourcesByInvoiceIndex.add(mi.sourceProducts);
    }

    if (invoicesToInsert.isEmpty()) {
      return;
    }
    SystemContextAccess.insertRecords(invoicesToInsert);

    List<InvoiceLine__c> linesToInsert = new List<InvoiceLine__c>();
    for (Integer i = 0; i < invoicesToInsert.size(); i++) {
      Invoice__c parent = invoicesToInsert[i];
      List<InvoiceProductMergeService.MergedLine> lines = linesByInvoiceIndex[
        i
      ];
      if (lines == null) {
        continue;
      }
      for (InvoiceProductMergeService.MergedLine ml : lines) {
        InvoiceLine__c line = new InvoiceLine__c();
        line.Invoice__c = parent.Id;
        line.LineMergeKey__c = ml.lineMergeKey;
        line.ProductName__c = ml.productName;
        line.UnitPrice__c = ml.unitPrice;
        line.Quantity__c = ml.quantity;
        line.Amount__c = ml.amount;
        line.PeriodLabel__c = ml.periodLabel;
        line.HistoryVersionLabel__c = ml.historyVersionLabel;
        clearLineManualFlags(line);
        line.SourcePeriodLineIds__c = joinIds(ml.sourceInvoiceProductIds);
        line.ServicePeriodStartDate__c = ml.servicePeriodStartDate;
        line.ServicePeriodEndDate__c = ml.servicePeriodEndDate;
        line.RevenueRecognitionBasis__c = ml.revenueRecognitionBasis;
        line.AcceptanceEndDate__c = acceptanceEndDateForNewLine(ml.revenueRecognitionBasis, ml.servicePeriodEndDate);
        ContractProduct__c sourceContractProduct = null;
        if (ml.sourceProducts != null && !ml.sourceProducts.isEmpty()) {
          InvoiceProduct__c sourcePeriod = ml.sourceProducts[0];
          if (sourcePeriod.ContractProduct__c != null) {
            line.ContractProduct__c = sourcePeriod.ContractProduct__c;
          }
          // コア直書き（商品名・単価・数量・金額・契約商品）
          if (sourcePeriod.ContractProduct__r != null) {
            sourceContractProduct = sourcePeriod.ContractProduct__r;
            line.Product__c = sourceContractProduct.Product__c;
            line.Unit__c = sourceContractProduct.Unit__c;
          }
        }
        FieldCopyDefinitionService.apply(
          line,
          InvoiceProductFieldCopyService.TARGET_INVOICE_LINE,
          null,
          buildCanonicalCopySources(
            ml.sourceProducts == null || ml.sourceProducts.isEmpty()
              ? null
              : ml.sourceProducts[0],
            null
          )
        );
        linesToInsert.add(line);
      }
    }
    if (!linesToInsert.isEmpty()) {
      SystemContextAccess.insertRecords(linesToInsert);
    }
    // 請求の正本は Invoice。期間明細の請求寄せ項目は項目削除済みのためクリア不要。
  }

  /**
   * 請求プレビュー編集: 請求明細金額のみ更新し、親請求の税抜・税額を同期する。
   * 契約期間明細・契約履歴・請求アカウント等の上流マスタは更新しない。
   */
  public static void updateLineAmount(Id lineId, Decimal newAmount) {
    LineAmountEdit edit = new LineAmountEdit();
    edit.lineId = lineId;
    edit.amount = newAmount;
    updateLineAmounts(new List<LineAmountEdit>{ edit });
  }

  /**
   * 請求プレビュー編集: 複数明細の金額を一括更新し、親請求へ税抜・税額を同期する。
   * DML 対象は InvoiceLine__c / Invoice__c のみ。
   * 仕様: Core 第11.9節、第7.8節、第1.1.10節
   */
  public static void updateLineAmounts(List<LineAmountEdit> edits) {
    ContractHistoryStatusPathService.beginPathSyncDefer();
    try {
      updateLineAmountsBody(edits);
    } finally {
      ContractHistoryStatusPathService.endPathSyncDefer();
    }
  }

  private static void updateLineAmountsBody(List<LineAmountEdit> edits) {
    assertCanEditInvoicePreview();
    if (edits == null || edits.isEmpty()) {
      throw new InvoiceEditException('明細と金額は必須です。');
    }

    Map<Id, Decimal> amountByLineId = new Map<Id, Decimal>();
    for (LineAmountEdit edit : edits) {
      if (edit == null || edit.lineId == null || edit.amount == null) {
        throw new InvoiceEditException('明細と金額は必須です。');
      }
      amountByLineId.put(edit.lineId, roundInvoiceAmount(edit.amount));
    }

    List<InvoiceLine__c> lines = [
      SELECT Id, Amount__c, Invoice__c, Invoice__r.ContractHistory__c
      FROM InvoiceLine__c
      WHERE Id IN :amountByLineId.keySet()
      WITH SYSTEM_MODE
    ];
    if (lines.size() != amountByLineId.size()) {
      throw new InvoiceEditException('更新対象の明細が見つかりません。');
    }

    Set<Id> invoiceIds = new Set<Id>();
    for (InvoiceLine__c line : lines) {
      invoiceIds.add(line.Invoice__c);
    }
    InvoiceLockUtil.assertInvoicesEditable(invoiceIds);

    for (InvoiceLine__c line : lines) {
      line.Amount__c = amountByLineId.get(line.Id);
      markLineAmountAdjusted(line);
    }
    SystemContextAccess.updateRecords(lines);
    for (Id invoiceId : invoiceIds) {
      markInvoiceAmountAdjustedAndRecalc(invoiceId);
    }
  }

  /**
   * 請求プレビュー編集: 請求明細の検収終了日のみ更新する。
   * 金額系の編集と違い、確定済み請求でも編集を許す（InvoiceLockUtil を通さない）。
   * 仕様: Core 第7.6節、第7.9.6節、日付仕様 第6.1節・第7.3節、Accounting 第8.2節、第8.5節、第8.8節
   * 取消基準日は呼び出し側が渡す。null 固定の省略経路は持たない。
   */
  public static void updateLineAcceptanceEndDates(
    Map<Id, Date> acceptanceEndDateByLineId,
    Date cancellationDate
  ) {
    updateLineAcceptanceEndDates(acceptanceEndDateByLineId, cancellationDate, null);
  }

  /** 仕様: Core 第7.6節、第7.9.6節、第7.9.7節、日付仕様 第6.1節・第7.3節、Accounting 第8.2節、第8.5節、第8.8節 */
  public static void updateLineAcceptanceEndDates(
    Map<Id, Date> acceptanceEndDateByLineId,
    Date cancellationDate,
    String businessOperationKey
  ) {
    updateLineAcceptanceEndDates(
      acceptanceEndDateByLineId,
      cancellationDate,
      businessOperationKey,
      null
    );
  }

  /** 仕様: Core 第7.6節、第7.9.6節、第7.9.7節、日付仕様 第6.1節・第7.3節、Accounting 第8.2節、第8.5節、第8.8節 */
  public static void updateLineAcceptanceEndDates(
    Map<Id, Date> acceptanceEndDateByLineId,
    Date cancellationDate,
    String businessOperationKey,
    String expectedToken
  ) {
    List<InvoiceLine__c> lines = loadAcceptanceLines(acceptanceEndDateByLineId);
    Set<Id> confirmedInvoiceIds = lockConfirmedAcceptanceInvoices(
      lines,
      cancellationDate
    );
    Set<Id> invoiceIds = new Set<Id>();
    for (InvoiceLine__c line : lines) {
      invoiceIds.add(line.Invoice__c);
    }
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      invoiceIds.size() == 1 ? businessOperationKey : null
    );
    if (String.isNotBlank(businessOperationKey) && invoiceIds.size() == 1) {
      Id invoiceId = new List<Id>(invoiceIds)[0];
      Invoice__c locked = [
        SELECT BusinessOperationKey__c
        FROM Invoice__c
        WHERE Id = :invoiceId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (locked.BusinessOperationKey__c == operationKey) {
        return;
      }
    }
    // 仕様: Core 第4.3.12節・第7.9.7節。比較値未指定は拒否。検査省略の互換は持たない。
    for (Id invoiceId : invoiceIds) {
      AccountingCauseLockService.assertInvoiceOperationUnchanged(
        invoiceId,
        expectedToken
      );
    }
    for (InvoiceLine__c line : lines) {
      line.AcceptanceEndDate__c = acceptanceEndDateByLineId.get(line.Id);
    }
    SystemContextAccess.updateRecords(lines);
    applyAcceptanceAccounting(
      confirmedInvoiceIds,
      cancellationDate,
      businessOperationKey
    );
  }

  /** 仕様: Core 第7.6節、第7.9.6節、Accounting 第8.5節・第8.8節、日付仕様 第7.3節 */
  public static AccountingDiffService.CancelPreview previewLineAcceptanceEndDates(
    Map<Id, Date> acceptanceEndDateByLineId,
    Date cancellationDate
  ) {
    List<InvoiceLine__c> lines = loadAcceptanceLines(acceptanceEndDateByLineId);
    Set<Id> confirmedInvoiceIds = lockConfirmedAcceptanceInvoices(
      lines,
      cancellationDate
    );
    if (!isAccountingEnabledForAcceptance(confirmedInvoiceIds)) {
      AccountingDiffService.CancelPreview empty = new AccountingDiffService.CancelPreview();
      empty.logicalDeleteCount = 0;
      empty.reverseCount = 0;
      empty.reverseDateCounts = new List<AccountingDiffService.ReverseDateCount>();
      empty.hasFutureReverseDate = false;
      empty.displayText = AccountingDiffService.toDisplayText(empty);
      return empty;
    }
    Savepoint savepoint = Database.setSavepoint();
    try {
      for (InvoiceLine__c line : lines) {
        line.AcceptanceEndDate__c = acceptanceEndDateByLineId.get(line.Id);
      }
      SystemContextAccess.updateRecords(lines);
      AccountingDiffService.CancelPreview preview = new AccountingDiffService.CancelPreview();
      preview.logicalDeleteCount = 0;
      preview.reverseCount = 0;
      preview.reverseDateCounts = new List<AccountingDiffService.ReverseDateCount>();
      preview.hasFutureReverseDate = false;
      Map<Date, Integer> countByDate = new Map<Date, Integer>();
      for (Id invoiceId : confirmedInvoiceIds) {
        AccountingDiffService.CancelPreview one = AccountingDiffService.previewApply(
          invoiceId,
          AccountingEventFixedCatalog.ACCEPTANCE_DATE_CHANGED.key,
          cancellationDate
        );
        preview.logicalDeleteCount += one.logicalDeleteCount == null
          ? 0
          : one.logicalDeleteCount;
        preview.reverseCount += one.reverseCount == null ? 0 : one.reverseCount;
        if (one.hasFutureReverseDate == true) {
          preview.hasFutureReverseDate = true;
        }
        if (one.reverseDateCounts == null) {
          continue;
        }
        for (AccountingDiffService.ReverseDateCount row : one.reverseDateCounts) {
          Integer currentCount = countByDate.containsKey(row.reverseDate)
            ? countByDate.get(row.reverseDate)
            : 0;
          countByDate.put(
            row.reverseDate,
            currentCount + (row.journalCount == null ? 0 : row.journalCount)
          );
        }
      }
      List<Date> dates = new List<Date>(countByDate.keySet());
      dates.sort();
      for (Date reverseDate : dates) {
        AccountingDiffService.ReverseDateCount row = new AccountingDiffService.ReverseDateCount();
        row.reverseDate = reverseDate;
        row.journalCount = countByDate.get(reverseDate);
        preview.reverseDateCounts.add(row);
      }
      preview.displayText = AccountingDiffService.toDisplayText(preview);
      Database.rollback(savepoint);
      return preview;
    } catch (Exception ex) {
      Database.rollback(savepoint);
      throw ex;
    }
  }

  /** 仕様: Core 第1.1.10節、第7.6節、Accounting 第8.2節、第1.1節、第1.8.1節、第8.5節、第8.8節 */
  private static void applyAcceptanceAccounting(
    Set<Id> invoiceIds,
    Date cancellationDate,
    String businessOperationKey
  ) {
    if (!isAccountingEnabledForAcceptance(invoiceIds)) {
      return;
    }
    for (Id invoiceId : invoiceIds) {
      String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
        invoiceIds.size() == 1 ? businessOperationKey : null
      );
      writeInvoiceOperationKey(invoiceId, operationKey);
      AccountingDiffService.applyForInvoice(
        invoiceId,
        AccountingEventFixedCatalog.ACCEPTANCE_DATE_CHANGED.key,
        operationKey,
        cancellationDate
      );
    }
  }

  /** 仕様: Core 第7.9.7節 */
  private static void writeInvoiceOperationKey(Id invoiceId, String operationKey) {
    if (invoiceId == null || String.isBlank(operationKey)) {
      return;
    }
    Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
    InvoiceLockUtil.allowLockedStatusWrite = true;
    try {
      SystemContextAccess.updateRecords(
        new List<Invoice__c>{
          new Invoice__c(Id = invoiceId, BusinessOperationKey__c = operationKey)
        }
      );
    } finally {
      InvoiceLockUtil.allowLockedStatusWrite = previousLock;
    }
  }

  private static Boolean isAccountingEnabledForAcceptance(Set<Id> invoiceIds) {
    if (invoiceIds == null || invoiceIds.isEmpty()) {
      return false;
    }
    GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
    if (policy.AccountingEnabled__c == true) {
      return true;
    }
    for (Id invoiceId : invoiceIds) {
      if (hasActiveCurrent(invoiceId)) {
        throw new InvoiceEditException(
          'Accounting OFFで過去の関連仕訳があるため検収終了日を変更できません。'
        );
      }
    }
    return false;
  }

  /**
   * 仕様: Core 第7.6節・第7.7.3節・第7.7.0節。
   * 検収終了日変更は請求ボードの操作。未確定請求を直す権限（10）を見る。
   */
  private static List<InvoiceLine__c> loadAcceptanceLines(
    Map<Id, Date> acceptanceEndDateByLineId
  ) {
    assertCanEditInvoicePreview();
    if (acceptanceEndDateByLineId == null || acceptanceEndDateByLineId.isEmpty()) {
      throw new InvoiceEditException('明細は必須です。');
    }
    List<InvoiceLine__c> lines = [
      SELECT
        Id,
        AcceptanceEndDate__c,
        RevenueRecognitionBasis__c,
        Invoice__c,
        Invoice__r.InvoiceTransactionStatus__c
      FROM InvoiceLine__c
      WHERE Id IN :acceptanceEndDateByLineId.keySet()
      WITH SYSTEM_MODE
    ];
    if (lines.size() != acceptanceEndDateByLineId.size()) {
      throw new InvoiceEditException('更新対象の明細が見つかりません。');
    }
    for (InvoiceLine__c line : lines) {
      Date nextDate = acceptanceEndDateByLineId.get(line.Id);
      if (nextDate == null) {
        throw new InvoiceEditException('検収終了日は空にできません。');
      }
      // 仕様: Core 第1.1.5節・第7.6節・第12.2節。取消済みは編集対象にしない。
      if (InvoiceTransactionStatusService.isCancelled(line.Invoice__r)) {
        throw new InvoiceEditException('取消済み請求の検収終了日は変更できません。');
      }
      if (
        ContractMetadataService.normalizeRevenueRecognitionBasis(
          line.RevenueRecognitionBasis__c
        ) == ContractMetadataService.REVENUE_BASIS_OVER_TIME
      ) {
        throw new InvoiceEditException('月次計上に検収終了日は設定できません。');
      }
    }
    return lines;
  }

  private static Set<Id> lockConfirmedAcceptanceInvoices(
    List<InvoiceLine__c> lines,
    Date cancellationDate
  ) {
    Set<Id> confirmedInvoiceIds = new Set<Id>();
    Set<Id> allInvoiceIds = new Set<Id>();
    for (InvoiceLine__c line : lines) {
      allInvoiceIds.add(line.Invoice__c);
      if (InvoiceTransactionStatusService.isConfirmed(line.Invoice__r)) {
        confirmedInvoiceIds.add(line.Invoice__c);
      }
    }
    List<Id> lockOrder = new List<Id>(allInvoiceIds);
    lockOrder.sort();
    for (Id invoiceId : lockOrder) {
      AccountingCauseLockService.lockInvoice(invoiceId);
    }
    if (!allInvoiceIds.isEmpty()) {
      Integer lockedJournals = [
        SELECT COUNT()
        FROM GlJournal__c
        WHERE
          Invoice__c IN :allInvoiceIds
          AND IsLocked__c = TRUE
          AND TransactionStatus__c = 'Active'
        WITH SYSTEM_MODE
      ];
      if (lockedJournals > 0 && cancellationDate == null) {
        throw new InvoiceEditException(
          'ロック済み仕訳がある取消では取消基準日が必要です。'
        );
      }
    }
    return confirmedInvoiceIds;
  }

  /** 仕様: Accounting 第1.1節、第1.8.1節。Currentは論理削除・取消済元・取消仕訳を数えない。 */
  private static Boolean hasActiveCurrent(Id invoiceId) {
    for (GlJournal__c journal : AccountingCurrentService.load(invoiceId)) {
      if (journal.TransactionStatus__c == 'Active') {
        return true;
      }
    }
    return false;
  }

  /**
   * 請求ボード「請求情報編集」: 請求日・入金予定日だけを同一 Invoice へ 1 DML で更新する。
   * 宛名・メール・税率引数は互換のため残すが書き込まない。
   * 仕様: Core 第7.8節
   */
  public static void updateInvoiceHeaderAndDates(
    Id invoiceId,
    Date invoiceDate,
    Date paymentScheduledDate,
    Id billingAccountId,
    String billingAddressee,
    String billingEmailTo,
    String billingEmailCc,
    String billingEmailBcc,
    String paymentTerm,
    Decimal taxPercent
  ) {
    updateInvoiceHeaderAndDates(
      invoiceId,
      invoiceDate,
      paymentScheduledDate,
      billingAccountId,
      billingAddressee,
      billingEmailTo,
      billingEmailCc,
      billingEmailBcc,
      paymentTerm,
      taxPercent,
      null
    );
  }

  /** 仕様: Core 第7.8節、第7.9.2節、第11.4.4節。未確定は請求日・入金予定日。税率は書かない。確定後は日付・請求アカウントを拒否し、ロック除外の追加項目だけ残す。 */
  public static void updateInvoiceHeaderAndDates(
    Id invoiceId,
    Date invoiceDate,
    Date paymentScheduledDate,
    Id billingAccountId,
    String billingAddressee,
    String billingEmailTo,
    String billingEmailCc,
    String billingEmailBcc,
    String paymentTerm,
    Decimal taxPercent,
    Map<String, Object> extraFieldValues
  ) {
    assertCanEditInvoicePreview();
    if (invoiceId == null) {
      throw new InvoiceEditException('請求は必須です。');
    }
    // billingAccountId / paymentTerm は Aura 互換のため残すが意図的に未使用。
    Invoice__c invoice = [
      SELECT
        Id,
        ContractHistory__c,
        InvoiceDate__c,
        PaymentScheduledDate__c,
        Amount__c,
        TaxPercent__c,
        TaxAmount__c,
        BillingAddresseeSnapShot__c,
        BillingEmailToSnapShot__c,
        BillingEmailCcSnapShot__c,
        BillingEmailBccSnapShot__c,
        SystemIntegrationDate__c,
        PaymentClearingCompletedDate__c,
        InvoiceTransactionStatus__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (InvoiceTransactionStatusService.isCancelled(invoice)) {
      throw new InvoiceEditException(InvoiceLockUtil.INVOICE_EDIT_BLOCK_MESSAGE);
    }
    Boolean confirmed = InvoiceTransactionStatusService.isConfirmed(invoice);
    if (!confirmed) {
      InvoiceLockUtil.assertInvoiceEditable(invoice);
    }
    if (confirmed) {
      if (
        (invoiceDate != null && invoiceDate != invoice.InvoiceDate__c) ||
        (paymentScheduledDate != null &&
        paymentScheduledDate != invoice.PaymentScheduledDate__c)
      ) {
        throw new InvoiceEditException(
          InvoiceLockUtil.CONFIRMED_CORE_FIELDS_BLOCK_MESSAGE
        );
      }
    } else {
      if (invoiceDate == null) {
        throw new InvoiceEditException('請求日は必須です。');
      }
      if (paymentScheduledDate == null) {
        throw new InvoiceEditException('入金予定日は必須です。');
      }
      invoice.InvoiceDate__c = invoiceDate;
      invoice.PaymentScheduledDate__c = paymentScheduledDate;
      // 仕様: Core 第7.8節。税率は請求情報編集の対象外。書かない。
      markInvoiceHeaderTouched(invoice);
      invoice.MergeKey__c = null;
    }
    Set<String> extraAllowed = InvoiceOpsFieldService.fieldApiNames('Invoice__c');
    if (confirmed) {
      extraAllowed.retainAll(InvoiceLockUtil.resolveLockExemptFieldNames());
      extraAllowed.removeAll(
        new Set<String>{
          'InvoiceDate__c',
          'PaymentScheduledDate__c',
          'TaxPercent__c',
          'BillingAccountSnapShot__c'
        }
      );
    }
    InvoiceOpsFieldService.applyDisplayedValues(
      invoice,
      'Invoice__c',
      extraFieldValues,
      extraAllowed
    );
    SystemContextAccess.updateRecords(new List<Invoice__c>{ invoice });
  }

  /** 仕様: Core 第7.8節。宛名・To/Cc/Bcc・届け方を請求アカウントから載せ直す。 */
  public static void applyBillingAccountContent(Id invoiceId) {
    assertCanEditInvoicePreview();
    if (invoiceId == null) {
      throw new InvoiceEditException('請求は必須です。');
    }
    Invoice__c invoice = [
      SELECT
        Id,
        BillingAccountSnapShot__c,
        InvoiceDate__c,
        PaymentScheduledDate__c,
        TaxPercent__c,
        BillingAccountKeySnapShot__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    InvoiceLockUtil.assertInvoiceEditable(invoice);
    if (invoice.BillingAccountSnapShot__c == null) {
      throw new InvoiceEditException('請求アカウントがありません。');
    }
    BillingAccount__c account = [
      SELECT
        Id,
        BillingAddressee__c,
        BillingEmailTo__c,
        BillingEmailCc__c,
        BillingEmailBcc__c,
        InvoiceDeliveryMethod__c
      FROM BillingAccount__c
      WHERE Id = :invoice.BillingAccountSnapShot__c
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    invoice.BillingAddresseeSnapShot__c = account.BillingAddressee__c;
    invoice.BillingEmailToSnapShot__c = account.BillingEmailTo__c;
    invoice.BillingEmailCcSnapShot__c = account.BillingEmailCc__c;
    invoice.BillingEmailBccSnapShot__c = account.BillingEmailBcc__c;
    invoice.InvoiceDeliveryMethodSnapShot__c = account.InvoiceDeliveryMethod__c;
    SystemContextAccess.updateRecords(new List<Invoice__c>{ invoice });
  }

  /**
   * 同一請求内の明細分割（concept わける）。新 Invoice__c は作らず、
   * 選択明細ごとに移す分の InvoiceLine__c を同一請求へ新規作成し、元明細を残す側へ更新する。
   * 対応モード: unitPrice / quantity / period。端数・手動調整はクリアする。
   */
  public static void splitLinesInPlace(
    Id invoiceId,
    List<SplitLineInput> splitLines
  ) {
    ContractHistoryStatusPathService.beginPathSyncDefer();
    try {
      splitLinesInPlaceBody(invoiceId, splitLines);
    } finally {
      ContractHistoryStatusPathService.endPathSyncDefer();
    }
  }

  private static void splitLinesInPlaceBody(
    Id invoiceId,
    List<SplitLineInput> splitLines
  ) {
    assertCanEditInvoicePreview();
    // 仕様: Core 第11.4.2節
    FieldCopyDefinitionService.validateAllDefinitions();
    if (invoiceId == null || splitLines == null || splitLines.isEmpty()) {
      throw new InvoiceEditException('分割元請求・分割内容は必須です。');
    }

    Invoice__c source = [
      SELECT
        Id,
        Amount__c,
        PeriodLineAmountTotal__c,
        SystemIntegrationDate__c,
        PaymentClearingCompletedDate__c,
        InvoiceTransactionStatus__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    InvoiceLockUtil.assertInvoiceEditable(source);

    Map<Id, InvoiceLine__c> sourceLineById = new Map<Id, InvoiceLine__c>(
      [
        SELECT
          Id,
          Amount__c,
          ProductName__c,
          Product__c,
          Unit__c,
          UnitPrice__c,
          Quantity__c,
          PeriodLabel__c,
          LineMergeKey__c,
          HistoryVersionLabel__c,
          SourcePeriodLineIds__c,
          ServicePeriodStartDate__c,
          ServicePeriodEndDate__c,
          RevenueRecognitionBasis__c,
          IsManuallyAdjusted__c,
          IsAmountAdjusted__c,
          IsSplitMoved__c,
          ContractProduct__c,
          ContractProduct__r.Product__c,
          ContractProduct__r.Unit__c,
          ContractProduct__r.BillingType__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoiceId
        WITH SYSTEM_MODE
      ]
    );
    if (sourceLineById.isEmpty()) {
      throw new InvoiceEditException('分割対象の明細が見つかりません。');
    }

    Set<Id> targetLineIds = new Set<Id>();
    for (SplitLineInput raw : splitLines) {
      if (raw != null && raw.lineId != null) {
        targetLineIds.add(raw.lineId);
      }
    }
    // 単価／数量／期間分割の前に、対象明細の端数調整を由来期間合計へ戻す
    resetFactorSplitLineAmountsToSource(
      invoiceId,
      targetLineIds,
      sourceLineById
    );

    Set<Id> periodMoveIds = new Set<Id>();
    Set<Id> periodRestrictLineIds = new Set<Id>();
    List<SplitLineInput> normalized = new List<SplitLineInput>();

    for (SplitLineInput raw : splitLines) {
      if (raw == null || raw.lineId == null) {
        continue;
      }
      InvoiceLine__c sourceLine = sourceLineById.get(raw.lineId);
      if (sourceLine == null) {
        throw new InvoiceEditException('分割対象の明細が見つかりません。');
      }
      String mode = String.isBlank(raw.splitMode) ? null : raw.splitMode.trim();
      if (
        mode != SPLIT_MODE_UNIT_PRICE &&
        mode != SPLIT_MODE_QUANTITY &&
        mode != SPLIT_MODE_PERIOD
      ) {
        throw new InvoiceEditException(
          '同一請求内分割は単価・個数・月分割のみです: ' +
          sourceLine.ProductName__c
        );
      }
      if (mode == SPLIT_MODE_PERIOD) {
        if (
          !ContractMetadataService.isRecurringBillingType(
            sourceLine.ContractProduct__r == null
              ? null
              : sourceLine.ContractProduct__r.BillingType__c
          )
        ) {
          throw new InvoiceEditException(
            '月分割は継続課金明細のみです: ' + sourceLine.ProductName__c
          );
        }
        List<Id> resolvedMoveIds = resolvePeriodMoveIdsForLine(raw, sourceLine);
        for (Id periodId : resolvedMoveIds) {
          if (periodId != null) {
            periodMoveIds.add(periodId);
          }
        }
        periodRestrictLineIds.add(raw.lineId);
        continue;
      }
      normalized.add(normalizeFactorSplitInput(raw, sourceLine, mode));
    }

    if (!periodMoveIds.isEmpty()) {
      List<SplitLineInput> periodNormalized = buildPeriodSplitInputs(
        invoiceId,
        periodMoveIds,
        periodRestrictLineIds
      );
      for (SplitLineInput periodInput : periodNormalized) {
        periodInput.splitMode = SPLIT_MODE_PERIOD;
        normalized.add(periodInput);
      }
    }
    if (normalized.isEmpty()) {
      throw new InvoiceEditException('移動する明細がありません。');
    }

    Map<Id, SplitLineInput> inputByLineId = new Map<Id, SplitLineInput>();
    for (SplitLineInput input : normalized) {
      if (input == null || input.lineId == null || input.moveAmount == null) {
        continue;
      }
      Decimal move = roundInvoiceAmount(input.moveAmount);
      // 仕様: Core 第7.8.4節、第1.1.4節
      if (
        move == 0 &&
        input.splitMode != SPLIT_MODE_UNIT_PRICE &&
        input.splitMode != SPLIT_MODE_QUANTITY
      ) {
        continue;
      }
      input.moveAmount = move;
      if (input.remainAmount != null) {
        input.remainAmount = roundInvoiceAmount(input.remainAmount);
      }
      inputByLineId.put(input.lineId, input);
    }
    if (inputByLineId.isEmpty()) {
      throw new InvoiceEditException('移動する金額がありません。');
    }

    List<InvoiceLine__c> newLines = new List<InvoiceLine__c>();
    List<InvoiceLine__c> sourceUpdates = new List<InvoiceLine__c>();
    List<InvoiceLine__c> sourceDeletes = new List<InvoiceLine__c>();

    for (Id lineId : inputByLineId.keySet()) {
      InvoiceLine__c sourceLine = sourceLineById.get(lineId);
      SplitLineInput input = inputByLineId.get(lineId);
      Decimal move = input.moveAmount;
      Decimal current = sourceLine.Amount__c == null ? 0 : sourceLine.Amount__c;
      if (isMoveAmountOutOfRange(move, current)) {
        throw new InvoiceEditException(
          '移動金額が明細金額を超えています: ' + sourceLine.ProductName__c
        );
      }

      InvoiceLine__c createdLine = new InvoiceLine__c();
      createdLine.Invoice__c = invoiceId;
      createdLine.ProductName__c = sourceLine.ProductName__c;
      createdLine.UnitPrice__c = input.moveUnitPrice != null
        ? input.moveUnitPrice
        : sourceLine.UnitPrice__c;
      createdLine.Quantity__c = input.moveQuantity != null
        ? input.moveQuantity
        : sourceLine.Quantity__c;
      createdLine.Amount__c = move;
      createdLine.PeriodLabel__c = String.isNotBlank(input.movePeriodLabel)
        ? input.movePeriodLabel
        : sourceLine.PeriodLabel__c;
      createdLine.HistoryVersionLabel__c = sourceLine.HistoryVersionLabel__c;
      createdLine.SourcePeriodLineIds__c = input.moveSourcePeriodLineIds != null
        ? input.moveSourcePeriodLineIds
        : sourceLine.SourcePeriodLineIds__c;
      createdLine.RevenueRecognitionBasis__c = sourceLine.RevenueRecognitionBasis__c;
      applyServicePeriodSnapshot(
        createdLine,
        sourceLine,
        createdLine.SourcePeriodLineIds__c
      );
      createdLine.ContractProduct__c = sourceLine.ContractProduct__c;
      if (sourceLine.ContractProduct__r != null) {
        createdLine.Product__c = sourceLine.ContractProduct__r.Product__c;
      } else {
        createdLine.Product__c = sourceLine.Product__c;
      }
      // 仕様: Core 第7.8節、第1.1.10節。単位は元明細。商品マスタから埋めない。
      createdLine.Unit__c = sourceLine.Unit__c;
      refreshLineMergeKey(createdLine);
      // 同一請求内分割: 端数はリセット済み。分割・移動済を立てる
      markLineSplitMoved(createdLine, false);
      newLines.add(createdLine);

      Decimal remain = resolveConservingRemainAmount(
        move,
        input.remainAmount,
        current,
        sourceLine.ProductName__c
      );
      Boolean keepZeroRemain =
        input.splitMode == SPLIT_MODE_UNIT_PRICE ||
        input.splitMode == SPLIT_MODE_QUANTITY;
      if (remain == 0 && !keepZeroRemain) {
        sourceDeletes.add(sourceLine);
      } else {
        sourceLine.Amount__c = remain;
        if (input.remainUnitPrice != null) {
          sourceLine.UnitPrice__c = input.remainUnitPrice;
        }
        if (input.remainQuantity != null) {
          sourceLine.Quantity__c = input.remainQuantity;
        }
        markLineSplitMoved(sourceLine, false);
        if (input.remainSourcePeriodLineIds != null) {
          sourceLine.SourcePeriodLineIds__c = input.remainSourcePeriodLineIds;
        }
        if (input.remainPeriodLabel != null) {
          sourceLine.PeriodLabel__c = input.remainPeriodLabel;
        }
        applyServicePeriodSnapshot(
          sourceLine,
          sourceLine,
          sourceLine.SourcePeriodLineIds__c
        );
        refreshLineMergeKey(sourceLine);
        sourceUpdates.add(sourceLine);
      }
    }

    // Master-Detail: 同一親へ移す側を先に insert し、残す側を update（全額移動のみ delete）
    if (!newLines.isEmpty()) {
      SystemContextAccess.insertRecords(newLines);
    }
    if (!sourceUpdates.isEmpty()) {
      SystemContextAccess.updateRecords(sourceUpdates);
    }
    if (!sourceDeletes.isEmpty()) {
      SystemContextAccess.deleteRecords(sourceDeletes);
    }

    // 因子／月分割: 対象行は分割・移動済。兄弟に端数が残るなら調整前合計を維持。
    // 端数フラグも実ギャップも無いときだけ調整前＝税抜合計に揃える（分割・移動済フラグは残す）。
    // 比率按分でギャップだけ乗った請求はフラグ無しでも調整前を潰さない。
    deriveInvoiceManualFlagsAndRecalc(invoiceId);
    Invoice__c refreshed = [
      SELECT
        Id,
        Amount__c,
        PeriodLineAmountTotal__c,
        IsAmountAdjusted__c,
        IsSplitMoved__c,
        IsManuallyAdjusted__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    Decimal amountTotal = refreshed.Amount__c == null ? 0 : refreshed.Amount__c;
    Decimal periodTotal = refreshed.PeriodLineAmountTotal__c == null
      ? amountTotal
      : refreshed.PeriodLineAmountTotal__c;
    if (amountTotal != periodTotal) {
      // 実ギャップあり: 潰さず、フラグが無ければ立てて表示を整合
      if (refreshed.IsAmountAdjusted__c != true) {
        refreshed.IsAmountAdjusted__c = true;
        syncInvoiceManualUmbrella(refreshed);
        SystemContextAccess.updateRecords(new List<Invoice__c>{ refreshed });
      }
      return;
    }
    if (refreshed.IsAmountAdjusted__c == true) {
      return;
    }
    SystemContextAccess.updateRecords(
      new List<Invoice__c>{
        new Invoice__c(Id = invoiceId, PeriodLineAmountTotal__c = amountTotal)
      }
    );
  }

  /**
   * 同一請求内の月分割 UI 用。継続課金明細で期間月が2つ以上あるとき、
   * 最早月を除くしきい日（期間月 StartDate）候補を返す。
   */
  public static List<SplitThresholdLineOptions> getSplitThresholdDateOptions(
    Id invoiceId
  ) {
    List<SplitThresholdLineOptions> rows = new List<SplitThresholdLineOptions>();
    if (invoiceId == null) {
      return rows;
    }

    Invoice__c invoiceHeader = [
      SELECT Id, PeriodLineAmountTotal__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    List<InvoiceLine__c> lines = [
      SELECT
        Id,
        Amount__c,
        IsAmountAdjusted__c,
        SourcePeriodLineIds__c,
        ContractProduct__r.BillingType__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
    ];
    if (lines.isEmpty()) {
      return rows;
    }

    Set<Id> allPeriodIds = new Set<Id>();
    Map<Id, List<Id>> periodIdsByLineId = new Map<Id, List<Id>>();
    Map<Id, Decimal> lineAmountById = new Map<Id, Decimal>();
    Map<Id, Boolean> lineAmountAdjustedById = new Map<Id, Boolean>();
    for (InvoiceLine__c line : lines) {
      lineAmountById.put(line.Id, line.Amount__c == null ? 0 : line.Amount__c);
      lineAmountAdjustedById.put(line.Id, line.IsAmountAdjusted__c == true);
      if (
        !ContractMetadataService.isRecurringBillingType(
          line.ContractProduct__r == null
            ? null
            : line.ContractProduct__r.BillingType__c
        )
      ) {
        continue;
      }
      List<Id> periodIds = parseIdList(line.SourcePeriodLineIds__c);
      if (periodIds.isEmpty()) {
        continue;
      }
      periodIdsByLineId.put(line.Id, periodIds);
      allPeriodIds.addAll(periodIds);
    }
    if (allPeriodIds.isEmpty()) {
      return rows;
    }

    Map<Id, InvoiceProduct__c> periodById = new Map<Id, InvoiceProduct__c>(
      [
        SELECT Id, Amount__c, StartDate__c, Enddate__c
        FROM InvoiceProduct__c
        WHERE Id IN :allPeriodIds
        WITH SYSTEM_MODE
      ]
    );

    for (Id lineId : periodIdsByLineId.keySet()) {
      List<InvoiceProduct__c> periods = new List<InvoiceProduct__c>();
      Date earliest = null;
      for (Id periodId : periodIdsByLineId.get(lineId)) {
        InvoiceProduct__c period = periodById.get(periodId);
        if (period == null || period.StartDate__c == null) {
          continue;
        }
        periods.add(period);
        if (earliest == null || period.StartDate__c < earliest) {
          earliest = period.StartDate__c;
        }
      }
      if (periods.size() < 2 || earliest == null) {
        continue;
      }
      Map<Date, InvoiceProduct__c> periodByStart = new Map<Date, InvoiceProduct__c>();
      for (InvoiceProduct__c period : periods) {
        if (
          period.StartDate__c == earliest ||
          periodByStart.containsKey(period.StartDate__c)
        ) {
          continue;
        }
        periodByStart.put(period.StartDate__c, period);
      }
      if (periodByStart.isEmpty()) {
        continue;
      }
      // 分割実行時は端数をリセットするため、プレビューも調整前で出す。
      // 金額分割後は SourcePeriodLineIds が共有され満額合算すると水増しになるため、
      // ヘッダ調整前請求額からの明細按分を正とする（resetFactorSplit と同じ）。
      Decimal allPeriodSum = sumPeriodAmounts(periods);
      Decimal lineAmount = lineAmountById.containsKey(lineId)
        ? lineAmountById.get(lineId)
        : 0;
      if (lineAmountAdjustedById.get(lineId) == true) {
        lineAmount = resolveAmountAdjustedResetBaseline(
          lineId,
          invoiceHeader.PeriodLineAmountTotal__c,
          lineAmountById,
          new Set<Id>{ lineId },
          allPeriodSum
        );
      }
      List<Date> starts = new List<Date>(periodByStart.keySet());
      starts.sort();
      List<SplitThresholdDateOption> options = new List<SplitThresholdDateOption>();
      for (Date startDate : starts) {
        List<InvoiceProduct__c> movePeriods = new List<InvoiceProduct__c>();
        for (InvoiceProduct__c period : periods) {
          if (period.StartDate__c >= startDate) {
            movePeriods.add(period);
          }
        }
        Decimal moveAmount = scaleAmountByPeriodShare(
          lineAmount,
          sumPeriodAmounts(movePeriods),
          allPeriodSum
        );
        SplitThresholdDateOption option = new SplitThresholdDateOption();
        option.value = String.valueOf(startDate);
        // UI は期間ではなくしきい日（開始日）を選ぶ
        option.label =
          String.valueOf(startDate.year()) +
          '/' +
          String.valueOf(startDate.month()) +
          '/' +
          String.valueOf(startDate.day());
        option.moveAmount = moveAmount;
        option.remainAmount = lineAmount - moveAmount;
        options.add(option);
      }
      SplitThresholdLineOptions row = new SplitThresholdLineOptions();
      row.invoiceLineId = lineId;
      row.options = options;
      rows.add(row);
    }
    return rows;
  }

  /**
   * 選択明細を既存の未ロック請求へ全額移す（手動マージ相当）。
   * Master-Detail のため付け替え不可 → 行き先へ新規明細を作り、元明細を削除する。
   * 請求日・BA・税率は行き先ヘッダに従う。同一 ContractHistory のみ。Version 跨ぎ不可。
   * 元請求の明細が0件になったら元請求を削除する。
   */
  public static void moveLinesToExistingInvoice(
    Id sourceInvoiceId,
    Id targetInvoiceId,
    List<Id> lineIds
  ) {
    ContractHistoryStatusPathService.beginPathSyncDefer();
    try {
      moveLinesToExistingInvoiceBody(sourceInvoiceId, targetInvoiceId, lineIds);
    } finally {
      ContractHistoryStatusPathService.endPathSyncDefer();
    }
  }

  private static void moveLinesToExistingInvoiceBody(
    Id sourceInvoiceId,
    Id targetInvoiceId,
    List<Id> lineIds
  ) {
    assertCanEditInvoicePreview();
    if (
      sourceInvoiceId == null ||
      targetInvoiceId == null ||
      lineIds == null ||
      lineIds.isEmpty()
    ) {
      throw new InvoiceEditException(
        '移動元請求・移動先請求・明細は必須です。'
      );
    }
    if (sourceInvoiceId == targetInvoiceId) {
      throw new InvoiceEditException('移動元と移動先の請求が同じです。');
    }

    Set<Id> lineIdSet = new Set<Id>();
    for (Id lineId : lineIds) {
      if (lineId != null) {
        lineIdSet.add(lineId);
      }
    }
    if (lineIdSet.isEmpty()) {
      throw new InvoiceEditException('移動する明細を選択してください。');
    }

    Map<Id, Invoice__c> invoicesById = new Map<Id, Invoice__c>(
      [
        SELECT
          Id,
          ContractService__c,
          ContractHistory__c,
          Amount__c,
          PeriodLineAmountTotal__c,
          TaxPercent__c,
          MergeKey__c,
          SystemIntegrationDate__c,
          PaymentClearingCompletedDate__c,
          InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE Id IN :new Set<Id>{ sourceInvoiceId, targetInvoiceId }
        WITH SYSTEM_MODE
      ]
    );
    Invoice__c source = invoicesById.get(sourceInvoiceId);
    Invoice__c target = invoicesById.get(targetInvoiceId);
    if (source == null || target == null) {
      throw new InvoiceEditException(
        '移動元または移動先の請求が見つかりません。'
      );
    }
    InvoiceLockUtil.assertInvoiceEditable(source);
    InvoiceLockUtil.assertInvoiceEditable(target);
    if (
      source.ContractHistory__c == null ||
      source.ContractHistory__c != target.ContractHistory__c
    ) {
      throw new InvoiceEditException(
        '同一 Version（契約履歴）の請求へだけ明細を移せます。'
      );
    }
    if (source.TaxPercent__c != target.TaxPercent__c) {
      throw new InvoiceEditException('税率が違う請求へは移せません。');
    }

    List<InvoiceLine__c> sourceLines = [
      SELECT
        Id,
        Amount__c,
        ProductName__c,
        Product__c,
        Unit__c,
        UnitPrice__c,
        Quantity__c,
        PeriodLabel__c,
        LineMergeKey__c,
        HistoryVersionLabel__c,
        SourcePeriodLineIds__c,
        ServicePeriodStartDate__c,
        ServicePeriodEndDate__c,
        AcceptanceEndDate__c,
        RevenueRecognitionBasis__c,
        ContractProduct__c,
        ContractProduct__r.Product__c,
        ContractProduct__r.Unit__c,
        IsManuallyAdjusted__c,
        IsAmountAdjusted__c,
        IsSplitMoved__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :sourceInvoiceId AND Id IN :lineIdSet
      WITH SYSTEM_MODE
    ];
    if (sourceLines.size() != lineIdSet.size()) {
      throw new InvoiceEditException('移動対象の明細が見つかりません。');
    }

    Decimal sourceAmountBefore = source.Amount__c == null
      ? 0
      : source.Amount__c;
    Decimal sourcePeriodTotal = source.PeriodLineAmountTotal__c == null
      ? sourceAmountBefore
      : source.PeriodLineAmountTotal__c;
    Decimal targetPeriodTotalBefore = target.PeriodLineAmountTotal__c == null
      ? (target.Amount__c == null ? 0 : target.Amount__c)
      : target.PeriodLineAmountTotal__c;

    List<InvoiceLine__c> createdLines = new List<InvoiceLine__c>();
    Decimal movedAmount = 0;
    for (InvoiceLine__c sourceLine : sourceLines) {
      Decimal amount = sourceLine.Amount__c == null ? 0 : sourceLine.Amount__c;
      movedAmount += amount;
      InvoiceLine__c created = new InvoiceLine__c();
      created.Invoice__c = targetInvoiceId;
      created.ProductName__c = sourceLine.ProductName__c;
      created.UnitPrice__c = sourceLine.UnitPrice__c;
      created.Quantity__c = sourceLine.Quantity__c;
      created.Amount__c = amount;
      created.PeriodLabel__c = sourceLine.PeriodLabel__c;
      created.HistoryVersionLabel__c = sourceLine.HistoryVersionLabel__c;
      created.SourcePeriodLineIds__c = sourceLine.SourcePeriodLineIds__c;
      created.ServicePeriodStartDate__c = sourceLine.ServicePeriodStartDate__c;
      created.ServicePeriodEndDate__c = sourceLine.ServicePeriodEndDate__c;
      created.AcceptanceEndDate__c = sourceLine.AcceptanceEndDate__c;
      created.RevenueRecognitionBasis__c = sourceLine.RevenueRecognitionBasis__c;
      created.ContractProduct__c = sourceLine.ContractProduct__c;
      if (sourceLine.ContractProduct__r != null) {
        created.Product__c = sourceLine.ContractProduct__r.Product__c;
      } else {
        created.Product__c = sourceLine.Product__c;
      }
      // 仕様: Core 第7.8節、第1.1.10節。単位は元明細。商品マスタから埋めない。
      created.Unit__c = sourceLine.Unit__c;
      refreshLineMergeKey(created);
      // 明細移動: 端数フラグは引き継ぎ、分割・移動済を立てる
      created.IsAmountAdjusted__c = sourceLine.IsAmountAdjusted__c == true;
      markLineSplitMoved(created, true);
      createdLines.add(created);
    }

    SystemContextAccess.insertRecords(createdLines);
    SystemContextAccess.deleteRecords(sourceLines);

    Decimal movedPeriodTotal;
    Decimal remainPeriodTotal;
    if (sourceAmountBefore == 0) {
      // 税抜合計0は金額比が使えない。明細絶対値の寄与で調整前を按分する
      Decimal movedAbsShare = 0;
      for (InvoiceLine__c sourceLine : sourceLines) {
        Decimal amount = sourceLine.Amount__c == null
          ? 0
          : sourceLine.Amount__c;
        movedAbsShare += amount.abs();
      }
      Decimal remainAbsShare = 0;
      for (InvoiceLine__c other : [
        SELECT Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :sourceInvoiceId AND Id NOT IN :lineIdSet
        WITH SYSTEM_MODE
      ]) {
        Decimal amount = other.Amount__c == null ? 0 : other.Amount__c;
        remainAbsShare += amount.abs();
      }
      movedPeriodTotal = allocatePeriodTotalByAbsShare(
        sourcePeriodTotal,
        movedAbsShare,
        remainAbsShare
      );
      remainPeriodTotal = sourcePeriodTotal - movedPeriodTotal;
    } else {
      movedPeriodTotal = roundInvoiceAmount(
        sourcePeriodTotal * movedAmount / sourceAmountBefore
      );
      remainPeriodTotal = sourcePeriodTotal - movedPeriodTotal;
    }

    markInvoiceSplitMovedAndRecalc(targetInvoiceId);
    Invoice__c targetUpdate = new Invoice__c(
      Id = targetInvoiceId,
      PeriodLineAmountTotal__c = targetPeriodTotalBefore + movedPeriodTotal,
      MergeKey__c = null
    );
    SystemContextAccess.updateRecords(new List<Invoice__c>{ targetUpdate });
    syncAmountAdjustedFlagFromPeriodGap(targetInvoiceId);

    List<InvoiceLine__c> remainLines = [
      SELECT Id
      FROM InvoiceLine__c
      WHERE Invoice__c = :sourceInvoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (remainLines.isEmpty()) {
      SystemContextAccess.deleteRecords(new List<Invoice__c>{ source });
    } else {
      markInvoiceSplitMovedAndRecalc(sourceInvoiceId);
      Invoice__c sourceUpdate = new Invoice__c(
        Id = sourceInvoiceId,
        PeriodLineAmountTotal__c = remainPeriodTotal,
        MergeKey__c = null
      );
      SystemContextAccess.updateRecords(new List<Invoice__c>{ sourceUpdate });
      syncAmountAdjustedFlagFromPeriodGap(sourceInvoiceId);
    }
  }

  /**
   * 請求日分割: 指定明細金額を新請求へ移す（Master-Detail のため付け替えではなく新規作成）。
   * 入金予定日は必須（人が渡した値のみ使用。自動再計算・元請求コピーなし）。
   * DML 対象は Invoice__c / InvoiceLine__c のみ。上流マスタは更新しない。
   */
  public static Id splitInvoiceByDate(
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<SplitLineInput> splitLines
  ) {
    return splitInvoice(
      sourceInvoiceId,
      newInvoiceDate,
      newPaymentScheduledDate,
      null,
      splitLines,
      true,
      false
    );
  }

  /**
   * 請求アカウント分割: 明細金額を別 BA の新請求へ移す。
   * 請求日・入金予定日・請求アカウントは必須。元請求日のコピーはしない。
   * 指定 BA は SnapShot コピー元として参照するだけで、BA マスタ自体は更新しない。
   */
  /** 仕様: Core 第7.8節 */
  public static Id splitInvoiceByBillingAccount(
    Id sourceInvoiceId,
    Id newBillingAccountId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<SplitLineInput> splitLines
  ) {
    if (newBillingAccountId == null) {
      throw new InvoiceEditException('分割先の請求アカウントは必須です。');
    }
    if (newInvoiceDate == null) {
      throw new InvoiceEditException('分割先の請求日は必須です。');
    }
    return splitInvoice(
      sourceInvoiceId,
      newInvoiceDate,
      newPaymentScheduledDate,
      newBillingAccountId,
      splitLines,
      true,
      false
    );
  }

  private static Id splitInvoice(
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    Id newBillingAccountId,
    List<SplitLineInput> splitLines,
    Boolean requireNewInvoiceDate,
    Boolean clearManualAdjustment
  ) {
    ContractHistoryStatusPathService.beginPathSyncDefer();
    try {
      return splitInvoiceBody(
        sourceInvoiceId,
        newInvoiceDate,
        newPaymentScheduledDate,
        newBillingAccountId,
        splitLines,
        requireNewInvoiceDate,
        clearManualAdjustment
      );
    } finally {
      ContractHistoryStatusPathService.endPathSyncDefer();
    }
  }

  private static Id splitInvoiceBody(
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    Id newBillingAccountId,
    List<SplitLineInput> splitLines,
    Boolean requireNewInvoiceDate,
    Boolean clearManualAdjustment
  ) {
    assertCanEditInvoicePreview();
    // 仕様: Core 第11.4.2節
    FieldCopyDefinitionService.validateAllDefinitions();
    if (
      sourceInvoiceId == null ||
      splitLines == null ||
      splitLines.isEmpty() ||
      (requireNewInvoiceDate && newInvoiceDate == null)
    ) {
      throw new InvoiceEditException('分割元請求・分割内容は必須です。');
    }
    if (newPaymentScheduledDate == null) {
      throw new InvoiceEditException('分割先の入金予定日は必須です。');
    }

    Invoice__c source = [
      SELECT
        Id,
        ContractService__c,
        ContractHistory__c,
        BillingAccountSnapShot__c,
        InvoiceDate__c,
        PaymentScheduledDate__c,
        TaxPercent__c,
        Amount__c,
        PeriodLineAmountTotal__c,
        SystemIntegrationDate__c,
        PaymentClearingCompletedDate__c,
        InvoiceTransactionStatus__c
      FROM Invoice__c
      WHERE Id = :sourceInvoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    InvoiceLockUtil.assertInvoiceEditable(source);
    Decimal sourceAmountBefore = source.Amount__c == null
      ? 0
      : source.Amount__c;
    Decimal sourcePeriodTotal = source.PeriodLineAmountTotal__c == null
      ? sourceAmountBefore
      : source.PeriodLineAmountTotal__c;

    Map<Id, SplitLineInput> inputByLineId = new Map<Id, SplitLineInput>();
    for (SplitLineInput input : splitLines) {
      if (input == null || input.lineId == null || input.moveAmount == null) {
        continue;
      }
      Decimal move = roundInvoiceAmount(input.moveAmount);
      if (move == 0) {
        continue;
      }
      input.moveAmount = move;
      if (input.remainAmount != null) {
        input.remainAmount = roundInvoiceAmount(input.remainAmount);
      }
      inputByLineId.put(input.lineId, input);
    }
    if (inputByLineId.isEmpty()) {
      throw new InvoiceEditException('移動する金額がありません。');
    }

    List<InvoiceLine__c> sourceLines = [
      SELECT
        Id,
        Amount__c,
        ProductName__c,
        Product__c,
        Unit__c,
        UnitPrice__c,
        Quantity__c,
        PeriodLabel__c,
        LineMergeKey__c,
        HistoryVersionLabel__c,
        SourcePeriodLineIds__c,
        ServicePeriodStartDate__c,
        ServicePeriodEndDate__c,
        RevenueRecognitionBasis__c,
        ContractProduct__c,
        ContractProduct__r.Product__c,
        ContractProduct__r.Unit__c,
        IsAmountAdjusted__c,
        IsSplitMoved__c,
        IsManuallyAdjusted__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :sourceInvoiceId AND Id IN :inputByLineId.keySet()
      WITH SYSTEM_MODE
    ];
    if (sourceLines.size() != inputByLineId.size()) {
      throw new InvoiceEditException('分割対象の明細が見つかりません。');
    }

    Invoice__c created = new Invoice__c();
    created.ContractService__c = source.ContractService__c;
    created.ContractHistory__c = source.ContractHistory__c;
    created.InvoiceDate__c = newInvoiceDate == null
      ? source.InvoiceDate__c
      : newInvoiceDate;
    created.PaymentScheduledDate__c = newPaymentScheduledDate;
    created.TaxPercent__c = source.TaxPercent__c;
    // 調整前請求額は分割後に移す／残すへ再配分する（丸コピーすると偽の端数ギャップになる）
    created.PeriodLineAmountTotal__c = 0;
    created.IsAmountAdjusted__c = false;
    created.IsSplitMoved__c = true;
    syncInvoiceManualUmbrella(created);
    created.Amount__c = 0;
    created.TaxAmount__c = 0;
    // 分割で生まれる新請求は集約キーを付けない（手動調整後と同様。突合は Id ベース）
    created.MergeKey__c = null;
    // BA SnapShot（必須）は作成時マスタをハードコードでスタンプ。
    // 当請求への手修正 SnapShot は引き継がない。CMDT は顧客／サンプル拡張のみ。
    Id billingAccountId = newBillingAccountId != null
      ? newBillingAccountId
      : source.BillingAccountSnapShot__c;
    prepareBillingAccountSnapshotReference(created, billingAccountId);
    applyHardcodedBillingAccountSnapshot(
      created,
      loadBillingAccountForSnapshot(billingAccountId)
    );
    SystemContextAccess.insertRecords(new List<Invoice__c>{ created });

    List<InvoiceLine__c> newLines = new List<InvoiceLine__c>();
    List<InvoiceLine__c> sourceUpdates = new List<InvoiceLine__c>();
    List<InvoiceLine__c> sourceDeletes = new List<InvoiceLine__c>();
    Decimal newInvoiceAmount = 0;
    Decimal movedAbsShare = 0;
    Decimal remainAbsShare = 0;
    Boolean trackAbsShare =
      sourceAmountBefore == 0 &&
      clearManualAdjustment != true;

    for (InvoiceLine__c sourceLine : sourceLines) {
      SplitLineInput input = inputByLineId.get(sourceLine.Id);
      Decimal move = input.moveAmount;
      Decimal current = sourceLine.Amount__c == null ? 0 : sourceLine.Amount__c;
      // 利用期間分割も按分後は明細金額以内。正負どちらも同符号かつ |move| <= |current|
      if (isMoveAmountOutOfRange(move, current)) {
        throw new InvoiceEditException(
          '移動金額が明細金額を超えています: ' + sourceLine.ProductName__c
        );
      }
      InvoiceLine__c createdLine = new InvoiceLine__c();
      createdLine.Invoice__c = created.Id;
      // 表示名・金額は分割入力。単価・数量は因子分割時のみ上書き、それ以外は分割元をコピー。
      // 仕様: Core 第7.8節、第1.1.10節。単位は元明細。商品マスタから埋めない。
      createdLine.ProductName__c = sourceLine.ProductName__c;
      createdLine.UnitPrice__c = input.moveUnitPrice != null
        ? input.moveUnitPrice
        : sourceLine.UnitPrice__c;
      createdLine.Quantity__c = input.moveQuantity != null
        ? input.moveQuantity
        : sourceLine.Quantity__c;
      createdLine.Amount__c = move;
      createdLine.PeriodLabel__c = String.isNotBlank(input.movePeriodLabel)
        ? input.movePeriodLabel
        : sourceLine.PeriodLabel__c;
      createdLine.HistoryVersionLabel__c = sourceLine.HistoryVersionLabel__c;
      createdLine.SourcePeriodLineIds__c = input.moveSourcePeriodLineIds != null
        ? input.moveSourcePeriodLineIds
        : sourceLine.SourcePeriodLineIds__c;
      createdLine.RevenueRecognitionBasis__c = sourceLine.RevenueRecognitionBasis__c;
      applyServicePeriodSnapshot(
        createdLine,
        sourceLine,
        createdLine.SourcePeriodLineIds__c
      );
      createdLine.ContractProduct__c = sourceLine.ContractProduct__c;
      if (sourceLine.ContractProduct__r != null) {
        createdLine.Product__c = sourceLine.ContractProduct__r.Product__c;
      } else {
        createdLine.Product__c = sourceLine.Product__c;
      }
      // 仕様: Core 第7.8節、第1.1.10節。単位は元明細。商品マスタから埋めない。
      createdLine.Unit__c = sourceLine.Unit__c;
      refreshLineMergeKey(createdLine);
      if (clearManualAdjustment == true) {
        markLineSplitMoved(createdLine, false);
      } else {
        createdLine.IsAmountAdjusted__c =
          sourceLine.IsAmountAdjusted__c == true;
        markLineSplitMoved(createdLine, true);
      }
      newLines.add(createdLine);
      newInvoiceAmount += move;

      Decimal remain = resolveConservingRemainAmount(
        move,
        input.remainAmount,
        current,
        sourceLine.ProductName__c
      );
      if (trackAbsShare) {
        movedAbsShare += move.abs();
        remainAbsShare += remain.abs();
      }
      // 全額移動（残 0）のみ削除。マイナス残は打消し明細として残す
      if (remain == 0) {
        sourceDeletes.add(sourceLine);
      } else {
        sourceLine.Amount__c = remain;
        if (input.remainUnitPrice != null) {
          sourceLine.UnitPrice__c = input.remainUnitPrice;
        }
        if (input.remainQuantity != null) {
          sourceLine.Quantity__c = input.remainQuantity;
        }
        if (clearManualAdjustment == true) {
          markLineSplitMoved(sourceLine, false);
        } else {
          markLineSplitMoved(sourceLine, true);
        }
        if (input.remainSourcePeriodLineIds != null) {
          sourceLine.SourcePeriodLineIds__c = input.remainSourcePeriodLineIds;
        }
        if (input.remainPeriodLabel != null) {
          sourceLine.PeriodLabel__c = input.remainPeriodLabel;
        }
        applyServicePeriodSnapshot(
          sourceLine,
          sourceLine,
          sourceLine.SourcePeriodLineIds__c
        );
        refreshLineMergeKey(sourceLine);
        sourceUpdates.add(sourceLine);
      }
    }

    if (trackAbsShare) {
      for (InvoiceLine__c other : [
        SELECT Amount__c
        FROM InvoiceLine__c
        WHERE
          Invoice__c = :sourceInvoiceId
          AND Id NOT IN :inputByLineId.keySet()
        WITH SYSTEM_MODE
      ]) {
        Decimal amount = other.Amount__c == null ? 0 : other.Amount__c;
        remainAbsShare += amount.abs();
      }
    }

    if (!newLines.isEmpty()) {
      SystemContextAccess.insertRecords(newLines);
    }
    if (!sourceUpdates.isEmpty()) {
      SystemContextAccess.updateRecords(sourceUpdates);
    }
    if (!sourceDeletes.isEmpty()) {
      SystemContextAccess.deleteRecords(sourceDeletes);
    }

    Decimal remainAmount = sourceAmountBefore - newInvoiceAmount;
    Decimal createdPeriodTotal;
    Decimal remainPeriodTotal;
    if (clearManualAdjustment == true) {
      // 利用期間分割: 期間明細ベースへ戻すので調整前＝金額
      createdPeriodTotal = newInvoiceAmount;
      remainPeriodTotal = remainAmount;
    } else if (sourceAmountBefore == 0) {
      // 税抜合計0は金額比が使えない。明細絶対値の寄与で調整前を按分する
      createdPeriodTotal = allocatePeriodTotalByAbsShare(
        sourcePeriodTotal,
        movedAbsShare,
        remainAbsShare
      );
      remainPeriodTotal = sourcePeriodTotal - createdPeriodTotal;
    } else {
      // 請求日／BA 分割: 調整前を金額比で按分（端数調整のギャップを比率で引き継ぐ）
      createdPeriodTotal = roundInvoiceAmount(
        sourcePeriodTotal * newInvoiceAmount / sourceAmountBefore
      );
      remainPeriodTotal = sourcePeriodTotal - createdPeriodTotal;
    }

    created.Amount__c = newInvoiceAmount;
    created.PeriodLineAmountTotal__c = createdPeriodTotal;
    created.TaxAmount__c = TaxCalculationUtil.calculateTaxAmount(
      newInvoiceAmount,
      TaxCalculationUtil.fromPercentFieldStorage(created.TaxPercent__c)
    );
    Boolean createdHasAmountAdjusted = false;
    if (clearManualAdjustment != true) {
      for (InvoiceLine__c newLine : newLines) {
        if (newLine.IsAmountAdjusted__c == true) {
          createdHasAmountAdjusted = true;
          break;
        }
      }
    }
    // 金額比按分でギャップが乗った請求は、明細に端数フラグが無くても端数扱い
    created.IsAmountAdjusted__c =
      createdHasAmountAdjusted ||
      (clearManualAdjustment != true &&
      newInvoiceAmount != createdPeriodTotal);
    created.IsSplitMoved__c = true;
    syncInvoiceManualUmbrella(created);
    SystemContextAccess.updateRecords(new List<Invoice__c>{ created });
    // 元請求が残る場合は常に分割・移動済（clearManual でも derive だけに落とさない）
    List<InvoiceLine__c> remainLines = [
      SELECT Id
      FROM InvoiceLine__c
      WHERE Invoice__c = :sourceInvoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (remainLines.isEmpty()) {
      SystemContextAccess.deleteRecords(new List<Invoice__c>{ source });
    } else {
      markInvoiceSplitMovedAndRecalc(sourceInvoiceId);
      // 仕様: 請求を分ける後は元・先とも MergeKey を破棄（突合の正は Id）
      Invoice__c remainInvoice = new Invoice__c(
        Id = sourceInvoiceId,
        PeriodLineAmountTotal__c = remainPeriodTotal,
        MergeKey__c = null
      );
      SystemContextAccess.updateRecords(new List<Invoice__c>{ remainInvoice });
      syncAmountAdjustedFlagFromPeriodGap(sourceInvoiceId);
    }
    return created.Id;
  }

  /**
   * Amount ≠ PeriodLineAmountTotal のときヘッダ端数フラグを立てる。
   * 比率按分でギャップだけ引き継いだ請求の「端数なし顔」を防ぐ。
   * ギャップが無いときは既存フラグを落とさない（明細由来の端数を維持）。
   */
  private static void syncAmountAdjustedFlagFromPeriodGap(Id invoiceId) {
    if (invoiceId == null) {
      return;
    }
    Invoice__c invoice = [
      SELECT
        Id,
        Amount__c,
        PeriodLineAmountTotal__c,
        IsAmountAdjusted__c,
        IsSplitMoved__c,
        IsManuallyAdjusted__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    Decimal amount = invoice.Amount__c == null ? 0 : invoice.Amount__c;
    Decimal periodTotal = invoice.PeriodLineAmountTotal__c == null
      ? amount
      : invoice.PeriodLineAmountTotal__c;
    if (amount == periodTotal || invoice.IsAmountAdjusted__c == true) {
      return;
    }
    invoice.IsAmountAdjusted__c = true;
    syncInvoiceManualUmbrella(invoice);
    SystemContextAccess.updateRecords(new List<Invoice__c>{ invoice });
  }

  private static void markInvoiceAmountAdjustedAndRecalc(Id invoiceId) {
    recalcInvoiceTotals(invoiceId, true, null);
  }

  private static void markInvoiceSplitMovedAndRecalc(Id invoiceId) {
    recalcInvoiceTotals(invoiceId, null, true);
  }

  private static void deriveInvoiceManualFlagsAndRecalc(Id invoiceId) {
    recalcInvoiceTotals(invoiceId, null, null);
  }

  private static void clearInvoiceManualFlags(Invoice__c invoice) {
    if (invoice == null) {
      return;
    }
    invoice.IsAmountAdjusted__c = false;
    invoice.IsSplitMoved__c = false;
    invoice.IsManuallyAdjusted__c = false;
  }

  private static void clearLineManualFlags(InvoiceLine__c line) {
    if (line == null) {
      return;
    }
    line.IsAmountAdjusted__c = false;
    line.IsSplitMoved__c = false;
    line.IsManuallyAdjusted__c = false;
  }

  private static void markLineAmountAdjusted(InvoiceLine__c line) {
    if (line == null) {
      return;
    }
    line.IsAmountAdjusted__c = true;
    syncLineManualUmbrella(line);
  }

  /**
   * 分割・移動済を立てる。keepAmountAdjusted=false のとき端数フラグも落とす。
   */
  private static void markLineSplitMoved(
    InvoiceLine__c line,
    Boolean keepAmountAdjusted
  ) {
    if (line == null) {
      return;
    }
    if (keepAmountAdjusted != true) {
      line.IsAmountAdjusted__c = false;
    }
    line.IsSplitMoved__c = true;
    syncLineManualUmbrella(line);
  }

  private static void markInvoiceSplitMoved(Invoice__c invoice) {
    if (invoice == null) {
      return;
    }
    invoice.IsSplitMoved__c = true;
    // ヘッダ編集パスでは IsAmountAdjusted を SOQL していないことがあるため触らない
    invoice.IsManuallyAdjusted__c = true;
  }

  /** 請求情報編集（日付・宛名等）。分割していないので IsSplitMoved は立てない。 */
  private static void markInvoiceHeaderTouched(Invoice__c invoice) {
    if (invoice == null) {
      return;
    }
    invoice.IsManuallyAdjusted__c = true;
  }

  private static void syncLineManualUmbrella(InvoiceLine__c line) {
    if (line == null) {
      return;
    }
    line.IsManuallyAdjusted__c =
      line.IsAmountAdjusted__c == true ||
      line.IsSplitMoved__c == true;
  }

  private static void syncInvoiceManualUmbrella(Invoice__c invoice) {
    if (invoice == null) {
      return;
    }
    // ヘッダ手直し（詳細フラグなし）の傘は維持。再生成の clear で消える。
    invoice.IsManuallyAdjusted__c =
      invoice.IsAmountAdjusted__c == true ||
      invoice.IsSplitMoved__c == true ||
      invoice.IsManuallyAdjusted__c == true;
  }

  /**
   * 請求合計を明細から再計算し、手動調整フラグを同期する。
   * forceAmount / forceSplit: true=強制オン、null=明細から導出。
   */
  private static void recalcInvoiceTotals(
    Id invoiceId,
    Boolean forceAmountAdjusted,
    Boolean forceSplitMoved
  ) {
    if (invoiceId == null) {
      return;
    }
    Decimal amountTotal = 0;
    Integer amountAdjustedCount = 0;
    Integer splitMovedCount = 0;
    for (InvoiceLine__c line : [
      SELECT Amount__c, IsAmountAdjusted__c, IsSplitMoved__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
    ]) {
      amountTotal += line.Amount__c == null ? 0 : line.Amount__c;
      if (line.IsAmountAdjusted__c == true) {
        amountAdjustedCount++;
      }
      if (line.IsSplitMoved__c == true) {
        splitMovedCount++;
      }
    }
    Invoice__c invoice = [
      SELECT
        Id,
        TaxPercent__c,
        IsAmountAdjusted__c,
        IsSplitMoved__c,
        IsManuallyAdjusted__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    invoice.Amount__c = amountTotal;
    invoice.TaxAmount__c = TaxCalculationUtil.calculateTaxAmount(
      amountTotal,
      TaxCalculationUtil.fromPercentFieldStorage(invoice.TaxPercent__c)
    );
    // 端数: 強制オン、または明細に残存
    Boolean amountFlag = forceAmountAdjusted == true || amountAdjustedCount > 0;
    // 分割・移動: 強制オン、または明細に残存（請求情報編集では立てない）
    Boolean splitFlag = forceSplitMoved == true || splitMovedCount > 0;

    invoice.IsAmountAdjusted__c = amountFlag;
    invoice.IsSplitMoved__c = splitFlag;
    // ヘッダ手直しの傘を消さない（再生成 clear まで）
    Boolean keepHeaderTouch = invoice.IsManuallyAdjusted__c == true;
    invoice.IsManuallyAdjusted__c = amountFlag || splitFlag || keepHeaderTouch;
    SystemContextAccess.updateRecords(new List<Invoice__c>{ invoice });
  }

  /** 仕様: Core 第7.8.4節、第1.1.4節 */
  private static SplitLineInput normalizeFactorSplitInput(
    SplitLineInput raw,
    InvoiceLine__c sourceLine,
    String mode
  ) {
    Decimal lineAmount = sourceLine.Amount__c == null
      ? 0
      : sourceLine.Amount__c;
    SplitLineInput input = new SplitLineInput();
    input.lineId = sourceLine.Id;
    input.splitMode = mode;

    if (mode == SPLIT_MODE_WHOLE) {
      if (lineAmount == 0) {
        throw new InvoiceEditException(
          '0円明細は分割できません: ' + sourceLine.ProductName__c
        );
      }
      input.moveAmount = lineAmount;
      input.remainAmount = 0;
      return input;
    }

    if (mode == SPLIT_MODE_UNIT_PRICE) {
      Decimal original = sourceLine.UnitPrice__c == null
        ? 0
        : roundInvoiceQuantityUnitPrice(sourceLine.UnitPrice__c);
      Decimal movePrice = raw.moveUnitPrice == null
        ? null
        : roundInvoiceQuantityUnitPrice(raw.moveUnitPrice);
      Decimal remainPrice = raw.remainUnitPrice == null
        ? null
        : roundInvoiceQuantityUnitPrice(raw.remainUnitPrice);
      if (movePrice == null || remainPrice == null) {
        throw new InvoiceEditException(
          '残す単価と移す単価を入力してください: ' + sourceLine.ProductName__c
        );
      }
      if (movePrice == 0) {
        throw new InvoiceEditException(
          '移す単価は0以外にしてください: ' + sourceLine.ProductName__c
        );
      }
      if (remainPrice + movePrice != original) {
        throw new InvoiceEditException(
          '残す単価と移す単価の合計が元の単価と一致しません: ' +
          sourceLine.ProductName__c
        );
      }
      if (original == 0) {
        throw new InvoiceEditException(
          '単価0の明細は単価分割できません: ' + sourceLine.ProductName__c
        );
      }
      Decimal moveAmount = scaleAmountByPeriodShare(
        lineAmount,
        movePrice,
        original
      );
      input.moveUnitPrice = movePrice;
      input.remainUnitPrice = remainPrice;
      input.moveAmount = moveAmount;
      input.remainAmount = lineAmount - moveAmount;
      return input;
    }

    if (mode == SPLIT_MODE_QUANTITY) {
      Decimal original = sourceLine.Quantity__c == null
        ? 0
        : roundInvoiceQuantityUnitPrice(sourceLine.Quantity__c);
      Decimal moveQty = raw.moveQuantity == null
        ? null
        : roundInvoiceQuantityUnitPrice(raw.moveQuantity);
      Decimal remainQty = raw.remainQuantity == null
        ? null
        : roundInvoiceQuantityUnitPrice(raw.remainQuantity);
      if (moveQty == null || remainQty == null) {
        throw new InvoiceEditException(
          '残す数量と移す数量を入力してください: ' + sourceLine.ProductName__c
        );
      }
      if (moveQty == 0) {
        throw new InvoiceEditException(
          '移す数量は0以外にしてください: ' + sourceLine.ProductName__c
        );
      }
      if (remainQty + moveQty != original) {
        throw new InvoiceEditException(
          '残す数量と移す数量の合計が元の数量と一致しません: ' +
          sourceLine.ProductName__c
        );
      }
      if (original == 0) {
        throw new InvoiceEditException(
          '数量0の明細は個数分割できません: ' + sourceLine.ProductName__c
        );
      }
      Decimal moveAmount = scaleAmountByPeriodShare(
        lineAmount,
        moveQty,
        original
      );
      input.moveQuantity = moveQty;
      input.remainQuantity = remainQty;
      input.moveAmount = moveAmount;
      input.remainAmount = lineAmount - moveAmount;
      return input;
    }

    // 従来: moveAmount 直接指定
    if (raw.moveAmount == null || raw.moveAmount == 0) {
      throw new InvoiceEditException(
        '移動金額を指定してください: ' + sourceLine.ProductName__c
      );
    }
    input.moveAmount = raw.moveAmount;
    input.remainAmount = raw.remainAmount;
    input.moveSourcePeriodLineIds = raw.moveSourcePeriodLineIds;
    input.remainSourcePeriodLineIds = raw.remainSourcePeriodLineIds;
    input.movePeriodLabel = raw.movePeriodLabel;
    input.remainPeriodLabel = raw.remainPeriodLabel;
    input.moveUnitPrice = raw.moveUnitPrice;
    input.remainUnitPrice = raw.remainUnitPrice;
    input.moveQuantity = raw.moveQuantity;
    input.remainQuantity = raw.remainQuantity;
    return input;
  }

  /**
   * 同一請求内の単価／数量／期間分割の直前に、対象明細の端数調整を調整前金額へ戻す。
   * 調整前の正はヘッダ PeriodLineAmountTotal からの明細按分（兄弟の現状 Amount を控除）。
   * 由来期間合計はヒントに留め、金額分割後の共有 SourcePeriodLineIds 満額合算での水増しを防ぐ。
   * sourceLineById はメモリ上も更新する（このあとの按分がリセット後金額を使うため）。
   */
  private static void resetFactorSplitLineAmountsToSource(
    Id invoiceId,
    Set<Id> lineIds,
    Map<Id, InvoiceLine__c> sourceLineById
  ) {
    if (
      invoiceId == null ||
      lineIds == null ||
      lineIds.isEmpty() ||
      sourceLineById == null ||
      sourceLineById.isEmpty()
    ) {
      return;
    }

    Set<Id> resetLineIds = new Set<Id>();
    for (Id lineId : lineIds) {
      InvoiceLine__c line = sourceLineById.get(lineId);
      if (line != null && line.IsAmountAdjusted__c == true) {
        resetLineIds.add(lineId);
      }
    }
    if (resetLineIds.isEmpty()) {
      return;
    }

    Invoice__c invoiceHeader = [
      SELECT Id, PeriodLineAmountTotal__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    Map<Id, Decimal> amountByLineId = new Map<Id, Decimal>();
    for (InvoiceLine__c sibling : [
      SELECT Id, Amount__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
    ]) {
      amountByLineId.put(
        sibling.Id,
        sibling.Amount__c == null ? 0 : sibling.Amount__c
      );
    }
    // 分割対象のメモリ上金額を優先（呼び出し直前の値）
    for (Id lineId : sourceLineById.keySet()) {
      InvoiceLine__c mem = sourceLineById.get(lineId);
      if (mem != null) {
        amountByLineId.put(lineId, mem.Amount__c == null ? 0 : mem.Amount__c);
      }
    }

    Set<Id> allPeriodIds = new Set<Id>();
    for (Id lineId : resetLineIds) {
      InvoiceLine__c line = sourceLineById.get(lineId);
      if (line != null) {
        allPeriodIds.addAll(parseIdList(line.SourcePeriodLineIds__c));
      }
    }
    Map<Id, InvoiceProduct__c> periodById = allPeriodIds.isEmpty()
      ? new Map<Id, InvoiceProduct__c>()
      : new Map<Id, InvoiceProduct__c>(
          [
            SELECT Id, Amount__c
            FROM InvoiceProduct__c
            WHERE Id IN :allPeriodIds
            WITH SYSTEM_MODE
          ]
        );

    Map<Id, Decimal> baselineByLineId = new Map<Id, Decimal>();
    for (Id lineId : resetLineIds) {
      InvoiceLine__c line = sourceLineById.get(lineId);
      if (line == null) {
        continue;
      }
      List<InvoiceProduct__c> periods = new List<InvoiceProduct__c>();
      for (Id periodId : parseIdList(line.SourcePeriodLineIds__c)) {
        InvoiceProduct__c period = periodById.get(periodId);
        if (period != null) {
          periods.add(period);
        }
      }
      baselineByLineId.put(
        lineId,
        resolveAmountAdjustedResetBaseline(
          lineId,
          invoiceHeader.PeriodLineAmountTotal__c,
          amountByLineId,
          resetLineIds,
          sumPeriodAmounts(periods)
        )
      );
    }

    List<InvoiceLine__c> toUpdate = new List<InvoiceLine__c>();
    for (Id lineId : baselineByLineId.keySet()) {
      InvoiceLine__c line = sourceLineById.get(lineId);
      if (line == null) {
        continue;
      }
      line.Amount__c = baselineByLineId.get(lineId);
      line.IsAmountAdjusted__c = false;
      syncLineManualUmbrella(line);
      toUpdate.add(line);
    }
    if (toUpdate.isEmpty()) {
      return;
    }
    SystemContextAccess.updateRecords(toUpdate);
    deriveInvoiceManualFlagsAndRecalc(invoiceId);
  }

  /**
   * 端数リセット時の明細調整前金額。
   * ヘッダ調整前 − リセット対象外明細の Amount。複数明細を同時リセットするときは
   * 残プールを現状 Amount 比で配分（単一明細なら厳密に調整前シェア）。
   * periodSumHint は由来期間合計。ヘッダ調整前が無くヒントだけ使えるときのフォールバック。
   */
  private static Decimal resolveAmountAdjustedResetBaseline(
    Id lineId,
    Decimal invoicePeriodTotal,
    Map<Id, Decimal> amountByLineId,
    Set<Id> resetLineIds,
    Decimal periodSumHint
  ) {
    if (lineId == null || amountByLineId == null || amountByLineId.isEmpty()) {
      return periodSumHint == null ? 0 : periodSumHint;
    }
    Decimal siblingSum = 0;
    Decimal resetAmountSum = 0;
    Integer resetCount = 0;
    for (Id otherId : amountByLineId.keySet()) {
      Decimal amt = amountByLineId.get(otherId);
      if (amt == null) {
        amt = 0;
      }
      if (resetLineIds != null && resetLineIds.contains(otherId)) {
        resetAmountSum += amt;
        resetCount++;
      } else {
        siblingSum += amt;
      }
    }
    Decimal currentAmount = amountByLineId.containsKey(lineId)
      ? amountByLineId.get(lineId)
      : 0;
    if (currentAmount == null) {
      currentAmount = 0;
    }

    if (invoicePeriodTotal != null) {
      Decimal pool = invoicePeriodTotal - siblingSum;
      if (resetCount <= 1) {
        return pool;
      }
      if (resetAmountSum == 0) {
        // 同符号で割れないときは均等
        return roundInvoiceAmount(pool / resetCount);
      }
      return roundInvoiceAmount(pool * currentAmount / resetAmountSum);
    }
    return periodSumHint == null ? currentAmount : periodSumHint;
  }

  /**
   * 利用期間ID集合から、明細ごとの SplitLineInput を組み立てる。
   * restrictLineIds 指定時はその明細だけ（統一分割の②-3）。null なら請求内の該当明細すべて。
   */
  private static List<SplitLineInput> buildPeriodSplitInputs(
    Id sourceInvoiceId,
    Set<Id> movePeriodIdSet,
    Set<Id> restrictLineIds
  ) {
    List<SplitLineInput> splitLines = new List<SplitLineInput>();
    if (
      sourceInvoiceId == null ||
      movePeriodIdSet == null ||
      movePeriodIdSet.isEmpty()
    ) {
      return splitLines;
    }

    List<InvoiceLine__c> sourceLines = [
      SELECT
        Id,
        Amount__c,
        ProductName__c,
        SourcePeriodLineIds__c,
        ContractProduct__r.BillingType__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :sourceInvoiceId
      WITH SYSTEM_MODE
    ];
    if (sourceLines.isEmpty()) {
      throw new InvoiceEditException('分割対象の明細が見つかりません。');
    }

    Map<Id, Id> invoiceLineByPeriodId = new Map<Id, Id>();
    Map<Id, String> billingTypeByLineId = new Map<Id, String>();
    Set<Id> allPeriodIds = new Set<Id>();
    for (InvoiceLine__c line : sourceLines) {
      if (restrictLineIds != null && !restrictLineIds.contains(line.Id)) {
        continue;
      }
      String billingType = line.ContractProduct__r == null
        ? null
        : line.ContractProduct__r.BillingType__c;
      billingTypeByLineId.put(line.Id, billingType);
      for (Id periodId : parseIdList(line.SourcePeriodLineIds__c)) {
        allPeriodIds.add(periodId);
        invoiceLineByPeriodId.put(periodId, line.Id);
      }
    }

    for (Id moveId : movePeriodIdSet) {
      if (!invoiceLineByPeriodId.containsKey(moveId)) {
        throw new InvoiceEditException(
          '選択した利用期間がこの請求書の対象明細に含まれていません。'
        );
      }
      if (
        restrictLineIds != null &&
        !restrictLineIds.contains(invoiceLineByPeriodId.get(moveId))
      ) {
        throw new InvoiceEditException(
          '選択した利用期間が対象明細に含まれていません。'
        );
      }
    }

    Map<Id, InvoiceProduct__c> periodById = new Map<Id, InvoiceProduct__c>();
    if (!allPeriodIds.isEmpty()) {
      for (InvoiceProduct__c periodLine : [
        SELECT Id, Amount__c, StartDate__c, Enddate__c
        FROM InvoiceProduct__c
        WHERE Id IN :allPeriodIds
        WITH SYSTEM_MODE
      ]) {
        periodById.put(periodLine.Id, periodLine);
      }
    }

    Map<Id, List<InvoiceProduct__c>> movePeriodsByLine = new Map<Id, List<InvoiceProduct__c>>();
    Map<Id, List<InvoiceProduct__c>> keepPeriodsByLine = new Map<Id, List<InvoiceProduct__c>>();
    Map<Id, Decimal> lineAmountById = new Map<Id, Decimal>();
    for (InvoiceLine__c line : sourceLines) {
      if (restrictLineIds != null && !restrictLineIds.contains(line.Id)) {
        continue;
      }
      lineAmountById.put(line.Id, line.Amount__c == null ? 0 : line.Amount__c);
      List<InvoiceProduct__c> movePeriods = new List<InvoiceProduct__c>();
      List<InvoiceProduct__c> keepPeriods = new List<InvoiceProduct__c>();
      for (Id periodId : parseIdList(line.SourcePeriodLineIds__c)) {
        InvoiceProduct__c periodLine = periodById.get(periodId);
        if (periodLine == null) {
          continue;
        }
        if (movePeriodIdSet.contains(periodId)) {
          movePeriods.add(periodLine);
        } else {
          keepPeriods.add(periodLine);
        }
      }
      if (!movePeriods.isEmpty()) {
        movePeriodsByLine.put(line.Id, movePeriods);
        keepPeriodsByLine.put(line.Id, keepPeriods);
      }
    }
    if (movePeriodsByLine.isEmpty()) {
      throw new InvoiceEditException('移す利用期間を選択してください。');
    }

    for (Id lineId : movePeriodsByLine.keySet()) {
      List<InvoiceProduct__c> movePeriods = movePeriodsByLine.get(lineId);
      List<InvoiceProduct__c> keepPeriods = keepPeriodsByLine.get(lineId);
      Boolean mergeContinuous = ContractMetadataService.isRecurringBillingType(
        billingTypeByLineId.get(lineId)
      );
      Decimal movePeriodSum = sumPeriodAmounts(movePeriods);
      Decimal keepPeriodSum = sumPeriodAmounts(keepPeriods);
      Decimal allPeriodSum = movePeriodSum + keepPeriodSum;
      Decimal lineAmount = lineAmountById.containsKey(lineId)
        ? lineAmountById.get(lineId)
        : 0;
      Decimal moveAmount = scaleAmountByPeriodShare(
        lineAmount,
        movePeriodSum,
        allPeriodSum
      );
      if (moveAmount == 0) {
        continue;
      }
      SplitLineInput input = new SplitLineInput();
      input.lineId = lineId;
      input.moveAmount = moveAmount;
      input.remainAmount = lineAmount - moveAmount;
      input.moveSourcePeriodLineIds = joinIds(collectSourceIds(movePeriods));
      input.remainSourcePeriodLineIds = joinIds(collectSourceIds(keepPeriods));
      input.movePeriodLabel = InvoiceProductMergeService.buildPeriodLabel(
        movePeriods,
        mergeContinuous
      );
      input.remainPeriodLabel = InvoiceProductMergeService.buildPeriodLabel(
        keepPeriods,
        mergeContinuous
      );
      splitLines.add(input);
    }
    return splitLines;
  }

  private static Decimal sumPeriodAmounts(List<InvoiceProduct__c> periods) {
    Decimal total = 0;
    if (periods == null) {
      return total;
    }
    for (InvoiceProduct__c period : periods) {
      if (period != null && period.Amount__c != null) {
        total += period.Amount__c;
      }
    }
    return total;
  }

  /**
   * 利用期間分割の移す金額。請求明細金額 ×（移す期間合計 ÷ 明細の由来期間合計）。
   * 由来期間合計が明細と食い違う（金額分割後の共有 ID 等）でも明細金額を超えない。
   */
  private static Decimal scaleAmountByPeriodShare(
    Decimal lineAmount,
    Decimal movePeriodSum,
    Decimal allPeriodSum
  ) {
    if (lineAmount == null) {
      lineAmount = 0;
    }
    if (
      allPeriodSum == null ||
      allPeriodSum == 0 ||
      movePeriodSum == null ||
      movePeriodSum == 0
    ) {
      return 0;
    }
    return roundInvoiceAmount(lineAmount * movePeriodSum / allPeriodSum);
  }

  /** 移す金額が明細と同符号かつ絶対値が明細以内か。0 は範囲外扱いしない（呼び出し側で除外）。 */
  private static Boolean isMoveAmountOutOfRange(Decimal move, Decimal current) {
    if (move == null || current == null) {
      return true;
    }
    if (current > 0) {
      return move < 0 || move > current;
    }
    if (current < 0) {
      return move > 0 || move < current;
    }
    return move != 0;
  }

  /**
   * 残金額を解決する。未指定なら current - move。
   * 指定時は move + remain == current を強制（水増し／目減り防止）。
   */
  @TestVisible
  private static Decimal resolveConservingRemainAmount(
    Decimal move,
    Decimal remainAmount,
    Decimal current,
    String productName
  ) {
    Decimal safeCurrent = current == null ? 0 : current;
    Decimal safeMove = move == null ? 0 : move;
    if (remainAmount == null) {
      return safeCurrent - safeMove;
    }
    Decimal remain = remainAmount;
    if (safeMove + remain != safeCurrent) {
      String suffix = String.isNotBlank(productName)
        ? (': ' + productName)
        : '';
      throw new InvoiceEditException(SPLIT_AMOUNT_CONSERVE_MESSAGE + suffix);
    }
    return remain;
  }

  /**
   * 税抜合計が 0 のとき、調整前請求額を明細絶対値の寄与比で移す側へ割り当てる。
   * 残側は呼び出し元で sourcePeriodTotal - 戻り値とする（合計保全）。
   */
  @TestVisible
  private static Decimal allocatePeriodTotalByAbsShare(
    Decimal sourcePeriodTotal,
    Decimal movedAbsShare,
    Decimal remainAbsShare
  ) {
    Decimal baseline = sourcePeriodTotal == null ? 0 : sourcePeriodTotal;
    Decimal movedAbs = movedAbsShare == null ? 0 : movedAbsShare;
    Decimal remainAbs = remainAbsShare == null ? 0 : remainAbsShare;
    Decimal denom = movedAbs + remainAbs;
    if (denom == 0) {
      // 分けようがない: 残寄与が無ければ新側へ全額、あれば残側維持（移す側0）
      return remainAbs == 0 ? baseline : 0;
    }
    return roundInvoiceAmount(baseline * movedAbs / denom);
  }

  /**
   * 月分割の移す期間IDを解決する。
   * thresholdDate があればその明細の由来期間から StartDate >= threshold を採用。
   * しきい日は最早月以外の期間月 StartDate のみ許可（両側が空にならない境界）。
   * threshold 未指定時は movePeriodLineIds をそのまま使う。
   */
  private static List<Id> resolvePeriodMoveIdsForLine(
    SplitLineInput raw,
    InvoiceLine__c sourceLine
  ) {
    if (raw == null || sourceLine == null) {
      throw new InvoiceEditException('移す利用期間を選択してください。');
    }
    if (raw.thresholdDate == null) {
      if (raw.movePeriodLineIds == null || raw.movePeriodLineIds.isEmpty()) {
        throw new InvoiceEditException(
          '移す利用期間を選択してください: ' + sourceLine.ProductName__c
        );
      }
      return raw.movePeriodLineIds;
    }

    List<Id> sourcePeriodIds = parseIdList(sourceLine.SourcePeriodLineIds__c);
    if (sourcePeriodIds.size() < 2) {
      throw new InvoiceEditException(
        '月分割には2か月以上の利用期間が必要です: ' + sourceLine.ProductName__c
      );
    }
    Map<Id, InvoiceProduct__c> periodById = new Map<Id, InvoiceProduct__c>(
      [
        SELECT Id, StartDate__c
        FROM InvoiceProduct__c
        WHERE Id IN :sourcePeriodIds
        WITH SYSTEM_MODE
      ]
    );
    Date earliest = null;
    Set<Date> allowedThresholds = new Set<Date>();
    for (Id periodId : sourcePeriodIds) {
      InvoiceProduct__c period = periodById.get(periodId);
      if (period == null || period.StartDate__c == null) {
        continue;
      }
      if (earliest == null || period.StartDate__c < earliest) {
        earliest = period.StartDate__c;
      }
    }
    for (Id periodId : sourcePeriodIds) {
      InvoiceProduct__c period = periodById.get(periodId);
      if (
        period == null ||
        period.StartDate__c == null ||
        period.StartDate__c == earliest
      ) {
        continue;
      }
      allowedThresholds.add(period.StartDate__c);
    }
    if (earliest == null || !allowedThresholds.contains(raw.thresholdDate)) {
      throw new InvoiceEditException(
        'しきい日は日割のない期間月の開始日を選んでください: ' +
        sourceLine.ProductName__c
      );
    }

    List<Id> moveIds = new List<Id>();
    for (Id periodId : sourcePeriodIds) {
      InvoiceProduct__c period = periodById.get(periodId);
      if (
        period != null &&
        period.StartDate__c != null &&
        period.StartDate__c >= raw.thresholdDate
      ) {
        moveIds.add(periodId);
      }
    }
    if (moveIds.isEmpty()) {
      throw new InvoiceEditException(
        '移す利用期間を選択してください: ' + sourceLine.ProductName__c
      );
    }
    // 最早月は残す側に残る想定。全移動は境界バリデーションで防ぐ。
    if (moveIds.size() >= sourcePeriodIds.size()) {
      throw new InvoiceEditException(
        'しきい日では残す側が空になります: ' + sourceLine.ProductName__c
      );
    }
    return moveIds;
  }

  private static List<Id> parseIdList(String raw) {
    List<Id> ids = new List<Id>();
    if (String.isBlank(raw)) {
      return ids;
    }
    for (String part : raw.split(',')) {
      String trimmed = part == null ? null : part.trim();
      if (String.isBlank(trimmed)) {
        continue;
      }
      try {
        ids.add((Id) trimmed);
      } catch (Exception ignore) {
        // 監査用文字列のため不正値は無視
      }
    }
    return ids;
  }

  private static List<Id> collectSourceIds(List<InvoiceProduct__c> products) {
    List<Id> ids = new List<Id>();
    if (products == null) {
      return ids;
    }
    for (InvoiceProduct__c product : products) {
      if (product != null && product.Id != null) {
        ids.add(product.Id);
      }
    }
    return ids;
  }

  private static String joinIds(List<Id> ids) {
    if (ids == null || ids.isEmpty()) {
      return null;
    }
    List<String> parts = new List<String>();
    for (Id value : ids) {
      if (value != null) {
        parts.add(String.valueOf(value));
      }
    }
    return String.join(parts, ',');
  }

  private static List<InvoiceProduct__c> queryPeriodLinesForCanonical(
    Set<Id> contractHistoryIds
  ) {
    Set<String> selectFields = new Set<String>{
      'Id',
      'Name',
      'InvoiceBucketKey__c',
      'LineBucketKey__c',
      'UnitPrice__c',
      'Quantity__c',
      'Unit__c',
      'StartDate__c',
      'Enddate__c',
      'Amount__c',
      'ContractHistory__r.ContractService__r.TaxPercent__c',
      'ContractProduct__c',
      'ContractProduct__r.Product__c',
      'ContractProduct__r.Product__r.Name',
      'ContractProduct__r.Product__r.BillingType__c',
      'ContractProduct__r.Product__r.RevenueRecognitionBasis__c',
      'ContractProduct__r.Unit__c',
      'ContractProduct__r.BillingType__c',
      'ContractProduct__r.RevenueRecognitionBasis__c',
      'ContractProduct__r.Type__c',
      'ContractHistory__c',
      'ContractHistory__r.Version__c',
      'ContractHistory__r.ContractService__c',
      'ContractHistory__r.ContractService__r.Name',
      'ContractHistory__r.ContractService__r.BiilingAcccount__c',
      'ContractHistory__r.ContractService__r.BiilingAcccount__r.Name',
      'ContractHistory__r.ContractService__r.Account__c',
      'ContractHistory__r.ContractService__r.Account__r.Name',
      'ContractProduct__r.Product__r.ProductCode'
    };
    // 請求／請求明細向け CMDT のコピー元を親子リレーション経由で取得
    for (
      String fieldApiName : InvoiceProductFieldCopyService.getSourceFieldApiNames(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
        InvoiceProductFieldCopyService.TARGET_INVOICE
      )
    ) {
      if (fieldApiName != null && fieldApiName != 'Id') {
        selectFields.add('ContractHistory__r.' + fieldApiName);
      }
    }
    for (
      String fieldApiName : InvoiceProductFieldCopyService.getSourceFieldApiNames(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_PRODUCT,
        InvoiceProductFieldCopyService.TARGET_INVOICE_LINE
      )
    ) {
      if (fieldApiName != null && fieldApiName != 'Id') {
        selectFields.add('ContractProduct__r.' + fieldApiName);
      }
    }
    List<String> selectList = new List<String>(selectFields);
    selectList.sort();
    String soql =
      'SELECT ' +
      String.join(selectList, ',') +
      ' FROM InvoiceProduct__c' +
      ' WHERE ContractHistory__c IN :contractHistoryIds' +
      ' WITH SYSTEM_MODE' +
      ' ORDER BY InvoiceBucketKey__c ASC NULLS LAST, StartDate__c ASC NULLS LAST, Name ASC';
    return Database.query(soql);
  }

  private static Map<Id, BillingAccount__c> loadBillingAccountsForProducts(
    List<InvoiceProduct__c> products
  ) {
    Set<Id> billingAccountIds = new Set<Id>();
    if (products != null) {
      for (InvoiceProduct__c product : products) {
        Id billingAccountId = resolveBillingAccountId(product);
        if (billingAccountId != null) {
          billingAccountIds.add(billingAccountId);
        }
      }
    }
    Map<Id, BillingAccount__c> byId = new Map<Id, BillingAccount__c>();
    if (billingAccountIds.isEmpty()) {
      return byId;
    }
    // ハードコード SnapShot 用（CMDT 依存にしない）
    Set<String> selectFields = new Set<String>{
      'Id',
      'BillingAddressee__c',
      'BillingEmailTo__c',
      'BillingEmailCc__c',
      'BillingEmailBcc__c',
      'BillingAccountKey__c'
    };
    selectFields.addAll(BillingScheduleService.BILLING_ACCOUNT_SCHEDULE_FIELDS);
    selectFields.addAll(
      InvoiceProductFieldCopyService.getSourceFieldApiNames(
        InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT,
        InvoiceProductFieldCopyService.TARGET_INVOICE
      )
    );
    Map<String, Schema.SObjectField> baFieldMap = BillingAccount__c.SObjectType.getDescribe()
      .fields.getMap();
    List<String> selectList = new List<String>();
    for (String fieldApiName : selectFields) {
      if (baFieldMap.containsKey(fieldApiName)) {
        selectList.add(fieldApiName);
      }
    }
    selectList.sort();
    String soql =
      'SELECT ' +
      String.join(selectList, ',') +
      ' FROM BillingAccount__c' +
      ' WHERE Id IN :billingAccountIds' +
      ' WITH SYSTEM_MODE';
    for (BillingAccount__c ba : Database.query(soql)) {
      byId.put(ba.Id, ba);
    }
    return byId;
  }

  private static Id resolveBillingAccountId(InvoiceProduct__c product) {
    if (
      product == null ||
      product.ContractHistory__r == null ||
      product.ContractHistory__r.ContractService__r == null
    ) {
      return null;
    }
    return product.ContractHistory__r.ContractService__r.BiilingAcccount__c;
  }

  private static Map<String, SObject> buildCanonicalCopySources(
    InvoiceProduct__c periodLine,
    BillingAccount__c billingAccount
  ) {
    Map<String, SObject> sources = new Map<String, SObject>();
    if (periodLine != null) {
      if (periodLine.ContractHistory__r != null) {
        sources.put(
          InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
          periodLine.ContractHistory__r
        );
      }
      if (periodLine.ContractProduct__r != null) {
        sources.put(
          InvoiceProductFieldCopyService.OBJECT_CONTRACT_PRODUCT,
          periodLine.ContractProduct__r
        );
        if (periodLine.ContractProduct__r.Product__r != null) {
          sources.put(
            InvoiceProductFieldCopyService.OBJECT_PRODUCT,
            periodLine.ContractProduct__r.Product__r
          );
        }
      }
    }
    if (billingAccount != null) {
      sources.put(
        InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT,
        billingAccount
      );
    }
    if (
      periodLine != null &&
      periodLine.ContractHistory__r != null &&
      periodLine.ContractHistory__r.ContractService__r != null &&
      periodLine.ContractHistory__r.ContractService__r.Account__r != null
    ) {
      sources.put(
        InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
        periodLine.ContractHistory__r.ContractService__r.Account__r
      );
    }
    return sources;
  }

  /**
   * 必須の BA SnapShot（Id・キー・宛名・メール・支払条件・請求日）をコードで埋める。
   * Insert トリガ側と同じ空欄埋め（手入力の非空は尊重）。
   * 仕様: Core 第3.3.5節、第5.2節
   */
  private static void applyHardcodedBillingAccountSnapshot(
    Invoice__c invoice,
    BillingAccount__c billingAccount
  ) {
    InvoiceProductFieldCopyService.applyHardcodedInvoiceBillingAccountSnapshot(
      invoice,
      billingAccount
    );
  }

  private static void refreshLineMergeKey(InvoiceLine__c line) {
    if (line == null) {
      return;
    }
    line.LineMergeKey__c = InvoiceMergeKeyConfigService.buildLineBucketKey(
      line.ContractProduct__c,
      line.UnitPrice__c,
      line.Quantity__c,
      line.Unit__c,
      line.Product__c
    );
  }

  /**
   * 期間 ID リストからサービス期間を再計算。リストが空／同一なら source をコピー。
   */
  private static void applyServicePeriodSnapshot(
    InvoiceLine__c target,
    InvoiceLine__c sourceFallback,
    String sourcePeriodLineIds
  ) {
    if (target == null) {
      return;
    }
    DateRange bounds = resolveServicePeriodBounds(sourcePeriodLineIds);
    if (bounds != null) {
      target.ServicePeriodStartDate__c = bounds.startDate;
      target.ServicePeriodEndDate__c = bounds.endDate;
      InvoiceProductMergeService.assertPeriodIdsContiguous(
        sourcePeriodLineIds,
        loadPeriodsByIds(sourcePeriodLineIds)
      );
      return;
    }
    if (sourceFallback != null) {
      target.ServicePeriodStartDate__c = sourceFallback.ServicePeriodStartDate__c;
      target.ServicePeriodEndDate__c = sourceFallback.ServicePeriodEndDate__c;
    }
  }

  private class DateRange {
    public Date startDate;
    public Date endDate;
  }

  private static DateRange resolveServicePeriodBounds(String sourcePeriodLineIds) {
    Map<Id, InvoiceProduct__c> periodById = loadPeriodsByIds(sourcePeriodLineIds);
    if (periodById.isEmpty()) {
      return null;
    }
    Date minStart;
    Date maxEnd;
    for (InvoiceProduct__c period : periodById.values()) {
      if (
        period.StartDate__c != null &&
        (minStart == null || period.StartDate__c < minStart)
      ) {
        minStart = period.StartDate__c;
      }
      if (
        period.Enddate__c != null &&
        (maxEnd == null || period.Enddate__c > maxEnd)
      ) {
        maxEnd = period.Enddate__c;
      }
    }
    if (minStart == null || maxEnd == null || maxEnd < minStart) {
      throw new InvoiceEditException(
        '請求明細のサービス期間が不正です（開始・終了が揃いません）。'
      );
    }
    DateRange bounds = new DateRange();
    bounds.startDate = minStart;
    bounds.endDate = maxEnd;
    return bounds;
  }

  private static Map<Id, InvoiceProduct__c> loadPeriodsByIds(
    String sourcePeriodLineIds
  ) {
    Map<Id, InvoiceProduct__c> periodById = new Map<Id, InvoiceProduct__c>();
    if (String.isBlank(sourcePeriodLineIds)) {
      return periodById;
    }
    Set<Id> ids = new Set<Id>();
    for (String token : sourcePeriodLineIds.split(',')) {
      if (String.isBlank(token)) {
        continue;
      }
      ids.add(Id.valueOf(token.trim()));
    }
    if (ids.isEmpty()) {
      return periodById;
    }
    for (InvoiceProduct__c period : [
      SELECT Id, StartDate__c, Enddate__c, Amount__c
      FROM InvoiceProduct__c
      WHERE Id IN :ids
      WITH SYSTEM_MODE
    ]) {
      periodById.put(period.Id, period);
    }
    return periodById;
  }

  /**
   * 仕様: Core 第3.3.5節、第3.3.7節、第7.8節
   */
  private static BillingAccount__c loadBillingAccountForSnapshot(
    Id billingAccountId
  ) {
    if (billingAccountId == null) {
      return null;
    }
    List<BillingAccount__c> rows = [
      SELECT
        Id,
        BillingAddressee__c,
        BillingEmailTo__c,
        BillingEmailCc__c,
        BillingEmailBcc__c,
        BillingAccountKey__c,
        InvoiceDeliveryMethod__c,
        InvoiceDateMethod__c,
        InvoiceDateDayKind__c,
        InvoiceDateDayOfMonth__c,
        InvoiceDateMonthOffset__c,
        InvoiceDateDayOffset__c,
        InvoiceDateAdjust__c,
        PaymentTermMethod__c,
        PaymentTermDayKind__c,
        PaymentTermDayOfMonth__c,
        PaymentTermMonthOffset__c,
        PaymentTermDayOffset__c,
        PaymentTermAdjust__c
      FROM BillingAccount__c
      WHERE Id = :billingAccountId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /**
   * 新規請求に載せる請求アカウント参照だけをセットする。
   * 宛名・メール等の必須 SnapShot 本文は applyHardcodedBillingAccountSnapshot で埋める。
   */
  private static void prepareBillingAccountSnapshotReference(
    Invoice__c invoice,
    Id billingAccountId
  ) {
    if (invoice == null || billingAccountId == null) {
      return;
    }
    Integer found = [
      SELECT COUNT()
      FROM BillingAccount__c
      WHERE Id = :billingAccountId
      WITH SYSTEM_MODE
    ];
    if (found == 0) {
      throw new InvoiceEditException('指定の請求アカウントが見つかりません。');
    }
    invoice.BillingAccountSnapShot__c = billingAccountId;
  }

  /**
   * 仕様: Accounting 第3.2節、第3.3節、日付仕様 第1.2節。
   * 月次は組織の月次方式と同じ刻みの件数。一括は1。月次でサービス期間が空なら空欄。検収終了日は使わない。
   */
  public static void applyRecognitionBucketCount(List<InvoiceLine__c> lines) {
    applyRecognitionBucketCount(lines, null);
  }

  /** 仕様: Accounting 第3.2節、第3.3節、日付仕様 第1.2節 */
  public static void applyRecognitionBucketCount(
    List<InvoiceLine__c> lines,
    Map<Id, InvoiceLine__c> oldMap
  ) {
    if (lines == null || lines.isEmpty()) {
      return;
    }
    String method = null;
    for (InvoiceLine__c line : lines) {
      if (line == null) {
        continue;
      }
      InvoiceLine__c prior = oldMap == null || line.Id == null
        ? null
        : oldMap.get(line.Id);
      String basis = ContractMetadataService.normalizeRevenueRecognitionBasis(
        (String) recognitionField(line, prior, InvoiceLine__c.RevenueRecognitionBasis__c)
      );
      if (basis == ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME) {
        line.RecognitionBucketCount__c = 1;
        continue;
      }
      if (basis != ContractMetadataService.REVENUE_BASIS_OVER_TIME) {
        line.RecognitionBucketCount__c = null;
        continue;
      }
      Date startDate = (Date) recognitionField(
        line,
        prior,
        InvoiceLine__c.ServicePeriodStartDate__c
      );
      Date endDate = (Date) recognitionField(
        line,
        prior,
        InvoiceLine__c.ServicePeriodEndDate__c
      );
      if (startDate == null || endDate == null) {
        line.RecognitionBucketCount__c = null;
        continue;
      }
      if (method == null) {
        method = recognitionBucketMethod();
      }
      List<MonthlyBillingPeriodUtil.BillingPeriod> periods = monthlyRecognitionPeriods(
        startDate,
        endDate,
        method
      );
      line.RecognitionBucketCount__c = periods.isEmpty() ? null : periods.size();
    }
  }

  /** 仕様: Accounting 第9.1.1節。確認用のカンマ金額。税込は税抜＋明細税。 */
  public static void applyYenCommaTexts(List<InvoiceLine__c> lines) {
    if (lines == null || lines.isEmpty()) {
      return;
    }
    for (InvoiceLine__c line : lines) {
      if (line == null) {
        continue;
      }
      Decimal body = line.Amount__c == null ? 0 : line.Amount__c;
      Decimal tax = line.AllocatedTaxAmount__c == null ? 0 : line.AllocatedTaxAmount__c;
      line.AmountCommaText__c = yenCommaText(body);
      line.AllocatedTaxCommaText__c = yenCommaText(tax);
      line.TaxInclusiveCommaText__c = yenCommaText(body + tax);
    }
  }

  /** 仕様: Accounting 第9.1.1節。桁区切りはカンマ。例 1,000,000。負は先頭に - */
  @TestVisible
  private static String yenCommaText(Decimal value) {
    Long n = value == null ? 0 : value.longValue();
    Long absN = n < 0 ? -n : n;
    String digits = String.valueOf(absN);
    String grouped = '';
    while (digits.length() > 3) {
      grouped = ',' + digits.substring(digits.length() - 3) + grouped;
      digits = digits.substring(0, digits.length() - 3);
    }
    grouped = digits + grouped;
    return n < 0 ? '-' + grouped : grouped;
  }

  /** 仕様: Core 第7.6節、第4.4.3節、Accounting 第3.2節 */
  public static void assertAcceptanceRules(List<InvoiceLine__c> lines) {
    assertAcceptanceRules(lines, null);
  }

  /** 仕様: Core 第7.6節、第4.4.3節、Accounting 第3.2節 */
  public static void assertAcceptanceRules(
    List<InvoiceLine__c> lines,
    Map<Id, InvoiceLine__c> oldMap
  ) {
    if (lines == null) {
      return;
    }
    for (InvoiceLine__c line : lines) {
      if (line == null) {
        continue;
      }
      if (oldMap != null && line.Id != null) {
        InvoiceLine__c prior = oldMap.get(line.Id);
        if (prior != null) {
          String nextBasis = ContractMetadataService.normalizeRevenueRecognitionBasis(
            line.RevenueRecognitionBasis__c
          );
          String priorBasis = ContractMetadataService.normalizeRevenueRecognitionBasis(
            prior.RevenueRecognitionBasis__c
          );
          if (nextBasis != priorBasis) {
            line.addError(EXISTING_BASIS_LOCKED_MESSAGE);
          }
        }
      }
      String basis = ContractMetadataService.normalizeRevenueRecognitionBasis(
        line.RevenueRecognitionBasis__c
      );
      if (
        basis == ContractMetadataService.REVENUE_BASIS_OVER_TIME &&
        line.AcceptanceEndDate__c != null
      ) {
        line.addError('月次計上に検収終了日は設定できません。');
      }
      if (
        basis == ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME &&
        line.AcceptanceEndDate__c == null
      ) {
        line.addError('一括計上の検収終了日は空にできません。');
      }
    }
  }

  private static Date acceptanceEndDateForNewLine(String basis, Date servicePeriodEndDate) {
    return ContractMetadataService.normalizeRevenueRecognitionBasis(basis) ==
        ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
      ? servicePeriodEndDate
      : null;
  }

  /** 仕様: Accounting 第3.1節・第3.2節、Core 第1.1.10節。方針0件・月次方式空を Auto へ落とさない。 */
  private static String recognitionBucketMethod() {
    GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
    if (String.isBlank(policy.MonthlyBucketMethod__c)) {
      throw new GlAccountingPolicyService.PolicyException(
        '月次バケットの刻み方がありません。'
      );
    }
    return policy.MonthlyBucketMethod__c;
  }

  private static Object recognitionField(
    InvoiceLine__c line,
    InvoiceLine__c prior,
    SObjectField field
  ) {
    if (prior == null || line.isSet(field)) {
      return line.get(field);
    }
    return prior.get(field);
  }

  /** 仕様: Accounting 第3.3節、日付仕様 第1.2節。AccountingGoalService の月次刻みと同じ。 */
  private static List<MonthlyBillingPeriodUtil.BillingPeriod> monthlyRecognitionPeriods(
    Date startDate,
    Date endDate,
    String method
  ) {
    if (method == 'CalendarMonth') {
      return MonthlyBillingPeriodUtil.buildCalendarMonthPeriods(startDate, endDate);
    }
    if (method == 'Auto' && MonthlyBillingPeriodUtil.countMonthlyCycles(startDate, endDate) < 0) {
      return MonthlyBillingPeriodUtil.buildCalendarMonthPeriods(startDate, endDate);
    }
    return MonthlyBillingPeriodUtil.buildMonthlyPeriodsCoveringEnd(startDate, endDate);
  }
}
