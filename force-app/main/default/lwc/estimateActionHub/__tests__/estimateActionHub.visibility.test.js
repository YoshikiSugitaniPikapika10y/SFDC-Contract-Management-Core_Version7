import EstimateActionHub from "c/estimateActionHub";

jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_04_Can_IssueEstimate",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_05_Can_SendEstimate",
  () => ({ default: true }),
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
  "lightning/navigation",
  () => ({
    NavigationMixin: (Base) =>
      class extends Base {
        [Symbol.for("NavigationMixin.Navigate")]() {}
      }
  }),
  { virtual: true }
);
jest.mock("lightning/actions", () => ({ CloseActionScreenEvent: class {} }), {
  virtual: true
});

function keysOf(ctx) {
  return EstimateActionHub.prototype.visibleActions
    .get.call(ctx)
    .map((row) => row.key);
}

describe("estimateActionHub (Core 4.3.1)", () => {
  it("lists hub actions for Estimate when send mode is PDF and email", () => {
    expect(
      keysOf({
        historyStatus: "Estimate",
        estimateSendMode: "PdfAndEmail"
      })
    ).toEqual(["edit", "copy", "archive", "issue", "send"]);
  });

  it("hides send when estimate documents are PDF only, and hides issue when unused", () => {
    expect(
      keysOf({
        historyStatus: "Estimate",
        estimateSendMode: "PdfOnly"
      })
    ).toEqual(["edit", "copy", "archive", "issue"]);
    expect(
      keysOf({
        historyStatus: "Estimate",
        estimateSendMode: "Unused"
      })
    ).toEqual(["edit", "copy", "archive"]);
  });

  it("does not list Estimate hub actions for Ordered", () => {
    expect(
      keysOf({
        historyStatus: "Ordered",
        estimateSendMode: "PdfAndEmail"
      })
    ).toEqual([]);
  });
});
