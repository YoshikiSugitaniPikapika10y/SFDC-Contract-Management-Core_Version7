import {
  applyClearedScheduleFields,
  invoiceDateMethodHelp,
  isBillingScheduleFieldVisible,
  isInvoiceDateFieldVisible,
  parseDefaultFieldValues,
  paymentTermMethodHelp,
  resolveNewAccountId,
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

const DAY_KIND_MONTH_END = "MonthEnd";

describe("billingAccountForm (Core 3.3.2 / 3.3.3 / 7.2 / 7.5, 共通基盤 10.4)", () => {
  const proto = BillingAccountForm.prototype;

  it("SameDay は日種別・指定日・月数・日数を出さず空にする (Core 7.2)", () => {
    ["InvoiceDateDayKind__c", "InvoiceDateDayOfMonth__c", "InvoiceDateMonthOffset__c", "InvoiceDateDayOffset__c"].forEach(
      (apiName) => {
        expect(
          isInvoiceDateFieldVisible(apiName, METHOD_SAME_DAY, DAY_KIND_DAY)
        ).toBe(false);
      }
    );
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateMethod__c",
        METHOD_SAME_DAY,
        DAY_KIND_DAY
      )
    ).toBe(true);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateAdjust__c",
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

  it("OnOrAfter は Day のときだけ指定日を出し、MonthEnd では空にする (Core 7.2)", () => {
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateDayOfMonth__c",
        METHOD_ON_OR_AFTER,
        DAY_KIND_MONTH_END
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
        "InvoiceDateDayKind__c",
        METHOD_ON_OR_AFTER,
        DAY_KIND_MONTH_END
      )
    ).toBe(true);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateMonthOffset__c",
        METHOD_ON_OR_AFTER,
        DAY_KIND_DAY
      )
    ).toBe(false);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateDayOffset__c",
        METHOD_ON_OR_AFTER,
        DAY_KIND_DAY
      )
    ).toBe(false);
  });

  it("MonthOffset は月数と日種別を出し、DayOffset は日数だけ出す (Core 7.2)", () => {
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateMonthOffset__c",
        METHOD_MONTH_OFFSET,
        DAY_KIND_DAY
      )
    ).toBe(true);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateDayKind__c",
        METHOD_MONTH_OFFSET,
        DAY_KIND_DAY
      )
    ).toBe(true);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateDayOffset__c",
        METHOD_MONTH_OFFSET,
        DAY_KIND_DAY
      )
    ).toBe(false);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateDayOffset__c",
        METHOD_DAY_OFFSET,
        null
      )
    ).toBe(true);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateDayKind__c",
        METHOD_DAY_OFFSET,
        DAY_KIND_DAY
      )
    ).toBe(false);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateDayOfMonth__c",
        METHOD_DAY_OFFSET,
        DAY_KIND_DAY
      )
    ).toBe(false);
    expect(
      isInvoiceDateFieldVisible(
        "InvoiceDateMonthOffset__c",
        METHOD_DAY_OFFSET,
        DAY_KIND_DAY
      )
    ).toBe(false);
  });

  it("支払条件 DayOffset は日種別・指定日・月数を空にし、MonthOffset は日数を出さない (Core 7.5)", () => {
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
    expect(
      isBillingScheduleFieldVisible("PaymentTermDayOffset__c", {
        PaymentTermMethod__c: METHOD_DAY_OFFSET
      })
    ).toBe(true);
    expect(
      isBillingScheduleFieldVisible("PaymentTermMonthOffset__c", {
        PaymentTermMethod__c: METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c: DAY_KIND_DAY
      })
    ).toBe(true);
    expect(
      isBillingScheduleFieldVisible("PaymentTermDayOfMonth__c", {
        PaymentTermMethod__c: METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c: DAY_KIND_MONTH_END
      })
    ).toBe(false);
    expect(
      isBillingScheduleFieldVisible("PaymentTermDayOffset__c", {
        PaymentTermMethod__c: METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c: DAY_KIND_DAY
      })
    ).toBe(false);
  });

  it("方式の説明は第7.2節・第7.5節の計算文であり日付例は出さない (Core 3.3.2)", () => {
    expect(invoiceDateMethodHelp(METHOD_SAME_DAY)).toContain(
      "請求基準日をそのまま請求日とする"
    );
    expect(invoiceDateMethodHelp(METHOD_ON_OR_AFTER)).toContain(
      "請求基準日以後で最初に到来する指定日または月末を請求日とする"
    );
    expect(invoiceDateMethodHelp(METHOD_ON_OR_AFTER)).toContain(
      "請求基準日自身が該当すれば同日とする"
    );
    expect(invoiceDateMethodHelp(METHOD_MONTH_OFFSET)).toContain(
      "請求基準日の属する暦月を0として、指定した月数だけ前後へ移動した月の指定日または月末を請求日とする"
    );
    expect(invoiceDateMethodHelp(METHOD_DAY_OFFSET)).toContain(
      "請求基準日に指定日数を加減した日を請求日とする"
    );
    expect(invoiceDateMethodHelp(METHOD_DAY_OFFSET)).toContain(
      "先行請求を表せるよう負数も許可する"
    );
    expect(paymentTermMethodHelp(METHOD_MONTH_OFFSET)).toContain(
      "請求日の属する暦月を0として、当月、翌月、翌々月等の指定日または月末を入金予定日とする"
    );
    expect(paymentTermMethodHelp(METHOD_DAY_OFFSET)).toContain(
      "請求日に0日以上の指定日数を加えた日を入金予定日とする"
    );
    expect(paymentTermMethodHelp(METHOD_DAY_OFFSET)).toContain(
      "0日は即日払いを表す"
    );
    const allHelp =
      invoiceDateMethodHelp(METHOD_SAME_DAY) +
      invoiceDateMethodHelp(METHOD_ON_OR_AFTER) +
      invoiceDateMethodHelp(METHOD_MONTH_OFFSET) +
      invoiceDateMethodHelp(METHOD_DAY_OFFSET) +
      paymentTermMethodHelp(METHOD_MONTH_OFFSET) +
      paymentTermMethodHelp(METHOD_DAY_OFFSET);
    expect(allHelp).not.toMatch(/\d{4}[/-]/);
    expect(allHelp).not.toContain("6/1");
    expect(allHelp).not.toContain("例:");
  });

  it("編集保存はキーを送らず、New だけキー入力を出す (Core 3.3.1 / 3.3.3)", () => {
    const showKeyInput = Object.getOwnPropertyDescriptor(
      proto,
      "showKeyInput"
    ).get;
    const showKeyOutput = Object.getOwnPropertyDescriptor(
      proto,
      "showKeyOutput"
    ).get;
    const showHasReference = Object.getOwnPropertyDescriptor(
      proto,
      "showHasReference"
    ).get;
    expect(showKeyInput.call({ isNew: true })).toBe(true);
    expect(showKeyOutput.call({ isNew: true })).toBe(false);
    expect(showHasReference.call({ isNew: true })).toBe(false);
    expect(showKeyInput.call({ isNew: false })).toBe(false);
    expect(showKeyOutput.call({ isNew: false })).toBe(true);
    expect(showHasReference.call({ isNew: false })).toBe(true);

    const form = { submit: jest.fn() };
    proto.handleSubmit.call(
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

  it("関連リスト新規の defaultFieldValues を取引先へ載せる (Core 3.3.2)", () => {
    expect(
      parseDefaultFieldValues("Account__c=001xx000000BA01,Name=FromRelated")
    ).toEqual({
      Account__c: "001xx000000BA01",
      Name: "FromRelated"
    });
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

  it("クリック元の取引先を New の初期値にする (Core 3.3.2)", () => {
    const payload = {
      type: "standard__recordPage",
      attributes: {
        recordId: "001xx000000ACC1",
        objectApiName: "Account",
        actionName: "view"
      }
    };
    const encoded =
      "1." + Buffer.from(JSON.stringify(payload), "utf8").toString("base64");
    expect(resolveNewAccountId({ inContextOfRef: encoded })).toBe(
      "001xx000000ACC1"
    );
    expect(
      resolveNewAccountId({
        backgroundContext: "/lightning/r/Account/001xx000000ACC2/view"
      })
    ).toBe("001xx000000ACC2");
    expect(
      resolveNewAccountId({
        href: "https://example.lightning.force.com/lightning/r/Account/001xx000000ACC3/view"
      })
    ).toBe("001xx000000ACC3");
    expect(
      resolveNewAccountId({
        defaultFieldValues: "Account__c=001FROMDEF000001",
        inContextOfRef: encoded
      })
    ).toBe("001FROMDEF000001");
    const opportunity = {
      type: "standard__recordPage",
      attributes: {
        recordId: "006xx000000OPP1",
        objectApiName: "Opportunity",
        actionName: "view"
      }
    };
    expect(
      resolveNewAccountId({
        inContextOfRef:
          "1." + Buffer.from(JSON.stringify(opportunity), "utf8").toString("base64")
      })
    ).toBe("");
    expect(parseDefaultFieldValues({ Account__c: "001OBJ000000001" })).toEqual({
      Account__c: "001OBJ000000001"
    });
    expect(parseDefaultFieldValues("Account__c%3D001ENC000000001")).toEqual({
      Account__c: "001ENC000000001"
    });
  });

  it("19 が無ければ New／Edit は出さず、View は出す (Core 3.3.2 / 共通基盤 10.4)", () => {
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
      showForm.call({
        isView: false,
        isNew: true,
        canCreate: false,
        canUpdate: false
      })
    ).toBe(false);
    expect(
      denied.call({
        isView: false,
        isNew: true,
        showForm: false
      })
    ).not.toBe("");
    expect(
      showForm.call({
        isView: false,
        isNew: false,
        canCreate: false,
        canUpdate: false
      })
    ).toBe(false);
    expect(
      denied.call({
        isView: false,
        isNew: false,
        showForm: false
      })
    ).not.toBe("");
    expect(
      showEdit.call({
        isView: true,
        canUpdate: true
      })
    ).toBe(true);
  });

  it("Aura 上書きで recordId があり action が空なら Edit とする (Core 3.3.2)", () => {
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
