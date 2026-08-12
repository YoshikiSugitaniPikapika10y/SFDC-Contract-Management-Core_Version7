import { LightningElement, api, track } from "lwc";
import LightningConfirm from "lightning/confirm";
import getSplitThresholdDateOptions from "@salesforce/apex/OrderCreateController.getSplitThresholdDateOptions";

const ALL_VERSIONS = "ALL";
const KIND_PERIOD = "period";
const KIND_UNIT_PRICE = "unitPrice";
const KIND_QUANTITY = "quantity";
/** 商品名: 列幅に収まるまで縮小（rem）。下限未満は省略記号。 */
const PRODUCT_NAME_FONT_MAX_REM = 0.6875;
const PRODUCT_NAME_FONT_MIN_REM = 0.5625;
const PRODUCT_NAME_FONT_STEP_REM = 0.03125;

export default class OrderInvoicePreviewTable extends LightningElement {
  @api billingAccountOptions = [];
  @api isSaving = false;

  @api
  clearBillingEditState() {
    this.billingEditState = null;
  }

  @track selectedVersion = ALL_VERSIONS;
  @track invoiceSplitState = null;
  @track invoiceMoveState = null;
  @track lineSplitState = null;
  @track billingEditState = null;
  @track amountDrafts = {};

  _preview;
  /** オープン時の Version フィルタ初期値を一度だけ適用したか（保存後の再取得では維持）。 */
  _defaultVersionApplied = false;
  _wheelBound = false;
  _onPreviewWheel = (event) => this.handlePreviewWheel(event);
  _fitProductNamesRaf = null;
  _resizeObserver = null;

  billingAccountMatchingInfo = {
    primaryField: {
      fieldPath: "Name"
    }
  };

  @api
  get preview() {
    return this._preview;
  }
  set preview(value) {
    this._preview = value;
    // サーバ反映後は draft を捨てて正本表示に戻す
    this.amountDrafts = {};
    this.invoiceSplitState = null;
    this.invoiceMoveState = null;
    this.lineSplitState = null;
    this.applyDefaultVersionFilter();
  }

  /**
   * クリック元の契約履歴 Version をフィルタ初期値にする。
   * 候補に無ければ全バージョン。ユーザー切替後／保存後の再取得では維持。
   */
  applyDefaultVersionFilter() {
    if (this._defaultVersionApplied || !this._preview) {
      return;
    }
    const raw = this._preview.sourceHistoryVersion;
    if (raw == null || raw === "") {
      this._defaultVersionApplied = true;
      return;
    }
    const value = String(raw);
    const exists = (this._preview.versionOptions || []).some(
      (option) => String(option?.value) === value
    );
    this.selectedVersion = exists ? value : ALL_VERSIONS;
    this._defaultVersionApplied = true;
  }

  connectedCallback() {
    // capture + host でテーブル内のどこでも親スクローラへ渡す
    this.template.host.addEventListener("wheel", this._onPreviewWheel, {
      passive: false,
      capture: true
    });
    this._wheelBound = true;
  }

  renderedCallback() {
    if (!this._resizeObserver && typeof ResizeObserver !== "undefined") {
      this._resizeObserver = new ResizeObserver(() => {
        this.scheduleFitProductNames();
      });
      this._resizeObserver.observe(this.template.host);
    }
    this.scheduleFitProductNames();
  }

  scheduleFitProductNames() {
    if (this._fitProductNamesRaf != null) {
      return;
    }
    this._fitProductNamesRaf = requestAnimationFrame(() => {
      this._fitProductNamesRaf = null;
      this.fitProductNameFonts();
    });
  }

  /**
   * 商品名を列幅内の1行に収める。長い場合はフォントを下限まで縮小し、
   * それでも溢れるときだけ ellipsis（title で全文）。
   */
  fitProductNameFonts() {
    const nodes = this.template.querySelectorAll(".product-name");
    if (!nodes || nodes.length === 0) {
      return;
    }
    nodes.forEach((el) => {
      if (!el) {
        return;
      }
      let rem = PRODUCT_NAME_FONT_MAX_REM;
      el.style.fontSize = `${rem}rem`;
      // レイアウト確定後に測る（幅0はスキップ）
      if (el.clientWidth < 8) {
        return;
      }
      while (
        el.scrollWidth > el.clientWidth + 1 &&
        rem > PRODUCT_NAME_FONT_MIN_REM + 0.0001
      ) {
        rem = Math.max(
          PRODUCT_NAME_FONT_MIN_REM,
          rem - PRODUCT_NAME_FONT_STEP_REM
        );
        el.style.fontSize = `${rem}rem`;
      }
    });
  }

  disconnectedCallback() {
    if (this._fitProductNamesRaf != null) {
      cancelAnimationFrame(this._fitProductNamesRaf);
      this._fitProductNamesRaf = null;
    }
    if (this._resizeObserver) {
      this._resizeObserver.disconnect();
      this._resizeObserver = null;
    }
    if (!this._wheelBound) {
      return;
    }
    this.template.host.removeEventListener("wheel", this._onPreviewWheel, {
      capture: true
    });
    this._wheelBound = false;
  }

  get relatedBillingAccountOptions() {
    return (this.billingAccountOptions || [])
      .map((option) => ({
        label: option.name || option.label || String(option.id),
        value: option.id || option.value
      }))
      .filter((option) => option.value);
  }

  get showInvoiceSplitRelatedBillingCombobox() {
    return (
      this.invoiceSplitState != null &&
      !this.invoiceSplitState.allowOtherAccountBilling
    );
  }

  get showInvoiceSplitOtherBillingPicker() {
    return (
      this.invoiceSplitState != null &&
      this.invoiceSplitState.allowOtherAccountBilling === true
    );
  }

  get invoiceSplitBillingAccountComboboxOptions() {
    return this.buildBillingComboboxOptions(this.invoiceSplitState);
  }

  buildBillingComboboxOptions(state) {
    const options = [...this.relatedBillingAccountOptions];
    const sourceInvoice = this.findInvoice(state?.invoiceId);
    const ensureIds = [
      state?.newBillingAccountId,
      sourceInvoice?.billingAccountId
    ].filter(Boolean);
    const existing = new Set(options.map((row) => row.value));
    for (const id of ensureIds) {
      if (existing.has(id)) {
        continue;
      }
      const label =
        sourceInvoice?.billingAccountId === id
          ? sourceInvoice.billingAccountName || id
          : id;
      options.unshift({ label, value: id });
      existing.add(id);
    }
    return options;
  }

  get versionOptions() {
    const options = [{ label: "全バージョン", value: ALL_VERSIONS }];
    (this.preview?.versionOptions || []).forEach((option) => {
      if (!option?.value) {
        return;
      }
      options.push({
        label: option.label || `V${option.value}`,
        value: String(option.value)
      });
    });
    return options;
  }

  get showVersionFilter() {
    return (this.preview?.versionOptions || []).length > 0;
  }

  /** Ordered Version の最大値（フィルタ value と同形式）。 */
  get latestOrderedVersionValue() {
    let max = null;
    for (const option of this.preview?.versionOptions || []) {
      if (option?.value == null || option.value === "") {
        continue;
      }
      const n = Number(option.value);
      if (!Number.isFinite(n)) {
        continue;
      }
      if (max == null || n > max) {
        max = n;
      }
    }
    return max == null ? null : String(max);
  }

  invoicesForSelectedVersion() {
    const selected = this.selectedVersion;
    if (selected === ALL_VERSIONS) {
      return [];
    }
    return (this.preview?.invoices || []).filter(
      (invoice) =>
        invoice?.historyVersion != null &&
        String(Number(invoice.historyVersion)) === String(selected)
    );
  }

  /**
   * 特定 Version 絞り込み・最新 Ordered・配下請求がすべて未ロックのときだけ表示。
   */
  get showResetPostOrderButton() {
    if (!this.canEdit) {
      return false;
    }
    if (this.selectedVersion === ALL_VERSIONS) {
      return false;
    }
    if (
      this.latestOrderedVersionValue == null ||
      String(this.selectedVersion) !== String(this.latestOrderedVersionValue)
    ) {
      return false;
    }
    const invoices = this.invoicesForSelectedVersion();
    return invoices.every((invoice) => invoice.locked !== true);
  }

  get resetPostOrderDisabled() {
    return this.isSaving === true || this.hasAmountDrafts;
  }

  get resetPostOrderTitle() {
    if (this.hasAmountDrafts) {
      return "端数調整の保存または取消後に操作できます";
    }
    return "この Version の請求を受注直後の状態に作り直します";
  }

  get hasInvoices() {
    return this.invoiceCards.length > 0;
  }

  get canEdit() {
    return (
      this.preview?.canEdit === true && this.preview?.versionEditBlocked !== true
    );
  }

  get showAmountCompare() {
    return this.hasInvoices;
  }

  get hasAmountDrafts() {
    return Object.keys(this.amountDrafts || {}).length > 0;
  }

  get showAmountDraftActions() {
    return this.hasAmountDrafts && this.canEdit;
  }

  get amountDraftActionsDisabled() {
    return this.isSaving === true;
  }

  get estimatePreviewTotal() {
    const selected = this.selectedVersion;
    if (selected === ALL_VERSIONS) {
      return this.preview?.periodLineAmountTotal ?? 0;
    }
    const option = (this.preview?.versionOptions || []).find(
      (row) => String(row.value) === String(selected)
    );
    return Number(option?.periodLineAmountTotal ?? 0);
  }

  get invoicePreviewTotal() {
    const selected = this.selectedVersion;
    let base = 0;
    if (selected === ALL_VERSIONS) {
      base = Number(this.preview?.invoiceAmountTotal ?? 0);
    } else {
      const option = (this.preview?.versionOptions || []).find(
        (row) => String(row.value) === String(selected)
      );
      if (option) {
        base = Number(option.invoiceAmountTotal ?? 0);
      } else {
        base = this.sumSavedInvoiceAmountForVersion(selected);
      }
    }
    return base + this.draftAmountDeltaForSelection();
  }

  get amountDifference() {
    return (
      (Number(this.invoicePreviewTotal) || 0) -
      (Number(this.estimatePreviewTotal) || 0)
    );
  }

  get amountDifferenceAbs() {
    return Math.abs(Number(this.amountDifference) || 0);
  }

  /**
   * 端数調整の実績（保存済みの明細調整 + 未保存 draft）。
   * 見積＝請求でも、生成元からの調整分があればその値を出す。
   */
  get manualAdjustmentAmount() {
    const selected = this.selectedVersion;
    let base = 0;
    if (selected === ALL_VERSIONS) {
      base = Number(this.preview?.manualAdjustmentAmount ?? 0);
    } else {
      const option = (this.preview?.versionOptions || []).find(
        (row) => String(row.value) === String(selected)
      );
      base = Number(option?.manualAdjustmentAmount ?? 0);
    }
    return base + this.draftAmountDeltaForSelection();
  }

  /**
   * 調整なし請求額（表示しない。調整後 − 端数調整実績）。
   * 将来の内訳表示や計算用に保持。
   */
  get invoiceAmountBeforeAdjustment() {
    return (
      (Number(this.invoicePreviewTotal) || 0) -
      (Number(this.manualAdjustmentAmount) || 0)
    );
  }

  get isAmountMatched() {
    return Number(this.amountDifference) === 0;
  }

  get amountCompareOperator() {
    const estimate = Number(this.estimatePreviewTotal) || 0;
    const invoice = Number(this.invoicePreviewTotal) || 0;
    if (estimate === invoice) {
      return "=";
    }
    if (estimate > invoice) {
      return ">";
    }
    return "<";
  }

  get amountCompareStatusLabel() {
    return this.isAmountMatched ? "端数なし" : "端数あり";
  }

  get amountCompareClass() {
    const classes = ["amount-compare"];
    if (!this.isAmountMatched) {
      classes.push("amount-compare_drift");
    } else {
      classes.push("amount-compare_ok");
    }
    if (this.hasAmountDrafts) {
      classes.push("amount-compare_draft");
    }
    return classes.join(" ");
  }

  formatSignedYen(value) {
    const n = Math.round(Number(value) || 0);
    const abs = Math.abs(n).toLocaleString("ja-JP");
    if (n > 0) {
      return `+¥${abs}`;
    }
    if (n < 0) {
      return `-¥${abs}`;
    }
    return "¥0";
  }

  get editBlockedMessage() {
    if (this.preview?.versionEditBlocked) {
      return "この Version に連携済または消込済の請求があるため編集できません。";
    }
    if (this.preview?.canEdit !== true) {
      return "請求プレビュー編集の権限がありません。";
    }
    return "";
  }

  get invoiceCards() {
    const selected = this.selectedVersion;
    const filterAll = selected === ALL_VERSIONS;
    const lineSplitOpenId = this.lineSplitState?.invoiceId || null;
    const invoiceSplitOpenId = this.invoiceSplitState?.invoiceId || null;
    const invoiceMoveOpenId = this.invoiceMoveState?.invoiceId || null;
    const splitLoading = this.lineSplitState?.loadingThresholds === true;
    const splitError = this.lineSplitState?.thresholdsError || "";

    return (this.preview?.invoices || [])
      .map((invoice, index) => {
        const invoiceId = invoice.invoiceId;
        const isLineSplitOpen = lineSplitOpenId === invoiceId;
        const isInvoiceSplitOpen = invoiceSplitOpenId === invoiceId;
        const isInvoiceMoveOpen = invoiceMoveOpenId === invoiceId;
        const canEditInvoice = this.canEdit && invoice.locked !== true;
        const moveTargetOptions = isInvoiceMoveOpen
          ? this.buildMoveTargetOptions(invoice)
          : [];
        const sourceLines = invoice.lines || [];
        const lines = sourceLines
          .filter(
            (line) => filterAll || this.lineMatchesVersion(line, selected)
          )
          .map((line, lineIndex) => {
            const lineId = line.lineId;
            const savedAmount = Number(line.amount ?? 0);
            const amount = this.isLineDrafted(lineId)
              ? Number(this.amountDrafts[lineId] ?? 0)
              : savedAmount;
            const hasSourceAmount = line.sourceAmountTotal != null;
            const sourceAmountTotal = hasSourceAmount
              ? Number(line.sourceAmountTotal ?? 0)
              : null;
            // 円は整数。IEEE754 の誤差で偽の「ずれあり／なし」にしない
            const amountDeltaFromSource = hasSourceAmount
              ? Math.round(amount - sourceAmountTotal)
              : null;
            const hasAmountDrift =
              hasSourceAmount && amountDeltaFromSource !== 0;
            const isRecurring = line.isRecurring === true;
            const unitPrice = Number(line.unitPrice ?? 0);
            const quantity = Number(line.quantity ?? 0);
            const splitRow =
              isLineSplitOpen
                ? this.lineSplitState?.rows?.[lineId] || null
                : null;
            const splitSelected = splitRow?.selected === true;
            const activeSplitLineId = isLineSplitOpen
              ? Object.keys(this.lineSplitState?.rows || {}).find(
                  (id) => this.lineSplitState.rows[id]?.selected === true
                ) || null
              : null;
            const splitBusyOther =
              activeSplitLineId != null && activeSplitLineId !== lineId;
            const thresholdOptions =
              isLineSplitOpen
                ? this.lineSplitState?.thresholdsByLineId?.[lineId] || []
                : [];
            const kindOptions = this.buildSplitKindOptions(
              isRecurring,
              thresholdOptions
            );
            const splitKind = this.resolveSplitKind(
              splitRow?.kind,
              kindOptions
            );
            const moveUnitPriceRaw = splitRow?.moveUnitPrice;
            const moveQuantityRaw = splitRow?.moveQuantity;
            const moveUnitPriceNum = this.parseOptionalNumber(moveUnitPriceRaw);
            const moveQuantityNum = this.parseOptionalNumber(moveQuantityRaw);
            const remainUnitPrice =
              moveUnitPriceNum == null
                ? null
                : this.roundMoney2(unitPrice - moveUnitPriceNum);
            const remainQuantity =
              moveQuantityNum == null
                ? null
                : this.roundMoney2(quantity - moveQuantityNum);
            const invoiceMoveSelected =
              (isInvoiceSplitOpen &&
                this.invoiceSplitState?.selected?.[lineId] === true) ||
              (isInvoiceMoveOpen &&
                this.invoiceMoveState?.selected?.[lineId] === true);
            return {
              key: lineId || line.lineMergeKey || `line-${index}-${lineIndex}`,
              splitControlsKey: `${lineId || line.lineMergeKey || `line-${index}-${lineIndex}`}-split`,
              lineId,
              productName: line.productName || "—",
              versionLabel: line.historyVersionLabel || "—",
              unitPrice,
              unit: line.unit || "—",
              quantity,
              periodLabel: line.periodLabel || "—",
              cycleCountLabel: line.cycleCountLabel || "—",
              isRecurring,
              amount,
              isAmountDrafted: this.isLineDrafted(lineId),
              isManuallyAdjusted:
                line.isManuallyAdjusted === true || this.isLineDrafted(lineId),
              showAmountMeta:
                line.isManuallyAdjusted === true ||
                this.isLineDrafted(lineId) ||
                hasSourceAmount,
              hasSourceAmount,
              sourceAmountTotal,
              amountDeltaFromSource,
              hasAmountDrift,
              amountDriftClass: hasAmountDrift
                ? "line-drift line-drift_warn"
                : "line-drift line-drift_ok",
              amountDriftLabel: !hasSourceAmount
                ? ""
                : hasAmountDrift
                  ? `端数あり ${this.formatSignedYen(amountDeltaFromSource)}`
                  : "端数なし",
              integratedAmount: line.integratedAmount ?? 0,
              clearedAmount: line.clearedAmount ?? 0,
              openAmount: line.openAmount ?? 0,
              invoiceMoveSelected,
              showRowSplitAction:
                canEditInvoice && !isInvoiceSplitOpen && !isInvoiceMoveOpen,
              rowSplitActionClass: splitSelected
                ? "amount-chip amount-chip_split amount-chip_split-active"
                : "amount-chip amount-chip_split",
              rowSplitDisabled:
                this.hasAmountDrafts ||
                this.isSaving ||
                invoice.locked === true ||
                splitBusyOther,
              rowSplitTitle: splitBusyOther
                ? "編集中の分割をキャンセルまたは実行してから操作してください"
                : this.hasAmountDrafts
                  ? "端数調整の保存または取消後に操作できます"
                  : invoice.locked === true
                    ? "この請求は連携済または消込済のため編集できません。"
                    : "",
              splitSelected,
              splitKind,
              splitKindOptions: kindOptions.map((option) => ({
                ...option,
                key: `${lineId}-${option.value}`,
                buttonClass:
                  option.value === splitKind
                    ? "split-kind-btn split-kind-btn_active"
                    : "split-kind-btn"
              })),
              splitShowPeriod: splitKind === KIND_PERIOD,
              splitShowUnitPrice: splitKind === KIND_UNIT_PRICE,
              splitShowQuantity: splitKind === KIND_QUANTITY,
              splitThresholdOptions: thresholdOptions,
              splitThresholdDate: splitRow?.thresholdDate || "",
              splitMoveUnitPrice:
                moveUnitPriceRaw == null ? "" : moveUnitPriceRaw,
              splitMoveQuantity:
                moveQuantityRaw == null ? "" : moveQuantityRaw,
              splitOriginalUnitPriceLabel: this.formatPlainNumber(unitPrice),
              splitOriginalQuantityLabel: this.formatPlainNumber(quantity),
              splitRemainUnitPriceLabel:
                remainUnitPrice == null
                  ? "—"
                  : this.formatPlainNumber(remainUnitPrice),
              splitRemainQuantityLabel:
                remainQuantity == null
                  ? "—"
                  : this.formatPlainNumber(remainQuantity),
              splitRowValid: this.isSplitRowValid({
                selected: splitSelected,
                kind: splitKind,
                thresholdDate: splitRow?.thresholdDate || "",
                moveUnitPrice: moveUnitPriceRaw,
                moveQuantity: moveQuantityRaw,
                unitPrice,
                quantity,
                kindOptions
              }),
              splitConfirmDisabled:
                this.isSaving ||
                this.lineSplitState?.loadingThresholds === true ||
                !this.isSplitRowValid({
                  selected: splitSelected,
                  kind: splitKind,
                  thresholdDate: splitRow?.thresholdDate || "",
                  moveUnitPrice: moveUnitPriceRaw,
                  moveQuantity: moveQuantityRaw,
                  unitPrice,
                  quantity,
                  kindOptions
                })
            };
          });

        if (lines.length === 0) {
          return null;
        }

        const hasDraftInInvoice = lines.some((line) => line.isAmountDrafted);
        // 全明細が残るならヘッダバケツを正（Version 絞り込み含む。標準は 1請求=1 Version）。
        // 一部行だけのとき（端数ドラフト／混在 Version＋フィルタ間引き）は行按分の足し戻し。
        // 後者の HALF_UP 端数ずれは仕様上許容（§6.9）。
        const totals =
          lines.length === sourceLines.length && !hasDraftInInvoice
            ? {
                amountTotal: invoice.amountTotal ?? 0,
                taxTotal: invoice.taxTotal ?? 0,
                integratedAmount: invoice.integratedAmount ?? 0,
                clearedAmount: invoice.clearedAmount ?? 0,
                openAmount: invoice.openAmount ?? 0
              }
            : this.sumLineTotals(lines, invoice.taxPercent);

        const isBillingEditOpen =
          this.billingEditState?.invoiceId === invoiceId;
        const showSplitSelectCol = isInvoiceSplitOpen || isInvoiceMoveOpen;
        const hasLineSplitSelection = lines.some(
          (line) => line.splitSelected === true
        );
        const hasValidSplitSelection = lines.some(
          (line) => line.splitRowValid === true
        );
        const hasInvoiceMoveSelection = lines.some(
          (line) => line.invoiceMoveSelected === true
        );
        const selectedMoveLineCount = lines.filter(
          (line) => line.invoiceMoveSelected === true
        ).length;
        const amountTotal = totals.amountTotal || 0;
        const invoiceSplitMoveTotal = lines.reduce((sum, line) => {
          if (line.invoiceMoveSelected !== true) {
            return sum;
          }
          return sum + (Number(line.amount) || 0);
        }, 0);
        const invoiceSplitRemainTotal = amountTotal - invoiceSplitMoveTotal;
        const invoiceSplitEquationOk = invoiceSplitMoveTotal > 0;
        const willEmptySourceOnMove =
          isInvoiceMoveOpen &&
          hasInvoiceMoveSelection &&
          selectedMoveLineCount >= lines.length;
        const canMoveLines =
          canEditInvoice && this.buildMoveTargetOptions(invoice).length > 0;
        const taxTotal = totals.taxTotal || 0;
        const taxInclusiveTotal = amountTotal + taxTotal;
        const toTaxInclusive = (exclusiveAmount) =>
          this.toTaxInclusiveAmount(
            exclusiveAmount,
            amountTotal,
            taxInclusiveTotal,
            invoice.taxPercent
          );

        return {
          key: invoiceId || invoice.mergeKey || `invoice-${index}`,
          invoiceId,
          invoiceName: invoice.invoiceName || "—",
          recordUrl: invoiceId
            ? `/lightning/r/Invoice__c/${invoiceId}/view`
            : "",
          invoiceDate: invoice.invoiceDate || "—",
          paymentScheduledDate: invoice.paymentScheduledDate || "—",
          lineCountLabel: `${lines.length}`,
          amountTotal,
          taxTotal,
          taxInclusiveTotal,
          integratedAmount: totals.integratedAmount,
          clearedAmount: totals.clearedAmount,
          openAmount: totals.openAmount,
          openAmountIncl: toTaxInclusive(totals.openAmount),
          integratedAmountIncl: toTaxInclusive(totals.integratedAmount),
          clearedAmountIncl: toTaxInclusive(totals.clearedAmount),
          isManuallyAdjusted: invoice.isManuallyAdjusted === true,
          billingAccountId: invoice.billingAccountId || "",
          billingAccountName: invoice.billingAccountName || "—",
          billingAddressee: invoice.billingAddressee || "—",
          paymentTerm: invoice.paymentTerm || "",
          isInvoiceSplitOpen,
          isInvoiceMoveOpen,
          isLineSplitOpen,
          showSplitSelectCol,
          showLineSplitActionBar: isLineSplitOpen && hasLineSplitSelection,
          // V〜金額の8列（選択列があるときは+1）。行操作列は廃止済み。
          splitControlsColspan: showSplitSelectCol ? 9 : 8,
          lineSplitLoading: isLineSplitOpen && splitLoading,
          lineSplitError: isLineSplitOpen ? splitError : "",
          lineSplitConfirmDisabled:
            !isLineSplitOpen ||
            splitLoading ||
            Boolean(splitError) ||
            !hasValidSplitSelection ||
            this.isSaving === true,
          invoiceSplitRemainTotal,
          invoiceSplitMoveTotal,
          invoiceSplitEquationOk,
          invoiceSplitNewInvoiceDate: isInvoiceSplitOpen
            ? this.invoiceSplitState.newInvoiceDate || ""
            : "",
          invoiceSplitNewPaymentDate: isInvoiceSplitOpen
            ? this.invoiceSplitState.newPaymentDate || ""
            : "",
          invoiceSplitNewBillingAccountId: isInvoiceSplitOpen
            ? this.invoiceSplitState.newBillingAccountId || ""
            : "",
          invoiceSplitAllowOtherAccountBilling:
            isInvoiceSplitOpen &&
            this.invoiceSplitState.allowOtherAccountBilling === true,
          invoiceSplitConfirmDisabled:
            !isInvoiceSplitOpen ||
            !this.invoiceSplitState?.newInvoiceDate ||
            !this.invoiceSplitState?.newBillingAccountId ||
            !hasInvoiceMoveSelection ||
            this.isSaving === true,
          invoiceMoveTargetOptions: moveTargetOptions,
          invoiceMoveTargetInvoiceId: isInvoiceMoveOpen
            ? this.invoiceMoveState?.targetInvoiceId || ""
            : "",
          invoiceMoveRemainTotal: invoiceSplitRemainTotal,
          invoiceMoveMoveTotal: invoiceSplitMoveTotal,
          invoiceMoveEquationOk: invoiceSplitEquationOk,
          invoiceMoveWillEmptySource: willEmptySourceOnMove,
          invoiceMoveConfirmDisabled:
            !isInvoiceMoveOpen ||
            !this.invoiceMoveState?.targetInvoiceId ||
            !hasInvoiceMoveSelection ||
            this.isSaving === true,
          canMoveLines,
          moveLinesDisabled:
            this.hasAmountDrafts ||
            invoice.locked === true ||
            !canMoveLines,
          moveLinesTitle: this.hasAmountDrafts
            ? "端数調整の保存または取消後に操作できます"
            : invoice.locked === true
              ? "この請求は連携済または消込済のため編集できません。"
              : !canMoveLines
                ? "同じ Version に移せる未ロックの請求がありません"
                : "",
          isBillingEditOpen,
          locked: invoice.locked === true,
          canEditInvoice,
          canAdjustAmount: this.canEdit && invoice.locked !== true,
          lockNote:
            invoice.locked === true
              ? "この請求は連携済または消込済のため編集できません。"
              : "",
          billingEditDisabled:
            this.hasAmountDrafts || invoice.locked === true,
          billingEditTitle: this.hasAmountDrafts
            ? "端数調整の保存または取消後に操作できます"
            : invoice.locked === true
              ? "この請求は連携済または消込済のため編集できません。"
              : "",
          otherActionsDisabled:
            this.hasAmountDrafts || invoice.locked === true,
          otherActionsTitle: this.hasAmountDrafts
            ? "端数調整の保存または取消後に操作できます"
            : invoice.locked === true
              ? "この請求は連携済または消込済のため編集できません。"
              : "",
          draftInvoiceDate: isBillingEditOpen
            ? this.billingEditState.invoiceDate
            : invoice.invoiceDate || "",
          draftPaymentScheduledDate: isBillingEditOpen
            ? this.billingEditState.paymentScheduledDate
            : invoice.paymentScheduledDate || "",
          draftBillingAddressee: isBillingEditOpen
            ? this.billingEditState.billingAddressee
            : invoice.billingAddressee || "",
          draftBillingEmailTo: isBillingEditOpen
            ? this.billingEditState.billingEmailTo
            : invoice.billingEmailTo || "",
          draftBillingEmailCc: isBillingEditOpen
            ? this.billingEditState.billingEmailCc
            : invoice.billingEmailCc || "",
          draftBillingEmailBcc: isBillingEditOpen
            ? this.billingEditState.billingEmailBcc
            : invoice.billingEmailBcc || "",
          draftTaxPercent: isBillingEditOpen
            ? this.billingEditState.taxPercent
            : invoice.taxPercent == null || invoice.taxPercent === ""
              ? 0
              : Number(invoice.taxPercent),
          lines
        };
      })
      .filter(Boolean);
  }

  handleVersionChange(event) {
    this.selectedVersion = event.detail.value;
  }

  async handleResetPostOrderClick() {
    if (!this.showResetPostOrderButton || this.resetPostOrderDisabled) {
      return;
    }
    const confirmed = await LightningConfirm.open({
      label: "受注直後の請求に戻す",
      message:
        "この Version の請求書・請求明細を、受注直後の状態に作り直します。分割や端数・請求日などの手直しはすべて消えます。よろしいですか？",
      theme: "warning",
      variant: "header"
    });
    if (!confirmed) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("resetpostorder", {
        detail: {
          versionValue: String(this.selectedVersion)
        }
      })
    );
  }

  isLineDrafted(lineId) {
    return (
      lineId != null &&
      Object.prototype.hasOwnProperty.call(this.amountDrafts || {}, lineId)
    );
  }

  draftAmountDeltaForSelection() {
    const selected = this.selectedVersion;
    const filterAll = selected === ALL_VERSIONS;
    let delta = 0;

    for (const invoice of this.preview?.invoices || []) {
      for (const line of invoice.lines || []) {
        const lineId = line.lineId;
        if (!this.isLineDrafted(lineId)) {
          continue;
        }
        if (!filterAll && !this.lineMatchesVersion(line, selected)) {
          continue;
        }
        const saved = Number(line.amount ?? 0);
        const draft = Number(this.amountDrafts[lineId] ?? 0);
        delta += draft - saved;
      }
    }
    return delta;
  }

  sumSavedInvoiceAmountForVersion(selected) {
    let total = 0;
    for (const invoice of this.preview?.invoices || []) {
      for (const line of invoice.lines || []) {
        if (!this.lineMatchesVersion(line, selected)) {
          continue;
        }
        total += Number(line.amount ?? 0);
      }
    }
    return total;
  }

  handleAdjustAmount(event) {
    if (!this.canEdit || this.isSaving) {
      return;
    }
    const lineId = event.currentTarget.dataset.lineId;
    const delta = Number(event.currentTarget.dataset.delta || 0);
    if (!lineId || !delta) {
      return;
    }
    const saved = this.findLineAmount(lineId);
    const current = this.isLineDrafted(lineId)
      ? Number(this.amountDrafts[lineId] ?? 0)
      : saved;
    // マイナス明細（Change 打消し等）も 0 に潰さず加減算する
    const next = current + delta;
    if (next === current) {
      return;
    }
    if (next === saved) {
      const nextDrafts = { ...this.amountDrafts };
      delete nextDrafts[lineId];
      this.amountDrafts = nextDrafts;
      return;
    }
    this.amountDrafts = {
      ...this.amountDrafts,
      [lineId]: next
    };
  }

  handleDiscardAmountDrafts() {
    this.amountDrafts = {};
  }

  handleSaveAmountDrafts() {
    if (!this.hasAmountDrafts || this.isSaving) {
      return;
    }
    const edits = Object.keys(this.amountDrafts).map((lineId) => ({
      lineId,
      amount: this.amountDrafts[lineId]
    }));
    this.dispatchEvent(
      new CustomEvent("savelineamounts", {
        detail: { edits }
      })
    );
  }

  findLineAmount(lineId) {
    for (const invoice of this.preview?.invoices || []) {
      for (const line of invoice.lines || []) {
        if (line.lineId === lineId) {
          return Number(line.amount ?? 0);
        }
      }
    }
    return 0;
  }

  findInvoice(invoiceId) {
    return (this.preview?.invoices || []).find(
      (row) => row.invoiceId === invoiceId
    );
  }

  findLine(lineId) {
    for (const invoice of this.preview?.invoices || []) {
      for (const line of invoice.lines || []) {
        if (line.lineId === lineId) {
          return line;
        }
      }
    }
    return null;
  }

  isInvoiceLocked(invoiceId) {
    return this.findInvoice(invoiceId)?.locked === true;
  }

  buildSplitKindOptions(isRecurring, thresholdOptions) {
    const options = [];
    if (isRecurring && (thresholdOptions || []).length >= 1) {
      options.push({ label: "日付", value: KIND_PERIOD });
    }
    options.push({ label: "単価", value: KIND_UNIT_PRICE });
    options.push({ label: "数量", value: KIND_QUANTITY });
    return options;
  }

  resolveSplitKind(kind, kindOptions) {
    const values = new Set((kindOptions || []).map((row) => row.value));
    if (kind && values.has(kind)) {
      return kind;
    }
    return kindOptions?.[0]?.value || KIND_UNIT_PRICE;
  }

  parseOptionalNumber(raw) {
    if (raw === "" || raw == null) {
      return null;
    }
    const n = Number(raw);
    return Number.isFinite(n) ? n : null;
  }

  roundMoney2(value) {
    return Math.round((Number(value) || 0) * 100) / 100;
  }

  /** しきい日候補は期間表示ではなく日付（例: 2026/6/1）。 */
  formatThresholdDateLabel(value) {
    const raw = String(value || "").trim();
    const match = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!match) {
      return raw;
    }
    return `${Number(match[1])}/${Number(match[2])}/${Number(match[3])}`;
  }

  formatPlainNumber(value) {
    const n = this.roundMoney2(value);
    return n.toLocaleString("ja-JP", {
      minimumFractionDigits: 0,
      maximumFractionDigits: 2
    });
  }

  defaultMoveHalf(original) {
    return this.roundMoney2(Number(original || 0) / 2);
  }

  buildFactorDefaults(line, kind) {
    if (kind === KIND_UNIT_PRICE) {
      return {
        moveUnitPrice: String(this.defaultMoveHalf(line?.unitPrice)),
        moveQuantity: ""
      };
    }
    if (kind === KIND_QUANTITY) {
      return {
        moveUnitPrice: "",
        moveQuantity: String(this.defaultMoveHalf(line?.quantity))
      };
    }
    return {
      moveUnitPrice: "",
      moveQuantity: ""
    };
  }

  isSplitRowValid({
    selected,
    kind,
    thresholdDate,
    moveUnitPrice,
    moveQuantity,
    unitPrice,
    quantity,
    kindOptions
  }) {
    if (selected !== true) {
      return false;
    }
    const resolvedKind = this.resolveSplitKind(kind, kindOptions);
    if (resolvedKind === KIND_PERIOD) {
      return Boolean(thresholdDate);
    }
    if (resolvedKind === KIND_UNIT_PRICE) {
      const move = this.parseOptionalNumber(moveUnitPrice);
      if (move == null) {
        return false;
      }
      const moveRounded = this.roundMoney2(move);
      const remain = this.roundMoney2(unitPrice - moveRounded);
      const original = this.roundMoney2(unitPrice);
      return (
        moveRounded !== 0 &&
        remain !== 0 &&
        this.roundMoney2(moveRounded + remain) === original
      );
    }
    if (resolvedKind === KIND_QUANTITY) {
      const move = this.parseOptionalNumber(moveQuantity);
      if (move == null) {
        return false;
      }
      const moveRounded = this.roundMoney2(move);
      const remain = this.roundMoney2(quantity - moveRounded);
      const original = this.roundMoney2(quantity);
      return (
        moveRounded !== 0 &&
        remain !== 0 &&
        this.roundMoney2(moveRounded + remain) === original
      );
    }
    return false;
  }

  handleOpenInvoiceSplit(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    if (this.hasAmountDrafts || this.isInvoiceLocked(invoiceId)) {
      return;
    }
    this.billingEditState = null;
    this.lineSplitState = null;
    this.invoiceMoveState = null;
    const invoice = this.findInvoice(invoiceId);
    const invoiceDate =
      invoice?.invoiceDate && invoice.invoiceDate !== "—"
        ? invoice.invoiceDate
        : "";
    const paymentDate =
      invoice?.paymentScheduledDate && invoice.paymentScheduledDate !== "—"
        ? invoice.paymentScheduledDate
        : "";
    this.invoiceSplitState = {
      invoiceId,
      newInvoiceDate: invoiceDate,
      newPaymentDate: paymentDate,
      newBillingAccountId: invoice?.billingAccountId || "",
      allowOtherAccountBilling: false,
      selected: {}
    };
  }

  handleCloseInvoiceSplit() {
    this.invoiceSplitState = null;
  }

  handleOpenInvoiceMove(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    if (this.hasAmountDrafts || this.isInvoiceLocked(invoiceId)) {
      return;
    }
    const invoice = this.findInvoice(invoiceId);
    const targets = this.buildMoveTargetOptions(invoice);
    if (targets.length === 0) {
      return;
    }
    this.billingEditState = null;
    this.lineSplitState = null;
    this.invoiceSplitState = null;
    this.invoiceMoveState = {
      invoiceId,
      targetInvoiceId: targets[0].value,
      selected: {}
    };
  }

  handleCloseInvoiceMove() {
    this.invoiceMoveState = null;
  }

  handleInvoiceMoveTargetChange(event) {
    if (!this.invoiceMoveState) {
      return;
    }
    this.invoiceMoveState = {
      ...this.invoiceMoveState,
      targetInvoiceId: event.detail.value || ""
    };
  }

  buildMoveTargetOptions(sourceInvoice) {
    if (!sourceInvoice?.invoiceId) {
      return [];
    }
    const sourceVersion =
      sourceInvoice.historyVersion == null
        ? null
        : String(sourceInvoice.historyVersion);
    return (this.preview?.invoices || [])
      .filter((invoice) => {
        if (!invoice?.invoiceId || invoice.invoiceId === sourceInvoice.invoiceId) {
          return false;
        }
        if (invoice.locked === true) {
          return false;
        }
        const version =
          invoice.historyVersion == null
            ? null
            : String(invoice.historyVersion);
        return sourceVersion == null || version === sourceVersion;
      })
      .map((invoice) => {
        const dateLabel =
          invoice.invoiceDate && invoice.invoiceDate !== "—"
            ? invoice.invoiceDate
            : "請求日未設定";
        const name = invoice.invoiceName || invoice.invoiceId;
        const amountLabel = this.formatYen(invoice.amountTotal ?? 0);
        return {
          label: `${name} / ${dateLabel} / ${amountLabel}`,
          value: invoice.invoiceId
        };
      });
  }

  formatYen(amount) {
    const n = Number(amount);
    if (!Number.isFinite(n)) {
      return "¥0";
    }
    return `¥${Math.round(n).toLocaleString("ja-JP")}`;
  }

  handleInvoiceSplitDateChange(event) {
    if (!this.invoiceSplitState) {
      return;
    }
    this.invoiceSplitState = {
      ...this.invoiceSplitState,
      newInvoiceDate: event.detail.value
    };
  }

  handleInvoiceSplitPaymentChange(event) {
    if (!this.invoiceSplitState) {
      return;
    }
    this.invoiceSplitState = {
      ...this.invoiceSplitState,
      newPaymentDate: event.detail.value
    };
  }

  handleInvoiceSplitBillingAccountChange(event) {
    if (!this.invoiceSplitState) {
      return;
    }
    this.invoiceSplitState = {
      ...this.invoiceSplitState,
      newBillingAccountId: event.detail.value || ""
    };
  }

  handleInvoiceSplitBillingAccountPickerChange(event) {
    if (!this.invoiceSplitState) {
      return;
    }
    this.invoiceSplitState = {
      ...this.invoiceSplitState,
      newBillingAccountId: event.detail.recordId || ""
    };
  }

  handleInvoiceSplitAllowOtherAccountBillingChange(event) {
    if (!this.invoiceSplitState) {
      return;
    }
    const allowOther = event.target.checked === true;
    let nextBillingAccountId = this.invoiceSplitState.newBillingAccountId || "";
    if (!allowOther) {
      nextBillingAccountId = this.resolveRelatedBillingAccountId(
        this.invoiceSplitState.invoiceId,
        nextBillingAccountId
      );
    }
    this.invoiceSplitState = {
      ...this.invoiceSplitState,
      allowOtherAccountBilling: allowOther,
      newBillingAccountId: nextBillingAccountId
    };
  }

  resolveRelatedBillingAccountId(invoiceId, currentId) {
    const relatedIds = new Set(
      this.relatedBillingAccountOptions.map((row) => row.value)
    );
    const sourceInvoice = this.findInvoice(invoiceId);
    if (sourceInvoice?.billingAccountId) {
      relatedIds.add(sourceInvoice.billingAccountId);
    }
    if (currentId && relatedIds.has(currentId)) {
      return currentId;
    }
    return sourceInvoice?.billingAccountId || "";
  }

  handleInvoiceSplitToggle(event) {
    const lineId = event.target.dataset.lineId;
    if (!lineId) {
      return;
    }
    const checked = event.target.checked === true;
    if (this.invoiceSplitState) {
      this.invoiceSplitState = {
        ...this.invoiceSplitState,
        selected: {
          ...this.invoiceSplitState.selected,
          [lineId]: checked
        }
      };
      return;
    }
    if (this.invoiceMoveState) {
      this.invoiceMoveState = {
        ...this.invoiceMoveState,
        selected: {
          ...this.invoiceMoveState.selected,
          [lineId]: checked
        }
      };
    }
  }

  async handleConfirmInvoiceSplit() {
    if (!this.invoiceSplitState?.invoiceId || this.isSaving) {
      return;
    }
    if (!this.invoiceSplitState.newInvoiceDate) {
      return;
    }
    if (!this.invoiceSplitState.newBillingAccountId) {
      return;
    }
    const invoice = this.findInvoice(this.invoiceSplitState.invoiceId);
    const selectedLines = (invoice?.lines || []).filter(
      (line) =>
        line?.lineId &&
        this.invoiceSplitState.selected?.[line.lineId] === true
    );
    const splitLines = selectedLines
      .map((line) => ({
        lineId: line.lineId,
        moveAmount: Number(line.amount ?? 0)
      }))
      .filter((row) => row.moveAmount !== 0);
    if (splitLines.length === 0) {
      return;
    }
    if (selectedLines.length >= (invoice?.lines || []).length) {
      const confirmed = await LightningConfirm.open({
        label: "請求を分ける",
        message:
          "選択した明細をすべて移すため、元の請求書は削除されます。よろしいですか？",
        theme: "warning",
        variant: "header"
      });
      if (!confirmed) {
        return;
      }
    }
    const sourceBillingAccountId = invoice?.billingAccountId || "";
    const newBillingAccountId =
      this.invoiceSplitState.newBillingAccountId || "";
    const changedBillingAccount =
      Boolean(newBillingAccountId) &&
      newBillingAccountId !== sourceBillingAccountId;
    this.dispatchEvent(
      new CustomEvent("splitinvoice", {
        detail: {
          mode: changedBillingAccount ? "billingAccount" : "date",
          sourceInvoiceId: this.invoiceSplitState.invoiceId,
          newInvoiceDate: this.invoiceSplitState.newInvoiceDate || null,
          newPaymentScheduledDate:
            this.invoiceSplitState.newPaymentDate || null,
          newBillingAccountId: changedBillingAccount
            ? newBillingAccountId
            : null,
          splitLines
        }
      })
    );
    this.invoiceSplitState = null;
  }

  async handleConfirmInvoiceMove() {
    if (!this.invoiceMoveState?.invoiceId || this.isSaving) {
      return;
    }
    if (!this.invoiceMoveState.targetInvoiceId) {
      return;
    }
    const invoice = this.findInvoice(this.invoiceMoveState.invoiceId);
    const lineIds = (invoice?.lines || [])
      .filter(
        (line) =>
          line?.lineId &&
          this.invoiceMoveState.selected?.[line.lineId] === true
      )
      .map((line) => line.lineId);
    if (lineIds.length === 0) {
      return;
    }
    if (lineIds.length >= (invoice?.lines || []).length) {
      const confirmed = await LightningConfirm.open({
        label: "明細を移す",
        message:
          "選択した明細をすべて移すため、元の請求書は削除されます。よろしいですか？",
        theme: "warning",
        variant: "header"
      });
      if (!confirmed) {
        return;
      }
    }
    this.dispatchEvent(
      new CustomEvent("movelines", {
        detail: {
          sourceInvoiceId: this.invoiceMoveState.invoiceId,
          targetInvoiceId: this.invoiceMoveState.targetInvoiceId,
          lineIds
        }
      })
    );
    this.invoiceMoveState = null;
  }

  async handleRowSplitClick(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    const lineId = event.currentTarget.dataset.lineId;
    if (
      !invoiceId ||
      !lineId ||
      this.hasAmountDrafts ||
      this.isInvoiceLocked(invoiceId) ||
      this.isSaving
    ) {
      return;
    }
    this.billingEditState = null;
    this.invoiceSplitState = null;
    this.invoiceMoveState = null;

    if (this.lineSplitState?.invoiceId === invoiceId) {
      const current = this.lineSplitState.rows?.[lineId];
      if (current?.selected === true) {
        this.updateLineSplitRow(lineId, { selected: false });
        return;
      }
      const activeOther = Object.keys(this.lineSplitState.rows || {}).find(
        (id) =>
          id !== lineId && this.lineSplitState.rows[id]?.selected === true
      );
      if (activeOther) {
        return;
      }
      this.selectLineForSplit(lineId);
      return;
    }

    await this.ensureLineSplitState(invoiceId);
    if (
      !this.lineSplitState ||
      this.lineSplitState.invoiceId !== invoiceId
    ) {
      return;
    }
    this.selectLineForSplit(lineId);
  }

  async ensureLineSplitState(invoiceId) {
    if (
      this.lineSplitState?.invoiceId === invoiceId &&
      !this.lineSplitState.loadingThresholds
    ) {
      return;
    }
    const invoice = this.findInvoice(invoiceId);
    const rows = {};
    (invoice?.lines || []).forEach((line) => {
      if (!line?.lineId) {
        return;
      }
      rows[line.lineId] = {
        selected: false,
        kind: KIND_UNIT_PRICE,
        thresholdDate: "",
        moveUnitPrice: "",
        moveQuantity: ""
      };
    });
    this.lineSplitState = {
      invoiceId,
      loadingThresholds: true,
      thresholdsError: "",
      thresholdsByLineId: {},
      rows
    };
    try {
      const optionRows = await getSplitThresholdDateOptions({ invoiceId });
      if (
        !this.lineSplitState ||
        this.lineSplitState.invoiceId !== invoiceId
      ) {
        return;
      }
      const thresholdsByLineId = {};
      (optionRows || []).forEach((row) => {
        if (!row?.invoiceLineId) {
          return;
        }
        thresholdsByLineId[row.invoiceLineId] = (row.options || []).map(
          (option) => ({
            label: this.formatThresholdDateLabel(option.value),
            value: option.value
          })
        );
      });
      const nextRows = { ...this.lineSplitState.rows };
      Object.keys(nextRows).forEach((rowLineId) => {
        const line = this.findLine(rowLineId);
        const kindOptions = this.buildSplitKindOptions(
          line?.isRecurring === true,
          thresholdsByLineId[rowLineId] || []
        );
        nextRows[rowLineId] = {
          ...nextRows[rowLineId],
          kind: this.resolveSplitKind(nextRows[rowLineId].kind, kindOptions)
        };
      });
      this.lineSplitState = {
        ...this.lineSplitState,
        loadingThresholds: false,
        thresholdsError: "",
        thresholdsByLineId,
        rows: nextRows
      };
    } catch (error) {
      if (
        !this.lineSplitState ||
        this.lineSplitState.invoiceId !== invoiceId
      ) {
        return;
      }
      const message =
        error?.body?.message ||
        error?.message ||
        "分割候補の読み込みに失敗しました。";
      this.lineSplitState = {
        ...this.lineSplitState,
        loadingThresholds: false,
        thresholdsError: message,
        thresholdsByLineId: {},
        rows: this.lineSplitState.rows
      };
    }
  }

  selectLineForSplit(lineId) {
    if (!this.lineSplitState || !lineId) {
      return;
    }
    const activeOther = Object.keys(this.lineSplitState.rows || {}).find(
      (id) =>
        id !== lineId && this.lineSplitState.rows[id]?.selected === true
    );
    if (activeOther) {
      return;
    }
    const line = this.findLine(lineId);
    const thresholdOptions =
      this.lineSplitState.thresholdsByLineId?.[lineId] || [];
    const kindOptions = this.buildSplitKindOptions(
      line?.isRecurring === true,
      thresholdOptions
    );
    const current = this.lineSplitState.rows?.[lineId];
    const kind = this.resolveSplitKind(current?.kind, kindOptions);
    this.updateLineSplitRow(lineId, {
      selected: true,
      kind,
      thresholdDate: current?.thresholdDate || "",
      ...this.buildFactorDefaults(line, kind)
    });
  }

  handleCloseLineSplit() {
    this.lineSplitState = null;
  }

  handleCancelLineSplitRow(event) {
    const lineId = event.currentTarget.dataset.lineId;
    if (!this.lineSplitState || !lineId) {
      return;
    }
    const remaining = Object.keys(this.lineSplitState.rows || {}).some(
      (id) =>
        id !== lineId && this.lineSplitState.rows[id]?.selected === true
    );
    if (remaining) {
      this.updateLineSplitRow(lineId, { selected: false });
      return;
    }
    this.lineSplitState = null;
  }

  updateLineSplitRow(lineId, patch) {
    if (!this.lineSplitState || !lineId) {
      return;
    }
    const current = this.lineSplitState.rows?.[lineId] || {
      selected: false,
      kind: KIND_UNIT_PRICE,
      thresholdDate: "",
      moveUnitPrice: "",
      moveQuantity: ""
    };
    this.lineSplitState = {
      ...this.lineSplitState,
      rows: {
        ...this.lineSplitState.rows,
        [lineId]: {
          ...current,
          ...patch
        }
      }
    };
  }

  handleLineSplitKindClick(event) {
    const lineId = event.currentTarget.dataset.lineId;
    const kind = event.currentTarget.dataset.kind;
    if (!lineId || !kind) {
      return;
    }
    const line = this.findLine(lineId);
    this.updateLineSplitRow(lineId, {
      kind,
      ...this.buildFactorDefaults(line, kind)
    });
  }

  handleLineSplitThresholdChange(event) {
    const lineId = event.target.dataset.lineId;
    this.updateLineSplitRow(lineId, {
      thresholdDate: event.detail.value || ""
    });
  }

  handleLineSplitMoveUnitPriceChange(event) {
    const lineId = event.target.dataset.lineId;
    this.updateLineSplitRow(lineId, {
      moveUnitPrice: event.detail.value
    });
  }

  handleLineSplitMoveQuantityChange(event) {
    const lineId = event.target.dataset.lineId;
    this.updateLineSplitRow(lineId, {
      moveQuantity: event.detail.value
    });
  }

  buildSplitLinesPayload() {
    if (!this.lineSplitState?.invoiceId) {
      return [];
    }
    const invoice = this.findInvoice(this.lineSplitState.invoiceId);
    const payload = [];
    for (const line of invoice?.lines || []) {
      const lineId = line.lineId;
      const row = this.lineSplitState.rows?.[lineId];
      if (!row?.selected) {
        continue;
      }
      const thresholdOptions =
        this.lineSplitState.thresholdsByLineId?.[lineId] || [];
      const kindOptions = this.buildSplitKindOptions(
        line.isRecurring === true,
        thresholdOptions
      );
      const kind = this.resolveSplitKind(row.kind, kindOptions);
      if (
        !this.isSplitRowValid({
          selected: true,
          kind,
          thresholdDate: row.thresholdDate || "",
          moveUnitPrice: row.moveUnitPrice,
          moveQuantity: row.moveQuantity,
          unitPrice: Number(line.unitPrice ?? 0),
          quantity: Number(line.quantity ?? 0),
          kindOptions
        })
      ) {
        continue;
      }
      if (kind === KIND_PERIOD) {
        payload.push({
          lineId,
          splitMode: KIND_PERIOD,
          thresholdDate: row.thresholdDate
        });
        continue;
      }
      if (kind === KIND_UNIT_PRICE) {
        const moveUnitPrice = this.roundMoney2(
          this.parseOptionalNumber(row.moveUnitPrice)
        );
        const remainUnitPrice = this.roundMoney2(
          Number(line.unitPrice ?? 0) - moveUnitPrice
        );
        payload.push({
          lineId,
          splitMode: KIND_UNIT_PRICE,
          remainUnitPrice,
          moveUnitPrice
        });
        continue;
      }
      if (kind === KIND_QUANTITY) {
        const moveQuantity = this.roundMoney2(
          this.parseOptionalNumber(row.moveQuantity)
        );
        const remainQuantity = this.roundMoney2(
          Number(line.quantity ?? 0) - moveQuantity
        );
        payload.push({
          lineId,
          splitMode: KIND_QUANTITY,
          remainQuantity,
          moveQuantity
        });
      }
    }
    return payload;
  }

  handleConfirmLineSplit() {
    if (!this.lineSplitState?.invoiceId || this.isSaving) {
      return;
    }
    if (this.lineSplitState.loadingThresholds) {
      return;
    }
    const splitLines = this.buildSplitLinesPayload();
    if (splitLines.length === 0) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("splitlinesinplace", {
        detail: {
          invoiceId: this.lineSplitState.invoiceId,
          splitLines
        }
      })
    );
  }

  handleOpenBillingEdit(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    if (this.hasAmountDrafts || this.isInvoiceLocked(invoiceId)) {
      return;
    }
    const invoice = this.findInvoice(invoiceId);
    if (!invoice) {
      return;
    }
    this.invoiceSplitState = null;
    this.invoiceMoveState = null;
    this.lineSplitState = null;
    const invoiceDate =
      invoice.invoiceDate && invoice.invoiceDate !== "—"
        ? invoice.invoiceDate
        : "";
    const paymentScheduledDate =
      invoice.paymentScheduledDate && invoice.paymentScheduledDate !== "—"
        ? invoice.paymentScheduledDate
        : "";
    const taxPercent =
      invoice.taxPercent == null || invoice.taxPercent === ""
        ? 0
        : Number(invoice.taxPercent);
    this.billingEditState = {
      invoiceId,
      invoiceDate,
      paymentScheduledDate,
      taxPercent: Number.isFinite(taxPercent) ? taxPercent : 0,
      billingAddressee: invoice.billingAddressee || "",
      billingEmailTo: invoice.billingEmailTo || "",
      billingEmailCc: invoice.billingEmailCc || "",
      billingEmailBcc: invoice.billingEmailBcc || ""
    };
  }

  handleCloseBillingEdit() {
    this.billingEditState = null;
  }

  handleBillingFieldChange(event) {
    if (!this.billingEditState) {
      return;
    }
    const field = event.target.dataset.field;
    if (!field) {
      return;
    }
    this.billingEditState = {
      ...this.billingEditState,
      [field]: event.detail.value
    };
  }

  handleSaveBillingHeader() {
    if (!this.billingEditState?.invoiceId) {
      return;
    }
    if (!this.billingEditState.invoiceDate) {
      return;
    }
    const taxPercentRaw = this.billingEditState.taxPercent;
    const taxPercent =
      taxPercentRaw == null || taxPercentRaw === ""
        ? 0
        : Number(taxPercentRaw);
    if (!Number.isFinite(taxPercent) || taxPercent < 0 || taxPercent > 100) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("savebillingheader", {
        detail: {
          invoiceId: this.billingEditState.invoiceId,
          invoiceDate: this.billingEditState.invoiceDate || null,
          paymentScheduledDate:
            this.billingEditState.paymentScheduledDate || null,
          taxPercent,
          billingAddressee: this.billingEditState.billingAddressee ?? "",
          billingEmailTo: this.billingEditState.billingEmailTo ?? "",
          billingEmailCc: this.billingEditState.billingEmailCc ?? "",
          billingEmailBcc: this.billingEditState.billingEmailBcc ?? ""
        }
      })
    );
    this.billingEditState = null;
  }

  lineMatchesVersion(line, selected) {
    const versions = line.historyVersions || [];
    if (versions.length > 0) {
      return versions.some(
        (version) => String(Number(version)) === String(selected)
      );
    }
    const label = line.historyVersionLabel || "";
    return label
      .split(",")
      .map((part) => part.trim().replace(/^V/i, ""))
      .includes(String(selected));
  }

  sumLineTotals(lines, taxPercent) {
    const totals = lines.reduce(
      (acc, line) => {
        acc.amountTotal += line.amount || 0;
        acc.integratedAmount += line.integratedAmount || 0;
        acc.clearedAmount += line.clearedAmount || 0;
        acc.openAmount += line.openAmount || 0;
        return acc;
      },
      {
        amountTotal: 0,
        taxTotal: 0,
        integratedAmount: 0,
        clearedAmount: 0,
        openAmount: 0
      }
    );
    const resolvedPercent =
      taxPercent == null || taxPercent === "" ? 0 : Number(taxPercent);
    const rate = resolvedPercent > 1 ? resolvedPercent / 100 : resolvedPercent;
    totals.taxTotal = Math.trunc(totals.amountTotal * rate);
    return totals;
  }

  toTaxInclusiveAmount(
    exclusiveAmount,
    amountTotal,
    taxInclusiveTotal,
    taxPercent
  ) {
    const exclusive = Number(exclusiveAmount) || 0;
    if (exclusive === 0) {
      return 0;
    }
    if (exclusive === (Number(amountTotal) || 0)) {
      return Number(taxInclusiveTotal) || 0;
    }
    const resolvedPercent =
      taxPercent == null || taxPercent === "" ? 0 : Number(taxPercent);
    const rate = resolvedPercent > 1 ? resolvedPercent / 100 : resolvedPercent;
    return exclusive + Math.trunc(exclusive * rate);
  }

  /**
   * ネスト overflow（特に overflow-x:auto が y も auto 化するケース）が
   * ホイールを握って動かない問題を避け、外側の実スクローラへ渡す。
   */
  handlePreviewWheel(event) {
    if (!event || event.ctrlKey) {
      return;
    }
    const deltaY = this.resolveWheelDeltaY(event);
    if (!deltaY) {
      return;
    }
    if (this.isNativeScrollField(event.target)) {
      return;
    }
    const host = this.template.host;
    // ホスト内に「今まさに縦へ動ける」要素があるときだけネイティブに任せる
    if (this.hasScrollableRoomBetween(event.target, host, deltaY)) {
      return;
    }
    const scroller = this.findScrollableAncestorOutside();
    if (!scroller) {
      return;
    }
    const before = scroller.scrollTop;
    scroller.scrollTop = before + deltaY;
    event.preventDefault();
  }

  resolveWheelDeltaY(event) {
    // shift+横ホイールを縦として扱う環境向け
    let delta =
      event.shiftKey && event.deltaY === 0 ? event.deltaX : event.deltaY;
    if (!delta) {
      return 0;
    }
    if (event.deltaMode === 1) {
      delta *= 16;
    } else if (event.deltaMode === 2) {
      delta *=
        (document.scrollingElement || document.documentElement).clientHeight ||
        800;
    }
    return delta;
  }

  isNativeScrollField(target) {
    let node = target;
    if (node && node.nodeType === Node.TEXT_NODE) {
      node = node.parentElement;
    }
    while (node && node.nodeType === 1) {
      const tag = node.tagName;
      if (tag === "TEXTAREA" || tag === "SELECT") {
        return true;
      }
      if (node === this.template.host) {
        break;
      }
      const root = node.getRootNode && node.getRootNode();
      node = node.parentElement || (root instanceof ShadowRoot ? root.host : null);
    }
    return false;
  }

  canScrollY(el) {
    if (!el || el.nodeType !== 1) {
      return false;
    }
    const style = getComputedStyle(el);
    const oy = style.overflowY;
    if (oy !== "auto" && oy !== "scroll" && oy !== "overlay") {
      return false;
    }
    return el.scrollHeight > el.clientHeight + 1;
  }

  canScrollInDirection(el, deltaY) {
    if (!this.canScrollY(el)) {
      return false;
    }
    if (deltaY < 0) {
      return el.scrollTop > 0;
    }
    return el.scrollTop + el.clientHeight < el.scrollHeight - 1;
  }

  hasScrollableRoomBetween(start, stop, deltaY) {
    let node = start;
    if (node && node.nodeType === Node.TEXT_NODE) {
      node = node.parentElement;
    }
    while (node && node !== stop) {
      if (this.canScrollInDirection(node, deltaY)) {
        return true;
      }
      const root = node.getRootNode && node.getRootNode();
      if (node.parentElement) {
        node = node.parentElement;
      } else if (root instanceof ShadowRoot && root.host && root.host !== stop) {
        node = root.host;
      } else {
        break;
      }
    }
    return false;
  }

  findScrollableAncestorOutside() {
    let el = this.template.host.parentElement;
    if (!el) {
      const root = this.template.host.getRootNode();
      if (root instanceof ShadowRoot) {
        el = root.host;
      }
    }
    while (el) {
      if (this.canScrollY(el)) {
        return el;
      }
      if (el.parentElement) {
        el = el.parentElement;
      } else {
        const root = el.getRootNode && el.getRootNode();
        if (root instanceof ShadowRoot && root.host) {
          el = root.host;
        } else {
          break;
        }
      }
    }
    return document.scrollingElement || document.documentElement || null;
  }
}
