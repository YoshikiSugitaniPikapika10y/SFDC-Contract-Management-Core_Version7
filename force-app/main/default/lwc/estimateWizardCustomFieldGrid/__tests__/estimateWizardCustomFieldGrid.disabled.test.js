import EstimateWizardCustomFieldGrid from "c/estimateWizardCustomFieldGrid";

describe("estimateWizardCustomFieldGrid disabled (Core 4.3.12)", () => {
  const proto = EstimateWizardCustomFieldGrid.prototype;

  it("disabledなら変更イベントを出さない", () => {
    const ctx = {
      disabled: true,
      fields: [{ apiName: "X__c", fieldType: "TEXT" }],
      dispatchEvent: jest.fn()
    };
    proto.handleFieldChange.call(ctx, {
      currentTarget: { dataset: { field: "X__c" } },
      target: { value: "n" }
    });
    expect(ctx.dispatchEvent).not.toHaveBeenCalled();
  });
});
