import OrderRevertWizard from "c/orderRevertWizard";
import getOrderContext from "@salesforce/apex/OrderCreateController.getOrderContext";
import revertOrder from "@salesforce/apex/OrderCreateController.revertOrder";
import issueRevertOperationKey from "@salesforce/apex/OrderCreateController.issueRevertOperationKey";
import {
  closeOrderWizardTab,
  isOrderWizardTabView,
  readOrderWizardRecordId
} from "c/orderWizardNavigation";
import {
  notifyOrderRecordStatusChanged,
  requestOrderWizardClose
} from "c/orderWizardClose";
import { resolveSaveErrorAlert } from "c/estimateValidationAlertUtils";
import { buildCustomFieldInputs } from "c/estimateWizardCustomFields";

jest.mock(
  "@salesforce/customPermission/Loop_07_Can_Revert",
  () => ({ __esModule: true, default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.getOrderContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.revertOrder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.issueRevertOperationKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/navigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {},
    CurrentPageReference: class CurrentPageReference {}
  }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardNavigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {},
    closeOrderWizardTab: jest.fn(),
    initializeOrderWizardFromUrl: jest.fn(),
    isOrderWizardTabView: jest.fn(() => false),
    readOrderWizardRecordId: jest.fn(() => null)
  }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardClose",
  () => ({
    HISTORY_STATUS_ARCHIVE: "Archive",
    isOrderActionBootstrapping: (component) => component.isLoading === true,
    notifyOrderRecordStatusChanged: jest.fn(),
    requestOrderWizardClose: jest.fn(),
    scheduleRecordActionLoad: jest.fn(),
    resetRecordActionLoadState: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "c/estimateValidationAlertUtils",
  () => ({ resolveSaveErrorAlert: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/estimateWizardCustomFields",
  () => ({ buildCustomFieldInputs: jest.fn(() => []) }),
  { virtual: true }
);

const VERSION_CONFLICT_MESSAGE =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";

const proto = OrderRevertWizard.prototype;

const ORDERED = {
  historyStatus: "Ordered",
  isOrdered: true,
  canRevert: true,
  hasRenewOpportunity: true,
  lastModifiedToken: "tok",
  historySavedFields: { OrderDate__c: "2026-01-15", Extra__c: "残す" },
  historyFieldDefinitions: [
    { apiName: "OrderDate__c", label: "受注日", required: true },
    { apiName: "Extra__c", label: "追加A", required: true },
    null
  ],
  historyType: "New",
  hasManualAdjustment: false,
  revertBlockedReason: ""
};

function bind(overrides = {}) {
  const ctx = {
    recordId: "a0H000000000001AAA",
    pendingRecordRefresh: undefined,
    isTabView: false,
    isLoading: false,
    isSaving: false,
    errorMessage: "",
    contentLoadFailed: false,
    context: ORDERED,
    hasManualAdjustment: false,
    deleteRenewOpportunity: true,
    historyCustomFields: { OrderDate__c: "2026-01-15" },
    _lastModifiedToken: "tok",
    _pendingOperationKey: "",
    ...overrides
  };
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor") {
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

describe("orderRevertWizard uncovered (Core 5.3 / 4.3.12 / 11.4.3)", () => {
  beforeEach(() => {
    getOrderContext.mockReset().mockResolvedValue(ORDERED);
    revertOrder.mockReset().mockResolvedValue({});
    issueRevertOperationKey.mockReset().mockResolvedValue("op-key-1");
    resolveSaveErrorAlert.mockReset().mockReturnValue({
      messages: [{ text: "失敗" }]
    });
    buildCustomFieldInputs.mockReset().mockImplementation((definitions) =>
      (definitions || []).map((field) => ({ ...field, key: field.apiName }))
    );
    closeOrderWizardTab.mockClear();
    requestOrderWizardClose.mockClear();
    notifyOrderRecordStatusChanged.mockClear();
    isOrderWizardTabView.mockReset().mockReturnValue(false);
    readOrderWizardRecordId.mockReset().mockReturnValue(null);
  });

  it("pageClass switches tab and modal shells", () => {
    expect(bind({ isTabView: true }).pageClass).toContain("revert-page_tab");
    expect(bind({ isTabView: false }).pageClass).toContain("revert-page_modal");
  });

  it("wire sets recordId from URL and tab flag", () => {
    readOrderWizardRecordId.mockReturnValue("a0H000000000099AAA");
    isOrderWizardTabView.mockReturnValue(true);
    const ctx = bind({ recordId: "" });
    ctx.setCurrentPageReference({ type: "standard__recordPage" });
    expect(ctx.recordId).toBe("a0H000000000099AAA");
    expect(ctx.isTabView).toBe(true);
  });

  it("empty recordId loadContext is a no-op", async () => {
    const ctx = bind({ recordId: "" });
    await ctx.loadContext();
    expect(getOrderContext).not.toHaveBeenCalled();
  });

  it("Archive history cannot revert (Core 5.3)", async () => {
    getOrderContext.mockResolvedValue({
      historyStatus: "Archive",
      isOrdered: false
    });
    const ctx = bind({ context: undefined });
    await ctx.loadContext();
    expect(ctx.errorMessage).toBe(
      "アーカイブ済みの契約履歴では差し戻しは利用できません。"
    );
    expect(ctx.context).toBeUndefined();
    expect(ctx.isLoading).toBe(false);
  });

  it("Estimate history directs to 受注 (Core 5.3)", async () => {
    getOrderContext.mockResolvedValue({
      historyStatus: "Estimate",
      isOrdered: false
    });
    const ctx = bind({ context: undefined });
    await ctx.loadContext();
    expect(ctx.errorMessage).toBe(
      "見積状態の契約履歴です。「受注」ボタンをご利用ください。"
    );
  });

  it("Ordered context loads fields and renew delete default ON (Core 5.3 / 5.6)", async () => {
    getOrderContext.mockResolvedValue({
      ...ORDERED,
      hasManualAdjustment: true,
      deleteRenewOpportunity: false
    });
    const ctx = bind({
      context: undefined,
      deleteRenewOpportunity: false,
      hasManualAdjustment: false
    });
    await ctx.loadContext();
    expect(ctx.context).toEqual(
      expect.objectContaining({ canRevert: true, isOrdered: true })
    );
    expect(ctx.deleteRenewOpportunity).toBe(true);
    expect(ctx.hasManualAdjustment).toBe(true);
    expect(ctx._lastModifiedToken).toBe("tok");
    expect(ctx.historyCustomFields).toEqual(ORDERED.historySavedFields);
  });

  it("loadContext error sets contentLoadFailed (Core 4.3.11)", async () => {
    getOrderContext.mockRejectedValue(new Error("x"));
    resolveSaveErrorAlert.mockReturnValue({
      messages: [{ text: "照会失敗" }]
    });
    const ctx = bind({ context: undefined });
    await ctx.loadContext();
    expect(ctx.errorMessage).toBe("照会失敗");
    expect(ctx.contentLoadFailed).toBe(true);
    expect(ctx.isLoading).toBe(false);
  });

  it("handleContentReload reloads", async () => {
    const ctx = bind();
    const spy = jest.spyOn(ctx, "loadContext").mockResolvedValue();
    ctx.handleContentReload();
    expect(spy).toHaveBeenCalled();
  });

  it("canRevert / blocked notice / renew / busy getters (Core 5.3)", () => {
    const ok = bind();
    expect(ok.canRevert).toBe(true);
    expect(ok.hasRenewOpportunity).toBe(true);
    expect(ok.hasContext).toBe(true);
    expect(ok.showRevertBlockedNotice).toBe(false);
    expect(ok.isBusy).toBe(false);
    expect(ok.isRevertDisabled).toBe(false);
    expect(ok.canOpenRevert).toBe(true);

    const blocked = bind({
      context: {
        ...ORDERED,
        canRevert: false,
        revertBlockedReason: "後続Estimateあり"
      }
    });
    expect(blocked.canRevert).toBe(false);
    expect(blocked.revertBlockedReason).toBe("後続Estimateあり");
    expect(blocked.showRevertBlockedNotice).toBe(true);
    expect(blocked.isRevertDisabled).toBe(true);
  });

  it("manual adjustment notice only when can revert (Core 5.3)", () => {
    expect(
      bind({ hasManualAdjustment: true, context: { ...ORDERED, canRevert: true } })
        .showManualAdjustmentNotice
    ).toBe(true);
    expect(
      bind({
        hasManualAdjustment: true,
        context: { ...ORDERED, canRevert: false }
      }).showManualAdjustmentNotice
    ).toBe(false);
  });

  it("showBootstrapLoading follows loading", () => {
    expect(bind({ isLoading: true }).showBootstrapLoading).toBe(true);
    expect(bind({ isLoading: false }).showBootstrapLoading).toBe(false);
  });

  it("差し戻し追加項目は必須を見ない (Core 5.3 / 11.4.3)", () => {
    const ctx = bind();
    const defs = ctx.revertHistoryFieldDefinitions;
    expect(defs.map((f) => f.apiName)).toEqual(["OrderDate__c", "Extra__c"]);
    expect(defs.every((f) => f.required === false)).toBe(true);
    expect(ctx.showHistoryFields).toBe(true);
    expect(buildCustomFieldInputs).toHaveBeenCalled();
  });

  it("handleDeleteRenewOpportunityChange", () => {
    const ctx = bind({ deleteRenewOpportunity: true });
    ctx.handleDeleteRenewOpportunityChange({ target: { checked: false } });
    expect(ctx.deleteRenewOpportunity).toBe(false);
  });

  it("history field change ignored when busy or missing api", () => {
    const busy = bind({ isSaving: true, historyCustomFields: { A: "1" } });
    busy.handleHistoryFieldChange({ detail: { fieldApi: "A", value: "2" } });
    expect(busy.historyCustomFields.A).toBe("1");

    const missing = bind();
    missing.handleHistoryFieldChange({ detail: {} });
    expect(missing.historyCustomFields).toEqual({ OrderDate__c: "2026-01-15" });
  });

  it("history field change updates draft", () => {
    const ctx = bind();
    ctx.handleHistoryFieldChange({
      detail: { fieldApi: "Extra__c", value: "新" }
    });
    expect(ctx.historyCustomFields.Extra__c).toBe("新");
  });

  it("差し戻し成功は更新商談削除フラグと操作キーを渡し閉じる (Core 5.3 / 4.3.12)", async () => {
    revertOrder.mockResolvedValue({ businessOperationKey: "echo" });
    const ctx = bind({
      deleteRenewOpportunity: true,
      _pendingOperationKey: "",
      historyCustomFields: { Extra__c: "x" }
    });
    const closeSpy = jest.spyOn(ctx, "closeAction").mockImplementation(() => {});
    await ctx.handleRevert();
    expect(issueRevertOperationKey).toHaveBeenCalled();
    expect(revertOrder).toHaveBeenCalledWith({
      contractHistoryId: "a0H000000000001AAA",
      deleteRenewOpportunity: true,
      expectedLastModifiedToken: "tok",
      historyCustomFieldsJson: JSON.stringify({ Extra__c: "x" }),
      businessOperationKey: "op-key-1"
    });
    expect(notifyOrderRecordStatusChanged).toHaveBeenCalledWith(
      ctx,
      "a0H000000000001AAA"
    );
    expect(closeSpy).toHaveBeenCalled();
    expect(ctx._pendingOperationKey).toBe("");
    expect(ctx.isSaving).toBe(false);
  });

  it("reuses pending key and skips renew delete when unchecked", async () => {
    const ctx = bind({
      _pendingOperationKey: "keep",
      deleteRenewOpportunity: false
    });
    jest.spyOn(ctx, "closeAction").mockImplementation(() => {});
    await ctx.handleRevert();
    expect(issueRevertOperationKey).not.toHaveBeenCalled();
    expect(revertOrder).toHaveBeenCalledWith(
      expect.objectContaining({
        businessOperationKey: "keep",
        deleteRenewOpportunity: false
      })
    );
  });

  it("disabled or saving revert does nothing", async () => {
    await bind({
      context: { ...ORDERED, canRevert: false }
    }).handleRevert();
    expect(revertOrder).not.toHaveBeenCalled();
    await bind({ isSaving: true }).handleRevert();
    expect(revertOrder).not.toHaveBeenCalled();
  });

  it("版比較失敗はキーを捨てて読み直す (Core 4.3.12)", async () => {
    revertOrder.mockRejectedValue(new Error("conflict"));
    resolveSaveErrorAlert.mockReturnValue({
      messages: [{ text: VERSION_CONFLICT_MESSAGE }]
    });
    const ctx = bind({ _pendingOperationKey: "old" });
    const loadSpy = jest.spyOn(ctx, "loadContext").mockResolvedValue();
    await ctx.handleRevert();
    expect(ctx.errorMessage).toBe(VERSION_CONFLICT_MESSAGE);
    expect(ctx._pendingOperationKey).toBe("");
    expect(loadSpy).toHaveBeenCalled();
    expect(ctx.isSaving).toBe(false);
  });

  it("non-version revert error keeps message", async () => {
    revertOrder.mockRejectedValue(new Error("denied"));
    resolveSaveErrorAlert.mockReturnValue({
      messages: [{ text: "差し戻し不可" }]
    });
    const ctx = bind();
    await ctx.handleRevert();
    expect(ctx.errorMessage).toBe("差し戻し不可");
    expect(notifyOrderRecordStatusChanged).not.toHaveBeenCalled();
  });

  it("handleClose closes without refresh", () => {
    const ctx = bind();
    ctx.handleClose();
    expect(requestOrderWizardClose).toHaveBeenCalledWith(ctx, {
      refresh: false,
      recordId: "a0H000000000001AAA"
    });
  });

  it("closeAction uses tab close when tab view", () => {
    const ctx = bind({ isTabView: true });
    ctx.closeAction({ refresh: true });
    expect(closeOrderWizardTab).toHaveBeenCalledWith(ctx, {
      recordId: "a0H000000000001AAA",
      refresh: true
    });
    expect(requestOrderWizardClose).not.toHaveBeenCalled();
  });

  it("closeAction defaults refresh true for modal", () => {
    const ctx = bind({ isTabView: false });
    ctx.closeAction();
    expect(requestOrderWizardClose).toHaveBeenCalledWith(ctx, {
      refresh: true,
      recordId: "a0H000000000001AAA"
    });
  });
});
