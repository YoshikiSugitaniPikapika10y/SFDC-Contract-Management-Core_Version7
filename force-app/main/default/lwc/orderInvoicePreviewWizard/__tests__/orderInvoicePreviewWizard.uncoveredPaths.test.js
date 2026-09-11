import OrderInvoicePreviewWizard from "c/orderInvoicePreviewWizard";
import resolvePreviewScope from "@salesforce/apex/OrderCreateController.resolvePreviewScope";
import getInvoicePreview from "@salesforce/apex/OrderCreateController.getInvoicePreview";
import getBillingAccountOptionsForPreview from "@salesforce/apex/OrderCreateController.getBillingAccountOptionsForPreview";
import updateInvoiceLineAmounts from "@salesforce/apex/OrderCreateController.updateInvoiceLineAmounts";
import updateInvoiceLineAcceptanceEndDate from "@salesforce/apex/OrderCreateController.updateInvoiceLineAcceptanceEndDate";
import splitInvoiceByDate from "@salesforce/apex/OrderCreateController.splitInvoiceByDate";
import splitInvoiceByBillingAccount from "@salesforce/apex/OrderCreateController.splitInvoiceByBillingAccount";
import moveLinesToExistingInvoice from "@salesforce/apex/OrderCreateController.moveLinesToExistingInvoice";
import splitLinesInPlace from "@salesforce/apex/OrderCreateController.splitLinesInPlace";
import resetLatestVersionInvoicesToPostOrder from "@salesforce/apex/OrderCreateController.resetLatestVersionInvoicesToPostOrder";
import updateInvoiceHeaderAndDates from "@salesforce/apex/OrderCreateController.updateInvoiceHeaderAndDates";
import applyBillingAccountContent from "@salesforce/apex/OrderCreateController.applyBillingAccountContent";
import cancelConfirmedFromPreview from "@salesforce/apex/OrderCreateController.cancelConfirmedFromPreview";
import {
  requestOrderWizardClose
} from "c/orderWizardClose";
import {
  closeOrderWizardTab,
  readOrderWizardRecordId,
  isOrderWizardTabView
} from "c/orderWizardNavigation";

jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);
jest.mock(
  "lightning/refresh",
  () => ({ RefreshEvent: class RefreshEvent {} }),
  { virtual: true }
);
jest.mock(
  "lightning/navigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {},
    CurrentPageReference: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "lightning/platformShowToastEvent",
  () => ({ ShowToastEvent: class ShowToastEvent {} }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardNavigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {},
    closeOrderWizardTab: jest.fn(),
    initializeOrderWizardFromUrl: jest.fn(),
    isOrderWizardTabView: jest.fn(() => false),
    readOrderWizardRecordId: jest.fn(() => "")
  }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardClose",
  () => ({
    isOrderActionBootstrapping: jest.fn(() => false),
    requestOrderWizardClose: jest.fn(),
    scheduleRecordActionLoad: jest.fn((ctx, fn) =>
      typeof fn === "function" ? fn() : undefined
    ),
    resetRecordActionLoadState: jest.fn(),
    closeOrderWizardTab: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "c/estimateValidationAlertUtils",
  () => ({
    resolveSaveErrorAlert: jest.fn((error) => ({
      messages: [
        {
          text:
            error?.body?.message || error?.message || "処理に失敗しました。"
        }
      ]
    }))
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/OrderCreateController.resolvePreviewScope",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.getInvoicePreview",
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
  "@salesforce/apex/OrderCreateController.resetLatestVersionInvoicesToPostOrder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.getBillingAccountOptionsForPreview",
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

const proto = OrderInvoicePreviewWizard.prototype;
const VERSION_CONFLICT =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";

function bind(overrides = {}) {
  const ctx = {
    recordId: "a0H000000000001AAA",
    isTabView: false,
    isLoading: false,
    isSaving: false,
    errorMessage: "",
    contentLoadFailed: false,
    invoicePreview: { contentVersion: "v1", invoices: [] },
    completionNote: "",
    billingAccountOptions: [],
    previewScope: { contractHistoryId: "a0H000000000001AAA", canOpen: true },
    template: { querySelector: jest.fn(() => null), host: { style: { setProperty: jest.fn() } } },
    dispatchEvent: jest.fn(),
    ...overrides
  };
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor" || name === "dispatchEvent") {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (!desc || (desc.get && desc.set)) {
      return;
    }
    if (Object.prototype.hasOwnProperty.call(ctx, name)) {
      return;
    }
    if (desc.get && !desc.set) {
      Object.defineProperty(ctx, name, { get: desc.get, configurable: true });
    } else if (typeof desc.value === "function") {
      ctx[name] = desc.value;
    }
  });
  return ctx;
}

describe("orderInvoicePreviewWizard uncovered (Core 7.7 / 7.9.7 / 4.3.11)", () => {
  beforeEach(() => {
    resolvePreviewScope.mockReset().mockResolvedValue({
      canOpen: true,
      contractHistoryId: "a0H000000000001AAA",
      initialVersion: "1",
      initialInvoiceId: "a00INV"
    });
    getInvoicePreview.mockReset().mockResolvedValue({
      contentVersion: "v2",
      invoices: []
    });
    getBillingAccountOptionsForPreview.mockReset().mockResolvedValue([]);
    updateInvoiceLineAmounts.mockReset().mockResolvedValue({ invoices: [] });
    updateInvoiceLineAcceptanceEndDate.mockReset().mockResolvedValue({
      invoices: []
    });
    splitInvoiceByDate.mockReset().mockResolvedValue({ invoices: [] });
    splitInvoiceByBillingAccount.mockReset().mockResolvedValue({ invoices: [] });
    moveLinesToExistingInvoice.mockReset().mockResolvedValue({ invoices: [] });
    splitLinesInPlace.mockReset().mockResolvedValue({ invoices: [] });
    resetLatestVersionInvoicesToPostOrder.mockReset().mockResolvedValue({
      invoices: []
    });
    updateInvoiceHeaderAndDates.mockReset().mockResolvedValue({ invoices: [] });
    applyBillingAccountContent.mockReset().mockResolvedValue({ invoices: [] });
    cancelConfirmedFromPreview.mockReset().mockResolvedValue({ invoices: [] });
  });

  it("empty recordId does not load", async () => {
    const ctx = bind({ recordId: "" });
    await ctx.loadPreview();
    expect(resolvePreviewScope).not.toHaveBeenCalled();
  });

  it("canOpen false without blockReason uses 請求ボードを開けません。", async () => {
    resolvePreviewScope.mockResolvedValue({ canOpen: false });
    const ctx = bind({ invoicePreview: undefined });
    await ctx.loadPreview();
    expect(ctx.errorMessage).toBe("請求ボードを開けません。");
    expect(ctx.contentLoadFailed).toBe(false);
  });

  it("load failure shows 再読み込み path (Core 4.3.11)", async () => {
    getInvoicePreview.mockRejectedValue({ body: { message: "読込失敗" } });
    const ctx = bind({ invoicePreview: undefined });
    await ctx.loadPreview();
    expect(ctx.errorMessage).toBe("読込失敗");
    expect(ctx.contentLoadFailed).toBe(true);
    ctx.handleContentReload();
    await Promise.resolve();
  });

  it("pageClass is modal vs tab and table initials follow scope", () => {
    const modal = bind();
    expect(modal.pageClass).toBe("preview-page preview-page_modal");
    expect(modal.previewHistoryId).toBe("a0H000000000001AAA");
    expect(modal.hasPreview).toBe(true);
    const tab = bind({
      isTabView: true,
      previewScope: { initialVersion: "2", initialInvoiceId: "inv", contractHistoryId: "h" }
    });
    expect(tab.pageClass).toBe("preview-page preview-page_tab");
    expect(tab.tableInitialVersion).toBe("2");
    expect(tab.tableInitialInvoiceId).toBe("inv");
  });

  it("請求日と入金予定日は必須 (Core 7.9)", async () => {
    const ctx = bind();
    await ctx.handleSaveBillingHeader({ detail: { invoiceId: "inv" } });
    expect(ctx.errorMessage).toBe("請求日は必須です。");
    ctx.errorMessage = "";
    await ctx.handleSaveBillingHeader({
      detail: { invoiceId: "inv", invoiceDate: "2026-04-01" }
    });
    expect(ctx.errorMessage).toBe("入金予定日は必須です。");
  });

  it("save billing header writes 請求情報を保存しました。", async () => {
    const table = { clearBillingEditState: jest.fn() };
    const ctx = bind({
      template: { querySelector: jest.fn(() => table) }
    });
    await ctx.handleSaveBillingHeader({
      detail: {
        invoiceId: "inv",
        invoiceDate: "2026-04-01",
        paymentScheduledDate: "2026-04-30",
        expectedContentVersion: "v1"
      }
    });
    expect(ctx.completionNote).toBe("請求情報を保存しました。");
    expect(table.clearBillingEditState).toHaveBeenCalled();
  });

  it("split requires 分割先の請求日／入金予定日", async () => {
    const ctx = bind();
    await ctx.handleSplitInvoice({
      detail: { sourceInvoiceId: "inv", splitLines: [{}] }
    });
    expect(ctx.errorMessage).toBe("分割先の請求日は必須です。");
    ctx.errorMessage = "";
    await ctx.handleSplitInvoice({
      detail: {
        sourceInvoiceId: "inv",
        splitLines: [{}],
        newInvoiceDate: "2026-05-01"
      }
    });
    expect(ctx.errorMessage).toBe("分割先の入金予定日は必須です。");
  });

  it("split by billing account vs date (Core 7.9)", async () => {
    const ctx = bind();
    await ctx.handleSplitInvoice({
      detail: {
        mode: "billingAccount",
        sourceInvoiceId: "inv",
        newInvoiceDate: "2026-05-01",
        newPaymentScheduledDate: "2026-05-31",
        newBillingAccountId: "ba",
        splitLines: [{ lineId: "1" }]
      }
    });
    expect(splitInvoiceByBillingAccount).toHaveBeenCalled();
    await ctx.handleSplitInvoice({
      detail: {
        sourceInvoiceId: "inv",
        newInvoiceDate: "2026-05-01",
        newPaymentScheduledDate: "2026-05-31",
        splitLines: [{ lineId: "1" }]
      }
    });
    expect(splitInvoiceByDate).toHaveBeenCalled();
  });

  it("line amounts / move / in-place / reset / apply / cancel run edit", async () => {
    const ctx = bind();
    await ctx.handleSaveLineAmounts({
      detail: { edits: [{ lineId: "1" }], expectedTokenByInvoiceId: {} }
    });
    expect(updateInvoiceLineAmounts).toHaveBeenCalled();
    await ctx.handleMoveLines({
      detail: {
        sourceInvoiceId: "a",
        targetInvoiceId: "b",
        lineIds: ["1"]
      }
    });
    expect(moveLinesToExistingInvoice).toHaveBeenCalled();
    await ctx.handleSplitLinesInPlace({
      detail: { invoiceId: "inv", splitLines: [{}] }
    });
    expect(splitLinesInPlace).toHaveBeenCalled();
    await ctx.handleResetPostOrder({ detail: { versionValue: "1" } });
    expect(resetLatestVersionInvoicesToPostOrder).toHaveBeenCalled();
    await ctx.handleApplyBillingAccountContent({ detail: { invoiceId: "inv" } });
    expect(applyBillingAccountContent).toHaveBeenCalled();
    await ctx.handleCancelConfirmed({
      detail: {
        invoiceId: "inv",
        journalPreviewText: "仕訳",
        customerNotice: "通知"
      }
    });
    expect(cancelConfirmedFromPreview).toHaveBeenCalled();
  });

  it("acceptance missing 取消基準日 opens table prompt (Core 7.9)", async () => {
    updateInvoiceLineAcceptanceEndDate.mockRejectedValue({
      body: { message: "取消基準日が必要です。" }
    });
    const table = { showAcceptanceCancelDateRequired: jest.fn() };
    const ctx = bind({
      template: { querySelector: jest.fn(() => table) }
    });
    await ctx.handleSaveAcceptanceEndDate({
      detail: { lineId: "line1", acceptanceEndDate: "2026-03-31" }
    });
    expect(table.showAcceptanceCancelDateRequired).toHaveBeenCalledWith(
      "line1",
      "2026-03-31"
    );
  });

  it("version conflict reloads the board (Core 7.9.7 / 4.3.12)", async () => {
    updateInvoiceLineAmounts.mockRejectedValue({
      body: { message: VERSION_CONFLICT }
    });
    const ctx = bind();
    await ctx.handleSaveLineAmounts({
      detail: { edits: [{ lineId: "1" }] }
    });
    expect(resolvePreviewScope).toHaveBeenCalled();
    expect(ctx.reduceError({ body: { message: VERSION_CONFLICT } })).toBe(
      VERSION_CONFLICT
    );
  });

  it("closes modal vs tab", () => {
    const ctx = bind();
    ctx.handleClose();
    expect(requestOrderWizardClose).toHaveBeenCalled();
    const tab = bind({ isTabView: true });
    tab.closeAction({ refresh: true });
    expect(closeOrderWizardTab).toHaveBeenCalled();
  });

  it("empty edits / ids are no-ops", async () => {
    const ctx = bind();
    await ctx.handleSaveLineAmounts({ detail: {} });
    await ctx.handleSaveAcceptanceEndDate({ detail: {} });
    await ctx.handleSaveBillingHeader({ detail: {} });
    await ctx.handleSplitInvoice({ detail: {} });
    await ctx.handleMoveLines({ detail: {} });
    await ctx.handleSplitLinesInPlace({ detail: {} });
    await ctx.handleResetPostOrder({ detail: {} });
    await ctx.handleApplyBillingAccountContent({ detail: {} });
    await ctx.handleCancelConfirmed({ detail: {} });
    expect(updateInvoiceLineAmounts).not.toHaveBeenCalled();
  });

  it("busy save does not start a second edit (Core 4.3.12)", async () => {
    const ctx = bind({ isSaving: true });
    const ok = await ctx.runEdit(() => updateInvoiceLineAmounts({}));
    expect(ok).toBe(false);
    expect(updateInvoiceLineAmounts).not.toHaveBeenCalled();
  });

  it("wheel helpers skip ctrl and inner listbox (Core 7.7.0)", () => {
    const ctx = bind();
    ctx.handlePreviewWheel(null);
    ctx.handlePreviewWheel({ ctrlKey: true });
    const root = {
      nodeType: 1,
      scrollTop: 0,
      clientHeight: 500,
      scrollHeight: 2000,
      style: {}
    };
    const listbox = document.createElement("div");
    listbox.setAttribute("role", "listbox");
    expect(ctx.isSmallScroller(listbox)).toBe(true);
    expect(ctx.resolveWheelDeltaY({ deltaY: 0, deltaX: 0, shiftKey: false })).toBe(0);
    expect(ctx.resolveWheelDeltaY({ deltaY: 2, deltaMode: 1, shiftKey: false })).toBe(32);
    expect(ctx.canScrollY(null)).toBe(false);
  });

  it("connectedCallback / disconnectedCallback bind resize", () => {
    const add = jest.spyOn(window, "addEventListener");
    const remove = jest.spyOn(window, "removeEventListener");
    const ctx = bind({ _resizeBound: false });
    ctx.connectedCallback();
    expect(ctx._resizeBound).toBe(true);
    ctx.disconnectedCallback();
    expect(ctx._resizeBound).toBe(false);
    add.mockRestore();
    remove.mockRestore();
  });

  it("billingAccount split without account is a no-op", async () => {
    const ctx = bind();
    await ctx.handleSplitInvoice({
      detail: {
        mode: "billingAccount",
        sourceInvoiceId: "inv",
        newInvoiceDate: "2026-05-01",
        newPaymentScheduledDate: "2026-05-31",
        splitLines: [{}]
      }
    });
    expect(splitInvoiceByBillingAccount).not.toHaveBeenCalled();
  });

  it("invoiceopscomplete reloads without dropping preview (Core 7.7.0)", async () => {
    const ctx = bind();
    await ctx.handleInvoiceOpsComplete();
    expect(getInvoicePreview).toHaveBeenCalled();
    expect(ctx.hasPreview).toBe(true);
  });

  it("pageRef sets record id and tab view", () => {
    readOrderWizardRecordId.mockReturnValue("a0HZZZ");
    isOrderWizardTabView.mockReturnValue(true);
    const ctx = bind({ recordId: "" });
    ctx.setCurrentPageReference({ type: "standard__navItemPage" });
    expect(ctx.recordId).toBe("a0HZZZ");
    expect(ctx.isTabView).toBe(true);
  });

  it("applyScrollSizing writes height 100% (Core 7.7.0)", () => {
    const host = {
      style: { setProperty: jest.fn() },
      getBoundingClientRect: () => ({ height: 400, top: 10 })
    };
    const root = {
      style: { setProperty: jest.fn() },
      getBoundingClientRect: () => ({ height: 400, top: 10 })
    };
    const ctx = bind({
      template: { host, querySelector: jest.fn(() => root) }
    });
    ctx.applyScrollSizing();
    expect(host.style.setProperty).toHaveBeenCalledWith("overflow", "hidden");
    expect(ctx.showBootstrapLoading).toBe(false);
  });

  it("canConsumeY and deltaMode 2 (Core 7.7.0)", () => {
    const ctx = bind();
    const el = document.createElement("textarea");
    expect(ctx.isSmallScroller(el)).toBe(true);
    const tall = document.createElement("div");
    Object.defineProperty(tall, "scrollTop", { value: 10, writable: true });
    Object.defineProperty(tall, "clientHeight", { value: 100 });
    Object.defineProperty(tall, "scrollHeight", { value: 400 });
    tall.style.overflowY = "auto";
    expect(ctx.canConsumeY(tall, -5)).toBe(true);
    expect(
      ctx.resolveWheelDeltaY({
        deltaY: 1,
        deltaMode: 2,
        shiftKey: false
      })
    ).toBeGreaterThan(0);
  });
});
