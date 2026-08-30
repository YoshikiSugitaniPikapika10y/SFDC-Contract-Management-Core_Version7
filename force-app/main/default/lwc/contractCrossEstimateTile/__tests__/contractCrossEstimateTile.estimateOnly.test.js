import ContractCrossEstimateTile from "c/contractCrossEstimateTile";

jest.mock("lightning/platformShowToastEvent", () => ({ ShowToastEvent: class {} }), {
  virtual: true
});
jest.mock(
  "@salesforce/apex/ContractCrossController.getEstimateIssueContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.previewEstimateIssueFileName",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.issueEstimate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

describe("contractCrossEstimateTile Estimate only (横断画面.md 第5節)", () => {
  const proto = ContractCrossEstimateTile.prototype;
  const showEstimateContent = Object.getOwnPropertyDescriptor(
    proto,
    "showEstimateContent"
  ).get;
  const notEstimateMessage = Object.getOwnPropertyDescriptor(
    proto,
    "notEstimateMessage"
  ).get;
  const historyRecordUrl = Object.getOwnPropertyDescriptor(
    proto,
    "historyRecordUrl"
  ).get;

  it("Ordered／Archiveは見出し・明細を出さない", () => {
    expect(
      showEstimateContent.call({
        isEstimate: false
      })
    ).toBe(false);
    expect(
      notEstimateMessage.call({
        tile: { id: "a01", isEstimate: false },
        isEstimate: false
      })
    ).toBe(
      "見積書の表示・発行はステータスが見積の契約履歴のみ利用できます。"
    );
  });

  it("Estimateは見出し・明細を出す", () => {
    expect(showEstimateContent.call({ isEstimate: true })).toBe(true);
    expect(
      notEstimateMessage.call({
        tile: { id: "a01", isEstimate: true },
        isEstimate: true
      })
    ).toBe("");
  });

  it("契約履歴名はレコードリンク (横断画面.md 第1節・第5節)", () => {
    expect(
      historyRecordUrl.call({ tile: { id: "a01000000000001AAA" } })
    ).toBe("/lightning/r/ContractHistory__c/a01000000000001AAA/view");
  });
});
