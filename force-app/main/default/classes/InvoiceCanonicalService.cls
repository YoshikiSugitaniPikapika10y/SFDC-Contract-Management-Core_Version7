/**
 * 契約期間明細（InvoiceProduct__c）から請求正本（Invoice__c / InvoiceLine__c）を生成・更新する。
 * プレビュー集約ロジック（InvoiceProductMergeService）と同じキーで永続化する。
 */
public without sharing class InvoiceCanonicalService {
  @TestVisible
  private static Boolean testHasEditPreviewPermission;

  public static final String SPLIT_AMOUNT_CONSERVE_MESSAGE =
    '分割後の金額合計が元の明細金額と一致しません。';

  public class InvoiceEditException extends Exception {
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
      ContractPermissionUtil.EDIT_INVOICE_PREVIEW
    );
  }

  public static void assertCanEditInvoicePreview() {
    if (!canEditInvoicePreview()) {
      throw new InvoiceEditException('請求プレビューを編集する権限がありません。');
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
        '期間明細・請求・請求明細は受注済み（Ordered）の契約履歴にのみ作成できます。'
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
    deleteInvoicesForHistories(contractHistoryIds);
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
          PaymentClearingCompletedDate__c
        FROM Invoice__c
        WHERE ContractHistory__c IN :contractHistoryIds
        WITH SYSTEM_MODE
      ];
      if (!ContractPermissionUtil.canBypassIntegrityGuards()) {
        for (Invoice__c invoice : existing) {
          if (InvoiceLockUtil.isLocked(invoice)) {
            throw new InvoiceLockUtil.InvoiceLockException(
              InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE
            );
          }
        }
      }
      if (!existing.isEmpty()) {
        SystemContextAccess.deleteRecords(existing);
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

  /**
   * 契約サービス配下で請求正本が無い Version を、既存の契約期間明細から埋める。
   */
  public static Integer backfillMissingForContractService(Id contractServiceId) {
    if (contractServiceId == null) {
      return 0;
    }
    Set<Id> historyIds = new Set<Id>();
    String orderedStatus = ContractDomainConstants.HISTORY_STATUS_ORDERED;
    for (AggregateResult ar : [
      SELECT ContractHistory__c historyId
      FROM InvoiceProduct__c
      WHERE
        ContractHistory__r.ContractService__c = :contractServiceId
        AND ContractHistory__r.historystatus__c = :orderedStatus
      WITH SYSTEM_MODE
      GROUP BY ContractHistory__c
    ]) {
      historyIds.add((Id) ar.get('historyId'));
    }
    if (historyIds.isEmpty()) {
      return 0;
    }
    Set<Id> already = new Set<Id>();
    for (AggregateResult ar : [
      SELECT ContractHistory__c historyId
      FROM Invoice__c
      WHERE ContractHistory__c IN :historyIds
      WITH SYSTEM_MODE
      GROUP BY ContractHistory__c
    ]) {
      already.add((Id) ar.get('historyId'));
    }
    Set<Id> missing = new Set<Id>();
    for (Id historyId : historyIds) {
      if (!already.contains(historyId)) {
        missing.add(historyId);
      }
    }
    if (missing.isEmpty()) {
      return 0;
    }
    persistFromPeriodLines(missing);
    return missing.size();
  }

  private static void persistFromPeriodLines(Set<Id> contractHistoryIds) {
    // 非 Ordered には請求正本を作らない（バックフィル混入防止）
    contractHistoryIds = retainOrderedHistoryIds(contractHistoryIds);
    if (contractHistoryIds.isEmpty()) {
      return;
    }
    InvoiceProductFieldCopyService.validateActiveDefinitions();
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
      invoice.IsManuallyAdjusted__c = false;
      invoice.SourcePeriodLineIds__c = joinIds(collectSourceIds(mi.sourceProducts));
      // 連携日／消込日は Ops が請求書に付与する。期間明細からはコピーしない。
      invoice.SystemIntegrationDate__c = null;
      invoice.PaymentClearingCompletedDate__c = null;

      // BA SnapShot（必須）はハードコード。CMDT は顧客／サンプル拡張のみ。
      Id billingAccountId = resolveBillingAccountId(rep);
      BillingAccount__c billingAccount = billingAccountById.get(billingAccountId);
      applyHardcodedBillingAccountSnapshot(invoice, billingAccount);
      InvoiceProductFieldCopyService.applyCopies(
        invoice,
        InvoiceProductFieldCopyService.TARGET_INVOICE,
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
      List<InvoiceProductMergeService.MergedLine> lines = linesByInvoiceIndex[i];
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
        line.IsManuallyAdjusted__c = false;
        line.SourcePeriodLineIds__c = joinIds(ml.sourceInvoiceProductIds);
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
        InvoiceProductFieldCopyService.applyCopies(
          line,
          InvoiceProductFieldCopyService.TARGET_INVOICE_LINE,
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
      amountByLineId.put(
        edit.lineId,
        edit.amount.setScale(0, RoundingMode.HALF_UP)
      );
    }

    List<InvoiceLine__c> lines = [
      SELECT
        Id,
        Amount__c,
        Invoice__c,
        Invoice__r.ContractHistory__c
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
      line.IsManuallyAdjusted__c = true;
    }
    SystemContextAccess.updateRecords(lines);
    for (Id invoiceId : invoiceIds) {
      markInvoiceAdjustedAndRecalc(invoiceId);
    }
  }

  /**
   * 請求プレビュー編集: 請求に埋め込まれた請求日・入金予定日のみ更新する。
   * 上流マスタや契約期間明細は更新しない（入金予定の自動再計算もしない）。
   */
  public static void updateInvoiceDates(
    Id invoiceId,
    Date invoiceDate,
    Date paymentScheduledDate
  ) {
    assertCanEditInvoicePreview();
    if (invoiceId == null) {
      throw new InvoiceEditException('請求は必須です。');
    }
    Invoice__c invoice = [
      SELECT
        Id,
        ContractHistory__c,
        InvoiceDate__c,
        PaymentScheduledDate__c,
        SystemIntegrationDate__c,
        PaymentClearingCompletedDate__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    InvoiceLockUtil.assertInvoiceEditable(invoice);
    if (invoiceDate != null) {
      invoice.InvoiceDate__c = invoiceDate;
    }
    if (paymentScheduledDate != null) {
      invoice.PaymentScheduledDate__c = paymentScheduledDate;
    }
    invoice.IsManuallyAdjusted__c = true;
    invoice.MergeKey__c = null;
    SystemContextAccess.updateRecords(new List<Invoice__c>{ invoice });
  }

  /**
   * 請求プレビュー編集: 請求に埋め込まれた宛名・メール SnapShot と税率を更新する。
   * 請求アカウントマスタ／支払条件ルール／契約期間明細等は更新しない。
   * billingAccountId・paymentTerm 引数は互換のため残すが無視する（BA 差し替えは分割を使う）。
   * taxPercent は表示％（10＝10%）。null のときは税率を変更しない。
   */
  public static void updateInvoiceBillingHeader(
    Id invoiceId,
    Id billingAccountId,
    String billingAddressee,
    String billingEmailTo,
    String billingEmailCc,
    String billingEmailBcc,
    String paymentTerm,
    Decimal taxPercent
  ) {
    assertCanEditInvoicePreview();
    if (invoiceId == null) {
      throw new InvoiceEditException('請求は必須です。');
    }
    // billingAccountId / paymentTerm は Aura 互換のため残すが意図的に未使用。
    // BA 差し替えは splitInvoiceByBillingAccount、支払条件は BA ルール側の責務。
    Invoice__c invoice = [
      SELECT
        Id,
        ContractHistory__c,
        Amount__c,
        TaxPercent__c,
        TaxAmount__c,
        BillingAddresseeSnapShot__c,
        BillingEmailToSnapShot__c,
        BillingEmailCcSnapShot__c,
        BillingEmailBccSnapShot__c,
        SystemIntegrationDate__c,
        PaymentClearingCompletedDate__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    InvoiceLockUtil.assertInvoiceEditable(invoice);
    if (billingAddressee != null) {
      invoice.BillingAddresseeSnapShot__c = billingAddressee;
    }
    if (billingEmailTo != null) {
      invoice.BillingEmailToSnapShot__c = billingEmailTo;
    }
    if (billingEmailCc != null) {
      invoice.BillingEmailCcSnapShot__c = billingEmailCc;
    }
    if (billingEmailBcc != null) {
      invoice.BillingEmailBccSnapShot__c = billingEmailBcc;
    }
    if (taxPercent != null) {
      Decimal displayPercent = TaxCalculationUtil.resolveTaxPercent(taxPercent);
      invoice.TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(
        displayPercent
      );
      Decimal amountTotal = invoice.Amount__c == null ? 0 : invoice.Amount__c;
      invoice.TaxAmount__c = TaxCalculationUtil.calculateTaxAmount(
        amountTotal,
        displayPercent
      );
    }
    invoice.IsManuallyAdjusted__c = true;
    invoice.MergeKey__c = null;
    SystemContextAccess.updateRecords(new List<Invoice__c>{ invoice });
  }

  /**
   * 請求プレビュー「請求情報編集」: 日付・宛名・メール・税率を同一 Invoice へ 1 DML で更新する。
   * 画面上の一体保存を 2 トランザクションに割らない（片側だけ成功してエラー表示、を防ぐ）。
   * billingAccountId・paymentTerm は互換のため残すが無視する（updateInvoiceBillingHeader と同じ）。
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
        PaymentClearingCompletedDate__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    InvoiceLockUtil.assertInvoiceEditable(invoice);
    if (invoiceDate != null) {
      invoice.InvoiceDate__c = invoiceDate;
    }
    if (paymentScheduledDate != null) {
      invoice.PaymentScheduledDate__c = paymentScheduledDate;
    }
    if (billingAddressee != null) {
      invoice.BillingAddresseeSnapShot__c = billingAddressee;
    }
    if (billingEmailTo != null) {
      invoice.BillingEmailToSnapShot__c = billingEmailTo;
    }
    if (billingEmailCc != null) {
      invoice.BillingEmailCcSnapShot__c = billingEmailCc;
    }
    if (billingEmailBcc != null) {
      invoice.BillingEmailBccSnapShot__c = billingEmailBcc;
    }
    if (taxPercent != null) {
      Decimal displayPercent = TaxCalculationUtil.resolveTaxPercent(taxPercent);
      invoice.TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(
        displayPercent
      );
      Decimal amountTotal = invoice.Amount__c == null ? 0 : invoice.Amount__c;
      invoice.TaxAmount__c = TaxCalculationUtil.calculateTaxAmount(
        amountTotal,
        displayPercent
      );
    }
    invoice.IsManuallyAdjusted__c = true;
    invoice.MergeKey__c = null;
    SystemContextAccess.updateRecords(new List<Invoice__c>{ invoice });
  }

  /**
   * 統一分割: 明細ごと（whole）／単価／個数／月 を混在して新請求へ振り分ける。
   * ②（unitPrice / quantity / period）が1行でも含まれると端数・手動調整をクリアする。
   * ①のみのときは従来の請求日分割と同様、調整前を金額比で引き継ぐ。
   */
  public static Id splitInvoiceUnified(
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    Id newBillingAccountId,
    List<SplitLineInput> splitLines
  ) {
    assertCanEditInvoicePreview();
    if (
      sourceInvoiceId == null ||
      newInvoiceDate == null ||
      splitLines == null ||
      splitLines.isEmpty()
    ) {
      throw new InvoiceEditException('分割元請求・請求日・分割内容は必須です。');
    }

    Map<Id, InvoiceLine__c> sourceLineById = new Map<Id, InvoiceLine__c>(
      [
        SELECT
          Id,
          Amount__c,
          UnitPrice__c,
          Quantity__c,
          ProductName__c,
          SourcePeriodLineIds__c,
          ContractProduct__r.BillingType__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :sourceInvoiceId
        WITH SYSTEM_MODE
      ]
    );
    if (sourceLineById.isEmpty()) {
      throw new InvoiceEditException('分割対象の明細が見つかりません。');
    }

    Boolean clearManualAdjustment = false;
    Set<Id> periodMoveIds = new Set<Id>();
    Map<Id, SplitLineInput> periodInputByLineId = new Map<Id, SplitLineInput>();
    List<SplitLineInput> normalized = new List<SplitLineInput>();

    for (SplitLineInput raw : splitLines) {
      if (raw == null || raw.lineId == null) {
        continue;
      }
      InvoiceLine__c sourceLine = sourceLineById.get(raw.lineId);
      if (sourceLine == null) {
        throw new InvoiceEditException('分割対象の明細が見つかりません。');
      }
      String mode = String.isBlank(raw.splitMode)
        ? null
        : raw.splitMode.trim();
      if (mode == SPLIT_MODE_PERIOD) {
        clearManualAdjustment = true;
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
        periodInputByLineId.put(raw.lineId, raw);
        continue;
      }
      if (mode == SPLIT_MODE_UNIT_PRICE || mode == SPLIT_MODE_QUANTITY) {
        clearManualAdjustment = true;
      }
      normalized.add(normalizeFactorSplitInput(raw, sourceLine, mode));
    }

    if (!periodMoveIds.isEmpty()) {
      List<SplitLineInput> periodNormalized = buildPeriodSplitInputs(
        sourceInvoiceId,
        periodMoveIds,
        periodInputByLineId.keySet()
      );
      for (SplitLineInput periodInput : periodNormalized) {
        periodInput.splitMode = SPLIT_MODE_PERIOD;
        normalized.add(periodInput);
      }
    }
    if (normalized.isEmpty()) {
      throw new InvoiceEditException('移動する明細がありません。');
    }

    return splitInvoice(
      sourceInvoiceId,
      newInvoiceDate,
      newPaymentScheduledDate,
      newBillingAccountId,
      normalized,
      true,
      clearManualAdjustment
    );
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
    InvoiceProductFieldCopyService.validateActiveDefinitions();
    if (invoiceId == null || splitLines == null || splitLines.isEmpty()) {
      throw new InvoiceEditException('分割元請求・分割内容は必須です。');
    }

    Invoice__c source = [
      SELECT
        Id,
        Amount__c,
        PeriodLineAmountTotal__c,
        SystemIntegrationDate__c,
        PaymentClearingCompletedDate__c
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
          Unit__c,
          UnitPrice__c,
          Quantity__c,
          PeriodLabel__c,
          LineMergeKey__c,
          HistoryVersionLabel__c,
          SourcePeriodLineIds__c,
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
      String mode = String.isBlank(raw.splitMode)
        ? null
        : raw.splitMode.trim();
      if (
        mode != SPLIT_MODE_UNIT_PRICE &&
        mode != SPLIT_MODE_QUANTITY &&
        mode != SPLIT_MODE_PERIOD
      ) {
        throw new InvoiceEditException(
          '同一請求内分割は単価・個数・月分割のみです: ' + sourceLine.ProductName__c
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
      Decimal move = input.moveAmount.setScale(0, RoundingMode.HALF_UP);
      if (move == 0) {
        continue;
      }
      input.moveAmount = move;
      if (input.remainAmount != null) {
        input.remainAmount = input.remainAmount.setScale(0, RoundingMode.HALF_UP);
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
      createdLine.LineMergeKey__c = sourceLine.LineMergeKey__c;
      createdLine.HistoryVersionLabel__c = sourceLine.HistoryVersionLabel__c;
      createdLine.SourcePeriodLineIds__c = input.moveSourcePeriodLineIds != null
        ? input.moveSourcePeriodLineIds
        : sourceLine.SourcePeriodLineIds__c;
      createdLine.ContractProduct__c = sourceLine.ContractProduct__c;
      if (sourceLine.ContractProduct__r != null) {
        createdLine.Product__c = sourceLine.ContractProduct__r.Product__c;
        createdLine.Unit__c = String.isNotBlank(sourceLine.ContractProduct__r.Unit__c)
          ? sourceLine.ContractProduct__r.Unit__c
          : sourceLine.Unit__c;
      } else {
        createdLine.Unit__c = sourceLine.Unit__c;
      }
      createdLine.IsManuallyAdjusted__c = false;
      newLines.add(createdLine);

      Decimal remain = resolveConservingRemainAmount(
        move,
        input.remainAmount,
        current,
        sourceLine.ProductName__c
      );
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
        sourceLine.IsManuallyAdjusted__c = false;
        if (input.remainSourcePeriodLineIds != null) {
          sourceLine.SourcePeriodLineIds__c = input.remainSourcePeriodLineIds;
        }
        if (input.remainPeriodLabel != null) {
          sourceLine.PeriodLabel__c = input.remainPeriodLabel;
        }
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

    // 因子／月分割: 分割対象行の端数はクリア済み。
    // 兄弟明細に手動調整が残るなら親フラグと調整前合計を維持する
    // （無条件 false / 調整前上書きだと Invoice 詳細と差し戻し警告が壊れる）。
    // 残調整が無いときだけ、仕様どおり調整前＝税抜合計に揃える。
    recalcInvoiceTotals(invoiceId, false);
    Invoice__c refreshed = [
      SELECT Id, Amount__c, IsManuallyAdjusted__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (refreshed.IsManuallyAdjusted__c == true) {
      return;
    }
    Decimal amountTotal = refreshed.Amount__c == null ? 0 : refreshed.Amount__c;
    SystemContextAccess.updateRecords(
      new List<Invoice__c>{
        new Invoice__c(
          Id = invoiceId,
          PeriodLineAmountTotal__c = amountTotal,
          IsManuallyAdjusted__c = false
        )
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

    List<InvoiceLine__c> lines = [
      SELECT
        Id,
        Amount__c,
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
    for (InvoiceLine__c line : lines) {
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
      lineAmountById.put(line.Id, line.Amount__c == null ? 0 : line.Amount__c);
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
      Decimal lineAmount = lineAmountById.containsKey(lineId)
        ? lineAmountById.get(lineId)
        : 0;
      Decimal allPeriodSum = sumPeriodAmounts(periods);
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
      moveLinesToExistingInvoiceBody(
        sourceInvoiceId,
        targetInvoiceId,
        lineIds
      );
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
      throw new InvoiceEditException('移動元請求・移動先請求・明細は必須です。');
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
          PaymentClearingCompletedDate__c
        FROM Invoice__c
        WHERE Id IN :new Set<Id>{ sourceInvoiceId, targetInvoiceId }
        WITH SYSTEM_MODE
      ]
    );
    Invoice__c source = invoicesById.get(sourceInvoiceId);
    Invoice__c target = invoicesById.get(targetInvoiceId);
    if (source == null || target == null) {
      throw new InvoiceEditException('移動元または移動先の請求が見つかりません。');
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

    List<InvoiceLine__c> sourceLines = [
      SELECT
        Id,
        Amount__c,
        ProductName__c,
        Unit__c,
        UnitPrice__c,
        Quantity__c,
        PeriodLabel__c,
        LineMergeKey__c,
        HistoryVersionLabel__c,
        SourcePeriodLineIds__c,
        ContractProduct__c,
        ContractProduct__r.Product__c,
        ContractProduct__r.Unit__c,
        IsManuallyAdjusted__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :sourceInvoiceId AND Id IN :lineIdSet
      WITH SYSTEM_MODE
    ];
    if (sourceLines.size() != lineIdSet.size()) {
      throw new InvoiceEditException('移動対象の明細が見つかりません。');
    }

    Decimal sourceAmountBefore = source.Amount__c == null ? 0 : source.Amount__c;
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
      created.LineMergeKey__c = sourceLine.LineMergeKey__c;
      created.HistoryVersionLabel__c = sourceLine.HistoryVersionLabel__c;
      created.SourcePeriodLineIds__c = sourceLine.SourcePeriodLineIds__c;
      created.ContractProduct__c = sourceLine.ContractProduct__c;
      if (sourceLine.ContractProduct__r != null) {
        created.Product__c = sourceLine.ContractProduct__r.Product__c;
        created.Unit__c = String.isNotBlank(sourceLine.ContractProduct__r.Unit__c)
          ? sourceLine.ContractProduct__r.Unit__c
          : sourceLine.Unit__c;
      } else {
        created.Unit__c = sourceLine.Unit__c;
      }
      created.IsManuallyAdjusted__c = true;
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
        Decimal amount = sourceLine.Amount__c == null ? 0 : sourceLine.Amount__c;
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
      movedPeriodTotal = (sourcePeriodTotal * movedAmount / sourceAmountBefore)
        .setScale(0, RoundingMode.HALF_UP);
      remainPeriodTotal = sourcePeriodTotal - movedPeriodTotal;
    }

    markInvoiceAdjustedAndRecalc(targetInvoiceId);
    Invoice__c targetUpdate = new Invoice__c(
      Id = targetInvoiceId,
      PeriodLineAmountTotal__c = targetPeriodTotalBefore + movedPeriodTotal,
      MergeKey__c = null
    );
    SystemContextAccess.updateRecords(new List<Invoice__c>{ targetUpdate });

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
      markInvoiceAdjustedAndRecalc(sourceInvoiceId);
      Invoice__c sourceUpdate = new Invoice__c(
        Id = sourceInvoiceId,
        PeriodLineAmountTotal__c = remainPeriodTotal,
        MergeKey__c = null
      );
      SystemContextAccess.updateRecords(new List<Invoice__c>{ sourceUpdate });
    }
  }

  /**
   * 請求日分割: 指定明細金額を新請求へ移す（Master-Detail のため付け替えではなく新規作成）。
   * 入金予定日は人が渡した値のみ使用（自動再計算しない）。
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
   * 請求日は元請求を引き継ぎ（必要なら引数で上書き可）。
   * 指定 BA は SnapShot コピー元として参照するだけで、BA マスタ自体は更新しない。
   */
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
    return splitInvoice(
      sourceInvoiceId,
      newInvoiceDate,
      newPaymentScheduledDate,
      newBillingAccountId,
      splitLines,
      false,
      false
    );
  }

  /**
   * 利用期間でわける: 選んだ契約期間明細を新請求へ移し、
   * 残す／移す双方の SourcePeriodLineIds・PeriodLabel・金額を付け替える。
   * 金額の正は請求明細 Amount（現状値）。由来期間の InvoiceProduct 合計との比で按分する。
   * 請求日／BA 金額分割後も同一 SourcePeriodLineIds が残っていて満額合算すると水増しになるため、
   * 期間明細金額をそのまま書き戻さない。
   * newBillingAccountId 指定時は新請求の SnapShot をその BA からコピーする。
   */
  public static Id splitInvoiceByPeriod(
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<Id> movePeriodLineIds
  ) {
    return splitInvoiceByPeriod(
      sourceInvoiceId,
      newInvoiceDate,
      newPaymentScheduledDate,
      movePeriodLineIds,
      null
    );
  }

  public static Id splitInvoiceByPeriod(
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<Id> movePeriodLineIds,
    Id newBillingAccountId
  ) {
    assertCanEditInvoicePreview();
    if (
      sourceInvoiceId == null ||
      newInvoiceDate == null ||
      movePeriodLineIds == null ||
      movePeriodLineIds.isEmpty()
    ) {
      throw new InvoiceEditException('分割元請求・請求日・移す利用期間は必須です。');
    }

    Set<Id> movePeriodIdSet = new Set<Id>();
    for (Id periodId : movePeriodLineIds) {
      if (periodId != null) {
        movePeriodIdSet.add(periodId);
      }
    }
    if (movePeriodIdSet.isEmpty()) {
      throw new InvoiceEditException('移す利用期間を選択してください。');
    }

    List<SplitLineInput> splitLines = buildPeriodSplitInputs(
      sourceInvoiceId,
      movePeriodIdSet,
      null
    );
    if (splitLines.isEmpty()) {
      throw new InvoiceEditException('移動する金額がありません。');
    }

    // 期間明細ベースへ戻す分割なので、手動調整フラグ／端数調整はクリアする
    return splitInvoice(
      sourceInvoiceId,
      newInvoiceDate,
      newPaymentScheduledDate,
      newBillingAccountId,
      splitLines,
      true,
      true
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
    InvoiceProductFieldCopyService.validateActiveDefinitions();
    if (
      sourceInvoiceId == null ||
      splitLines == null ||
      splitLines.isEmpty() ||
      (requireNewInvoiceDate && newInvoiceDate == null)
    ) {
      throw new InvoiceEditException('分割元請求・分割内容は必須です。');
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
        PaymentClearingCompletedDate__c
      FROM Invoice__c
      WHERE Id = :sourceInvoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    InvoiceLockUtil.assertInvoiceEditable(source);
    Decimal sourceAmountBefore = source.Amount__c == null ? 0 : source.Amount__c;
    Decimal sourcePeriodTotal = source.PeriodLineAmountTotal__c == null
      ? sourceAmountBefore
      : source.PeriodLineAmountTotal__c;

    Map<Id, SplitLineInput> inputByLineId = new Map<Id, SplitLineInput>();
    for (SplitLineInput input : splitLines) {
      if (input == null || input.lineId == null || input.moveAmount == null) {
        continue;
      }
      Decimal move = input.moveAmount.setScale(0, RoundingMode.HALF_UP);
      if (move == 0) {
        continue;
      }
      input.moveAmount = move;
      if (input.remainAmount != null) {
        input.remainAmount = input.remainAmount.setScale(0, RoundingMode.HALF_UP);
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
        Unit__c,
        UnitPrice__c,
        Quantity__c,
        PeriodLabel__c,
        LineMergeKey__c,
        HistoryVersionLabel__c,
        SourcePeriodLineIds__c,
        ContractProduct__c,
        ContractProduct__r.Product__c,
        ContractProduct__r.Unit__c
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
    created.PaymentScheduledDate__c = newPaymentScheduledDate == null
      ? source.PaymentScheduledDate__c
      : newPaymentScheduledDate;
    created.TaxPercent__c = source.TaxPercent__c;
    // 調整前請求額は分割後に移す／残すへ再配分する（丸コピーすると偽の端数ギャップになる）
    created.PeriodLineAmountTotal__c = 0;
    created.IsManuallyAdjusted__c = clearManualAdjustment != true;
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
      sourceAmountBefore == 0 && clearManualAdjustment != true;

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
      // 商品参照・単位は作成時の契約商品マスタ。
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
      createdLine.LineMergeKey__c = sourceLine.LineMergeKey__c;
      createdLine.HistoryVersionLabel__c = sourceLine.HistoryVersionLabel__c;
      createdLine.SourcePeriodLineIds__c = input.moveSourcePeriodLineIds != null
        ? input.moveSourcePeriodLineIds
        : sourceLine.SourcePeriodLineIds__c;
      createdLine.ContractProduct__c = sourceLine.ContractProduct__c;
      if (sourceLine.ContractProduct__r != null) {
        createdLine.Product__c = sourceLine.ContractProduct__r.Product__c;
        createdLine.Unit__c = String.isNotBlank(sourceLine.ContractProduct__r.Unit__c)
          ? sourceLine.ContractProduct__r.Unit__c
          : sourceLine.Unit__c;
      } else {
        createdLine.Unit__c = sourceLine.Unit__c;
      }
      createdLine.IsManuallyAdjusted__c = clearManualAdjustment != true;
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
        sourceLine.IsManuallyAdjusted__c = clearManualAdjustment != true;
        if (input.remainSourcePeriodLineIds != null) {
          sourceLine.SourcePeriodLineIds__c = input.remainSourcePeriodLineIds;
        }
        if (input.remainPeriodLabel != null) {
          sourceLine.PeriodLabel__c = input.remainPeriodLabel;
        }
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
      createdPeriodTotal = (sourcePeriodTotal * newInvoiceAmount / sourceAmountBefore)
        .setScale(0, RoundingMode.HALF_UP);
      remainPeriodTotal = sourcePeriodTotal - createdPeriodTotal;
    }

    created.Amount__c = newInvoiceAmount;
    created.PeriodLineAmountTotal__c = createdPeriodTotal;
    created.TaxAmount__c = TaxCalculationUtil.calculateTaxAmount(
      newInvoiceAmount,
      TaxCalculationUtil.fromPercentFieldStorage(created.TaxPercent__c)
    );
    if (clearManualAdjustment == true) {
      created.IsManuallyAdjusted__c = false;
    }
    SystemContextAccess.updateRecords(new List<Invoice__c>{ created });
    if (clearManualAdjustment == true) {
      recalcInvoiceTotals(sourceInvoiceId, false);
    } else {
      markInvoiceAdjustedAndRecalc(sourceInvoiceId);
    }

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
      Invoice__c remainInvoice = new Invoice__c(
        Id = sourceInvoiceId,
        PeriodLineAmountTotal__c = remainPeriodTotal
      );
      SystemContextAccess.updateRecords(new List<Invoice__c>{ remainInvoice });
    }
    return created.Id;
  }

  private static void markInvoiceAdjustedAndRecalc(Id invoiceId) {
    recalcInvoiceTotals(invoiceId, true);
  }

  /**
   * 請求合計を明細から再計算する。
   * markAdjusted=true: 手動調整済にする（端数調整・請求日分割など）。
   * markAdjusted=false: 明細のいずれかに調整があれば親も true、なければ false。
   */
  private static void recalcInvoiceTotals(Id invoiceId, Boolean markAdjusted) {
    if (invoiceId == null) {
      return;
    }
    AggregateResult[] sums = [
      SELECT SUM(Amount__c) amt
      FROM InvoiceLine__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
    ];
    Decimal amountTotal = 0;
    if (!sums.isEmpty() && sums[0].get('amt') != null) {
      amountTotal = (Decimal) sums[0].get('amt');
    }
    Boolean anyLineAdjusted = false;
    if (markAdjusted != true) {
      Integer adjustedCount = [
        SELECT COUNT()
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoiceId AND IsManuallyAdjusted__c = TRUE
        WITH SYSTEM_MODE
      ];
      anyLineAdjusted = adjustedCount > 0;
    }
    Invoice__c invoice = [
      SELECT Id, TaxPercent__c
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
    invoice.IsManuallyAdjusted__c = markAdjusted == true
      ? true
      : anyLineAdjusted;
    SystemContextAccess.updateRecords(new List<Invoice__c>{ invoice });
  }

  private static SplitLineInput normalizeFactorSplitInput(
    SplitLineInput raw,
    InvoiceLine__c sourceLine,
    String mode
  ) {
    Decimal lineAmount = sourceLine.Amount__c == null ? 0 : sourceLine.Amount__c;
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
        : sourceLine.UnitPrice__c.setScale(2, RoundingMode.HALF_UP);
      Decimal movePrice = raw.moveUnitPrice == null
        ? null
        : raw.moveUnitPrice.setScale(2, RoundingMode.HALF_UP);
      Decimal remainPrice = raw.remainUnitPrice == null
        ? null
        : raw.remainUnitPrice.setScale(2, RoundingMode.HALF_UP);
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
      if (moveAmount == 0 || moveAmount == lineAmount) {
        throw new InvoiceEditException(
          '単価分割の結果が全額または0円になります: ' + sourceLine.ProductName__c
        );
      }
      input.moveUnitPrice = movePrice;
      input.remainUnitPrice = remainPrice;
      input.moveAmount = moveAmount;
      input.remainAmount = lineAmount - moveAmount;
      return input;
    }

    if (mode == SPLIT_MODE_QUANTITY) {
      Decimal original = sourceLine.Quantity__c == null
        ? 0
        : sourceLine.Quantity__c.setScale(2, RoundingMode.HALF_UP);
      Decimal moveQty = raw.moveQuantity == null
        ? null
        : raw.moveQuantity.setScale(2, RoundingMode.HALF_UP);
      Decimal remainQty = raw.remainQuantity == null
        ? null
        : raw.remainQuantity.setScale(2, RoundingMode.HALF_UP);
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
      if (moveAmount == 0 || moveAmount == lineAmount) {
        throw new InvoiceEditException(
          '個数分割の結果が全額または0円になります: ' + sourceLine.ProductName__c
        );
      }
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
      if (
        restrictLineIds != null &&
        !restrictLineIds.contains(line.Id)
      ) {
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
      if (
        restrictLineIds != null &&
        !restrictLineIds.contains(line.Id)
      ) {
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
    return (lineAmount * movePeriodSum / allPeriodSum)
      .setScale(0, RoundingMode.HALF_UP);
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
      String suffix = String.isNotBlank(productName) ? (': ' + productName) : '';
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
    return (baseline * movedAbs / denom).setScale(0, RoundingMode.HALF_UP);
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
      'TaxPercent__c',
      'ContractProduct__c',
      'ContractProduct__r.Product__c',
      'ContractProduct__r.Product__r.Name',
      'ContractProduct__r.Product__r.BillingType__c',
      'ContractProduct__r.Unit__c',
      'ContractProduct__r.BillingType__c',
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
      'PaymentTerm__c',
      'BillingDayOfMonth__c'
    };
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
   * 必須の BA SnapShot（Id・宛名・メール・支払条件・請求日）をコードで埋める。
   * Insert トリガ側と同じ空欄埋め（手入力の非空は尊重）。
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

  private static BillingAccount__c loadBillingAccountForSnapshot(Id billingAccountId) {
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
        PaymentTerm__c,
        BillingDayOfMonth__c
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

}
