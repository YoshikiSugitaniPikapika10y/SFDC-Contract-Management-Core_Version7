import {
  validateNewProducts,
  validateChangeProducts,
  validateChangeEffectiveDate,
  requiresChangeEffectiveDateOnBillingPeriodStart,
  getEarliestChangeBillingThresholdDate,
  BILLING_TYPE_RECURRING,
  BILLING_TYPE_ONE_TIME,
  PRODUCT_TYPE_NEW,
  PRODUCT_TYPE_ORIGINAL,
  PRODUCT_TYPE_REMAKE,
  PRODUCT_TYPE_RENEW,
  INVOICE_SETTING_PREPAID_START,
  INVOICE_SETTING_SPLIT_MONTHLY,
  isRenewProductLine,
  canDuplicateProductLine,
  resolveInvoiceTypeForBillingType,
  validateInvoiceSettingForBillingType
} from "c/estimateLineItemUtils";

describe("resolveInvoiceTypeForBillingType", () => {
  const options = [
    { label: INVOICE_SETTING_PREPAID_START },
    { label: "一括後払" },
    { label: INVOICE_SETTING_SPLIT_MONTHLY }
  ];

  it("keeps a valid invoice setting", () => {
    expect(
      resolveInvoiceTypeForBillingType(
        INVOICE_SETTING_SPLIT_MONTHLY,
        BILLING_TYPE_RECURRING,
        options,
        INVOICE_SETTING_PREPAID_START
      )
    ).toBe(INVOICE_SETTING_SPLIT_MONTHLY);
  });

  it("does not silently replace an invalid invoice setting with the first option", () => {
    expect(
      resolveInvoiceTypeForBillingType(
        INVOICE_SETTING_SPLIT_MONTHLY,
        BILLING_TYPE_ONE_TIME,
        options,
        INVOICE_SETTING_PREPAID_START
      )
    ).toBe(INVOICE_SETTING_SPLIT_MONTHLY);
    expect(
      validateInvoiceSettingForBillingType(
        BILLING_TYPE_ONE_TIME,
        INVOICE_SETTING_SPLIT_MONTHLY
      )
    ).toMatch(/一回課金/);
  });

  it("fills fallback only when invoice setting is empty", () => {
    expect(
      resolveInvoiceTypeForBillingType(
        "",
        BILLING_TYPE_ONE_TIME,
        options,
        INVOICE_SETTING_PREPAID_START
      )
    ).toBe(INVOICE_SETTING_PREPAID_START);
  });
});

describe("validateNewProducts smoke", () => {
  const headerStart = "2026-04-01";
  const headerEnd = "2027-03-31";

  it("requires at least one active product line", () => {
    expect(validateNewProducts([], headerStart, headerEnd)).toMatch(
      /商品明細を1行以上/
    );
  });

  it("accepts a simple one-time New line within the header period", () => {
    const error = validateNewProducts(
      [
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_ONE_TIME,
          invoiceType: INVOICE_SETTING_PREPAID_START,
          startDate: headerStart,
          endDate: headerStart,
          recordType: PRODUCT_TYPE_NEW,
          typeLabel: "New",
          amount: 1000
        }
      ],
      headerStart,
      headerEnd
    );
    expect(error).toBeNull();
  });

  it("rejects recurring New lines when header period is not monthly-aligned", () => {
    const error = validateNewProducts(
      [
        {
          productId: "01tBBB",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          startDate: "2026-04-01",
          endDate: "2026-04-15",
          recordType: PRODUCT_TYPE_NEW,
          typeLabel: "New",
          amount: 1000
        }
      ],
      "2026-04-01",
      "2026-04-15"
    );
    expect(error).toMatch(/月次/);
  });
  it("rejects one-time lines with split-monthly invoice setting", () => {
    const error = validateNewProducts(
      [
        {
          productId: "01tCCC",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_ONE_TIME,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          startDate: headerStart,
          endDate: headerStart,
          recordType: PRODUCT_TYPE_NEW,
          typeLabel: "New",
          amount: 1000
        }
      ],
      headerStart,
      headerEnd
    );
    expect(error).toMatch(/一回課金/);
  });
});

describe("validateChangeProducts smoke", () => {
  const contractStart = "2026-04-01";
  const contractEnd = "2027-03-31";
  const previousStart = "2025-04-01";
  const previousEnd = "2026-03-31";
  const sourceId = "a0xSRC";

  const sourceProducts = [
    {
      contractProductId: sourceId,
      productId: "01tAAA",
      quantity: 1,
      unitPrice: 1000,
      startDate: previousStart,
      endDate: previousEnd,
      invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
      billingType: BILLING_TYPE_RECURRING
    }
  ];

  it("requires Original coverage for previous recurring products", () => {
    const error = validateChangeProducts(
      [
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          startDate: contractStart,
          endDate: contractEnd,
          recordType: PRODUCT_TYPE_REMAKE,
          typeLabel: "Remake",
          sourceContractProductId: sourceId,
          amount: 12000
        }
      ],
      contractStart,
      contractEnd,
      contractStart,
      sourceProducts,
      previousStart,
      previousEnd
    );
    expect(error).toMatch(/Original/);
  });

  it("accepts Original + Remake reconstitution for a single source product", () => {
    const error = validateChangeProducts(
      [
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          startDate: previousStart,
          endDate: previousEnd,
          recordType: PRODUCT_TYPE_ORIGINAL,
          typeLabel: "Original",
          sourceContractProductId: sourceId,
          amount: 12000
        },
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          startDate: contractStart,
          endDate: contractEnd,
          recordType: PRODUCT_TYPE_REMAKE,
          typeLabel: "Remake",
          sourceContractProductId: sourceId,
          amount: 12000
        }
      ],
      contractStart,
      contractEnd,
      contractStart,
      sourceProducts,
      previousStart,
      previousEnd
    );
    expect(error == null || !/Original行が必要/.test(error)).toBe(true);
    expect(error == null || !/Remake行を1件以上/.test(error)).toBe(true);
  });
});

describe("validateChangeEffectiveDate one-time mid-period", () => {
  const termStart = "2026-06-01";
  const termEnd = "2027-05-31";
  const midPeriod = "2026-10-15";
  const sourceId = "a0xSRC";

  const unchangedOriginal = {
    productId: "01tREC",
    quantity: 1,
    unitPrice: 8000,
    billingType: BILLING_TYPE_RECURRING,
    invoiceType: INVOICE_SETTING_PREPAID_START,
    startDate: termStart,
    endDate: termEnd,
    recordType: PRODUCT_TYPE_ORIGINAL,
    sourceContractProductId: sourceId
  };
  const unchangedRemake = {
    ...unchangedOriginal,
    recordType: PRODUCT_TYPE_REMAKE,
    typeLabel: "Remake"
  };
  const oneTimeAddon = {
    productId: "01tOT",
    quantity: 1,
    unitPrice: 50000,
    billingType: BILLING_TYPE_ONE_TIME,
    invoiceType: INVOICE_SETTING_PREPAID_START,
    startDate: midPeriod,
    endDate: "2026-10-31",
    recordType: PRODUCT_TYPE_NEW,
    sourceContractProductId: null
  };

  it("does not require billing-period start when only one-time New drives the event", () => {
    const products = [unchangedOriginal, unchangedRemake, oneTimeAddon];
    expect(requiresChangeEffectiveDateOnBillingPeriodStart(products)).toBe(
      false
    );
    expect(
      getEarliestChangeBillingThresholdDate(products, termStart)
    ).toBeNull();
    expect(
      validateChangeEffectiveDate(
        "",
        termStart,
        termEnd,
        termStart,
        products
      )
    ).toBeNull();
    expect(
      validateChangeEffectiveDate(
        midPeriod,
        termStart,
        termEnd,
        termStart,
        products
      )
    ).toBeNull();
  });

  it("still requires billing-period start when Remake content changes", () => {
    const changedRemake = {
      ...unchangedRemake,
      unitPrice: 9000,
      startDate: midPeriod
    };
    const products = [unchangedOriginal, changedRemake, oneTimeAddon];
    expect(requiresChangeEffectiveDateOnBillingPeriodStart(products)).toBe(
      true
    );
    expect(
      validateChangeEffectiveDate(
        midPeriod,
        termStart,
        termEnd,
        termStart,
        products
      )
    ).toMatch(/請求期間開始日/);
  });
});

describe("isRenewProductLine", () => {
  it("is true only for Type=Renew rows", () => {
    expect(isRenewProductLine({ recordType: PRODUCT_TYPE_RENEW })).toBe(true);
    expect(isRenewProductLine({ recordType: PRODUCT_TYPE_NEW })).toBe(false);
    expect(isRenewProductLine({ recordType: PRODUCT_TYPE_REMAKE })).toBe(false);
    expect(isRenewProductLine(null)).toBe(false);
  });
});

describe("canDuplicateProductLine", () => {
  const editableNewRow = {
    recordType: PRODUCT_TYPE_NEW,
    isReadonly: false
  };

  it("allows Type=New rows in New and Renew wizards", () => {
    expect(
      canDuplicateProductLine(editableNewRow, { wizardType: "New" })
    ).toBe(true);
    expect(
      canDuplicateProductLine(editableNewRow, { wizardType: "Renew" })
    ).toBe(true);
  });

  it("denies Renew inherited rows and readonly rows", () => {
    expect(
      canDuplicateProductLine(
        { recordType: PRODUCT_TYPE_RENEW, isReadonly: false },
        { wizardType: "Renew" }
      )
    ).toBe(false);
    expect(
      canDuplicateProductLine(
        { ...editableNewRow, isReadonly: true },
        { wizardType: "New" }
      )
    ).toBe(false);
  });

  it("allows Change new-product rows only", () => {
    expect(
      canDuplicateProductLine(editableNewRow, { wizardType: "Change" })
    ).toBe(true);
    expect(
      canDuplicateProductLine(
        { recordType: PRODUCT_TYPE_REMAKE, isReadonly: false },
        { wizardType: "Change" }
      )
    ).toBe(false);
  });

  it("denies duplicate in ordered edit mode", () => {
    expect(
      canDuplicateProductLine(editableNewRow, {
        wizardType: "New",
        orderedCustomFieldsOnly: true
      })
    ).toBe(false);
  });
});
