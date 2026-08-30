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

describe("orderInvoicePreviewTable billing header (Core 7.8)", () => {
  const proto = OrderInvoicePreviewTable.prototype;

  it("請求情報編集の保存に税率を載せない", async () => {
    const dispatchEvent = jest.fn();
    await proto.handleSaveBillingHeader.call({
      billingEditState: {
        invoiceId: "a00INV000000001",
        invoiceDate: "2026-06-01",
        paymentScheduledDate: "2026-07-31",
        extraFieldValues: {}
      },
      isSaving: false,
      hasAmountDrafts: false,
      preview: { invoiceLockExemptFieldApiNames: [] },
      findInvoice: () => ({ extraFieldValues: {}, lastModifiedToken: "1" }),
      extraFieldValuesFromViews: () => ({}),
      buildExtraFieldViews: () => [],
      isConfirmedInvoice: () => false,
      resolvePendingOperationKey: async () => "k1",
      dispatchEvent
    });
    const event = dispatchEvent.mock.calls[0][0];
    expect(event.type).toBe("savebillingheader");
    expect(event.detail.taxPercent).toBeUndefined();
  });
});
