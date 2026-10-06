import OrderRevertWizard from "c/orderRevertWizard";

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
    isOrderWizardTabView: () => false,
    readOrderWizardRecordId: () => null
  }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardClose",
  () => ({
    HISTORY_STATUS_ARCHIVE: "Archive",
    isOrderActionBootstrapping: () => false,
    notifyOrderRecordStatusChanged: jest.fn(),
    requestOrderWizardClose: jest.fn(),
    scheduleRecordActionLoad: jest.fn(),
    resetRecordActionLoadState: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "c/estimateValidationAlertUtils",
  () => ({
    resolveSaveErrorAlert: () => ({ messages: [] })
  }),
  { virtual: true }
);
jest.mock(
  "c/estimateWizardCustomFields",
  () => ({
    buildCustomFieldInputs: jest.fn(() => [{ key: "display" }])
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
  const proto = OrderRevertWizard.prototype;
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

describe("orderRevertWizard product display (Core 11.4.1 / 11.4.3)", () => {
  it("見積商品の表示行を出さない", () => {
    const wizard = bind();

    expect(wizard.productDisplayLines).toEqual([]);
    expect(wizard.showProductDisplayLines).toBe(false);
  });
});
