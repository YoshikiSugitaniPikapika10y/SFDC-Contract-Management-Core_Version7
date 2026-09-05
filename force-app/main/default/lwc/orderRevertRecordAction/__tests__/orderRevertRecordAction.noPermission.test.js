import { createElement } from "lwc";
import OrderRevertRecordAction from "c/orderRevertRecordAction";

jest.mock(
  "@salesforce/customPermission/Loop_07_Can_Revert",
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
  "c/orderRevertWizard",
  () => {
    const { LightningElement } = require("lwc");
    return class OrderRevertWizard extends LightningElement {};
  },
  { virtual: true }
);

describe("orderRevertRecordAction without Loop_07 (Core 4.3.1 / 5.3)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("does not open the revert wizard without 07", async () => {
    const element = createElement("c-order-revert-record-action", {
      is: OrderRevertRecordAction
    });
    element.recordId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-order-revert-wizard")
    ).toBeNull();
  });
});
