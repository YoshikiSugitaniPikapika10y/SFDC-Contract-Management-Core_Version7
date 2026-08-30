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

describe("orderInvoicePreviewTable invoice cancel gate (Core 7.9.3 / 7.7.3 / 1.1.10)", () => {
  const proto = OrderInvoicePreviewTable.prototype;

  it("有効な請求入出金がある請求は取消できない", () => {
    expect(
      proto.invoiceCancelBlockedReason.call(proto, {
        payments: [{ paymentTransactionStatus: "Active" }]
      })
    ).toBe("有効な請求入出金がある請求は取消できません。");
  });

  it("取消済み入出金だけなら入出金では止めない", () => {
    expect(
      proto.invoiceCancelBlockedReason.call(proto, {
        payments: [{ paymentTransactionStatus: "Cancelled" }]
      })
    ).toBe("");
  });

  it("有効な手動仕訳がある請求は取消できない", () => {
    expect(
      proto.invoiceCancelBlockedReason.call(proto, {
        payments: [],
        manualJournals: [{ transactionStatus: "Active" }]
      })
    ).toBe("有効な手動仕訳がある請求は取消できません。");
  });

  it("その他の理由テキスト空白のみは取消を進めない (Core 7.9.5 / 1.1.10)", async () => {
    const dispatchEvent = jest.fn();
    await proto.handleConfirmInvoiceCancel.call({
      invoiceCancelState: {
        invoiceId: "a00INV000000001",
        cancellationReason: "Other",
        cancellationReasonText: "   "
      },
      invoiceUiState: { a00INV000000001: { bundle: {} } },
      invoiceCancelBlockedReason: () => "",
      isBlankReasonText: proto.isBlankReasonText,
      dispatchEvent
    });
    expect(dispatchEvent).toHaveBeenCalled();
    const event = dispatchEvent.mock.calls[0][0];
    expect(event.detail.message).toBe(
      "取消理由がその他のときは内容を入力してください。"
    );
  });
});
