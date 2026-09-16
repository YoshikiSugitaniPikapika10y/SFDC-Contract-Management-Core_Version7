import ContractCrossWork from "c/contractCrossWork";

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
  "@salesforce/apex/ContractCrossController.getInvoicePreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.getBillingAccountOptionsForPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.updateInvoiceLineAmounts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.updateInvoiceLineAcceptanceEndDate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.splitInvoiceByDate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.splitInvoiceByBillingAccount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.moveLinesToExistingInvoice",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.splitLinesInPlace",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.updateInvoiceHeaderAndDates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.applyBillingAccountContent",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.cancelConfirmedFromPreview",
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

describe("contractCrossWork left chrome (共通基盤 第5節)", () => {
  const proto = ContractCrossWork.prototype;
  const filterSummaryItems = Object.getOwnPropertyDescriptor(
    proto,
    "filterSummaryItems"
  ).get;
  const splitClass = Object.getOwnPropertyDescriptor(proto, "splitClass").get;
  const showFilterSummary = Object.getOwnPropertyDescriptor(
    proto,
    "showFilterSummary"
  ).get;

  it("既定はフィルタを畳み、効いている条件の要約を出す", () => {
    const items = filterSummaryItems.call({
      isEstimateMenu: true,
      isInvoiceMenu: false,
      isJournalMenu: false,
      estCloseFrom: "2026-06-08",
      estCloseTo: "2026-09-30",
      estAccountId: null,
      estServiceId: null,
      estType: "",
      estSent: "",
      estIssued: "",
      estAutoRenew: "",
      estValidFrom: "",
      estValidTo: "",
      typeOptions: [],
      showEstimateSendFilter: false,
      showEstimateIssueFilter: false
    });
    expect(items.map((item) => item.text)).toEqual([
      "完了予定日 2026-06-08〜2026-09-30"
    ]);
    expect(
      showFilterSummary.call({
        filtersOpen: false,
        filterSummaryItems: items
      })
    ).toBe(true);
    expect(
      showFilterSummary.call({
        filtersOpen: true,
        filterSummaryItems: items
      })
    ).toBe(false);
  });

  it("請求の既定要約は請求状態だけであり、取消済みOFFは出さない", () => {
    const items = filterSummaryItems.call({
      isEstimateMenu: false,
      isInvoiceMenu: true,
      isJournalMenu: false,
      invStatus: "Draft",
      invName: "",
      invBillingAccountId: null,
      invAccountId: null,
      invDateFrom: "",
      invDateTo: "",
      invIncludeCancelled: false,
      invSent: "",
      invIssued: "",
      invOverdue: "",
      invCollection: "",
      invoiceStatusOptions: [{ label: "未確定", value: "Draft" }],
      collectionOptions: [],
      showInvoiceSendFilter: false,
      showInvoiceIssueFilter: false,
      showAccountingInvoiceColumns: false
    });
    expect(items.map((item) => item.text)).toEqual(["請求状態 未確定"]);
  });

  it("左右は左を広くし、列モードでは全幅にする", () => {
    expect(
      splitClass.call({
        isJournalMenu: false,
        journalColumnMode: false,
        showRightPane: true
      })
    ).toBe("split has-handle");
    expect(
      splitClass.call({
        isJournalMenu: true,
        journalColumnMode: true,
        showRightPane: false
      })
    ).toBe("split split_column-mode");
    expect(
      Object.getOwnPropertyDescriptor(proto, "splitCssVars").get.call({
        leftPanePercent: 60
      })
    ).toBe("--cross-left: 60%;");
  });

  it("絞り込みと表示は畳み開きできる", () => {
    const ctx = { filtersOpen: false, displayOpen: false };
    proto.handleToggleFilters.call(ctx);
    proto.handleToggleDisplay.call(ctx);
    expect(ctx.filtersOpen).toBe(true);
    expect(ctx.displayOpen).toBe(true);
    proto.handleOpenFilters.call(ctx);
    expect(ctx.filtersOpen).toBe(true);
  });

  it("請求名は入力の区切りまでサーバを叩かない", () => {
    jest.useFakeTimers();
    const fetchList = jest.fn();
    const ctx = { fetchList, _filterFetchTimer: undefined };
    proto.scheduleFilterFetch.call(ctx, "invName");
    expect(fetchList).not.toHaveBeenCalled();
    jest.advanceTimersByTime(399);
    expect(fetchList).not.toHaveBeenCalled();
    jest.advanceTimersByTime(1);
    expect(fetchList).toHaveBeenCalledWith(true);
    proto.scheduleFilterFetch.call(ctx, "invStatus");
    expect(fetchList).toHaveBeenCalledTimes(2);
    jest.useRealTimers();
  });
});
