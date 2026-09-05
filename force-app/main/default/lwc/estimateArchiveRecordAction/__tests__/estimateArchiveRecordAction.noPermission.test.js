import { createElement } from "lwc";
import EstimateArchiveRecordAction from "c/estimateArchiveRecordAction";

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
  "lightning/platformShowToastEvent",
  () => ({ ShowToastEvent: class ShowToastEvent {} }),
  { virtual: true }
);
jest.mock(
  "lightning/uiRecordApi",
  () => ({ getRecordNotifyChange: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateArchiveController.archiveEstimate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateArchiveController.getArchiveContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.issueEstimateOperationKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "c/quickActionPanelResize",
  () => ({ resizeQuickActionPanel: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/estimateValidationAlertUtils",
  () => ({ resolveSaveErrorAlert: jest.fn() }),
  { virtual: true }
);

describe("estimateArchiveRecordAction without Loop_03 (共通基盤 10.4)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("権限なしは見積アーカイブを実行できない", async () => {
    const element = createElement("c-estimate-archive-record-action", {
      is: EstimateArchiveRecordAction
    });
    element.recordId = "a01000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    expect(element.shadowRoot.textContent).toContain(
      "見積アーカイブを実行する権限がありません。"
    );
    const archiveButton = Array.from(
      element.shadowRoot.querySelectorAll("button")
    ).find((button) => button.textContent.replace(/\s+/g, "") === "アーカイブする");
    expect(archiveButton.disabled).toBe(true);
  });
});
