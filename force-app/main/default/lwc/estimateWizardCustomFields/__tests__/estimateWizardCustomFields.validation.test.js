import {
  getCustomFieldTypeError,
  validateCustomFieldMaps,
  isCustomFieldVisible,
  coerceCustomFieldDefault,
  applyDefaultCustomFields,
  resolveCustomFieldDefault,
  syncCustomFieldsForVisibility,
  filterCustomFieldDefinitionsForWizardType,
  filterVisibleCustomFieldDefinitions,
  shallowEqualFieldMaps,
  buildCustomFieldInputs
} from "c/estimateWizardCustomFields";

describe("getCustomFieldTypeError", () => {
  it("allows blank values (required is separate)", () => {
    expect(getCustomFieldTypeError("DATE", "")).toBeNull();
    expect(getCustomFieldTypeError("INTEGER", null)).toBeNull();
    expect(getCustomFieldTypeError("DOUBLE", undefined)).toBeNull();
  });

  it("validates ISO dates", () => {
    expect(getCustomFieldTypeError("DATE", "2026-07-28")).toBeNull();
    expect(getCustomFieldTypeError("DATE", "2026-13-01")).toContain(
      "YYYY-MM-DD"
    );
    expect(getCustomFieldTypeError("DATE", "07/28/2026")).toContain(
      "YYYY-MM-DD"
    );
    expect(getCustomFieldTypeError("DATE", "2026-02-30")).toContain(
      "YYYY-MM-DD"
    );
  });

  it("validates integers", () => {
    expect(getCustomFieldTypeError("INTEGER", "12")).toBeNull();
    expect(getCustomFieldTypeError("LONG", -3)).toBeNull();
    expect(getCustomFieldTypeError("INTEGER", "12.5")).toContain("整数");
    expect(getCustomFieldTypeError("INTEGER", "abc")).toContain("整数");
  });

  it("validates decimals", () => {
    expect(getCustomFieldTypeError("DOUBLE", "12.5")).toBeNull();
    expect(getCustomFieldTypeError("CURRENCY", 100)).toBeNull();
    expect(getCustomFieldTypeError("PERCENT", "10%")).toContain("数値");
    expect(getCustomFieldTypeError("DOUBLE", "abc")).toContain("数値");
  });

  it("validates record references", () => {
    expect(
      getCustomFieldTypeError("REFERENCE", "005000000000001AAA")
    ).toBeNull();
    expect(getCustomFieldTypeError("REFERENCE", "not-an-id")).toContain(
      "レコード"
    );
  });
});

describe("validateCustomFieldMaps", () => {
  const definitions = [
    {
      apiName: "Memo__c",
      label: "メモ",
      fieldType: "STRING",
      required: true
    },
    {
      apiName: "AppDate__c",
      label: "申込日",
      fieldType: "DATE",
      required: false
    },
    {
      apiName: "Qty__c",
      label: "数量",
      fieldType: "INTEGER",
      required: false
    }
  ];

  it("returns required error before type errors", () => {
    const error = validateCustomFieldMaps(
      definitions,
      { AppDate__c: "bad", Qty__c: "x" },
      "契約履歴"
    );
    expect(error).toContain("必須カスタム項目");
    expect(error).toContain("メモ");
  });

  it("returns type errors for filled invalid values", () => {
    const error = validateCustomFieldMaps(
      definitions,
      { Memo__c: "ok", AppDate__c: "2026/07/28", Qty__c: "1.5" },
      "契約履歴"
    );
    expect(error).toContain("形式が不正");
    expect(error).toContain("申込日");
    expect(error).toContain("数量");
  });

  it("passes when values are valid", () => {
    expect(
      validateCustomFieldMaps(
        definitions,
        { Memo__c: "ok", AppDate__c: "2026-07-28", Qty__c: "3" },
        "契約履歴"
      )
    ).toBeNull();
  });

  it("skips required/type checks for invisible product fields", () => {
    const productDefs = [
      {
        apiName: "LicenseKey__c",
        label: "ライセンスキー",
        fieldType: "STRING",
        required: true,
        visibilityFieldApiName: "Family",
        visibilityOperator: "IN",
        visibilityValues: "Software"
      }
    ];
    expect(
      validateCustomFieldMaps(productDefs, {}, "商品明細", {
        Family: "Hardware"
      })
    ).toBeNull();
    expect(
      validateCustomFieldMaps(productDefs, {}, "商品明細", {
        Family: "Software"
      })
    ).toContain("ライセンスキー");
  });
});

describe("isCustomFieldVisible", () => {
  it("shows unconditional fields", () => {
    expect(
      isCustomFieldVisible({ apiName: "A__c" }, { Family: "Software" })
    ).toBe(true);
  });

  it("evaluates comma-separated IN values", () => {
    const def = {
      apiName: "A__c",
      visibilityFieldApiName: "Family",
      visibilityOperator: "IN",
      visibilityValues: "Software, Add-On"
    };
    expect(isCustomFieldVisible(def, { Family: "Add-On" })).toBe(true);
    expect(isCustomFieldVisible(def, { Family: "Hardware" })).toBe(false);
  });
});

describe("default custom fields", () => {
  const defs = [
    {
      apiName: "Memo__c",
      fieldType: "STRING",
      defaultValue: "hello",
      visibilityFieldApiName: "Family",
      visibilityOperator: "EQUALS",
      visibilityValues: "Zeroboard"
    },
    {
      apiName: "Flag__c",
      fieldType: "BOOLEAN",
      defaultValue: "true"
    }
  ];

  it("coerces boolean defaults", () => {
    expect(coerceCustomFieldDefault("BOOLEAN", "true")).toBe(true);
    expect(coerceCustomFieldDefault("BOOLEAN", "0")).toBe(false);
    expect(coerceCustomFieldDefault("STRING", "  x ")).toBe("x");
    expect(coerceCustomFieldDefault("STRING", "   ")).toBeUndefined();
  });

  it("applies defaults only for missing keys", () => {
    expect(applyDefaultCustomFields({}, defs, { Family: "Zeroboard" })).toEqual(
      { Memo__c: "hello", Flag__c: true }
    );
    expect(
      applyDefaultCustomFields({ Memo__c: "", Flag__c: false }, defs, {
        Family: "Zeroboard"
      })
    ).toEqual({ Memo__c: "", Flag__c: false });
  });

  it("reapplies defaults after hide then show", () => {
    const filled = applyDefaultCustomFields({}, defs, {
      Family: "Zeroboard"
    });
    expect(filled.Memo__c).toBe("hello");

    const hidden = syncCustomFieldsForVisibility(filled, defs, {
      Family: "Other"
    });
    expect(hidden).toEqual({ Flag__c: true });

    const reshown = syncCustomFieldsForVisibility(hidden, defs, {
      Family: "Zeroboard"
    });
    expect(reshown.Memo__c).toBe("hello");
    expect(reshown.Flag__c).toBe(true);
  });

  it("filters by wizard type flags", () => {
    const typed = [
      {
        apiName: "OnlyNew__c",
        fieldType: "STRING",
        defaultValue: "n",
        showOnNew: true,
        showOnChange: false,
        showOnRenew: false,
        showOnCancel: false
      }
    ];
    expect(
      applyDefaultCustomFields({}, typed, undefined, "New").OnlyNew__c
    ).toBe("n");
    expect(applyDefaultCustomFields({}, typed, undefined, "Change")).toEqual(
      {}
    );
  });

  it("prunes ShowOn-hidden contract fields and reapplies defaults on re-show", () => {
    const typed = [
      {
        apiName: "OnlyNew__c",
        fieldType: "STRING",
        defaultValue: "n",
        showOnNew: true,
        showOnChange: false,
        showOnRenew: false,
        showOnCancel: false
      }
    ];
    const filled = syncCustomFieldsForVisibility(
      { OnlyNew__c: "typed" },
      typed,
      undefined,
      "New",
      {}
    );
    expect(filled.OnlyNew__c).toBe("typed");

    const hidden = syncCustomFieldsForVisibility(
      filled,
      typed,
      undefined,
      "Change",
      {}
    );
    expect(hidden).toEqual({});

    const reshown = syncCustomFieldsForVisibility(
      hidden,
      typed,
      undefined,
      "New",
      {}
    );
    expect(reshown.OnlyNew__c).toBe("n");
  });

  it("resolves Opportunity, Account, Product2, and static defaults", () => {
    const oppField = {
      apiName: "Memo__c",
      fieldType: "STRING",
      defaultSource: "Opportunity",
      defaultValue: "Name",
      showOnNew: true,
      showOnChange: true,
      showOnRenew: true,
      showOnCancel: true
    };
    const accountField = {
      apiName: "AccountMemo__c",
      fieldType: "STRING",
      defaultSource: "Account",
      defaultValue: "Name",
      showOnNew: true,
      showOnChange: true,
      showOnRenew: true,
      showOnCancel: true
    };
    const productField = {
      apiName: "ProductMemo__c",
      fieldType: "STRING",
      defaultSource: "Product2",
      defaultValue: "Family",
      visibilityFieldApiName: "Family",
      visibilityOperator: "EQUALS",
      visibilityValues: "Zeroboard",
      showOnNew: true,
      showOnChange: true,
      showOnRenew: true,
      showOnCancel: true
    };
    const staticField = {
      apiName: "StaticMemo__c",
      fieldType: "STRING",
      defaultSource: "",
      defaultValue: "固定メモ",
      showOnNew: true,
      showOnChange: true,
      showOnRenew: true,
      showOnCancel: true
    };

    expect(
      resolveCustomFieldDefault(oppField, undefined, { Name: "商談A" })
    ).toBe("商談A");
    expect(
      resolveCustomFieldDefault(accountField, undefined, {
        "Account.Name": "取引先B"
      })
    ).toBe("取引先B");
    expect(
      resolveCustomFieldDefault(
        productField,
        { Family: "Zeroboard" },
        undefined
      )
    ).toBe("Zeroboard");
    expect(resolveCustomFieldDefault(staticField, undefined, undefined)).toBe(
      "固定メモ"
    );
    const today = resolveCustomFieldDefault(
      {
        apiName: "OrderDate__c",
        fieldType: "DATE",
        defaultSource: "Today",
        showOnNew: true
      },
      undefined,
      undefined
    );
    expect(today).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(
      resolveCustomFieldDefault(oppField, undefined, undefined)
    ).toBeUndefined();
    expect(
      resolveCustomFieldDefault(
        { ...oppField, defaultValue: "Missing__c" },
        undefined,
        { Name: "商談A" }
      )
    ).toBeUndefined();

    expect(
      applyDefaultCustomFields(
        {},
        [oppField, accountField, productField, staticField],
        { Family: "Zeroboard" },
        "New",
        { Name: "商談A", "Account.Name": "取引先B" }
      )
    ).toEqual({
      Memo__c: "商談A",
      AccountMemo__c: "取引先B",
      ProductMemo__c: "Zeroboard",
      StaticMemo__c: "固定メモ"
    });
  });

  it("type-only filter keeps visibility-gated fields for global toggles", () => {
    const typeFilterDefs = [
      {
        apiName: "Memo__c",
        fieldType: "STRING",
        visibilityFieldApiName: "Family",
        visibilityOperator: "EQUALS",
        visibilityValues: "Zeroboard",
        showOnNew: true,
        showOnChange: true,
        showOnRenew: true,
        showOnCancel: true
      }
    ];
    expect(
      filterCustomFieldDefinitionsForWizardType(typeFilterDefs, "New")
    ).toHaveLength(1);
    expect(
      filterVisibleCustomFieldDefinitions(typeFilterDefs, null, "New")
    ).toHaveLength(0);
  });
});

describe("shallowEqualFieldMaps", () => {
  it("compares primitive maps by key/value without JSON stringify", () => {
    expect(shallowEqualFieldMaps({ a: "1" }, { a: "1" })).toBe(true);
    expect(shallowEqualFieldMaps({ a: "1" }, { a: "2" })).toBe(false);
    expect(shallowEqualFieldMaps({ a: "1" }, { a: "1", b: "2" })).toBe(false);
    expect(shallowEqualFieldMaps(null, {})).toBe(true);
  });
});

describe("buildCustomFieldInputs picklist display (Core 第0.1節・第7.2節・第7.5節)", () => {
  it("shows Japanese picklist labels while keeping API values", () => {
    const inputs = buildCustomFieldInputs(
      [
        {
          apiName: "InvoiceDateMethod__c",
          label: "請求日の計算方式",
          fieldType: "PICKLIST",
          picklistOptions: [
            { label: "基準日と同日", value: "SameDay" },
            { label: "基準日以後の指定日", value: "OnOrAfterSpecifiedDay" }
          ]
        },
        {
          apiName: "PaymentTermMethod__c",
          label: "支払条件の計算方式",
          fieldType: "PICKLIST",
          picklistOptions: [
            { label: "請求月から指定月数後", value: "MonthOffset" }
          ]
        }
      ],
      {
        InvoiceDateMethod__c: "SameDay",
        PaymentTermMethod__c: "MonthOffset"
      },
      "order-billing",
      true
    );
    expect(inputs[0].value).toBe("SameDay");
    expect(inputs[0].displayValue).toBe("基準日と同日");
    expect(inputs[1].value).toBe("MonthOffset");
    expect(inputs[1].displayValue).toBe("請求月から指定月数後");
  });
});
