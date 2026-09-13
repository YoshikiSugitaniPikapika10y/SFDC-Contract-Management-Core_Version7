import { createElement } from "lwc";
import EstimateSendRecordAction from "c/estimateSendRecordAction";

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
  "lightning/confirm",
  () => ({ default: { open: jest.fn() } }),
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
    openContentDocumentFilePreview: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateSendBoardController.getBoardContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateSendBoardController.getRecordActionEstimate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateSendBoardController.previewEstimateFromRecordPage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateSendBoardController.sendEstimateFromRecordPage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.getEstimateSendBoardContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.getEstimateSendRecord",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.previewEstimateFromRecordPage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.sendEstimateFromRecordPage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_05_Can_SendEstimate",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);

describe("estimateSendRecordAction without Loop_05 (共通基盤 10.4)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("権限なしは見積を送れない", async () => {
    const element = createElement("c-estimate-send-record-action", {
      is: EstimateSendRecordAction
    });
    element.recordId = "a01000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();

    expect(element.shadowRoot.textContent).toContain(
      "この操作の権限がありません。"
    );
  });
});
