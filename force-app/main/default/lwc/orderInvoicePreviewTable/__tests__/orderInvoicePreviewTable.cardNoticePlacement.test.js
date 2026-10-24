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

const INVOICE = "a00INV000000001";
const LINE = "a01LINE00000001";
const PAYMENT = "a0P000000000001";

let OrderInvoicePreviewTable;

beforeAll(async () => {
  global.__lwcJestMock_previewCancelConfirmed = jest.fn();
  global.__lwcJestMock_previewCancelPaymentFromPreview = jest.fn();
  global.__lwcJestMock_previewInvoiceLineAcceptanceEndDate = jest.fn();
  global.__lwcJestMock_previewIssueInvoice = jest.fn();
  const mod = await import("c/orderInvoicePreviewTable");
  OrderInvoicePreviewTable = mod.default;
});

function placeCtx(extra) {
  const proto = OrderInvoicePreviewTable.prototype;
  return {
    surfaceError: "",
    cardNotice: null,
    completionNote: "",
    contractHistoryId: "a0H000000000001",
    beginCardNotice: proto.beginCardNotice,
    setSurfaceError: proto.setSurfaceError,
    reduceInvoiceOpsError: proto.reduceInvoiceOpsError,
    ...extra
  };
}

describe("orderInvoicePreviewTable card notice placement (Core 7.7.0)", () => {
  it("請求取消の拒否はカードの取消に出し、最上部には出さない", async () => {
    const proto = OrderInvoicePreviewTable.prototype;
    const ctx = placeCtx({
      invoiceUiState: {
        [INVOICE]: {
          bundle: { payments: [{ paymentTransactionStatus: "Active" }] }
        }
      },
      invoiceCancelBlockedReason: proto.invoiceCancelBlockedReason,
      isInactivePayment: proto.isInactivePayment,
      paymentTransactionStatus: proto.paymentTransactionStatus
    });
    await proto.handleOpenInvoiceCancel.call(ctx, {
      currentTarget: { dataset: { invoiceId: INVOICE } }
    });
    expect(ctx.surfaceError).toBe("");
    expect(ctx.invoiceCancelState).toBeUndefined();
    expect(ctx.cardNotice).toMatchObject({
      invoiceId: INVOICE,
      anchor: "cancel",
      text: "有効な請求入出金がある請求は取消できません。",
      reload: true
    });
  });

  it("請求取消を開くプレビュー失敗はカードの取消に出す", async () => {
    const proto = OrderInvoicePreviewTable.prototype;
    global.__lwcJestMock_previewCancelConfirmed.mockRejectedValue({
      body: { message: "取消基準日を読めません。" }
    });
    const ctx = placeCtx({
      invoiceUiState: {
        [INVOICE]: { bundle: { payments: [], hasLockedJournals: true } }
      },
      todayLocalIso: () => "2026-10-19",
      invoiceCancelBlockedReason: proto.invoiceCancelBlockedReason,
      isInactivePayment: proto.isInactivePayment,
      paymentTransactionStatus: proto.paymentTransactionStatus
    });
    await proto.handleOpenInvoiceCancel.call(ctx, {
      currentTarget: { dataset: { invoiceId: INVOICE } }
    });
    expect(ctx.surfaceError).toBe("");
    expect(ctx.invoiceCancelState).toBeUndefined();
    expect(ctx.cardNotice).toMatchObject({
      invoiceId: INVOICE,
      anchor: "cancel",
      text: "取消基準日を読めません。",
      reload: true
    });
  });

  it("入出金取消を開くプレビュー失敗は、その入出金の取消に出す", async () => {
    const proto = OrderInvoicePreviewTable.prototype;
    global.__lwcJestMock_previewCancelPaymentFromPreview.mockRejectedValue({
      body: { message: "入出金を読めません。" }
    });
    const ctx = placeCtx({
      invoiceOpsProcessingId: null,
      findInvoice: () => ({ invoiceName: "INV-1" }),
      invoiceUiState: {
        [INVOICE]: {
          bundle: {
            payments: [{ paymentId: PAYMENT, paymentPurpose: "Invoice" }]
          }
        }
      }
    });
    await proto.handlePaymentCancel.call(ctx, {
      currentTarget: {
        dataset: { invoiceId: INVOICE, paymentId: PAYMENT }
      }
    });
    expect(ctx.surfaceError).toBe("");
    expect(ctx.invoiceUiState[INVOICE].cancelDraft).toBeUndefined();
    expect(ctx.cardNotice).toMatchObject({
      invoiceId: INVOICE,
      anchor: "paymentCancel",
      rowId: PAYMENT,
      text: "入出金を読めません。",
      reload: true
    });
  });

  it("検収終了日の変更プレビュー失敗は、その明細のそばに出す", async () => {
    const proto = OrderInvoicePreviewTable.prototype;
    global.__lwcJestMock_previewInvoiceLineAcceptanceEndDate.mockRejectedValue({
      body: { message: "検収終了日を読めません。" }
    });
    const ctx = placeCtx({
      canEdit: true,
      isSaving: false,
      findLine: () => ({
        revenueRecognitionBasis: "一括計上",
        acceptanceEndDate: "2027-03-31"
      }),
      preview: {
        invoices: [{ invoiceId: INVOICE, lines: [{ lineId: LINE }] }]
      },
      invoiceUiState: { [INVOICE]: { bundle: {} } }
    });
    await proto.handleAcceptanceEndDateChange.call(ctx, {
      currentTarget: { dataset: { lineId: LINE } },
      detail: { value: "2027-04-30" }
    });
    expect(ctx.surfaceError).toBe("");
    expect(ctx.cardNotice).toMatchObject({
      invoiceId: INVOICE,
      anchor: "acceptance",
      rowId: LINE,
      text: "検収終了日を読めません。",
      reload: true
    });
  });

  it("検収終了日の保存失敗は、行識別子があるときその明細の直下に出す", () => {
    const proto = OrderInvoicePreviewTable.prototype;
    const ctx = placeCtx();
    proto.showCardNotice.call(
      ctx,
      INVOICE,
      "acceptance",
      "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。",
      true,
      LINE
    );
    expect(ctx.surfaceError).toBe("");
    expect(ctx.cardNotice).toMatchObject({
      invoiceId: INVOICE,
      anchor: "acceptance",
      rowId: LINE,
      text: "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。",
      reload: true
    });
  });

  it("行識別子の無いカード通知は、検収終了日の直下には出さない", () => {
    const proto = OrderInvoicePreviewTable.prototype;
    const ctx = placeCtx();
    proto.showCardNotice.call(ctx, INVOICE, "acceptance", "請求情報を保存しました。", false);
    expect(ctx.surfaceError).toBe("");
    expect(ctx.cardNotice.rowId).toBeUndefined();
    expect(ctx.cardNotice.text).toBe("請求情報を保存しました。");
  });

  it("発行の帳票変更プレビュー失敗はパネルの中に残し、最上部には出さない", async () => {
    const proto = OrderInvoicePreviewTable.prototype;
    global.__lwcJestMock_previewIssueInvoice.mockRejectedValue({
      body: { message: "帳票を読めません。" }
    });
    const ctx = placeCtx({
      reloadInvoiceIssuePreview: proto.reloadInvoiceIssuePreview,
      invoiceIssueState: {
        invoiceId: INVOICE,
        documentTemplateKey: "OLD",
        fileName: "a.pdf"
      }
    });
    await proto.handleInvoiceIssueTemplateChange.call(ctx, {
      detail: { value: "NEW" }
    });
    expect(ctx.surfaceError).toBe("");
    expect(ctx.cardNotice).toBeNull();
    expect(ctx.invoiceIssueState.previewFailed).toBe(true);
    expect(ctx.invoiceIssueState.previewError).toBe("帳票を読めません。");
    expect(ctx.invoiceIssueState.documentTemplateKey).toBe("NEW");
  });
});
