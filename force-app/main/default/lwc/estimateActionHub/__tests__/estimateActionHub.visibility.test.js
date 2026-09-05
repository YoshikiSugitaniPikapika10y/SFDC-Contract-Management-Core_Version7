import { createElement } from "lwc";
import EstimateActionHub from "c/estimateActionHub";
import getDocumentDefaults from "@salesforce/apex/EstimateCreateController.getDocumentDefaults";

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
jest.mock("lightning/actions", () => ({ CloseActionScreenEvent: class {} }), {
  virtual: true
});

const visibleActions = Object.getOwnPropertyDescriptor(
  EstimateActionHub.prototype,
  "visibleActions"
).get;

function actionsOf(overrides) {
  const ctx = Object.create(EstimateActionHub.prototype);
  Object.assign(ctx, overrides);
  return visibleActions.call(ctx);
}

describe("estimateActionHub (Core 4.3.1 / 共通基盤 10.4)", () => {
  it("lists hub actions for Estimate when send mode is PDF and email", () => {
    expect(
      actionsOf({
        historyStatus: "Estimate",
        estimateSendMode: "PdfAndEmail"
      }).map((row) => row.label)
    ).toEqual(["編集", "コピー", "アーカイブ", "見積書発行", "見積を送る"]);
  });

  it("hides send when estimate documents are PDF only, and hides issue when unused", () => {
    expect(
      actionsOf({
        historyStatus: "Estimate",
        estimateSendMode: "PdfOnly"
      }).map((row) => row.label)
    ).toEqual(["編集", "コピー", "アーカイブ", "見積書発行"]);
    expect(
      actionsOf({
        historyStatus: "Estimate",
        estimateSendMode: "Unused"
      }).map((row) => row.label)
    ).toEqual(["編集", "コピー", "アーカイブ"]);
  });

  it("does not list Estimate hub actions for Ordered", () => {
    expect(
      actionsOf({
        historyStatus: "Ordered",
        estimateSendMode: "PdfAndEmail"
      })
    ).toEqual([]);
  });

  it("loads document defaults when the hub opens", async () => {
    getDocumentDefaults.mockResolvedValue({ estimateSendMode: "PdfAndEmail" });
    const element = createElement("c-estimate-action-hub", {
      is: EstimateActionHub
    });
    document.body.appendChild(element);
    await Promise.resolve();
    expect(getDocumentDefaults).toHaveBeenCalled();
    document.body.removeChild(element);
  });
});
