import { LightningElement, api, track } from "lwc";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSplitThresholdDateOptions from "@salesforce/apex/OrderCreateController.getSplitThresholdDateOptions";
import getInvoiceOpsContext from "@salesforce/apex/InvoiceSendBoardController.getBoardContext";
import confirmInvoice from "@salesforce/apex/InvoiceSendBoardController.confirmInvoiceFromPreview";
import issueInvoiceDocument from "@salesforce/apex/InvoiceBoardDocumentService.issueFromPreview";
import previewIssueInvoice from "@salesforce/apex/InvoiceBoardDocumentService.previewIssueFromPreview";
import sendInvoice from "@salesforce/apex/InvoiceBoardDocumentService.sendFromPreview";
import previewInvoiceSend from "@salesforce/apex/InvoiceBoardDocumentService.previewFromPreview";
import getOpsBundle from "@salesforce/apex/InvoicePreviewOpsController.getOpsBundle";
import savePaymentFromPreview from "@salesforce/apex/InvoicePreviewOpsController.savePaymentFromPreview";
import cancelPaymentFromPreview from "@salesforce/apex/InvoicePreviewOpsController.cancelPaymentFromPreview";
import previewCancelPaymentFromPreview from "@salesforce/apex/InvoicePreviewOpsController.previewCancelPaymentFromPreview";
import previewRegisterFromPreview from "@salesforce/apex/InvoicePreviewOpsController.previewRegisterFromPreview";
import previewCancelConfirmed from "@salesforce/apex/OrderCreateController.previewCancelConfirmed";
import previewInvoiceLineAcceptanceEndDate from "@salesforce/apex/OrderCreateController.previewInvoiceLineAcceptanceEndDate";
import lockJournalsForInvoice from "@salesforce/apex/InvoicePreviewOpsController.lockJournalsForInvoice";
import unlockJournalsForInvoice from "@salesforce/apex/InvoicePreviewOpsController.unlockJournalsForInvoice";
import updateJournalMemo from "@salesforce/apex/InvoicePreviewOpsController.updateJournalMemo";
import updateInvoiceMemo from "@salesforce/apex/InvoiceOpsController.updateInvoiceMemo";
import issueInvoiceOperationKey from "@salesforce/apex/InvoicePreviewOpsController.issueInvoiceOperationKey";
import getInvoiceOpsFieldDefinitions from "@salesforce/apex/InvoiceOpsFieldService.getDefinitions";
import updatePaymentFromPreview from "@salesforce/apex/InvoicePreviewOpsController.updatePaymentFromPreview";
import {
  resolveScaledNumericInput,
  roundUnitPrice,
  setAmountCalculationRoundingModes
} from "c/estimateLineItemUtils";
import hasLockJournal from "@salesforce/customPermission/Loop_16_Can_LockJournal";
import hasUnlockJournal from "@salesforce/customPermission/Loop_17_Can_UnlockJournal";
import hasEditDraftInvoice from "@salesforce/customPermission/Loop_10_Can_EditDraftInvoice";
import hasConfirmInvoice from "@salesforce/customPermission/Loop_11_Can_ConfirmInvoice";
import hasSendInvoice from "@salesforce/customPermission/Loop_12_Can_SendInvoice";
import hasInvoicePayment from "@salesforce/customPermission/Loop_13_Can_InvoicePayment";
import hasManualJournal from "@salesforce/customPermission/Loop_14_Can_ManualJournal";
import hasCancelInvoice from "@salesforce/customPermission/Loop_15_Can_CancelInvoice";

const ALL_VERSIONS = "ALL";
const ALL_INVOICES = "ALL";
const ALL_DIFFERENCES = "ALL";
const VERSION_CONFLICT_MESSAGE =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";
const DIFFERENCE_HAS = "HAS";
const DIFFERENCE_NONE = "NONE";
const SEND_MODE_UNUSED = "Unused";
const SEND_MODE_PDF_AND_EMAIL = "PdfAndEmail";
/** 仕様: Core 第7.10節 */
const SEND_FAILURE_RETRY_NOTE =
  "失敗のあと送り直すと、先のメールが届いていることがある";
const CUSTOMER_CANCEL_NOTICE = "顧客への取消連絡が必要です。";

/** 仕様: Core 第3.3.7節。保存値 Email／Post／None。空はメールではない。 */
function deliveryMethodLabel(value) {
  if (value === "Email") {
    return "メール";
  }
  if (value === "Post") {
    return "郵送";
  }
  if (value === "None") {
    return "送付なし";
  }
  return "—";
}
/** 仕様: Core 第7.8節、第7.8.2節、第7.11節 */
const LOCKED_INVOICE_EDIT_NOTE = "確定済み・取消済みの請求は編集できません。";
const REVENUE_BASIS_POINT_IN_TIME = "一括計上";
const KIND_PERIOD = "period";
const KIND_UNIT_PRICE = "unitPrice";
const KIND_QUANTITY = "quantity";

/** 仕様: Core 第7.8.1節。金額0円を除く全明細と一致するときだけ元削除確認を出す。 */
function movesAllNonZeroLines(invoice, movingLineIds) {
  const moving = new Set(movingLineIds || []);
  const nonZeroIds = (invoice?.lines || [])
    .filter((line) => line?.lineId && Number(line.amount ?? 0) !== 0)
    .map((line) => line.lineId);
  return (
    nonZeroIds.length > 0 && nonZeroIds.every((lineId) => moving.has(lineId))
  );
}
/** 商品名: 列幅に収まるまで縮小（rem）。下限未満は省略記号。 */
const PRODUCT_NAME_FONT_MAX_REM = 0.6875;
const PRODUCT_NAME_FONT_MIN_REM = 0.5625;
const PRODUCT_NAME_FONT_STEP_REM = 0.03125;

/** 仕様: Accounting 第11.1節、第9.4節 */
const JOURNAL_EVENT_FILTER_OPTIONS = [
  { label: "請求確定", value: "BILLING_CONFIRMED" },
  { label: "請求取消", value: "BILLING_CANCELLED" },
  { label: "検収日変更", value: "ACCEPTANCE_DATE_CHANGED" },
  {
    label: "請求入出金登録（Purpose=Invoice／NonInvoiceと符号付きAmountを含む）",
    value: "PAYMENT_RECORDED"
  },
  { label: "請求入出金取消", value: "PAYMENT_CANCELLED" },
  { label: "手動仕訳", value: "MANUAL_JOURNAL" }
];
const JOURNAL_STATUS_FILTER_OPTIONS = [
  { label: "有効", value: "Active" },
  { label: "論理削除", value: "LogicallyDeleted" },
  { label: "取消済", value: "Cancelled" },
  { label: "取消", value: "Reversal" }
];
const JOURNAL_LOCK_FILTER_OPTIONS = [
  { label: "未ロック", value: "Unlocked" },
  { label: "ロック済み", value: "Locked" }
];

// 仕様: Accounting 第2.3節、日付仕様 第8章
function postingPeriodLabel(postingDate, asOfDate) {
  if (!postingDate || !asOfDate) {
    return "";
  }
  const posting = String(postingDate).slice(0, 10);
  return posting > asOfDate ? "将来" : "到来済み";
}

function journalMatchesFilters(journal, eventKeys, statuses, lockStatuses) {
  if (eventKeys.length > 0 && !eventKeys.includes(journal.eventKey)) {
    return false;
  }
  // 仕様: Accounting 第2.3節・第11.1節。空＝通常表示で有効だけ。監査状態は明示選択時。
  if (statuses.length === 0) {
    if (journal.transactionStatus !== "Active") {
      return false;
    }
  } else if (!statuses.includes(journal.transactionStatus)) {
    return false;
  }
  if (lockStatuses.length > 0) {
    const lockValue = journal.isLocked ? "Locked" : "Unlocked";
    if (!lockStatuses.includes(lockValue)) {
      return false;
    }
  }
  return true;
}

/** 仕様: Core 第7.9.6節、Accounting 第8.5節。取消系はON/OFFを問わずロック済みなら基準日。 */
function requiresCancelDate(bundle) {
  const journals = bundle?.journals || [];
  if (journals.length > 0) {
    return journals.some(
      (row) => row.isLocked === true && row.transactionStatus === "Active"
    );
  }
  return bundle?.hasLockedJournals === true;
}

function extraFieldInputType(fieldType) {
  if (fieldType === "DATE") {
    return "date";
  }
  if (fieldType === "DATETIME") {
    return "datetime";
  }
  if (
    fieldType === "INTEGER" ||
    fieldType === "LONG" ||
    fieldType === "DOUBLE" ||
    fieldType === "CURRENCY" ||
    fieldType === "PERCENT"
  ) {
    return "number";
  }
  if (fieldType === "EMAIL") {
    return "email";
  }
  if (fieldType === "PHONE") {
    return "tel";
  }
  if (fieldType === "URL") {
    return "url";
  }
  return "text";
}

function isBlankExtraValue(value) {
  if (value === null || value === undefined) {
    return true;
  }
  if (typeof value === "boolean") {
    return false;
  }
  return String(value).trim() === "";
}

function extraFieldChecked(raw) {
  return raw === true || raw === "true" || raw === "1" || raw === 1;
}

/** 仕様: Accounting 第1.1節・第8.5節。入金登録だけONかつロック済みのとき取消基準日。 */
function requiresPaymentRegisterCancelDate(bundle) {
  if (bundle == null || bundle.accountingEnabled !== true) {
    return false;
  }
  return requiresCancelDate(bundle);
}

export default class OrderInvoicePreviewTable extends LightningElement {
  @api billingAccountOptions = [];
  @api isSaving = false;
  @api initialVersion;
  @api initialInvoiceId;
  /** 仕様: Core 第7.7.3節 */
  @api contractHistoryId;
  /** 仕様: 横断画面.md 第2.2節。横断では受注直後に戻すを置かない。 */
  @api hideResetPostOrder = false;
  /** 仕様: 横断画面.md 仕訳一覧。左の仕訳から来たときは仕訳タブ。 */
  @api initialActiveTab;
  /** 仕様: 横断画面.md 仕訳一覧。クリックした仕訳行を選択状態にする。 */
  @api highlightJournalId;

  @api
  clearBillingEditState() {
    this.billingEditState = null;
  }

  @track selectedVersion = ALL_VERSIONS;
  @track selectedInvoiceId = ALL_INVOICES;
  @track selectedDifferenceFilter = ALL_DIFFERENCES;
  @track includeCancelled = false;
  @track includeCancelledPayments = false;
  @track invoiceCancelState = null;
  @track memoDrafts = {};
  @track journalMemoDrafts = {};
  @track journalEventFilter = [];
  @track journalStatusFilter = [];
  @track journalLockFilter = [];
  @track journalLockSelected = {};
  @track unlockReason = "";
  @track invoiceSplitState = null;
  @track invoiceMoveState = null;
  /** 仕様: Core 第7.8.1節。他の未確定があるときの新規／既存の選択。 */
  @track invoiceDestinationChoiceState = null;
  @track lineSplitState = null;
  @track billingEditState = null;
  @track paymentEditState = null;
  @track journalToggleOpen = {};
  @track journalExtraDrafts = {};
  @track invoiceOpsFieldDefinitions = [];
  @track invoiceOpsFieldConfigError = "";
  @track invoiceSendState = null;
  @track invoiceIssueState = null;
  @track invoiceOpsProcessingId = null;
  @track invoiceUiState = {};
  @track amountDrafts = {};
  /** 単価分割の数式ポップアップ（見積金額入力と同じ UI） */
  @track unitPriceFormulaLineId = null;
  @track unitPriceFormulaDraft = "";
  @track unitPriceFormulaError = "";
  @track unitPriceFormulaHint = "";

  _preview;
  /** オープン時の親子フィルタ初期値を一度だけ適用したか（保存後の再取得では維持）。 */
  _defaultVersionApplied = false;
  _fitProductNamesRaf = null;
  _resizeObserver = null;
  invoiceSendFeatureEnabled = false;
  /** 仕様: 共通基盤 第10.4節。請求書発行・送付は 12。 */
  get canSendInvoiceDocument() {
    return hasSendInvoice === true;
  }
  /** 仕様: 共通基盤 第10.4節。入金は 13。 */
  get canPayInvoice() {
    return hasInvoicePayment === true;
  }
  /** 仕様: 共通基盤 第10.4節。確定は 11。 */
  get canConfirmInvoiceOp() {
    return hasConfirmInvoice === true;
  }
  /** 仕様: 共通基盤 第10.4節。確定取消は 15。 */
  get canCancelInvoiceOp() {
    return hasCancelInvoice === true;
  }
  /** 仕様: 共通基盤 第10.4節。手動仕訳は 14。 */
  get canManualJournalOp() {
    return hasManualJournal === true;
  }
  /** 仕様: 共通基盤 第10.4節。未確定・メモは 10。 */
  get canEditDraftInvoiceOp() {
    return hasEditDraftInvoice === true;
  }
  /** 仕様: Core 第7.7.2節。組織のAccounting ON/OFF。 */
  accountingEnabledOnBoard = false;
  // 仕様: Accounting 第9.5節、共通基盤 第3.2節・第10.4節。手動Lockと手動Unlockはそれぞれ専用権限。
  get canLockJournal() {
    return hasLockJournal === true;
  }
  get canUnlockJournal() {
    return hasUnlockJournal === true;
  }
  invoiceDocumentTemplateOptions = [];
  invoiceEmailTemplateOptions = [];
  defaultInvoiceDocumentTemplateKey = "";
  defaultInvoiceEmailTemplateApiName = "";
  companyBlockedReason = "";
  orgFromResolved = false;
  invoiceOpsContextError = "";

  billingAccountMatchingInfo = {
    primaryField: {
      fieldPath: "Name"
    }
  };

  connectedCallback() {
    this.loadInvoiceOpsContext();
    this.loadInvoiceOpsFieldDefinitions();
  }

  @api
  get preview() {
    return this._preview;
  }
  set preview(value) {
    this._preview = value;
    // 仕様: Core 第11.9節、第1.1.10節。分割／移すの数量・単価丸めは OrgDefault。未設定を0へ落とさない。
    setAmountCalculationRoundingModes({
      quantityUnitPriceRoundingMode: value?.quantityUnitPriceRoundingMode,
      amountRoundingMode: value?.amountRoundingMode
    });
    // サーバ反映後は draft を捨てて正本表示に戻す
    this.amountDrafts = {};
    this.invoiceSplitState = null;
    this.invoiceMoveState = null;
    this.invoiceDestinationChoiceState = null;
    this.lineSplitState = null;
    this.billingEditState = null;
    this.paymentEditState = null;
    this.journalToggleOpen = {};
    this.journalExtraDrafts = {};
    this.invoiceSendState = null;
    this.invoiceIssueState = null;
    this.handleCloseUnitPriceFormula();
    this.applyDefaultVersionFilter();
    this.initializeInvoiceUiState();
  }

  initializeInvoiceUiState() {
    const next = { ...this.invoiceUiState };
    const invoiceIds = new Set();
    for (const invoice of this._preview?.invoices || []) {
      if (!invoice?.invoiceId) {
        continue;
      }
      invoiceIds.add(invoice.invoiceId);
      const previous = next[invoice.invoiceId];
      next[invoice.invoiceId] = {
        activeTab:
          this.initialInvoiceId === invoice.invoiceId && this.initialActiveTab
            ? this.initialActiveTab
            : previous?.activeTab || "lines",
        bundle: previous?.bundle || null,
        loading: previous?.loading === true,
        error: previous?.error || "",
        paymentDraft:
          previous?.paymentDraft || this.newPaymentDraft(invoice.invoiceId),
        cancelDraft: previous?.cancelDraft || null
      };
    }
    Object.keys(next).forEach((invoiceId) => {
      if (!invoiceIds.has(invoiceId)) {
        delete next[invoiceId];
      }
    });
    this.invoiceUiState = next;
    invoiceIds.forEach((invoiceId) => this.loadOpsBundle(invoiceId));
  }

  newPaymentDraft(invoiceId, remainingNet, paymentLines) {
    const remaining = remainingNet == null ? null : Number(remainingNet);
    const draft = {
      invoiceId,
      paymentId: null,
      amount: remaining == null ? "" : String(remaining),
      purpose: "Invoice",
      paymentDate: this.todayLocalIso(),
      memo: "",
      extraFieldValues: {},
      allocations: []
    };
    draft.allocations = this.proposePaymentAllocations(
      paymentLines || [],
      remaining == null ? 0 : remaining,
      remaining == null ? 0 : remaining
    );
    return draft;
  }

  // 仕様: Core 第11.9節。未処理税込の比例と符号付き最大剰余。最終決済は残をそのまま載せる。
  proposePaymentAllocations(lines, parentAmount, headerRemaining) {
    const rows = Array.isArray(lines) ? lines : [];
    const amount = Number(parentAmount);
    const header = Number(headerRemaining);
    const mapped = rows.map((line) => ({
      lineId: line.lineId,
      productName: line.productName || "—",
      remainingInclusive: Number(line.remainingInclusive ?? 0),
      amount: 0
    }));
    if (mapped.length === 0 || !amount) {
      return mapped;
    }
    if (amount === header) {
      return mapped.map((row) => ({
        ...row,
        amount: row.remainingInclusive
      }));
    }
    const remainingTotal = mapped.reduce(
      (sum, row) => sum + row.remainingInclusive,
      0
    );
    if (remainingTotal === 0) {
      return mapped;
    }
    const theoreticals = mapped.map(
      (row) => (row.remainingInclusive * amount) / remainingTotal
    );
    const truncated = theoreticals.map((value) => this.truncTowardZero(value));
    let diff = amount - truncated.reduce((sum, value) => sum + value, 0);
    const order = truncated
      .map((_, index) => ({
        index,
        remainder: theoreticals[index] - truncated[index]
      }))
      .sort((left, right) => {
        if (right.remainder !== left.remainder) {
          return right.remainder - left.remainder;
        }
        return left.index - right.index;
      });
    const amounts = truncated.slice();
    const step = diff > 0 ? 1 : -1;
    let guard = 0;
    while (diff !== 0 && order.length > 0 && guard < 100000) {
      amounts[order[guard % order.length].index] += step;
      diff -= step;
      guard += 1;
    }
    return mapped.map((row, index) => ({
      ...row,
      amount: amounts[index]
    }));
  }

  truncTowardZero(value) {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return value < 0 ? Math.ceil(value) : Math.floor(value);
  }

  isWithinLineRemaining(amount, remaining) {
    const alloc = Number(amount);
    const left = Number(remaining);
    if (!Number.isFinite(alloc) || alloc !== Math.trunc(alloc)) {
      return false;
    }
    if (alloc === 0) {
      return true;
    }
    if (left === 0) {
      return false;
    }
    if (Math.sign(alloc) !== Math.sign(left)) {
      return false;
    }
    return Math.abs(alloc) <= Math.abs(left);
  }

  updateInvoiceUiState(invoiceId, patch) {
    const current = this.invoiceUiState[invoiceId] || {
      activeTab: "lines",
      paymentDraft: this.newPaymentDraft(invoiceId)
    };
    this.invoiceUiState = {
      ...this.invoiceUiState,
      [invoiceId]: { ...current, ...patch }
    };
  }

  /** 仕様: Core 第7.9.7節 */
  async resolvePendingOperationKey(invoiceId) {
    const existing = this.invoiceUiState[invoiceId]?.pendingOperationKey;
    if (existing) {
      return existing;
    }
    const key = await issueInvoiceOperationKey();
    this.updateInvoiceUiState(invoiceId, { pendingOperationKey: key });
    return key;
  }

  /** 仕様: Core 第7.9.7節 */
  clearPendingOperationKey(invoiceId) {
    if (!invoiceId) {
      return;
    }
    this.updateInvoiceUiState(invoiceId, { pendingOperationKey: null });
  }

  async loadOpsBundle(invoiceId) {
    if (!invoiceId) {
      return;
    }
    this.updateInvoiceUiState(invoiceId, { loading: true, error: "" });
    try {
      const bundle = await getOpsBundle({
        invoiceId,
        contractHistoryId: this.contractHistoryId
      });
      if (!this.findInvoice(invoiceId)) {
        return;
      }
      const current = this.invoiceUiState[invoiceId] || {};
      const remaining =
        Number(bundle?.taxInclusiveAmount ?? 0) -
        Number(bundle?.invoicePaymentNet ?? 0);
      const draft =
        current.paymentDraft ||
        this.newPaymentDraft(invoiceId, remaining, bundle?.paymentLines);
      // 仕様: Core 第8.9節。初期金額は符号付き未処理Net。未処理0はInvoice目的を登録できない。
      const nextDraft =
        draft.amount === "" || draft.amount == null
          ? this.newPaymentDraft(invoiceId, remaining, bundle?.paymentLines)
          : draft;
      const requiresDate = requiresPaymentRegisterCancelDate(bundle);
      this.updateInvoiceUiState(invoiceId, {
        bundle,
        paymentDraft: {
          ...nextDraft,
          cancellationDate: requiresDate
            ? nextDraft.cancellationDate || this.todayLocalIso()
            : ""
        },
        loading: false,
        error: ""
      });
    } catch (error) {
      this.updateInvoiceUiState(invoiceId, {
        loading: false,
        error: this.reduceInvoiceOpsError(error)
      });
    }
  }

  /**
   * 入口の初期フィルタ。ユーザー切替後／保存後の再取得では維持。
   */
  applyDefaultVersionFilter() {
    if (this._defaultVersionApplied || !this._preview) {
      return;
    }
    const requestedVersion =
      this.initialVersion != null && this.initialVersion !== ""
        ? String(this.initialVersion)
        : "";
    if (requestedVersion === ALL_VERSIONS) {
      this.selectedVersion = ALL_VERSIONS;
    } else {
      const raw = requestedVersion || this._preview.sourceHistoryVersion;
      if (raw != null && raw !== "") {
        const value = String(raw);
        const exists = (this._preview.versionOptions || []).some(
          (option) => String(option?.value) === value
        );
        this.selectedVersion = exists ? value : ALL_VERSIONS;
      }
    }
    if (this.initialInvoiceId) {
      this.selectedInvoiceId = this.initialInvoiceId;
      const initial = this.findInvoice(this.initialInvoiceId);
      if (this.isCancelledInvoice(initial)) {
        this.includeCancelled = true;
      }
    }
    this._defaultVersionApplied = true;
  }

  async loadInvoiceOpsContext() {
    this.invoiceOpsContextError = "";
    try {
      const context = await getInvoiceOpsContext();
      this.invoiceSendFeatureEnabled = context?.featureEnabled === true;
      this.accountingEnabledOnBoard = context?.accountingEnabled === true;
      this.invoiceDocumentTemplateOptions =
        context?.documentTemplateOptions || [];
      this.invoiceEmailTemplateOptions = context?.emailTemplateOptions || [];
      this.defaultInvoiceDocumentTemplateKey =
        context?.defaultDocumentTemplateKey || "";
      this.defaultInvoiceEmailTemplateApiName =
        context?.defaultEmailTemplateApiName || "";
      this.companyBlockedReason = context?.companyBlockedReason || "";
      this.orgFromResolved = context?.orgFromResolved === true;
    } catch (error) {
      this.invoiceSendFeatureEnabled = false;
      this.accountingEnabledOnBoard = false;
      this.companyBlockedReason = "";
      this.orgFromResolved = false;
      this.invoiceOpsContextError = this.reduceInvoiceOpsError(error);
    }
  }

  // 仕様: Core 第11.4.4節。定義不整合は対象画面を続行せず設定エラー。
  async loadInvoiceOpsFieldDefinitions() {
    this.invoiceOpsFieldConfigError = "";
    try {
      this.invoiceOpsFieldDefinitions =
        (await getInvoiceOpsFieldDefinitions()) || [];
    } catch (error) {
      this.invoiceOpsFieldDefinitions = [];
      this.invoiceOpsFieldConfigError = this.reduceInvoiceOpsError(error);
    }
  }

  opsFieldDefinitionsFor(targetObject) {
    return (this.invoiceOpsFieldDefinitions || []).filter(
      (row) => row && row.targetObject === targetObject
    );
  }

  isPaymentPurposeVisible(definition, purpose) {
    if (purpose === "Invoice") {
      return definition.showOnInvoicePurpose === true;
    }
    return definition.showOnNonInvoicePurpose === true;
  }

  resolveExtraDisplayValue(definition, stored) {
    if (!isBlankExtraValue(stored)) {
      return stored;
    }
    return definition.defaultValue == null ? "" : definition.defaultValue;
  }

  lockExemptNameSet(names) {
    return new Set(
      (names || [])
        .map((name) => String(name || "").trim())
        .filter((name) => name !== "")
    );
  }

  extraFieldValueFromEvent(event) {
    if (event.target.dataset.inputKind === "checkbox") {
      return event.detail.checked === true;
    }
    return event.detail.value;
  }

  extraFieldValuesFromViews(fields) {
    const values = {};
    for (const field of fields || []) {
      if (field.disabled) {
        continue;
      }
      values[field.apiName] = field.isCheckbox ? field.checked : field.value;
    }
    return values;
  }

  // 仕様: Core 第11.4.4節。表示中だけ必須。確定後／登録後／Lock後の編集はロック除外へ人が足した項目だけ。
  buildExtraFieldViews({
    targetObject,
    storedValues,
    draftValues,
    purpose,
    disabledAll,
    exemptNames,
    requireExemptToEdit
  }) {
    const stored = storedValues || {};
    const drafts = draftValues || {};
    const exempt = this.lockExemptNameSet(exemptNames);
    return this.opsFieldDefinitionsFor(targetObject)
      .filter((definition) => {
        if (targetObject === "InvoicePayment__c") {
          return this.isPaymentPurposeVisible(definition, purpose);
        }
        return true;
      })
      .map((definition) => {
        const apiName = definition.apiName;
        const raw = Object.prototype.hasOwnProperty.call(drafts, apiName)
          ? drafts[apiName]
          : this.resolveExtraDisplayValue(definition, stored[apiName]);
        const lockedOut =
          requireExemptToEdit === true && !exempt.has(apiName);
        const disabled = disabledAll === true || lockedOut;
        const fieldType = definition.fieldType || "STRING";
        const isCheckbox = fieldType === "BOOLEAN";
        const isPicklist = fieldType === "PICKLIST";
        const isTextarea =
          fieldType === "TEXTAREA" || fieldType === "LONGTEXTAREA";
        const checked = extraFieldChecked(raw);
        return {
          apiName,
          key: apiName,
          label: definition.label,
          helpText: definition.helpText || "",
          required: definition.required === true && !disabled,
          disabled,
          isCheckbox,
          isPicklist,
          isTextarea,
          isInput: !isCheckbox && !isPicklist && !isTextarea,
          inputType: extraFieldInputType(fieldType),
          value: isCheckbox ? checked : raw == null ? "" : raw,
          checked,
          picklistOptions: definition.picklistOptions || []
        };
      });
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
    const options = [{ label: "全版", value: ALL_VERSIONS }];
    (this.preview?.versionOptions || []).forEach((option) => {
      if (!option?.value) {
        return;
      }
      options.push({
        label: option.label || `版${option.value}`,
        value: String(option.value)
      });
    });
    return options;
  }

  get showVersionFilter() {
    return (this.preview?.versionOptions || []).length > 0;
  }

  get invoiceFilterOptions() {
    const options = [{ label: "全請求書", value: ALL_INVOICES }];
    this.invoicesForFilter()
      .filter((invoice) => this.includeCancelled || !this.isCancelledInvoice(invoice))
      .filter((invoice) => this.invoiceMatchesDifferenceFilter(invoice))
      .forEach((invoice) => {
        options.push({
          label: invoice.invoiceName || invoice.invoiceId,
          value: invoice.invoiceId
        });
      });
    return options;
  }

  get differenceFilterOptions() {
    return [
      { label: "すべて", value: ALL_DIFFERENCES },
      { label: "差額あり", value: DIFFERENCE_HAS },
      { label: "差額なし", value: DIFFERENCE_NONE }
    ];
  }

  get invoiceSendMode() {
    return this.preview?.invoiceSendMode || "";
  }

  get canIssueDocument() {
    return (
      this.invoiceSendMode && this.invoiceSendMode !== SEND_MODE_UNUSED
    );
  }

  get canSendDocument() {
    return this.invoiceSendMode === SEND_MODE_PDF_AND_EMAIL;
  }

  // 仕様: Core 第11.3.1節・第7.10節・第1.1.10節。必須の会社情報が空なら発行を止める。
  invoiceIssueUnavailableReason(confirmedOrLater, isCancelled) {
    if (!this.canIssueDocument) {
      return "請求書設定が使わないのため発行できません。";
    }
    if (!confirmedOrLater || isCancelled) {
      return "確定済みの請求だけ発行できます。";
    }
    if (!this.isBlankReasonText(this.companyBlockedReason)) {
      return this.companyBlockedReason;
    }
    if (!this.defaultInvoiceDocumentTemplateKey) {
      return "利用できる請求書テンプレートがありません。";
    }
    return "";
  }

  // 仕様: Core 第11.3.2節・第7.10節。PDFとメール送付なら請求用組織送信元必須。
  invoiceSendUnavailableReason(invoice, confirmedOrLater, isCancelled) {
    if (!this.canSendDocument) {
      return (
        this.invoiceOpsContextError ||
        "請求書設定がPDFとメール送付のときだけ送付できます。"
      );
    }
    if (!confirmedOrLater || isCancelled) {
      return "確定済みの請求だけ送付できます。";
    }
    if (invoice.invoiceDeliveryMethod !== "Email") {
      return "届け方がメールのときだけ送付できます。";
    }
    if (this.isBlankReasonText(invoice.billingEmailTo)) {
      return "請求のToメールアドレスが設定されていません。";
    }
    if (
      this.hasInvalidEmailList(invoice.billingEmailTo) ||
      this.hasInvalidEmailList(invoice.billingEmailCc) ||
      this.hasInvalidEmailList(invoice.billingEmailBcc)
    ) {
      return "不正なメールアドレスがあるため送れません。";
    }
    if (!this.defaultInvoiceDocumentTemplateKey) {
      return "利用できる請求書テンプレートがありません。";
    }
    if (this.orgFromResolved !== true) {
      return "PDFとメール送付のとき、組織の送信元を選んでください。";
    }
    return "";
  }

  get sendFailureRetryNote() {
    return SEND_FAILURE_RETRY_NOTE;
  }

  /** 未保存の端数下書きがある間は Version 切替不可（別 Version への黙殺保存を防ぐ）。 */
  get versionFilterDisabled() {
    return this.hasAmountDrafts === true || this.isSaving === true;
  }

  get versionFilterTitle() {
    if (this.hasAmountDrafts) {
      return "端数調整の保存または取消後に版を切り替えられます";
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
    return this.invoicesForFilter();
  }

  invoicesForFilter() {
    const selected = this.selectedVersion;
    return (this.preview?.invoices || []).filter((invoice) => {
      if (selected === ALL_VERSIONS) {
        return true;
      }
      return (
        invoice?.historyVersion != null &&
        String(Number(invoice.historyVersion)) === String(selected)
      );
    });
  }

  isCancelledInvoice(invoice) {
    return (
      invoice?.isCancelled === true ||
      invoice?.invoiceTransactionStatus === "Cancelled"
    );
  }

  // 仕様: Core 第8.8節。差額は全入出金Net－請求税込。負額請求でも式を反転しない。
  invoiceBalanceDifference(invoice) {
    const bundle = this.invoiceUiState[invoice?.invoiceId]?.bundle;
    const headerInclusive =
      bundle?.taxInclusiveAmount ?? invoice?.taxInclusiveAmount;
    const gross =
      headerInclusive != null
        ? Number(headerInclusive)
        : Number(invoice?.amountTotal ?? 0) + Number(invoice?.taxTotal ?? 0);
    const allPaymentNet = Number(
      bundle?.paymentNetTotal ?? invoice?.paymentNetTotal ?? 0
    );
    return Math.round(allPaymentNet - gross);
  }

  // 仕様: Accounting 第11.2節、Core 第8.7節。完全一致だけ差額なし。
  invoiceMatchesDifferenceFilter(invoice) {
    if (this.selectedDifferenceFilter === ALL_DIFFERENCES) {
      return true;
    }
    const difference = this.invoiceBalanceDifference(invoice);
    if (this.selectedDifferenceFilter === DIFFERENCE_HAS) {
      return difference !== 0;
    }
    return difference === 0;
  }

  paymentTransactionStatus(payment) {
    if (payment?.paymentTransactionStatus) {
      return payment.paymentTransactionStatus;
    }
    if (payment?.isCancelled === true) {
      return "Cancelled";
    }
    if (payment?.isCancellation === true) {
      return "Reversal";
    }
    return "Active";
  }

  // 仕様: Core 第2.3.1節。有効／取消済み／取消。
  paymentStatusLabel(payment) {
    const status = this.paymentTransactionStatus(payment);
    if (status === "Cancelled") {
      return "取消済み";
    }
    if (status === "Reversal") {
      return "取消";
    }
    return "有効";
  }

  isInactivePayment(payment) {
    const status = this.paymentTransactionStatus(payment);
    return status === "Cancelled" || status === "Reversal";
  }

  // 仕様: Core 第7.9.5節・第7.10節・第1.1.10節、Accounting 第9.5節
  isBlankReasonText(value) {
    return value == null || String(value).trim() === "";
  }

  /** 仕様: Core 第7.10節、第1.1.10節。空の区切りは無視。不正があれば送れない。 */
  hasInvalidEmailList(raw) {
    if (raw == null || String(raw).trim() === "") {
      return false;
    }
    if (String(raw).length > 255) {
      return true;
    }
    const pattern =
      /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/;
    for (const candidate of String(raw).split(",")) {
      const address = candidate.trim();
      if (!address) {
        continue;
      }
      if (!pattern.test(address)) {
        return true;
      }
    }
    return false;
  }

  /** 仕様: Accounting 第9.1節、第1.1.10節。Unlock理由はテキスト255。 */
  isUnlockReasonTooLong(value) {
    return value != null && String(value).length > 255;
  }

  // 仕様: Core 第7.9.3節・第7.7.3節・第1.1.10節
  invoiceCancelBlockedReason(bundle) {
    const payments = bundle?.payments || [];
    if (payments.some((payment) => !this.isInactivePayment(payment))) {
      return "有効な請求入出金がある請求は取消できません。";
    }
    const manuals = bundle?.manualJournals || [];
    if (manuals.some((header) => header.transactionStatus === "Active")) {
      return "有効な手動仕訳がある請求は取消できません。";
    }
    return "";
  }

  isDraftInvoice(invoice) {
    if (this.isCancelledInvoice(invoice)) {
      return false;
    }
    return (invoice?.invoiceTransactionStatus || "Draft") === "Draft";
  }

  isConfirmedInvoice(invoice) {
    if (this.isCancelledInvoice(invoice)) {
      return false;
    }
    return invoice?.invoiceTransactionStatus === "Confirmed";
  }

  transactionStatusLabel(status) {
    if (status === "Draft") {
      return "未確定";
    }
    if (status === "Confirmed") {
      return "確定済み";
    }
    if (status === "Cancelled") {
      return "取消済み";
    }
    return status || "";
  }

  // 仕様: Accounting 第9.3節。仕訳の4状態。保存値は変えない。
  journalTransactionStatusLabel(status) {
    if (status === "Active") {
      return "有効";
    }
    if (status === "LogicallyDeleted") {
      return "論理削除";
    }
    if (status === "Cancelled") {
      return "取消済";
    }
    if (status === "Reversal") {
      return "取消";
    }
    return status || "";
  }

  get journalEventFilterOptions() {
    return JOURNAL_EVENT_FILTER_OPTIONS;
  }

  get journalStatusFilterOptions() {
    return JOURNAL_STATUS_FILTER_OPTIONS;
  }

  get journalLockFilterOptions() {
    return JOURNAL_LOCK_FILTER_OPTIONS;
  }

  handleJournalEventFilterChange(event) {
    this.journalEventFilter = event.detail.value || [];
  }

  handleJournalStatusFilterChange(event) {
    this.journalStatusFilter = event.detail.value || [];
  }

  handleJournalLockFilterChange(event) {
    this.journalLockFilter = event.detail.value || [];
  }

  handleClearJournalFilters() {
    this.journalEventFilter = [];
    this.journalStatusFilter = [];
    this.journalLockFilter = [];
  }

  documentTemplateLabel(key) {
    if (!key) {
      return "";
    }
    const option = (this.invoiceDocumentTemplateOptions || []).find(
      (row) => row.value === key
    );
    return option?.label || key;
  }

  emailTemplateLabel(templateId) {
    if (!templateId) {
      return "";
    }
    const option = (this.invoiceEmailTemplateOptions || []).find(
      (row) => row.value === templateId
    );
    return option?.label || templateId;
  }

  /**
   * 特定 Version 絞り込み・最新 Ordered・有効な確定済みが0件のとき表示。
   * 取消済みがあっても可。仕様: Core 第7.7.2節・第7.7.3節。
   */
  get showResetPostOrderButton() {
    if (this.hideResetPostOrder === true) {
      return false;
    }
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
    if (invoices.length === 0) {
      return false;
    }
    return !invoices.some((invoice) => this.isConfirmedInvoice(invoice));
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
      return "別の請求へ分ける／分割をキャンセルまたは実行してから操作できます";
    }
    return "この版の請求を受注直後の状態に作り直します";
  }

  get hasInvoices() {
    return this.invoiceCards.length > 0;
  }

  get canEdit() {
    return (
      this.preview?.canEdit === true &&
      this.preview?.versionEditBlocked !== true &&
      this.canEditDraftInvoiceOp === true
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
   * 別の請求へ分ける／同一請求内分割の編集中（しきい日ロード中含む）。
   * この間は端数ドラフト不可。閉じたあとの幽霊 lineSplitState は無視。
   */
  get isSplitOrMoveUiOpen() {
    return (
      this.invoiceSplitState != null ||
      this.invoiceMoveState != null ||
      this.invoiceDestinationChoiceState != null ||
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

  /**
   * Version合計の対象。親が全版でも請求書1枚に絞ったときは、その請求の版で計算する。
   */
  // 仕様: Core 第7.7.0節
  versionKeyForInvoice(invoice) {
    if (invoice?.historyVersion != null && invoice.historyVersion !== "") {
      return String(Number(invoice.historyVersion));
    }
    return null;
  }

  confirmVersionKey(invoice) {
    return (
      this.versionKeyForInvoice(invoice) ||
      (this.selectedVersion !== ALL_VERSIONS
        ? this.selectedVersion
        : ALL_VERSIONS)
    );
  }

  get versionKeyForTotals() {
    if (this.selectedVersion !== ALL_VERSIONS) {
      return this.selectedVersion;
    }
    if (this.selectedInvoiceId !== ALL_INVOICES) {
      return (
        this.versionKeyForInvoice(this.findInvoice(this.selectedInvoiceId)) ||
        ALL_VERSIONS
      );
    }
    return ALL_VERSIONS;
  }

  versionOption(selected) {
    return (this.preview?.versionOptions || []).find(
      (row) => String(row.value) === String(selected)
    );
  }

  taxPercentForVersion(selected) {
    for (const invoice of this.preview?.invoices || []) {
      if (this.isCancelledInvoice(invoice)) {
        continue;
      }
      if (
        selected !== ALL_VERSIONS &&
        this.versionKeyForInvoice(invoice) !== String(selected)
      ) {
        continue;
      }
      if (invoice.taxPercent != null && invoice.taxPercent !== "") {
        return invoice.taxPercent;
      }
    }
    return null;
  }

  computeInclusive(amountExcl, taxPercent) {
    return (
      (Number(amountExcl) || 0) +
      this.calculateTaxAmount(amountExcl, taxPercent)
    );
  }

  // 仕様: Core 第7.4節、第7.7.0節、第7.8.5節、第7.9.1節
  totalsForVersion(selected) {
    const option = this.versionOption(selected);
    const taxPercent = this.taxPercentForVersion(selected);
    let estimateExcl;
    let invoiceExcl;
    let estimateIncl;
    let invoiceIncl;
    if (selected === ALL_VERSIONS) {
      estimateExcl = Number(this.preview?.periodLineAmountTotal ?? 0);
      invoiceExcl = Number(this.preview?.invoiceAmountTotal ?? 0);
      estimateIncl =
        this.preview?.periodLineTaxInclusiveTotal != null
          ? Number(this.preview.periodLineTaxInclusiveTotal)
          : this.computeInclusive(estimateExcl, taxPercent);
      invoiceIncl =
        this.preview?.invoiceTaxInclusiveTotal != null
          ? Number(this.preview.invoiceTaxInclusiveTotal)
          : this.sumSavedInvoiceInclusiveForVersion(selected);
    } else {
      estimateExcl = Number(option?.periodLineAmountTotal ?? 0);
      if (option) {
        invoiceExcl = Number(option.invoiceAmountTotal ?? 0);
      } else {
        invoiceExcl = this.sumSavedInvoiceAmountForVersion(selected);
      }
      estimateIncl =
        option?.periodLineTaxInclusiveTotal != null
          ? Number(option.periodLineTaxInclusiveTotal)
          : this.computeInclusive(estimateExcl, taxPercent);
      invoiceIncl =
        option?.invoiceTaxInclusiveTotal != null
          ? Number(option.invoiceTaxInclusiveTotal)
          : this.sumSavedInvoiceInclusiveForVersion(selected);
    }
    return {
      estimateExcl,
      invoiceExcl: invoiceExcl + this.draftAmountDeltaForVersion(selected),
      estimateIncl,
      invoiceIncl:
        invoiceIncl + this.draftInclusiveDeltaForVersion(selected)
    };
  }

  get estimatePreviewTotal() {
    return this.totalsForVersion(this.versionKeyForTotals).estimateExcl;
  }

  get invoicePreviewTotal() {
    return this.totalsForVersion(this.versionKeyForTotals).invoiceExcl;
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
   * 仕様: Core 第7.8.5節
   */
  get manualAdjustmentAmount() {
    const selected = this.versionKeyForTotals;
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

  // 仕様: Core 第7.8.5節、第7.9.1節。フッタと確定は同じ合計。未保存ドラフトを含む。
  isAmountMatchedForVersion(selected) {
    const totals = this.totalsForVersion(selected);
    return Number(totals.invoiceExcl) === Number(totals.estimateExcl);
  }

  // 仕様: Core 第7.8.5節。保存済みヘッダーだけの税抜。確定判定には使わない。
  isSavedAmountMatchedForVersion(selected) {
    const totals = this.totalsForVersion(selected);
    const savedExcl =
      Number(totals.invoiceExcl) -
      Number(this.draftAmountDeltaForVersion(selected) || 0);
    return savedExcl === Number(totals.estimateExcl);
  }

  // 仕様: Core 第7.9.1節。各請求の税額が第11.9節の丸めで税抜×税率と一致。
  isInvoiceTaxMatched(invoice) {
    const expected = this.calculateTaxAmount(
      invoice?.amountTotal,
      invoice?.taxPercent
    );
    if (!Number.isFinite(expected)) {
      return false;
    }
    return Number(invoice?.taxTotal ?? 0) === expected;
  }

  isInvoiceTaxMatchedForVersion(selected) {
    for (const invoice of this.preview?.invoices || []) {
      if (this.isCancelledInvoice(invoice)) {
        continue;
      }
      if (
        selected !== ALL_VERSIONS &&
        this.versionKeyForInvoice(invoice) !== String(selected)
      ) {
        continue;
      }
      if (!this.isInvoiceTaxMatched(invoice)) {
        return false;
      }
    }
    return true;
  }

  // 仕様: Core 第7.6節。一括計上の検収終了日が空なら確定できない。
  hasEmptyAcceptanceForConfirm(invoice) {
    for (const line of invoice?.lines || []) {
      if (
        line.revenueRecognitionBasis === REVENUE_BASIS_POINT_IN_TIME &&
        !line.acceptanceEndDate
      ) {
        return true;
      }
    }
    return false;
  }

  // 仕様: Core 第7.9.1節、第7.8.5節、第7.6節、第3.3.7節。税込合計は見ない。フッタと同じ税抜合計。PdfAndEmailの届け方空は確定できない。
  confirmBlockedReason(invoice) {
    const versionKey = this.confirmVersionKey(invoice);
    if (!this.isAmountMatchedForVersion(versionKey)) {
      return "見積合計と請求合計（税抜）が一致しないため確定できません。";
    }
    if (!this.isInvoiceTaxMatchedForVersion(versionKey)) {
      return "請求書の税額が税抜と税率から計算した値と一致しないため確定できません。";
    }
    if (this.hasEmptyAcceptanceForConfirm(invoice)) {
      return "検収終了日が空の明細があるため確定できません。";
    }
    if ((this.preview?.invoiceSendMode || "") === SEND_MODE_PDF_AND_EMAIL) {
      const method = invoice?.invoiceDeliveryMethod;
      if (method == null || String(method).trim() === "") {
        return "組織の請求書設定がPDFとメール送付のとき、届け方が空の請求は確定できません。";
      }
    }
    return "";
  }

  get isAmountMatched() {
    return this.isAmountMatchedForVersion(this.versionKeyForTotals);
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
      return "この版に連携済または消込済の請求があるため編集できません。";
    }
    if (this.preview?.canEdit !== true) {
      return "請求ボード編集の権限がありません。";
    }
    return "";
  }

  // 仕様: Core 第7.7.0節、第7.7.3節、第7.11節、第8.4節、第8.8節、第8.10節、Accounting 第10.3節、第11.2節、第11.4節
  get invoiceCards() {
    const selected = this.selectedVersion;
    const filterAll = selected === ALL_VERSIONS;
    const lineSplitOpenId = this.lineSplitState?.invoiceId || null;
    const invoiceSplitOpenId = this.invoiceSplitState?.invoiceId || null;
    const invoiceMoveOpenId = this.invoiceMoveState?.invoiceId || null;
    const invoiceDestinationChoiceOpenId =
      this.invoiceDestinationChoiceState?.invoiceId || null;
    const splitLoading = this.lineSplitState?.loadingThresholds === true;
    const splitError = this.lineSplitState?.thresholdsError || "";

    return (this.preview?.invoices || [])
      .map((invoice, index) => {
        if (
          !this.includeCancelled &&
          this.isCancelledInvoice(invoice)
        ) {
          return null;
        }
        const invoiceVersion = this.versionKeyForInvoice(invoice);
        if (
          !filterAll &&
          invoiceVersion != null &&
          invoiceVersion !== String(selected)
        ) {
          return null;
        }
        if (
          this.selectedInvoiceId !== ALL_INVOICES &&
          invoice.invoiceId !== this.selectedInvoiceId
        ) {
          return null;
        }
        if (!this.invoiceMatchesDifferenceFilter(invoice)) {
          return null;
        }
        const invoiceId = invoice.invoiceId;
        const isCancelled = this.isCancelledInvoice(invoice);
        const isDraft = this.isDraftInvoice(invoice);
        const isConfirmed = this.isConfirmedInvoice(invoice);
        // 仕様: Core 第7.6節、Accounting 第1.1節・第3.2節。OFFは仕訳タブを出さない。
        const accountingEnabled =
          this.accountingEnabledOnBoard === true ||
          this.invoiceUiState[invoiceId]?.bundle?.accountingEnabled === true;
        const isLineSplitOpen = lineSplitOpenId === invoiceId;
        const isInvoiceSplitOpen = invoiceSplitOpenId === invoiceId;
        const isInvoiceMoveOpen = invoiceMoveOpenId === invoiceId;
        const isInvoiceDestinationChoiceOpen =
          invoiceDestinationChoiceOpenId === invoiceId;
        const canEditInvoice = this.canEdit && invoice.locked !== true;
        // 仕様: Core 第7.8節、第7.7.3節、第11.4.4節。請求情報編集は確定後も出す。取消済みは出さない。
        const showBillingEdit = this.canEdit && !isCancelled;
        const moveTargetOptions = isInvoiceMoveOpen
          ? this.buildMoveTargetOptions(invoice)
          : [];
        const sourceLines = invoice.lines || [];
        const lines = sourceLines.map((line, lineIndex) => {
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
              acceptanceEndDate:
                this.invoiceUiState[invoiceId]?.acceptanceDraft?.lineId ===
                lineId
                  ? this.invoiceUiState[invoiceId].acceptanceDraft.nextDate ||
                    ""
                  : line.acceptanceEndDate || "",
              // 仕様: Core 第7.6節・第1.1.5節・第12.2節。取消済みは参照だけ。
              showAcceptanceEndDateInput:
                accountingEnabled &&
                this.canEdit &&
                !isCancelled &&
                line.revenueRecognitionBasis === REVENUE_BASIS_POINT_IN_TIME,
              // 仕様: Core 第7.6節
              acceptanceEndDateDisabled:
                isCancelled ||
                line.revenueRecognitionBasis !== REVENUE_BASIS_POINT_IN_TIME ||
                !this.canEdit ||
                this.isSaving === true ||
                this.isAmountAdjustBlocked,
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
                canEditInvoice &&
                !isInvoiceSplitOpen &&
                !isInvoiceMoveOpen &&
                !isInvoiceDestinationChoiceOpen,
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
                      ? LOCKED_INVOICE_EDIT_NOTE
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
        // 仕様: Core 第7.7.3節、第7.8節、第7.8.4節
        const invoiceSplitEquationOk = hasInvoiceMoveSelection;
        const willEmptySourceOnMove =
          isInvoiceMoveOpen &&
          hasInvoiceMoveSelection &&
          selectedMoveLineCount >= lines.length;
        const canMoveLines =
          canEditInvoice && this.buildMoveTargetOptions(invoice).length > 0;
        const taxTotal = totals.taxTotal || 0;
        const taxInclusiveTotal = amountTotal + taxTotal;
        const amountAdjustDisabled =
          this.isSaving === true || this.isAmountAdjustBlocked;
        const amountAdjustBlockedTitle = this.isBillingEditUiOpen
          ? "請求情報編集をキャンセルまたは保存してから端数調整できます"
          : this.isSplitOrMoveUiOpen
              ? "別の請求へ分ける／分割をキャンセルまたは実行してから端数調整できます"
            : this.isSaving === true
              ? "保存中は端数調整できません"
              : "";
        const invoiceTransactionStatus =
          invoice.invoiceTransactionStatus || "Draft";
        const confirmedOrLater = isConfirmed;
        const invoiceOpsBusy =
          this.invoiceOpsProcessingId != null ||
          this.isSaving ||
          this.hasAmountDrafts ||
          this.isBillingEditUiOpen ||
          this.isSplitOrMoveUiOpen;
        const isInvoiceSendOpen =
          this.invoiceSendState?.invoiceId === invoiceId;
        const isInvoiceIssueOpen =
          this.invoiceIssueState?.invoiceId === invoiceId;
        let sendUnavailableReason = this.invoiceSendUnavailableReason(
          invoice,
          confirmedOrLater,
          isCancelled
        );
        let issueUnavailableReason = this.invoiceIssueUnavailableReason(
          confirmedOrLater,
          isCancelled
        );
        const uiState = this.invoiceUiState[invoiceId] || {
          activeTab: "lines",
          bundle: null,
          loading: false,
          error: "",
          paymentDraft: this.newPaymentDraft(invoiceId)
        };
        const bundle = uiState.bundle;
        const activeTab = uiState.activeTab || "lines";
        const paymentTypeOptions = this.paymentPurposeOptions();
        const paymentDraft = uiState.paymentDraft;
        const cancelDraft = uiState.cancelDraft;
        const invoicePaymentNet = Number(
          bundle?.invoicePaymentNet ?? invoice.invoicePaymentNet ?? 0
        );
        const allPaymentNet = Number(
          bundle?.paymentNetTotal ?? invoice.paymentNetTotal ?? 0
        );
        const gross = Number(
          bundle?.taxInclusiveAmount ??
            invoice.taxInclusiveAmount ??
            taxInclusiveTotal ??
            0
        );
        const invoiceUnprocessedNet = gross - invoicePaymentNet;
        // 仕様: Core 第8.10節。絶対値を残額表示に使い、符号で回収／返金方向を示す。
        const invoiceUnprocessedRemaining = Math.abs(invoiceUnprocessedNet);
        const invoiceUnprocessedDirectionLabel =
          invoiceUnprocessedNet > 0
            ? "回収"
            : invoiceUnprocessedNet < 0
              ? "返金"
              : "";
        const nonInvoiceNet = allPaymentNet - invoicePaymentNet;
        const balanceDifference = Math.round(allPaymentNet - gross);
        const dueStatus = invoice.dueStatus || "";
        const overdueDays = invoice.overdueDays;
        const showOverdueDays =
          overdueDays != null &&
          overdueDays !== "" &&
          Number.isFinite(Number(overdueDays));
        const paymentRows = (bundle?.payments || [])
          .filter(
            (payment) =>
              this.includeCancelledPayments || !this.isInactivePayment(payment)
          )
          .map((payment) => ({
            ...payment,
            key: payment.paymentId,
            statusLabel: this.paymentStatusLabel(payment),
            typeLabel: this.paymentPurposeLabel(
              payment.paymentPurpose || payment.paymentType
            ),
            showActions:
              (payment.canCancel === true ||
                (payment.paymentTransactionStatus === "Active" &&
                  !payment.isCancelled &&
                  !payment.isCancellation)) &&
              this.canPayInvoice === true &&
              !isCancelled,
            canEditPayment:
              this.canEditDraftInvoiceOp === true &&
              payment.paymentTransactionStatus === "Active" &&
              !payment.isCancelled &&
              !payment.isCancellation &&
              !isCancelled,
            isPaymentEditOpen:
              this.paymentEditState?.invoiceId === invoiceId &&
              this.paymentEditState?.paymentId === payment.paymentId
          }));
        const opsBusy = this.invoiceOpsProcessingId != null;
        const purpose = paymentDraft?.purpose || "Invoice";
        const inputAmount = Number(paymentDraft?.amount);
        // 仕様: Core 第8.3節。0円と小数は登録しない。
        const amountNotInteger =
          Number.isFinite(inputAmount) &&
          inputAmount !== Math.trunc(inputAmount);
        const isInvoicePurpose = purpose === "Invoice";
        const paymentAllocationRows = isInvoicePurpose
          ? paymentDraft?.allocations || []
          : [];
        const allocationTotal = paymentAllocationRows.reduce(
          (sum, row) => sum + Number(row.amount || 0),
          0
        );
        const sameSignOverflow =
          isInvoicePurpose &&
          inputAmount &&
          invoiceUnprocessedNet !== 0 &&
          Math.sign(inputAmount) === Math.sign(invoiceUnprocessedNet) &&
          Math.abs(inputAmount) > Math.abs(invoiceUnprocessedNet);
        const signMismatch =
          isInvoicePurpose &&
          inputAmount &&
          invoiceUnprocessedNet !== 0 &&
          Math.sign(inputAmount) !== Math.sign(invoiceUnprocessedNet);
        const invoicePurposeBlocked =
          isInvoicePurpose && invoiceUnprocessedNet === 0;
        const paymentAllocationTotalMismatch =
          isInvoicePurpose &&
          inputAmount !== 0 &&
          allocationTotal !== inputAmount;
        const paymentAllocationExceeds = paymentAllocationRows.some(
          (row) =>
            !this.isWithinLineRemaining(row.amount, row.remainingInclusive)
        );
        const invoiceDateIso = String(
          bundle?.invoiceDate || invoice.invoiceDate || ""
        ).slice(0, 10);
        const paymentDateIso = String(paymentDraft?.paymentDate || "").slice(
          0,
          10
        );
        const showPaymentDateBeforeInvoiceWarning = Boolean(
          paymentDateIso && invoiceDateIso && paymentDateIso < invoiceDateIso
        );
        const effectiveTransactionStatus =
          bundle?.invoiceTransactionStatus || invoiceTransactionStatus;
        const canAddPayment =
          bundle?.paymentAllowed === true &&
          paymentTypeOptions.length > 0 &&
          !opsBusy;
        const cancelBlockedReason = this.invoiceCancelBlockedReason(bundle);

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
          draftBeforeAmount: isDraft ? gross : 0,
          showDraftBefore: isDraft,
          invoiceUnprocessedNet,
          invoiceUnprocessedRemaining,
          invoiceUnprocessedDirectionLabel,
          invoiceProcessedNet: invoicePaymentNet,
          nonInvoiceNet,
          balanceDifference,
          dueStatus,
          showDueLabel: Boolean(dueStatus),
          overdueDays: showOverdueDays ? Number(overdueDays) : null,
          showOverdueDays,
          isCancelled,
          cancelledLabel: isCancelled ? "取消済み" : "",
          // 仕様: Core 第12.2節・第7.7.3節。取消済みは参照だけ。メモ編集は未確定・確定済み。
          canEditInvoiceMemo: this.canEdit && !isCancelled,
          // 仕様: Core 第12.2節・第7.7.3節。仕訳メモも取消済みでは参照だけ。
          canEditJournalMemo: this.canEdit && !isCancelled,
          // 仕様: Accounting 第9.5節、共通基盤 第10.4節、Core 第7.7.3節・第12.2節。
          // LockとUnlockはそれぞれ専用権限。無い操作は出さない。閲覧・編集・確定では代替しない。
          showJournalLockButton:
            accountingEnabled && !isCancelled && this.canLockJournal,
          showJournalUnlockButton:
            accountingEnabled && !isCancelled && this.canUnlockJournal,
          showJournalLockActions:
            accountingEnabled &&
            !isCancelled &&
            (this.canLockJournal || this.canUnlockJournal),
          memoDraft:
            this.memoDrafts[invoiceId] != null
              ? this.memoDrafts[invoiceId]
              : invoice.memo || "",
          isInvoiceCancelOpen:
            this.invoiceCancelState?.invoiceId === invoiceId,
          requiresCustomerNotice: invoice.deliveryStatus === "Sent",
          customerNotice:
            invoice.deliveryStatus === "Sent" ? CUSTOMER_CANCEL_NOTICE : "",
          cancelReason: this.invoiceCancelState?.cancellationReason || "",
          cancelReasonText:
            this.invoiceCancelState?.cancellationReasonText || "",
          cancelDate: this.invoiceCancelState?.cancellationDate || "",
          cancelRequiresDate: requiresCancelDate(bundle),
          cancelReasonTextRequired:
            this.invoiceCancelState?.cancellationReason === "Other",
          invoiceCancelConfirmDisabled:
            invoiceOpsBusy ||
            Boolean(cancelBlockedReason) ||
            !this.invoiceCancelState?.cancellationReason ||
            (this.invoiceCancelState?.cancellationReason === "Other" &&
              this.isBlankReasonText(
                this.invoiceCancelState?.cancellationReasonText
              )) ||
            (requiresCancelDate(bundle) &&
              !this.invoiceCancelState?.cancellationDate),
          showCancelAction:
            isConfirmed && !isCancelled && this.canCancelInvoiceOp === true,
          isManuallyAdjusted: invoice.isManuallyAdjusted === true,
          billingAccountId: invoice.billingAccountId || "",
          billingAccountName: invoice.billingAccountName || "—",
          billingAddressee: invoice.billingAddressee || "—",
          invoiceDeliveryMethod: invoice.invoiceDeliveryMethod || "",
          invoiceDeliveryMethodLabel: deliveryMethodLabel(
            invoice.invoiceDeliveryMethod
          ),
          billingEmailTo: invoice.billingEmailTo || "",
          billingEmailCc: invoice.billingEmailCc || "",
          billingEmailBcc: invoice.billingEmailBcc || "",
          paymentTerm: invoice.paymentTerm || "",
          invoiceTransactionStatus: effectiveTransactionStatus,
          invoiceTransactionStatusLabel: this.transactionStatusLabel(
            effectiveTransactionStatus
          ),
          sentDate: bundle?.sentDate || invoice.sentDate || "",
          sentDateLabel: this.sentDateDisplay(
            bundle?.sentDate || invoice.sentDate,
            invoice.deliveryStatus
          ),
          sentStatusLabel: this.deliveryStatusLabel(invoice.deliveryStatus),
          lastModifiedToken: invoice.lastModifiedToken || "",
          // 仕様: Core 第12.2節・第7.9節。サーバ markInvoiced と同じ請求入出金操作権限（13）。
          showConfirmAction:
            invoice.canConfirm === true &&
            !isCancelled &&
            this.canConfirmInvoiceOp === true,
          confirmActionTitle: this.confirmBlockedReason(invoice),
          // 仕様: Core 第12.2節・第4.10節・第7.10節。サーバと同じ請求入出金操作権限（13）。
          showIssueAction:
            confirmedOrLater &&
            this.canIssueDocument &&
            this.canSendInvoiceDocument === true,
          showViewPdfAction: Boolean(invoice.latestIssuedContentDocumentId),
          latestIssuedContentDocumentId:
            invoice.latestIssuedContentDocumentId || "",
          showSendAction:
            confirmedOrLater &&
            this.canSendDocument &&
            invoice.invoiceDeliveryMethod === "Email" &&
            this.canSendInvoiceDocument === true,
          confirmActionDisabled:
            invoiceOpsBusy ||
            this.hasAmountDrafts ||
            Boolean(this.confirmBlockedReason(invoice)),
          cancelActionDisabled: invoiceOpsBusy || Boolean(cancelBlockedReason),
          cancelActionTitle: cancelBlockedReason,
          confirmationReason: invoice.confirmationReason || "",
          issueActionDisabled:
            invoiceOpsBusy || Boolean(issueUnavailableReason),
          issueActionTitle: issueUnavailableReason,
          sendActionLabel: invoice.sentDate ? "再送" : "送付",
          sendActionDisabled: invoiceOpsBusy || Boolean(sendUnavailableReason),
          sendActionTitle: sendUnavailableReason,
          isInvoiceSendOpen,
          isInvoiceIssueOpen,
          invoiceIssueDocumentTemplateKey: isInvoiceIssueOpen
            ? this.invoiceIssueState.documentTemplateKey
            : "",
          invoiceIssueFileName: isInvoiceIssueOpen
            ? this.invoiceIssueState.fileName || ""
            : "",
          showInvoiceIssuePdfPreview:
            isInvoiceIssueOpen &&
            Boolean(invoice.latestIssuedContentDocumentId),
          invoiceIssuePdfPreviewUrl: this.issuedPdfPreviewUrl(
            isInvoiceIssueOpen
              ? invoice.latestIssuedContentDocumentId
              : ""
          ),
          showInvoiceIssuePdfDownload:
            isInvoiceIssueOpen &&
            Boolean(invoice.latestIssuedContentDocumentId),
          invoiceIssuePdfDownloadUrl: this.issuedPdfDownloadUrl(
            isInvoiceIssueOpen
              ? invoice.latestIssuedContentDocumentId
              : ""
          ),
          invoiceIssueConfirmDisabled:
            invoiceOpsBusy ||
            !isInvoiceIssueOpen ||
            !this.invoiceIssueState?.documentTemplateKey ||
            !this.invoiceIssueState?.fileName ||
            !this.isBlankReasonText(this.companyBlockedReason),
          invoiceDocumentTemplateKey: isInvoiceSendOpen
            ? this.invoiceSendState.documentTemplateKey
            : "",
          invoiceEmailTemplateApiName: isInvoiceSendOpen
            ? this.invoiceSendState.emailTemplateApiName
            : "",
          invoiceFromLabel: isInvoiceSendOpen
            ? this.invoiceSendState.fromLabel || ""
            : "",
          invoiceDraftTo: isInvoiceSendOpen
            ? this.invoiceSendState.toAddresses || ""
            : "",
          invoiceDraftCc: isInvoiceSendOpen
            ? this.invoiceSendState.ccAddresses || ""
            : "",
          invoiceDraftBcc: isInvoiceSendOpen
            ? this.invoiceSendState.bccAddresses || ""
            : "",
          invoiceDraftSubject: isInvoiceSendOpen
            ? this.invoiceSendState.subject || ""
            : "",
          invoiceDraftBody: isInvoiceSendOpen
            ? this.invoiceSendState.body || ""
            : "",
          invoiceDraftFileName: isInvoiceSendOpen
            ? this.invoiceSendState.fileName || ""
            : "",
          invoiceAttachmentId: isInvoiceSendOpen
            ? this.invoiceSendState.attachmentId || ""
            : "",
          invoiceAttachmentOptions: isInvoiceSendOpen
            ? this.invoiceSendState.attachmentOptions || []
            : [],
          showInvoiceDocumentTemplatePicker:
            isInvoiceSendOpen && this.invoiceSendState.attachmentId === "NEW",
          showExistingFilePreview:
            isInvoiceSendOpen &&
            Boolean(this.invoiceSendState.attachmentId) &&
            this.invoiceSendState.attachmentId !== "NEW",
          existingFilePreviewUrl:
            isInvoiceSendOpen &&
            this.invoiceSendState.attachmentId &&
            this.invoiceSendState.attachmentId !== "NEW"
              ? `/lightning/r/ContentDocument/${this.invoiceSendState.attachmentId}/view`
              : "",
          invoiceDocumentTemplateOptions: this.invoiceDocumentTemplateOptions,
          invoiceEmailTemplateOptions: this.invoiceEmailTemplateOptions,
          invoiceSendConfirmDisabled:
            invoiceOpsBusy ||
            !isInvoiceSendOpen ||
            !this.invoiceSendState?.documentTemplateKey ||
            !this.invoiceSendState?.emailTemplateApiName ||
            this.isBlankReasonText(this.invoiceSendState?.toAddresses) ||
            this.hasInvalidEmailList(this.invoiceSendState?.toAddresses) ||
            this.hasInvalidEmailList(this.invoiceSendState?.ccAddresses) ||
            this.hasInvalidEmailList(this.invoiceSendState?.bccAddresses) ||
            !this.invoiceSendState?.attachmentId ||
            this.isBlankReasonText(this.invoiceSendState?.fileName) ||
            this.orgFromResolved !== true,
          isInvoiceSplitOpen,
          isInvoiceMoveOpen,
          isInvoiceDestinationChoiceOpen,
          isLineSplitOpen,
          showSplitSelectCol,
          showLineSplitActionBar: isLineSplitOpen && hasLineSplitSelection,
          // V〜金額の9列（選択列があるときは+1）。行操作列は廃止済み。
          splitControlsColspan: showSplitSelectCol ? 10 : 9,
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
                ? LOCKED_INVOICE_EDIT_NOTE
                : !canMoveLines
                  ? "同じ版に移せる未ロックの請求がありません"
                  : "",
          isBillingEditOpen,
          locked: invoice.locked === true,
          canEditInvoice,
          showBillingEdit,
          billingCoreFieldsDisabled: isConfirmed,
          billingExtraFields: isBillingEditOpen
            ? this.buildExtraFieldViews({
                targetObject: "Invoice__c",
                storedValues: invoice.extraFieldValues,
                draftValues: this.billingEditState?.extraFieldValues,
                disabledAll: false,
                exemptNames: this.preview?.invoiceLockExemptFieldApiNames,
                requireExemptToEdit: isConfirmed
              })
            : [],
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
            invoice.locked === true ? LOCKED_INVOICE_EDIT_NOTE : "",
          billingEditDisabled:
            this.hasAmountDrafts || this.isSplitOrMoveUiOpen,
          billingEditTitle: this.isSplitOrMoveUiOpen
            ? "別の請求へ分ける／分割をキャンセルまたは実行してから操作できます"
            : this.hasAmountDrafts
              ? "端数調整の保存または取消後に操作できます"
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
                ? LOCKED_INVOICE_EDIT_NOTE
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
            : this.billingEditTaxPercent(invoice.taxPercent),
          activeTab,
          isLinesTab: activeTab === "lines",
          isPaymentsTab: activeTab === "payments",
          // 仕様: Accounting 第1.1節。OFFは仕訳タブ内容を出さない。
          isJournalsTab: accountingEnabled && activeTab === "journals",
          linesTabClass:
            activeTab === "lines" ? "invoice-tab invoice-tab_active" : "invoice-tab",
          paymentsTabClass:
            activeTab === "payments"
              ? "invoice-tab invoice-tab_active"
              : "invoice-tab",
          journalsTabClass:
            activeTab === "journals"
              ? "invoice-tab invoice-tab_active"
              : "invoice-tab",
          showJournalsTab: accountingEnabled,
          opsLoading: uiState.loading === true,
          opsError: uiState.error,
          payments: paymentRows,
          hasPayments: paymentRows.length > 0,
          includeCancelledPayments: this.includeCancelledPayments,
          paymentTypeOptions,
          cancellationReasonOptions: this.cancellationReasonOptions(),
          paymentDraftAmount: paymentDraft?.amount ?? "",
          paymentDraftType: purpose,
          paymentDraftDate: paymentDraft?.paymentDate || "",
          paymentDraftMemo: paymentDraft?.memo || "",
          paymentRegisterExtraFields: this.buildExtraFieldViews({
            targetObject: "InvoicePayment__c",
            storedValues: {},
            draftValues: paymentDraft?.extraFieldValues,
            purpose,
            disabledAll: false
          }),
          isPaymentEditOpen: this.paymentEditState?.invoiceId === invoiceId,
          paymentEditMemo: this.paymentEditState?.memo || "",
          paymentEditAmount: this.paymentEditState?.amount,
          paymentEditDate: this.paymentEditState?.paymentDate || "",
          paymentEditPurposeLabel: this.paymentPurposeLabel(
            this.paymentEditState?.paymentPurpose
          ),
          paymentEditExtraFields:
            this.paymentEditState?.invoiceId === invoiceId
              ? this.buildExtraFieldViews({
                  targetObject: "InvoicePayment__c",
                  storedValues: this.paymentEditState?.storedExtraFieldValues,
                  draftValues: this.paymentEditState?.extraFieldValues,
                  purpose: this.paymentEditState?.paymentPurpose,
                  disabledAll: false,
                  exemptNames: this.preview?.paymentLockExemptFieldApiNames,
                  requireExemptToEdit: true
                })
              : [],
          paymentRegisterRequiresDate: requiresPaymentRegisterCancelDate(bundle),
          paymentRegisterCancelDate: paymentDraft?.cancellationDate || "",
          paymentFormTitle: "入出金を追加",
          paymentSaveLabel: "追加",
          paymentBlockedReason: bundle?.paymentBlockedReason || "",
          showPaymentCancelForm: Boolean(cancelDraft),
          // 仕様: Core 第12.2節・第8.4節。表示もサーバと同じ請求入出金操作権限（13）。
          showPaymentForm:
            bundle?.paymentAllowed === true &&
            !cancelDraft &&
            this.canPayInvoice === true,
          showPaymentAllocations:
            isInvoicePurpose && paymentAllocationRows.length > 0 && !cancelDraft,
          paymentAllocationRows,
          paymentAllocationsLocked:
            isInvoicePurpose &&
            inputAmount === invoiceUnprocessedNet &&
            invoiceUnprocessedNet !== 0,
          paymentAllocationTotalMismatch,
          showPaymentOverflow: sameSignOverflow === true,
          paymentOverflowPurposeLabel: this.paymentPurposeLabel(purpose),
          paymentAllowedAmount: invoiceUnprocessedNet,
          paymentInputAmount: inputAmount,
          paymentExcessAmount: sameSignOverflow
            ? inputAmount - invoiceUnprocessedNet
            : 0,
          showPaymentDateBeforeInvoiceWarning,
          paymentCancelInvoiceName: cancelDraft?.invoiceName || "",
          paymentCancelPurposeLabel: cancelDraft?.purposeLabel || "",
          paymentCancelAmount: cancelDraft?.amount,
          paymentCancelDateDisplay: cancelDraft?.paymentDate || "",
          paymentCancelReason: cancelDraft?.cancellationReason || "",
          paymentCancelReasonText: cancelDraft?.cancellationReasonText || "",
          paymentCancelRequiresDate: cancelDraft?.requiresDate === true,
          paymentCancelDate: cancelDraft?.cancelDate || "",
          paymentCancelSaveDisabled:
            opsBusy ||
            !cancelDraft?.cancellationReason ||
            (cancelDraft?.cancellationReason === "Other" &&
              this.isBlankReasonText(cancelDraft?.cancellationReasonText)) ||
            (cancelDraft?.requiresDate === true && !cancelDraft?.cancelDate),
          paymentSaveDisabled:
            !canAddPayment ||
            Boolean(cancelDraft) ||
            !inputAmount ||
            inputAmount === 0 ||
            amountNotInteger ||
            !purpose ||
            !paymentDraft?.paymentDate ||
            (requiresPaymentRegisterCancelDate(bundle) &&
              !paymentDraft?.cancellationDate) ||
            sameSignOverflow ||
            signMismatch ||
            invoicePurposeBlocked ||
            (isInvoicePurpose &&
              (paymentAllocationTotalMismatch ||
                paymentAllocationExceeds ||
                paymentAllocationRows.length === 0)),
          acceptanceCancelDraft: uiState.acceptanceDraft || null,
          acceptanceCancelDate: uiState.acceptanceDraft?.cancellationDate || "",
          acceptanceCancelSaveDisabled:
            opsBusy ||
            (uiState.acceptanceDraft?.requiresDate === true &&
              !uiState.acceptanceDraft?.cancellationDate),
          // 仕様: Accounting 第1.1節。OFFは仕訳タブも停止中注記も出さない。
          showAccountingOffNote: false,
          accountingEnabled,
          // 仕様: Core 第7.6節、Accounting 第3.2節
          showAcceptanceEndDateColumn: accountingEnabled,
          // 仕様: Accounting 第11.4節・第10.3節・第10.4節、Core 第12.2節。
          // 確定済み・未取消・請求入出金操作権限（13）。表示もサーバと同じ。
          showManualJournalEntry:
            bundle?.accountingEnabled === true &&
            isConfirmed &&
            !isCancelled &&
            this.canManualJournalOp === true,
          journals: (bundle?.journals || [])
            .filter((journal) =>
              journalMatchesFilters(
                journal,
                this.journalEventFilter || [],
                this.journalStatusFilter || [],
                this.journalLockFilter || []
              )
            )
            .map((journal) => ({
            ...journal,
            key: journal.journalId,
            extraRowKey: `${journal.journalId}-extras`,
            eventName:
              journal.eventName || journal.eventKey || "",
            postingPeriod: postingPeriodLabel(
              journal.postingDate,
              this.todayLocalIso()
            ),
            transactionStatusLabel: this.journalTransactionStatusLabel(
              journal.transactionStatus
            ),
            lockLabel: journal.isLocked ? "Lock" : "未Lock",
            extrasOpen: this.journalToggleOpen[journal.journalId] === true,
            toggleGlyph:
              this.journalToggleOpen[journal.journalId] === true ? "▾" : "▸",
            confirmationText: journal.confirmationText || "",
            extraFields: this.buildExtraFieldViews({
              targetObject: "GlJournal__c",
              storedValues: journal.extraFieldValues,
              draftValues: this.journalExtraDrafts[journal.journalId],
              disabledAll: isCancelled || !this.canEdit,
              exemptNames: this.preview?.journalLockExemptFieldApiNames,
              requireExemptToEdit: journal.isLocked === true
            }),
            canSaveJournalExtras: this.canEdit && !isCancelled,
            // 仕様: Accounting 第2.3節・第9.5節、Core 第7.7.3節。
            // 手動Lock／Unlockの選択は有効仕訳だけ。監査表示の論理削除・取消済・取消は選べない。
            canSelectForJournalLock: journal.transactionStatus === "Active",
            journalSelected:
              journal.transactionStatus === "Active" &&
              this.journalLockSelected?.[invoiceId]?.[journal.journalId] ===
                true,
            memoDraft:
              this.journalMemoDrafts[journal.journalId] != null
                ? this.journalMemoDrafts[journal.journalId]
                : journal.memo || "",
            rowClass:
              journal.journalId === this.highlightJournalId
                ? "journal-row journal-row_highlight"
                : "journal-row"
          })),
          hasJournals: (bundle?.journals || []).length > 0,
          tagResults: bundle?.tagResults || [],
          hasTagResults: (bundle?.tagResults || []).length > 0,
          manualSettings: bundle?.manualSettings || [],
          manualJournals: (bundle?.manualJournals || []).map((header) => ({
            ...header,
            transactionStatusLabel:
              header.transactionStatusLabel ||
              this.manualJournalStatusLabel(header.transactionStatus)
          })),
          hasLockedJournals: bundle?.hasLockedJournals === true,
          hasUnlockedJournals: bundle?.hasUnlockedJournals === true,
          unlockReason: this.unlockReason,
          // 仕様: Core 第12.2節。取消済みではLock操作を出せない。
          journalLockDisabled:
            opsBusy ||
            isCancelled ||
            !this.selectedJournalIds(invoiceId).length,
          // 仕様: Accounting 第9.5節・第9.1節、Core 第1.1.10節。Unlockは理由必須。255超は止める。
          journalUnlockDisabled:
            opsBusy ||
            isCancelled ||
            !this.selectedJournalIds(invoiceId).length ||
            this.isBlankReasonText(this.unlockReason) ||
            this.isUnlockReasonTooLong(this.unlockReason),
          applyBillingDisabled:
            this.hasAmountDrafts ||
            this.isSplitOrMoveUiOpen ||
            this.isBillingEditUiOpen ||
            invoice.locked === true ||
            !invoice.billingAccountId,
          applyBillingTitle: !invoice.billingAccountId
            ? "請求アカウントがありません。"
            : this.isBillingEditUiOpen
              ? "請求情報編集をキャンセルまたは保存してから反映できます"
              : this.isSplitOrMoveUiOpen
                ? "別の請求へ分ける／分割をキャンセルまたは実行してから反映できます"
                : this.hasAmountDrafts
                  ? "端数調整の保存または取消後に反映できます"
                  : "",
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
            "未保存の端数調整があります。保存または取消してから版を切り替えてください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    this.selectedVersion = next;
    this.selectedInvoiceId = ALL_INVOICES;
  }

  handleInvoiceFilterChange(event) {
    this.selectedInvoiceId = event.detail.value || ALL_INVOICES;
  }

  handleDifferenceFilterChange(event) {
    this.selectedDifferenceFilter = event.detail.value || ALL_DIFFERENCES;
    if (
      this.selectedDifferenceFilter !== ALL_DIFFERENCES &&
      this.selectedInvoiceId !== ALL_INVOICES
    ) {
      const current = this.findInvoice(this.selectedInvoiceId);
      if (current && !this.invoiceMatchesDifferenceFilter(current)) {
        this.selectedInvoiceId = ALL_INVOICES;
      }
    }
  }

  handleIncludeCancelledPaymentsChange(event) {
    this.includeCancelledPayments = event.target.checked === true;
  }

  handleIncludeCancelledChange(event) {
    this.includeCancelled = event.target.checked === true;
    if (
      !this.includeCancelled &&
      this.selectedInvoiceId !== ALL_INVOICES
    ) {
      const current = this.findInvoice(this.selectedInvoiceId);
      if (this.isCancelledInvoice(current)) {
        this.selectedInvoiceId = ALL_INVOICES;
      }
    }
  }

  // 仕様: Core 第7.11節
  deliveryStatusLabel(status) {
    if (status === "Sent") {
      return "送付済";
    }
    if (status === "Unsent") {
      return "未送付";
    }
    if (status === "NotApplicable") {
      return "対象外";
    }
    return "";
  }

  // 仕様: Core 第7.11節
  sentDateDisplay(sentDate, deliveryStatus) {
    if (sentDate) {
      return sentDate;
    }
    return this.deliveryStatusLabel(deliveryStatus);
  }

  // 仕様: Core 第7.7.2節・第6.6節。ONの確認だけ検収終了日を名指しする。
  isAccountingEnabledForBoard() {
    if (this.accountingEnabledOnBoard === true) {
      return true;
    }
    const states = this.invoiceUiState || {};
    return Object.keys(states).some(
      (invoiceId) => states[invoiceId]?.bundle?.accountingEnabled === true
    );
  }

  // 仕様: Core 第7.7.2節。Accounting ONの確認だけ検収終了日を名指しする。
  resetPostOrderConfirmMessage() {
    if (this.isAccountingEnabledForBoard()) {
      return "この版の請求書・請求明細を、受注直後の状態に作り直します。分割や端数・請求日・検収終了日などの手直しはすべて消えます。よろしいですか？";
    }
    return "この版の請求書・請求明細を、受注直後の状態に作り直します。分割や端数・請求日などの手直しはすべて消えます。よろしいですか？";
  }

  async handleResetPostOrderClick() {
    if (!this.showResetPostOrderButton || this.resetPostOrderDisabled) {
      return;
    }
    const confirmed = await LightningConfirm.open({
      label: "受注直後の請求に戻す",
      message: this.resetPostOrderConfirmMessage(),
      theme: "warning",
      variant: "header"
    });
    if (!confirmed) {
      return;
    }
    const versionInvoices = (this.preview?.invoices || []).filter(
      (invoice) =>
        invoice?.historyVersion != null &&
        String(Number(invoice.historyVersion)) ===
          String(this.selectedVersion) &&
        !this.isCancelledInvoice(invoice)
    );
    const expectedTokenByInvoiceId = {};
    for (const invoice of versionInvoices) {
      if (invoice?.invoiceId) {
        expectedTokenByInvoiceId[invoice.invoiceId] = invoice.lastModifiedToken;
      }
    }
    const keyInvoiceId = versionInvoices[0]?.invoiceId;
    this.dispatchEvent(
      new CustomEvent("resetpostorder", {
        detail: {
          versionValue: String(this.selectedVersion),
          expectedTokenByInvoiceId,
          businessOperationKey: keyInvoiceId
            ? await this.resolvePendingOperationKey(keyInvoiceId)
            : null
        }
      })
    );
  }

  // 仕様: Accounting 第1.1節、Core 第7.9節。OFFの確定確認に仕訳の結果表示を伴わない。
  confirmInvoiceMessage() {
    if (this.accountingEnabledOnBoard === true) {
      return "この請求を確定します。確定後は内容がロックされ、仕訳が作成されます。よろしいですか？";
    }
    return "この請求を確定します。確定後は内容がロックされます。よろしいですか？";
  }

  // 仕様: Core 第7.8.5節、第7.9.1節、第7.8.2節。フッタと同じ合計。未保存端数中は確定しない。
  async handleConfirmInvoice(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    const invoice = this.findInvoice(invoiceId);
    if (
      !invoice ||
      invoice.canConfirm !== true ||
      this.hasAmountDrafts ||
      Boolean(this.confirmBlockedReason(invoice))
    ) {
      return;
    }
    const confirmed = await LightningConfirm.open({
      label: "請求を確定",
      message: this.confirmInvoiceMessage(),
      variant: "header"
    });
    if (!confirmed) {
      return;
    }
    await this.runInvoiceOperation(invoiceId, "confirm", async () => {
      const key = await this.resolvePendingOperationKey(invoiceId);
      const result = await confirmInvoice({
        invoiceId,
        // 仕様: Core 第7.9節。確定日はサーバが組織TZの操作日を書く。画面の日付引数では書かない。
        confirmationDate: null,
        expectedToken: invoice.lastModifiedToken,
        businessOperationKey: key,
        contractHistoryId: this.contractHistoryId
      });
      this.clearPendingOperationKey(invoiceId);
      if (result?.issueWarning) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "確定後のPDF発行ができませんでした",
            message: result.issueWarning,
            variant: "warning",
            mode: "sticky"
          })
        );
      }
    });
  }

  /** 仕様: 横断画面.md 操作21。発行画面のプレビューは標準 Files。 */
  issuedPdfPreviewUrl(documentId) {
    return documentId
      ? `/lightning/r/ContentDocument/${documentId}/view`
      : "";
  }

  /** 仕様: 横断画面.md 操作21。発行画面で最新PDFをダウンロードする。PDFを見るは操作23。 */
  issuedPdfDownloadUrl(documentId) {
    return documentId
      ? `/sfc/servlet.shepherd/document/download/${documentId}`
      : "";
  }

  // 仕様: Core 第7.7.3節、第7.10節。印付きのうち最新の1つを標準 Files プレビューで開く。
  handleViewIssuedPdf(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    const documentId = this.findInvoice(invoiceId)?.latestIssuedContentDocumentId;
    if (!documentId) {
      return;
    }
    window.open(`/lightning/r/ContentDocument/${documentId}/view`, "_blank");
  }

  // 仕様: Core 第4.8節、第7.7.3節、第7.10節、第11.3.2節
  async handleIssueInvoice(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    const invoice = this.findInvoice(invoiceId);
    if (!invoice || !this.canIssueDocument || invoice.issueActionDisabled) {
      return;
    }
    if (this.invoiceOpsProcessingId != null) {
      return;
    }
    this.invoiceSendState = null;
    this.updateInvoiceUiState(invoiceId, { activeTab: "lines" });
    this.invoiceIssueState = {
      invoiceId,
      documentTemplateKey: this.defaultInvoiceDocumentTemplateKey,
      fileName: ""
    };
    try {
      await this.reloadInvoiceIssuePreview();
    } catch (error) {
      this.invoiceIssueState = null;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: this.reduceInvoiceOpsError(error),
          variant: "error"
        })
      );
    }
  }

  async reloadInvoiceIssuePreview() {
    if (!this.invoiceIssueState?.invoiceId) {
      return;
    }
    const preview = await previewIssueInvoice({
      invoiceId: this.invoiceIssueState.invoiceId,
      documentTemplateKey: this.invoiceIssueState.documentTemplateKey || null,
      contractHistoryId: this.contractHistoryId
    });
    this.invoiceIssueState = {
      ...this.invoiceIssueState,
      fileName: preview?.fileName || "",
      documentTemplateKey:
        preview?.documentTemplateKey || this.invoiceIssueState.documentTemplateKey
    };
  }

  handleCloseInvoiceIssue() {
    if (this.invoiceOpsProcessingId == null) {
      this.invoiceIssueState = null;
    }
  }

  async handleInvoiceIssueTemplateChange(event) {
    if (!this.invoiceIssueState) {
      return;
    }
    this.invoiceIssueState = {
      ...this.invoiceIssueState,
      documentTemplateKey: event.detail.value
    };
    try {
      await this.reloadInvoiceIssuePreview();
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: this.reduceInvoiceOpsError(error),
          variant: "error"
        })
      );
    }
  }

  async handleSubmitInvoiceIssue() {
    const invoiceId = this.invoiceIssueState?.invoiceId;
    const invoice = this.findInvoice(invoiceId);
    if (
      !invoice ||
      !this.invoiceIssueState?.documentTemplateKey ||
      this.invoiceOpsProcessingId != null ||
      !this.isBlankReasonText(this.companyBlockedReason)
    ) {
      return;
    }
    const documentTemplateKey = this.invoiceIssueState.documentTemplateKey;
    // 仕様: Core 第7.10節。処理中は発行を押せない。後着はサーバ行ロックで失敗する。
    await this.runInvoiceOperation(invoiceId, "issue", () =>
      issueInvoiceDocument({
        invoiceId,
        documentTemplateKey,
        expectedToken: invoice.lastModifiedToken,
        contractHistoryId: this.contractHistoryId
      })
    );
  }

  // 仕様: Core 第7.10節
  async handleOpenInvoiceSend(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    if (!invoiceId || this.invoiceOpsProcessingId != null) {
      return;
    }
    this.invoiceIssueState = null;
    this.updateInvoiceUiState(invoiceId, { activeTab: "lines" });
    this.invoiceSendState = {
      invoiceId,
      documentTemplateKey: this.defaultInvoiceDocumentTemplateKey,
      emailTemplateApiName: this.defaultInvoiceEmailTemplateApiName
    };
    try {
      await this.reloadInvoiceSendPreview();
    } catch (error) {
      this.invoiceSendState = null;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: this.reduceInvoiceOpsError(error),
          variant: "error"
        })
      );
    }
  }

  async reloadInvoiceSendPreview() {
    if (!this.invoiceSendState?.invoiceId) {
      return;
    }
    const previousAttachmentId = this.invoiceSendState.attachmentId;
    const previousFileName = this.invoiceSendState.fileName;
    const preview = await previewInvoiceSend({
      invoiceId: this.invoiceSendState.invoiceId,
      documentTemplateKey: this.invoiceSendState.documentTemplateKey,
      emailTemplateApiName: this.invoiceSendState.emailTemplateApiName,
      preferredAttachmentId: this.invoiceSendState.attachmentId || null,
      contractHistoryId: this.contractHistoryId
    });
    const nextAttachmentId = preview?.attachmentId || "";
    let nextFileName = preview?.fileName || "";
    // 仕様: Core 第7.10節。帳票変更のファイル名やり直しは新しく発行するときだけ。
    if (
      nextAttachmentId &&
      nextAttachmentId !== "NEW" &&
      nextAttachmentId === previousAttachmentId &&
      previousFileName
    ) {
      nextFileName = previousFileName;
    }
    this.invoiceSendState = {
      ...this.invoiceSendState,
      fromLabel: preview?.fromLabel || "",
      toAddresses: preview?.toAddresses || "",
      ccAddresses: preview?.ccAddresses || "",
      bccAddresses: preview?.bccAddresses || "",
      subject: preview?.subject || "",
      body: preview?.body || "",
      fileName: nextFileName,
      attachmentId: nextAttachmentId,
      attachmentOptions: (preview?.attachmentOptions || []).map((item) => ({
        label: item.label,
        value: item.value,
        fileName: item.fileName
      })),
      newIssueFileName: preview?.newIssueFileName || "",
      documentTemplateKey:
        preview?.documentTemplateKey || this.invoiceSendState.documentTemplateKey,
      emailTemplateApiName:
        preview?.emailTemplateApiName || this.invoiceSendState.emailTemplateApiName
    };
  }

  handleCloseInvoiceSend() {
    if (this.invoiceOpsProcessingId == null) {
      this.invoiceSendState = null;
    }
  }

  // 仕様: Core 第7.10節
  async handleInvoiceDocumentTemplateChange(event) {
    if (!this.invoiceSendState) {
      return;
    }
    const next = event.detail.value;
    const confirmed = await LightningConfirm.open({
      label: "テンプレートを変更",
      message:
        this.invoiceSendState?.attachmentId === "NEW"
          ? "帳票またはメールを変えると、差し込みとファイル名をやり直します。加筆は捨てます。"
          : "メールを変えると差し込みをやり直します。既存添付は作り直しません。加筆は捨てます。",
      variant: "header"
    });
    if (!confirmed) {
      event.target.value = this.invoiceSendState.documentTemplateKey;
      return;
    }
    this.invoiceSendState = {
      ...this.invoiceSendState,
      documentTemplateKey: next
    };
    await this.reloadInvoiceSendPreview();
  }

  // 仕様: Core 第7.10節
  async handleInvoiceEmailTemplateChange(event) {
    if (!this.invoiceSendState) {
      return;
    }
    const next = event.detail.value;
    const confirmed = await LightningConfirm.open({
      label: "テンプレートを変更",
      message:
        this.invoiceSendState?.attachmentId === "NEW"
          ? "帳票またはメールを変えると、差し込みとファイル名をやり直します。加筆は捨てます。"
          : "メールを変えると差し込みをやり直します。既存添付は作り直しません。加筆は捨てます。",
      variant: "header"
    });
    if (!confirmed) {
      event.target.value = this.invoiceSendState.emailTemplateApiName;
      return;
    }
    this.invoiceSendState = {
      ...this.invoiceSendState,
      emailTemplateApiName: next
    };
    await this.reloadInvoiceSendPreview();
  }

  handleInvoiceSendDraftChange(event) {
    if (!this.invoiceSendState) {
      return;
    }
    const { name, value } = event.target;
    if (
      name === "toAddresses" ||
      name === "ccAddresses" ||
      name === "bccAddresses"
    ) {
      return;
    }
    this.invoiceSendState = {
      ...this.invoiceSendState,
      [name]: value
    };
  }

  // 仕様: Core 第7.10節
  handleInvoiceAttachmentChange(event) {
    if (!this.invoiceSendState) {
      return;
    }
    const next = event.detail.value;
    let fileName = this.invoiceSendState.fileName;
    if (next === "NEW") {
      fileName = this.invoiceSendState.newIssueFileName || fileName;
    } else {
      const option = (this.invoiceSendState.attachmentOptions || []).find(
        (item) => item.value === next
      );
      fileName = option?.fileName || "";
    }
    this.invoiceSendState = {
      ...this.invoiceSendState,
      attachmentId: next,
      fileName
    };
  }

  // 仕様: Core 第7.7.3節、第7.10節、第11.3.2節
  async handleSendInvoice() {
    const invoiceId = this.invoiceSendState?.invoiceId;
    const invoice = this.findInvoice(invoiceId);
    if (
      !invoice ||
      !this.invoiceSendState?.documentTemplateKey ||
      this.isBlankReasonText(this.invoiceSendState?.fileName) ||
      this.isBlankReasonText(this.invoiceSendState?.toAddresses) ||
      this.hasInvalidEmailList(this.invoiceSendState?.toAddresses) ||
      this.hasInvalidEmailList(this.invoiceSendState?.ccAddresses) ||
      this.hasInvalidEmailList(this.invoiceSendState?.bccAddresses) ||
      this.orgFromResolved !== true ||
      this.invoiceOpsProcessingId != null
    ) {
      return;
    }
    const isResend = Boolean(invoice.sentDate);
    const confirmed = await LightningConfirm.open({
      label: isResend ? "請求書を再送" : "請求書を送付",
      message: `${this.invoiceSendState.toAddresses || "設定済みの宛先"}へ請求書を${
        isResend ? "再送" : "送付"
      }します。よろしいですか？\n${SEND_FAILURE_RETRY_NOTE}`,
      variant: "header"
    });
    if (!confirmed) {
      return;
    }
    const documentTemplateKey = this.invoiceSendState.documentTemplateKey;
    const emailTemplateApiName = this.invoiceSendState.emailTemplateApiName || null;
    const draft = {
      toAddresses: this.invoiceSendState.toAddresses,
      ccAddresses: this.invoiceSendState.ccAddresses,
      bccAddresses: this.invoiceSendState.bccAddresses,
      subject: this.invoiceSendState.subject,
      body: this.invoiceSendState.body,
      fileName: this.invoiceSendState.fileName,
      attachmentId: this.invoiceSendState.attachmentId
    };
    await this.runInvoiceOperation(invoiceId, "send", () =>
      sendInvoice({
        invoiceId,
        documentTemplateKey,
        emailTemplateApiName,
        expectedToken: invoice.lastModifiedToken,
        draft,
        contractHistoryId: this.contractHistoryId
      })
    );
  }

  async runInvoiceOperation(invoiceId, mode, action) {
    if (!invoiceId || this.invoiceOpsProcessingId != null) {
      return;
    }
    this.invoiceOpsProcessingId = invoiceId;
    try {
      await action();
      this.invoiceSendState = null;
      this.invoiceIssueState = null;
      const labels = {
        confirm: "請求を確定しました",
        send: "請求書を送付しました",
        issue: "請求書PDFを発行しました",
        cancel: "請求を取り消しました"
      };
      this.dispatchEvent(
        new ShowToastEvent({
          title: labels[mode],
          variant: "success"
        })
      );
      this.dispatchEvent(new CustomEvent("invoiceopscomplete"));
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: this.reduceInvoiceOpsError(error),
          variant: "error",
          mode: "dismissable"
        })
      );
    } finally {
      this.invoiceOpsProcessingId = null;
    }
  }

  reduceInvoiceOpsError(error) {
    return (
      error?.body?.message ||
      error?.body?.[0]?.message ||
      error?.message ||
      "請求を操作できませんでした。"
    );
  }

  // 仕様: Core 第0.1節、Accounting 第10.3節。保存値は変えない。
  manualJournalStatusLabel(status) {
    if (status === "Active") {
      return "有効";
    }
    if (status === "Cancelled") {
      return "取消済";
    }
    return status || "";
  }

  todayLocalIso() {
    // 仕様: 日付仕様 第8章。組織タイムゾーンの年月日。ブラウザローカルや toISOString() は使わない。
    const value = this.preview?.operationDay;
    if (!value) {
      return "";
    }
    return String(value).slice(0, 10);
  }

  get previewOperationDay() {
    return this.preview?.operationDay || "";
  }

  handleInvoiceTabClick(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    const tab = event.currentTarget.dataset.tab;
    if (!invoiceId || !tab) {
      return;
    }
    this.updateInvoiceUiState(invoiceId, { activeTab: tab });
    if (
      (tab === "payments" || tab === "journals") &&
      !this.invoiceUiState[invoiceId]?.bundle
    ) {
      this.loadOpsBundle(invoiceId);
    }
  }

  paymentPurposeOptions() {
    return [
      { label: "請求金額", value: "Invoice" },
      { label: "請求金額以外", value: "NonInvoice" }
    ];
  }

  paymentPurposeLabel(purpose) {
    const map = {
      Invoice: "請求金額",
      NonInvoice: "請求金額以外"
    };
    return map[purpose] || purpose || "—";
  }

  cancellationReasonOptions() {
    return [
      { label: "金額・日付などの誤り", value: "AmountOrDateError" },
      { label: "登録先の誤り", value: "WrongDestination" },
      { label: "重複登録", value: "Duplicate" },
      { label: "元取引の変更・取消", value: "SourceChanged" },
      { label: "その他", value: "Other" }
    ];
  }

  handlePaymentDraftChange(event) {
    const invoiceId = event.target.dataset.invoiceId;
    const field = event.target.dataset.field;
    if (!invoiceId || !field) {
      return;
    }
    const current = this.invoiceUiState[invoiceId] || {
      paymentDraft: this.newPaymentDraft(invoiceId)
    };
    const nextDraft = {
      ...current.paymentDraft,
      extraFieldValues: {
        ...(current.paymentDraft?.extraFieldValues || {})
      }
    };
    if (event.target.dataset.extra === "true") {
      nextDraft.extraFieldValues[field] = this.extraFieldValueFromEvent(event);
    } else {
      nextDraft[field] = event.detail.value;
    }
    if (field === "amount" || field === "purpose") {
      const bundle = current.bundle;
      const remaining =
        Number(bundle?.taxInclusiveAmount ?? 0) -
        Number(bundle?.invoicePaymentNet ?? 0);
      const purpose = nextDraft.purpose || "Invoice";
      nextDraft.allocations =
        purpose === "Invoice"
          ? this.proposePaymentAllocations(
              bundle?.paymentLines || [],
              Number(nextDraft.amount),
              remaining
            )
          : [];
    }
    this.updateInvoiceUiState(invoiceId, {
      paymentDraft: nextDraft
    });
  }

  handlePaymentAllocationChange(event) {
    const invoiceId = event.target.dataset.invoiceId;
    const lineId = event.target.dataset.lineId;
    if (!invoiceId || !lineId) {
      return;
    }
    const current = this.invoiceUiState[invoiceId] || {
      paymentDraft: this.newPaymentDraft(invoiceId)
    };
    const raw = event.detail.value;
    const nextAmount = raw === "" || raw == null ? "" : Number(raw);
    this.updateInvoiceUiState(invoiceId, {
      paymentDraft: {
        ...current.paymentDraft,
        allocations: (current.paymentDraft?.allocations || []).map((row) =>
          row.lineId === lineId ? { ...row, amount: nextAmount } : row
        )
      }
    });
  }

  async handlePaymentSave(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    const draft = this.invoiceUiState[invoiceId]?.paymentDraft;
    const bundle = this.invoiceUiState[invoiceId]?.bundle;
    if (!invoiceId || !draft || this.invoiceOpsProcessingId != null) {
      return;
    }
    const amount = Number(draft.amount);
    const purpose = draft.purpose;
    if (!amount || amount === 0 || !purpose || !draft.paymentDate) {
      return;
    }
    // 仕様: Core 第8.3節。0円と小数は登録しない。
    if (!Number.isFinite(amount) || amount !== Math.trunc(amount)) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "入出金金額は整数にしてください。",
          variant: "error"
        })
      );
      return;
    }
    const remaining =
      Number(bundle?.taxInclusiveAmount ?? 0) -
      Number(bundle?.invoicePaymentNet ?? 0);
    if (
      purpose === "Invoice" &&
      remaining !== 0 &&
      Math.sign(amount) === Math.sign(remaining) &&
      Math.abs(amount) > Math.abs(remaining)
    ) {
      return;
    }
    const requiresDate = requiresPaymentRegisterCancelDate(bundle);
    if (requiresDate && !draft.cancellationDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "ロック済み仕訳がある取消では取消基準日が必要です。",
          variant: "error"
        })
      );
      return;
    }
    const paymentArgs = {
      paymentId: null,
      invoiceId,
      amount,
      purpose,
      paymentDate: draft.paymentDate,
      memo: draft.memo || null,
      extraFieldValues: this.extraFieldValuesFromViews(
        this.buildExtraFieldViews({
          targetObject: "InvoicePayment__c",
          storedValues: {},
          draftValues: draft.extraFieldValues,
          purpose,
          disabledAll: false
        })
      ),
      expectedToken: bundle?.invoiceToken,
      allocations:
        purpose === "Invoice"
          ? (draft.allocations || []).map((row) => ({
              invoiceLineId: row.lineId,
              amount: Number(row.amount)
            }))
          : [],
      cancellationDate: requiresDate ? draft.cancellationDate || null : null,
      contractHistoryId: this.contractHistoryId
    };
    let journalPreviewText = "";
    // 仕様: Accounting 第8.8節。ONの入金登録は未Lockでも実行前に件数を出し確認する。OFFは件数プレビューを出さない。
    const showJournalPreview = bundle?.accountingEnabled === true;
    if (showJournalPreview) {
      try {
        const preview = await previewRegisterFromPreview(paymentArgs);
        journalPreviewText = preview?.displayText || "";
      } catch (error) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "請求操作エラー",
            message: this.reduceInvoiceOpsError(error),
            variant: "error"
          })
        );
        return;
      }
      const confirmed = await LightningConfirm.open({
        label: "入出金を追加",
        message:
          "この入出金を登録します。よろしいですか？\n\n" + journalPreviewText,
        variant: "header"
      });
      if (!confirmed) {
        return;
      }
    }
    await this.runInvoiceOpsMutation(invoiceId, async () => {
      const key = await this.resolvePendingOperationKey(invoiceId);
      await savePaymentFromPreview({
        ...paymentArgs,
        extraFieldValues: draft.extraFieldValues || {},
        businessOperationKey: key
      });
      this.updateInvoiceUiState(invoiceId, {
        paymentDraft: this.newPaymentDraft(invoiceId),
        cancelDraft: null
      });
      return journalPreviewText
        ? {
            title: "入出金を追加しました",
            message: journalPreviewText
          }
        : "入出金を追加しました";
    });
  }

  handleOpenPaymentEdit(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    const paymentId = event.currentTarget.dataset.paymentId;
    const bundle = this.invoiceUiState[invoiceId]?.bundle;
    const payment = (bundle?.payments || []).find(
      (row) => row.paymentId === paymentId
    );
    if (
      !payment ||
      payment.canCancel !== true ||
      this.isCancelledInvoice(this.findInvoice(invoiceId))
    ) {
      return;
    }
    const extraFieldValues = {};
    const stored = payment.extraFieldValues || {};
    for (const definition of this.opsFieldDefinitionsFor("InvoicePayment__c")) {
      if (
        !this.isPaymentPurposeVisible(
          definition,
          payment.paymentPurpose || payment.paymentType
        )
      ) {
        continue;
      }
      extraFieldValues[definition.apiName] = this.resolveExtraDisplayValue(
        definition,
        stored[definition.apiName]
      );
    }
    this.paymentEditState = {
      invoiceId,
      paymentId,
      memo: payment.memo || "",
      amount: payment.displayAmount ?? payment.amount,
      paymentDate: payment.paymentDate || "",
      paymentPurpose: payment.paymentPurpose || payment.paymentType,
      lastModifiedToken: payment.lastModifiedToken,
      storedExtraFieldValues: stored,
      extraFieldValues
    };
  }

  handleClosePaymentEdit() {
    this.paymentEditState = null;
  }

  handlePaymentEditFieldChange(event) {
    if (!this.paymentEditState) {
      return;
    }
    if (event.target.dataset.extra === "true") {
      const field = event.target.dataset.field;
      this.paymentEditState = {
        ...this.paymentEditState,
        extraFieldValues: {
          ...(this.paymentEditState.extraFieldValues || {}),
          [field]: this.extraFieldValueFromEvent(event)
        }
      };
      return;
    }
    this.paymentEditState = {
      ...this.paymentEditState,
      memo: event.detail.value
    };
  }

  // 仕様: Core 第8.4節、第8.9節、第7.9.7節、第11.4.4節。登録後はメモと入出金ロック除外の追加項目だけ。
  async handleSavePaymentEdit() {
    if (!this.paymentEditState?.paymentId || this.invoiceOpsProcessingId != null) {
      return;
    }
    const state = this.paymentEditState;
    const invoiceId = state.invoiceId;
    await this.runInvoiceOpsMutation(invoiceId, async () => {
      const key = await this.resolvePendingOperationKey(invoiceId);
      await updatePaymentFromPreview({
        paymentId: state.paymentId,
        invoiceId,
        memo: state.memo || "",
        extraFieldValues: this.extraFieldValuesFromViews(
          this.buildExtraFieldViews({
            targetObject: "InvoicePayment__c",
            storedValues: state.storedExtraFieldValues,
            draftValues: state.extraFieldValues,
            purpose: state.paymentPurpose,
            disabledAll: false,
            exemptNames: this.preview?.paymentLockExemptFieldApiNames,
            requireExemptToEdit: true
          })
        ),
        expectedToken:
          state.lastModifiedToken ||
          this.invoiceUiState[invoiceId]?.bundle?.invoiceToken,
        businessOperationKey: key,
        contractHistoryId: this.contractHistoryId
      });
      this.paymentEditState = null;
      return "入出金を更新しました";
    });
  }

  handlePaymentCancel(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    const paymentId = event.currentTarget.dataset.paymentId;
    const bundle = this.invoiceUiState[invoiceId]?.bundle;
    const invoice = this.findInvoice(invoiceId);
    const payment = (bundle?.payments || []).find(
      (row) => row.paymentId === paymentId
    );
    if (!payment || this.invoiceOpsProcessingId != null) {
      return;
    }
    const requiresDate = requiresCancelDate(bundle);
    this.updateInvoiceUiState(invoiceId, {
      cancelDraft: {
        invoiceId,
        paymentId: payment.paymentId,
        purpose: payment.paymentPurpose,
        purposeLabel: this.paymentPurposeLabel(payment.paymentPurpose),
        amount: payment.amount,
        paymentDate: payment.paymentDate,
        invoiceName: invoice?.invoiceName || "—",
        cancellationReason: "",
        cancellationReasonText: "",
        cancelDate: requiresDate ? this.todayLocalIso() : "",
        requiresDate,
        expectedToken: bundle?.invoiceToken
      }
    });
  }

  handlePaymentCancelDraftChange(event) {
    const invoiceId = event.target.dataset.invoiceId;
    const field = event.target.dataset.field;
    if (!invoiceId || !field) {
      return;
    }
    const current = this.invoiceUiState[invoiceId] || {};
    this.updateInvoiceUiState(invoiceId, {
      cancelDraft: {
        ...current.cancelDraft,
        [field]: event.detail.value
      }
    });
  }

  handlePaymentCancelClose(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    if (!invoiceId) {
      return;
    }
    this.updateInvoiceUiState(invoiceId, { cancelDraft: null });
  }

  // 仕様: Core 第7.9.5節・第7.9.6節・第1.1.10節、Accounting 第8.5節、日付仕様 第7.3節
  async handlePaymentCancelSave(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    const draft = this.invoiceUiState[invoiceId]?.cancelDraft;
    if (!invoiceId || !draft || this.invoiceOpsProcessingId != null) {
      return;
    }
    if (!draft.cancellationReason) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "取消理由を入力してください。",
          variant: "error"
        })
      );
      return;
    }
    if (
      draft.cancellationReason === "Other" &&
      this.isBlankReasonText(draft.cancellationReasonText)
    ) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "取消理由がその他のときは内容を入力してください。",
          variant: "error"
        })
      );
      return;
    }
    if (draft.requiresDate && !draft.cancelDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "ロック済み仕訳がある取消では取消基準日が必要です。",
          variant: "error"
        })
      );
      return;
    }
    let journalPreviewText = "";
    try {
      const preview = await previewCancelPaymentFromPreview({
        paymentId: draft.paymentId,
        invoiceId,
        cancelDate: draft.requiresDate ? draft.cancelDate : null,
        contractHistoryId: this.contractHistoryId
      });
      journalPreviewText = preview?.displayText || "";
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: this.reduceInvoiceOpsError(error),
          variant: "error"
        })
      );
      return;
    }
    const confirmed = await LightningConfirm.open({
      label: "入出金を取消",
      message:
        "この入出金を取り消します。よろしいですか？\n\n" + journalPreviewText,
      theme: "warning",
      variant: "header"
    });
    if (!confirmed) {
      return;
    }
    await this.runInvoiceOpsMutation(invoiceId, async () => {
      const key = await this.resolvePendingOperationKey(invoiceId);
      await cancelPaymentFromPreview({
        paymentId: draft.paymentId,
        invoiceId,
        cancelDate: draft.requiresDate ? draft.cancelDate : null,
        cancellationReason: draft.cancellationReason,
        cancellationReasonText: draft.cancellationReasonText || null,
        expectedToken: draft.expectedToken,
        businessOperationKey: key,
        contractHistoryId: this.contractHistoryId
      });
      this.updateInvoiceUiState(invoiceId, { cancelDraft: null });
      return {
        title: "入出金を取消しました",
        message: journalPreviewText
      };
    });
  }

  async runInvoiceOpsMutation(invoiceId, action) {
    if (!invoiceId || this.invoiceOpsProcessingId != null) {
      return;
    }
    this.invoiceOpsProcessingId = invoiceId;
    try {
      const success = await action();
      this.clearPendingOperationKey(invoiceId);
      const successTitle =
        typeof success === "string" ? success : success?.title;
      const extraMessage =
        typeof success === "string" ? "" : success?.message || "";
      const paymentCancelNotice =
        successTitle === "入出金を取消しました"
          ? "この現預金移動を別の請求書へ記録する必要がある場合は、対象請求書で新しく請求入出金を登録してください。"
          : "";
      const message = [extraMessage, paymentCancelNotice]
        .filter((part) => part)
        .join("\n");
      this.dispatchEvent(
        new ShowToastEvent({
          title: successTitle || "更新しました",
          message,
          variant: "success",
          mode: message ? "sticky" : "dismissable"
        })
      );
      await this.loadOpsBundle(invoiceId);
      this.dispatchEvent(new CustomEvent("invoiceopscomplete"));
    } catch (error) {
      const message = this.reduceInvoiceOpsError(error);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message,
          variant: "error",
          mode: "dismissable"
        })
      );
      // 仕様: Core 第7.9.7節・第4.3.12節。版比較失敗時はボード全体を読み直す。
      if (message === VERSION_CONFLICT_MESSAGE) {
        this.clearPendingOperationKey(invoiceId);
        this.dispatchEvent(new CustomEvent("invoiceopscomplete"));
      }
    } finally {
      this.invoiceOpsProcessingId = null;
    }
  }

  isLineDrafted(lineId) {
    return (
      lineId != null &&
      Object.prototype.hasOwnProperty.call(this.amountDrafts || {}, lineId)
    );
  }

  draftAmountDeltaForSelection() {
    return this.draftAmountDeltaForVersion(this.versionKeyForTotals);
  }

  draftAmountDeltaForVersion(selected) {
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

  // 仕様: Core 第7.4節、第7.7.0節。端数ドラフト中も請求書の税抜合計へ税率を1回適用する。明細ごと税の差は足さない。
  draftInclusiveDeltaForVersion(selected) {
    const filterAll = selected === ALL_VERSIONS;
    let delta = 0;
    for (const invoice of this.preview?.invoices || []) {
      if (this.isCancelledInvoice(invoice)) {
        continue;
      }
      if (
        !filterAll &&
        this.versionKeyForInvoice(invoice) !== String(selected)
      ) {
        continue;
      }
      let exclusiveDelta = 0;
      let hasDraft = false;
      for (const line of invoice.lines || []) {
        const lineId = line.lineId;
        if (!this.isLineDrafted(lineId)) {
          continue;
        }
        hasDraft = true;
        exclusiveDelta +=
          Number(this.amountDrafts[lineId] ?? 0) - Number(line.amount ?? 0);
      }
      if (!hasDraft) {
        continue;
      }
      const savedExcl = Number(invoice.amountTotal ?? 0);
      const taxPercent = invoice.taxPercent;
      const savedIncl =
        invoice.taxInclusiveAmount != null && invoice.taxInclusiveAmount !== ""
          ? Number(invoice.taxInclusiveAmount)
          : this.computeInclusive(savedExcl, taxPercent);
      delta +=
        this.computeInclusive(savedExcl + exclusiveDelta, taxPercent) -
        savedIncl;
    }
    return delta;
  }

  sumSavedInvoiceInclusiveForVersion(selected) {
    let total = 0;
    for (const invoice of this.preview?.invoices || []) {
      if (this.isCancelledInvoice(invoice)) {
        continue;
      }
      if (
        selected !== ALL_VERSIONS &&
        this.versionKeyForInvoice(invoice) !== String(selected)
      ) {
        continue;
      }
      const incl = invoice.taxInclusiveAmount;
      if (incl != null && incl !== "") {
        total += Number(incl);
        continue;
      }
      total += this.computeInclusive(
        invoice.amountTotal,
        invoice.taxPercent
      );
    }
    return total;
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

  /**
   * 検収終了日は金額と違いドラフトを溜めない。Accounting ON では件数プレビューと確認のあと保存する。
   * 取消基準日はロック済み仕訳があるときだけ取る。
   * 仕様: Core 第7.6節、第7.7.3節、第7.9.6節、Accounting 第8.8節、第1.1.10節。空欄へは変えない。
   */
  async handleAcceptanceEndDateChange(event) {
    if (!this.canEdit || this.isSaving) {
      return;
    }
    const lineId = event.currentTarget.dataset.lineId;
    if (!lineId) {
      return;
    }
    const line = this.findLine(lineId);
    if (line?.revenueRecognitionBasis !== REVENUE_BASIS_POINT_IN_TIME) {
      return;
    }
    const invoiceId = (this.preview?.invoices || []).find((invoice) =>
      (invoice.lines || []).some((row) => row.lineId === lineId)
    )?.invoiceId;
    if (
      this.invoiceUiState[invoiceId]?.bundle?.accountingEnabled !== true
    ) {
      return;
    }
    const raw = event.detail?.value ?? event.currentTarget.value ?? "";
    const trimmed = String(raw).trim();
    const next = trimmed ? trimmed.slice(0, 10) : null;
    const current = this.findLine(lineId)?.acceptanceEndDate || null;
    if (current === next) {
      return;
    }
    if (!next) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "検収終了日は空にできません。",
          variant: "error"
        })
      );
      return;
    }
    const bundle = this.invoiceUiState[invoiceId]?.bundle;
    if (requiresCancelDate(bundle)) {
      this.updateInvoiceUiState(invoiceId, {
        acceptanceDraft: {
          lineId,
          nextDate: next,
          cancellationDate: this.todayLocalIso(),
          requiresDate: true
        }
      });
      return;
    }
    let journalPreviewText = "";
    try {
      const preview = await previewInvoiceLineAcceptanceEndDate({
        lineId,
        acceptanceEndDate: next,
        cancellationDate: null,
        contractHistoryId: this.contractHistoryId
      });
      journalPreviewText = preview?.displayText || "";
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: this.reduceInvoiceOpsError(error),
          variant: "error"
        })
      );
      return;
    }
    const confirmed = await LightningConfirm.open({
      label: "検収終了日を変更",
      message:
        "検収終了日を変更します。よろしいですか？\n\n" + journalPreviewText,
      variant: "header"
    });
    if (!confirmed) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("saveacceptanceenddate", {
        detail: {
          lineId,
          acceptanceEndDate: next,
          cancellationDate: null,
          journalPreviewText,
          expectedContentVersion: this.findInvoice(invoiceId)?.lastModifiedToken,
          businessOperationKey: await this.resolvePendingOperationKey(invoiceId)
        }
      })
    );
  }

  handleAcceptanceCancelDraftChange(event) {
    const invoiceId = event.target.dataset.invoiceId;
    if (!invoiceId) {
      return;
    }
    const current = this.invoiceUiState[invoiceId] || {};
    this.updateInvoiceUiState(invoiceId, {
      acceptanceDraft: {
        ...current.acceptanceDraft,
        cancellationDate: event.detail.value
      }
    });
  }

  handleAcceptanceCancelClose(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    if (!invoiceId) {
      return;
    }
    this.updateInvoiceUiState(invoiceId, { acceptanceDraft: null });
  }

  // 仕様: Core 第7.6節、第7.9.6節、Accounting 第8.5節、日付仕様 第7.3節
  async handleAcceptanceCancelSave(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    const draft = this.invoiceUiState[invoiceId]?.acceptanceDraft;
    if (!invoiceId || !draft || this.invoiceOpsProcessingId != null) {
      return;
    }
    if (draft.requiresDate && !draft.cancellationDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "ロック済み仕訳がある取消では取消基準日が必要です。",
          variant: "error"
        })
      );
      return;
    }
    let journalPreviewText = "";
    try {
      const preview = await previewInvoiceLineAcceptanceEndDate({
        lineId: draft.lineId,
        acceptanceEndDate: draft.nextDate || null,
        cancellationDate: draft.requiresDate ? draft.cancellationDate || null : null,
        contractHistoryId: this.contractHistoryId
      });
      journalPreviewText = preview?.displayText || "";
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: this.reduceInvoiceOpsError(error),
          variant: "error"
        })
      );
      return;
    }
    const confirmed = await LightningConfirm.open({
      label: "検収終了日を変更",
      message:
        "検収終了日を変更します。よろしいですか？\n\n" + journalPreviewText,
      variant: "header"
    });
    if (!confirmed) {
      return;
    }
    this.updateInvoiceUiState(invoiceId, { acceptanceDraft: null });
    this.dispatchEvent(
      new CustomEvent("saveacceptanceenddate", {
        detail: {
          lineId: draft.lineId,
          acceptanceEndDate: draft.nextDate,
          cancellationDate: draft.requiresDate ? draft.cancellationDate : null,
          journalPreviewText,
          expectedContentVersion: this.findInvoice(invoiceId)?.lastModifiedToken,
          businessOperationKey: await this.resolvePendingOperationKey(invoiceId)
        }
      })
    );
  }

  handleDiscardAmountDrafts() {
    this.amountDrafts = {};
  }

  async handleSaveAmountDrafts() {
    if (!this.hasAmountDrafts || this.isSaving) {
      return;
    }
    const edits = Object.keys(this.amountDrafts).map((lineId) => ({
      lineId,
      amount: this.amountDrafts[lineId]
    }));
    const expectedTokenByInvoiceId = {};
    let keyInvoiceId = null;
    for (const lineId of Object.keys(this.amountDrafts)) {
      const invoice = (this.preview?.invoices || []).find((row) =>
        (row.lines || []).some((line) => line.lineId === lineId)
      );
      if (!invoice?.invoiceId) {
        continue;
      }
      expectedTokenByInvoiceId[invoice.invoiceId] = invoice.lastModifiedToken;
      if (!keyInvoiceId) {
        keyInvoiceId = invoice.invoiceId;
      }
    }
    this.dispatchEvent(
      new CustomEvent("savelineamounts", {
        detail: {
          edits,
          expectedTokenByInvoiceId,
          businessOperationKey: keyInvoiceId
            ? await this.resolvePendingOperationKey(keyInvoiceId)
            : null
        }
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
    // 仕様: Core 第11.9節、第1.1.10節。OrgDefault の数量・単価丸め。未設定の NaN を 0 へ落とさない。
    const rounded = roundUnitPrice(value);
    if (rounded === null) {
      return 0;
    }
    return Number.isFinite(rounded) ? rounded : Number.NaN;
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

  handleOpenInvoiceRedirect(event) {
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
    this.handleCloseLineSplit();
    this.invoiceSplitState = null;
    this.invoiceMoveState = null;
    if (targets.length === 0) {
      this.invoiceDestinationChoiceState = null;
      this.openInvoiceSplitPanel(invoiceId);
      return;
    }
    this.updateInvoiceUiState(invoiceId, { activeTab: "lines" });
    this.invoiceDestinationChoiceState = { invoiceId };
  }

  handleChooseNewInvoiceDestination() {
    const invoiceId = this.invoiceDestinationChoiceState?.invoiceId;
    this.invoiceDestinationChoiceState = null;
    if (!invoiceId) {
      return;
    }
    this.openInvoiceSplitPanel(invoiceId);
  }

  handleChooseExistingInvoiceDestination() {
    const invoiceId = this.invoiceDestinationChoiceState?.invoiceId;
    this.invoiceDestinationChoiceState = null;
    if (!invoiceId) {
      return;
    }
    this.openInvoiceMovePanel(invoiceId);
  }

  handleCloseInvoiceDestinationChoice() {
    this.invoiceDestinationChoiceState = null;
  }

  /** 仕様: Core 第7.8節、第1.1.10節。新しい請求日・入金予定日・請求アカウントは空で開き、人が渡す。 */
  openInvoiceSplitPanel(invoiceId) {
    this.updateInvoiceUiState(invoiceId, { activeTab: "lines" });
    this.handleCloseLineSplit();
    this.invoiceMoveState = null;
    this.invoiceDestinationChoiceState = null;
    this.invoiceSplitState = {
      invoiceId,
      newInvoiceDate: "",
      newPaymentDate: "",
      newBillingAccountId: "",
      allowOtherAccountBilling: false,
      selected: {}
    };
  }

  handleOpenInvoiceSplit(event) {
    this.handleOpenInvoiceRedirect(event);
  }

  handleCloseInvoiceSplit() {
    this.invoiceSplitState = null;
  }

  openInvoiceMovePanel(invoiceId) {
    const invoice = this.findInvoice(invoiceId);
    const targets = this.buildMoveTargetOptions(invoice);
    if (targets.length === 0) {
      return;
    }
    this.updateInvoiceUiState(invoiceId, { activeTab: "lines" });
    this.handleCloseLineSplit();
    this.invoiceSplitState = null;
    this.invoiceDestinationChoiceState = null;
    this.invoiceMoveState = {
      invoiceId,
      targetInvoiceId: targets[0].value,
      selected: {}
    };
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
    this.openInvoiceMovePanel(invoiceId);
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
        if (this.isCancelledInvoice(invoice) || !this.isDraftInvoice(invoice)) {
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
    // 0円は Apex に送らないため残る。削除確認は金額0円を除く全明細と一致するときだけ。
    const willDeleteSource = movesAllNonZeroLines(
      invoice,
      splitLines.map((row) => row.lineId)
    );
    if (willDeleteSource) {
      const confirmed = await LightningConfirm.open({
        label: "別の請求へ分ける",
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
          splitLines,
          expectedContentVersion: invoice?.lastModifiedToken,
          businessOperationKey: await this.resolvePendingOperationKey(
            this.invoiceSplitState.invoiceId
          )
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
          message: "同じ版の移動先請求を選んでから実行してください。",
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
        label: "別の請求へ分ける",
        message: `移動先の税率（${targetTax}%）が元請求（${sourceTax}%）と異なります。税抜金額はそのまま、税額・税込は移動先の税率で再計算されます。よろしいですか？`,
        theme: "warning",
        variant: "header"
      });
      if (!confirmedTax) {
        return;
      }
    }
    if (movesAllNonZeroLines(invoice, lineIds)) {
      const confirmed = await LightningConfirm.open({
        label: "別の請求へ分ける",
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
          lineIds,
          expectedContentVersion: invoice?.lastModifiedToken,
          expectedTargetContentVersion: targetInvoice?.lastModifiedToken,
          businessOperationKey: await this.resolvePendingOperationKey(
            this.invoiceMoveState.invoiceId
          )
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
    this.invoiceDestinationChoiceState = null;

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
          splitLines,
          expectedContentVersion: invoice?.lastModifiedToken,
          businessOperationKey: await this.resolvePendingOperationKey(
            this.lineSplitState.invoiceId
          )
        }
      })
    );
  }

  // 仕様: Core 第7.7.3節、第7.8節、第1.1.10節。0%は0を明示。空は0で埋めない。
  billingEditTaxPercent(invoiceTaxPercent) {
    if (
      invoiceTaxPercent == null ||
      String(invoiceTaxPercent).trim() === ""
    ) {
      return "";
    }
    const taxPercent = Number(invoiceTaxPercent);
    return Number.isFinite(taxPercent) ? taxPercent : "";
  }

  // 仕様: Core 第7.7.3節、第7.8節、第1.1.10節、第11.4.4節。確定後も開く。取消済みは出さない。
  handleOpenBillingEdit(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    if (this.hasAmountDrafts || this.isSplitOrMoveUiOpen) {
      return;
    }
    const invoice = this.findInvoice(invoiceId);
    if (!invoice || this.isCancelledInvoice(invoice)) {
      return;
    }
    this.updateInvoiceUiState(invoiceId, { activeTab: "lines" });
    this.invoiceSplitState = null;
    this.invoiceMoveState = null;
    this.invoiceDestinationChoiceState = null;
    this.handleCloseLineSplit();
    const invoiceDate =
      invoice.invoiceDate && invoice.invoiceDate !== "—"
        ? invoice.invoiceDate
        : "";
    const paymentScheduledDate =
      invoice.paymentScheduledDate && invoice.paymentScheduledDate !== "—"
        ? invoice.paymentScheduledDate
        : "";
    const taxPercent = this.billingEditTaxPercent(invoice.taxPercent);
    const extraFieldValues = {};
    const stored = invoice.extraFieldValues || {};
    for (const definition of this.opsFieldDefinitionsFor("Invoice__c")) {
      extraFieldValues[definition.apiName] = this.resolveExtraDisplayValue(
        definition,
        stored[definition.apiName]
      );
    }
    this.billingEditState = {
      invoiceId,
      invoiceDate,
      paymentScheduledDate,
      taxPercent,
      extraFieldValues
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
    if (event.target.dataset.extra === "true") {
      this.billingEditState = {
        ...this.billingEditState,
        extraFieldValues: {
          ...(this.billingEditState.extraFieldValues || {}),
          [field]: this.extraFieldValueFromEvent(event)
        }
      };
      return;
    }
    this.billingEditState = {
      ...this.billingEditState,
      [field]: event.detail.value
    };
  }

  // 仕様: Core 第7.8節・第4.6節・第1.1.10節
  async handleSaveBillingHeader() {
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
    if (
      !Number.isFinite(taxPercent) ||
      taxPercent < 0 ||
      taxPercent > 100 ||
      (taxPercent > 0 && taxPercent < 1)
    ) {
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
    const invoiceId = this.billingEditState.invoiceId;
    const invoice = this.findInvoice(invoiceId);
    this.dispatchEvent(
      new CustomEvent("savebillingheader", {
        detail: {
          invoiceId,
          invoiceDate: this.billingEditState.invoiceDate,
          paymentScheduledDate: this.billingEditState.paymentScheduledDate,
          taxPercent,
          extraFieldValues: this.extraFieldValuesFromViews(
            this.buildExtraFieldViews({
              targetObject: "Invoice__c",
              storedValues: invoice?.extraFieldValues,
              draftValues: this.billingEditState.extraFieldValues,
              disabledAll: false,
              exemptNames: this.preview?.invoiceLockExemptFieldApiNames,
              requireExemptToEdit: this.isConfirmedInvoice(invoice)
            })
          ),
          expectedContentVersion: this.findInvoice(invoiceId)?.lastModifiedToken,
          businessOperationKey: await this.resolvePendingOperationKey(invoiceId)
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
      .map((part) => part.trim().replace(/^V/i, "").replace(/^版/, ""))
      .includes(String(selected));
  }

  /**
   * Apex TaxCalculationUtil.calculateTaxAmount と同じ。
   * 仕様: Core 第11.9節、第1.1.10節。DOWN / HALF_UP / UP。無い・空・未知は 0方向へ落とさない。
   */
  calculateTaxAmount(amountExclTax, taxPercent) {
    const resolvedPercent = this.normalizeTaxPercent(taxPercent);
    if (!Number.isFinite(resolvedPercent)) {
      return Number.NaN;
    }
    const amount = Number(amountExclTax);
    if (!Number.isFinite(amount) || amount === 0) {
      return 0;
    }
    return this.roundTaxRaw((amount * resolvedPercent) / 100);
  }

  roundTaxRaw(raw) {
    const mode = this.preview?.taxRoundingMode;
    if (mode === "DOWN") {
      return Math.trunc(raw);
    }
    if (mode === "UP") {
      if (raw === 0) {
        return 0;
      }
      return raw > 0 ? Math.ceil(raw) : Math.floor(raw);
    }
    if (mode === "HALF_UP") {
      const sign = raw < 0 ? -1 : 1;
      return sign * Math.floor(Math.abs(raw) + 0.5);
    }
    return Number.NaN;
  }

  // 仕様: Core 第7.7.3節、第1.1.10節。0%は0を明示。空・不正は0にしない。
  normalizeTaxPercent(taxPercent) {
    if (taxPercent == null || taxPercent === "") {
      return Number.NaN;
    }
    const n = Number(taxPercent);
    if (!Number.isFinite(n) || n < 0) {
      return Number.NaN;
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

  // 仕様: Core 第7.8節、第3.3.5節、第1.1.10節。参照中BAが空なら画面で止める。
  async handleApplyBillingAccountContent(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    const invoice = this.findInvoice(invoiceId);
    if (
      !invoiceId ||
      !invoice?.billingAccountId ||
      this.hasAmountDrafts ||
      this.isSplitOrMoveUiOpen ||
      this.isBillingEditUiOpen
    ) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("applybillingaccountcontent", {
        detail: {
          invoiceId,
          expectedContentVersion: invoice.lastModifiedToken,
          businessOperationKey: await this.resolvePendingOperationKey(invoiceId)
        }
      })
    );
  }

  handleMemoChange(event) {
    if (!this.canEdit) {
      return;
    }
    const invoiceId = event.target.dataset.invoiceId;
    if (!invoiceId) {
      return;
    }
    // 仕様: Core 第12.2節。取消済みは参照だけ。
    if (this.isCancelledInvoice(this.findInvoice(invoiceId))) {
      return;
    }
    this.memoDrafts = {
      ...this.memoDrafts,
      [invoiceId]: event.detail.value
    };
  }

  // 仕様: Core 第7.7.0節、第7.7.3節、第12.2節
  async handleSaveMemo(event) {
    if (!this.canEdit) {
      return;
    }
    const invoiceId = event.currentTarget.dataset.invoiceId;
    if (!invoiceId) {
      return;
    }
    if (this.isCancelledInvoice(this.findInvoice(invoiceId))) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "取消済み請求のメモは編集できません。",
          variant: "error"
        })
      );
      return;
    }
    try {
      await updateInvoiceMemo({
        invoiceId,
        memo: this.memoDrafts[invoiceId] ?? this.findInvoice(invoiceId)?.memo ?? "",
        contractHistoryId: this.contractHistoryId
      });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "メモを保存しました",
          variant: "success"
        })
      );
      this.dispatchEvent(new CustomEvent("invoiceopscomplete"));
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "メモの保存に失敗しました",
          message: this.reduceInvoiceOpsError(error),
          variant: "error"
        })
      );
    }
  }

  // 仕様: Core 第7.9.3節・第7.7.3節・第7.9.6節・第1.1.10節、日付仕様 第7.3節、第8節
  async handleOpenInvoiceCancel(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    if (!invoiceId) {
      return;
    }
    if (!this.invoiceUiState[invoiceId]?.bundle) {
      await this.loadOpsBundle(invoiceId);
    }
    const blocked = this.invoiceCancelBlockedReason(
      this.invoiceUiState[invoiceId]?.bundle
    );
    if (blocked) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: blocked,
          variant: "error"
        })
      );
      return;
    }
    this.invoiceCancelState = {
      invoiceId,
      cancellationReason: "",
      cancellationReasonText: "",
      cancellationDate: ""
    };
    const requiresDate = requiresCancelDate(
      this.invoiceUiState[invoiceId]?.bundle
    );
    this.invoiceCancelState = {
      ...this.invoiceCancelState,
      cancellationDate: requiresDate ? this.todayLocalIso() : ""
    };
  }

  handleCloseInvoiceCancel() {
    this.invoiceCancelState = null;
  }

  handleCancelFieldChange(event) {
    if (!this.invoiceCancelState) {
      return;
    }
    const field = event.target.dataset.field;
    if (!field) {
      return;
    }
    this.invoiceCancelState = {
      ...this.invoiceCancelState,
      [field]: event.detail.value
    };
  }

  // 仕様: Core 第7.9.3節、第7.9.5節、第7.9.6節、第7.10節、第1.1.10節、Accounting 第8.5節、日付仕様 第7.3節
  async handleConfirmInvoiceCancel() {
    if (!this.invoiceCancelState?.invoiceId) {
      return;
    }
    const blocked = this.invoiceCancelBlockedReason(
      this.invoiceUiState[this.invoiceCancelState.invoiceId]?.bundle
    );
    if (blocked) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: blocked,
          variant: "error"
        })
      );
      return;
    }
    if (!this.invoiceCancelState.cancellationReason) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "取消理由を入力してください",
          variant: "error"
        })
      );
      return;
    }
    if (
      this.invoiceCancelState.cancellationReason === "Other" &&
      this.isBlankReasonText(this.invoiceCancelState.cancellationReasonText)
    ) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "取消理由がその他のときは内容を入力してください。",
          variant: "error"
        })
      );
      return;
    }
    const requiresDate = requiresCancelDate(
      this.invoiceUiState[this.invoiceCancelState.invoiceId]?.bundle
    );
    if (requiresDate && !this.invoiceCancelState.cancellationDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "ロック済み仕訳がある取消では取消基準日が必要です。",
          variant: "error"
        })
      );
      return;
    }
    let journalPreviewText = "";
    try {
      const preview = await previewCancelConfirmed({
        invoiceId: this.invoiceCancelState.invoiceId,
        cancellationDate: requiresDate
          ? this.invoiceCancelState.cancellationDate || null
          : null,
        contractHistoryId: this.contractHistoryId
      });
      journalPreviewText = preview?.displayText || "";
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: this.reduceInvoiceOpsError(error),
          variant: "error"
        })
      );
      return;
    }
    const requiresCustomerNotice =
      (this.preview?.invoices || []).find(
        (row) => row.invoiceId === this.invoiceCancelState.invoiceId
      )?.deliveryStatus === "Sent";
    const customerNotice = requiresCustomerNotice ? CUSTOMER_CANCEL_NOTICE : "";
    const confirmed = await LightningConfirm.open({
      label: "確定済み請求を取消",
      message: [
        "この請求を取消済みにし、同じ内容の未確定請求を作ります。よろしいですか？",
        journalPreviewText,
        customerNotice
      ]
        .filter((part) => part)
        .join("\n\n"),
      theme: "warning",
      variant: "header"
    });
    if (!confirmed) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("cancelconfirmed", {
        detail: {
          invoiceId: this.invoiceCancelState.invoiceId,
          cancellationReason: this.invoiceCancelState.cancellationReason,
          cancellationReasonText:
            this.invoiceCancelState.cancellationReasonText || null,
          cancellationDate: requiresDate
            ? this.invoiceCancelState.cancellationDate || null
            : null,
          journalPreviewText,
          requiresCustomerNotice,
          customerNotice,
          expectedContentVersion: this.findInvoice(
            this.invoiceCancelState.invoiceId
          )?.lastModifiedToken,
          businessOperationKey: await this.resolvePendingOperationKey(
            this.invoiceCancelState.invoiceId
          )
        }
      })
    );
    this.invoiceCancelState = null;
  }

  handleJournalMemoChange(event) {
    if (!this.canEdit) {
      return;
    }
    const journalId = event.target.dataset.journalId;
    if (!journalId) {
      return;
    }
    this.journalMemoDrafts = {
      ...this.journalMemoDrafts,
      [journalId]: event.detail.value
    };
  }

  handleToggleJournalExtras(event) {
    const journalId = event.currentTarget.dataset.journalId;
    if (!journalId) {
      return;
    }
    this.journalToggleOpen = {
      ...this.journalToggleOpen,
      [journalId]: this.journalToggleOpen[journalId] !== true
    };
  }

  handleJournalExtraChange(event) {
    const journalId = event.target.dataset.journalId;
    const field = event.target.dataset.field;
    if (!journalId || !field) {
      return;
    }
    this.journalExtraDrafts = {
      ...this.journalExtraDrafts,
      [journalId]: {
        ...(this.journalExtraDrafts[journalId] || {}),
        [field]: this.extraFieldValueFromEvent(event)
      }
    };
  }

  // 仕様: Core 第7.7.0節、第7.7.3節、第12.2節。取消済み請求の仕訳メモは参照だけ。
  async handleSaveJournalMemo(event) {
    if (!this.canEdit) {
      return;
    }
    const journalId = event.currentTarget.dataset.journalId;
    const invoiceId = event.currentTarget.dataset.invoiceId;
    if (!journalId) {
      return;
    }
    if (this.isCancelledInvoice(this.findInvoice(invoiceId))) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "取消済み請求の仕訳メモは編集できません。",
          variant: "error"
        })
      );
      return;
    }
    const journal = (
      this.invoiceUiState[invoiceId]?.bundle?.journals || []
    ).find((row) => row.journalId === journalId);
    try {
      await updateJournalMemo({
        journalId,
        memo: this.journalMemoDrafts[journalId] || "",
        invoiceId,
        extraFieldValues: this.extraFieldValuesFromViews(
          this.buildExtraFieldViews({
            targetObject: "GlJournal__c",
            storedValues: journal?.extraFieldValues,
            draftValues: this.journalExtraDrafts[journalId],
            disabledAll: false,
            exemptNames: this.preview?.journalLockExemptFieldApiNames,
            requireExemptToEdit: journal?.isLocked === true
          })
        )
      });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "仕訳メモを保存しました",
          variant: "success"
        })
      );
      this.dispatchEvent(new CustomEvent("invoiceopscomplete"));
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "仕訳メモの保存に失敗しました",
          message: this.reduceInvoiceOpsError(error),
          variant: "error"
        })
      );
    }
  }

  selectedJournalIds(invoiceId) {
    const selected = this.journalLockSelected?.[invoiceId] || {};
    const journals =
      this.invoiceUiState?.[invoiceId]?.bundle?.journals || [];
    const activeIds = new Set(
      journals
        .filter((journal) => journal.transactionStatus === "Active")
        .map((journal) => journal.journalId)
    );
    return Object.keys(selected).filter(
      (journalId) =>
        selected[journalId] === true && activeIds.has(journalId)
    );
  }

  // 仕様: Core 第7.7.3節、Accounting 第2.3節・第9.5節、第12.2節
  handleJournalLockToggle(event) {
    const invoiceId = event.target.dataset.invoiceId;
    const journalId = event.target.dataset.journalId;
    if (!invoiceId || !journalId) {
      return;
    }
    if (this.isCancelledInvoice(this.findInvoice(invoiceId))) {
      return;
    }
    const journals =
      this.invoiceUiState?.[invoiceId]?.bundle?.journals || [];
    const target = journals.find((journal) => journal.journalId === journalId);
    if (!target || target.transactionStatus !== "Active") {
      return;
    }
    const checked = event.target.checked === true;
    this.journalLockSelected = {
      ...this.journalLockSelected,
      [invoiceId]: {
        ...(this.journalLockSelected[invoiceId] || {}),
        [journalId]: checked
      }
    };
  }

  async handleLockJournals(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    if (this.isCancelledInvoice(this.findInvoice(invoiceId))) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "取消済み請求の仕訳はLock/Unlockできません。",
          variant: "error"
        })
      );
      return;
    }
    const journalIds = this.selectedJournalIds(invoiceId);
    if (!journalIds.length) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Lockする仕訳を選んでください。",
          variant: "error"
        })
      );
      return;
    }
    const confirmed = await LightningConfirm.open({
      label: "仕訳をLock",
      message: "選んだ仕訳をLockします。よろしいですか？",
      variant: "header"
    });
    if (!confirmed) {
      return;
    }
    try {
      const key = await this.resolvePendingOperationKey(invoiceId);
      await lockJournalsForInvoice({
        invoiceId,
        journalIds,
        expectedToken: this.findInvoice(invoiceId)?.lastModifiedToken,
        businessOperationKey: key
      });
      this.clearPendingOperationKey(invoiceId);
      this.journalLockSelected = {
        ...this.journalLockSelected,
        [invoiceId]: {}
      };
      this.dispatchEvent(
        new ShowToastEvent({
          title: "仕訳をLockしました",
          variant: "success"
        })
      );
      this.dispatchEvent(new CustomEvent("journalslockcomplete"));
      this.dispatchEvent(new CustomEvent("invoiceopscomplete"));
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Lockに失敗しました",
          message: this.reduceInvoiceOpsError(error),
          variant: "error"
        })
      );
    }
  }

  handleUnlockReasonChange(event) {
    this.unlockReason = event.detail.value;
  }

  async handleUnlockJournals(event) {
    const invoiceId = event.currentTarget.dataset.invoiceId;
    if (this.isCancelledInvoice(this.findInvoice(invoiceId))) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求操作エラー",
          message: "取消済み請求の仕訳はLock/Unlockできません。",
          variant: "error"
        })
      );
      return;
    }
    const journalIds = this.selectedJournalIds(invoiceId);
    if (!journalIds.length) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unlockする仕訳を選んでください。",
          variant: "error"
        })
      );
      return;
    }
    if (this.isBlankReasonText(this.unlockReason)) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unlockには理由が必要です",
          variant: "error"
        })
      );
      return;
    }
    if (this.isUnlockReasonTooLong(this.unlockReason)) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unlock理由は255文字以内で指定してください。",
          variant: "error"
        })
      );
      return;
    }
    const confirmed = await LightningConfirm.open({
      label: "仕訳をUnlock",
      message: "選んだ仕訳をUnlockします。よろしいですか？",
      variant: "header"
    });
    if (!confirmed) {
      return;
    }
    try {
      const key = await this.resolvePendingOperationKey(invoiceId);
      await unlockJournalsForInvoice({
        invoiceId,
        journalIds,
        reason: this.unlockReason,
        expectedToken: this.findInvoice(invoiceId)?.lastModifiedToken,
        businessOperationKey: key
      });
      this.clearPendingOperationKey(invoiceId);
      this.unlockReason = "";
      this.journalLockSelected = {
        ...this.journalLockSelected,
        [invoiceId]: {}
      };
      this.dispatchEvent(
        new ShowToastEvent({
          title: "仕訳をUnlockしました",
          variant: "success"
        })
      );
      this.dispatchEvent(new CustomEvent("journalslockcomplete"));
      this.dispatchEvent(new CustomEvent("invoiceopscomplete"));
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unlockに失敗しました",
          message: this.reduceInvoiceOpsError(error),
          variant: "error"
        })
      );
    }
  }

  handleManualJournalComplete() {
    this.dispatchEvent(new CustomEvent("invoiceopscomplete"));
  }
}
