import ContractCrossWork from "c/contractCrossWork";

jest.mock("c/estimateSendRecordAction");
jest.mock("c/orderCreateWizard");
jest.mock("c/contractCrossEstimateTile");
jest.mock("c/orderInvoicePreviewTable");
jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class {} }),
  { virtual: true }
);
jest.mock("lightning/refresh", () => ({ RefreshEvent: class {} }), {
  virtual: true
});
jest.mock(
  "@salesforce/apex/ContractCrossController.getBootstrap",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.queryEstimates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.queryInvoices",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.queryJournals",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.getEstimateTile",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.saveJournals",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/InvoiceOpsFieldService.getDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.getInvoicePreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.getBillingAccountOptionsForPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.updateInvoiceLineAmounts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.updateInvoiceLineAcceptanceEndDate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.splitInvoiceByDate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.splitInvoiceByBillingAccount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.moveLinesToExistingInvoice",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.splitLinesInPlace",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.updateInvoiceHeaderAndDates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.applyBillingAccountContent",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.cancelConfirmedFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/platformShowToastEvent",
  () => ({ ShowToastEvent: class {} }),
  { virtual: true }
);
jest.mock(
  "lightning/confirm",
  () => ({
    __esModule: true,
    default: { open: jest.fn() }
  }),
  { virtual: true }
);
jest.mock(
  "c/estimateValidationAlertUtils",
  () => ({ resolveSaveErrorAlert: jest.fn() }),
  { virtual: true }
);

describe("contractCrossWork estimate sort (横断画面.md 第5節 見積一覧)", () => {
  it("does not offer 有効期限 as a sort field; 有効期限 is a column only", () => {
    const get = Object.getOwnPropertyDescriptor(
      ContractCrossWork.prototype,
      "sortFieldOptions"
    ).get;
    const values = get
      .call({ menu: "estimate" })
      .map((option) => option.value);
    expect(values).not.toContain("validDate");
    expect(values).toContain("closeDate");
    expect(values).toContain("account");
  });
});

describe("contractCrossWork journal unlock (Accounting 9.5 / Core 1.1.10)", () => {
  const proto = ContractCrossWork.prototype;
  const saveDisabled = Object.getOwnPropertyDescriptor(
    proto,
    "saveDisabled"
  ).get;

  it("Unlock理由空白のみなら保存できない", () => {
    expect(
      saveDisabled.call({
        saving: false,
        hasChecked: true,
        hasDirtyMemos: false,
        jouLock: "Locked",
        unlockReason: "   ",
        isBlankReasonText: proto.isBlankReasonText,
        isUnlockReasonTooLong: proto.isUnlockReasonTooLong
      })
    ).toBe(true);
  });

  it("Unlock理由があれば保存できる", () => {
    expect(
      saveDisabled.call({
        saving: false,
        hasChecked: true,
        hasDirtyMemos: false,
        jouLock: "Locked",
        unlockReason: "監査",
        isBlankReasonText: proto.isBlankReasonText,
        isUnlockReasonTooLong: proto.isUnlockReasonTooLong
      })
    ).toBe(false);
  });

  it("Unlock理由255超なら保存できない", () => {
    expect(
      saveDisabled.call({
        saving: false,
        hasChecked: true,
        hasDirtyMemos: false,
        jouLock: "Locked",
        unlockReason: "a".repeat(256),
        isBlankReasonText: proto.isBlankReasonText,
        isUnlockReasonTooLong: proto.isUnlockReasonTooLong
      })
    ).toBe(true);
  });
});

describe("contractCrossWork journal memo (Core 12.2 / 7.7.3)", () => {
  const proto = ContractCrossWork.prototype;
  const journalCells = proto.journalCells.bind({
    journalGroups: [],
    canEditJournalMemoOp: true
  });

  it("取消済み請求の仕訳メモは編集できない", () => {
    const editable = journalCells(
      { invoiceCancelled: false, invoiceName: "INV" },
      "メモ"
    );
    const cancelled = journalCells(
      { invoiceCancelled: true, invoiceName: "INV" },
      "メモ"
    );
    const memoCell = (cells) => cells.find((cell) => cell.isMemo === true);
    expect(memoCell(editable).canEditMemo).toBe(true);
    expect(memoCell(cancelled).canEditMemo).toBe(false);
    expect(memoCell(editable).className).toBe("memo-cell no-open");
    expect(editable.find((cell) => cell.key === "confirm").className).toBe(
      "confirm-cell"
    );
  });

  it("列モードのLock済みは除外に無い追加項目を非活性にする", () => {
    const cells = proto.journalCells.call(
      {
        journalGroups: [],
        canEditJournalMemoOp: true,
        journalColumnMode: true,
        extraDrafts: {},
        journalLockExemptFieldApiNames: ["Memo__c"],
        journalExtraDefinitions: [
          { apiName: "UnlockReason__c", label: "Unlock理由", fieldType: "STRING" }
        ]
      },
      { invoiceCancelled: false, invoiceName: "INV", isLocked: true },
      "メモ"
    );
    const extra = cells.find((cell) => cell.isExtra === true);
    expect(extra.disabled).toBe(true);
  });

  it("取消済み請求のメモ変更は保存対象にしない", () => {
    const drafts = proto.dirtyMemos.call({
      journalRows: [
        { id: "j1", invoiceId: "inv1", memo: "旧", invoiceCancelled: true }
      ],
      memoDrafts: { j1: "新" }
    });
    expect(drafts).toEqual([]);
  });

  it("追加項目の変更は同じ保存のpayloadに載る", () => {
    const drafts = proto.dirtyJournalEdits.call({
      journalRows: [
        {
          id: "j1",
          invoiceId: "inv1",
          memo: "旧",
          extraFieldValues: { UnlockReason__c: "旧理由" }
        }
      ],
      memoDrafts: {},
      extraDrafts: { j1: { UnlockReason__c: "新理由" } },
      journalExtraDefinitions: [{ apiName: "UnlockReason__c", label: "Unlock理由" }]
    });
    expect(drafts).toEqual([
      {
        journalId: "j1",
        invoiceId: "inv1",
        memo: "旧",
        extraFieldValues: { UnlockReason__c: "新理由" }
      }
    ]);
  });

  it("取消・取消済の追加項目は保存対象にしない", () => {
    const drafts = proto.dirtyJournalEdits.call({
      journalRows: [
        {
          id: "j1",
          invoiceId: "inv1",
          memo: "旧",
          invoiceCancelled: true,
          extraFieldValues: {}
        },
        {
          id: "j2",
          invoiceId: "inv2",
          memo: "旧",
          transactionStatus: "Cancelled",
          extraFieldValues: {}
        }
      ],
      memoDrafts: {},
      extraDrafts: {
        j1: { UnlockReason__c: "x" },
        j2: { UnlockReason__c: "y" }
      },
      journalExtraDefinitions: [{ apiName: "UnlockReason__c" }]
    });
    expect(drafts).toEqual([]);
  });
});

describe("contractCrossWork openRow (横断画面.md 第2.4節・第5節)", () => {
  const proto = ContractCrossWork.prototype;

  it("請求一覧は同じ請求の再クリックでも右を取り直す", () => {
    const loadInvoiceTile = jest.fn();
    const ctx = {
      menu: "invoice",
      invoicePreview: { id: "inv1" },
      tableInitialInvoiceId: "inv1",
      previewHistoryId: "h1",
      highlightJournalId: null,
      loadInvoiceTile
    };
    proto.openRow.call(ctx, {
      id: "inv1",
      invoiceId: "inv1",
      historyId: "h1",
      journalId: null
    });
    expect(loadInvoiceTile).toHaveBeenCalledWith("h1", "inv1", null);
  });

  it("仕訳一覧は同じ請求なら右を維持する", () => {
    const loadInvoiceTile = jest.fn();
    const ctx = {
      menu: "journal",
      invoicePreview: { id: "inv1" },
      tableInitialInvoiceId: "inv1",
      previewHistoryId: "h1",
      highlightJournalId: null,
      loadInvoiceTile
    };
    proto.openRow.call(ctx, {
      id: "j2",
      invoiceId: "inv1",
      historyId: "h1",
      journalId: "j2"
    });
    expect(loadInvoiceTile).not.toHaveBeenCalled();
    expect(ctx.highlightJournalId).toBe("j2");
  });

  it("列モードでは行クリックで右を開かない", () => {
    const openRow = jest.fn();
    proto.handleRowClick.call(
      {
        menu: "journal",
        journalColumnMode: true,
        builtRows: [{ kind: "data", id: "j1" }],
        openRow
      },
      {
        target: { closest: () => null },
        currentTarget: { dataset: { id: "j1" } }
      }
    );
    expect(openRow).not.toHaveBeenCalled();
  });
});

describe("contractCrossWork invoiceStatus label (横断画面.md 第5節・操作11)", () => {
  const proto = ContractCrossWork.prototype;

  it("取消済みの見出し・列はCancelledではなく取消済み", () => {
    expect(
      proto.groupLabel.call(
        { invoiceStatusLabel: proto.invoiceStatusLabel },
        { id: "invoiceStatus" },
        { invoiceStatus: "Cancelled" }
      )
    ).toBe("取消済み");
  });

  it("未確定と確定は和名のまま", () => {
    const ctx = { invoiceStatusLabel: proto.invoiceStatusLabel };
    expect(
      proto.groupLabel.call(ctx, { id: "invoiceStatus" }, { invoiceStatus: "Draft" })
    ).toBe("未確定");
    expect(
      proto.groupLabel.call(
        ctx,
        { id: "invoiceStatus" },
        { invoiceStatus: "Confirmed" }
      )
    ).toBe("確定");
  });
});

describe("contractCrossWork journal columns (横断画面.md 第5節)", () => {
  const getHeaders = Object.getOwnPropertyDescriptor(
    ContractCrossWork.prototype,
    "columnHeaders"
  ).get;
  const offGroups = [
    { id: "postingDate", label: "計上日", on: false, total: false },
    { id: "billingAccount", label: "請求アカウント", on: false, total: false },
    { id: "invoice", label: "請求", on: false, total: false },
    { id: "event", label: "会計イベント", on: false, total: false }
  ];

  it("請求グループOFFでも請求書名は1列", () => {
    const headers = getHeaders.call({
      menu: "journal",
      journalGroups: offGroups
    });
    expect(headers.filter((item) => item.key === "invoice")).toHaveLength(1);
    expect(headers.filter((item) => item.label === "請求書名")).toHaveLength(1);
    expect(headers.filter((item) => item.label === "請求")).toHaveLength(0);
  });

  it("確認用とメモは幅クラスを持ち、商談名・契約履歴名は出さない", () => {
    const headers = getHeaders.call({
      menu: "journal",
      journalGroups: offGroups
    });
    expect(headers.find((item) => item.key === "confirm").className).toBe(
      "confirm-cell"
    );
    expect(headers.find((item) => item.key === "memo").className).toBe(
      "memo-cell"
    );
    expect(headers.some((item) => item.label === "商談名")).toBe(false);
    expect(headers.some((item) => item.label === "契約履歴名")).toBe(false);
  });

  it("請求一覧のメモは仕訳の幅クラスを付けない", () => {
    const headers = getHeaders.call({
      menu: "invoice",
      invoiceGroups: [],
      accountingEnabled: false,
      historyGroupOn: true,
      showInvoiceIssueFilter: false,
      showInvoiceSendFilter: false
    });
    expect(headers.find((item) => item.key === "memo").className).toBeUndefined();
  });

  it("列モードONなら既存列の右へ仕訳追加項目を出す", () => {
    const headers = getHeaders.call({
      menu: "journal",
      journalGroups: offGroups,
      journalColumnMode: true,
      journalExtraDefinitions: [
        { apiName: "UnlockReason__c", label: "Unlock理由" }
      ]
    });
    const keys = headers.map((item) => item.key);
    expect(keys[keys.length - 1]).toBe("extra-UnlockReason__c");
    expect(keys.indexOf("invoice")).toBeLessThan(
      keys.indexOf("extra-UnlockReason__c")
    );
  });

  it("請求一覧左にカスタム列は足さない", () => {
    const headers = getHeaders.call({
      menu: "invoice",
      invoiceGroups: [],
      accountingEnabled: false,
      historyGroupOn: true,
      showInvoiceIssueFilter: false,
      showInvoiceSendFilter: false,
      journalColumnMode: true,
      journalExtraDefinitions: [
        { apiName: "UnlockReason__c", label: "Unlock理由" }
      ]
    });
    expect(headers.some((item) => String(item.key).startsWith("extra-"))).toBe(
      false
    );
  });
});

describe("contractCrossWork journal lock colors (横断画面.md 第2.4節・第5節)", () => {
  const proto = ContractCrossWork.prototype;
  const journalActionClass = Object.getOwnPropertyDescriptor(
    proto,
    "journalActionClass"
  ).get;
  const tableWrapClass = Object.getOwnPropertyDescriptor(
    proto,
    "tableWrapClass"
  ).get;

  it("未Lockならチェックと保存のクラスは青、Lock済みなら赤", () => {
    expect(journalActionClass.call({ isLockUnlocked: true })).toBe(
      "journal-bar lock-unlocked"
    );
    expect(journalActionClass.call({ isLockUnlocked: false })).toBe(
      "journal-bar lock-locked"
    );
    expect(
      tableWrapClass.call({
        isJournalMenu: true,
        journalUnlockedClass: "lock-unlocked"
      })
    ).toBe("table-wrap lock-unlocked");
    expect(
      tableWrapClass.call({
        isJournalMenu: true,
        journalUnlockedClass: "lock-locked"
      })
    ).toBe("table-wrap lock-locked");
  });
});

describe("contractCrossWork total row (横断画面.md 第5節 小計・合計)", () => {
  it("合計は金額列だけに載せ、日付・名前は空", () => {
    const row = ContractCrossWork.prototype.toTotalRow.call(
      {
        columnHeaders: [
          { key: "account", label: "取引先" },
          { key: "amount", label: "税抜" },
          { key: "invoiceDate", label: "請求日" }
        ]
      },
      { id: "account", label: "取引先" },
      [{ amount: 1000 }, { amount: 500 }]
    );
    expect(row.cells.map((cell) => cell.text)).toEqual(["", "1,500", ""]);
    expect(row.cells[1].className).toBe("num");
  });
});

describe("contractCrossWork send mode columns (横断画面.md 第1節、Core 第4.10節)", () => {
  const proto = ContractCrossWork.prototype;
  const getHeaders = Object.getOwnPropertyDescriptor(proto, "columnHeaders").get;
  const showEstimateIssueFilter = Object.getOwnPropertyDescriptor(
    proto,
    "showEstimateIssueFilter"
  ).get;
  const showEstimateSendFilter = Object.getOwnPropertyDescriptor(
    proto,
    "showEstimateSendFilter"
  ).get;
  const showInvoiceIssueFilter = Object.getOwnPropertyDescriptor(
    proto,
    "showInvoiceIssueFilter"
  ).get;
  const showInvoiceSendFilter = Object.getOwnPropertyDescriptor(
    proto,
    "showInvoiceSendFilter"
  ).get;

  it("使わないなら発行も送付も出さない", () => {
    expect(showEstimateIssueFilter.call({ estimateSendMode: "Unused" })).toBe(
      false
    );
    expect(showEstimateSendFilter.call({ estimateSendMode: "Unused" })).toBe(
      false
    );
    expect(showInvoiceIssueFilter.call({ invoiceSendMode: "Unused" })).toBe(
      false
    );
    expect(showInvoiceSendFilter.call({ invoiceSendMode: "Unused" })).toBe(
      false
    );
  });

  it("PDFのみなら発行まで、送付は出さない", () => {
    expect(showEstimateIssueFilter.call({ estimateSendMode: "PdfOnly" })).toBe(
      true
    );
    expect(showEstimateSendFilter.call({ estimateSendMode: "PdfOnly" })).toBe(
      false
    );
    expect(showInvoiceIssueFilter.call({ invoiceSendMode: "PdfOnly" })).toBe(
      true
    );
    expect(showInvoiceSendFilter.call({ invoiceSendMode: "PdfOnly" })).toBe(
      false
    );
  });

  it("PDFとメール送付なら発行と送付を出す", () => {
    expect(
      showEstimateIssueFilter.call({ estimateSendMode: "PdfAndEmail" })
    ).toBe(true);
    expect(
      showEstimateSendFilter.call({ estimateSendMode: "PdfAndEmail" })
    ).toBe(true);
    expect(
      showInvoiceIssueFilter.call({ invoiceSendMode: "PdfAndEmail" })
    ).toBe(true);
    expect(showInvoiceSendFilter.call({ invoiceSendMode: "PdfAndEmail" })).toBe(
      true
    );
  });

  it("見積の使わないでは発行・送付列を出さない", () => {
    const headers = getHeaders.call({
      menu: "estimate",
      estimateGroups: [],
      showEstimateIssueFilter: false,
      showEstimateSendFilter: false
    });
    expect(headers.some((item) => item.key === "sent")).toBe(false);
    expect(headers.some((item) => item.key === "issued")).toBe(false);
    expect(headers.some((item) => item.key === "valid")).toBe(true);
  });

  it("請求のPDFのみでは発行列だけ出し遅延は残す", () => {
    const headers = getHeaders.call({
      menu: "invoice",
      invoiceGroups: [],
      accountingEnabled: false,
      historyGroupOn: true,
      showInvoiceIssueFilter: true,
      showInvoiceSendFilter: false
    });
    expect(headers.some((item) => item.key === "sent")).toBe(false);
    expect(headers.some((item) => item.key === "issued")).toBe(true);
    expect(headers.some((item) => item.key === "overdue")).toBe(true);
  });

  it("隠した送付・発行フィルタは取得条件に載せない", () => {
    const estimate = proto.estimateFilter.call({
      estCloseFrom: "",
      estCloseTo: "",
      estAccountId: null,
      estServiceId: null,
      estType: "",
      estSent: "true",
      estIssued: "true",
      estAutoRenew: "",
      estValidFrom: "",
      estValidTo: "",
      showEstimateSendFilter: false,
      showEstimateIssueFilter: false
    });
    expect(estimate.sent).toBeNull();
    expect(estimate.issued).toBeNull();
    const invoice = proto.invoiceFilter.call({
      accountingEnabled: false,
      tagRules: [],
      tagFilterState: {},
      invStatus: "Draft",
      invName: "",
      invBillingAccountId: null,
      invAccountId: null,
      invDateFrom: "",
      invDateTo: "",
      invCloseFrom: "",
      invCloseTo: "",
      invIncludeCancelled: false,
      invSent: "true",
      invIssued: "true",
      invOverdue: "",
      invCollection: "",
      showInvoiceSendFilter: false,
      showInvoiceIssueFilter: true
    });
    expect(invoice.sent).toBeNull();
    expect(invoice.issued).toBe(true);
  });
});

describe("contractCrossWork version group reload (横断画面.md 操作14・操作32)", () => {
  it("成功後の右は当該 Version の請求だけ残す", () => {
    const next = ContractCrossWork.prototype.keepOpenedVersionGroup({
      sourceHistoryVersion: "2",
      invoices: [
        { invoiceId: "a", historyVersion: 1 },
        { invoiceId: "b", historyVersion: 2 },
        { invoiceId: "c", historyVersion: 2 }
      ],
      versionOptions: [
        { value: "1", label: "版1" },
        { value: "2", label: "版2" }
      ]
    });
    expect(next.invoices.map((row) => row.invoiceId)).toEqual(["b", "c"]);
    expect(next.versionOptions.map((row) => row.value)).toEqual(["2"]);
  });
});

describe("contractCrossWork issued icon (横断画面.md 操作23)", () => {
  const proto = ContractCrossWork.prototype;

  function invoiceCtx() {
    return {
      invoiceGroups: [],
      accountingEnabled: false,
      historyGroupOn: true,
      showInvoiceSendFilter: false,
      showInvoiceIssueFilter: true
    };
  }

  it("発行ありなら最新PDFのプレビューURLを載せる", () => {
    const issued = proto.invoiceCells
      .call(invoiceCtx(), {
        id: "inv1",
        invoiceName: "I-1",
        issued: true,
        latestIssuedContentDocumentId: "069000000000001AAA",
        overdue: false
      })
      .find((cell) => cell.key === "issued");
    expect(issued.on).toBe(true);
    expect(issued.href).toBe(
      "/lightning/r/ContentDocument/069000000000001AAA/view"
    );
  });

  it("未発行ならURLは載せない", () => {
    const issued = proto.invoiceCells
      .call(invoiceCtx(), {
        id: "inv2",
        invoiceName: "I-2",
        issued: false,
        latestIssuedContentDocumentId: "",
        overdue: false
      })
      .find((cell) => cell.key === "issued");
    expect(issued.on).toBe(false);
    expect(issued.href).toBe("");
  });
});
