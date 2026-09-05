import BillingAccountForm from "c/billingAccountForm";

jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);

describe("billingAccountForm busy (Core 3.3.2 / 4.3.12)", () => {
  const proto = BillingAccountForm.prototype;

  it("保存中は二度目の保存をしない", () => {
    const form = { submit: jest.fn() };
    const event = { preventDefault: jest.fn(), detail: { fields: {} } };
    proto.handleSubmit.call(
      {
        isSaving: true,
        isNew: true,
        draft: {},
        template: { querySelector: () => form }
      },
      event
    );
    expect(event.preventDefault).toHaveBeenCalled();
    expect(form.submit).not.toHaveBeenCalled();
  });

  it("保存中はキャンセルしない", () => {
    const ctx = { isSaving: true, dispatchEvent: jest.fn(), recordId: "a00" };
    proto.handleCancel.call(ctx);
    expect(ctx.dispatchEvent).not.toHaveBeenCalled();
  });

  it("保存開始後は処理中になる", () => {
    const form = { submit: jest.fn() };
    const ctx = {
      isSaving: false,
      isNew: true,
      draft: {},
      template: { querySelector: () => form }
    };
    proto.handleSubmit.call(ctx, {
      preventDefault: jest.fn(),
      detail: { fields: { Name: "A" } }
    });
    expect(ctx.isSaving).toBe(true);
    expect(form.submit).toHaveBeenCalled();
  });
});
