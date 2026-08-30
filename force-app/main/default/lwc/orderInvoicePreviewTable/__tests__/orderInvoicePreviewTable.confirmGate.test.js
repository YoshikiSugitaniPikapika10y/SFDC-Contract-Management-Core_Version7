import OrderInvoicePreviewTable from "c/orderInvoicePreviewTable";

jest.mock(
  "@salesforce/customPermission/Loop_16_Can_LockJournal",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_17_Can_UnlockJournal",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_10_Can_EditDraftInvoice",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_11_Can_ConfirmInvoice",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_12_Can_SendInvoice",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_13_Can_InvoicePayment",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_14_Can_ManualJournal",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_15_Can_CancelInvoice",
  () => ({ default: true }),
  { virtual: true }
);

describe("orderInvoicePreviewTable confirm gate (Core 7.9.1 / 7.6 / 11.9)", () => {
  const proto = OrderInvoicePreviewTable.prototype;

  function board(preview) {
    return {
      preview,
      isCancelledInvoice: proto.isCancelledInvoice,
      versionKeyForInvoice: proto.versionKeyForInvoice,
      confirmVersionKey: proto.confirmVersionKey,
      isAmountMatchedForVersion: proto.isAmountMatchedForVersion,
      isSavedAmountMatchedForVersion: proto.isSavedAmountMatchedForVersion,
      isInvoiceTaxMatched: proto.isInvoiceTaxMatched,
      isInvoiceTaxMatchedForVersion: proto.isInvoiceTaxMatchedForVersion,
      hasEmptyAcceptanceForConfirm: proto.hasEmptyAcceptanceForConfirm,
      confirmBlockedReason: proto.confirmBlockedReason,
      calculateTaxAmount: proto.calculateTaxAmount,
      roundTaxRaw: proto.roundTaxRaw,
      normalizeTaxPercent: proto.normalizeTaxPercent,
      draftAmountDeltaForVersion: proto.draftAmountDeltaForVersion,
      isLineDrafted: proto.isLineDrafted,
      amountDrafts: {},
      totalsForVersion: () => ({
        invoiceExcl: preview.invoiceAmountTotal,
        estimateExcl: preview.periodLineAmountTotal
      })
    };
  }

  const matchedInvoice = {
    invoiceId: "a00INV000000001",
    historyVersion: "1",
    amountTotal: 1000,
    taxTotal: 100,
    taxPercent: 10,
    isCancelled: false,
    lines: [
      {
        lineId: "a01LINE00000001",
        revenueRecognitionBasis: "一括計上",
        acceptanceEndDate: "2027-03-31"
      }
    ]
  };

  it("税抜一致でも税額が丸め結果と違うなら確定できない", () => {
    const ctx = board({
      taxRoundingMode: "DOWN",
      periodLineAmountTotal: 15,
      invoiceAmountTotal: 15,
      invoices: [
        {
          ...matchedInvoice,
          amountTotal: 15,
          taxTotal: 2
        }
      ]
    });
    expect(proto.calculateTaxAmount.call(ctx, 15, 10)).toBe(1);
    expect(proto.confirmBlockedReason.call(ctx, ctx.preview.invoices[0])).toBe(
      "請求書の税額が税抜と税率から計算した値と一致しないため確定できません。"
    );
  });

  it("一括計上の検収終了日が空なら確定できない", () => {
    const ctx = board({
      taxRoundingMode: "DOWN",
      periodLineAmountTotal: 1000,
      invoiceAmountTotal: 1000,
      invoices: [
        {
          ...matchedInvoice,
          lines: [
            {
              lineId: "a01LINE00000001",
              revenueRecognitionBasis: "一括計上",
              acceptanceEndDate: ""
            }
          ]
        }
      ]
    });
    expect(proto.confirmBlockedReason.call(ctx, ctx.preview.invoices[0])).toBe(
      "検収終了日が空の明細があるため確定できません。"
    );
  });

  it("税率が空なら税一致とみなさない (Core 7.7.3 / 1.1.10)", () => {
    const ctx = board({
      taxRoundingMode: "DOWN",
      periodLineAmountTotal: 1000,
      invoiceAmountTotal: 1000,
      invoices: [
        {
          ...matchedInvoice,
          taxPercent: "",
          taxTotal: 0
        }
      ]
    });
    expect(proto.isInvoiceTaxMatched.call(ctx, ctx.preview.invoices[0])).toBe(
      false
    );
    expect(proto.confirmBlockedReason.call(ctx, ctx.preview.invoices[0])).toBe(
      "請求書の税額が税抜と税率から計算した値と一致しないため確定できません。"
    );
  });

  it("PdfAndEmailで届け方空なら確定できない (Core 7.9.1 / 3.3.7 / 1.1.10)", () => {
    const ctx = board({
      taxRoundingMode: "DOWN",
      invoiceSendMode: "PdfAndEmail",
      periodLineAmountTotal: 1000,
      invoiceAmountTotal: 1000,
      invoices: [{ ...matchedInvoice, invoiceDeliveryMethod: "" }]
    });
    expect(
      proto.confirmBlockedReason.call(ctx, ctx.preview.invoices[0])
    ).toBe(
      "組織の請求書設定がPDFとメール送付のとき、届け方が空の請求は確定できません。"
    );
  });

  it("PdfOnlyなら届け方空でも確定を止めない (Core 7.9.1 / 3.3.7)", () => {
    const ctx = board({
      taxRoundingMode: "DOWN",
      invoiceSendMode: "PdfOnly",
      periodLineAmountTotal: 1000,
      invoiceAmountTotal: 1000,
      invoices: [{ ...matchedInvoice, invoiceDeliveryMethod: "" }]
    });
    expect(proto.confirmBlockedReason.call(ctx, ctx.preview.invoices[0])).toBe(
      ""
    );
  });

  it("税抜・税・検収が揃えば確定を止めない", () => {
    const ctx = board({
      taxRoundingMode: "DOWN",
      periodLineAmountTotal: 1000,
      invoiceAmountTotal: 1000,
      invoices: [matchedInvoice]
    });
    expect(proto.confirmBlockedReason.call(ctx, matchedInvoice)).toBe("");
  });

  it("税抜不一致の確定ブロックは税抜と書く (Core 7.9.1 / 7.8.5)", () => {
    const ctx = board({
      taxRoundingMode: "DOWN",
      periodLineAmountTotal: 1000,
      invoiceAmountTotal: 900,
      invoices: [matchedInvoice]
    });
    expect(proto.confirmBlockedReason.call(ctx, matchedInvoice)).toBe(
      "見積合計と請求合計（税抜）が一致しないため確定できません。"
    );
  });

  it("税込合計のずれだけでは確定を止めない", () => {
    const ctx = board({
      taxRoundingMode: "DOWN",
      periodLineAmountTotal: 1000,
      invoiceAmountTotal: 1000,
      invoices: [
        {
          ...matchedInvoice,
          taxInclusiveAmount: 9999
        }
      ]
    });
    expect(proto.confirmBlockedReason.call(ctx, ctx.preview.invoices[0])).toBe(
      ""
    );
  });

  it("未保存の端数ドラフトでもフッタと確定は同じ合計 (Core 7.8.5 / 7.9.1)", () => {
    const ctx = board({
      taxRoundingMode: "DOWN",
      periodLineAmountTotal: 1010,
      invoiceAmountTotal: 1000,
      invoices: [matchedInvoice]
    });
    ctx.totalsForVersion = () => ({
      invoiceExcl: 1010,
      estimateExcl: 1010
    });
    ctx.draftAmountDeltaForVersion = () => 10;
    expect(proto.isAmountMatchedForVersion.call(ctx, "1")).toBe(true);
    expect(proto.isSavedAmountMatchedForVersion.call(ctx, "1")).toBe(false);
    expect(proto.confirmBlockedReason.call(ctx, matchedInvoice)).toBe("");
  });

  it("未保存端数がフッタを崩したら確定できない (Core 7.8.5 / 7.9.1)", () => {
    const ctx = board({
      taxRoundingMode: "DOWN",
      periodLineAmountTotal: 1000,
      invoiceAmountTotal: 1000,
      invoices: [matchedInvoice]
    });
    ctx.totalsForVersion = () => ({
      invoiceExcl: 990,
      estimateExcl: 1000
    });
    ctx.draftAmountDeltaForVersion = () => -10;
    expect(proto.isAmountMatchedForVersion.call(ctx, "1")).toBe(false);
    expect(proto.isSavedAmountMatchedForVersion.call(ctx, "1")).toBe(true);
    expect(proto.confirmBlockedReason.call(ctx, matchedInvoice)).toBe(
      "見積合計と請求合計（税抜）が一致しないため確定できません。"
    );
  });

  it("未保存端数がある間は確定を進めない (Core 7.8.5 / 7.8.2)", async () => {
    const dispatchEvent = jest.fn();
    await proto.handleConfirmInvoice.call(
      {
        hasAmountDrafts: true,
        findInvoice: () => ({ canConfirm: true }),
        confirmBlockedReason: () => "",
        dispatchEvent
      },
      { currentTarget: { dataset: { invoiceId: "a00INV000000001" } } }
    );
    expect(dispatchEvent).not.toHaveBeenCalled();
  });

  it("請求アカウント空なら反映を進めない (Core 7.8 / 3.3.5 / 1.1.10)", async () => {
    const dispatchEvent = jest.fn();
    await proto.handleApplyBillingAccountContent.call(
      {
        hasAmountDrafts: false,
        isSplitOrMoveUiOpen: false,
        isBillingEditUiOpen: false,
        findInvoice: () => ({ billingAccountId: "" }),
        dispatchEvent
      },
      { currentTarget: { dataset: { invoiceId: "a00INV000000001" } } }
    );
    expect(dispatchEvent).not.toHaveBeenCalled();
  });

  it("HALF_UP は 0.5 を 0 から離す", () => {
    const ctx = board({ taxRoundingMode: "HALF_UP" });
    expect(proto.calculateTaxAmount.call(ctx, 15, 10)).toBe(2);
    expect(proto.calculateTaxAmount.call(ctx, -15, 10)).toBe(-2);
  });

  it("UP は 0 から離れて切り上げる", () => {
    const ctx = board({ taxRoundingMode: "UP" });
    expect(proto.calculateTaxAmount.call(ctx, 11, 10)).toBe(2);
    expect(proto.calculateTaxAmount.call(ctx, -11, 10)).toBe(-2);
  });

  it("丸め設定が空なら 0方向へ落とさない", () => {
    const ctx = board({});
    expect(Number.isNaN(proto.calculateTaxAmount.call(ctx, 15, 10))).toBe(true);
  });

  it("boardがOFFでもbundleがONなら確認に検収終了日を出す (Core 7.7.2 / 6.6)", () => {
    const ctx = {
      accountingEnabledOnBoard: false,
      invoiceUiState: {
        a00INV000000001: { bundle: { accountingEnabled: true } }
      },
      isAccountingEnabledForBoard: proto.isAccountingEnabledForBoard
    };
    expect(proto.resetPostOrderConfirmMessage.call(ctx)).toContain(
      "検収終了日"
    );
  });

  it("Accounting OFFの確認に検収終了日を出さない (Core 7.7.2 / 6.6)", () => {
    const ctx = {
      accountingEnabledOnBoard: false,
      invoiceUiState: {},
      isAccountingEnabledForBoard: proto.isAccountingEnabledForBoard
    };
    expect(proto.resetPostOrderConfirmMessage.call(ctx)).not.toContain(
      "検収終了日"
    );
  });

  it("送付状態NotApplicableを未送付と出さない (Core 7.11)", () => {
    expect(proto.deliveryStatusLabel("NotApplicable")).toBe("対象外");
    expect(proto.sentDateDisplay("", "NotApplicable")).toBe("対象外");
    expect(proto.sentDateDisplay("", "Unsent")).toBe("未送付");
    expect(proto.sentDateDisplay("2026-06-10", "Sent")).toBe("2026-06-10");
  });

  it("請求送付の添付名空白のみは空として扱う (Core 7.10 / 1.1.10)", () => {
    expect(proto.isBlankReasonText("   ")).toBe(true);
    expect(proto.isBlankReasonText("invoice.pdf")).toBe(false);
  });

  it("Unlock理由空白のみは空として扱う (Accounting 9.5 / Core 1.1.10)", () => {
    expect(proto.isBlankReasonText("   ")).toBe(true);
    expect(proto.isBlankReasonText("監査のため")).toBe(false);
  });

  it("検収終了日の空欄は画面で止める (Core 7.6 / 7.7.3 / 1.1.10)", async () => {
    const dispatchEvent = jest.fn();
    await proto.handleAcceptanceEndDateChange.call(
      {
        canEdit: true,
        isSaving: false,
        findLine: () => ({
          revenueRecognitionBasis: "一括計上",
          acceptanceEndDate: "2027-03-31"
        }),
        preview: {
          invoices: [
            {
              invoiceId: "a00INV000000001",
              lines: [{ lineId: "a01LINE00000001" }]
            }
          ]
        },
        invoiceUiState: {
          a00INV000000001: { bundle: { accountingEnabled: true } }
        },
        dispatchEvent
      },
      {
        currentTarget: { dataset: { lineId: "a01LINE00000001" } },
        detail: { value: "" }
      }
    );
    expect(dispatchEvent).toHaveBeenCalled();
    const event = dispatchEvent.mock.calls[0][0];
    expect(event.detail.message).toBe("検収終了日は空にできません。");
    expect(event.type).not.toBe("saveacceptanceenddate");
  });

  it("請求送付のTo空白のみと不正アドレスを止める (Core 7.10 / 1.1.10)", () => {
    expect(proto.isBlankReasonText("   ")).toBe(true);
    expect(proto.hasInvalidEmailList("not-an-email")).toBe(true);
    expect(proto.hasInvalidEmailList("a@example.com, bad")).toBe(true);
    expect(proto.hasInvalidEmailList("a@example.com, b@example.com")).toBe(
      false
    );
    expect(proto.hasInvalidEmailList("   ")).toBe(false);
  });

  it("Accounting OFFの確定確認に仕訳を出さない (Accounting 1.1 / Core 7.9)", () => {
    expect(
      proto.confirmInvoiceMessage.call({ accountingEnabledOnBoard: false })
    ).toBe(
      "この請求を確定します。確定後は内容がロックされます。よろしいですか？"
    );
  });

  it("Accounting ONの確定確認は仕訳作成を出す (Accounting 1.1 / Core 7.9)", () => {
    expect(
      proto.confirmInvoiceMessage.call({ accountingEnabledOnBoard: true })
    ).toContain("仕訳が作成されます");
  });
});
