import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import { resolveSaveErrorAlert } from "c/estimateValidationAlertUtils";
import getBootstrap from "@salesforce/apex/ContractCrossController.getBootstrap";
import queryEstimates from "@salesforce/apex/ContractCrossController.queryEstimates";
import queryInvoices from "@salesforce/apex/ContractCrossController.queryInvoices";
import queryJournals from "@salesforce/apex/ContractCrossController.queryJournals";
import getEstimateTile from "@salesforce/apex/ContractCrossController.getEstimateTile";
import saveJournals from "@salesforce/apex/ContractCrossController.saveJournals";
import getInvoicePreview from "@salesforce/apex/OrderCreateController.getInvoicePreview";
import getBillingAccountOptionsForPreview from "@salesforce/apex/OrderCreateController.getBillingAccountOptionsForPreview";
import updateInvoiceLineAmounts from "@salesforce/apex/OrderCreateController.updateInvoiceLineAmounts";
import updateInvoiceLineAcceptanceEndDate from "@salesforce/apex/OrderCreateController.updateInvoiceLineAcceptanceEndDate";
import splitInvoiceByDate from "@salesforce/apex/OrderCreateController.splitInvoiceByDate";
import splitInvoiceByBillingAccount from "@salesforce/apex/OrderCreateController.splitInvoiceByBillingAccount";
import moveLinesToExistingInvoice from "@salesforce/apex/OrderCreateController.moveLinesToExistingInvoice";
import splitLinesInPlace from "@salesforce/apex/OrderCreateController.splitLinesInPlace";
import updateInvoiceHeaderAndDates from "@salesforce/apex/OrderCreateController.updateInvoiceHeaderAndDates";
import applyBillingAccountContent from "@salesforce/apex/OrderCreateController.applyBillingAccountContent";
import cancelConfirmedFromPreview from "@salesforce/apex/OrderCreateController.cancelConfirmedFromPreview";
import getInvoiceOpsFieldDefinitions from "@salesforce/apex/InvoiceOpsFieldService.getDefinitions";
import hasLockJournal from "@salesforce/customPermission/Loop_16_Can_LockJournal";
import hasUnlockJournal from "@salesforce/customPermission/Loop_17_Can_UnlockJournal";
import hasEditDraftInvoice from "@salesforce/customPermission/Loop_10_Can_EditDraftInvoice";

const MENU_ESTIMATE = "estimate";
const MENU_INVOICE = "invoice";
const MENU_JOURNAL = "journal";
const PAGE_ESTIMATE = 20;
const PAGE_INVOICE = 20;
const PAGE_JOURNAL = 50;
const VERSION_CONFLICT_MESSAGE =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";
const TRUNCATED_MESSAGE =
  "500件だけを取得しています。条件を狭めてリロードしてください。";

const TRI_OPTIONS = [
  { label: "指定しない", value: "" },
  { label: "あり", value: "true" },
  { label: "なし", value: "false" }
];

function formatAmount(value) {
  if (value == null || value === "") {
    return "";
  }
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return "";
  }
  return number.toLocaleString("ja-JP");
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

function formatDate(value) {
  return value ? String(value).slice(0, 10) : "";
}

function recordUrl(objectApiName, id) {
  return id ? `/lightning/r/${objectApiName}/${id}/view` : "";
}

function triBoolean(value) {
  if (value === "true") {
    return true;
  }
  if (value === "false") {
    return false;
  }
  return null;
}

function isEditableTarget(target) {
  if (!target) {
    return false;
  }
  const node = target.nodeType === 3 ? target.parentElement : target;
  if (!node || !node.closest) {
    return false;
  }
  if (node.isContentEditable) {
    return true;
  }
  const tag = node.tagName;
  if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") {
    return true;
  }
  return Boolean(
    node.closest(
      "lightning-input, lightning-textarea, lightning-combobox, lightning-record-picker, lightning-quill, .slds-rich-text-area, [contenteditable='true']"
    )
  );
}

function compareValues(a, b, dir, nullsFirst) {
  const mul = dir === "desc" ? -1 : 1;
  const emptyA = a == null || a === "";
  const emptyB = b == null || b === "";
  if (emptyA && emptyB) {
    return 0;
  }
  if (emptyA) {
    return nullsFirst ? -1 : 1;
  }
  if (emptyB) {
    return nullsFirst ? 1 : -1;
  }
  if (a < b) {
    return -1 * mul;
  }
  if (a > b) {
    return 1 * mul;
  }
  return 0;
}

function sortValue(row, field) {
  switch (field) {
    case "closeDate":
      return row.closeDate || "";
    case "account":
      return row.accountName || "";
    case "service":
      return row.serviceName || "";
    case "version":
      return row.version;
    case "estimateType":
      return row.estimateTypeLabel || row.estimateType || "";
    case "historyName":
      return row.historyName || "";
    case "amount":
      return row.amount;
    case "validDate":
      return row.validDate || "";
    case "invoiceDate":
      return row.invoiceDate || "";
    case "billingAccount":
      return row.billingAccountName || "";
    case "invoiceStatus":
      return row.invoiceStatus || "";
    case "invoiceName":
      return row.invoiceName || "";
    case "postingDate":
      return row.postingDate || "";
    case "event":
      return row.eventName || row.eventKey || "";
    case "debit":
      return row.debitName || "";
    default:
      return "";
  }
}

function groupValue(row, groupId) {
  switch (groupId) {
    case "closeDate":
      return row.closeDate || "";
    case "account":
      return row.accountId || row.accountName || "";
    case "service":
      return row.serviceId || row.serviceName || "";
    case "billingAccount":
      return row.billingAccountId || row.billingAccountName || "";
    case "history":
      return row.historyId || `${row.serviceName || ""}:${row.version || ""}`;
    case "invoiceStatus":
      return row.invoiceStatus || "";
    case "postingDate":
      return row.postingDate || "";
    case "invoice":
      return row.invoiceId || row.invoiceName || "";
    case "event":
      return row.eventKey || row.eventName || "";
    default:
      return "";
  }
}

function cloneGroups(items) {
  return items.map((item) => ({ ...item }));
}

function sendModeShowsIssue(mode) {
  return mode === "PdfOnly" || mode === "PdfAndEmail";
}

function sendModeShowsSend(mode) {
  return mode === "PdfAndEmail";
}

function issuedPdfPreviewUrl(documentId) {
  return documentId
    ? `/lightning/r/ContentDocument/${documentId}/view`
    : "";
}

function versionKey(value) {
  if (value == null || value === "") {
    return "";
  }
  const number = Number(value);
  return Number.isFinite(number) ? String(number) : String(value);
}

/** 仕様: 横断画面.md 第2.4節・操作14・操作32。右は当該 Version グループだけ取り直す。 */
function restrictPreviewToOpenedVersion(preview) {
  if (!preview) {
    return preview;
  }
  const opened = versionKey(preview.sourceHistoryVersion);
  if (!opened) {
    return preview;
  }
  return {
    ...preview,
    invoices: (preview.invoices || []).filter(
      (invoice) => versionKey(invoice?.historyVersion) === opened
    ),
    versionOptions: (preview.versionOptions || []).filter(
      (option) => versionKey(option?.value) === opened
    )
  };
}

/** 仕様: 横断画面.md 第5節 */
export default class ContractCrossWork extends LightningElement {
  menu = MENU_ESTIMATE;
  accountingEnabled = false;
  canIssueEstimate = false;
  canSendEstimate = false;
  canOrder = false;
  estimateSendMode = "";
  invoiceSendMode = "";
  tagRules = [];
  eventOptions = [];

  bootstrapped = false;
  loading = false;
  saving = false;
  errorMessage = "";
  truncated = false;
  truncatedMessage = "";

  estCloseFrom = "";
  estCloseTo = "";
  estAccountId = null;
  estServiceId = null;
  estType = "";
  estSent = "";
  estIssued = "";
  estAutoRenew = "";
  estValidFrom = "";
  estValidTo = "";

  invStatus = "Draft";
  invName = "";
  invBillingAccountId = null;
  invAccountId = null;
  invDateFrom = "";
  invDateTo = "";
  invCloseFrom = "";
  invCloseTo = "";
  invIncludeCancelled = false;
  invSent = "";
  invIssued = "";
  invOverdue = "";
  invCollection = "";
  invNextFrom = "";
  invNextTo = "";
  @track tagFilterState = {};

  jouFrom = "";
  jouTo = "";
  jouLock = "Unlocked";
  jouEvent = "";
  jouBillingAccountId = null;
  jouAccountId = null;
  jouInvoiceId = null;
  jouCloseFrom = "";
  jouCloseTo = "";
  unlockReason = "";

  @track estimateGroups = [
    { id: "closeDate", label: "完了予定日", on: false, total: false },
    { id: "account", label: "取引先", on: false, total: false },
    { id: "service", label: "契約サービス名", on: false, total: false }
  ];
  @track invoiceGroups = [
    { id: "closeDate", label: "完了予定日", on: false, total: false },
    { id: "billingAccount", label: "請求アカウント", on: false, total: false },
    { id: "history", label: "契約履歴", on: true, total: false },
    { id: "invoiceStatus", label: "請求状態", on: false, total: false }
  ];
  @track journalGroups = [
    { id: "postingDate", label: "計上日", on: false, total: false },
    { id: "billingAccount", label: "請求アカウント", on: false, total: false },
    { id: "invoice", label: "請求", on: false, total: false },
    { id: "event", label: "会計イベント", on: false, total: false }
  ];

  sort1 = "closeDate";
  sort1Dir = "asc";
  sort2 = "account";
  sort2Dir = "asc";
  estimateSort = {
    sort1: "closeDate",
    sort1Dir: "asc",
    sort2: "account",
    sort2Dir: "asc"
  };
  invoiceSort = {
    sort1: "invoiceDate",
    sort1Dir: "asc",
    sort2: "account",
    sort2Dir: "asc"
  };
  journalSort = {
    sort1: "postingDate",
    sort1Dir: "asc",
    sort2: "invoiceName",
    sort2Dir: "asc"
  };

  @track estimateRows = [];
  @track invoiceRows = [];
  @track journalRows = [];
  loaded = { estimate: false, invoice: false, journal: false };
  page = 1;
  selectedId = null;
  @track checkedIds = {};
  @track memoDrafts = {};
  @track extraDrafts = {};
  @track journalColumnMode = false;
  @track journalExtraDefinitions = [];
  @track journalLockExemptFieldApiNames = [];

  estimateTile = null;
  estimateTileLoading = false;
  invoicePreview = null;
  billingAccountOptions = [];
  previewHistoryId = null;
  tableInitialInvoiceId = null;
  tableInitialActiveTab = null;
  highlightJournalId = null;
  invoiceTileNonce = 0;
  invoiceLoading = false;
  invoiceError = "";
  isSaving = false;
  showSendOverlay = false;
  showOrderOverlay = false;
  overlayHistoryId = null;

  _keydown = (event) => this.handleWindowKeydown(event);

  connectedCallback() {
    window.addEventListener("keydown", this._keydown);
    this.bootstrap();
  }

  disconnectedCallback() {
    window.removeEventListener("keydown", this._keydown);
  }

  get isEstimateMenu() {
    return this.menu === MENU_ESTIMATE;
  }

  get isInvoiceMenu() {
    return this.menu === MENU_INVOICE;
  }

  get isJournalMenu() {
    return this.menu === MENU_JOURNAL;
  }

  canShowEstimateMenu = false;
  canShowInvoiceMenu = false;
  get showEstimateMenu() {
    return this.canShowEstimateMenu === true;
  }
  get showInvoiceMenu() {
    return this.canShowInvoiceMenu === true;
  }
  get showJournalMenu() {
    return this.accountingEnabled === true && this.canShowInvoiceMenu === true;
  }

  get estimateMenuClass() {
    return this.menuClass(MENU_ESTIMATE);
  }

  get invoiceMenuClass() {
    return this.menuClass(MENU_INVOICE);
  }

  get journalMenuClass() {
    return this.menuClass(MENU_JOURNAL);
  }

  menuClass(menu) {
    return this.menu === menu ? "menu-btn is-active" : "menu-btn";
  }

  get pageSize() {
    return this.menu === MENU_JOURNAL ? PAGE_JOURNAL : PAGE_ESTIMATE;
  }

  get currentRows() {
    if (this.menu === MENU_INVOICE) {
      return this.invoiceRows;
    }
    if (this.menu === MENU_JOURNAL) {
      return this.journalRows;
    }
    return this.estimateRows;
  }

  get currentGroups() {
    if (this.menu === MENU_INVOICE) {
      return this.invoiceGroups;
    }
    if (this.menu === MENU_JOURNAL) {
      return this.journalGroups;
    }
    return this.estimateGroups;
  }

  get groupItems() {
    return this.currentGroups.map((item) => ({
      ...item,
      totalDisabled: item.on !== true
    }));
  }

  get prevDisabled() {
    return this.page <= 1;
  }

  get nextDisabled() {
    return this.page >= this.totalPages;
  }

  // 仕様: 横断画面.md 第2.4節、第5節
  get tableWrapClass() {
    return this.isJournalMenu
      ? "table-wrap " + this.journalUnlockedClass
      : "table-wrap";
  }

  get historyGroupOn() {
    return this.invoiceGroups.some((item) => item.id === "history" && item.on);
  }

  get showAccountingInvoiceColumns() {
    return this.accountingEnabled === true;
  }

  get isLockUnlocked() {
    return this.jouLock === "Unlocked";
  }

  // 仕様: 共通基盤 第10.4節、Accounting 第9.5節。Lock は 16、Unlock は 17。片方で代替しない。
  get canLockJournalOp() {
    return hasLockJournal === true;
  }

  get canUnlockJournalOp() {
    return hasUnlockJournal === true;
  }

  // 仕様: 横断画面.md 第2.3節。メモ／追加項目の保存は 10。
  get canEditJournalMemoOp() {
    return hasEditDraftInvoice === true;
  }

  get canLockJournalsNow() {
    return (
      this.isJournalMenu === true &&
      this.isLockUnlocked === true &&
      this.canLockJournalOp === true
    );
  }

  get canUnlockJournalsNow() {
    return (
      this.isJournalMenu === true &&
      this.isLockUnlocked !== true &&
      this.canUnlockJournalOp === true
    );
  }

  get showJournalLockSelection() {
    return this.canLockJournalsNow === true || this.canUnlockJournalsNow === true;
  }

  get showJournalSave() {
    return (
      this.showJournalLockSelection === true ||
      (this.isJournalMenu === true && this.canEditJournalMemoOp === true)
    );
  }

  // 仕様: 横断画面.md 第2.4節、第5節
  get journalActionClass() {
    return this.isLockUnlocked
      ? "journal-bar lock-unlocked"
      : "journal-bar lock-locked";
  }

  get saveDisabled() {
    return (
      this.saving ||
      (this.hasChecked &&
        this.jouLock === "Locked" &&
        (this.isBlankReasonText(this.unlockReason) ||
          this.isUnlockReasonTooLong(this.unlockReason))) ||
      (!this.hasChecked && !this.hasDirtyJournalEdits)
    );
  }

  /** 仕様: Accounting 第9.5節、Core 第1.1.10節。Unlockは理由必須。 */
  isBlankReasonText(value) {
    return value == null || String(value).trim() === "";
  }

  /** 仕様: Accounting 第9.1節、Core 第1.1.10節。Unlock理由はテキスト255。 */
  isUnlockReasonTooLong(value) {
    return value != null && String(value).length > 255;
  }

  get hasChecked() {
    return this.currentPageCheckable.some((row) => this.checkedIds[row.id] === true);
  }

  get hasDirtyJournalEdits() {
    return this.dirtyJournalEdits().length > 0;
  }

  get showCheckColumn() {
    return this.showJournalLockSelection === true;
  }

  // 仕様: 横断画面.md 第2.4節、第5節
  get journalUnlockedClass() {
    return this.isLockUnlocked ? "lock-unlocked" : "lock-locked";
  }

  get showUnlockReason() {
    return this.canUnlockJournalsNow === true;
  }

  get triOptions() {
    return TRI_OPTIONS;
  }

  get typeOptions() {
    return [
      { label: "指定しない", value: "" },
      { label: "新規", value: "New" },
      { label: "追加変更", value: "Change" },
      { label: "更新", value: "Renew" },
      { label: "解約", value: "Cancel" }
    ];
  }

  get invoiceStatusOptions() {
    return [
      { label: "未確定", value: "Draft" },
      { label: "確定", value: "Confirmed" },
      { label: "両方", value: "Both" }
    ];
  }

  get collectionOptions() {
    return [
      { label: "指定しない", value: "" },
      { label: "未対応", value: "NotStarted" },
      { label: "対応中", value: "InProgress" },
      { label: "完了", value: "Completed" }
    ];
  }

  get lockOptions() {
    return [
      { label: "未Lock", value: "Unlocked" },
      { label: "Lock済み", value: "Locked" }
    ];
  }

  get eventFilterOptions() {
    return [{ label: "指定しない", value: "" }].concat(this.eventOptions || []);
  }

  get dirOptions() {
    return [
      { label: "昇順", value: "asc" },
      { label: "降順", value: "desc" }
    ];
  }

  /** 仕様: 横断画面.md 第5節 見積一覧 */
  get sortFieldOptions() {
    if (this.menu === MENU_INVOICE) {
      return [
        { label: "請求日", value: "invoiceDate" },
        { label: "取引先", value: "account" },
        { label: "完了予定日", value: "closeDate" },
        { label: "請求アカウント", value: "billingAccount" },
        { label: "請求状態", value: "invoiceStatus" },
        { label: "請求名", value: "invoiceName" },
        { label: "税抜", value: "amount" }
      ];
    }
    if (this.menu === MENU_JOURNAL) {
      return [
        { label: "計上日", value: "postingDate" },
        { label: "請求書", value: "invoiceName" },
        { label: "請求アカウント", value: "billingAccount" },
        { label: "会計イベント", value: "event" },
        { label: "借方", value: "debit" },
        { label: "金額", value: "amount" }
      ];
    }
    return [
      { label: "完了予定日", value: "closeDate" },
      { label: "取引先", value: "account" },
      { label: "契約サービス名", value: "service" },
      { label: "版", value: "version" },
      { label: "見積種別", value: "estimateType" },
      { label: "契約履歴名", value: "historyName" },
      { label: "見積税抜", value: "amount" }
    ];
  }

  get tagChips() {
    return (this.tagRules || []).map((rule) => {
      const state = this.tagFilterState[rule.fieldApiName] || "Unset";
      return {
        ...rule,
        state,
        chipClass:
          state === "True"
            ? "tag-chip is-true"
            : state === "False"
              ? "tag-chip is-false"
              : "tag-chip"
      };
    });
  }

  get sortedRows() {
    const rows = [...this.currentRows];
    const enabled = this.currentGroups.filter((item) => item.on);
    const first = this.sort1;
    const second = this.sort2;
    rows.sort((left, right) => {
      for (const group of enabled) {
        const cmp = compareValues(
          groupValue(left, group.id),
          groupValue(right, group.id),
          "asc",
          false
        );
        if (cmp !== 0) {
          return cmp;
        }
      }
      const firstCmp = compareValues(
        sortValue(left, first),
        sortValue(right, first),
        this.sort1Dir,
        first === "invoiceDate"
      );
      if (firstCmp !== 0) {
        return firstCmp;
      }
      return compareValues(
        sortValue(left, second),
        sortValue(right, second),
        this.sort2Dir,
        false
      );
    });
    return rows;
  }

  get builtRows() {
    return this.buildDisplayRows(this.sortedRows);
  }

  get dataRowCount() {
    return this.builtRows.filter((row) => row.kind === "data").length;
  }

  get totalPages() {
    return Math.max(1, Math.ceil(this.dataRowCount / this.pageSize));
  }

  get displayRows() {
    return this.windowRows(this.builtRows, this.page, this.pageSize);
  }

  get currentPageCheckable() {
    return this.displayRows.filter(
      (row) => row.kind === "data" && row.canCheck === true
    );
  }

  get pageItems() {
    return this.buildPageItems(this.page, this.totalPages);
  }

  get hasPrevPage() {
    return this.page > 1;
  }

  get hasNextPage() {
    return this.page < this.totalPages;
  }

  get columnHeaders() {
    const headers = [];
    if (this.menu === MENU_JOURNAL) {
      if (this.showCheckColumn === true) {
        headers.push({ key: "check", label: "" });
      }
      this.journalGroups
        .filter((item) => !item.on && item.id !== "invoice")
        .forEach((item) => headers.push({ key: item.id, label: item.label }));
      headers.push({ key: "debit", label: "借方" });
      headers.push({ key: "credit", label: "貸方" });
      headers.push({ key: "amount", label: "金額" });
      // 仕様: 横断画面.md 第5節
      headers.push({ key: "confirm", label: "確認用", className: "confirm-cell" });
      headers.push({ key: "memo", label: "メモ", className: "memo-cell" });
      headers.push({ key: "account", label: "取引先" });
      headers.push({ key: "invoice", label: "請求書名" });
      if (this.journalColumnMode) {
        (this.journalExtraDefinitions || []).forEach((definition) => {
          headers.push({
            key: `extra-${definition.apiName}`,
            label: definition.label,
            className: "extra-cell"
          });
        });
      }
      return headers;
    }
    if (this.menu === MENU_INVOICE) {
      this.invoiceGroups
        .filter((item) => !item.on)
        .forEach((item) => headers.push({ key: item.id, label: item.label }));
      headers.push({ key: "name", label: "請求名" });
      headers.push({ key: "opp", label: "商談名" });
      headers.push({ key: "account", label: "取引先" });
      headers.push({ key: "invoiceDate", label: "請求日" });
      headers.push({ key: "pay", label: "入金予定日" });
      headers.push({ key: "amount", label: "税抜" });
      if (this.showInvoiceSendFilter) {
        headers.push({ key: "sent", label: "送付" });
      }
      if (this.showInvoiceIssueFilter) {
        headers.push({ key: "issued", label: "発行" });
      }
      headers.push({ key: "overdue", label: "遅延" });
      if (this.accountingEnabled) {
        headers.push({ key: "next", label: "次の検収" });
        headers.push({ key: "tags", label: "タグ" });
      }
      if (!this.historyGroupOn) {
        headers.push({ key: "estAmt", label: "見積税抜" });
        headers.push({ key: "verAmt", label: "請求合計" });
        headers.push({ key: "diff", label: "差額" });
      }
      headers.push({ key: "memo", label: "メモ" });
      return headers;
    }
    this.estimateGroups
      .filter((item) => !item.on)
      .forEach((item) => headers.push({ key: item.id, label: item.label }));
    headers.push({ key: "version", label: "版" });
    headers.push({ key: "type", label: "見積種別" });
    headers.push({ key: "auto", label: "自動Renew" });
    headers.push({ key: "opp", label: "商談名" });
    headers.push({ key: "history", label: "契約履歴名" });
    headers.push({ key: "amount", label: "見積税抜" });
    headers.push({ key: "valid", label: "有効期限" });
    if (this.showEstimateSendFilter) {
      headers.push({ key: "sent", label: "送付" });
    }
    if (this.showEstimateIssueFilter) {
      headers.push({ key: "issued", label: "発行" });
    }
    return headers;
  }

  get colCount() {
    return this.columnHeaders.length;
  }

  get showEstimateTile() {
    return this.isEstimateMenu && this.estimateTile;
  }

  get invoiceTileInstances() {
    if (this.isJournalMenu && this.journalColumnMode) {
      return [];
    }
    if (!(this.isInvoiceMenu || this.isJournalMenu) || !this.invoicePreview) {
      return [];
    }
    return [{ id: String(this.invoiceTileNonce) }];
  }

  get showInvoiceTile() {
    if (this.isJournalMenu && this.journalColumnMode) {
      return false;
    }
    return (this.isInvoiceMenu || this.isJournalMenu) && this.invoicePreview;
  }

  get splitClass() {
    return this.isJournalMenu && this.journalColumnMode
      ? "split split_column-mode"
      : "split";
  }

  get showRightPane() {
    return !(this.isJournalMenu && this.journalColumnMode);
  }

  get showRightEmpty() {
    return !this.showEstimateTile && !this.showInvoiceTile && !this.estimateTileLoading && !this.invoiceLoading;
  }

  get hideResetPostOrder() {
    return true;
  }

  get tableInitialVersion() {
    return this.invoicePreview?.sourceHistoryVersion || "";
  }

  /** 仕様: 横断画面.md 第1節、Core 第4.10節。PDFのみなら発行まで。使わないなら発行も送付も出さない。 */
  get showEstimateIssueFilter() {
    return sendModeShowsIssue(this.estimateSendMode);
  }

  get showEstimateSendFilter() {
    return sendModeShowsSend(this.estimateSendMode);
  }

  get showInvoiceIssueFilter() {
    return sendModeShowsIssue(this.invoiceSendMode);
  }

  get showInvoiceSendFilter() {
    return sendModeShowsSend(this.invoiceSendMode);
  }

  keepOpenedVersionGroup(preview) {
    return restrictPreviewToOpenedVersion(preview);
  }

  async bootstrap() {
    this.loading = true;
    this.errorMessage = "";
    try {
      const dto = await getBootstrap();
      this.accountingEnabled = dto?.accountingEnabled === true;
      this.canIssueEstimate = dto?.canIssueEstimate === true;
      this.canSendEstimate = dto?.canSendEstimate === true;
      this.canOrder = dto?.canOrder === true;
      this.canShowEstimateMenu = dto?.canShowEstimateMenu === true;
      this.canShowInvoiceMenu = dto?.canShowInvoiceMenu === true;
      if (this.menu === MENU_ESTIMATE && this.canShowEstimateMenu !== true) {
        if (this.canShowInvoiceMenu === true) {
          this.menu = MENU_INVOICE;
        } else if (this.accountingEnabled === true) {
          this.menu = MENU_JOURNAL;
        }
      }
      this.estimateSendMode = dto?.estimateSendMode || "";
      this.invoiceSendMode = dto?.invoiceSendMode || "";
      this.estCloseFrom = formatDate(dto?.estimateCloseFrom);
      this.estCloseTo = formatDate(dto?.estimateCloseTo);
      this.jouFrom = formatDate(dto?.journalPostingFrom);
      this.jouTo = formatDate(dto?.journalPostingTo);
      this.tagRules = dto?.tagRules || [];
      this.eventOptions = (dto?.eventOptions || []).map((item) => ({
        label: item.label,
        value: item.value
      }));
      this.journalLockExemptFieldApiNames =
        dto?.journalLockExemptFieldApiNames || [];
      try {
        const definitions = (await getInvoiceOpsFieldDefinitions()) || [];
        this.journalExtraDefinitions = definitions.filter(
          (row) => row && row.targetObject === "GlJournal__c"
        );
      } catch (error) {
        this.journalExtraDefinitions = [];
        this.errorMessage = this.reduceError(error);
        this.bootstrapped = true;
        return;
      }
      this.bootstrapped = true;
      await this.fetchList(true);
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.loading = false;
    }
  }

  async fetchList(resetPage) {
    if (!this.bootstrapped) {
      return;
    }
    this.loading = true;
    this.errorMessage = "";
    this.truncated = false;
    this.truncatedMessage = "";
    if (this.menu === MENU_JOURNAL) {
      this.memoDrafts = {};
      this.extraDrafts = {};
      this.checkedIds = {};
    }
    try {
      if (this.menu === MENU_ESTIMATE) {
        const result = await queryEstimates({ filter: this.estimateFilter() });
        this.estimateRows = result?.estimates || [];
        this.loaded.estimate = true;
        this.applyTruncation(result);
      } else if (this.menu === MENU_INVOICE) {
        const result = await queryInvoices({ filter: this.invoiceFilter() });
        this.invoiceRows = result?.invoices || [];
        this.loaded.invoice = true;
        this.applyTruncation(result);
      } else {
        const result = await queryJournals({ filter: this.journalFilter() });
        this.journalRows = result?.journals || [];
        this.loaded.journal = true;
        this.applyTruncation(result);
      }
      if (resetPage) {
        this.page = 1;
      }
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.loading = false;
    }
  }

  applyTruncation(result) {
    this.truncated = result?.truncated === true;
    this.truncatedMessage = this.truncated
      ? result?.truncatedMessage || TRUNCATED_MESSAGE
      : "";
  }

  estimateFilter() {
    return {
      closeDateFrom: this.estCloseFrom,
      closeDateTo: this.estCloseTo,
      accountId: this.estAccountId,
      serviceId: this.estServiceId,
      estimateType: this.estType || null,
      sent: this.showEstimateSendFilter ? triBoolean(this.estSent) : null,
      issued: this.showEstimateIssueFilter ? triBoolean(this.estIssued) : null,
      autoRenew: triBoolean(this.estAutoRenew),
      validDateFrom: this.estValidFrom || null,
      validDateTo: this.estValidTo || null
    };
  }

  invoiceFilter() {
    const tagFilters = [];
    if (this.accountingEnabled) {
      for (const rule of this.tagRules || []) {
        const state = this.tagFilterState[rule.fieldApiName] || "Unset";
        if (state === "True" || state === "False") {
          tagFilters.push({ fieldApiName: rule.fieldApiName, state });
        }
      }
    }
    return {
      invoiceStatus: this.invStatus,
      invoiceName: this.invName || null,
      billingAccountId: this.invBillingAccountId,
      accountId: this.invAccountId,
      invoiceDateFrom: this.invDateFrom || null,
      invoiceDateTo: this.invDateTo || null,
      closeDateFrom: this.invCloseFrom || null,
      closeDateTo: this.invCloseTo || null,
      includeCancelled: this.invIncludeCancelled === true,
      sent: this.showInvoiceSendFilter ? triBoolean(this.invSent) : null,
      issued: this.showInvoiceIssueFilter ? triBoolean(this.invIssued) : null,
      overdue: triBoolean(this.invOverdue),
      collectionStatus: this.invCollection || null,
      nextAcceptanceFrom: this.accountingEnabled ? this.invNextFrom || null : null,
      nextAcceptanceTo: this.accountingEnabled ? this.invNextTo || null : null,
      tagFilters
    };
  }

  journalFilter() {
    return {
      postingDateFrom: this.jouFrom,
      postingDateTo: this.jouTo,
      lockState: this.jouLock,
      eventKey: this.jouEvent || null,
      billingAccountId: this.jouBillingAccountId,
      accountId: this.jouAccountId,
      invoiceId: this.jouInvoiceId,
      closeDateFrom: this.jouCloseFrom || null,
      closeDateTo: this.jouCloseTo || null
    };
  }

  handleMenu(event) {
    const next = event.currentTarget.dataset.menu;
    if (!next || next === this.menu) {
      return;
    }
    if (next === MENU_JOURNAL && !this.accountingEnabled) {
      return;
    }
    this.persistMenuSort(this.menu);
    this.menu = next;
    this.applyMenuSort(next);
    this.resetListWindow();
    if (!this.loaded[next]) {
      this.fetchList(true);
    }
  }

  persistMenuSort(menu) {
    const snap = {
      sort1: this.sort1,
      sort1Dir: this.sort1Dir,
      sort2: this.sort2,
      sort2Dir: this.sort2Dir
    };
    if (menu === MENU_INVOICE) {
      this.invoiceSort = snap;
    } else if (menu === MENU_JOURNAL) {
      this.journalSort = snap;
    } else {
      this.estimateSort = snap;
    }
  }

  applyMenuSort(menu) {
    const snap =
      menu === MENU_INVOICE
        ? this.invoiceSort
        : menu === MENU_JOURNAL
          ? this.journalSort
          : this.estimateSort;
    this.sort1 = snap.sort1;
    this.sort1Dir = snap.sort1Dir;
    this.sort2 = snap.sort2;
    this.sort2Dir = snap.sort2Dir;
  }

  handleReload() {
    this.fetchList(true);
  }

  handleFilterChange(event) {
    const name = event.target.name || event.currentTarget.dataset.name;
    const value =
      event.detail && Object.prototype.hasOwnProperty.call(event.detail, "checked")
        ? event.detail.checked
        : event.detail?.value ?? event.target.value;
    if (!name) {
      return;
    }
    if (
      (name === "estCloseFrom" ||
        name === "estCloseTo" ||
        name === "jouFrom" ||
        name === "jouTo" ||
        name === "invStatus" ||
        name === "jouLock") &&
      (value === "" || value == null)
    ) {
      const restored = this[name];
      this[name] = null;
      Promise.resolve().then(() => {
        this[name] = restored;
      });
      return;
    }
    this[name] = value;
    this.fetchList(true);
  }

  handleLookupChange(event) {
    const name = event.currentTarget.dataset.name;
    this[name] = event.detail.recordId || null;
    this.fetchList(true);
  }

  handleTagChip(event) {
    const field = event.currentTarget.dataset.field;
    const current = this.tagFilterState[field] || "Unset";
    const next =
      current === "Unset" ? "True" : current === "True" ? "False" : "Unset";
    this.tagFilterState = { ...this.tagFilterState, [field]: next };
    this.fetchList(true);
  }

  handleGroupOn(event) {
    const id = event.currentTarget.dataset.id;
    const checked = event.detail.checked;
    this.updateGroup(id, { on: checked, total: checked ? this.groupById(id).total : false });
  }

  handleGroupTotal(event) {
    const id = event.currentTarget.dataset.id;
    this.updateGroup(id, { total: event.detail.checked });
  }

  handleGroupMove(event) {
    const id = event.currentTarget.dataset.id;
    const dir = Number(event.currentTarget.dataset.dir);
    const items = cloneGroups(this.currentGroups);
    const index = items.findIndex((item) => item.id === id);
    const next = index + dir;
    if (index < 0 || next < 0 || next >= items.length) {
      return;
    }
    const swap = items[index];
    items[index] = items[next];
    items[next] = swap;
    this.setGroups(items);
    this.resetListWindow();
  }

  groupById(id) {
    return this.currentGroups.find((item) => item.id === id) || {};
  }

  updateGroup(id, patch) {
    const items = cloneGroups(this.currentGroups).map((item) =>
      item.id === id ? { ...item, ...patch } : item
    );
    this.setGroups(items);
    this.resetListWindow();
  }

  setGroups(items) {
    if (this.menu === MENU_INVOICE) {
      this.invoiceGroups = items;
    } else if (this.menu === MENU_JOURNAL) {
      this.journalGroups = items;
    } else {
      this.estimateGroups = items;
    }
  }

  handleSortChange(event) {
    const name = event.target.name;
    this[name] = event.detail.value;
    this.resetListWindow();
  }

  resetListWindow() {
    this.page = 1;
    if (this.menu === MENU_JOURNAL) {
      this.checkedIds = {};
    }
  }

  handlePageClick(event) {
    const next = Number(event.currentTarget.dataset.page);
    if (!next || next === this.page) {
      return;
    }
    this.page = next;
    if (this.menu === MENU_JOURNAL) {
      this.checkedIds = {};
    }
  }

  handlePrevPage() {
    if (!this.hasPrevPage) {
      return;
    }
    this.page -= 1;
    if (this.menu === MENU_JOURNAL) {
      this.checkedIds = {};
    }
  }

  handleNextPage() {
    if (!this.hasNextPage) {
      return;
    }
    this.page += 1;
    if (this.menu === MENU_JOURNAL) {
      this.checkedIds = {};
    }
  }

  handleWindowKeydown(event) {
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") {
      return;
    }
    if (isEditableTarget(event.target)) {
      return;
    }
    event.preventDefault();
    this.moveRow(event.key === "ArrowUp" ? -1 : 1);
  }

  moveRow(delta) {
    const data = this.builtRows.filter((row) => row.kind === "data");
    if (!data.length) {
      return;
    }
    const currentIndex = data.findIndex((row) => row.id === this.selectedId);
    let nextIndex = currentIndex < 0 ? (delta > 0 ? 0 : data.length - 1) : currentIndex + delta;
    if (nextIndex < 0 || nextIndex >= data.length) {
      return;
    }
    const nextPage = Math.floor(nextIndex / this.pageSize) + 1;
    if (nextPage !== this.page) {
      this.page = nextPage;
      if (this.menu === MENU_JOURNAL) {
        this.checkedIds = {};
      }
    }
    if (this.menu === MENU_JOURNAL && this.journalColumnMode) {
      this.selectedId = data[nextIndex].id;
      return;
    }
    this.openRow(data[nextIndex]);
  }

  handleRowClick(event) {
    if (
      event.target.closest(
        "a, lightning-input, lightning-combobox, lightning-textarea, .no-open"
      )
    ) {
      return;
    }
    // 仕様: 横断画面.md 第2.4節。列モードでは行クリックで右を開かない。
    if (this.menu === MENU_JOURNAL && this.journalColumnMode) {
      return;
    }
    const key = event.currentTarget.dataset.id;
    if (!key) {
      return;
    }
    const row = this.builtRows.find((item) => item.kind === "data" && rowId(item) === key);
    if (row) {
      this.openRow(row);
    }
  }

  handleCheck(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    this.checkedIds = { ...this.checkedIds, [id]: event.detail.checked };
  }

  handleSelectPage() {
    if (this.showJournalLockSelection !== true) {
      return;
    }
    const next = { ...this.checkedIds };
    this.currentPageCheckable.forEach((row) => {
      next[row.id] = true;
    });
    this.checkedIds = next;
  }

  handleClearPage() {
    if (this.showJournalLockSelection !== true) {
      return;
    }
    const next = { ...this.checkedIds };
    this.currentPageCheckable.forEach((row) => {
      next[row.id] = false;
    });
    this.checkedIds = next;
  }

  handleUnlockReason(event) {
    this.unlockReason = event.detail.value;
  }

  handleMemoInput(event) {
    const id = event.currentTarget.dataset.id;
    this.memoDrafts = { ...this.memoDrafts, [id]: event.detail.value };
  }

  async handleSaveJournals() {
    const checked =
      this.showJournalLockSelection === true
        ? this.currentPageCheckable
            .filter((row) => this.checkedIds[row.id] === true)
            .map((row) => row.id)
        : [];
    const memos = this.dirtyJournalEdits();
    if (!checked.length && !memos.length) {
      this.dispatchEvent(
        new ShowToastEvent({
          title:
            "チェックが無くメモの変更も追加項目の変更も無ければ実行できません。",
          variant: "error"
        })
      );
      return;
    }
    const unlocking = this.jouLock === "Locked";
    if (checked.length) {
      if (unlocking && this.isBlankReasonText(this.unlockReason)) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Unlockには理由が必要です",
            variant: "error"
          })
        );
        return;
      }
      if (unlocking && this.isUnlockReasonTooLong(this.unlockReason)) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Unlock理由は255文字以内で指定してください。",
            variant: "error"
          })
        );
        return;
      }
      const confirmed = await LightningConfirm.open({
        label: unlocking ? "仕訳をUnlock" : "仕訳をLock",
        message: unlocking
          ? "選んだ仕訳をUnlockします。よろしいですか？"
          : "選んだ仕訳をLockします。よろしいですか？",
        variant: "header"
      });
      if (!confirmed) {
        return;
      }
    }
    const invoiceTokens = {};
    this.journalRows.forEach((row) => {
      if (row.invoiceId && row.invoiceToken) {
        invoiceTokens[row.invoiceId] = row.invoiceToken;
      }
    });
    this.saving = true;
    try {
      const result = await saveJournals({
        request: {
          checkedJournalIds: checked,
          memos,
          unlockReason: unlocking ? this.unlockReason : null,
          lockState: this.jouLock,
          invoiceTokens
        }
      });
      if (result?.refreshed === true) {
        await this.fetchList(true);
        if (this.previewHistoryId) {
          await this.reloadInvoiceTile();
        }
      } else {
        this.applyLocalJournalEdits(memos);
      }
      this.dispatchEvent(
        new ShowToastEvent({
          title: "保存しました",
          variant: "success"
        })
      );
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "保存エラー",
          message: this.reduceError(error),
          variant: "error"
        })
      );
    } finally {
      this.saving = false;
    }
  }

  dirtyMemos() {
    return this.dirtyJournalEdits().filter(
      (draft) => draft.extraFieldValues == null
    );
  }

  // 仕様: 横断画面.md 第2.4節・操作27。メモ／追加項目だけの保存では左を取り直さない。
  dirtyJournalEdits() {
    const drafts = [];
    for (const row of this.journalRows) {
      if (row.invoiceCancelled === true) {
        continue;
      }
      const status = row.transactionStatus;
      if (status === "Cancelled" || status === "Reversal") {
        continue;
      }
      const memoDrafted = Object.prototype.hasOwnProperty.call(
        this.memoDrafts,
        row.id
      );
      const nextMemo = memoDrafted
        ? this.memoDrafts[row.id] == null
          ? ""
          : String(this.memoDrafts[row.id])
        : row.memo == null
          ? ""
          : String(row.memo);
      const currentMemo = row.memo == null ? "" : String(row.memo);
      const memoChanged = memoDrafted && nextMemo !== currentMemo;
      const extraChanged = this.journalExtraChanged(row);
      if (!memoChanged && !extraChanged) {
        continue;
      }
      drafts.push({
        journalId: row.id,
        invoiceId: row.invoiceId,
        memo: nextMemo,
        extraFieldValues: extraChanged ? this.extraValuesForSave(row) : null
      });
    }
    return drafts;
  }

  journalExtraChanged(row) {
    const drafts = (this.extraDrafts || {})[row.id];
    if (!drafts) {
      return false;
    }
    const stored = row.extraFieldValues || {};
    return Object.keys(drafts).some((apiName) => {
      return String(drafts[apiName] ?? "") !== String(stored[apiName] ?? "");
    });
  }

  extraValuesForSave(row) {
    const stored = row.extraFieldValues || {};
    const drafts = (this.extraDrafts || {})[row.id] || {};
    const values = {};
    (this.journalExtraDefinitions || []).forEach((definition) => {
      const apiName = definition.apiName;
      values[apiName] = Object.prototype.hasOwnProperty.call(drafts, apiName)
        ? drafts[apiName]
        : stored[apiName];
    });
    return values;
  }

  applyLocalMemos(memos) {
    this.applyLocalJournalEdits(memos);
  }

  applyLocalJournalEdits(memos) {
    const byId = {};
    const extraById = {};
    memos.forEach((draft) => {
      byId[draft.journalId] = draft.memo;
      if (draft.extraFieldValues) {
        extraById[draft.journalId] = draft.extraFieldValues;
      }
    });
    this.journalRows = this.journalRows.map((row) => {
      const next = Object.prototype.hasOwnProperty.call(byId, row.id)
        ? { ...row, memo: byId[row.id] }
        : { ...row };
      if (Object.prototype.hasOwnProperty.call(extraById, row.id)) {
        next.extraFieldValues = {
          ...(row.extraFieldValues || {}),
          ...extraById[row.id]
        };
      }
      return next;
    });
    this.memoDrafts = {};
    this.extraDrafts = {};
  }

  handleJournalExtraInput(event) {
    const id = event.currentTarget.dataset.id;
    const apiName = event.currentTarget.dataset.field;
    if (!id || !apiName) {
      return;
    }
    const value =
      event.currentTarget.dataset.inputKind === "checkbox"
        ? event.detail.checked === true
        : event.detail.value;
    this.extraDrafts = {
      ...(this.extraDrafts || {}),
      [id]: {
        ...((this.extraDrafts || {})[id] || {}),
        [apiName]: value
      }
    };
  }

  // 仕様: 横断画面.md 第2.4節。列モードONでは右を出さない。
  handleJournalColumnModeChange(event) {
    this.journalColumnMode = event.target.checked === true;
    if (this.journalColumnMode) {
      this.invoicePreview = null;
      this.selectedId = null;
    }
  }

  /** 仕様: 横断画面.md 第2.4節・第5節。右を開くときサーバの今を読む。同じ請求なら右は維持は仕訳導線だけ。 */
  openRow(row) {
    this.selectedId = row.id;
    if (this.menu === MENU_ESTIMATE) {
      this.loadEstimateTile(row.id);
      return;
    }
    if (
      this.menu === MENU_JOURNAL &&
      this.invoicePreview &&
      row.invoiceId &&
      row.invoiceId === this.tableInitialInvoiceId &&
      row.historyId === this.previewHistoryId
    ) {
      this.highlightJournalId = row.journalId || this.highlightJournalId;
      return;
    }
    this.loadInvoiceTile(row.historyId, row.invoiceId, row.journalId);
  }

  async loadEstimateTile(historyId) {
    this.estimateTile = null;
    this.estimateTileLoading = true;
    this.invoicePreview = null;
    try {
      this.estimateTile = await getEstimateTile({ historyId });
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.estimateTileLoading = false;
    }
  }

  async loadInvoiceTile(historyId, invoiceId, journalId) {
    this.estimateTile = null;
    this.invoicePreview = null;
    this.invoiceError = "";
    this.invoiceLoading = true;
    this.previewHistoryId = historyId;
    this.tableInitialInvoiceId = invoiceId;
    this.tableInitialActiveTab = journalId ? "journals" : null;
    this.highlightJournalId = journalId || null;
    this.invoiceTileNonce += 1;
    try {
      this.invoicePreview = await getInvoicePreview({
        contractHistoryId: historyId
      });
      this.billingAccountOptions = await getBillingAccountOptionsForPreview({
        contractHistoryId: historyId
      });
    } catch (error) {
      this.invoiceError = this.reduceError(error);
    } finally {
      this.invoiceLoading = false;
    }
  }

  async reloadInvoiceTile() {
    if (!this.previewHistoryId) {
      return;
    }
    await this.loadInvoiceTile(
      this.previewHistoryId,
      this.tableInitialInvoiceId,
      this.highlightJournalId
    );
  }

  handleSendEstimate(event) {
    this.overlayHistoryId = event.detail.historyId;
    this.showSendOverlay = true;
  }

  handleOrderEstimate(event) {
    this.overlayHistoryId = event.detail.historyId;
    this.showOrderOverlay = true;
  }

  handleOverlayClose() {
    this.showSendOverlay = false;
    this.showOrderOverlay = false;
    if (this.selectedId && this.menu === MENU_ESTIMATE) {
      this.loadEstimateTile(this.selectedId);
    }
  }

  handleIssueStateChange() {
    if (this.selectedId) {
      this.loadEstimateTile(this.selectedId);
    }
  }

  async handleJournalsLockComplete() {
    if (this.menu === MENU_JOURNAL) {
      await this.fetchList(true);
    }
    await this.reloadInvoiceTile();
  }

  async handleSaveLineAmounts(event) {
    const { edits, expectedTokenByInvoiceId, businessOperationKey } =
      event.detail || {};
    if (!edits?.length) {
      return;
    }
    await this.runEdit(() =>
      updateInvoiceLineAmounts({
        contractHistoryId: this.previewHistoryId,
        edits,
        expectedTokenByInvoiceId: expectedTokenByInvoiceId || {},
        businessOperationKey
      })
    );
  }

  async handleSaveAcceptanceEndDate(event) {
    const {
      lineId,
      acceptanceEndDate,
      cancellationDate,
      journalPreviewText,
      expectedContentVersion,
      businessOperationKey
    } = event.detail || {};
    if (!lineId) {
      return;
    }
    await this.runEdit(
      () =>
        updateInvoiceLineAcceptanceEndDate({
          contractHistoryId: this.previewHistoryId,
          lineId,
          acceptanceEndDate: acceptanceEndDate || null,
          expectedContentVersion:
            expectedContentVersion || this.invoicePreview?.contentVersion,
          cancellationDate: cancellationDate || null,
          businessOperationKey
        }),
      journalPreviewText || ""
    );
  }

  async handleSaveBillingHeader(event) {
    const {
      invoiceId,
      invoiceDate,
      paymentScheduledDate,
      expectedContentVersion,
      businessOperationKey,
      extraFieldValues
    } = event.detail || {};
    if (!invoiceId) {
      return;
    }
    const saved = await this.runEdit(() =>
      updateInvoiceHeaderAndDates({
        contractHistoryId: this.previewHistoryId,
        invoiceId,
        invoiceDate,
        paymentScheduledDate,
        billingAddressee: "",
        billingEmailTo: "",
        billingEmailCc: "",
        billingEmailBcc: "",
        taxPercent: null,
        expectedContentVersion:
          expectedContentVersion || this.invoicePreview?.contentVersion,
        businessOperationKey,
        extraFieldValues
      })
    );
    if (saved) {
      const table = this.template.querySelector("c-order-invoice-preview-table");
      if (table && typeof table.clearBillingEditState === "function") {
        table.clearBillingEditState();
      }
    }
  }

  async handleSplitInvoice(event) {
    const {
      mode,
      sourceInvoiceId,
      newInvoiceDate,
      newPaymentScheduledDate,
      newBillingAccountId,
      splitLines,
      expectedContentVersion,
      businessOperationKey
    } = event.detail || {};
    if (!sourceInvoiceId || !(splitLines || []).length) {
      return;
    }
    if (mode === "billingAccount") {
      await this.runEdit(
        () =>
          splitInvoiceByBillingAccount({
            contractHistoryId: this.previewHistoryId,
            sourceInvoiceId,
            newBillingAccountId,
            newInvoiceDate,
            newPaymentScheduledDate,
            splitLines,
            expectedContentVersion:
              expectedContentVersion || this.invoicePreview?.contentVersion,
            businessOperationKey
          }),
        "",
        { restrictToOpenedVersion: true }
      );
      return;
    }
    await this.runEdit(
      () =>
        splitInvoiceByDate({
          contractHistoryId: this.previewHistoryId,
          sourceInvoiceId,
          newInvoiceDate,
          newPaymentScheduledDate,
          splitLines,
          expectedContentVersion:
            expectedContentVersion || this.invoicePreview?.contentVersion,
          businessOperationKey
        }),
      "",
      { restrictToOpenedVersion: true }
    );
  }

  async handleMoveLines(event) {
    const {
      sourceInvoiceId,
      targetInvoiceId,
      lineIds,
      expectedContentVersion,
      expectedTargetContentVersion,
      businessOperationKey
    } = event.detail || {};
    if (!sourceInvoiceId || !targetInvoiceId || !(lineIds || []).length) {
      return;
    }
    await this.runEdit(
      () =>
        moveLinesToExistingInvoice({
          contractHistoryId: this.previewHistoryId,
          sourceInvoiceId,
          targetInvoiceId,
          lineIds,
          expectedContentVersion:
            expectedContentVersion || this.invoicePreview?.contentVersion,
          expectedTargetContentVersion:
            expectedTargetContentVersion ||
            expectedContentVersion ||
            this.invoicePreview?.contentVersion,
          businessOperationKey
        }),
      "",
      { restrictToOpenedVersion: true }
    );
  }

  async handleSplitLinesInPlace(event) {
    const { invoiceId, splitLines, expectedContentVersion, businessOperationKey } =
      event.detail || {};
    if (!invoiceId || !(splitLines || []).length) {
      return;
    }
    await this.runEdit(() =>
      splitLinesInPlace({
        contractHistoryId: this.previewHistoryId,
        invoiceId,
        splitLines,
        expectedContentVersion:
          expectedContentVersion || this.invoicePreview?.contentVersion,
        businessOperationKey
      })
    );
  }

  async handleApplyBillingAccountContent(event) {
    const { invoiceId, expectedContentVersion, businessOperationKey } =
      event.detail || {};
    if (!invoiceId) {
      return;
    }
    await this.runEdit(() =>
      applyBillingAccountContent({
        contractHistoryId: this.previewHistoryId,
        invoiceId,
        expectedContentVersion:
          expectedContentVersion || this.invoicePreview?.contentVersion,
        businessOperationKey
      })
    );
  }

  async handleCancelConfirmed(event) {
    const {
      invoiceId,
      cancellationReason,
      cancellationReasonText,
      cancellationDate,
      journalPreviewText,
      customerNotice,
      expectedContentVersion,
      businessOperationKey
    } = event.detail || {};
    if (!invoiceId) {
      return;
    }
    await this.runEdit(
      () =>
        cancelConfirmedFromPreview({
          contractHistoryId: this.previewHistoryId,
          invoiceId,
          cancellationReason,
          cancellationReasonText: cancellationReasonText || null,
          cancellationDate: cancellationDate || null,
          expectedContentVersion:
            expectedContentVersion || this.invoicePreview?.contentVersion,
          businessOperationKey
        }),
      [journalPreviewText, customerNotice].filter((part) => part).join("\n"),
      { restrictToOpenedVersion: true }
    );
  }

  async handleInvoiceOpsComplete() {
    await this.reloadInvoiceTile();
  }

  async runEdit(action, successMessage, options) {
    if (this.isSaving) {
      return false;
    }
    this.isSaving = true;
    this.invoiceError = "";
    try {
      const next = await action();
      // 仕様: 横断画面.md 操作14・操作32。成功後は右の当該 Version グループだけ取り直す。左の一覧全体はリロードしない。
      this.invoicePreview =
        options?.restrictToOpenedVersion === true
          ? restrictPreviewToOpenedVersion(next)
          : next;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "保存しました",
          message: successMessage || "請求正本を更新しました。",
          variant: "success",
          mode: successMessage ? "sticky" : "dismissable"
        })
      );
      return true;
    } catch (error) {
      this.invoiceError = this.reduceError(error);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "保存エラー",
          message: this.invoiceError,
          variant: "error"
        })
      );
      if (this.invoiceError === VERSION_CONFLICT_MESSAGE) {
        await this.reloadInvoiceTile();
      }
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  buildDisplayRows(rows) {
    const enabled = this.currentGroups.filter((item) => item.on);
    const flattened = [];
    this.nestRows(rows, enabled, 0, flattened);
    return flattened;
  }

  nestRows(rows, groups, depth, out) {
    if (depth >= groups.length) {
      rows.forEach((row) => out.push(this.toDataRow(row)));
      return;
    }
    const group = groups[depth];
    const buckets = [];
    let currentKey;
    let bucket = [];
    rows.forEach((row) => {
      const key = groupValue(row, group.id);
      if (currentKey === undefined || key !== currentKey) {
        if (bucket.length) {
          buckets.push({ key: currentKey, rows: bucket });
        }
        currentKey = key;
        bucket = [row];
      } else {
        bucket.push(row);
      }
    });
    if (bucket.length) {
      buckets.push({ key: currentKey, rows: bucket });
    }
    buckets.forEach((item) => {
      out.push(this.toHeaderRow(group, item.rows[0], item.rows));
      this.nestRows(item.rows, groups, depth + 1, out);
      if (group.total) {
        out.push(this.toTotalRow(group, item.rows));
      }
    });
  }

  toDataRow(row) {
    const id = row.id;
    const selected = id === this.selectedId;
    if (this.menu === MENU_JOURNAL) {
      const status = row.transactionStatus;
      const cancel = status === "Cancelled" || status === "Reversal";
      const rowClass = [
        "data-row",
        selected ? "is-selected" : "",
        cancel ? "row-cancel" : row.isLocked ? "row-locked" : ""
      ]
        .filter(Boolean)
        .join(" ");
      const memoValue = Object.prototype.hasOwnProperty.call(this.memoDrafts, id)
        ? this.memoDrafts[id]
        : row.memo || "";
      return {
        kind: "data",
        isData: true,
        key: `d-${id}`,
        id,
        historyId: row.historyId,
        invoiceId: row.invoiceId,
        journalId: id,
        canCheck: status === "Active" && this.showJournalLockSelection === true,
        checked: this.checkedIds[id] === true,
        rowClass,
        cells: this.journalCells(row, memoValue)
      };
    }
    if (this.menu === MENU_INVOICE) {
      return {
        kind: "data",
        isData: true,
        key: `d-${id}`,
        id,
        historyId: row.historyId,
        invoiceId: id,
        journalId: null,
        rowClass: selected ? "data-row is-selected" : "data-row",
        cells: this.invoiceCells(row)
      };
    }
    return {
      kind: "data",
      isData: true,
      key: `d-${id}`,
      id,
      historyId: id,
      invoiceId: null,
      journalId: null,
      rowClass: selected ? "data-row is-selected" : "data-row",
      cells: this.estimateCells(row)
    };
  }

  toHeaderRow(group, sample, rows) {
    const label = this.groupLabel(group, sample);
    const link = this.groupLink(group, sample);
    const extra = this.historyGroupOn && group.id === "history"
      ? `  見積税抜 ${formatAmount(sample.estimateAmount)}  請求合計 ${formatAmount(sample.versionInvoiceAmount)}  差額 ${formatAmount((Number(sample.estimateAmount) || 0) - (Number(sample.versionInvoiceAmount) || 0))}`
      : "";
    return {
      kind: "header",
      isHeader: true,
      key: `h-${group.id}-${groupValue(sample, group.id)}`,
      rowClass: "group-header",
      label: label + extra,
      href: link,
      isLink: Boolean(link)
    };
  }

  /** 仕様: 横断画面.md 第5節 小計・合計。数値・通貨列だけ足し、日付・名前・アイコンは空。 */
  toTotalRow(group, rows) {
    const sum = rows.reduce((acc, row) => acc + (Number(row.amount) || 0), 0);
    const amountLabel = formatAmount(sum);
    return {
      kind: "total",
      isTotal: true,
      key: `t-${group.id}-${groupValue(rows[0], group.id)}`,
      rowClass: "group-total",
      cells: this.columnHeaders.map((header) =>
        header.key === "amount"
          ? textCell(header.key, amountLabel, "num")
          : textCell(header.key, "")
      )
    };
  }

  groupLabel(group, sample) {
    switch (group.id) {
      case "closeDate":
        return formatDate(sample.closeDate);
      case "account":
        return sample.accountName || "";
      case "service":
        return sample.serviceName || "";
      case "billingAccount":
        return sample.billingAccountName || "";
      case "history":
        return `${sample.serviceName || ""} 版${sample.version ?? ""}`;
      case "invoiceStatus":
        return this.invoiceStatusLabel(sample.invoiceStatus);
      case "postingDate":
        return formatDate(sample.postingDate);
      case "invoice":
        return sample.invoiceName || "";
      case "event":
        return sample.eventName || sample.eventKey || "";
      default:
        return "";
    }
  }

  /** 仕様: 横断画面.md 第5節・操作11。Cancelledの表示名は取消済み。 */
  invoiceStatusLabel(status) {
    if (status === "Confirmed") {
      return "確定";
    }
    if (status === "Draft") {
      return "未確定";
    }
    if (status === "Cancelled") {
      return "取消済み";
    }
    return status || "";
  }

  groupLink(group, sample) {
    if (group.id === "billingAccount") {
      return recordUrl("BillingAccount__c", sample.billingAccountId);
    }
    if (group.id === "history") {
      return recordUrl("ContractHistory__c", sample.historyId);
    }
    if (group.id === "invoice") {
      return recordUrl("Invoice__c", sample.invoiceId);
    }
    return "";
  }

  estimateCells(row) {
    const cells = [];
    this.estimateGroups
      .filter((item) => !item.on)
      .forEach((item) => {
        cells.push(textCell(item.id, this.groupLabel(item, row)));
      });
    cells.push(textCell("version", row.version));
    cells.push(textCell("type", row.estimateTypeLabel || ""));
    cells.push(textCell("auto", row.autoRenew === true ? "自動Renew" : ""));
    cells.push(
      linkCell("opp", row.opportunityName, recordUrl("Opportunity", row.opportunityId))
    );
    cells.push(
      linkCell(
        "history",
        row.historyName,
        recordUrl("ContractHistory__c", row.id)
      )
    );
    cells.push(textCell("amount", formatAmount(row.amount), "num"));
    cells.push(textCell("valid", formatDate(row.validDate)));
    if (this.showEstimateSendFilter) {
      cells.push(iconCell("sent", row.sent === true, "utility:email", "送付済み"));
    }
    if (this.showEstimateIssueFilter) {
      cells.push(iconCell("issued", row.issued === true, "utility:file", "発行あり"));
    }
    return cells;
  }

  invoiceCells(row) {
    const cells = [];
    this.invoiceGroups
      .filter((item) => !item.on)
      .forEach((item) => {
        if (item.id === "billingAccount") {
          cells.push(
            linkCell(
              "ba",
              row.billingAccountName,
              recordUrl("BillingAccount__c", row.billingAccountId)
            )
          );
        } else if (item.id === "history") {
          cells.push(
            linkCell(
              "history",
              `${row.serviceName || ""} 版${row.version ?? ""}`,
              recordUrl("ContractHistory__c", row.historyId)
            )
          );
        } else {
          cells.push(textCell(item.id, this.groupLabel(item, row)));
        }
      });
    const marks = [];
    if (this.accountingEnabled) {
      if (row.hasMonthly) {
        marks.push("月次計上");
      }
      if (row.hasLump) {
        marks.push("一括計上");
      }
    }
    cells.push({
      key: "name",
      isLink: true,
      href: recordUrl("Invoice__c", row.id),
      text: row.invoiceName,
      sub: marks.join(" / "),
      className: ""
    });
    cells.push(
      linkCell("opp", row.opportunityName, recordUrl("Opportunity", row.opportunityId))
    );
    cells.push(textCell("account", row.accountName || ""));
    cells.push(textCell("invoiceDate", formatDate(row.invoiceDate)));
    cells.push(textCell("pay", formatDate(row.paymentScheduledDate)));
    cells.push(textCell("amount", formatAmount(row.amount), "num"));
    if (this.showInvoiceSendFilter) {
      cells.push(iconCell("sent", row.sent === true, "utility:email", "送付済み"));
    }
    if (this.showInvoiceIssueFilter) {
      // 仕様: 横断画面.md 操作23。発行アイコンから最新発行PDFをその場で開く。発行操作は走らせない。
      cells.push(
        iconCell(
          "issued",
          row.issued === true,
          "utility:file",
          "発行あり",
          issuedPdfPreviewUrl(row.latestIssuedContentDocumentId)
        )
      );
    }
    cells.push(iconCell("overdue", row.overdue === true, "utility:warning", "遅延"));
    if (this.accountingEnabled) {
      cells.push(textCell("next", formatDate(row.nextAcceptance)));
      cells.push(textCell("tags", (row.trueTagLabels || []).join(" ")));
    }
    if (!this.historyGroupOn) {
      cells.push(textCell("estAmt", formatAmount(row.estimateAmount), "num"));
      cells.push(textCell("verAmt", formatAmount(row.versionInvoiceAmount), "num"));
      cells.push(
        textCell(
          "diff",
          formatAmount(
            (Number(row.estimateAmount) || 0) -
              (Number(row.versionInvoiceAmount) || 0)
          ),
          "num"
        )
      );
    }
    cells.push(textCell("memo", row.memo || ""));
    return cells;
  }

  journalCells(row, memoValue) {
    const cells = [];
    this.journalGroups
      .filter((item) => !item.on && item.id !== "invoice")
      .forEach((item) => {
        if (item.id === "billingAccount") {
          cells.push(
            linkCell(
              "ba",
              row.billingAccountName,
              recordUrl("BillingAccount__c", row.billingAccountId)
            )
          );
        } else {
          cells.push(textCell(item.id, this.groupLabel(item, row)));
        }
      });
    cells.push(textCell("debit", row.debitName || ""));
    cells.push(textCell("credit", row.creditName || ""));
    cells.push(textCell("amount", formatAmount(row.amount), "num"));
    // 仕様: 横断画面.md 第5節
    cells.push(textCell("confirm", row.confirmationText || "", "confirm-cell"));
    // 仕様: 共通基盤 第1.4節・第10.4節、横断画面.md操作27。仕訳メモは10。取消済みは参照だけ。
    cells.push({
      key: "memo",
      isMemo: true,
      canEditMemo:
        this.canEditJournalMemoOp === true && row.invoiceCancelled !== true,
      value: memoValue,
      className: "memo-cell no-open"
    });
    cells.push(textCell("account", row.accountName || ""));
    cells.push(
      linkCell(
        "inv",
        row.invoiceName,
        recordUrl("Invoice__c", row.invoiceId)
      )
    );
    if (this.journalColumnMode) {
      const stored = row.extraFieldValues || {};
      const drafts = (this.extraDrafts || {})[row.id] || {};
      const exempt = new Set(
        (this.journalLockExemptFieldApiNames || []).map((name) =>
          String(name || "").trim()
        )
      );
      const cancelled =
        row.invoiceCancelled === true ||
        row.transactionStatus === "Cancelled" ||
        row.transactionStatus === "Reversal";
      (this.journalExtraDefinitions || []).forEach((definition) => {
        const apiName = definition.apiName;
        const raw = Object.prototype.hasOwnProperty.call(drafts, apiName)
          ? drafts[apiName]
          : stored[apiName];
        const lockedOut = row.isLocked === true && !exempt.has(apiName);
        const disabled =
          this.canEditJournalMemoOp !== true || cancelled || lockedOut;
        const fieldType = definition.fieldType || "STRING";
        const isCheckbox = fieldType === "BOOLEAN";
        const isPicklist = fieldType === "PICKLIST";
        const isTextarea =
          fieldType === "TEXTAREA" || fieldType === "LONGTEXTAREA";
        const checked =
          raw === true || raw === "true" || raw === "1" || raw === 1;
        cells.push({
          key: `extra-${apiName}`,
          isExtra: true,
          apiName,
          label: definition.label,
          value: isCheckbox ? checked : raw == null ? "" : raw,
          checked,
          isCheckbox,
          isPicklist,
          isTextarea,
          isInput: !isCheckbox && !isPicklist && !isTextarea,
          inputType: extraFieldInputType(fieldType),
          picklistOptions: definition.picklistOptions || [],
          required: definition.required === true && !disabled,
          disabled,
          className: "extra-cell no-open"
        });
      });
    }
    return cells;
  }

  windowRows(rows, page, pageSize) {
    const start = (page - 1) * pageSize;
    const end = page * pageSize;
    let dataIndex = -1;
    const firstByHeader = new Map();
    const lastByTotal = new Map();
    rows.forEach((row, index) => {
      if (row.kind === "data") {
        dataIndex += 1;
      } else if (row.kind === "header") {
        firstByHeader.set(index, dataIndex + 1);
      } else if (row.kind === "total") {
        lastByTotal.set(index, dataIndex);
      }
    });
    dataIndex = -1;
    const out = [];
    rows.forEach((row, index) => {
      if (row.kind === "data") {
        dataIndex += 1;
        if (dataIndex >= start && dataIndex < end) {
          out.push(row);
        }
        return;
      }
      if (row.kind === "header") {
        const first = firstByHeader.get(index);
        if (first >= start && first < end) {
          out.push(row);
        }
        return;
      }
      const last = lastByTotal.get(index);
      if (last >= start && last < end) {
        out.push(row);
      }
    });
    return out;
  }

  buildPageItems(page, total) {
    const items = [];
    const push = (n) =>
      items.push({
        key: String(n),
        label: String(n),
        page: n,
        className: n === page ? "page-btn is-active" : "page-btn"
      });
    if (total <= 7) {
      for (let i = 1; i <= total; i += 1) {
        push(i);
      }
      return items;
    }
    push(1);
    const from = Math.max(2, page - 1);
    const to = Math.min(total - 1, page + 1);
    if (from > 2) {
      items.push({ key: "l", label: "…", page: 0, className: "page-ellipsis" });
    }
    for (let i = from; i <= to; i += 1) {
      push(i);
    }
    if (to < total - 1) {
      items.push({ key: "r", label: "…", page: 0, className: "page-ellipsis" });
    }
    push(total);
    return items;
  }

  reduceError(error) {
    const alert = resolveSaveErrorAlert(error);
    if (alert?.messages?.length) {
      return alert.messages.map((entry) => entry.text).join("\n");
    }
    return error?.body?.message || error?.message || "処理に失敗しました。";
  }
}

function rowId(row) {
  return row.id;
}

function textCell(key, text, className) {
  return { key, isText: true, text: text == null ? "" : String(text), className: className || "" };
}

function linkCell(key, text, href) {
  return {
    key,
    isLink: true,
    text: text || "",
    href: href || "",
    className: ""
  };
}

function iconCell(key, on, icon, title, href) {
  return {
    key,
    isIcon: true,
    on,
    icon,
    title,
    href: href || "",
    className: "icon-cell"
  };
}
