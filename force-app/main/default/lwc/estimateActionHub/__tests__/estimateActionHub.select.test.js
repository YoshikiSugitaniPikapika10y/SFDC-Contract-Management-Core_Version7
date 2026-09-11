import EstimateActionHub from "c/estimateActionHub";
import { NavigationMixin } from "lightning/navigation";

jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ __esModule: true, default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_04_Can_IssueEstimate",
  () => ({ __esModule: true, default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_05_Can_SendEstimate",
  () => ({ __esModule: true, default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getDocumentDefaults",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/uiRecordApi",
  () => ({ getRecord: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/actions",
  () => ({
    CloseActionScreenEvent: class CloseActionScreenEvent extends Event {
      constructor() {
        super("closeActionScreen");
      }
    }
  }),
  { virtual: true }
);
jest.mock(
  "c/quickActionPanelResize",
  () => ({ resizeQuickActionPanel: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardNavigation",
  () => ({ openContentDocumentFilePreview: jest.fn() }),
  { virtual: true }
);

import { openContentDocumentFilePreview } from "c/orderWizardNavigation";

const Navigate = NavigationMixin.Navigate;

function hubContext(recordId) {
  const dispatched = [];
  const navigate = jest.fn();
  const proto = EstimateActionHub.prototype;
  const ctx = {
    recordId,
    showIssueFrame: false,
    dispatchEvent(event) {
      dispatched.push(event.type);
    },
    [Navigate]: navigate,
    openRecordQuickAction: proto.openRecordQuickAction
  };
  return { ctx, dispatched, navigate };
}

describe("estimateActionHub select (Core 4.3.1 / 画面見た目第2節)", () => {
  it("opens edit as record Quick Action overlay with backgroundContext (same as 受注)", () => {
    const { ctx, dispatched, navigate } = hubContext("a0H000000000001AAA");

    EstimateActionHub.prototype.handleSelect.call(ctx, {
      currentTarget: { dataset: { key: "edit" } }
    });

    expect(dispatched).toEqual([]);
    expect(navigate).toHaveBeenCalledWith(
      {
        type: "standard__quickAction",
        attributes: {
          apiName: "ContractHistory__c.EstimateEdit"
        },
        state: {
          objectApiName: "ContractHistory__c",
          context: "RECORD_DETAIL",
          recordId: "a0H000000000001AAA",
          backgroundContext:
            "/lightning/r/ContractHistory__c/a0H000000000001AAA/view"
        }
      },
      true
    );
  });

  it("opens copy, archive, and send as record Quick Action overlays", () => {
    const { ctx, navigate } = hubContext("a0H000000000001AAA");

    EstimateActionHub.prototype.handleSelect.call(ctx, {
      currentTarget: { dataset: { key: "copy" } }
    });
    expect(navigate).toHaveBeenLastCalledWith(
      expect.objectContaining({
        attributes: { apiName: "ContractHistory__c.EstimateCopy" }
      }),
      true
    );

    EstimateActionHub.prototype.handleSelect.call(ctx, {
      currentTarget: { dataset: { key: "archive" } }
    });
    expect(navigate).toHaveBeenLastCalledWith(
      expect.objectContaining({
        attributes: { apiName: "ContractHistory__c.Estimate_Archive" }
      }),
      true
    );

    EstimateActionHub.prototype.handleSelect.call(ctx, {
      currentTarget: { dataset: { key: "send" } }
    });
    expect(navigate).toHaveBeenLastCalledWith(
      expect.objectContaining({
        attributes: { apiName: "ContractHistory__c.Estimate_Send" }
      }),
      true
    );
  });

  it("keeps the hub overlay and shows issue VF inside for 見積書発行", () => {
    const { ctx, dispatched, navigate } = hubContext("a0H000000000001AAA");

    EstimateActionHub.prototype.handleSelect.call(ctx, {
      currentTarget: { dataset: { key: "issue" } }
    });

    expect(dispatched).toEqual([]);
    expect(navigate).not.toHaveBeenCalled();
    expect(ctx.showIssueFrame).toBe(true);
  });

  it("opens filePreview overlay from issue iframe message (Core 4.8 / 7.10)", () => {
    openContentDocumentFilePreview.mockClear();
    const { ctx, navigate } = hubContext("a0H000000000001AAA");
    ctx.showIssueFrame = true;

    EstimateActionHub.prototype.handleIssueFrameMessage.call(ctx, {
      origin: window.location.origin,
      data: {
        source: "EstimateDocumentIssue",
        action: "filePreview",
        documentId: "069AAA000000001"
      }
    });

    expect(openContentDocumentFilePreview).toHaveBeenCalledWith(
      ctx,
      "069AAA000000001"
    );
    expect(navigate).not.toHaveBeenCalled();
    expect(ctx.showIssueFrame).toBe(true);
  });

  it("opens send Quick Action from issue iframe sendThisFile (Core 4.8)", () => {
    const setItem = jest.spyOn(Storage.prototype, "setItem");
    const { ctx, navigate } = hubContext("a0H000000000001AAA");
    ctx.showIssueFrame = true;
    ctx.openRecordQuickAction = EstimateActionHub.prototype.openRecordQuickAction;

    EstimateActionHub.prototype.handleIssueFrameMessage.call(ctx, {
      origin: window.location.origin,
      data: {
        source: "EstimateDocumentIssue",
        action: "sendThisFile",
        documentId: "069AAA000000001",
        historyId: "a0H000000000001AAA"
      }
    });

    expect(setItem).toHaveBeenCalledWith(
      "cmc.estimateSend.initialContentDocumentId",
      "069AAA000000001"
    );
    expect(ctx.showIssueFrame).toBe(false);
    expect(navigate).toHaveBeenCalledWith(
      expect.objectContaining({
        attributes: { apiName: "ContractHistory__c.Estimate_Send" }
      }),
      true
    );
    setItem.mockRestore();
  });

  it("does not navigate when the row has no action", () => {
    const { ctx, dispatched, navigate } = hubContext("a0H000000000001AAA");

    EstimateActionHub.prototype.handleSelect.call(ctx, {
      currentTarget: { dataset: { key: "" } }
    });

    expect(dispatched).toEqual([]);
    expect(navigate).not.toHaveBeenCalled();
    expect(ctx.showIssueFrame).toBe(false);
  });
});
