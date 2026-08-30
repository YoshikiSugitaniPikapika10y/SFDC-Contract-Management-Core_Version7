import OrderCreateWizard from "c/orderCreateWizard";
import confirmOrder from "@salesforce/apex/OrderCreateController.confirmOrder";

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

describe("orderCreateWizard cancel billing gate (Core 5.2 / 1.1.10)", () => {
  const proto = OrderCreateWizard.prototype;

  afterEach(() => {
    confirmOrder.mockClear();
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
});
