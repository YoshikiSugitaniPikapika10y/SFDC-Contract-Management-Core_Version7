import { createElement } from "lwc";
import EstimateArchiveRecordAction from "c/estimateArchiveRecordAction";
import archiveEstimate from "@salesforce/apex/EstimateArchiveController.archiveEstimate";
import getArchiveContext from "@salesforce/apex/EstimateArchiveController.getArchiveContext";

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
  () => ({ default: true }),
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

describe("estimateArchiveRecordAction gate (Core 5.5 / 1.1.10)", () => {
  const proto = EstimateArchiveRecordAction.prototype;
  const isArchiveDisabled = Object.getOwnPropertyDescriptor(
    proto,
    "isArchiveDisabled"
  ).get;

  function ctx(overrides) {
    return {
      isBusy: false,
      recordId: "a01000000000001AAA",
      hasPermission: true,
      isEstimate: true,
      ...overrides
    };
  }

  it("Estimateならアーカイブできる", () => {
    expect(isArchiveDisabled.call(ctx())).toBe(false);
  });

  it("Estimate以外なら実行できない", () => {
    expect(isArchiveDisabled.call(ctx({ isEstimate: false }))).toBe(true);
  });
});

describe("estimateArchiveRecordAction subtitle (Core 0.1 / 4.3.1 / 5.5)", () => {
  const proto = EstimateArchiveRecordAction.prototype;
  const confirmSubtitle = Object.getOwnPropertyDescriptor(
    proto,
    "confirmSubtitle"
  ).get;

  it("uses 不採用 not 破棄", () => {
    expect(confirmSubtitle.call({})).toBe(
      "見積を不採用にして編集不可にします"
    );
    expect(confirmSubtitle.call({})).not.toMatch(/破棄/);
  });
});

describe("estimateArchiveRecordAction confirm (Core 5.5)", () => {
  const proto = EstimateArchiveRecordAction.prototype;

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("確認画面はアーカイブする／キャンセル。window.confirmは使わない", async () => {
    getArchiveContext.mockResolvedValue({
      historyStatus: "Estimate",
      lastModifiedToken: "tok"
    });
    const confirmSpy = jest.spyOn(window, "confirm");
    const element = createElement("c-estimate-archive-record-action", {
      is: EstimateArchiveRecordAction
    });
    element.recordId = "a01000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();

    const buttons = Array.from(element.shadowRoot.querySelectorAll("button")).map(
      (button) => button.textContent.replace(/\s+/g, "")
    );
    expect(buttons).toContain("キャンセル");
    expect(buttons).toContain("アーカイブする");
    expect(element.shadowRoot.textContent).toContain(
      "この見積を不採用にします。よろしいですか？"
    );
    expect(confirmSpy).not.toHaveBeenCalled();
    confirmSpy.mockRestore();
  });

  it("Estimate以外は不採用にできない", async () => {
    getArchiveContext.mockResolvedValue({
      historyStatus: "Ordered",
      lastModifiedToken: "tok"
    });
    const self = {
      recordId: "a01000000000001AAA",
      errorMessage: "",
      historyStatus: "",
      _lastModifiedToken: ""
    };
    await proto.loadContext.call(self);
    expect(self.errorMessage).toBe(
      "見積状態の契約履歴のみ不採用にできます。"
    );
    await proto.handleArchive.call({ isArchiveDisabled: true });
    expect(archiveEstimate).not.toHaveBeenCalled();
  });
});
