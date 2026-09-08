import BillingAccountForm from "c/billingAccountForm";

jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);

describe("billingAccountForm save (Core 3.3.2)", () => {
  const proto = BillingAccountForm.prototype;

  it("保存を止める確認ゲートは置かず、応答前の連打は二度目を送らない", () => {
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
    expect(form.submit).toHaveBeenCalledTimes(1);

    proto.handleSubmit.call(ctx, {
      preventDefault: jest.fn(),
      detail: { fields: { Name: "A" } }
    });
    expect(form.submit).toHaveBeenCalledTimes(1);
  });

  it("保存の応答が返る前はキャンセルしない", () => {
    const ctx = { isSaving: true, dispatchEvent: jest.fn(), recordId: "a00" };
    proto.handleCancel.call(ctx);
    expect(ctx.dispatchEvent).not.toHaveBeenCalled();
  });
});
