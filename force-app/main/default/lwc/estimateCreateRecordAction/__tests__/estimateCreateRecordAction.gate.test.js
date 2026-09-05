import { createElement } from "lwc";
import EstimateCreateRecordAction from "c/estimateCreateRecordAction";

jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ __esModule: true, default: true }),
  { virtual: true }
);
jest.mock(
  "lightning/navigation",
  () => ({
    NavigationMixin: (Base) =>
      class extends Base {
        [Symbol.for("NavigationMixin.Navigate")]() {}
      }
  }),
  { virtual: true }
);
jest.mock(
  "c/estimateWizardClose",
  () => ({
    closeEstimateWizard: jest.fn(),
    markEstimateRecordForRefresh: jest.fn(),
    refreshOnEstimateRecordActionUnmount: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "c/quickActionPanelResize",
  () => ({ resizeQuickActionPanel: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/estimateCreateWizard",
  () => {
    const { LightningElement } = require("lwc");
    return class EstimateCreateWizard extends LightningElement {};
  },
  { virtual: true }
);

describe("estimateCreateRecordAction (Core 4.3.1 / 共通基盤 10.4)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("opens the new-estimate wizard when Loop_03 is present", async () => {
    const element = createElement("c-estimate-create-record-action", {
      is: EstimateCreateRecordAction
    });
    element.recordId = "006000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    const wizard = element.shadowRoot.querySelector("c-estimate-create-wizard");
    expect(wizard).toBeTruthy();
    expect(wizard.recordId).toBe("006000000000001AAA");
    expect(wizard.modalMode).toBe(true);
  });
});
