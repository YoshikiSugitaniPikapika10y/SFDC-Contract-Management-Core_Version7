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

describe("estimateWizardCustomFieldGrid number step (Core 第11.4.1節)", () => {
  it("数値は小数点の位置。0なら整数。通貨は刻みを付けない", () => {
    const ctx = {
      fields: [
        { apiName: "Rate__c", fieldType: "DOUBLE", scale: 6 },
        { apiName: "Count__c", fieldType: "DOUBLE", scale: 0 },
        { apiName: "Money__c", fieldType: "CURRENCY", scale: 2 }
      ]
    };
    const views = Object.getOwnPropertyDescriptor(
      EstimateWizardCustomFieldGrid.prototype,
      "viewFields"
    ).get.call(ctx);
    expect(views[0].numberStep).toBe("0.000001");
    expect(views[1].numberStep).toBe("1");
    expect(views[2].numberStep).toBeUndefined();
  });
});
