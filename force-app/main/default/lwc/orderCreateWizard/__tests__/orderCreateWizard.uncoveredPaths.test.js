import OrderCreateWizard from "c/orderCreateWizard";
import confirmOrder from "@salesforce/apex/OrderCreateController.confirmOrder";
import getOrderContext from "@salesforce/apex/OrderCreateController.getOrderContext";
import issueOrderOperationKey from "@salesforce/apex/OrderCreateController.issueOrderOperationKey";
import {
  isMissingRequiredCustomValue,
  buildCustomFieldInputs
} from "c/estimateWizardCustomFields";
import {
  notifyOrderRecordStatusChanged,
  requestOrderWizardClose,
  isOrderActionBootstrapping
} from "c/orderWizardClose";
import { closeOrderWizardTab } from "c/orderWizardNavigation";

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
  "lightning/uiRecordApi",
  () => ({
    getRecord: jest.fn(),
    getRecordNotifyChange: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "lightning/uiObjectInfoApi",
  () => ({ getObjectInfo: jest.fn() }),
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
  "@salesforce/apex/OrderCreateController.getOrderContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.confirmOrder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.issueOrderOperationKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_06_Can_Order",
  () => ({ default: true }),
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
    HISTORY_STATUS_ARCHIVE: "Archive",
    isOrderActionBootstrapping: jest.fn(() => false),
    notifyOrderRecordStatusChanged: jest.fn(),
    requestOrderWizardClose: jest.fn(),
    scheduleRecordActionLoad: jest.fn((ctx, fn) => {
      if (typeof fn === "function") {
        return fn();
      }
      return undefined;
    }),
    resetRecordActionLoadState: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "c/estimateWizardCustomFields",
  () => ({
    applyDefaultCustomFields: jest.fn((fields) => fields || {}),
    buildCustomFieldInputs: jest.fn(() => []),
    isMissingRequiredCustomValue: jest.fn(() => false)
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

const proto = OrderCreateWizard.prototype;
const VERSION_CONFLICT =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";

function bind(overrides = {}) {
  const ctx = {
    recordId: "a0H000000000001AAA",
    _recordId: "a0H000000000001AAA",
    isTabView: false,
    fromCrossWork: false,
    isLoading: false,
    isSaving: false,
    errorMessage: "",
    contentLoadFailed: false,
    context: {
      canOrder: true,
      billingAccountId: "a00BA",
      historyType: "New",
      showCreateRenewOpportunity: true,
      lastModifiedToken: "tok1"
    },
    billingCustomFields: {},
    historyCustomFields: {},
    historyFieldDefinitions: [],
    createRenewOpportunity: true,
    _lastModifiedToken: "tok1",
    _pendingOperationKey: "",
    _recordActionMissingHandled: false,
    dispatchEvent: jest.fn(),
    template: {
      querySelector: jest.fn(() => null),
      querySelectorAll: jest.fn(() => [])
    },
    ...overrides
  };
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor") {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (!desc) {
      return;
    }
    if (desc.get && desc.set) {
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

describe("orderCreateWizard uncovered paths (Core 5.1 / 5.2 / 4.3.12)", () => {
  beforeEach(() => {
    getOrderContext.mockReset().mockResolvedValue({
      canOrder: true,
      billingAccountId: "a00BA",
      historyType: "New",
      showCreateRenewOpportunity: true,
      lastModifiedToken: "tok",
      historyFieldDefinitions: [],
      historyCustomFields: {},
      billingCustomFields: {}
    });
    confirmOrder.mockReset().mockResolvedValue({ businessOperationKey: "op1" });
    issueOrderOperationKey.mockReset().mockResolvedValue("op-key");
    isMissingRequiredCustomValue.mockReset().mockReturnValue(false);
    buildCustomFieldInputs.mockReset().mockReturnValue([]);
    isOrderActionBootstrapping.mockReturnValue(false);
    requestOrderWizardClose.mockClear();
    closeOrderWizardTab.mockClear();
    notifyOrderRecordStatusChanged.mockClear();
  });

  it("connectedCallback / renderedCallback schedule load (Core 5.2)", () => {
    const ctx = bind();
    ctx.connectedCallback();
    ctx.renderedCallback();
    expect(getOrderContext).toHaveBeenCalled();
  });

  it("large panel title copy is 請求設定の確認と受注 (Core 5.2)", () => {
    const ctx = bind();
    expect(ctx.isCancelConfirm).toBe(false);
    expect(ctx.panelSize).toBe("large");
    expect(ctx.showBillingStep).toBe(true);
    expect(ctx.showCreateRenewOpportunity).toBe(true);
  });

  it("Cancel copy lists 請求・契約期間明細は作成されません (Core 5.2)", () => {
    const ctx = bind({
      context: {
        canOrder: true,
        historyType: "Cancel",
        showCreateRenewOpportunity: false,
        billingAccountId: "a00BA"
      }
    });
    expect(ctx.isCancel).toBe(true);
    expect(ctx.isCancelConfirm).toBe(false);
    expect(ctx.showBillingStep).toBe(false);
    expect(ctx.showCreateRenewOpportunity).toBe(false);
    expect(ctx.panelSize).toBe("large");
  });

  it("required history fields block with 必須のカスタム項目を入力してください (Core 11.4.3)", async () => {
    const definitions = [
      {
        apiName: "ApplicationDate__c",
        label: "申込日",
        required: true,
        showOnNew: true
      }
    ];
    buildCustomFieldInputs.mockReturnValue([
      { apiName: "ApplicationDate__c", label: "申込日", required: true }
    ]);
    isMissingRequiredCustomValue.mockImplementation(
      (value) => value == null || String(value).trim() === ""
    );
    const ctx = bind({
      historyFieldDefinitions: definitions,
      historyCustomFields: { ApplicationDate__c: "" }
    });
    await ctx.handleConfirmOrder();
    expect(buildCustomFieldInputs).toHaveBeenCalledWith(
      definitions,
      { ApplicationDate__c: "" },
      "order-history",
      false,
      null,
      "New"
    );
    expect(ctx.errorMessage).toBe(
      "必須のカスタム項目を入力してください: 申込日"
    );
    expect(confirmOrder).not.toHaveBeenCalled();
  });

  it("confirm issues operation key then closes (Core 4.3.12 / 5.2)", async () => {
    const ctx = bind();
    await ctx.handleConfirmOrder();
    expect(issueOrderOperationKey).toHaveBeenCalledTimes(1);
    expect(confirmOrder).toHaveBeenCalledWith({
      contractHistoryId: "a0H000000000001AAA",
      billingCustomFieldsJson: null,
      createRenewOpportunity: true,
      expectedLastModifiedToken: "tok1",
      historyCustomFieldsJson: "{}",
      businessOperationKey: "op-key"
    });
    expect(issueOrderOperationKey.mock.invocationCallOrder[0]).toBeLessThan(
      confirmOrder.mock.invocationCallOrder[0]
    );
    expect(notifyOrderRecordStatusChanged).toHaveBeenCalledWith(
      ctx,
      "a0H000000000001AAA"
    );
    expect(requestOrderWizardClose).toHaveBeenCalledWith(ctx, {
      refresh: true,
      recordId: "a0H000000000001AAA"
    });
    expect(confirmOrder.mock.invocationCallOrder[0]).toBeLessThan(
      notifyOrderRecordStatusChanged.mock.invocationCallOrder[0]
    );
    expect(
      notifyOrderRecordStatusChanged.mock.invocationCallOrder[0]
    ).toBeLessThan(requestOrderWizardClose.mock.invocationCallOrder[0]);
  });

  it("version conflict reloads with 他のユーザーが先に更新しました (Core 4.3.12)", async () => {
    confirmOrder.mockRejectedValue({
      body: {
        message: VERSION_CONFLICT
      }
    });
    getOrderContext.mockResolvedValue({
      canOrder: true,
      billingAccountId: "a00BA",
      historyType: "New",
      showCreateRenewOpportunity: true,
      lastModifiedToken: "tok2",
      historyFieldDefinitions: [],
      historyCustomFields: {},
      billingCustomFields: {}
    });
    const ctx = bind();
    await ctx.handleConfirmOrder();
    expect(ctx.reduceError({ body: { message: VERSION_CONFLICT } })).toBe(
      VERSION_CONFLICT
    );
    expect(getOrderContext).toHaveBeenCalled();
    expect(ctx.contentLoadFailed).toBe(false);
  });

  it("loadContext failure shows 再読み込み (Core 4.3.11)", async () => {
    getOrderContext.mockRejectedValue({ body: { message: "timeout" } });
    const ctx = bind({ context: undefined });
    await ctx.loadContext();
    expect(ctx.contentLoadFailed).toBe(true);
    expect(ctx.errorMessage).toBe("timeout");
    getOrderContext.mockResolvedValue({
      canOrder: true,
      billingAccountId: "a00BA",
      historyType: "New",
      lastModifiedToken: "t",
      historyFieldDefinitions: [],
      historyCustomFields: {},
      billingCustomFields: {}
    });
    ctx.handleContentReload();
    await Promise.resolve();
  });

  it("renew checkbox writes createRenewOpportunity (Core 5.2)", () => {
    const ctx = bind();
    ctx.handleCreateRenewOpportunityChange({ target: { checked: false } });
    expect(ctx.createRenewOpportunity).toBe(false);
    ctx.isSaving = true;
    ctx.handleCreateRenewOpportunityChange({ target: { checked: true } });
    expect(ctx.createRenewOpportunity).toBe(false);
  });

  it("history field change writes custom field", () => {
    const ctx = bind();
    ctx.handleHistoryFieldChange({
      detail: { fieldApi: "AppDate__c", value: "2026-04-01" }
    });
    expect(ctx.historyCustomFields.AppDate__c).toBe("2026-04-01");
    ctx.handleHistoryFieldChange({ detail: {} });
    ctx.isSaving = true;
    ctx.handleHistoryFieldChange({
      detail: { fieldApi: "OrderDate__c", value: "x" }
    });
    expect(ctx.historyCustomFields.AppDate__c).toBe("2026-04-01");
  });

  it("closes with 閉じる when not busy; tab view uses tab close", () => {
    const ctx = bind();
    ctx.handleClose();
    expect(requestOrderWizardClose).toHaveBeenCalledWith(ctx, {
      refresh: false,
      recordId: "a0H000000000001AAA"
    });
    const tab = bind({ isTabView: true });
    tab.closeAction({ refresh: true });
    expect(closeOrderWizardTab).toHaveBeenCalledWith(tab, {
      recordId: "a0H000000000001AAA",
      refresh: true
    });
    expect(tab.pageClass).toBe("ord-page ord-page_tab");
    expect(tab.cancelPageClass).toContain("cancel-page_tab");
  });

  it("横断の見積書タイルでは契約履歴へ遷移しない (横断画面.md 第2.1節)", () => {
    requestOrderWizardClose.mockClear();
    closeOrderWizardTab.mockClear();
    const ctx = bind({ fromCrossWork: true, isTabView: true });
    ctx.closeAction({ refresh: true });
    expect(closeOrderWizardTab).not.toHaveBeenCalled();
    expect(requestOrderWizardClose).not.toHaveBeenCalled();
    expect(ctx.dispatchEvent).toHaveBeenCalled();
  });

  it("validateBillingStep and guide use billing child (Core 5.2)", () => {
    const billing = {
      validateBillingFields: jest.fn(() => "宛名不足"),
      openBillingAccountFormalEdit: jest.fn()
    };
    const ctx = bind({
      template: { querySelector: jest.fn(() => billing) }
    });
    expect(ctx.validateBillingStep()).toBe("宛名不足");
    ctx.guideToBillingAccountFormalEdit();
    expect(billing.openBillingAccountFormalEdit).toHaveBeenCalled();
  });

  it("pageRef sets tab view and record id", () => {
    const { readOrderWizardRecordId, isOrderWizardTabView } = require("c/orderWizardNavigation");
    readOrderWizardRecordId.mockReturnValue("a0HZZZ");
    isOrderWizardTabView.mockReturnValue(true);
    const ctx = bind({ recordId: "", _recordId: "" });
    ctx.setCurrentPageReference({ type: "standard__navItemPage" });
    expect(ctx._recordId).toBe("a0HZZZ");
    expect(ctx.isTabView).toBe(true);
  });

  it("empty recordId on loadContext is a no-op", async () => {
    const ctx = bind({ recordId: "", _recordId: "" });
    await ctx.loadContext();
    expect(getOrderContext).not.toHaveBeenCalled();
  });

  it("archive and ordered refuse with Core 5.1 copy", async () => {
    getOrderContext.mockResolvedValueOnce({ historyStatus: "Archive" });
    const archive = bind();
    await archive.loadContext();
    expect(archive.errorMessage).toBe(
      "アーカイブ済みの契約履歴では受注は利用できません。"
    );
    getOrderContext.mockResolvedValueOnce({ isOrdered: true });
    const ordered = bind();
    await ordered.loadContext();
    expect(ordered.errorMessage).toBe(
      "受注済みの契約履歴です。「請求ボード」「差し戻し」ボタンをご利用ください。"
    );
  });

  it("billing validation guides to formal edit (Core 5.2)", async () => {
    const billing = {
      validateBillingFields: jest.fn(() => "宛名不足"),
      openBillingAccountFormalEdit: jest.fn()
    };
    const ctx = bind({
      template: { querySelector: jest.fn(() => billing) }
    });
    await ctx.handleConfirmOrder();
    expect(ctx.errorMessage).toBe("宛名不足");
    expect(billing.openBillingAccountFormalEdit).toHaveBeenCalled();
    expect(confirmOrder).not.toHaveBeenCalled();
  });

  it("does not confirm when canOrder is false (Core 5.1)", async () => {
    const ctx = bind({
      context: { canOrder: false, billingAccountId: "a00BA" }
    });
    await ctx.handleConfirmOrder();
    expect(confirmOrder).not.toHaveBeenCalled();
  });

  it("reuses pending operation key (Core 4.3.12)", async () => {
    const ctx = bind({ _pendingOperationKey: "kept" });
    await ctx.handleConfirmOrder();
    expect(issueOrderOperationKey).not.toHaveBeenCalled();
    expect(confirmOrder).toHaveBeenCalled();
  });

  it("busy close is a no-op (Core 4.3.12)", () => {
    const ctx = bind({ isSaving: true });
    ctx.handleClose();
    expect(requestOrderWizardClose).not.toHaveBeenCalled();
  });

  it("recordId setter ignores same value then accepts a new id", () => {
    getOrderContext.mockResolvedValue({
      canOrder: true,
      billingAccountId: "a00BA",
      historyType: "New",
      lastModifiedToken: "t",
      historyFieldDefinitions: [],
      historyCustomFields: {},
      billingCustomFields: {}
    });
    const ctx = bind({ recordId: "a0H000000000001AAA" });
    proto.connectedCallback.call(ctx);
    expect(getOrderContext).toHaveBeenCalled();
  });

  it("showHistoryFields and isOrderDisabled follow inputs", () => {
    const definitions = [
      {
        apiName: "X__c",
        label: "追加項目X",
        showOnNew: true
      }
    ];
    const inputs = [{ apiName: "X__c", label: "追加項目X" }];
    buildCustomFieldInputs.mockReturnValue(inputs);
    const ctx = bind({
      historyFieldDefinitions: definitions,
      historyCustomFields: { X__c: "表示値" }
    });
    expect(ctx.historyFieldInputs).toEqual(inputs);
    expect(buildCustomFieldInputs).toHaveBeenCalledWith(
      definitions,
      { X__c: "表示値" },
      "order-history",
      false,
      null,
      "New"
    );
    expect(ctx.showHistoryFields).toBe(true);
    expect(ctx.isOrderDisabled).toBe(false);
    ctx.isSaving = true;
    expect(ctx.isOrderDisabled).toBe(true);
    expect(ctx.showMissingRecordError).toBe(false);
  });

  it("optional history fields do not block confirm", async () => {
    buildCustomFieldInputs.mockReturnValue([
      { apiName: "Note__c", label: "メモ", required: false }
    ]);
    const ctx = bind();
    expect(ctx.showBootstrapLoading).toBe(false);
    await ctx.handleConfirmOrder();
    expect(confirmOrder).toHaveBeenCalled();
  });
});
