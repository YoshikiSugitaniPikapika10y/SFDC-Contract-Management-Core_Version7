import { createElement } from "lwc";
import EstimateCopyRecordAction from "c/estimateCopyRecordAction";

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

describe("estimateCopyRecordAction (Core 4.3.1 / 4.3)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("opens the copy-preset wizard when Loop_03 is present", async () => {
    const element = createElement("c-estimate-copy-record-action", {
      is: EstimateCopyRecordAction
    });
    element.recordId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    const wizard = element.shadowRoot.querySelector("c-estimate-create-wizard");
    expect(wizard).toBeTruthy();
    expect(wizard.copySourceHistoryId).toBe("a0H000000000001AAA");
    expect(wizard.modalMode).toBe(true);
  });
});
