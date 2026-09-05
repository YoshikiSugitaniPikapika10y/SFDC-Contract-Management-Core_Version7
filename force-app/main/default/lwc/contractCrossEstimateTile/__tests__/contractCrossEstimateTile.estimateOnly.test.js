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
  const estimateTypeLabel = Object.getOwnPropertyDescriptor(
    proto,
    "estimateTypeLabel"
  ).get;
  const sentLabel = Object.getOwnPropertyDescriptor(proto, "sentLabel").get;
  const sendButtonLabel = Object.getOwnPropertyDescriptor(
    proto,
    "sendButtonLabel"
  ).get;
  const showOrderButton = Object.getOwnPropertyDescriptor(
    proto,
    "showOrderButton"
  ).get;
  const showAccountingColumn = Object.getOwnPropertyDescriptor(
    proto,
    "showAccountingColumn"
  ).get;
  const lines = Object.getOwnPropertyDescriptor(proto, "lines").get;

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

  it("見積種別チップは新規／追加変更／更新／解約 (Core 0.1)", () => {
    expect(
      estimateTypeLabel.call({
        tile: { estimateTypeLabel: "新規", estimateType: "New" }
      })
    ).toBe("新規");
    expect(
      estimateTypeLabel.call({ tile: { estimateTypeLabel: "追加変更" } })
    ).toBe("追加変更");
    expect(
      estimateTypeLabel.call({ tile: { estimateTypeLabel: "更新" } })
    ).toBe("更新");
    expect(
      estimateTypeLabel.call({ tile: { estimateTypeLabel: "解約" } })
    ).toBe("解約");
    expect(
      estimateTypeLabel.call({ tile: { estimateTypeLabel: "解約" } })
    ).not.toMatch(/Churn/);
  });

  it("送付は空なら未送付、送付済みなら再送する (横断画面.md 第5節)", () => {
    expect(sentLabel.call({ tile: {} })).toBe("未送付");
    expect(sendButtonLabel.call({ tile: {} })).toBe("見積を送る");
    expect(
      sendButtonLabel.call({ tile: { sentAt: "2026-09-01T00:00:00.000Z" } })
    ).toBe("再送する");
  });

  it("個別受注だけ出し一括受注は持たない (Core 第9章・横断画面.md 第5節)", () => {
    expect(showOrderButton.call({ isEstimate: true, canOrder: true })).toBe(
      true
    );
    expect(showOrderButton.call({ isEstimate: false, canOrder: true })).toBe(
      false
    );
    expect(showOrderButton.call({ isEstimate: true, canOrder: false })).toBe(
      false
    );
  });

  it("行種別は追加／変更前／変更後／更新。Accounting OFFは売上計上列なし (横断画面.md 第5節)", () => {
    const mapped = lines.call({
      tile: {
        lines: [
          { id: "1", typeLabel: "追加", typeValue: "New" },
          { id: "2", typeLabel: "変更前", typeValue: "Original" },
          { id: "3", typeLabel: "変更後", typeValue: "Remake" },
          { id: "4", typeLabel: "更新", typeValue: "Renew" }
        ]
      }
    });
    expect(mapped.map((row) => row.typeLabel)).toEqual([
      "追加",
      "変更前",
      "変更後",
      "更新"
    ]);
    expect(showAccountingColumn.call({ accountingEnabled: false })).toBe(
      false
    );
    expect(showAccountingColumn.call({ accountingEnabled: true })).toBe(true);
  });
});
