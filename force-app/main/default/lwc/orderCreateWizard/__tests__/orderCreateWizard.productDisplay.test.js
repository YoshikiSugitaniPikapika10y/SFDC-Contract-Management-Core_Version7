import OrderCreateWizard from "c/orderCreateWizard";

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
  () => {
    class GetRecordAdapter {}
    return {
      getRecord: GetRecordAdapter,
      getRecordNotifyChange: jest.fn()
    };
  },
  { virtual: true }
);
jest.mock(
  "lightning/uiObjectInfoApi",
  () => {
    class GetObjectInfoAdapter {}
    return { getObjectInfo: GetObjectInfoAdapter };
  },
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
    buildCustomFieldInputs: jest.fn(() => [{ key: "display" }]),
    isMissingRequiredCustomValue: jest.fn(() => false)
  }),
  { virtual: true }
);

function bind(overrides = {}) {
  const ctx = {
    context: {
      productFieldDefinitions: [{ label: "成約パートナー①", apiName: null }],
      products: [{ productName: "A商品" }],
      historyType: "New"
    },
    ...overrides
  };
  const proto = OrderCreateWizard.prototype;
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor") {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (desc?.get && !desc.set) {
      Object.defineProperty(ctx, name, { get: desc.get, configurable: true });
    }
  });
  return ctx;
}

describe("orderCreateWizard product display (Core 11.4.1 / 11.4.3)", () => {
  it("見積商品の表示行を出さない", () => {
    const wizard = bind();

    expect(wizard.productDisplayLines).toEqual([]);
    expect(wizard.showProductDisplayLines).toBe(false);
  });
});
