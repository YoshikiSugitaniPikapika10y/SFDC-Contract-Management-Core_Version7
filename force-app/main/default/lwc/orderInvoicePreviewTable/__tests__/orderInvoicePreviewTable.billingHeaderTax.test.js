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

describe("orderInvoicePreviewTable billing header tax (Core 4.6 / 7.8 / 1.1.10)", () => {
  const proto = OrderInvoicePreviewTable.prototype;

  it("税率0超〜1未満を画面で止める", async () => {
    const dispatchEvent = jest.fn();
    await proto.handleSaveBillingHeader.call({
      billingEditState: {
        invoiceId: "a00INV000000001",
        invoiceDate: "2026-06-01",
        paymentScheduledDate: "2026-07-31",
        taxPercent: 0.5
      },
      isSaving: false,
      hasAmountDrafts: false,
      dispatchEvent
    });
    expect(dispatchEvent).toHaveBeenCalled();
    const event = dispatchEvent.mock.calls[0][0];
    expect(event.detail.message).toBe(
      "税率は 0〜100 の数値で入力してください。"
    );
    expect(event.type).not.toBe("savebillingheader");
  });

  it("税率空を0で埋めない (Core 7.7.3 / 7.8 / 1.1.10)", () => {
    expect(proto.billingEditTaxPercent(null)).toBe("");
    expect(proto.billingEditTaxPercent("")).toBe("");
    expect(proto.billingEditTaxPercent("   ")).toBe("");
    expect(proto.billingEditTaxPercent(0)).toBe(0);
    expect(proto.billingEditTaxPercent(10)).toBe(10);
  });
});
