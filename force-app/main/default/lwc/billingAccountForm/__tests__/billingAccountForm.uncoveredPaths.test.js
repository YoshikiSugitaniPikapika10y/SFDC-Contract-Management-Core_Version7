import BillingAccountForm, {
  applyClearedScheduleFields,
  invoiceDateMethodHelp,
  isBillingScheduleFieldVisible,
  isPaymentTermFieldVisible,
  METHOD_DAY_OFFSET,
  METHOD_MONTH_OFFSET,
  METHOD_ON_OR_AFTER,
  METHOD_SAME_DAY,
  DAY_KIND_DAY,
  parseDefaultFieldValues
} from "c/billingAccountForm";
import { getFieldValue } from "lightning/uiRecordApi";

jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);
jest.mock(
  "lightning/navigation",
  () => {
    const Navigate = Symbol.for("NavigationMixin.Navigate");
    return {
      NavigationMixin: Object.assign(
        (Base) =>
          class extends Base {
            [Navigate]() {}
          },
        { Navigate }
      ),
      CurrentPageReference: class CurrentPageReference {}
    };
  },
  { virtual: true }
);
jest.mock(
  "lightning/uiObjectInfoApi",
  () => ({ getObjectInfo: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/uiRecordApi",
  () => ({
    getRecord: jest.fn(),
    getFieldValue: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c",
  () => ({ default: { objectApiName: "BillingAccount__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c.InvoiceDateMethod__c",
  () => ({ default: { fieldApiName: "InvoiceDateMethod__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c.InvoiceDateDayKind__c",
  () => ({ default: { fieldApiName: "InvoiceDateDayKind__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c.InvoiceDateDayOfMonth__c",
  () => ({ default: { fieldApiName: "InvoiceDateDayOfMonth__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c.InvoiceDateMonthOffset__c",
  () => ({ default: { fieldApiName: "InvoiceDateMonthOffset__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c.InvoiceDateDayOffset__c",
  () => ({ default: { fieldApiName: "InvoiceDateDayOffset__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c.InvoiceDateAdjust__c",
  () => ({ default: { fieldApiName: "InvoiceDateAdjust__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c.PaymentTermMethod__c",
  () => ({ default: { fieldApiName: "PaymentTermMethod__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c.PaymentTermDayKind__c",
  () => ({ default: { fieldApiName: "PaymentTermDayKind__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c.PaymentTermDayOfMonth__c",
  () => ({ default: { fieldApiName: "PaymentTermDayOfMonth__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c.PaymentTermMonthOffset__c",
  () => ({ default: { fieldApiName: "PaymentTermMonthOffset__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c.PaymentTermDayOffset__c",
  () => ({ default: { fieldApiName: "PaymentTermDayOffset__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c.PaymentTermAdjust__c",
  () => ({ default: { fieldApiName: "PaymentTermAdjust__c" } }),
  { virtual: true }
);

const proto = BillingAccountForm.prototype;
const Navigate = Symbol.for("NavigationMixin.Navigate");

function bind(overrides = {}) {
  const ctx = {
    recordId: "a00BA0000000001",
    objectApiName: "BillingAccount__c",
    formMode: "edit",
    _defaultFieldValues: "",
    _pageRef: { attributes: { actionName: "edit" } },
    _objectInfo: { createable: true, updateable: true },
    draft: { InvoiceDateMethod__c: METHOD_SAME_DAY },
    errorMessage: "",
    isSaving: false,
    template: { querySelector: jest.fn(() => ({ submit: jest.fn() })) },
    dispatchEvent: jest.fn(),
    [Navigate]: jest.fn(),
    ...overrides
  };
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor") {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (!desc || (desc.get && desc.set)) {
      return;
    }
    if (Object.prototype.hasOwnProperty.call(ctx, name)) {
      return;
    }
    if (desc.get && !desc.set) {
      Object.defineProperty(ctx, name, { get: desc.get, configurable: true });
    } else if (typeof desc.value === "function") {
      ctx[name] = desc.value;
    }
  });
  return ctx;
}

describe("billingAccountForm uncovered (Core 3.3.2 / 3.3.3 / 7.2 / 7.5)", () => {
  it("page titles are 作成／編集／請求アカウント (Core 3.3.3)", () => {
    expect(bind({ formMode: "new", recordId: "" }).pageTitle).toBe(
      "請求アカウントを作成"
    );
    expect(bind({ formMode: "edit" }).pageTitle).toBe("請求アカウントを編集");
    expect(bind({ formMode: "view" }).pageTitle).toBe("請求アカウント");
  });

  it("permission denied copy is この操作の権限がありません。", () => {
    const ctx = bind({
      formMode: "new",
      recordId: "",
      _objectInfo: { createable: false, updateable: false }
    });
    expect(ctx.permissionDeniedMessage).toBe("この操作の権限がありません。");
    expect(ctx.showForm).toBe(false);
  });

  it("schedule visibility for DayOffset and unknown method (Core 7.2 / 7.5)", () => {
    expect(
      isPaymentTermFieldVisible("PaymentTermDayOffset__c", METHOD_DAY_OFFSET)
    ).toBe(true);
    expect(
      isPaymentTermFieldVisible("PaymentTermMonthOffset__c", METHOD_DAY_OFFSET)
    ).toBe(false);
    expect(isBillingScheduleFieldVisible("BillingAddressee__c", {})).toBe(
      true
    );
    expect(invoiceDateMethodHelp("Unknown")).toBe("");
  });

  it("parseDefaultFieldValues skips junk pairs", () => {
    expect(parseDefaultFieldValues(null)).toEqual({});
    expect(parseDefaultFieldValues("nolink")).toEqual({});
  });

  it("wiredObjectInfo error denies create/update", () => {
    const ctx = bind({ _objectInfo: undefined });
    ctx.wiredObjectInfo({ error: { message: "no access" } });
    expect(ctx.canCreate).toBe(false);
    expect(ctx.canUpdate).toBe(false);
  });

  it("wiredRecord fills draft methods", () => {
    getFieldValue.mockImplementation((_data, field) => field.fieldApiName);
    const ctx = bind({ draft: {} });
    ctx.wiredRecord({ data: { fields: {} } });
    expect(ctx.draft.InvoiceDateMethod__c).toBeDefined();
  });

  it("handleFieldChange clears hidden schedule fields (Core 7.2)", () => {
    const ctx = bind({
      isSaving: false,
      draft: { InvoiceDateMethod__c: METHOD_ON_OR_AFTER }
    });
    ctx.handleFieldChange({
      target: { fieldName: "InvoiceDateMethod__c" },
      detail: { value: METHOD_SAME_DAY }
    });
    expect(ctx.draft.InvoiceDateMethod__c).toBe(METHOD_SAME_DAY);
    ctx.isSaving = true;
    ctx.handleFieldChange({
      target: { fieldName: "InvoiceDateMethod__c" },
      detail: { value: METHOD_DAY_OFFSET }
    });
    expect(ctx.draft.InvoiceDateMethod__c).toBe(METHOD_SAME_DAY);
  });

  it("handleError uses 保存できませんでした。 fallback", () => {
    const ctx = bind();
    ctx.handleError({ detail: {} });
    expect(ctx.errorMessage).toBe("保存できませんでした。");
    ctx.handleError({ detail: { detail: "入力規則" } });
    expect(ctx.errorMessage).toBe("入力規則");
  });

  it("cancel navigates to view or home (Core 3.3.3)", () => {
    const ctx = bind();
    ctx.handleCancel();
    expect(ctx[Navigate]).toHaveBeenCalled();
    const neu = bind({ recordId: "", formMode: "new" });
    neu.handleCancel();
    expect(neu[Navigate]).toHaveBeenCalled();
    ctx.isSaving = true;
    ctx[Navigate].mockClear();
    ctx.handleCancel();
    expect(ctx[Navigate]).not.toHaveBeenCalled();
  });

  it("open edit requires updateable (共通基盤 10.4)", () => {
    const ctx = bind({
      formMode: "view",
      _objectInfo: { updateable: true }
    });
    ctx.handleOpenEdit();
    expect(ctx[Navigate]).toHaveBeenCalled();
    const denied = bind({
      formMode: "view",
      _objectInfo: { updateable: false }
    });
    denied.handleOpenEdit();
    expect(denied[Navigate]).not.toHaveBeenCalled();
  });

  it("handleSuccess navigates to view", () => {
    const ctx = bind();
    ctx.handleSuccess({ detail: { id: "a00NEW" } });
    expect(ctx.isSaving).toBe(false);
    expect(ctx[Navigate]).toHaveBeenCalled();
  });

  it("show invoice/payment offsets follow method (Core 7.2 / 7.5)", () => {
    const month = bind({
      draft: {
        InvoiceDateMethod__c: METHOD_MONTH_OFFSET,
        InvoiceDateDayKind__c: DAY_KIND_DAY,
        PaymentTermMethod__c: METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c: DAY_KIND_DAY
      }
    });
    expect(month.showInvoiceMonthOffset).toBe(true);
    expect(month.showInvoiceDayKind).toBe(true);
    expect(month.showPaymentMonthOffset).toBe(true);
    const day = bind({
      draft: {
        InvoiceDateMethod__c: METHOD_DAY_OFFSET,
        PaymentTermMethod__c: METHOD_DAY_OFFSET
      }
    });
    expect(day.showInvoiceDayOffset).toBe(true);
    expect(day.showPaymentDayOffset).toBe(true);
    expect(month.hasInvoiceDateHelp).toBe(true);
    expect(month.hasPaymentTermHelp).toBe(true);
  });

  it("wiredPageRef applies related-list defaults when no recordId (Core 3.3.2)", () => {
    const ctx = bind({ recordId: "", draft: {} });
    ctx.wiredPageRef({
      attributes: { actionName: "new" },
      state: { defaultFieldValues: "Account__c=001AAA" }
    });
    expect(ctx.draft.Account__c).toBe("001AAA");
  });
});
