import {
  applyClearedScheduleFields,
  invoiceDateMethodHelp,
  isBillingScheduleFieldVisible,
  isInvoiceDateFieldVisible,
  paymentTermMethodHelp,
  METHOD_DAY_OFFSET,
  METHOD_MONTH_OFFSET,
  METHOD_ON_OR_AFTER,
  METHOD_SAME_DAY,
  DAY_KIND_DAY
} from "c/billingAccountForm";
import BillingAccountForm from "c/billingAccountForm";

jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);

describe("billingAccountForm schedule visibility (Core 3.3.2 / 7.2 / 7.5)", () => {
  it("hides unused invoice date fields for SameDay and clears them on switch", () => {
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateMonthOffset__c",
        METHOD_SAME_DAY,
        DAY_KIND_DAY
      )
    ).toBe(false);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateDayOfMonth__c",
        METHOD_SAME_DAY,
        DAY_KIND_DAY
      )
    ).toBe(false);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateMethod__c",
        METHOD_SAME_DAY,
        DAY_KIND_DAY
      )
    ).toBe(true);

    const cleared = applyClearedScheduleFields({
      InvoiceDateMethod__c: METHOD_SAME_DAY,
      InvoiceDateAdjust__c: "None",
      InvoiceDateDayKind__c: DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c: 15,
      InvoiceDateMonthOffset__c: 1,
      InvoiceDateDayOffset__c: 3
    });
    expect(cleared.InvoiceDateDayKind__c).toBeNull();
    expect(cleared.InvoiceDateDayOfMonth__c).toBeNull();
    expect(cleared.InvoiceDateMonthOffset__c).toBeNull();
    expect(cleared.InvoiceDateDayOffset__c).toBeNull();
    expect(cleared.InvoiceDateAdjust__c).toBe("None");
  });

  it("shows day-of-month only when day kind is Day (Core 7.2)", () => {
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateDayOfMonth__c",
        METHOD_ON_OR_AFTER,
        "MonthEnd"
      )
    ).toBe(false);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateDayOfMonth__c",
        METHOD_ON_OR_AFTER,
        DAY_KIND_DAY
      )
    ).toBe(true);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateMonthOffset__c",
        METHOD_MONTH_OFFSET,
        DAY_KIND_DAY
      )
    ).toBe(true);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateDayOffset__c",
        METHOD_DAY_OFFSET,
        null
      )
    ).toBe(true);
  });

  it("clears unused payment term fields on DayOffset (Core 7.5)", () => {
    const cleared = applyClearedScheduleFields({
      PaymentTermMethod__c: METHOD_DAY_OFFSET,
      PaymentTermAdjust__c: "None",
      PaymentTermDayKind__c: DAY_KIND_DAY,
      PaymentTermDayOfMonth__c: 10,
      PaymentTermMonthOffset__c: 1,
      PaymentTermDayOffset__c: 0
    });
    expect(cleared.PaymentTermDayKind__c).toBeNull();
    expect(cleared.PaymentTermDayOfMonth__c).toBeNull();
    expect(cleared.PaymentTermMonthOffset__c).toBeNull();
    expect(cleared.PaymentTermDayOffset__c).toBe(0);
    expect(
      isBillingScheduleFieldVisible("PaymentTermMonthOffset__c", {
        PaymentTermMethod__c: METHOD_DAY_OFFSET
      })
    ).toBe(false);
  });

  it("uses short method help without date examples (Core 7.2 / 7.5)", () => {
    const invoiceHelp = invoiceDateMethodHelp(METHOD_SAME_DAY);
    const paymentHelp = paymentTermMethodHelp(METHOD_DAY_OFFSET);
    expect(invoiceHelp).toContain("請求基準日をそのまま請求日とする");
    expect(paymentHelp).toContain("0日は即日払い");
    expect(invoiceHelp + paymentHelp).not.toMatch(/\d{4}[/-]/);
    expect(invoiceHelp + paymentHelp).not.toContain("6/1");
    expect(invoiceHelp + paymentHelp).not.toContain("例:");
  });

  it("shows View without 19 and hides New when createable is false (共通基盤 10.4)", () => {
    const proto = BillingAccountForm.prototype;
    const showForm = Object.getOwnPropertyDescriptor(proto, "showForm").get;
    const denied = Object.getOwnPropertyDescriptor(
      proto,
      "permissionDeniedMessage"
    ).get;
    const showEdit = Object.getOwnPropertyDescriptor(proto, "showEditButton")
      .get;

    expect(
      showForm.call({
        isView: true,
        isNew: false,
        canCreate: false,
        canUpdate: false
      })
    ).toBe(true);
    expect(
      showEdit.call({
        isView: true,
        canUpdate: false
      })
    ).toBe(false);
    expect(
      denied.call({
        isView: false,
        isNew: true,
        showForm: false
      })
    ).toBe("請求アカウントを作る権限がありません。");
  });
});
