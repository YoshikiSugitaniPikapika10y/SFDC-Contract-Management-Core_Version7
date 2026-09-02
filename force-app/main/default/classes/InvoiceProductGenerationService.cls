/**
 * 受注（Ordered）契約履歴から請求明細（InvoiceProduct__c）を生成する。
 * New / Change / Renew / Cancel ごとの行展開ルールをここで集約する。
 */
public without sharing class InvoiceProductGenerationService {
  private static final String BILLING_TYPE_RECURRING = ContractDomainConstants.BILLING_TYPE_RECURRING;
  private static final String PRODUCT_TYPE_ORIGINAL = ContractDomainConstants.PRODUCT_TYPE_ORIGINAL;
  private static final String PRODUCT_TYPE_REMAKE = ContractDomainConstants.PRODUCT_TYPE_REMAKE;
  private static final String LEGACY_PRODUCT_TYPE_DERIVATIVE = ContractDomainConstants.LEGACY_PRODUCT_TYPE_DERIVATIVE;
  private static final String HISTORY_TYPE_CHANGE = ContractDomainConstants.HISTORY_TYPE_CHANGE;
  private static final String HISTORY_TYPE_NEW = ContractDomainConstants.HISTORY_TYPE_NEW;
  private static final String HISTORY_TYPE_RENEW = ContractDomainConstants.HISTORY_TYPE_RENEW;
  private static final String HISTORY_TYPE_CANCEL = ContractDomainConstants.HISTORY_TYPE_CANCEL;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;
  private static Map<Id, HistoryGenerationContext> cachedHistoryGenerationContextById = new Map<Id, HistoryGenerationContext>();
  private static Map<Id, ContractHistory__c> cachedHistoriesForFieldCopy = new Map<Id, ContractHistory__c>();
  private static Map<Id, BillingAccount__c> cachedBillingAccountsById = new Map<Id, BillingAccount__c>();
  private static Map<Id, List<ContractProduct__c>> cachedContractProductsByHistoryId = new Map<Id, List<ContractProduct__c>>();

  private class InvoiceGenerationContext {
    public String historyType;
    public Date effectiveDate;
  }

  private class HistoryBillingContext {
    public Decimal taxPercent;
    public BillingAccount__c billingAccount;
    public ContractHistory__c contractHistory;
    public Opportunity opportunity;
    public Account account;
  }

  private class HistoryGenerationContext {
    public Id historyId;
    public Id contractServiceId;
    public Decimal version;
    public String historyType;
    public Date effectiveDate;
  }

  private class MergeKeyDraft {
    public String mergeKey;
    public Decimal amount = 0;
    public InvoiceProduct__c template;
    public Id contractProductId;
  }

  private class DraftInvoiceLine {
    public Id productId;
    public ContractProduct__c contractProduct;
    public InvoiceProduct__c invoiceProduct;

    public DraftInvoiceLine(
      Id productId,
      ContractProduct__c contractProduct,
      InvoiceProduct__c invoiceProduct
    ) {
      this.productId = productId;
      this.contractProduct = contractProduct;
      this.invoiceProduct = invoiceProduct;
    }
  }

  /** 仕様: Core 第6.1節、第7.6節、第7.7.2節 */
  public static void generateForHistories(Set<Id> contractHistoryIds) {
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return;
    }
    ContractArrCalculationService.beginRecalcDefer();
    ContractHistoryStatusPathService.beginPathSyncDefer();
    BillingAccountKeyService.beginReferenceRefreshDefer();
    ContractServiceLifecycleService.beginLifecycleDefer();
    try {
      generateForHistoriesBody(contractHistoryIds);
    } finally {
      ContractServiceLifecycleService.endLifecycleDefer();
      BillingAccountKeyService.endReferenceRefreshDefer();
      ContractHistoryStatusPathService.endPathSyncDefer();
      ContractArrCalculationService.endRecalcDefer();
    }
  }

  private static void generateForHistoriesBody(Set<Id> contractHistoryIds) {
    // 期間明細・請求は Ordered のみ（Estimate / Archive には作らない）
    InvoiceCanonicalService.assertHistoriesAreOrdered(contractHistoryIds);

    // 不正なコピー定義があると受注 DML 全体をロールバックする
    // 仕様: Core 第11.4.2節
    FieldCopyDefinitionService.validateAllDefinitions();
    InvoiceMergeKeyConfigService.validateActiveDefinitions();

    // Version 単位: 請求書ロック1件でもあれば全体エラー。なければ全削除して全作り直し。
    InvoiceLockUtil.assertNoLockedInvoices(contractHistoryIds);

    Map<Id, HistoryGenerationContext> historyContextById = loadHistoryGenerationContextById(
      contractHistoryIds
    );
    Set<Id> generateHistoryIds = new Set<Id>();
    for (Id historyId : contractHistoryIds) {
      HistoryGenerationContext historyContext = historyContextById.get(
        historyId
      );
      if (
        historyContext != null &&
        historyContext.historyType != HISTORY_TYPE_CANCEL
      ) {
        generateHistoryIds.add(historyId);
      }
    }
    // Cancel は期間明細・請求を新規生成しない（孤児掃除の削除＋空 rebuild のみ）
    if (generateHistoryIds.isEmpty()) {
      InvoiceCanonicalService.rebuildForHistories(contractHistoryIds);
      return;
    }

    Map<Id, HistoryBillingContext> billingContextByHistoryId = loadHistoryBillingContextByHistoryId(
      generateHistoryIds
    );

    List<ContractProduct__c> contractProducts = queryContractProductsForGeneration(
      generateHistoryIds
    );
    // Change は見積保存と同じカバー／有効日ルールを再検証（画面外データ対策）。
    // 仕様: Core 第6.1節。生成用見積商品照会を再利用し、Trigger 配下と二重に取らない。
    EstimateValidationService.assertChangeHistoriesReadyForInvoice(
      contractHistoryIds,
      cachedContractProductsByHistoryId
    );
    deleteAllInvoiceProducts(contractHistoryIds);

    Map<Id, List<ContractProduct__c>> contractProductsByHistoryId = new Map<Id, List<ContractProduct__c>>();
    for (ContractProduct__c contractProduct : contractProducts) {
      HistoryGenerationContext productHistoryContext = historyContextById.get(
        contractProduct.ContractHistory__c
      );
      ensureInvoiceAnchorFields(contractProduct, productHistoryContext);
      if (
        !contractProductsByHistoryId.containsKey(
          contractProduct.ContractHistory__c
        )
      ) {
        contractProductsByHistoryId.put(
          contractProduct.ContractHistory__c,
          new List<ContractProduct__c>()
        );
      }
      contractProductsByHistoryId.get(contractProduct.ContractHistory__c)
        .add(contractProduct);
    }

    List<InvoiceProduct__c> invoiceProductsToInsert = new List<InvoiceProduct__c>();

    for (Id historyId : generateHistoryIds) {
      HistoryGenerationContext historyContext = historyContextById.get(
        historyId
      );
      if (historyContext == null) {
        continue;
      }

      List<ContractProduct__c> historyProducts = contractProductsByHistoryId.get(
        historyId
      );
      if (historyProducts == null) {
        historyProducts = new List<ContractProduct__c>();
      }

      Map<String, MergeKeyDraft> shouldHaveByMergeKey = aggregateShouldHaveByMergeKey(
        historyContext,
        historyProducts,
        billingContextByHistoryId.get(historyId)
      );

      if (historyContext.historyType == HISTORY_TYPE_CHANGE) {
        PastPeriodKeyContext pastContext = loadPastPeriodKeyContext(
          historyContext.contractServiceId,
          historyContext.version
        );
        invoiceProductsToInsert.addAll(
          buildChangeInvoiceProducts(
            historyId,
            historyProducts,
            shouldHaveByMergeKey,
            pastContext.cumulativeByPeriodKey,
            pastContext.sampleByPeriodKey,
            billingContextByHistoryId.get(historyId),
            historyContext
          )
        );
      } else {
        invoiceProductsToInsert.addAll(
          buildShouldHaveInvoiceProducts(
            historyId,
            historyProducts,
            shouldHaveByMergeKey,
            billingContextByHistoryId.get(historyId)
          )
        );
      }
    }

    if (!invoiceProductsToInsert.isEmpty()) {
      SystemContextAccess.insertRecords(invoiceProductsToInsert);
    }
    // 契約期間明細を集約し、請求／請求明細正本を生成する（Cancel 含む全 ID で空 rebuild）
    InvoiceCanonicalService.rebuildForHistories(contractHistoryIds);
  }

  private static Map<Id, HistoryGenerationContext> loadHistoryGenerationContextById(
    Set<Id> contractHistoryIds
  ) {
    Map<Id, HistoryGenerationContext> contextByHistoryId = new Map<Id, HistoryGenerationContext>();
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return contextByHistoryId;
    }
    Set<Id> missingIds = new Set<Id>();
    for (Id historyId : contractHistoryIds) {
      if (cachedHistoryGenerationContextById.containsKey(historyId)) {
        contextByHistoryId.put(
          historyId,
          cachedHistoryGenerationContextById.get(historyId)
        );
      } else {
        missingIds.add(historyId);
      }
    }
    if (missingIds.isEmpty()) {
      return contextByHistoryId;
    }
    for (ContractHistory__c history : queryContractHistoriesForFieldCopy(missingIds)) {
      HistoryGenerationContext context = new HistoryGenerationContext();
      context.historyId = history.Id;
      context.contractServiceId = history.ContractService__c;
      context.version = history.Version__c;
      context.historyType = history.Type__c;
      context.effectiveDate = history.EffectiveDate__c;
      cachedHistoryGenerationContextById.put(history.Id, context);
      contextByHistoryId.put(history.Id, context);
    }
    return contextByHistoryId;
  }

  private static Map<String, MergeKeyDraft> aggregateShouldHaveByMergeKey(
    HistoryGenerationContext historyContext,
    List<ContractProduct__c> contractProducts,
    HistoryBillingContext billingContext
  ) {
    List<DraftInvoiceLine> draftLines = new List<DraftInvoiceLine>();
    if (historyContext.historyType == HISTORY_TYPE_CHANGE) {
      draftLines.addAll(
        buildChangeShouldHaveDraftLines(
          historyContext,
          contractProducts,
          billingContext
        )
      );
      InvoiceGenerationContext generationContext = new InvoiceGenerationContext();
      generationContext.historyType = historyContext.historyType;
      generationContext.effectiveDate = historyContext.effectiveDate;
      for (ContractProduct__c contractProduct : contractProducts) {
        if (!isChangeStandaloneContractProduct(contractProduct)) {
          continue;
        }
        draftLines.addAll(
          buildInvoiceProductDrafts(
            contractProduct,
            billingContext,
            generationContext
          )
        );
      }
    } else {
      InvoiceGenerationContext generationContext = new InvoiceGenerationContext();
      generationContext.historyType = historyContext.historyType;
      generationContext.effectiveDate = historyContext.effectiveDate;
      for (ContractProduct__c contractProduct : contractProducts) {
        if (isOriginalProductType(contractProduct)) {
          continue;
        }
        draftLines.addAll(
          buildInvoiceProductDrafts(
            contractProduct,
            billingContext,
            generationContext
          )
        );
      }
    }

    Map<String, MergeKeyDraft> shouldHaveByMergeKey = new Map<String, MergeKeyDraft>();
    for (DraftInvoiceLine draftLine : draftLines) {
      if (
        draftLine.productId == null ||
        draftLine.invoiceProduct == null ||
        draftLine.contractProduct == null
      ) {
        continue;
      }

      String mergeKey = InvoiceProductMergeKeyUtil.buildMergeKey(
        historyContext.contractServiceId,
        draftLine.productId,
        draftLine.invoiceProduct.StartDate__c,
        draftLine.invoiceProduct.Enddate__c,
        draftLine.contractProduct.Quantity__c,
        draftLine.contractProduct.UnitPrice__c,
        draftLine.contractProduct.Unit__c
      );
      if (String.isBlank(mergeKey)) {
        continue;
      }
      if (draftLine.contractProduct.Id == null) {
        throw new InvoiceProductGenerationException(
          '請求商品の見積商品を特定できません。見積商品Idがありません。'
        );
      }

      Decimal draftAmount = draftLine.invoiceProduct.Amount__c == null
        ? 0
        : draftLine.invoiceProduct.Amount__c;
      MergeKeyDraft aggregate = shouldHaveByMergeKey.get(mergeKey);
      if (aggregate == null) {
        aggregate = new MergeKeyDraft();
        aggregate.mergeKey = mergeKey;
        aggregate.template = cloneInvoiceProduct(draftLine.invoiceProduct);
        aggregate.contractProductId = draftLine.contractProduct.Id;
        if (aggregate.template != null) {
          aggregate.template.ContractProduct__c = draftLine.contractProduct.Id;
        }
        shouldHaveByMergeKey.put(mergeKey, aggregate);
      } else if (
        aggregate.contractProductId != null &&
        draftLine.contractProduct.Id != null &&
        aggregate.contractProductId != draftLine.contractProduct.Id
      ) {
        throw new InvoiceProductGenerationException(
          '請求商品の集約で見積商品が衝突しました。同一期間・同一条件に複数の見積商品が割り当てられています。'
        );
      }
      aggregate.amount += draftAmount;
      aggregate.template.Amount__c = aggregate.amount;
    }
    return shouldHaveByMergeKey;
  }

  private static List<DraftInvoiceLine> buildChangeShouldHaveDraftLines(
    HistoryGenerationContext historyContext,
    List<ContractProduct__c> contractProducts,
    HistoryBillingContext billingContext
  ) {
    // Original/Remake は Product2 ではなく前回見積商品（系統）単位で組む。
    // 同一商品が期間分割されている Change でも系統が混線しないようにする。
    Map<Id, List<ContractProduct__c>> contractProductsByLineageId = groupChangeContractProductsByLineage(
      contractProducts
    );
    List<DraftInvoiceLine> draftLines = new List<DraftInvoiceLine>();

    for (Id lineageId : contractProductsByLineageId.keySet()) {
      List<ContractProduct__c> rows = contractProductsByLineageId.get(
        lineageId
      );
      ContractProduct__c originalRow = null;
      List<ContractProduct__c> remakeRows = new List<ContractProduct__c>();
      for (ContractProduct__c row : rows) {
        if (isOriginalProductType(row)) {
          originalRow = row;
        } else if (isRemakeAfterProductType(row.Type__c)) {
          remakeRows.add(row);
        }
      }
      remakeRows.sort(new ContractProductStartDateComparator());

      // Remake なし（据え置き）: Original を Change 解釈なしでそのまま出す。
      if (remakeRows.isEmpty()) {
        if (originalRow != null) {
          draftLines.addAll(
            buildUnchangedLineageDraftLines(originalRow, null, billingContext)
          );
        }
        continue;
      }

      // Remake ありでも課金イベントなし（内容同一の据え置き）:
      // 有効日で月次グリッドを切り直すと period key が過去とずれ、偽差分が出る。
      // 明細開始日起点の月次のまま Remake 全期間を出す（一回課金 New 追加のみの Change 等）。
      if (
        originalRow != null &&
        !ChangeBillingEventUtil.lineageHasBillingEvent(originalRow, remakeRows)
      ) {
        draftLines.addAll(
          buildUnchangedLineageDraftLines(null, remakeRows, billingContext)
        );
        continue;
      }

      // Remake に課金イベントあり: 有効日前 = Original、有効日以降 = Remake。
      // 月次グリッドは明細開始日起点を維持し、開始は請求期間境界へスナップする。
      draftLines.addAll(
        buildChangeOriginalAndRemakeDraftLines(
          originalRow,
          remakeRows,
          historyContext,
          billingContext
        )
      );
    }
    return draftLines;
  }

  /**
   * 据え置き系統の should-have。Change 有効日は期間分割に使わない。
   */
  private static List<DraftInvoiceLine> buildUnchangedLineageDraftLines(
    ContractProduct__c originalRow,
    List<ContractProduct__c> remakeRows,
    HistoryBillingContext billingContext
  ) {
    InvoiceGenerationContext unchangedContext = new InvoiceGenerationContext();
    unchangedContext.historyType = null;
    unchangedContext.effectiveDate = null;
    List<DraftInvoiceLine> draftLines = new List<DraftInvoiceLine>();
    if (remakeRows != null && !remakeRows.isEmpty()) {
      for (ContractProduct__c remakeRow : remakeRows) {
        draftLines.addAll(
          buildInvoiceProductDrafts(remakeRow, billingContext, unchangedContext)
        );
      }
      return draftLines;
    }
    if (originalRow != null) {
      draftLines.addAll(
        buildInvoiceProductDrafts(originalRow, billingContext, unchangedContext)
      );
    }
    return draftLines;
  }

  /**
   * Change 系統で生成されるべき請求明細（期待行）。
   * Remake 本数に依存せず、単一 Remake と同じ思想で組む。
   */
  private static List<DraftInvoiceLine> buildChangeOriginalAndRemakeDraftLines(
    ContractProduct__c originalRow,
    List<ContractProduct__c> remakeRows,
    HistoryGenerationContext historyContext,
    HistoryBillingContext billingContext
  ) {
    List<DraftInvoiceLine> draftLines = new List<DraftInvoiceLine>();
    Date effectiveDate = historyContext == null
      ? null
      : historyContext.effectiveDate;

    if (originalRow != null && effectiveDate != null) {
      Date preEffectiveEndDate = effectiveDate.addDays(-1);
      if (
        originalRow.StartDate__c != null &&
        preEffectiveEndDate >= originalRow.StartDate__c
      ) {
        ContractProduct__c preEffectiveProduct = cloneContractProductForPeriod(
          originalRow,
          originalRow.StartDate__c,
          preEffectiveEndDate < originalRow.Enddate__c
            ? preEffectiveEndDate
            : originalRow.Enddate__c
        );
        // Change × 一括前払は有効日を請求基準日にする（表 Step2）。
        InvoiceGenerationContext preContext = new InvoiceGenerationContext();
        preContext.historyType = HISTORY_TYPE_CHANGE;
        preContext.effectiveDate = effectiveDate;
        draftLines.addAll(
          buildInvoiceProductDrafts(
            preEffectiveProduct,
            billingContext,
            preContext
          )
        );
      }
    }

    for (ContractProduct__c remakeRow : remakeRows) {
      Boolean remakeEndsBeforeEffective =
        effectiveDate != null &&
        remakeRow.Enddate__c != null &&
        remakeRow.Enddate__c < effectiveDate;

      // 有効日前で終わる Remake は Original 前半で賄う（二重防止）。
      if (remakeEndsBeforeEffective && originalRow != null) {
        continue;
      }

      InvoiceGenerationContext postContext = resolveChangeRemakeGenerationContext(
        remakeRow,
        effectiveDate
      );
      draftLines.addAll(
        buildInvoiceProductDrafts(remakeRow, billingContext, postContext)
      );
    }
    return draftLines;
  }

  private static InvoiceGenerationContext resolveChangeRemakeGenerationContext(
    ContractProduct__c remakeRow,
    Date effectiveDate
  ) {
    InvoiceGenerationContext context = new InvoiceGenerationContext();
    if (effectiveDate == null) {
      context.historyType = null;
      context.effectiveDate = null;
      return context;
    }
    // 有効日前で終わる Remake も Change × 一括前払なら請求基準日は有効日（表 Step2）。
    context.historyType = HISTORY_TYPE_CHANGE;
    context.effectiveDate = effectiveDate;
    return context;
  }

  private class ContractProductStartDateComparator implements Comparator<ContractProduct__c> {
    public Integer compare(ContractProduct__c left, ContractProduct__c right) {
      String leftStart = left == null ||
        left.StartDate__c == null
        ? ''
        : String.valueOf(left.StartDate__c);
      String rightStart = right == null ||
        right.StartDate__c == null
        ? ''
        : String.valueOf(right.StartDate__c);
      return leftStart.compareTo(rightStart);
    }
  }

  private static Map<Id, List<ContractProduct__c>> groupChangeContractProductsByLineage(
    List<ContractProduct__c> contractProducts
  ) {
    Map<Id, List<ContractProduct__c>> contractProductsByLineageId = new Map<Id, List<ContractProduct__c>>();
    for (ContractProduct__c contractProduct : contractProducts) {
      if (contractProduct == null) {
        continue;
      }
      if (
        !isOriginalProductType(contractProduct) &&
        !isRemakeAfterProductType(contractProduct.Type__c)
      ) {
        continue;
      }
      Id lineageId = contractProduct.PreviousContractProduct__c;
      if (lineageId == null) {
        lineageId = contractProduct.Id;
      }
      if (lineageId == null) {
        continue;
      }
      if (!contractProductsByLineageId.containsKey(lineageId)) {
        contractProductsByLineageId.put(
          lineageId,
          new List<ContractProduct__c>()
        );
      }
      contractProductsByLineageId.get(lineageId).add(contractProduct);
    }
    return contractProductsByLineageId;
  }

  private static ContractProduct__c cloneContractProductForPeriod(
    ContractProduct__c source,
    Date startDate,
    Date endDate
  ) {
    // Id を残し、請求明細が Original 見積商品へ帰属できるようにする。
    ContractProduct__c clone = source.clone(true, true, false, false);
    clone.StartDate__c = startDate;
    clone.Enddate__c = endDate;
    return clone;
  }

  private class PastPeriodKeyContext {
    public Map<String, Decimal> cumulativeByPeriodKey = new Map<String, Decimal>();
    public Map<String, InvoiceProduct__c> sampleByPeriodKey = new Map<String, InvoiceProduct__c>();
  }

  /** Change past 累計と打消しサンプルを1クエリで構築する */
  private static PastPeriodKeyContext loadPastPeriodKeyContext(
    Id contractServiceId,
    Decimal currentVersion
  ) {
    PastPeriodKeyContext context = new PastPeriodKeyContext();
    if (contractServiceId == null || currentVersion == null) {
      return context;
    }

    for (
      InvoiceProduct__c invoiceProduct : queryPastOrderedInvoiceProducts(
        contractServiceId,
        currentVersion
      )
    ) {
      String periodKey = InvoiceProductMergeKeyUtil.buildPeriodKey(
        invoiceProduct.ContractHistory__r.ContractService__c,
        invoiceProduct.ContractProduct__r.Product__c,
        invoiceProduct.StartDate__c,
        invoiceProduct.Enddate__c
      );
      if (String.isBlank(periodKey)) {
        continue;
      }
      Decimal amount = invoiceProduct.Amount__c == null
        ? 0
        : invoiceProduct.Amount__c;
      Decimal existing = context.cumulativeByPeriodKey.containsKey(periodKey)
        ? context.cumulativeByPeriodKey.get(periodKey)
        : 0;
      context.cumulativeByPeriodKey.put(periodKey, existing + amount);
      // サンプルは正金額（計上行）を優先。同符号なら先勝ち（新しい Version を維持）。
      // 打消し行が先に来ると Change 連続で Original 紐づけが外れるため。
      if (!context.sampleByPeriodKey.containsKey(periodKey)) {
        context.sampleByPeriodKey.put(periodKey, invoiceProduct);
      } else if (
        isPreferredPastSample(
          invoiceProduct,
          context.sampleByPeriodKey.get(periodKey)
        )
      ) {
        context.sampleByPeriodKey.put(periodKey, invoiceProduct);
      }
    }
    return context;
  }

  /**
   * past サンプル選定: 正金額を非正より優先。同符号なら既存（新しい Version）を維持。
   */
  @TestVisible
  private static Boolean isPreferredPastSample(
    InvoiceProduct__c candidate,
    InvoiceProduct__c existing
  ) {
    if (candidate == null || existing == null) {
      return false;
    }
    Decimal candidateAmount = candidate.Amount__c == null
      ? 0
      : candidate.Amount__c;
    Decimal existingAmount = existing.Amount__c == null
      ? 0
      : existing.Amount__c;
    return candidateAmount > 0 && existingAmount <= 0;
  }

  private static List<InvoiceProduct__c> buildChangeInvoiceProducts(
    Id historyId,
    List<ContractProduct__c> historyProducts,
    Map<String, MergeKeyDraft> shouldHaveByMergeKey,
    Map<String, Decimal> pastCumulativeByPeriodKey,
    Map<String, InvoiceProduct__c> pastSampleByPeriodKey,
    HistoryBillingContext billingContext,
    HistoryGenerationContext historyContext
  ) {
    List<InvoiceProduct__c> invoiceProducts = new List<InvoiceProduct__c>();
    Map<String, Decimal> shouldHaveAmountByPeriodKey = new Map<String, Decimal>();
    Map<String, MergeKeyDraft> chargeDraftByPeriodKey = new Map<String, MergeKeyDraft>();

    for (String mergeKey : shouldHaveByMergeKey.keySet()) {
      String periodKey = InvoiceProductMergeKeyUtil.extractPeriodKey(mergeKey);
      if (String.isBlank(periodKey)) {
        continue;
      }
      MergeKeyDraft draft = shouldHaveByMergeKey.get(mergeKey);
      Decimal existingAmount = shouldHaveAmountByPeriodKey.containsKey(
          periodKey
        )
        ? shouldHaveAmountByPeriodKey.get(periodKey)
        : 0;
      shouldHaveAmountByPeriodKey.put(periodKey, existingAmount + draft.amount);
      MergeKeyDraft existingDraft = chargeDraftByPeriodKey.get(periodKey);
      if (existingDraft == null || draft.amount > existingDraft.amount) {
        chargeDraftByPeriodKey.put(periodKey, draft);
      }
    }

    Set<String> allPeriodKeys = new Set<String>();
    allPeriodKeys.addAll(shouldHaveAmountByPeriodKey.keySet());
    allPeriodKeys.addAll(pastCumulativeByPeriodKey.keySet());

    for (String periodKey : allPeriodKeys) {
      Decimal shouldHaveAmount = shouldHaveAmountByPeriodKey.containsKey(
          periodKey
        )
        ? shouldHaveAmountByPeriodKey.get(periodKey)
        : 0;
      Decimal pastAmount = pastCumulativeByPeriodKey.containsKey(periodKey)
        ? pastCumulativeByPeriodKey.get(periodKey)
        : 0;
      if (shouldHaveAmount == pastAmount) {
        continue;
      }

      Id productId = extractProductIdFromPeriodKey(periodKey);
      InvoiceProduct__c pastSample = pastSampleByPeriodKey.get(periodKey);
      InvoiceProduct__c chargeLine = null;

      if (shouldHaveAmount != 0) {
        MergeKeyDraft chargeDraft = chargeDraftByPeriodKey.get(periodKey);
        if (chargeDraft != null && chargeDraft.template != null) {
          Id chargeContractProductId = requireContractProductId(chargeDraft);
          ContractProduct__c chargeContractProduct = findContractProductById(
            historyProducts,
            chargeContractProductId
          );
          if (chargeContractProduct == null) {
            throw new InvoiceProductGenerationException(
              '請求商品の見積商品が見つかりません: ' +
              String.valueOf(chargeContractProductId)
            );
          }
          chargeLine = buildExplicitInvoiceProduct(
            chargeDraft.template,
            historyId,
            chargeContractProduct,
            shouldHaveAmount,
            billingContext
          );
        }
      }

      // past ≠ 0 の継続課金差分は打消し必須。作れない場合は黙殺せず Fail closed
      //（プラスだけ残して過大請求になるのを防ぐ。正規操作では稀で不整合データ向け）
      if (
        pastAmount != 0 &&
        !isOneTimeBillingForPeriod(historyProducts, productId, pastSample)
      ) {
        if (pastSample == null) {
          throw new InvoiceProductGenerationException(
            'Change の打消し行を作成できません（過去の契約期間明細サンプルがありません）: ' +
            periodKey
          );
        }
        Id reversalContractProductId = resolveReversalContractProductId(
          historyProducts,
          productId,
          pastSample
        );
        ContractProduct__c reversalContractProduct = findContractProductById(
          historyProducts,
          reversalContractProductId
        );
        if (reversalContractProduct == null) {
          throw new InvoiceProductGenerationException(
            'Change の打消し行を Original に紐づけられませんでした。' +
              '過去の数量・単価と一致する Original 行があるか確認してください: ' +
              periodKey
          );
        }
        InvoiceProduct__c reversalLine = buildExplicitInvoiceProduct(
          pastSample,
          historyId,
          reversalContractProduct,
          -pastAmount,
          billingContext
        );
        // プラス行コピーはしない。減額側も請求設定ルートで再計算する（§6.7）。
        applyChangeReversalInvoiceDates(
          reversalLine,
          reversalContractProduct,
          historyContext,
          billingContext
        );
        invoiceProducts.add(reversalLine);
      }

      if (chargeLine != null) {
        invoiceProducts.add(chargeLine);
      }
    }
    return invoiceProducts;
  }

  /**
   * Change マイナス行の請求日・入金予定日を、保存済み請求基準日から再計算する。
   */
  private static void applyChangeReversalInvoiceDates(
    InvoiceProduct__c invoiceProduct,
    ContractProduct__c contractProduct,
    HistoryGenerationContext historyContext,
    HistoryBillingContext billingContext
  ) {
    if (invoiceProduct == null || contractProduct == null) {
      return;
    }

    Boolean usesBulkInvoiceDate = ContractMetadataService.usesBulkContractProductInvoiceDate(
      contractProduct.InvoiceSetting__c
    );
    Date rowAnchor = usesBulkInvoiceDate
      ? contractProduct.InvoiceAnchorDate__c
      : invoiceProduct.StartDate__c;
    Date invoiceDate = computeGeneratedInvoiceDate(billingContext, rowAnchor);
    applyMergeBucketKeys(
      invoiceProduct,
      contractProduct,
      billingContext,
      invoiceDate
    );
  }

  private static InvoiceGenerationContext buildInvoiceGenerationContext(
    HistoryGenerationContext historyContext
  ) {
    InvoiceGenerationContext context = new InvoiceGenerationContext();
    if (historyContext == null) {
      return context;
    }
    context.historyType = historyContext.historyType;
    context.effectiveDate = historyContext.effectiveDate;
    return context;
  }

  /** 仕様: Core 第7.2節、日付仕様 第4章 */
  private static Date computeGeneratedInvoiceDate(
    HistoryBillingContext billingContext,
    Date anchorDate
  ) {
    if (billingContext == null || billingContext.billingAccount == null) {
      throw new BillingScheduleService.ScheduleException(
        '請求アカウントが指定されていません。'
      );
    }
    return BillingScheduleService.computeInvoiceDateFromAnchor(
      billingContext.billingAccount,
      anchorDate
    );
  }

  private static ContractProduct__c findContractProductById(
    List<ContractProduct__c> historyProducts,
    Id contractProductId
  ) {
    if (historyProducts == null || contractProductId == null) {
      return null;
    }
    for (ContractProduct__c contractProduct : historyProducts) {
      if (contractProduct.Id == contractProductId) {
        return contractProduct;
      }
    }
    return null;
  }

  private static Decimal resolvePastQuantity(InvoiceProduct__c pastSample) {
    if (pastSample == null) {
      return 0;
    }
    if (pastSample.Quantity__c != null) {
      return pastSample.Quantity__c;
    }
    return pastSample.ContractProduct__r == null
      ? 0
      : pastSample.ContractProduct__r.Quantity__c;
  }

  private static Decimal resolvePastUnitPrice(InvoiceProduct__c pastSample) {
    if (pastSample == null) {
      return 0;
    }
    if (pastSample.UnitPrice__c != null) {
      return pastSample.UnitPrice__c;
    }
    return pastSample.ContractProduct__r == null
      ? 0
      : pastSample.ContractProduct__r.UnitPrice__c;
  }

  private static Id resolveReversalContractProductId(
    List<ContractProduct__c> historyProducts,
    Id productId,
    InvoiceProduct__c pastSample
  ) {
    if (historyProducts == null || productId == null || pastSample == null) {
      return null;
    }

    Decimal pastQuantity = resolvePastQuantity(pastSample);
    Decimal pastUnitPrice = resolvePastUnitPrice(pastSample);
    Id pastContractProductId = pastSample.ContractProduct__c;

    Id fallbackId = null;
    for (ContractProduct__c contractProduct : historyProducts) {
      if (contractProduct.Product__c != productId) {
        continue;
      }
      if (
        !isOriginalProductType(contractProduct) ||
        contractProduct.Quantity__c != pastQuantity ||
        contractProduct.UnitPrice__c != pastUnitPrice
      ) {
        continue;
      }
      // 過去請求の見積商品と PreviousContractProduct が一致する Original を優先
      if (
        pastContractProductId != null &&
        contractProduct.PreviousContractProduct__c == pastContractProductId
      ) {
        return contractProduct.Id;
      }
      if (fallbackId == null) {
        fallbackId = contractProduct.Id;
      }
    }
    return fallbackId;
  }

  private static Id extractProductIdFromPeriodKey(String periodKey) {
    if (String.isBlank(periodKey)) {
      return null;
    }
    List<String> parts = periodKey.split('_');
    if (parts.size() < 2) {
      return null;
    }
    return (Id) parts[1];
  }

  private static InvoiceProduct__c buildExplicitInvoiceProduct(
    InvoiceProduct__c template,
    Id contractHistoryId,
    ContractProduct__c contractProduct,
    Decimal amount,
    HistoryBillingContext billingContext
  ) {
    InvoiceProduct__c invoiceProduct = cloneInvoiceProduct(template);
    invoiceProduct.ContractHistory__c = contractHistoryId;
    invoiceProduct.ContractProduct__c = contractProduct == null
      ? null
      : contractProduct.Id;
    invoiceProduct.Amount__c = amount;
    applyCorePeriodLineFields(invoiceProduct, contractProduct, billingContext);
    applyConfiguredFieldCopies(invoiceProduct, contractProduct, billingContext);
    return invoiceProduct;
  }

  private static InvoiceProduct__c resolveDiffTemplate(
    String mergeKey,
    Decimal diffAmount,
    Map<String, MergeKeyDraft> shouldHaveByMergeKey,
    Map<String, InvoiceProduct__c> pastSampleByMergeKey
  ) {
    if (shouldHaveByMergeKey.containsKey(mergeKey)) {
      return shouldHaveByMergeKey.get(mergeKey).template;
    }
    if (pastSampleByMergeKey.containsKey(mergeKey)) {
      return pastSampleByMergeKey.get(mergeKey);
    }
    if (diffAmount < 0) {
      for (InvoiceProduct__c pastSample : pastSampleByMergeKey.values()) {
        return pastSample;
      }
    }
    return null;
  }

  private static Id requireContractProductId(MergeKeyDraft draft) {
    if (draft == null) {
      throw new InvoiceProductGenerationException(
        '請求商品の見積商品を特定できません。'
      );
    }
    Id contractProductId = draft.contractProductId;
    if (
      contractProductId == null &&
      draft.template != null &&
      draft.template.ContractProduct__c != null
    ) {
      contractProductId = draft.template.ContractProduct__c;
    }
    if (contractProductId == null) {
      throw new InvoiceProductGenerationException(
        '請求商品の見積商品を特定できません。生成データを確認してください。'
      );
    }
    return contractProductId;
  }

  private static Id extractProductIdFromMergeKey(String mergeKey) {
    if (String.isBlank(mergeKey)) {
      return null;
    }
    List<String> parts = mergeKey.split('_');
    if (parts.size() < 2) {
      return null;
    }
    return (Id) parts[1];
  }

  private static List<InvoiceProduct__c> buildShouldHaveInvoiceProducts(
    Id historyId,
    List<ContractProduct__c> historyProducts,
    Map<String, MergeKeyDraft> shouldHaveByMergeKey,
    HistoryBillingContext billingContext
  ) {
    List<InvoiceProduct__c> invoiceProducts = new List<InvoiceProduct__c>();
    for (String mergeKey : shouldHaveByMergeKey.keySet()) {
      MergeKeyDraft draft = shouldHaveByMergeKey.get(mergeKey);
      if (draft == null || draft.template == null || draft.amount == 0) {
        continue;
      }

      Id contractProductId = requireContractProductId(draft);
      ContractProduct__c contractProduct = findContractProductById(
        historyProducts,
        contractProductId
      );
      if (contractProduct == null) {
        throw new InvoiceProductGenerationException(
          '請求商品の見積商品が見つかりません: ' +
          String.valueOf(contractProductId)
        );
      }

      invoiceProducts.add(
        buildDiffInvoiceProduct(
          draft.template,
          historyId,
          contractProduct,
          draft.amount,
          billingContext
        )
      );
    }
    return invoiceProducts;
  }

  private static InvoiceProduct__c buildDiffInvoiceProduct(
    InvoiceProduct__c template,
    Id contractHistoryId,
    ContractProduct__c contractProduct,
    Decimal diffAmount,
    HistoryBillingContext billingContext
  ) {
    InvoiceProduct__c invoiceProduct = cloneInvoiceProduct(template);
    invoiceProduct.ContractHistory__c = contractHistoryId;
    invoiceProduct.ContractProduct__c = contractProduct == null
      ? null
      : contractProduct.Id;
    invoiceProduct.Amount__c = diffAmount;
    applyCorePeriodLineFields(invoiceProduct, contractProduct, billingContext);
    applyConfiguredFieldCopies(invoiceProduct, contractProduct, billingContext);
    return invoiceProduct;
  }

  /**
   * 契約期間明細のコア項目（CMDT 禁止・コード直書き）。
   */
  private static void applyCorePeriodLineFields(
    InvoiceProduct__c invoiceProduct,
    ContractProduct__c contractProduct,
    HistoryBillingContext billingContext
  ) {
    if (invoiceProduct == null || contractProduct == null) {
      return;
    }
    invoiceProduct.ContractProduct__c = contractProduct.Id;
    invoiceProduct.ContractHistory__c = contractProduct.ContractHistory__c !=
      null
      ? contractProduct.ContractHistory__c
      : (billingContext == null ||
          billingContext.contractHistory == null
          ? null
          : billingContext.contractHistory.Id);
    invoiceProduct.Quantity__c = contractProduct.Quantity__c;
    invoiceProduct.UnitPrice__c = contractProduct.UnitPrice__c;
    invoiceProduct.Unit__c = contractProduct.Unit__c;
  }

  private static void applyConfiguredFieldCopies(
    InvoiceProduct__c invoiceProduct,
    ContractProduct__c contractProduct,
    HistoryBillingContext billingContext
  ) {
    if (invoiceProduct == null) {
      return;
    }
    Map<String, SObject> sources = buildFieldCopySources(
      contractProduct,
      billingContext
    );
    FieldCopyDefinitionService.apply(
      invoiceProduct,
      InvoiceProductFieldCopyService.TARGET_INVOICE_PRODUCT,
      null,
      sources
    );
  }

  private static Map<String, SObject> buildFieldCopySources(
    ContractProduct__c contractProduct,
    HistoryBillingContext billingContext
  ) {
    Map<String, SObject> sources = new Map<String, SObject>();
    if (contractProduct != null) {
      sources.put(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_PRODUCT,
        contractProduct
      );
      SObject productSource = resolveProductSource(contractProduct);
      if (productSource != null) {
        sources.put(
          InvoiceProductFieldCopyService.OBJECT_PRODUCT,
          productSource
        );
      }
    }
    if (billingContext != null) {
      if (billingContext.contractHistory != null) {
        sources.put(
          InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
          billingContext.contractHistory
        );
      }
      if (billingContext.billingAccount != null) {
        sources.put(
          InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT,
          billingContext.billingAccount
        );
      }
      if (billingContext.opportunity != null) {
        sources.put(
          InvoiceProductFieldCopyService.OBJECT_OPPORTUNITY,
          billingContext.opportunity
        );
      }
      if (billingContext.account != null) {
        sources.put(
          InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
          billingContext.account
        );
      }
    }
    return sources;
  }

  private static SObject resolveProductSource(
    ContractProduct__c contractProduct
  ) {
    if (contractProduct == null) {
      return null;
    }
    SObject relatedProduct = contractProduct.getSObject('Product__r');
    if (relatedProduct != null) {
      return relatedProduct;
    }
    if (contractProduct.Product__c == null) {
      return null;
    }
    return InvoiceProductFieldCopyService.querySourceRecord(
      InvoiceProductFieldCopyService.OBJECT_PRODUCT,
      contractProduct.Product__c
    );
  }

  private static Map<Id, HistoryBillingContext> loadHistoryBillingContextByHistoryId(
    Set<Id> contractHistoryIds
  ) {
    Map<Id, HistoryBillingContext> billingContextByHistoryId = new Map<Id, HistoryBillingContext>();
    List<ContractHistory__c> histories = queryContractHistoriesForFieldCopy(
      contractHistoryIds
    );

    Set<Id> billingAccountIds = new Set<Id>();
    Set<Id> opportunityIds = new Set<Id>();
    Set<Id> accountIds = new Set<Id>();
    for (ContractHistory__c history : histories) {
      if (
        history.ContractService__r != null &&
        history.ContractService__r.BiilingAcccount__c != null
      ) {
        billingAccountIds.add(history.ContractService__r.BiilingAcccount__c);
      }
      if (history.Opportunity__c != null) {
        opportunityIds.add(history.Opportunity__c);
      }
      if (
        history.ContractService__r != null &&
        history.ContractService__r.Account__c != null
      ) {
        accountIds.add(history.ContractService__r.Account__c);
      }
    }

    Map<Id, BillingAccount__c> billingAccountById = loadBillingAccountsById(
      billingAccountIds
    );
    Map<Id, Opportunity> opportunityById = loadOpportunitiesById(
      opportunityIds
    );
    Map<Id, Account> accountById = loadAccountsById(accountIds);

    for (ContractHistory__c history : histories) {
      HistoryBillingContext billingContext = new HistoryBillingContext();
      billingContext.contractHistory = history;
      if (history.ContractService__r != null) {
        // Percent 項目の Apex 値（0.1＝10%）を表示％へ戻す。
        billingContext.taxPercent = TaxCalculationUtil.fromPercentFieldStorage(
          history.ContractService__r.TaxPercent__c
        );
      }
      Id billingAccountId = history.ContractService__r == null
        ? null
        : history.ContractService__r.BiilingAcccount__c;
      BillingAccount__c billingAccount = billingAccountId == null
        ? null
        : billingAccountById.get(billingAccountId);
      if (billingAccount != null) {
        billingContext.billingAccount = billingAccount;
      }
      if (history.Opportunity__c != null) {
        billingContext.opportunity = opportunityById.get(
          history.Opportunity__c
        );
      }
      Id accountId = history.ContractService__r == null
        ? null
        : history.ContractService__r.Account__c;
      if (accountId != null) {
        billingContext.account = accountById.get(accountId);
      }
      validateContractServiceAndOpportunityAccounts(billingContext);
      billingContextByHistoryId.put(history.Id, billingContext);
    }
    return billingContextByHistoryId;
  }

  /**
   * コピー元 Account は CS.Account。商談にも取引先がある場合は同一であること。
   */
  private static void validateContractServiceAndOpportunityAccounts(
    HistoryBillingContext billingContext
  ) {
    if (billingContext == null) {
      return;
    }
    Id serviceAccountId = billingContext.account == null
      ? null
      : billingContext.account.Id;
    Id opportunityAccountId = billingContext.opportunity == null
      ? null
      : billingContext.opportunity.AccountId;
    if (serviceAccountId == null || opportunityAccountId == null) {
      return;
    }
    if (serviceAccountId == opportunityAccountId) {
      return;
    }
    throw new InvoiceProductFieldCopyService.FieldCopyException(
      '契約サービスの取引先と商談の取引先が一致しません' +
        '（契約サービス取引先: ' +
        String.valueOf(serviceAccountId) +
        ' / 商談取引先: ' +
        String.valueOf(opportunityAccountId) +
        '）。'
    );
  }

  private static List<ContractHistory__c> queryContractHistoriesForFieldCopy(
    Set<Id> contractHistoryIds
  ) {
    Set<String> selectFields = InvoiceProductFieldCopyService.getSourceFieldApiNames(
      InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY
    );
    Map<String, Schema.SObjectField> fieldMap = ContractHistory__c.SObjectType.getDescribe()
      .fields.getMap();
    List<String> selectList = new List<String>();
    for (String fieldApiName : selectFields) {
      if (fieldMap.containsKey(fieldApiName)) {
        selectList.add(fieldApiName);
      }
    }
    if (selectList.isEmpty()) {
      selectList.add('Id');
    }
    Set<String> uniqueSelect = new Set<String>(selectList);
    uniqueSelect.add('Opportunity__c');
    uniqueSelect.add('Type__c');
    uniqueSelect.add('EffectiveDate__c');
    uniqueSelect.add('Version__c');
    uniqueSelect.add('ContractService__c');
    uniqueSelect.add('ContractService__r.TaxPercent__c');
    uniqueSelect.add('ContractService__r.BiilingAcccount__c');
    uniqueSelect.add('ContractService__r.Account__c');
    selectList = new List<String>(uniqueSelect);

    Set<Id> missingHistoryIds = new Set<Id>();
    for (Id historyId : contractHistoryIds) {
      if (!cachedHistoriesForFieldCopy.containsKey(historyId)) {
        missingHistoryIds.add(historyId);
      }
    }
    if (!missingHistoryIds.isEmpty()) {
    String soql =
      'SELECT ' +
      String.join(selectList, ',') +
      ' FROM ContractHistory__c' +
      ' WHERE Id IN :missingHistoryIds WITH SYSTEM_MODE';
    for (ContractHistory__c history : (List<ContractHistory__c>) Database.query(soql)) {
      cachedHistoriesForFieldCopy.put(history.Id, history);
    }
    }
    List<ContractHistory__c> loaded = new List<ContractHistory__c>();
    for (Id historyId : contractHistoryIds) {
      if (cachedHistoriesForFieldCopy.containsKey(historyId)) {
        loaded.add(cachedHistoriesForFieldCopy.get(historyId));
      }
    }
    InvoiceProductFieldCopyService.rememberRecords(loaded);
    return loaded;
  }

  private static Map<Id, BillingAccount__c> loadBillingAccountsById(
    Set<Id> billingAccountIds
  ) {
    if (billingAccountIds == null || billingAccountIds.isEmpty()) {
      return new Map<Id, BillingAccount__c>();
    }

    Set<String> selectFields = InvoiceProductFieldCopyService.getSourceFieldApiNames(
      InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT
    );
    // Invoice-date / payment-date calculation fields (not necessarily copy targets).
    selectFields.addAll(BillingScheduleService.BILLING_ACCOUNT_SCHEDULE_FIELDS);
    // 仕様: Core 第3.3.5節、第3.3.7節。受注時スナップショット用。
    selectFields.add('InvoiceDeliveryMethod__c');
    selectFields.add('BillingAddressee__c');
    selectFields.add('BillingEmailTo__c');
    selectFields.add('BillingEmailCc__c');
    selectFields.add('BillingEmailBcc__c');
    selectFields.add('BillingAccountKey__c');

    Map<String, Schema.SObjectField> fieldMap = BillingAccount__c.SObjectType.getDescribe()
      .fields.getMap();
    List<String> selectList = new List<String>();
    for (String fieldApiName : selectFields) {
      if (fieldMap.containsKey(fieldApiName)) {
        selectList.add(fieldApiName);
      }
    }
    if (selectList.isEmpty()) {
      selectList.add('Id');
    }

    Set<Id> missingBillingAccountIds = new Set<Id>();
    for (Id accountId : billingAccountIds) {
      if (!cachedBillingAccountsById.containsKey(accountId)) {
        missingBillingAccountIds.add(accountId);
      }
    }
    String soql =
      'SELECT ' +
      String.join(selectList, ',') +
      ' FROM BillingAccount__c' +
      ' WHERE Id IN :missingBillingAccountIds WITH SYSTEM_MODE';
    if (!missingBillingAccountIds.isEmpty()) {
      for (BillingAccount__c account : (List<BillingAccount__c>) Database.query(soql)) {
        cachedBillingAccountsById.put(account.Id, account);
      }
    }
    Map<Id, BillingAccount__c> loaded = new Map<Id, BillingAccount__c>();
    for (Id accountId : billingAccountIds) {
      if (cachedBillingAccountsById.containsKey(accountId)) {
        loaded.put(accountId, cachedBillingAccountsById.get(accountId));
      }
    }
    InvoiceProductFieldCopyService.rememberRecords(loaded.values());
    return loaded;
  }

  private static Map<Id, Opportunity> loadOpportunitiesById(
    Set<Id> opportunityIds
  ) {
    if (opportunityIds == null || opportunityIds.isEmpty()) {
      return new Map<Id, Opportunity>();
    }

    Set<String> selectFields = InvoiceProductFieldCopyService.getSourceFieldApiNames(
      InvoiceProductFieldCopyService.OBJECT_OPPORTUNITY
    );
    // CS.Account との一致検証用（CMDT コピー元とは別）
    selectFields.add('AccountId');

    Map<String, Schema.SObjectField> fieldMap = Opportunity.SObjectType.getDescribe()
      .fields.getMap();
    List<String> selectList = new List<String>();
    for (String fieldApiName : selectFields) {
      if (fieldMap.containsKey(fieldApiName)) {
        selectList.add(fieldApiName);
      }
    }
    if (selectList.isEmpty()) {
      selectList.add('Id');
    }

    String soql =
      'SELECT ' +
      String.join(selectList, ',') +
      ' FROM Opportunity' +
      ' WHERE Id IN :opportunityIds WITH SYSTEM_MODE';
    Map<Id, Opportunity> loaded = new Map<Id, Opportunity>(
      (List<Opportunity>) Database.query(soql)
    );
    InvoiceProductFieldCopyService.rememberRecords(loaded.values());
    return loaded;
  }

  private static Map<Id, Account> loadAccountsById(Set<Id> accountIds) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new Map<Id, Account>();
    }

    Set<String> selectFields = InvoiceProductFieldCopyService.getSourceFieldApiNames(
      InvoiceProductFieldCopyService.OBJECT_ACCOUNT
    );
    Map<String, Schema.SObjectField> fieldMap = Account.SObjectType.getDescribe()
      .fields.getMap();
    List<String> selectList = new List<String>();
    for (String fieldApiName : selectFields) {
      if (fieldMap.containsKey(fieldApiName)) {
        selectList.add(fieldApiName);
      }
    }
    if (selectList.isEmpty()) {
      selectList.add('Id');
    }

    String soql =
      'SELECT ' +
      String.join(selectList, ',') +
      ' FROM Account' +
      ' WHERE Id IN :accountIds WITH SYSTEM_MODE';
    Map<Id, Account> loaded = new Map<Id, Account>(
      (List<Account>) Database.query(soql)
    );
    InvoiceProductFieldCopyService.rememberRecords(loaded.values());
    return loaded;
  }

  private static List<ContractProduct__c> queryContractProductsForGeneration(
    Set<Id> contractHistoryIds
  ) {
    Set<String> selectFields = InvoiceProductFieldCopyService.getSourceFieldApiNames(
      InvoiceProductFieldCopyService.OBJECT_CONTRACT_PRODUCT
    );
    // 生成ロジックが直接参照する必須項目（CMDT の有無に依存させない）
    selectFields.add('ContractHistory__c');
    selectFields.add('Product__c');
    selectFields.add('Type__c');
    selectFields.add('BillingType__c');
    selectFields.add('Quantity__c');
    selectFields.add('UnitPrice__c');
    selectFields.add('Unit__c');
    selectFields.add('Amount__c');
    selectFields.add('StartDate__c');
    selectFields.add('Enddate__c');
    selectFields.add('InvoiceSetting__c');
    selectFields.add('InvoiceAnchorDate__c');
    selectFields.add('RevenueRecognitionBasis__c');
    selectFields.add('PreviousContractProduct__c');

    Map<String, Schema.SObjectField> fieldMap = ContractProduct__c.SObjectType.getDescribe()
      .fields.getMap();
    List<String> selectList = new List<String>();
    for (String fieldApiName : selectFields) {
      if (fieldMap.containsKey(fieldApiName)) {
        selectList.add(fieldApiName);
      }
    }

    Set<String> productSelectFields = new Set<String>{ 'BillingType__c' };
    productSelectFields.addAll(
      InvoiceProductFieldCopyService.getSourceFieldApiNames(
        InvoiceProductFieldCopyService.OBJECT_PRODUCT
      )
    );
    Map<String, Schema.SObjectField> productFieldMap = Product2.SObjectType.getDescribe()
      .fields.getMap();
    for (String fieldApiName : productSelectFields) {
      if (productFieldMap.containsKey(fieldApiName)) {
        selectList.add('Product__r.' + fieldApiName);
      }
    }

    Set<Id> missingHistoryIds = new Set<Id>();
    for (Id historyId : contractHistoryIds) {
      if (!cachedContractProductsByHistoryId.containsKey(historyId)) {
        missingHistoryIds.add(historyId);
      }
    }
    if (!missingHistoryIds.isEmpty()) {
      String soql =
        'SELECT ' +
        String.join(selectList, ',') +
        ' FROM ContractProduct__c' +
        ' WHERE ContractHistory__c IN :missingHistoryIds WITH SYSTEM_MODE';
      for (ContractProduct__c contractProduct : (List<ContractProduct__c>) Database.query(
        soql
      )) {
        List<ContractProduct__c> bucket = cachedContractProductsByHistoryId.get(
          contractProduct.ContractHistory__c
        );
        if (bucket == null) {
          bucket = new List<ContractProduct__c>();
          cachedContractProductsByHistoryId.put(
            contractProduct.ContractHistory__c,
            bucket
          );
        }
        bucket.add(contractProduct);
      }
      for (Id historyId : missingHistoryIds) {
        if (!cachedContractProductsByHistoryId.containsKey(historyId)) {
          cachedContractProductsByHistoryId.put(
            historyId,
            new List<ContractProduct__c>()
          );
        }
      }
    }
    List<ContractProduct__c> loaded = new List<ContractProduct__c>();
    for (Id historyId : contractHistoryIds) {
      List<ContractProduct__c> bucket = cachedContractProductsByHistoryId.get(
        historyId
      );
      if (bucket != null) {
        loaded.addAll(bucket);
      }
    }
    InvoiceProductFieldCopyService.rememberRecords(loaded);
    return loaded;
  }

  private static List<InvoiceProduct__c> queryPastOrderedInvoiceProducts(
    Id contractServiceId,
    Decimal currentVersion
  ) {
    Set<String> selectFields = new Set<String>{
      'StartDate__c',
      'Enddate__c',
      'InvoiceBucketKey__c',
      'LineBucketKey__c',
      'Amount__c',
      'Quantity__c',
      'UnitPrice__c',
      'Unit__c'
    };
    // 期間明細向け定義のみ。Invoice / InvoiceLine 向け（BA SnapShot 等）を混ぜない
    selectFields.addAll(
      InvoiceProductFieldCopyService.getTargetFieldApiNames(
        InvoiceProductFieldCopyService.TARGET_INVOICE_PRODUCT
      )
    );

    Map<String, Schema.SObjectField> fieldMap = InvoiceProduct__c.SObjectType.getDescribe()
      .fields.getMap();
    List<String> selectList = new List<String>();
    for (String fieldApiName : selectFields) {
      if (fieldMap.containsKey(fieldApiName)) {
        selectList.add(fieldApiName);
      }
    }
    selectList.add('ContractProduct__r.Product__c');
    selectList.add('ContractProduct__r.Quantity__c');
    selectList.add('ContractProduct__r.UnitPrice__c');
    selectList.add('ContractProduct__r.Unit__c');
    selectList.add('ContractProduct__r.BillingType__c');
    selectList.add('ContractProduct__r.Product__r.BillingType__c');
    selectList.add('ContractHistory__r.ContractService__c');

    String soql =
      'SELECT ' +
      String.join(selectList, ',') +
      ' FROM InvoiceProduct__c' +
      ' WHERE ContractHistory__r.ContractService__c = :contractServiceId' +
      ' AND ContractHistory__r.historystatus__c = :HISTORY_STATUS_ORDERED' +
      ' AND ContractHistory__r.Version__c < :currentVersion' +
      ' WITH SYSTEM_MODE' +
      ' ORDER BY ContractHistory__r.Version__c DESC, CreatedDate DESC, Id DESC';
    return (List<InvoiceProduct__c>) Database.query(soql);
  }

  private static void deleteAllInvoiceProducts(Set<Id> contractHistoryIds) {
    List<InvoiceProduct__c> existingProducts = [
      SELECT Id
      FROM InvoiceProduct__c
      WHERE ContractHistory__c IN :contractHistoryIds
      WITH SYSTEM_MODE
    ];
    if (!existingProducts.isEmpty()) {
      SystemContextAccess.deleteRecords(existingProducts);
    }
  }

  private static List<DraftInvoiceLine> buildInvoiceProductDrafts(
    ContractProduct__c contractProduct,
    HistoryBillingContext billingContext,
    InvoiceGenerationContext context
  ) {
    List<DraftInvoiceLine> draftLines = new List<DraftInvoiceLine>();
    String invoiceSetting = contractProduct.InvoiceSetting__c;

    Date serviceStartDate = contractProduct.StartDate__c;
    Date generationStartDate = resolveGenerationStartDate(
      contractProduct,
      context
    );
    Date generationEndDate = contractProduct.Enddate__c;
    if (
      generationStartDate == null ||
      generationEndDate == null ||
      generationEndDate < generationStartDate
    ) {
      return draftLines;
    }

    String billingType = resolveBillingType(contractProduct);
    Boolean usesBulkInvoiceDate = ContractMetadataService.usesBulkContractProductInvoiceDate(
      invoiceSetting
    );
    Date contractProductInvoiceDate;
    if (usesBulkInvoiceDate && contractProduct.InvoiceAnchorDate__c != null) {
      contractProductInvoiceDate = computeGeneratedInvoiceDate(
        billingContext,
        contractProduct.InvoiceAnchorDate__c
      );
    }
    if (
      billingType == BILLING_TYPE_RECURRING &&
      ContractMetadataService.isRecurringBillingType(billingType)
    ) {
      // 仕様: カレンダー月分割は使わない（明細開始日起点の月次のみ）
      List<MonthlyBillingPeriodUtil.BillingPeriod> periods = MonthlyBillingPeriodUtil.buildMonthlyPeriods(
        generationStartDate,
        generationEndDate
      );
      for (MonthlyBillingPeriodUtil.BillingPeriod period : periods) {
        Date invoiceDate = usesBulkInvoiceDate
          ? contractProductInvoiceDate
          : computeGeneratedInvoiceDate(billingContext, period.startDate);
        draftLines.add(
          new DraftInvoiceLine(
            contractProduct.Product__c,
            contractProduct,
            createInvoiceProduct(
              contractProduct,
              period.startDate,
              period.endDate,
              invoiceDate,
              billingContext
            )
          )
        );
      }
      return draftLines;
    }

    Date invoiceDate = usesBulkInvoiceDate
      ? contractProductInvoiceDate
      : computeGeneratedInvoiceDate(billingContext, serviceStartDate);
    draftLines.add(
      new DraftInvoiceLine(
        contractProduct.Product__c,
        contractProduct,
        createInvoiceProduct(
          contractProduct,
          serviceStartDate,
          generationEndDate,
          invoiceDate,
          billingContext
        )
      )
    );
    return draftLines;
  }

  private static Date resolveGenerationStartDate(
    ContractProduct__c contractProduct,
    InvoiceGenerationContext context
  ) {
    Date startDate = contractProduct.StartDate__c;
    if (isOriginalProductType(contractProduct)) {
      return startDate;
    }
    if (
      context == null ||
      context.historyType != HISTORY_TYPE_CHANGE ||
      context.effectiveDate == null
    ) {
      return startDate;
    }
    // 有効日前で終わるセグメントは期間を空にしない（請求基準日のみ有効日へ寄せる）。
    if (
      contractProduct.Enddate__c != null &&
      contractProduct.Enddate__c < context.effectiveDate
    ) {
      return startDate;
    }
    if (startDate == null || context.effectiveDate <= startDate) {
      return startDate;
    }
    // 有効日以降を出すときも月次グリッドは明細開始日起点のまま。
    // 有効日そのものを開始にすると期中日でグリッドが再錨定され、過去 period key とずれる。
    Date snappedStart = resolveFirstMonthlyPeriodStartOnOrAfter(
      startDate,
      context.effectiveDate
    );
    return snappedStart == null ? context.effectiveDate : snappedStart;
  }

  /**
   * 明細開始日起点の月次境界上で、candidate 当日以降の最初の期間開始日を返す。
   * candidate が境界上ならその日。期中なら次の期間開始日。
   */
  @TestVisible
  private static Date resolveFirstMonthlyPeriodStartOnOrAfter(
    Date anchorStartDate,
    Date candidateDate
  ) {
    if (anchorStartDate == null || candidateDate == null) {
      return candidateDate;
    }
    if (candidateDate < anchorStartDate) {
      return anchorStartDate;
    }
    if (
      MonthlyBillingPeriodUtil.isMonthlyPeriodStartDate(
        anchorStartDate,
        candidateDate
      )
    ) {
      return candidateDate;
    }
    Date periodStart = anchorStartDate;
    while (periodStart <= candidateDate) {
      Date periodEnd = MonthlyBillingPeriodUtil.endOfMonthlyPeriod(periodStart);
      Date nextStart = periodEnd.addDays(1);
      if (candidateDate <= periodEnd) {
        return nextStart;
      }
      periodStart = nextStart;
    }
    return candidateDate;
  }

  private static void ensureInvoiceAnchorFields(
    ContractProduct__c contractProduct,
    HistoryGenerationContext historyContext
  ) {
    if (
      contractProduct == null ||
      contractProduct.InvoiceAnchorDate__c != null
    ) {
      return;
    }
    InvoiceAnchorDateUtil.applyToContractProduct(
      contractProduct,
      historyContext == null ? null : historyContext.historyType,
      historyContext == null ? null : historyContext.effectiveDate
    );
  }

  /**
   * Change 差分生成などで期間明細を複製する。
   * コピー対象は期間・金額等のコア＋期間明細向け CMDT のみ。
   * 請求ヘッダ用 SnapShot（Inv_BA_* 等）は混ぜない。
   */
  @TestVisible
  private static InvoiceProduct__c cloneInvoiceProduct(
    InvoiceProduct__c source
  ) {
    if (source == null) {
      return null;
    }

    Set<String> fieldsToCopy = new Set<String>{
      'ContractProduct__c',
      'StartDate__c',
      'Enddate__c',
      'InvoiceBucketKey__c',
      'LineBucketKey__c',
      'Amount__c'
    };
    fieldsToCopy.addAll(
      InvoiceProductFieldCopyService.getTargetFieldApiNames(
        InvoiceProductFieldCopyService.TARGET_INVOICE_PRODUCT
      )
    );

    InvoiceProduct__c cloned = new InvoiceProduct__c();
    Map<String, Object> populatedFields = source.getPopulatedFieldsAsMap();
    for (String fieldApiName : fieldsToCopy) {
      if (populatedFields.containsKey(fieldApiName)) {
        cloned.put(fieldApiName, populatedFields.get(fieldApiName));
      }
    }
    return cloned;
  }

  private static InvoiceProduct__c createInvoiceProduct(
    ContractProduct__c contractProduct,
    Date startDate,
    Date endDate,
    Date invoiceDate,
    HistoryBillingContext billingContext
  ) {
    InvoiceProduct__c invoiceProduct = new InvoiceProduct__c(
      ContractProduct__c = contractProduct == null ? null : contractProduct.Id,
      StartDate__c = startDate,
      Enddate__c = endDate,
      Amount__c = calculatePositiveAmount(contractProduct)
    );
    applyCorePeriodLineFields(invoiceProduct, contractProduct, billingContext);
    applyMergeBucketKeys(
      invoiceProduct,
      contractProduct,
      billingContext,
      invoiceDate
    );
    applyConfiguredFieldCopies(invoiceProduct, contractProduct, billingContext);
    return invoiceProduct;
  }

  /**
   * 期間明細に請求書／請求明細バケットキーを載せる。
   * 構成はパッケージ固定（静的キー）。請求寄せ項目自体は期間明細に持たない。
   */
  private static void applyMergeBucketKeys(
    InvoiceProduct__c invoiceProduct,
    ContractProduct__c contractProduct,
    HistoryBillingContext billingContext,
    Date invoiceDate
  ) {
    if (invoiceProduct == null) {
      return;
    }
    Id billingAccountId = billingContext == null ||
      billingContext.billingAccount == null
      ? null
      : billingContext.billingAccount.Id;
    Id contractHistoryId = billingContext == null ||
      billingContext.contractHistory == null
      ? null
      : billingContext.contractHistory.Id;
    if (
      contractHistoryId == null &&
      invoiceProduct.ContractHistory__c != null
    ) {
      contractHistoryId = invoiceProduct.ContractHistory__c;
    }
    Date paymentScheduledDate = billingContext != null &&
      billingContext.billingAccount != null
      ? BillingScheduleService.computePaymentScheduledDate(
          billingContext.billingAccount,
          invoiceDate
        )
      : null;
    invoiceProduct.InvoiceBucketKey__c = InvoiceMergeKeyConfigService.buildInvoiceBucketKey(
      billingAccountId,
      contractHistoryId,
      invoiceDate,
      paymentScheduledDate
    );

    Id contractProductId = contractProduct == null
      ? invoiceProduct.ContractProduct__c
      : contractProduct.Id;
    Decimal unitPrice = contractProduct == null
      ? invoiceProduct.UnitPrice__c
      : contractProduct.UnitPrice__c;
    Decimal quantity = contractProduct == null
      ? invoiceProduct.Quantity__c
      : contractProduct.Quantity__c;
    String unit = contractProduct == null
      ? invoiceProduct.Unit__c
      : contractProduct.Unit__c;
    Id productId = contractProduct == null ? null : contractProduct.Product__c;
    invoiceProduct.LineBucketKey__c = InvoiceMergeKeyConfigService.buildLineBucketKey(
      contractProductId,
      unitPrice,
      quantity,
      unit,
      productId
    );
  }

  private static Decimal calculatePositiveAmount(
    ContractProduct__c contractProduct
  ) {
    Decimal quantity = contractProduct.Quantity__c == null
      ? 0
      : contractProduct.Quantity__c;
    Decimal unitPrice = contractProduct.UnitPrice__c == null
      ? 0
      : contractProduct.UnitPrice__c;
    // 期間明細1サイクル税抜は画面 yenFromQuantityUnitPrice(qty, price, 1) と一致させる。
    return ContractProductAmountUtil.yenFromQuantityUnitPrice(
      quantity,
      unitPrice,
      1
    );
  }

  private static String resolveBillingType(ContractProduct__c contractProduct) {
    return ContractMetadataService.resolveLineBillingType(contractProduct);
  }

  /**
   * period key の課金種別判定。見積商品の課金形態だけを使う。
   */
  private static Boolean isOneTimeBillingForPeriod(
    List<ContractProduct__c> historyProducts,
    Id productId,
    InvoiceProduct__c pastSample
  ) {
    if (pastSample != null && pastSample.ContractProduct__r != null) {
      String pastBillingType = resolveBillingType(
        pastSample.ContractProduct__r
      );
      if (String.isNotBlank(pastBillingType)) {
        return isOneTimeBillingType(pastBillingType);
      }
    }
    if (historyProducts != null && productId != null) {
      for (ContractProduct__c contractProduct : historyProducts) {
        if (contractProduct.Product__c == productId) {
          return isOneTimeBillingType(resolveBillingType(contractProduct));
        }
      }
    }
    return false;
  }

  private static Boolean isOneTimeBillingType(String billingType) {
    return String.isNotBlank(billingType) &&
      !ContractMetadataService.isRecurringBillingType(billingType);
  }

  private static Boolean isOriginalProductType(ContractProduct__c product) {
    return product != null && product.Type__c == PRODUCT_TYPE_ORIGINAL;
  }

  private static Boolean isRemakeAfterProductType(String productType) {
    return productType == PRODUCT_TYPE_REMAKE ||
      productType == LEGACY_PRODUCT_TYPE_DERIVATIVE;
  }

  private static Boolean isChangeStandaloneContractProduct(
    ContractProduct__c product
  ) {
    if (product == null || isOriginalProductType(product)) {
      return false;
    }
    return !isRemakeAfterProductType(product.Type__c);
  }

  public class InvoiceProductGenerationException extends Exception {
  }
}
