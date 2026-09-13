import { createElement } from "lwc";
import ContractCrossWork from "c/contractCrossWork";
import getBootstrap from "@salesforce/apex/ContractCrossController.getBootstrap";
import queryEstimates from "@salesforce/apex/ContractCrossController.queryEstimates";
import queryInvoices from "@salesforce/apex/ContractCrossController.queryInvoices";
import queryJournals from "@salesforce/apex/ContractCrossController.queryJournals";
import getEstimateTile from "@salesforce/apex/ContractCrossController.getEstimateTile";
import getInvoiceOpsFieldDefinitions from "@salesforce/apex/InvoiceOpsFieldService.getDefinitions";
import getInvoicePreview from "@salesforce/apex/OrderCreateController.getInvoicePreview";
import getBillingAccountOptionsForPreview from "@salesforce/apex/OrderCreateController.getBillingAccountOptionsForPreview";
import updateInvoiceLineAmounts from "@salesforce/apex/OrderCreateController.updateInvoiceLineAmounts";
import updateInvoiceLineAcceptanceEndDate from "@salesforce/apex/OrderCreateController.updateInvoiceLineAcceptanceEndDate";
import updateInvoiceHeaderAndDates from "@salesforce/apex/OrderCreateController.updateInvoiceHeaderAndDates";
import splitInvoiceByDate from "@salesforce/apex/OrderCreateController.splitInvoiceByDate";
import splitInvoiceByBillingAccount from "@salesforce/apex/OrderCreateController.splitInvoiceByBillingAccount";
import moveLinesToExistingInvoice from "@salesforce/apex/OrderCreateController.moveLinesToExistingInvoice";
import splitLinesInPlace from "@salesforce/apex/OrderCreateController.splitLinesInPlace";
import applyBillingAccountContent from "@salesforce/apex/OrderCreateController.applyBillingAccountContent";
import cancelConfirmedFromPreview from "@salesforce/apex/OrderCreateController.cancelConfirmedFromPreview";
import saveJournals from "@salesforce/apex/ContractCrossController.saveJournals";
import { resolveSaveErrorAlert } from "c/estimateValidationAlertUtils";
import { openContentDocumentFilePreview } from "c/orderWizardNavigation";

jest.mock("c/estimateSendRecordAction");
jest.mock("c/orderCreateWizard");
jest.mock("c/contractCrossEstimateTile");
jest.mock("c/orderInvoicePreviewTable");
jest.mock(
  "c/orderWizardNavigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {},
    openContentDocumentFilePreview: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class {} }),
  { virtual: true }
);
jest.mock("lightning/refresh", () => ({ RefreshEvent: class {} }), {
  virtual: true
});
jest.mock(
  "@salesforce/apex/ContractCrossController.getBootstrap",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.queryEstimates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.queryInvoices",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.queryJournals",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.getEstimateTile",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.saveJournals",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/InvoiceOpsFieldService.getDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.getInvoicePreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.getBillingAccountOptionsForPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.updateInvoiceLineAmounts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.updateInvoiceLineAcceptanceEndDate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.splitInvoiceByDate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.splitInvoiceByBillingAccount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.moveLinesToExistingInvoice",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.splitLinesInPlace",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.updateInvoiceHeaderAndDates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.applyBillingAccountContent",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.cancelConfirmedFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/platformShowToastEvent",
  () => ({ ShowToastEvent: class {} }),
  { virtual: true }
);
jest.mock(
  "lightning/confirm",
  () => ({
    __esModule: true,
    default: { open: jest.fn() }
  }),
  { virtual: true }
);
jest.mock(
  "c/estimateValidationAlertUtils",
  () => ({ resolveSaveErrorAlert: jest.fn() }),
  { virtual: true }
);

const proto = ContractCrossWork.prototype;

function bind(overrides = {}) {
  const ctx = {
    menu: "estimate",
    accountingEnabled: true,
    canShowEstimateMenu: true,
    canShowInvoiceMenu: true,
    canIssueEstimate: true,
    canSendEstimate: true,
    canOrder: true,
    estimateSendMode: "PdfAndEmail",
    invoiceSendMode: "PdfOnly",
    bootstrapped: true,
    loading: false,
    saving: false,
    isSaving: false,
    errorMessage: "",
    truncated: false,
    truncatedMessage: "",
    completionNote: "",
    estimateRows: [],
    invoiceRows: [],
    journalRows: [],
    loaded: { estimate: true, invoice: false, journal: false },
    page: 1,
    selectedId: null,
    checkedIds: {},
    memoDrafts: {},
    extraDrafts: {},
    journalColumnMode: false,
    filtersOpen: false,
    displayOpen: false,
    leftPanePercent: 60,
    tagRules: [],
    tagFilterState: {},
    eventOptions: [{ label: "売上", value: "Rev" }],
    estimateGroups: [
      { id: "closeDate", label: "完了予定日", on: false, total: false }
    ],
    invoiceGroups: [
      { id: "history", label: "契約履歴", on: true, total: true }
    ],
    journalGroups: [
      { id: "postingDate", label: "計上日", on: false, total: false }
    ],
    sort1: "closeDate",
    sort1Dir: "asc",
    sort2: "account",
    sort2Dir: "asc",
    estimateSort: {
      sort1: "closeDate",
      sort1Dir: "asc",
      sort2: "account",
      sort2Dir: "asc"
    },
    invoiceSort: {
      sort1: "invoiceDate",
      sort1Dir: "asc",
      sort2: "account",
      sort2Dir: "asc"
    },
    journalSort: {
      sort1: "postingDate",
      sort1Dir: "asc",
      sort2: "invoiceName",
      sort2Dir: "asc"
    },
    estCloseFrom: "2026-04-01",
    estCloseTo: "2026-09-30",
    estAccountId: null,
    estServiceId: null,
    estType: "",
    estSent: "",
    estIssued: "",
    estAutoRenew: "",
    estValidFrom: "",
    estValidTo: "",
    invStatus: "Draft",
    invName: "",
    invBillingAccountId: null,
    invAccountId: null,
    invDateFrom: "",
    invDateTo: "",
    invCloseFrom: "",
    invCloseTo: "",
    invIncludeCancelled: false,
    invSent: "",
    invIssued: "",
    invOverdue: "",
    invCollection: "",
    invNextFrom: "",
    invNextTo: "",
    jouFrom: "2026-04-01",
    jouTo: "2026-09-30",
    jouLock: "Unlocked",
    jouEvent: "",
    jouBillingAccountId: null,
    jouAccountId: null,
    jouInvoiceId: null,
    jouCloseFrom: "",
    jouCloseTo: "",
    unlockReason: "",
    journalExtraDefinitions: [],
    journalLockExemptFieldApiNames: [],
    invoicePreview: null,
    invoiceTileNonce: 0,
    estimateTile: null,
    estimateTileLoading: false,
    invoiceLoading: false,
    previewHistoryId: null,
    tableInitialInvoiceId: null,
    highlightJournalId: null,
    overlayHistoryId: null,
    invoiceError: "",
    overlayBusy: false,
    showSendOverlay: false,
    showOrderOverlay: false,
    dispatchEvent: jest.fn(),
    template: {
      querySelector: jest.fn(() => null),
      querySelectorAll: jest.fn(() => [])
    },
    ...overrides
  };
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor" || Object.prototype.hasOwnProperty.call(ctx, name)) {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (desc.get && !desc.set) {
      Object.defineProperty(ctx, name, { get: desc.get, configurable: true });
    } else if (typeof desc.value === "function") {
      ctx[name] = desc.value;
    }
  });
  return ctx;
}

function bootstrapDto() {
  return {
    accountingEnabled: true,
    canIssueEstimate: true,
    canSendEstimate: true,
    canOrder: true,
    canShowEstimateMenu: true,
    canShowInvoiceMenu: true,
    estimateSendMode: "PdfAndEmail",
    invoiceSendMode: "PdfOnly",
    estimateCloseFrom: "2026-04-01",
    estimateCloseTo: "2026-09-30",
    journalPostingFrom: "2026-04-01",
    journalPostingTo: "2026-09-30",
    operationDay: "2026-09-13",
    tagRules: [{ fieldApiName: "Tag__c", label: "タグ" }],
    eventOptions: [{ label: "売上", value: "Rev" }],
    journalLockExemptFieldApiNames: []
  };
}

describe("contractCrossWork uncovered paths (共通基盤 横断 第1 / 2.4 / 5 / Core 4.10)", () => {
  beforeEach(() => {
    getBootstrap.mockReset().mockResolvedValue(bootstrapDto());
    getInvoiceOpsFieldDefinitions.mockReset().mockResolvedValue([]);
    queryEstimates.mockReset().mockResolvedValue({
      estimates: [
        {
          id: "a01EST",
          historyName: "履歴A",
          accountName: "取引先",
          serviceName: "サービス",
          amount: 12000,
          closeDate: "2026-09-30",
          estimateType: "New",
          estimateTypeLabel: "新規"
        }
      ],
      truncated: true
    });
    queryInvoices.mockReset().mockResolvedValue({ invoices: [] });
    queryJournals.mockReset().mockResolvedValue({ journals: [] });
    getEstimateTile.mockReset().mockResolvedValue({ id: "a01EST" });
    getInvoicePreview.mockReset().mockResolvedValue({
      sourceHistoryVersion: 1,
      invoices: [{ historyVersion: 1, invoiceName: "INV-1" }],
      versionOptions: [{ value: 1, label: "1" }]
    });
    getBillingAccountOptionsForPreview.mockReset().mockResolvedValue([]);
    updateInvoiceLineAmounts.mockReset().mockResolvedValue({
      sourceHistoryVersion: 1,
      invoices: [{ historyVersion: 1 }]
    });
    updateInvoiceLineAcceptanceEndDate.mockReset().mockResolvedValue({
      sourceHistoryVersion: 1,
      invoices: [{ historyVersion: 1 }]
    });
    updateInvoiceHeaderAndDates.mockReset().mockResolvedValue({
      sourceHistoryVersion: 1,
      invoices: [{ historyVersion: 1 }]
    });
    saveJournals.mockReset().mockResolvedValue({ refreshed: false });
    splitInvoiceByDate.mockReset().mockResolvedValue({
      sourceHistoryVersion: 1,
      invoices: [{ historyVersion: 1 }]
    });
    splitInvoiceByBillingAccount.mockReset().mockResolvedValue({
      sourceHistoryVersion: 1,
      invoices: [{ historyVersion: 1 }]
    });
    moveLinesToExistingInvoice.mockReset().mockResolvedValue({
      sourceHistoryVersion: 1,
      invoices: [{ historyVersion: 1 }]
    });
    splitLinesInPlace.mockReset().mockResolvedValue({
      sourceHistoryVersion: 1,
      invoices: [{ historyVersion: 1 }]
    });
    applyBillingAccountContent.mockReset().mockResolvedValue({
      sourceHistoryVersion: 1,
      invoices: [{ historyVersion: 1 }]
    });
    cancelConfirmedFromPreview.mockReset().mockResolvedValue({
      sourceHistoryVersion: 1,
      invoices: [{ historyVersion: 1 }]
    });
    resolveSaveErrorAlert.mockReset().mockReturnValue(null);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("mounts 契約横断 with 見積／請求／仕訳 and truncated 500件 (横断 第1節 / 第5節)", async () => {
    const el = createElement("c-contract-cross-work", { is: ContractCrossWork });
    document.body.appendChild(el);
    await Promise.resolve();
    await Promise.resolve();
    await new Promise((r) => setTimeout(r, 0));
    expect(el.shadowRoot.querySelector(".cross-title").textContent).toBe(
      "契約横断"
    );
    const menus = [...el.shadowRoot.querySelectorAll(".menu button")].map((b) =>
      b.textContent.trim()
    );
    expect(menus).toEqual(["見積", "請求", "仕訳"]);
    const warn = el.shadowRoot.querySelector(".alert_warn");
    expect(warn.textContent).toBe(
      "500件だけを取得しています。条件を狭めてリロードしてください。"
    );
    expect(el.shadowRoot.querySelector("button.btn_secondary").textContent.trim()).toBe(
      "リロード"
    );
    document.body.removeChild(el);
  });

  it("Accounting OFF hides 仕訳 menu (横断 第5節)", () => {
    const ctx = bind({ accountingEnabled: false, canShowInvoiceMenu: true });
    expect(ctx.showJournalMenu).toBe(false);
    ctx.handleMenu({ currentTarget: { dataset: { menu: "journal" } } });
    expect(ctx.menu).toBe("estimate");
  });

  it("Unused send mode hides issue and send filters (Core 4.10)", () => {
    const unused = bind({
      estimateSendMode: "Unused",
      invoiceSendMode: "Unused"
    });
    expect(unused.showEstimateIssueFilter).toBe(false);
    expect(unused.showEstimateSendFilter).toBe(false);
    expect(unused.showInvoiceIssueFilter).toBe(false);
    expect(unused.showInvoiceSendFilter).toBe(false);
    const pdf = bind({
      estimateSendMode: "PdfOnly",
      invoiceSendMode: "PdfAndEmail"
    });
    expect(pdf.showEstimateIssueFilter).toBe(true);
    expect(pdf.showEstimateSendFilter).toBe(false);
    expect(pdf.showInvoiceIssueFilter).toBe(true);
    expect(pdf.showInvoiceSendFilter).toBe(true);
  });

  it("type / status / lock labels stay 新規・未確定／確定・未Lock (横断 第5節)", () => {
    const ctx = bind();
    expect(ctx.triOptions.map((o) => o.label)).toEqual([
      "指定しない",
      "あり",
      "なし"
    ]);
    expect(ctx.typeOptions.map((o) => o.label)).toEqual([
      "指定しない",
      "新規",
      "追加変更",
      "更新",
      "解約"
    ]);
    expect(ctx.invoiceStatusOptions.map((o) => o.label)).toEqual([
      "未確定",
      "確定",
      "両方"
    ]);
    expect(ctx.lockOptions.map((o) => o.label)).toEqual(["未Lock", "Lock済み"]);
  });

  it("bootstrap then fetch invoices and journals (横断 第5節)", async () => {
    queryInvoices.mockResolvedValue({
      invoices: [
        {
          id: "a02INV",
          invoiceName: "INV-1",
          invoiceStatus: "Draft",
          historyId: "a01HIS",
          serviceName: "サービス",
          version: 1,
          amount: 1000
        }
      ],
      truncated: false
    });
    queryJournals.mockResolvedValue({
      journals: [
        {
          id: "a03JOU",
          postingDate: "2026-04-01",
          invoiceName: "INV-1",
          invoiceId: "a02INV",
          amount: 1000,
          transactionStatus: "Active",
          lockState: "Unlocked",
          memo: ""
        }
      ]
    });
    const ctx = bind({ bootstrapped: false, loaded: { estimate: false, invoice: false, journal: false } });
    await ctx.bootstrap();
    expect(ctx.bootstrapped).toBe(true);
    expect(ctx.estimateRows.length).toBe(1);
    ctx.handleMenu({ currentTarget: { dataset: { menu: "invoice" } } });
    await Promise.resolve();
    expect(ctx.menu).toBe("invoice");
    expect(ctx.invoiceStatusOptions[0].label).toBe("未確定");
    ctx.handleMenu({ currentTarget: { dataset: { menu: "journal" } } });
    await Promise.resolve();
    expect(ctx.menu).toBe("journal");
    expect(ctx.pageSize).toBe(50);
  });

  it("invoiceFilter omits hidden send/issue; journalFilter keeps lock (横断 第5節)", () => {
    const inv = bind({
      invoiceSendMode: "PdfOnly",
      invSent: "true",
      invIssued: "true",
      accountingEnabled: true,
      tagRules: [{ fieldApiName: "Tag__c" }],
      tagFilterState: { Tag__c: "True" }
    });
    const invoiceFilter = inv.invoiceFilter();
    expect(invoiceFilter.sent).toBe(null);
    expect(invoiceFilter.issued).toBe(true);
    expect(invoiceFilter.tagFilters).toEqual([
      { fieldApiName: "Tag__c", state: "True" }
    ]);
    const jou = bind({ menu: "journal", jouLock: "Locked" });
    expect(jou.journalFilter().lockState).toBe("Locked");
  });

  it("applyTruncation uses default 500件 copy (横断 第5節)", () => {
    const ctx = bind();
    ctx.applyTruncation({ truncated: true });
    expect(ctx.truncatedMessage).toBe(
      "500件だけを取得しています。条件を狭めてリロードしてください。"
    );
    ctx.applyTruncation({ truncated: false });
    expect(ctx.truncatedMessage).toBe("");
  });

  it("keepOpenedVersionGroup keeps only the opened Version (横断 第2.4節)", () => {
    const ctx = bind();
    const next = ctx.keepOpenedVersionGroup({
      sourceHistoryVersion: 2,
      invoices: [
        { historyVersion: 1, invoiceName: "old" },
        { historyVersion: 2, invoiceName: "cur" }
      ],
      versionOptions: [
        { value: 1, label: "1" },
        { value: 2, label: "2" }
      ]
    });
    expect(next.invoices.map((i) => i.invoiceName)).toEqual(["cur"]);
  });

  it("runEdit version conflict keeps 他のユーザーが先に更新しました (横断 操作14)", async () => {
    resolveSaveErrorAlert.mockReturnValue(null);
    const ctx = bind({
      selectedId: "a02INV",
      menu: "invoice",
      invoicePreview: { sourceHistoryVersion: 1, contractHistoryId: "a01HIS" }
    });
    getInvoicePreview.mockResolvedValue({
      sourceHistoryVersion: 1,
      invoices: []
    });
    const failed = await ctx.runEdit(
      async () => {
        const err = new Error(
          "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。"
        );
        err.body = { message: err.message };
        throw err;
      },
      "",
      { restrictToOpenedVersion: true }
    );
    expect(failed).toBe(false);
    expect(ctx.invoiceError).toBe(
      "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。"
    );
  });

  it("runEdit success note is 請求情報を保存しました (横断 操作14)", async () => {
    const ctx = bind({ isSaving: false });
    const ok = await ctx.runEdit(
      async () => ({
        sourceHistoryVersion: 1,
        invoices: [{ historyVersion: 1 }]
      }),
      "",
      { restrictToOpenedVersion: true }
    );
    expect(ok).toBe(true);
    expect(ctx.completionNote).toBe("請求情報を保存しました。");
  });

  it("handleReload refetches; reduceError falls back to 処理に失敗しました", async () => {
    const ctx = bind();
    await ctx.handleReload();
    expect(queryEstimates).toHaveBeenCalled();
    expect(ctx.reduceError({})).toBe("処理に失敗しました。");
  });

  it("display rows group 契約履歴 and total amount only (横断 第5節 小計)", () => {
    const ctx = bind({
      menu: "invoice",
      invoiceRows: [
        {
          id: "a02INV",
          invoiceName: "INV-1",
          invoiceStatus: "Draft",
          historyId: "a01HIS",
          serviceName: "サービス",
          version: 1,
          amount: 1000,
          billingAccountName: "BA"
        }
      ]
    });
    const rows = ctx.buildDisplayRows(ctx.invoiceRows);
    expect(rows.some((r) => r.kind === "header")).toBe(true);
    expect(rows.some((r) => r.kind === "total")).toBe(true);
    expect(ctx.displayRows.length).toBeGreaterThan(0);
  });

  it("window arrows skip INPUT (横断 第5節)", () => {
    const ctx = bind({
      estimateRows: [
        { id: "a01EST", amount: 1, closeDate: "2026-09-30" },
        { id: "a01ES2", amount: 2, closeDate: "2026-09-30" }
      ],
      selectedId: "a01EST"
    });
    const input = document.createElement("input");
    ctx.handleWindowKeydown({
      key: "ArrowDown",
      target: input,
      preventDefault: jest.fn()
    });
    expect(ctx.selectedId).toBe("a01EST");
  });

  it("handleFilterChange on invName does not fetch immediately (横断 第5節)", () => {
    jest.useFakeTimers();
    const ctx = bind();
    const fetchList = jest.spyOn(ctx, "fetchList").mockResolvedValue();
    ctx.handleFilterChange({
      target: { name: "invName", value: "INV" },
      currentTarget: { dataset: {} },
      detail: { value: "INV" }
    });
    expect(fetchList).not.toHaveBeenCalled();
    jest.advanceTimersByTime(400);
    expect(fetchList).toHaveBeenCalled();
    jest.useRealTimers();
  });

  it("disconnectedCallback removes keydown", () => {
    const ctx = bind({ _keydown: jest.fn(), _filterFetchTimer: undefined });
    ctx.disconnectedCallback();
    expect(ctx._boundSplitMove).toBe(null);
  });

  it("empty journal save is チェックが無くメモの変更も追加項目の変更も無ければ実行できません", async () => {
    const ctx = bind({
      menu: "journal",
      journalRows: [
        {
          id: "a03JOU",
          invoiceId: "a02INV",
          invoiceCancelled: false,
          transactionStatus: "Active",
          memo: ""
        }
      ]
    });
    await ctx.handleSaveJournals();
    expect(ctx.errorMessage).toBe(
      "チェックが無くメモの変更も追加項目の変更も無ければ実行できません。"
    );
  });

  it("memo-only journal save is 仕訳を保存しました (横断 第2.4節)", async () => {
    const ctx = bind({
      menu: "journal",
      journalRows: [
        {
          id: "a03JOU",
          invoiceId: "a02INV",
          invoiceCancelled: false,
          transactionStatus: "Active",
          memo: "旧"
        }
      ],
      memoDrafts: { a03JOU: "新メモ" }
    });
    await ctx.handleSaveJournals();
    expect(ctx.completionNote).toBe("仕訳を保存しました。");
    expect(saveJournals).toHaveBeenCalled();
  });

  it("openRow estimate loads tile; invoice opens preview (横断 第5節)", async () => {
    const est = bind({ menu: "estimate" });
    await est.openRow({ id: "a01EST" });
    expect(getEstimateTile).toHaveBeenCalledWith({ historyId: "a01EST" });
    const inv = bind({
      menu: "invoice",
      invoiceTileNonce: 0,
      previewHistoryId: null
    });
    await inv.openRow({
      id: "a02INV",
      historyId: "a01HIS",
      invoiceId: "a02INV",
      journalId: null
    });
    expect(getInvoicePreview).toHaveBeenCalled();
  });

  it("filters lookup/tag/group/sort and paging (横断 第5節)", async () => {
    const ctx = bind({
      menu: "estimate",
      page: 1,
      estimateRows: Array.from({ length: 25 }, (_, i) => ({
        id: `e${i}`,
        amount: i,
        closeDate: "2026-09-30"
      }))
    });
    await ctx.handleLookupChange({
      currentTarget: { dataset: { name: "estAccountId" } },
      detail: { recordId: "001AAA" }
    });
    expect(ctx.estAccountId).toBe("001AAA");
    ctx.handleTagChip({ currentTarget: { dataset: { field: "Tag__c" } } });
    expect(ctx.tagFilterState.Tag__c).toBe("True");
    ctx.handleGroupOn({
      currentTarget: { dataset: { id: "closeDate" } },
      detail: { checked: true }
    });
    expect(ctx.estimateGroups[0].on).toBe(true);
    ctx.handleGroupTotal({
      currentTarget: { dataset: { id: "closeDate" } },
      detail: { checked: true }
    });
    ctx.handleSortChange({
      target: { name: "sort1Dir" },
      detail: { value: "desc" }
    });
    expect(ctx.sort1Dir).toBe("desc");
    ctx.handlePageClick({ currentTarget: { dataset: { page: "2" } } });
    expect(ctx.page).toBe(2);
  });

  it("send/order overlays and issue refresh (横断 第4節)", async () => {
    const ctx = bind({ selectedId: "a01EST", menu: "estimate" });
    ctx.handleSendEstimate({ detail: { historyId: "a01EST" } });
    expect(ctx.showSendOverlay).toBe(true);
    ctx.overlayBusy = false;
    ctx.handleOverlayClose();
    expect(ctx.showSendOverlay).toBe(false);
    ctx.handleOrderEstimate({ detail: { historyId: "a01EST" } });
    expect(ctx.showOrderOverlay).toBe(true);
    ctx.handleIssueStateChange();
    expect(getEstimateTile).toHaveBeenCalled();
  });

  it("invoice line amount / header / acceptance save notes 請求情報を保存しました", async () => {
    const ctx = bind({
      previewHistoryId: "a01HIS",
      invoicePreview: { contentVersion: 1, sourceHistoryVersion: 1 }
    });
    await ctx.handleSaveLineAmounts({
      detail: {
        edits: [{ lineId: "li1", amount: 100 }],
        expectedTokenByInvoiceId: {},
        businessOperationKey: "k1"
      }
    });
    expect(ctx.completionNote).toBe("請求情報を保存しました。");
    await ctx.handleSaveBillingHeader({
      detail: {
        invoiceId: "a02INV",
        invoiceDate: "2026-04-01",
        paymentScheduledDate: "2026-04-30",
        expectedContentVersion: 1,
        businessOperationKey: "k2",
        extraFieldValues: {}
      }
    });
    await ctx.handleSaveAcceptanceEndDate({
      detail: {
        lineId: "li1",
        acceptanceEndDate: "2026-04-30",
        businessOperationKey: "k3"
      }
    });
    expect(updateInvoiceLineAcceptanceEndDate).toHaveBeenCalled();
  });

  it("row click opens estimate; link click does not (横断 第5節)", async () => {
    const ctx = bind({
      menu: "estimate",
      estimateRows: [
        {
          id: "a01EST",
          amount: 1,
          closeDate: "2026-09-30",
          historyName: "履歴A"
        }
      ]
    });
    const anchor = document.createElement("a");
    ctx.handleRowClick({
      target: { closest: (sel) => (sel.includes("a") ? anchor : null) },
      currentTarget: { dataset: { id: "a01EST" } }
    });
    expect(getEstimateTile).not.toHaveBeenCalled();
    ctx.handleRowClick({
      target: { closest: () => null },
      currentTarget: { dataset: { id: "a01EST" } }
    });
    await Promise.resolve();
    expect(getEstimateTile).toHaveBeenCalled();
  });

  it("pdf preview and memo input (横断 第5節)", () => {
    const ctx = bind({ menu: "journal" });
    ctx.handleIssuedPdfPreview({
      stopPropagation: jest.fn(),
      currentTarget: { dataset: { documentId: "069AAA" } }
    });
    expect(openContentDocumentFilePreview).toHaveBeenCalled();
    ctx.handleMemoInput({
      currentTarget: { dataset: { id: "a03JOU" } },
      detail: { value: "メモ" }
    });
    expect(ctx.memoDrafts.a03JOU).toBe("メモ");
    ctx.handleUnlockReason({ detail: { value: "理由" } });
    expect(ctx.unlockReason).toBe("理由");
  });

  it("journal column headers include 確認用 and メモ (横断 第5節)", () => {
    const ctx = bind({ menu: "journal", journalColumnMode: false });
    const labels = ctx.columnHeaders.map((h) => h.label);
    expect(labels).toContain("確認用");
    expect(labels).toContain("メモ");
  });

  it("split / move / apply account / cancel keep 請求情報を保存しました (横断 第4節)", async () => {
    const ctx = bind({
      previewHistoryId: "a01HIS",
      invoicePreview: { contentVersion: 1, sourceHistoryVersion: 1 }
    });
    const splitLines = [{ lineId: "li1", quantity: 1 }];
    await ctx.handleSplitInvoice({
      detail: {
        mode: "date",
        sourceInvoiceId: "a02INV",
        newInvoiceDate: "2026-05-01",
        splitLines,
        businessOperationKey: "s1"
      }
    });
    await ctx.handleSplitInvoice({
      detail: {
        mode: "billingAccount",
        sourceInvoiceId: "a02INV",
        newBillingAccountId: "a00BA",
        splitLines,
        businessOperationKey: "s2"
      }
    });
    await ctx.handleMoveLines({
      detail: {
        sourceInvoiceId: "a02INV",
        targetInvoiceId: "a02INV2",
        lineIds: ["li1"],
        businessOperationKey: "m1"
      }
    });
    await ctx.handleSplitLinesInPlace({
      detail: {
        invoiceId: "a02INV",
        splitLines,
        businessOperationKey: "s3"
      }
    });
    await ctx.handleApplyBillingAccountContent({
      detail: { invoiceId: "a02INV", businessOperationKey: "a1" }
    });
    await ctx.handleCancelConfirmed({
      detail: {
        invoiceId: "a02INV",
        cancellationReason: "Other",
        businessOperationKey: "c1"
      }
    });
    expect(ctx.completionNote).toBe("請求情報を保存しました。");
    expect(splitInvoiceByDate).toHaveBeenCalled();
    expect(cancelConfirmedFromPreview).toHaveBeenCalled();
  });

  it("sort labels 昇順, move row, reload tile, column mode (横断 第5節 / 第2.4節)", async () => {
    const ctx = bind({
      menu: "estimate",
      selectedId: "e0",
      previewHistoryId: "a01HIS",
      estimateRows: [
        { id: "e0", amount: 1, closeDate: "2026-09-01", accountName: "A" },
        { id: "e1", amount: 2, closeDate: "2026-09-02", accountName: "B" }
      ]
    });
    expect(ctx.dirOptions.map((o) => o.label)).toEqual(["昇順", "降順"]);
    expect(ctx.sortFieldOptions.some((o) => o.label === "完了予定日")).toBe(
      true
    );
    const inv = bind({ menu: "invoice" });
    expect(inv.sortFieldOptions.some((o) => o.label === "請求日")).toBe(true);
    const jou = bind({ menu: "journal" });
    expect(jou.sortFieldOptions.some((o) => o.label === "計上日")).toBe(true);
    const prevent = jest.fn();
    ctx.handleWindowKeydown({
      key: "ArrowDown",
      target: document.body,
      preventDefault: prevent
    });
    expect(prevent).toHaveBeenCalled();
    await ctx.handleInvoiceOpsComplete();
    expect(getInvoicePreview).toHaveBeenCalled();
    await ctx.handleJournalsLockComplete();
    ctx.handleJournalColumnModeChange({
      target: { checked: true },
      detail: { checked: true }
    });
    expect(ctx.journalColumnMode).toBe(true);
    expect(ctx.invoicePreview).toBe(null);
    ctx.handleJournalExtraInput({
      currentTarget: {
        dataset: { id: "a03JOU", field: "Foo__c", inputKind: "text" }
      },
      detail: { value: "x" }
    });
    expect(ctx.extraDrafts.a03JOU.Foo__c).toBe("x");
    ctx.handleGroupMove({
      currentTarget: { dataset: { id: "closeDate", dir: "1" } }
    });
    ctx.handleCheck({
      stopPropagation: jest.fn(),
      currentTarget: { dataset: { id: "a03JOU" } },
      detail: { checked: true }
    });
    expect(ctx.checkedIds.a03JOU).toBe(true);
    expect(ctx.collectionOptions.map((o) => o.label)).toContain("未対応");
  });
});

