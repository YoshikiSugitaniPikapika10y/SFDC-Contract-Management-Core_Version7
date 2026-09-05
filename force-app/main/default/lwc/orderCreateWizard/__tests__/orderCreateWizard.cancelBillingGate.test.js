import OrderCreateWizard from "c/orderCreateWizard";
import confirmOrder from "@salesforce/apex/OrderCreateController.confirmOrder";
import getOrderContext from "@salesforce/apex/OrderCreateController.getOrderContext";
import issueOrderOperationKey from "@salesforce/apex/OrderCreateController.issueOrderOperationKey";
import { handleMissingRecordActionId } from "c/orderWizardClose";

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
  () => ({ getRecordNotifyChange: jest.fn() }),
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
  "c/estimateWizardCustomFields",
  () => ({
    applyDefaultCustomFields: jest.fn((fields) => fields || {}),
    buildCustomFieldInputs: jest.fn(() => []),
    isMissingRequiredCustomValue: jest.fn(() => false)
  }),
  { virtual: true }
);

describe("orderCreateWizard cancel billing gate (Core 5.2 / 1.1.10)", () => {
  const proto = OrderCreateWizard.prototype;

  afterEach(() => {
    confirmOrder.mockClear();
    getOrderContext.mockReset();
    issueOrderOperationKey.mockReset();
  });

  it("Cancel受注も請求アカウント必須不足を画面で止める", async () => {
    const missing =
      "請求アカウントの必須項目が未設定です。請求アカウントの正規編集画面で設定してください: 宛名";
    const ctx = {
      isSaving: false,
      canOrder: true,
      hasBillingAccount: true,
      isCancel: true,
      validateHistoryFields: () => null,
      validateBillingStep: () => missing,
      guideToBillingAccountFormalEdit: jest.fn(),
      showToast: jest.fn()
    };
    await proto.handleConfirmOrder.call(ctx);
    expect(ctx.showToast).toHaveBeenCalledWith("入力エラー", missing, "error");
    expect(ctx.guideToBillingAccountFormalEdit).toHaveBeenCalled();
    expect(confirmOrder).not.toHaveBeenCalled();
  });

  it("does not confirm without a billing account (Core 5.1 / 5.2)", async () => {
    const ctx = {
      isSaving: false,
      canOrder: true,
      hasBillingAccount: false,
      errorMessage: "",
      showToast: jest.fn()
    };
    await proto.handleConfirmOrder.call(ctx);
    expect(ctx.errorMessage).toBe(
      "請求アカウントが未設定のため受注できません。見積で請求アカウントを設定してください。"
    );
    expect(confirmOrder).not.toHaveBeenCalled();
  });

  it("Cancel uses confirm size and hides billing and renew-opportunity (Core 5.2)", () => {
    const isCancel = Object.getOwnPropertyDescriptor(proto, "isCancel").get;
    const showBilling = Object.getOwnPropertyDescriptor(
      proto,
      "showBillingStep"
    ).get;
    const panelSize = Object.getOwnPropertyDescriptor(proto, "panelSize").get;
    const showRenew = Object.getOwnPropertyDescriptor(
      proto,
      "showCreateRenewOpportunity"
    ).get;

    const cancel = {
      context: {
        historyType: "Cancel",
        showCreateRenewOpportunity: false
      },
      hasContext: true,
      isCancel: true,
      isCancelConfirm: true
    };
    expect(isCancel.call(cancel)).toBe(true);
    expect(showBilling.call(cancel)).toBe(false);
    expect(panelSize.call(cancel)).toBe("confirm");
    expect(showRenew.call(cancel)).toBe(false);

    const termNew = {
      context: {
        historyType: "New",
        showCreateRenewOpportunity: true
      },
      hasContext: true,
      isCancel: false,
      isCancelConfirm: false
    };
    expect(showBilling.call(termNew)).toBe(true);
    expect(panelSize.call(termNew)).toBe("large");
    expect(showRenew.call(termNew)).toBe(true);
  });

  it("refuses Archive and Ordered on open (Core 5.1 / 5.2)", async () => {
    const archive = {
      recordId: "a0H000000000001AAA",
      emitPanelSize: jest.fn(),
      template: { querySelector: () => null }
    };
    getOrderContext.mockResolvedValueOnce({ historyStatus: "Archive" });
    await proto.loadContext.call(archive);
    expect(archive.errorMessage).toBe(
      "アーカイブ済みの契約履歴では受注は利用できません。"
    );
    expect(archive.context).toBeUndefined();

    const ordered = {
      recordId: "a0H000000000002AAA",
      emitPanelSize: jest.fn(),
      template: { querySelector: () => null }
    };
    getOrderContext.mockResolvedValueOnce({ isOrdered: true });
    await proto.loadContext.call(ordered);
    expect(ordered.errorMessage).toBe(
      "受注済みの契約履歴です。「請求ボード」「差し戻し」ボタンをご利用ください。"
    );
    expect(ordered.context).toBeUndefined();
  });

  it("turns renew-opportunity on only when the context offers it (Core 5.2)", async () => {
    const on = {
      recordId: "a0H000000000003AAA",
      emitPanelSize: jest.fn(),
      template: { querySelector: () => null },
      createRenewOpportunity: false
    };
    getOrderContext.mockResolvedValueOnce({
      historyType: "Renew",
      showCreateRenewOpportunity: true,
      lastModifiedToken: "tok",
      historyFieldDefinitions: [],
      historyCustomFields: {},
      billingCustomFields: {}
    });
    await proto.loadContext.call(on);
    expect(on.createRenewOpportunity).toBe(true);

    const off = {
      recordId: "a0H000000000004AAA",
      emitPanelSize: jest.fn(),
      template: { querySelector: () => null },
      createRenewOpportunity: true
    };
    getOrderContext.mockResolvedValueOnce({
      historyType: "Cancel",
      showCreateRenewOpportunity: false,
      lastModifiedToken: "tok",
      historyFieldDefinitions: [],
      historyCustomFields: {},
      billingCustomFields: {}
    });
    await proto.loadContext.call(off);
    expect(off.createRenewOpportunity).toBe(false);
  });

  it("受注処理中は閉じない (Core 5.2 / 4.3.12)", () => {
    const ctx = {
      isBusy: true,
      closeAction: jest.fn()
    };
    proto.handleClose.call(ctx);
    expect(ctx.closeAction).not.toHaveBeenCalled();
  });

  it("empty recordId uses 指定されていません (Core 5.2)", () => {
    const showMissing = Object.getOwnPropertyDescriptor(
      proto,
      "showMissingRecordError"
    ).get;
    expect(
      showMissing.call({
        recordId: "",
        _recordActionMissingHandled: true
      })
    ).toBe(true);
    const ctx = {
      recordId: "",
      errorMessage: "",
      isLoading: true
    };
    handleMissingRecordActionId(ctx);
    expect(ctx.errorMessage).toBe("契約履歴IDが指定されていません。");
    expect(ctx.isLoading).toBe(false);
  });
});
