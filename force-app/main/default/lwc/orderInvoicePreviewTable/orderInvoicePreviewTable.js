import { LightningElement, api, track } from "lwc";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSplitThresholdDateOptions from "@salesforce/apex/OrderCreateController.getSplitThresholdDateOptions";
import {
  resolveScaledNumericInput,
  roundUnitPrice
} from "c/estimateLineItemUtils";

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
  /** 単価分割の数式ポップアップ（見積金額入力と同じ UI） */
  @track unitPriceFormulaLineId = null;
  @track unitPriceFormulaDraft = "";
  @track unitPriceFormulaError = "";
  @track unitPriceFormulaHint = "";

  _preview;
  /** オープン時の Version フィルタ初期値を一度だけ適用したか（保存後の再取得では維持）。 */
  _defaultVersionApplied = false;
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
    this.billingEditState = null;
    this.handleCloseUnitPriceFormula();
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
    // eslint-disable-next-line @lwc/lwc/no-async-operation
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
    this.handleCloseUnitPriceFormula();
    if (this._fitProductNamesRaf != null) {
      cancelAnimationFrame(this._fitProductNamesRaf);
      this._fitProductNamesRaf = null;
    }
    if (this._resizeObserver) {
      this._resizeObserver.disconnect();
      this._resizeObserver = null;
    }
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

  /** 未保存の端数下書きがある間は Version 切替不可（別 Version への黙殺保存を防ぐ）。 */
  get versionFilterDisabled() {
    return this.hasAmountDrafts === true || this.isSaving === true;
  }

  get versionFilterTitle() {
    if (this.hasAmountDrafts) {
      return "端数調整の保存または取消後に Version を切り替えられます";
    }
    return "";
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
    return (
      this.isSaving === true ||
      this.hasAmountDrafts ||
      this.isBillingEditUiOpen ||
      this.isSplitOrMoveUiOpen
    );
  }

  get resetPostOrderTitle() {
    if (this.hasAmountDrafts) {
      return "端数調整の保存または取消後に操作できます";
    }
    if (this.isBillingEditUiOpen) {
      return "請求情報編集をキャンセルまたは保存してから操作できます";
    }
    if (this.isSplitOrMoveUiOpen) {
      return "分ける／移す／分割をキャンセルまたは実行してから操作できます";
    }
    return "この Version の請求を受注直後の状態に作り直します";
  }

  get hasInvoices() {
    return this.invoiceCards.length > 0;
  }

  get canEdit() {
    return (
      this.preview?.canEdit === true &&
      this.preview?.versionEditBlocked !== true
    );
  }

  get showAmountCompare() {
    return this.hasInvoices;
  }

  get hasAmountDrafts() {
    return Object.keys(this.amountDrafts || {}).length > 0;
  }

  /** 請求情報編集パネル表示中。 */
  get isBillingEditUiOpen() {
    return this.billingEditState != null;
  }

  /**
   * 分ける／移す／同一請求内分割の編集中（しきい日ロード中含む）。
   * この間は端数ドラフト不可。閉じたあとの幽霊 lineSplitState は無視。
   */
  get isSplitOrMoveUiOpen() {
    return (
      this.invoiceSplitState != null ||
      this.invoiceMoveState != null ||
      this.hasActiveLineSplitSelection ||
      this.lineSplitState?.loadingThresholds === true
    );
  }

  /** 端数 ± を塞ぐ排他パネル（分割系＋請求情報編集）。 */
  get isAmountAdjustBlocked() {
    return this.isSplitOrMoveUiOpen || this.isBillingEditUiOpen;
  }

  /** 同一請求内分割で明細が選択されているときだけ true（閉じたあとの幽霊 state を無視） */
  get hasActiveLineSplitSelection() {
    const rows = this.lineSplitState?.rows;
    if (!rows) {
      return false;
    }
    return Object.keys(rows).some((id) => rows[id]?.selected === true);
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
            const splitRow = isLineSplitOpen
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
            const thresholdOptions = isLineSplitOpen
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
            const splitThresholdDate = splitRow?.thresholdDate || "";
            const selectedThreshold =
              splitKind === KIND_PERIOD && splitThresholdDate
                ? thresholdOptions.find(
                    (option) => option?.value === splitThresholdDate
                  ) || null
                : null;
            const periodRemainAmount =
              selectedThreshold?.remainAmount == null
                ? null
                : Number(selectedThreshold.remainAmount);
            const periodMoveAmount =
              selectedThreshold?.moveAmount == null
                ? null
                : Number(selectedThreshold.moveAmount);
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
              isAmountAdjusted:
                line.isAmountAdjusted === true || this.isLineDrafted(lineId),
              isSplitMoved: line.isSplitMoved === true,
              // ピルは1つ。端数 > 分割
              showManualTag:
                line.isAmountAdjusted === true ||
                this.isLineDrafted(lineId) ||
                line.isSplitMoved === true,
              manualTagLabel:
                line.isAmountAdjusted === true || this.isLineDrafted(lineId)
                  ? "端数"
                  : "分割",
              manualTagClass:
                line.isAmountAdjusted === true || this.isLineDrafted(lineId)
                  ? "adjusted-pill adjusted-pill_amount"
                  : "adjusted-pill adjusted-pill_split",
              isManuallyAdjusted:
                line.isManuallyAdjusted === true || this.isLineDrafted(lineId),
              showAmountMeta:
                line.isAmountAdjusted === true ||
                line.isSplitMoved === true ||
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
                this.isBillingEditUiOpen ||
                invoice.locked === true ||
                splitBusyOther,
              rowSplitTitle: splitBusyOther
                ? "編集中の分割をキャンセルまたは実行してから操作してください"
                : this.isBillingEditUiOpen
                  ? "請求情報編集をキャンセルまたは保存してから操作できます"
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
              splitThresholdDate,
              splitMoveUnitPrice:
                moveUnitPriceRaw == null ? "" : moveUnitPriceRaw,
              splitMoveUnitPriceLabel:
                moveUnitPriceRaw == null || moveUnitPriceRaw === ""
                  ? "単価を入力..."
                  : this.formatPlainNumber(
                      this.parseOptionalNumber(moveUnitPriceRaw) ??
                        moveUnitPriceRaw
                    ),
              isUnitPriceFormulaOpen:
                this.unitPriceFormulaLineId != null &&
                this.unitPriceFormulaLineId === lineId,
              splitMoveQuantity: moveQuantityRaw == null ? "" : moveQuantityRaw,
              splitRemainAmountLabel:
                periodRemainAmount == null
                  ? "—"
                  : this.formatYen(periodRemainAmount),
              splitMoveAmountLabel:
                periodMoveAmount == null
                  ? "—"
                  : this.formatYen(periodMoveAmount),
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
                thresholdDate: splitThresholdDate,
                moveUnitPrice: moveUnitPriceRaw,
                moveQuantity: moveQuantityRaw,
                unitPrice,
                quantity,
                kindOptions
              }),
              splitConfirmDisabled:
                this.isSaving ||
                this.hasAmountDrafts ||
                this.lineSplitState?.loadingThresholds === true ||
                this.unitPriceFormulaLineId === lineId ||
                !this.isSplitRowValid({
                  selected: splitSelected,
                  kind: splitKind,
                  thresholdDate: splitThresholdDate,
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
        const amountAdjustDisabled =
          this.isSaving === true || this.isAmountAdjustBlocked;
        const amountAdjustBlockedTitle = this.isBillingEditUiOpen
          ? "請求情報編集をキャンセルまたは保存してから端数調整できます"
          : this.isSplitOrMoveUiOpen
            ? "分ける／移す／分割をキャンセルまたは実行してから端数調整できます"
            : this.isSaving === true
              ? "保存中は端数調整できません"
              : "";

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
            this.hasAmountDrafts ||
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
            !this.invoiceSplitState?.newPaymentDate ||
            !this.invoiceSplitState?.newBillingAccountId ||
            !hasInvoiceMoveSelection ||
            !invoiceSplitEquationOk ||
            this.hasAmountDrafts ||
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
            this.hasAmountDrafts ||
            this.isSaving === true,
          canMoveLines,
          moveLinesDisabled:
            this.hasAmountDrafts ||
            this.isBillingEditUiOpen ||
            invoice.locked === true ||
            !canMoveLines,
          moveLinesTitle: this.isBillingEditUiOpen
            ? "請求情報編集をキャンセルまたは保存してから操作できます"
            : this.hasAmountDrafts
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
          amountAdjustDisabled,
          amountAdjustPlus1Title: amountAdjustDisabled
            ? amountAdjustBlockedTitle
            : "1円増やす",
          amountAdjustMinus1Title: amountAdjustDisabled
            ? amountAdjustBlockedTitle
            : "1円減らす",
          amountAdjustPlus10Title: amountAdjustDisabled
            ? amountAdjustBlockedTitle
            : "10円増やす",
          amountAdjustMinus10Title: amountAdjustDisabled
            ? amountAdjustBlockedTitle
            : "10円減らす",
          lockNote:
            invoice.locked === true
              ? "この請求は連携済または消込済のため編集できません。"
              : "",
          billingEditDisabled:
            this.hasAmountDrafts ||
            this.isSplitOrMoveUiOpen ||
            invoice.locked === true,
          billingEditTitle: this.isSplitOrMoveUiOpen
            ? "分ける／移す／分割をキャンセルまたは実行してから操作できます"
            : this.hasAmountDrafts
              ? "端数調整の保存または取消後に操作できます"
              : invoice.locked === true
                ? "この請求は連携済または消込済のため編集できません。"
                : "",
          otherActionsDisabled:
            this.hasAmountDrafts ||
            this.isBillingEditUiOpen ||
            invoice.locked === true,
          otherActionsTitle: this.isBillingEditUiOpen
            ? "請求情報編集をキャンセルまたは保存してから操作できます"
            : this.hasAmountDrafts
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
    const next = event.detail.value;
    if (next === this.selectedVersion) {
      return;
    }
    if (this.hasAmountDrafts || this.isSaving) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "端数調整を先に確定してください",
          message:
            "未保存の端数調整があります。保存または取消してから Version を切り替えてください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    this.selectedVersion = next;
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
    if (!this.canEdit || this.isSaving || this.isAmountAdjustBlocked) {
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
    const n = Number(String(raw).replace(/,/g, "").trim());
    return Number.isFinite(n) ? n : null;
  }

  roundMoney2(value) {
    // 見積・式評価と同じ HALF_UP 小数第2位（Math.round は使わない）
    const rounded = roundUnitPrice(value);
    return Number.isFinite(rounded) ? rounded : 0;
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
    if (
      this.hasAmountDrafts ||
      this.isBillingEditUiOpen ||
      this.isInvoiceLocked(invoiceId)
    ) {
      return;
    }
    this.handleCloseLineSplit();
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
    if (
      this.hasAmountDrafts ||
      this.isBillingEditUiOpen ||
      this.isInvoiceLocked(invoiceId)
    ) {
      return;
    }
    const invoice = this.findInvoice(invoiceId);
    const targets = this.buildMoveTargetOptions(invoice);
    if (targets.length === 0) {
      return;
    }
    this.handleCloseLineSplit();
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
        if (
          !invoice?.invoiceId ||
          invoice.invoiceId === sourceInvoice.invoiceId
        ) {
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
    if (
      !this.invoiceSplitState?.invoiceId ||
      this.isSaving ||
      this.hasAmountDrafts
    ) {
      return;
    }
    if (!this.invoiceSplitState.newInvoiceDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求日を入力してください",
          message: "分割先の請求日は必須です。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    if (!this.invoiceSplitState.newPaymentDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "入金予定日を入力してください",
          message: "分割先の入金予定日は必須です。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    if (!this.invoiceSplitState.newBillingAccountId) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求アカウントを選択してください",
          message: "分割先の請求アカウントは必須です。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    const invoice = this.findInvoice(this.invoiceSplitState.invoiceId);
    const selectedLines = (invoice?.lines || []).filter(
      (line) =>
        line?.lineId && this.invoiceSplitState.selected?.[line.lineId] === true
    );
    const splitLines = selectedLines
      .map((line) => ({
        lineId: line.lineId,
        moveAmount: Number(line.amount ?? 0)
      }))
      .filter((row) => row.moveAmount !== 0);
    if (splitLines.length === 0) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "明細を選択してください",
          message: "分ける明細にチェックを入れてから実行してください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    // 0円は Apex に送らないため残る。削除確認は「実際に全明細が移るとき」だけ出す。
    const willDeleteSource =
      splitLines.length >= (invoice?.lines || []).length;
    if (willDeleteSource) {
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
          newInvoiceDate: this.invoiceSplitState.newInvoiceDate,
          newPaymentScheduledDate: this.invoiceSplitState.newPaymentDate,
          newBillingAccountId: changedBillingAccount
            ? newBillingAccountId
            : null,
          splitLines
        }
      })
    );
    // 成功時は preview 再取得で閉じる。失敗時は入力を維持する。
  }

  async handleConfirmInvoiceMove() {
    if (
      !this.invoiceMoveState?.invoiceId ||
      this.isSaving ||
      this.hasAmountDrafts
    ) {
      return;
    }
    if (!this.invoiceMoveState.targetInvoiceId) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "移動先を選択してください",
          message: "同じ Version の移動先請求を選んでから実行してください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    const invoice = this.findInvoice(this.invoiceMoveState.invoiceId);
    const lineIds = (invoice?.lines || [])
      .filter(
        (line) =>
          line?.lineId && this.invoiceMoveState.selected?.[line.lineId] === true
      )
      .map((line) => line.lineId);
    if (lineIds.length === 0) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "明細を選択してください",
          message: "移す明細にチェックを入れてから実行してください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    const targetInvoice = this.findInvoice(
      this.invoiceMoveState.targetInvoiceId
    );
    const sourceTax = this.normalizeTaxPercent(invoice?.taxPercent);
    const targetTax = this.normalizeTaxPercent(targetInvoice?.taxPercent);
    if (sourceTax !== targetTax) {
      const confirmedTax = await LightningConfirm.open({
        label: "明細を移す",
        message: `移動先の税率（${targetTax}%）が元請求（${sourceTax}%）と異なります。税抜金額はそのまま、税額・税込は移動先の税率で再計算されます。よろしいですか？`,
        theme: "warning",
        variant: "header"
      });
      if (!confirmedTax) {
        return;
      }
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
    // 成功時は preview 再取得で閉じる。失敗時は入力を維持する。
  }

  async handleRowSplitClick(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    const lineId = event.currentTarget.dataset.lineId;
    if (
      !invoiceId ||
      !lineId ||
      this.hasAmountDrafts ||
      this.isBillingEditUiOpen ||
      this.isInvoiceLocked(invoiceId) ||
      this.isSaving
    ) {
      return;
    }
    this.invoiceSplitState = null;
    this.invoiceMoveState = null;

    if (this.lineSplitState?.invoiceId === invoiceId) {
      const current = this.lineSplitState.rows?.[lineId];
      if (current?.selected === true) {
        // 選択中チップの再クリック＝分割キャンセル（幽霊 state で端数を塞がない）
        this.handleCloseLineSplit();
        return;
      }
      const activeOther = Object.keys(this.lineSplitState.rows || {}).find(
        (id) => id !== lineId && this.lineSplitState.rows[id]?.selected === true
      );
      if (activeOther) {
        return;
      }
      this.selectLineForSplit(lineId);
      return;
    }

    await this.ensureLineSplitState(invoiceId);
    if (!this.lineSplitState || this.lineSplitState.invoiceId !== invoiceId) {
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
    // 別請求へ切り替えるとき、前請求の単価数式ポップアップを孤児にしない
    this.handleCloseUnitPriceFormula();
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
      if (!this.lineSplitState || this.lineSplitState.invoiceId !== invoiceId) {
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
            value: option.value,
            remainAmount:
              option.remainAmount == null ? null : Number(option.remainAmount),
            moveAmount:
              option.moveAmount == null ? null : Number(option.moveAmount)
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
      if (!this.lineSplitState || this.lineSplitState.invoiceId !== invoiceId) {
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
      (id) => id !== lineId && this.lineSplitState.rows[id]?.selected === true
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
    this.handleCloseUnitPriceFormula();
    this.lineSplitState = null;
  }

  handleCancelLineSplitRow(event) {
    const lineId = event.currentTarget.dataset.lineId;
    if (!this.lineSplitState || !lineId) {
      return;
    }
    if (this.unitPriceFormulaLineId === lineId) {
      this.handleCloseUnitPriceFormula();
    }
    const remaining = Object.keys(this.lineSplitState.rows || {}).some(
      (id) => id !== lineId && this.lineSplitState.rows[id]?.selected === true
    );
    if (remaining) {
      this.updateLineSplitRow(lineId, { selected: false });
      return;
    }
    this.handleCloseUnitPriceFormula();
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
    this.handleCloseUnitPriceFormula();
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

  handleOpenUnitPriceFormula(event) {
    const lineId = event.currentTarget.dataset.lineId;
    if (!lineId || !this.lineSplitState?.rows?.[lineId]) {
      return;
    }
    const current = this.lineSplitState.rows[lineId].moveUnitPrice;
    const num = this.parseOptionalNumber(current);
    this.unitPriceFormulaLineId = lineId;
    this.unitPriceFormulaDraft =
      num == null ? String(current || "") : this.formatPlainNumber(num);
    this.unitPriceFormulaError = "";
    this.unitPriceFormulaHint = "単価、または = で四則計算（例: =1,200/12）";
    if (!this._boundUnitPriceFormulaEscape) {
      this._boundUnitPriceFormulaEscape = (e) => {
        if (e.key === "Escape" && this.unitPriceFormulaLineId != null) {
          e.preventDefault();
          this.handleCloseUnitPriceFormula();
        }
      };
      window.addEventListener("keydown", this._boundUnitPriceFormulaEscape);
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    Promise.resolve().then(() => {
      const input = this.template.querySelector(
        '[data-id="unit-price-formula-input"]'
      );
      if (input) {
        input.focus();
        if (typeof input.select === "function") {
          input.select();
        }
      }
    });
  }

  handleCloseUnitPriceFormula() {
    this.unitPriceFormulaLineId = null;
    this.unitPriceFormulaDraft = "";
    this.unitPriceFormulaError = "";
    this.unitPriceFormulaHint = "";
    if (this._boundUnitPriceFormulaEscape) {
      window.removeEventListener("keydown", this._boundUnitPriceFormulaEscape);
      this._boundUnitPriceFormulaEscape = null;
    }
  }

  handleUnitPriceFormulaDraftChange(event) {
    this.unitPriceFormulaDraft = event.target.value;
    this.unitPriceFormulaError = "";
  }

  handleUnitPriceFormulaKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.applyUnitPriceFormulaDraft();
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.handleCloseUnitPriceFormula();
    }
  }

  handleApplyUnitPriceFormula() {
    this.applyUnitPriceFormulaDraft();
  }

  applyUnitPriceFormulaDraft() {
    const lineId = this.unitPriceFormulaLineId;
    if (!lineId) {
      return;
    }
    const resolved = resolveScaledNumericInput(this.unitPriceFormulaDraft, 2);
    if (!resolved.ok) {
      this.unitPriceFormulaError = resolved.message;
      this.unitPriceFormulaHint = "";
      return;
    }
    this.updateLineSplitRow(lineId, {
      moveUnitPrice: String(resolved.value)
    });
    this.handleCloseUnitPriceFormula();
  }

  handleLineSplitMoveUnitPriceChange(event) {
    // 互換（旧直入力経路）。ポップアップ適用を正とする
    const lineId = event.target.dataset.lineId;
    const resolved = resolveScaledNumericInput(event.detail.value, 2);
    if (!resolved.ok) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "単価を確定できません",
          message: resolved.message,
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    this.updateLineSplitRow(lineId, {
      moveUnitPrice: String(resolved.value)
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

  async handleConfirmLineSplit() {
    if (
      !this.lineSplitState?.invoiceId ||
      this.isSaving ||
      this.hasAmountDrafts
    ) {
      return;
    }
    if (this.unitPriceFormulaLineId != null) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "単価の入力を確定してください",
          message:
            "数式ポップアップを適用（またはキャンセル）してから分割を実行してください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    if (this.lineSplitState.loadingThresholds) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "分割候補を読み込み中です",
          message: "読み込み完了後に分割を実行してください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    const splitLines = this.buildSplitLinesPayload();
    if (splitLines.length === 0) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "分割内容を入力してください",
          message: "明細を選択し、期間／単価／数量の分割内容を確定してください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    const invoice = this.findInvoice(this.lineSplitState.invoiceId);
    const selectedAmountAdjusted = (invoice?.lines || []).some((line) => {
      if (!line?.lineId) {
        return false;
      }
      const row = this.lineSplitState.rows?.[line.lineId];
      return row?.selected === true && line.isAmountAdjusted === true;
    });
    if (selectedAmountAdjusted) {
      const confirmed = await LightningConfirm.open({
        label: "明細を分割",
        message:
          "選択した明細の端数調整はリセットしてから分割します。よろしいですか？",
        theme: "warning",
        variant: "header"
      });
      if (!confirmed) {
        return;
      }
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
    if (
      this.hasAmountDrafts ||
      this.isSplitOrMoveUiOpen ||
      this.isInvoiceLocked(invoiceId)
    ) {
      return;
    }
    const invoice = this.findInvoice(invoiceId);
    if (!invoice) {
      return;
    }
    this.invoiceSplitState = null;
    this.invoiceMoveState = null;
    this.handleCloseLineSplit();
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
    if (this.isSaving) {
      return;
    }
    if (this.hasAmountDrafts) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "端数調整を先に確定してください",
          message:
            "未保存の端数調整があります。保存または取消してから請求情報を保存してください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    if (!this.billingEditState.invoiceDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求日を入力してください",
          message: "請求日は必須です。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    if (!this.billingEditState.paymentScheduledDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "入金予定日を入力してください",
          message: "入金予定日は必須です。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    const taxPercentRaw = this.billingEditState.taxPercent;
    if (taxPercentRaw == null || taxPercentRaw === "") {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "税率を入力してください",
          message:
            "税率は必須です。0% で運用する場合は 0 を明示的に入力してください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    const taxPercent = Number(taxPercentRaw);
    if (!Number.isFinite(taxPercent) || taxPercent < 0 || taxPercent > 100) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "税率が不正です",
          message: "税率は 0〜100 の数値で入力してください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    this.dispatchEvent(
      new CustomEvent("savebillingheader", {
        detail: {
          invoiceId: this.billingEditState.invoiceId,
          invoiceDate: this.billingEditState.invoiceDate,
          paymentScheduledDate: this.billingEditState.paymentScheduledDate,
          taxPercent,
          billingAddressee: this.billingEditState.billingAddressee ?? "",
          billingEmailTo: this.billingEditState.billingEmailTo ?? "",
          billingEmailCc: this.billingEditState.billingEmailCc ?? "",
          billingEmailBcc: this.billingEditState.billingEmailBcc ?? ""
        }
      })
    );
    // パネルは親が保存成功時に clearBillingEditState する（失敗時は維持）
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

  /**
   * Apex TaxCalculationUtil.calculateTaxAmount と同じ:
   * 表示％で (税抜 × 税率/100) を RoundingMode.DOWN（0方向への切り捨て）= Math.trunc。
   */
  calculateTaxAmount(amountExclTax, taxPercent) {
    const amount = Number(amountExclTax);
    if (!Number.isFinite(amount) || amount === 0) {
      return 0;
    }
    const resolvedPercent = this.normalizeTaxPercent(taxPercent);
    // 整数％は amount*percent/100 で浮動小数の揺らぎを抑える（Apex Decimal に近づける）
    return Math.trunc((amount * resolvedPercent) / 100);
  }

  normalizeTaxPercent(taxPercent) {
    if (taxPercent == null || taxPercent === "") {
      return 0;
    }
    const n = Number(taxPercent);
    if (!Number.isFinite(n) || n < 0) {
      return 0;
    }
    // Percent 項目の小数表記（0.1＝10%）を表示％へ
    if (n > 0 && n < 1) {
      return n * 100;
    }
    return n;
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
    totals.taxTotal = this.calculateTaxAmount(totals.amountTotal, taxPercent);
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
    return exclusive + this.calculateTaxAmount(exclusive, taxPercent);
  }
}
