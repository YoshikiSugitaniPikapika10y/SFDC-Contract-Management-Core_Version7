import { createElement } from "lwc";
import OrderCreateRecordAction from "c/orderCreateRecordAction";

jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_06_Can_Order",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardNavigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {}
  }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardClose",
  () => ({
    closeOrderRecordAction: jest.fn(),
    markOrderRecordForRefresh: jest.fn(),
    refreshOnRecordActionUnmount: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "c/quickActionPanelResize",
  () => ({ resizeQuickActionPanel: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/orderCreateWizard",
  () => {
    const { LightningElement } = require("lwc");
    return class OrderCreateWizard extends LightningElement {};
  },
  { virtual: true }
);

describe("orderCreateRecordAction without Loop_06 (Core 4.3.1 / 5.1)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("does not open the order wizard without 06", async () => {
    const element = createElement("c-order-create-record-action", {
      is: OrderCreateRecordAction
    });
    element.recordId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-order-create-wizard")
    ).toBeNull();
    expect(element.shadowRoot.textContent).toContain(
      "この操作の権限がありません。"
    );
  });
});
