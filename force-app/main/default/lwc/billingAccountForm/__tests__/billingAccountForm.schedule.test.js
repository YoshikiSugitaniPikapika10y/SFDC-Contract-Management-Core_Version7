import {
  applyClearedScheduleFields,
  invoiceDateMethodHelp,
  isBillingScheduleFieldVisible,
  isInvoiceDateFieldVisible,
  parseDefaultFieldValues,
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

  it("parses related-list defaults and omits key on edit save (Core 3.3.2 / 3.3.3)", () => {
    expect(
      parseDefaultFieldValues("Account__c=001xx000000BA01,Name=FromRelated")
    ).toEqual({
      Account__c: "001xx000000BA01",
      Name: "FromRelated"
    });
    const form = { submit: jest.fn() };
    BillingAccountForm.prototype.handleSubmit.call(
      {
        isSaving: false,
        isNew: false,
        draft: { InvoiceDateMethod__c: METHOD_SAME_DAY },
        template: { querySelector: () => form }
      },
      {
        preventDefault: jest.fn(),
        detail: {
          fields: {
            BillingAccountKey__c: "SHOULD-NOT-SAVE",
            Name: "Edited"
          }
        }
      }
    );
    expect(form.submit.mock.calls[0][0].BillingAccountKey__c).toBeUndefined();
    expect(form.submit.mock.calls[0][0].Name).toBe("Edited");
  });

  it("applies Aura defaultFieldValues onto Account (Core 3.3.2)", () => {
    const proto = BillingAccountForm.prototype;
    const self = { draft: {} };
    proto.applyDefaultFieldValues.call(
      self,
      "Account__c=001xx000000BA01,Name=FromRelated"
    );
    expect(self.draft.Account__c).toBe("001xx000000BA01");
    expect(self.draft.Name).toBe("FromRelated");
    const accountIdValue = Object.getOwnPropertyDescriptor(
      proto,
      "accountIdValue"
    ).get;
    expect(accountIdValue.call(self)).toBe("001xx000000BA01");
  });

  it("uses the same 7.2 / 7.5 method help as the order confirmation (Core 3.3.2 / 7.2 / 7.5)", () => {
    expect(invoiceDateMethodHelp(METHOD_ON_OR_AFTER)).toContain(
      "請求基準日以後で最初に到来する指定日または月末"
    );
    expect(invoiceDateMethodHelp(METHOD_MONTH_OFFSET)).toContain(
      "指定した月数だけ前後へ移動した月"
    );
    expect(paymentTermMethodHelp(METHOD_MONTH_OFFSET)).toContain(
      "当月、翌月、翌々月等の指定日または月末"
    );
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

  it("treats Aura override with recordId as Edit when page action is empty (Core 3.3.2)", () => {
    const proto = BillingAccountForm.prototype;
    const isNew = Object.getOwnPropertyDescriptor(proto, "isNew").get;
    const isEdit = Object.getOwnPropertyDescriptor(proto, "isEdit").get;
    const isView = Object.getOwnPropertyDescriptor(proto, "isView").get;
    const ctx = {
      formMode: "edit",
      recordId: "a00xx0000000001AAA",
      actionName: ""
    };
    expect(isNew.call(ctx)).toBe(false);
    expect(isEdit.call(ctx)).toBe(true);
    ctx.isNew = false;
    ctx.isEdit = true;
    expect(isView.call(ctx)).toBe(false);
  });
});
