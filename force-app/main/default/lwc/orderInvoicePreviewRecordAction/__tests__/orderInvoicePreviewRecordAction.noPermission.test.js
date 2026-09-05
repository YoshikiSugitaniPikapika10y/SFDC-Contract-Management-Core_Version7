import { createElement } from "lwc";
import OrderInvoicePreviewRecordAction from "c/orderInvoicePreviewRecordAction";

jest.mock(
  "@salesforce/customPermission/Loop_09_Can_ViewInvoice",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_10_Can_EditDraftInvoice",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_11_Can_ConfirmInvoice",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_12_Can_SendInvoice",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_13_Can_InvoicePayment",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_14_Can_ManualJournal",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_15_Can_CancelInvoice",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_16_Can_LockJournal",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_17_Can_UnlockJournal",
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
  "c/orderInvoicePreviewWizard",
  () => {
    const { LightningElement } = require("lwc");
    return class OrderInvoicePreviewWizard extends LightningElement {};
  },
  { virtual: true }
);

describe("orderInvoicePreviewRecordAction without board permissions (Core 7.7.0)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("does not open the invoice board without 09〜17", async () => {
    const element = createElement("c-order-invoice-preview-record-action", {
      is: OrderInvoicePreviewRecordAction
    });
    element.recordId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-order-invoice-preview-wizard")
    ).toBeNull();
  });
});
