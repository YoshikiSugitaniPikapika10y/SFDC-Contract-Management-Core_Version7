import {
  validateNewProducts,
  validateSpotChangeProducts,
  SPOT_CHANGE_ONE_TIME_ONLY_MESSAGE,
  SPOT_CHANGE_NO_PREVIOUS_PRODUCT_MESSAGE,
  validateChangeProducts,
  validateChangeEffectiveDate,
  requiresChangeEffectiveDateOnBillingPeriodStart,
  getEarliestChangeBillingThresholdDate,
  CHANGE_EFFECTIVE_DATE_BILLING_PERIOD_START_MESSAGE,
  validateChangeIsNotCustomFieldOnly,
  CHANGE_CUSTOM_FIELDS_ONLY_MESSAGE,
  CHANGE_REQUIRES_BILLING_EVENT_MESSAGE,
  CHANGE_MID_TERM_REMAKE_SPLIT_MESSAGE,
  validateChangeMidTermRemakeSplit,
  validateChangeReconstitutionCoverage,
  validateCancelProducts,
  validateRenewProducts,
  BILLING_TYPE_RECURRING,
  BILLING_TYPE_ONE_TIME,
  PRODUCT_TYPE_NEW,
  PRODUCT_TYPE_ORIGINAL,
  PRODUCT_TYPE_REMAKE,
  PRODUCT_TYPE_RENEW,
  INVOICE_SETTING_PREPAID_START,
  INVOICE_SETTING_SPLIT_MONTHLY,
  isRenewProductLine,
  isBillingTypeLockedLine,
  canDuplicateProductLine,
  resolveInvoiceTypeForBillingType,
  validateInvoiceSettingForBillingType,
  QUANTITY_MIN_MESSAGE,
  validateNewProductPeriodOverlap,
  validateChangeProductPeriodOverlap,
  REVENUE_BASIS_BLANK_MESSAGE,
  REVENUE_BASIS_INVALID_MESSAGE
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

  it("does not fill blank when fillBlankWithDefault is false (BUG-094)", () => {
    expect(
      resolveInvoiceTypeForBillingType(
        "",
        BILLING_TYPE_RECURRING,
        options,
        INVOICE_SETTING_PREPAID_START,
        { fillBlankWithDefault: false }
      )
    ).toBe("");
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
          revenueRecognitionBasis: "月次計上",
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

  it("rejects blank revenue recognition basis on New (Core 1.1.10 / 4.5.2)", () => {
    const error = validateNewProducts(
      [
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_ONE_TIME,
          invoiceType: INVOICE_SETTING_PREPAID_START,
          revenueRecognitionBasis: "",
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
    expect(error).toContain(REVENUE_BASIS_BLANK_MESSAGE);
  });

  it("rejects invalid revenue recognition basis on New", () => {
    const error = validateNewProducts(
      [
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_ONE_TIME,
          invoiceType: INVOICE_SETTING_PREPAID_START,
          revenueRecognitionBasis: "OverTime",
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
    expect(error).toContain(REVENUE_BASIS_INVALID_MESSAGE);
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
          revenueRecognitionBasis: "月次計上",
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
          revenueRecognitionBasis: "月次計上",
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
      amount: 12000,
      startDate: previousStart,
      endDate: previousEnd,
      invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
      revenueRecognitionBasis: "月次計上",
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
          revenueRecognitionBasis: "月次計上",
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
    expect(error).toMatch(/変更前/);
  });

  it("rejects blank revenue recognition basis on Term Change New (Core 1.1.10 / 4.5.2)", () => {
    const error = validateChangeProducts(
      [
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "月次計上",
          startDate: previousStart,
          endDate: previousEnd,
          recordType: PRODUCT_TYPE_ORIGINAL,
          typeLabel: "Original",
          sourceContractProductId: sourceId,
          amount: -12000
        },
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "月次計上",
          startDate: contractStart,
          endDate: contractEnd,
          recordType: PRODUCT_TYPE_REMAKE,
          typeLabel: "Remake",
          sourceContractProductId: sourceId,
          amount: 12000
        },
        {
          productId: "01tBBB",
          quantity: 1,
          unitPrice: 500,
          billingType: BILLING_TYPE_ONE_TIME,
          invoiceType: INVOICE_SETTING_PREPAID_START,
          revenueRecognitionBasis: "",
          startDate: contractStart,
          endDate: contractStart,
          recordType: PRODUCT_TYPE_NEW,
          typeLabel: "New",
          amount: 500
        }
      ],
      contractStart,
      contractEnd,
      contractStart,
      sourceProducts,
      previousStart,
      previousEnd
    );
    expect(error).toBe(`商品明細（追加）: ${REVENUE_BASIS_BLANK_MESSAGE}`);
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
          revenueRecognitionBasis: "月次計上",
          startDate: previousStart,
          endDate: previousEnd,
          recordType: PRODUCT_TYPE_ORIGINAL,
          typeLabel: "Original",
          sourceContractProductId: sourceId,
          amount: -12000
        },
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "月次計上",
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
    expect(error == null || !/変更前の行が必要/.test(error)).toBe(true);
    expect(error == null || !/Remake行を1件以上/.test(error)).toBe(true);
  });

  it("rejects mid-term unit-price Remake without pre-period same-as-Original Remake", () => {
    const original = {
      productId: "01tAAA",
      quantity: 1,
      unitPrice: 30000,
      billingType: BILLING_TYPE_RECURRING,
      invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
      revenueRecognitionBasis: "月次計上",
      startDate: "2026-04-01",
      endDate: "2027-03-31",
      recordType: PRODUCT_TYPE_ORIGINAL,
      typeLabel: "Original",
      sourceContractProductId: sourceId,
      amount: -360000
    };
    const remakeFullNewPrice = {
      productId: "01tAAA",
      quantity: 1,
      unitPrice: 50000,
      billingType: BILLING_TYPE_RECURRING,
      invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
      revenueRecognitionBasis: "月次計上",
      startDate: "2026-04-01",
      endDate: "2027-03-31",
      recordType: PRODUCT_TYPE_REMAKE,
      typeLabel: "Remake",
      sourceContractProductId: sourceId,
      amount: 600000
    };
    // 全期間1本の単価変更は洗替（差分開始＝Original開始）として許容。
    expect(
      validateChangeMidTermRemakeSplit(original, [remakeFullNewPrice])
    ).toBeNull();

    const remakeMidOnly = {
      ...remakeFullNewPrice,
      startDate: "2026-05-01",
      endDate: "2027-03-31",
      amount: 550000
    };
    expect(
      validateChangeMidTermRemakeSplit(original, [remakeMidOnly])
    ).toBe(CHANGE_MID_TERM_REMAKE_SPLIT_MESSAGE);

    const remakePreSame = {
      ...remakeFullNewPrice,
      startDate: "2026-04-01",
      endDate: "2026-04-30",
      unitPrice: 30000,
      amount: 30000
    };
    expect(
      validateChangeMidTermRemakeSplit(original, [remakePreSame, remakeMidOnly])
    ).toBeNull();
  });

  it("rejects Remake invoice setting that differs from previous even with unit price change", () => {
    const error = validateChangeProducts(
      [
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "月次計上",
          startDate: previousStart,
          endDate: previousEnd,
          recordType: PRODUCT_TYPE_ORIGINAL,
          typeLabel: "Original",
          sourceContractProductId: sourceId,
          amount: -12000
        },
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 2000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_PREPAID_START,
          revenueRecognitionBasis: "月次計上",
          startDate: contractStart,
          endDate: contractEnd,
          recordType: PRODUCT_TYPE_REMAKE,
          typeLabel: "Remake",
          sourceContractProductId: sourceId,
          amount: 24000
        }
      ],
      contractStart,
      contractEnd,
      contractStart,
      sourceProducts,
      previousStart,
      previousEnd
    );
    expect(error).toMatch(/請求設定は前回の版と同じ/);
  });

  it("rejects Remake billing type that differs from previous estimate product", () => {
    const error = validateChangeProducts(
      [
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "月次計上",
          startDate: previousStart,
          endDate: previousEnd,
          recordType: PRODUCT_TYPE_ORIGINAL,
          typeLabel: "Original",
          sourceContractProductId: sourceId,
          amount: -12000
        },
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 2000,
          billingType: BILLING_TYPE_ONE_TIME,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "月次計上",
          startDate: previousStart,
          endDate: previousEnd,
          recordType: PRODUCT_TYPE_REMAKE,
          typeLabel: "Remake",
          sourceContractProductId: sourceId,
          amount: 24000
        }
      ],
      contractStart,
      contractEnd,
      contractStart,
      sourceProducts,
      previousStart,
      previousEnd
    );
    expect(error).toMatch(/課金形態は前回の版と同じ/);
  });

  it("rejects Remake revenue recognition basis that differs from previous", () => {
    const sourceWithRevenue = [
      {
        ...sourceProducts[0],
        revenueRecognitionBasis: "月次計上"
      }
    ];
    const error = validateChangeProducts(
      [
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "月次計上",
          startDate: previousStart,
          endDate: previousEnd,
          recordType: PRODUCT_TYPE_ORIGINAL,
          typeLabel: "Original",
          sourceContractProductId: sourceId,
          amount: -12000
        },
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 2000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "一括計上",
          startDate: contractStart,
          endDate: contractEnd,
          recordType: PRODUCT_TYPE_REMAKE,
          typeLabel: "Remake",
          sourceContractProductId: sourceId,
          amount: 24000
        }
      ],
      contractStart,
      contractEnd,
      contractStart,
      sourceWithRevenue,
      previousStart,
      previousEnd
    );
    expect(error).toMatch(/売上計上基準は前回の版と同じ/);
  });

  it("rejects Original revenue recognition basis that differs from previous (BUG-082)", () => {
    const error = validateChangeProducts(
      [
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "一括計上",
          startDate: previousStart,
          endDate: previousEnd,
          recordType: PRODUCT_TYPE_ORIGINAL,
          typeLabel: "Original",
          sourceContractProductId: sourceId,
          amount: -12000
        },
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "月次計上",
          startDate: previousStart,
          endDate: previousEnd,
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
    expect(error).toMatch(/変更前の行は前回の版の見積商品と一致/);
  });

  it("rejects Original billing type that differs from previous estimate product", () => {
    const error = validateChangeProducts(
      [
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_ONE_TIME,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "月次計上",
          startDate: previousStart,
          endDate: previousEnd,
          recordType: PRODUCT_TYPE_ORIGINAL,
          typeLabel: "Original",
          sourceContractProductId: sourceId,
          amount: -12000
        },
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "月次計上",
          startDate: previousStart,
          endDate: previousEnd,
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
    expect(error).toMatch(/変更前の行は前回の版の見積商品と一致/);
  });

  it("rejects Original amount that is not -(previous Amount) (BUG-085)", () => {
    const error = validateChangeProducts(
      [
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_RECURRING,
          invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
          revenueRecognitionBasis: "月次計上",
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
          revenueRecognitionBasis: "月次計上",
          startDate: previousStart,
          endDate: previousEnd,
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
    expect(error).toMatch(/変更前の行は前回の版の見積商品と一致/);
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
    revenueRecognitionBasis: "月次計上",
    startDate: termStart,
    endDate: termEnd,
    recordType: PRODUCT_TYPE_ORIGINAL,
    sourceContractProductId: sourceId,
    amount: -96000
  };
  const unchangedRemake = {
    ...unchangedOriginal,
    recordType: PRODUCT_TYPE_REMAKE,
    typeLabel: "Remake",
    amount: 96000
  };
  const oneTimeAddon = {
    productId: "01tOT",
    quantity: 1,
    unitPrice: 50000,
    billingType: BILLING_TYPE_ONE_TIME,
    invoiceType: INVOICE_SETTING_PREPAID_START,
    revenueRecognitionBasis: "月次計上",
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
      validateChangeEffectiveDate("", termStart, termEnd, termStart, products)
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
    ).toBe(CHANGE_EFFECTIVE_DATE_BILLING_PERIOD_START_MESSAGE);
  });

  it("anchors Change billing events to the source line start, not the header (CHANGE-248)", () => {
    const headerStart = "2026-01-15";
    const headerEnd = "2027-01-14";
    const lineStart = "2026-03-01";
    const onLineCycle = "2026-05-01";
    const onHeaderCycle = "2026-05-15";
    const original = {
      ...unchangedOriginal,
      startDate: lineStart,
      endDate: headerEnd
    };
    const remakeOnLine = {
      ...original,
      recordType: PRODUCT_TYPE_REMAKE,
      typeLabel: "Remake",
      unitPrice: 9000,
      startDate: onLineCycle
    };
    expect(
      validateChangeEffectiveDate(
        onLineCycle,
        headerStart,
        headerEnd,
        headerStart,
        [original, remakeOnLine]
      )
    ).toBeNull();
    const remakeOnHeader = {
      ...remakeOnLine,
      startDate: onHeaderCycle
    };
    expect(
      validateChangeEffectiveDate(
        onHeaderCycle,
        headerStart,
        headerEnd,
        headerStart,
        [original, remakeOnHeader]
      )
    ).toBe(CHANGE_EFFECTIVE_DATE_BILLING_PERIOD_START_MESSAGE);
  });

  it("does not require effective date when billing events are empty (CHANGE-241)", () => {
    const products = [unchangedOriginal, unchangedRemake];
    expect(requiresChangeEffectiveDateOnBillingPeriodStart(products)).toBe(
      false
    );
    expect(
      validateChangeEffectiveDate("", termStart, termEnd, termStart, products)
    ).toBeNull();
  });

  it("rejects custom-fields-only Change on the screen (CHANGE-242)", () => {
    const products = [
      unchangedOriginal,
      {
        ...unchangedRemake,
        customFields: { Description__c: "changed" }
      }
    ];
    const sources = [
      {
        contractProductId: sourceId,
        productId: unchangedOriginal.productId,
        quantity: 1,
        unitPrice: 8000,
        amount: 96000,
        startDate: termStart,
        endDate: termEnd,
        invoiceType: INVOICE_SETTING_PREPAID_START,
        revenueRecognitionBasis: "月次計上",
        billingType: BILLING_TYPE_RECURRING,
        customFields: { Description__c: "previous" }
      }
    ];
    expect(validateChangeIsNotCustomFieldOnly(products, sources)).toBe(
      CHANGE_CUSTOM_FIELDS_ONLY_MESSAGE
    );
    expect(
      validateChangeProducts(
        products,
        termStart,
        termEnd,
        "",
        sources,
        termStart,
        termEnd
      )
    ).toBe(CHANGE_CUSTOM_FIELDS_ONLY_MESSAGE);
  });

  it("still guides to Renew when no event and no custom-field diff (CHANGE-241)", () => {
    const products = [unchangedOriginal, unchangedRemake];
    const sources = [
      {
        contractProductId: sourceId,
        productId: unchangedOriginal.productId,
        quantity: 1,
        unitPrice: 8000,
        amount: 96000,
        startDate: termStart,
        endDate: termEnd,
        invoiceType: INVOICE_SETTING_PREPAID_START,
        revenueRecognitionBasis: "月次計上",
        billingType: BILLING_TYPE_RECURRING,
        customFields: {}
      }
    ];
    expect(
      validateChangeProducts(
        products,
        termStart,
        termEnd,
        "",
        sources,
        termStart,
        termEnd
      )
    ).toBe(CHANGE_REQUIRES_BILLING_EVENT_MESSAGE);
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
    expect(canDuplicateProductLine(editableNewRow, { wizardType: "New" })).toBe(
      true
    );
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

describe("isBillingTypeLockedLine", () => {
  it("locks Remake and Original; Renew is editable like New (Core 4.5.2 / 4.4.1)", () => {
    expect(isBillingTypeLockedLine({ recordType: PRODUCT_TYPE_RENEW })).toBe(
      false
    );
    expect(isBillingTypeLockedLine({ recordType: PRODUCT_TYPE_REMAKE })).toBe(
      true
    );
    expect(isBillingTypeLockedLine({ recordType: PRODUCT_TYPE_ORIGINAL })).toBe(
      true
    );
    expect(isBillingTypeLockedLine({ recordType: PRODUCT_TYPE_NEW })).toBe(
      false
    );
    expect(isBillingTypeLockedLine(null)).toBe(false);
  });
});

describe("quantity min (Core 4.3.9)", () => {
  const headerStart = "2026-04-01";
  const headerEnd = "2027-03-31";
  const newLine = {
    productId: "01tNEW",
    quantity: 1,
    unitPrice: 1000,
    amount: 12000,
    billingType: BILLING_TYPE_RECURRING,
    invoiceType: INVOICE_SETTING_PREPAID_START,
    revenueRecognitionBasis: "月次計上",
    startDate: headerStart,
    endDate: headerEnd,
    recordType: PRODUCT_TYPE_NEW
  };

  it("rejects quantity 0 on a selected product with the specified message", () => {
    expect(
      validateNewProducts([{ ...newLine, quantity: 0 }], headerStart, headerEnd)
    ).toContain(QUANTITY_MIN_MESSAGE);
  });

  it("rejects quantity below 0.01", () => {
    expect(
      validateNewProducts(
        [{ ...newLine, quantity: 0.009 }],
        headerStart,
        headerEnd
      )
    ).toContain(QUANTITY_MIN_MESSAGE);
  });

  it("does not quantity-error a blank product line", () => {
    expect(
      validateNewProducts(
        [{ ...newLine, productId: null, quantity: null }],
        headerStart,
        headerEnd
      )
    ).toBe("商品明細を1行以上入力してください。");
  });

  it("rejects Original quantity 0", () => {
    const sourceId = "a00SRC000000001";
    const original = {
      productId: "01tREC",
      quantity: 0,
      unitPrice: 8000,
      amount: 0,
      billingType: BILLING_TYPE_RECURRING,
      invoiceType: INVOICE_SETTING_PREPAID_START,
      revenueRecognitionBasis: "月次計上",
      startDate: headerStart,
      endDate: headerEnd,
      recordType: PRODUCT_TYPE_ORIGINAL,
      sourceContractProductId: sourceId
    };
    const remake = {
      ...original,
      quantity: 1,
      amount: 96000,
      recordType: PRODUCT_TYPE_REMAKE
    };
    expect(
      validateChangeProducts(
        [original, remake],
        headerStart,
        headerEnd,
        headerStart,
        [
          {
            contractProductId: sourceId,
            productId: original.productId,
            quantity: 1,
            unitPrice: 8000,
            startDate: headerStart,
            endDate: headerEnd,
            invoiceType: INVOICE_SETTING_PREPAID_START,
            revenueRecognitionBasis: "月次計上",
            billingType: BILLING_TYPE_RECURRING
          }
        ],
        headerStart,
        headerEnd
      )
    ).toContain(QUANTITY_MIN_MESSAGE);
  });
});

describe("validateNewProductPeriodOverlap Core 4.5.1", () => {
  it("allows overlapping one-time lines of the same product", () => {
    expect(
      validateNewProductPeriodOverlap([
        {
          productId: "01tAAA",
          quantity: 1,
          billingType: BILLING_TYPE_ONE_TIME,
          startDate: "2026-06-01",
          endDate: "2026-06-30",
          recordType: PRODUCT_TYPE_NEW
        },
        {
          productId: "01tAAA",
          quantity: 1,
          billingType: BILLING_TYPE_ONE_TIME,
          startDate: "2026-06-15",
          endDate: "2026-07-15",
          recordType: PRODUCT_TYPE_NEW
        }
      ])
    ).toBeNull();
  });

  it("rejects overlapping recurring lines of the same product", () => {
    expect(
      validateNewProductPeriodOverlap([
        {
          productId: "01tAAA",
          quantity: 1,
          billingType: BILLING_TYPE_RECURRING,
          startDate: "2026-06-01",
          endDate: "2026-06-30",
          recordType: PRODUCT_TYPE_NEW
        },
        {
          productId: "01tAAA",
          quantity: 1,
          billingType: BILLING_TYPE_RECURRING,
          startDate: "2026-06-15",
          endDate: "2026-07-15",
          recordType: PRODUCT_TYPE_NEW
        }
      ])
    ).toMatch(/同一商品の契約期間が重複しています/);
  });

  it("rejects overlapping recurring and one-time lines of the same product", () => {
    expect(
      validateChangeProductPeriodOverlap([
        {
          productId: "01tAAA",
          quantity: 1,
          billingType: BILLING_TYPE_RECURRING,
          startDate: "2026-06-01",
          endDate: "2026-06-30",
          recordType: PRODUCT_TYPE_REMAKE
        },
        {
          productId: "01tAAA",
          quantity: 1,
          billingType: BILLING_TYPE_ONE_TIME,
          startDate: "2026-06-01",
          endDate: "2026-06-30",
          recordType: PRODUCT_TYPE_NEW
        }
      ])
    ).toMatch(/同一商品の契約期間が重複しています/);
  });
});

describe("Core 0.1 display names on validation messages", () => {
  it("uses 変更後／変更前 for Change coverage and start-date errors (Core 0.1, 1.3)", () => {
    const original = {
      startDate: "2026-04-01",
      endDate: "2027-03-31"
    };
    const remakeWithGap = {
      productId: "01tAAA",
      quantity: 1,
      unitPrice: 1000,
      recordType: PRODUCT_TYPE_REMAKE,
      startDate: "2026-06-01",
      endDate: "2027-03-31"
    };
    expect(
      validateChangeReconstitutionCoverage(original, [remakeWithGap])
    ).toBe("変更後は変更前の期間を重複や隙間なく埋める必要があります。");

    const remakeEarly = {
      ...remakeWithGap,
      startDate: "2026-03-01",
      endDate: "2027-03-31"
    };
    expect(validateChangeReconstitutionCoverage(original, [remakeEarly])).toBe(
      "変更後の開始日は変更前の開始日より前にできません。"
    );
  });

  it("uses 変更前／変更後 for mid-term Remake split (Core 0.1, 4.4)", () => {
    expect(CHANGE_MID_TERM_REMAKE_SPLIT_MESSAGE).toBe(
      "期中切替では、切替日前は変更前と同条件の変更後と、切替日以降の変更後に分けてください。"
    );
  });

  it("uses 解約 for Cancel product validation (Core 0.1, 4.3)", () => {
    expect(
      validateCancelProducts([
        {
          productId: "01tAAA",
          quantity: 1,
          unitPrice: 1000,
          recordType: PRODUCT_TYPE_NEW
        }
      ])
    ).toBe("解約では商品明細を入力できません。");
  });

  it("uses 更新 for Renew recurring-required validation (Core 0.1, 4.5)", () => {
    expect(
      validateRenewProducts(
        [
          {
            productId: "01tAAA",
            quantity: 1,
            unitPrice: 1000,
            billingType: BILLING_TYPE_ONE_TIME,
            recordType: PRODUCT_TYPE_NEW
          }
        ],
        "2026-04-01",
        "2027-03-31",
        "2026-03-31"
      )
    ).toBe(
      "更新では継続課金商品を1行以上指定してください。一回課金のみの更新はできません。"
    );
  });

  it("uses 変更後 when Remake lines are missing (Core 0.1, 4.3.13)", () => {
    expect(
      validateChangeReconstitutionCoverage(
        { startDate: "2026-04-01", endDate: "2027-03-31" },
        []
      )
    ).toBe("変更後の商品明細を1行以上入力してください。");
  });
});

describe("validateSpotChangeProducts (Core 5.1 / 1.1.10)", () => {
  const oneTimeNew = {
    productId: "01tAAA",
    quantity: 1,
    unitPrice: 1000,
    billingType: BILLING_TYPE_ONE_TIME,
    invoiceType: INVOICE_SETTING_PREPAID_START,
    revenueRecognitionBasis: "月次計上",
    startDate: "2026-04-01",
    endDate: "2026-04-01",
    recordType: PRODUCT_TYPE_NEW,
    typeLabel: "New",
    amount: 1000
  };

  it("accepts one-time Type=New only", () => {
    expect(validateSpotChangeProducts([oneTimeNew])).toBeNull();
  });

  it("rejects recurring billing instead of a header-period error", () => {
    expect(
      validateSpotChangeProducts([
        { ...oneTimeNew, billingType: BILLING_TYPE_RECURRING }
      ])
    ).toBe(SPOT_CHANGE_ONE_TIME_ONLY_MESSAGE);
  });

  it("rejects Original", () => {
    expect(
      validateSpotChangeProducts([
        { ...oneTimeNew, recordType: PRODUCT_TYPE_ORIGINAL, typeLabel: "Original" }
      ])
    ).toBe(SPOT_CHANGE_ONE_TIME_ONLY_MESSAGE);
  });

  it("rejects Remake", () => {
    expect(
      validateSpotChangeProducts([
        {
          ...oneTimeNew,
          recordType: PRODUCT_TYPE_REMAKE,
          typeLabel: "Remake",
          sourceContractProductId: "a00SRC000000001"
        }
      ])
    ).toBe(SPOT_CHANGE_ONE_TIME_ONLY_MESSAGE);
  });

  it("rejects inherited previous products", () => {
    expect(
      validateSpotChangeProducts([
        { ...oneTimeNew, sourceContractProductId: "a00SRC000000001" }
      ])
    ).toBe(SPOT_CHANGE_NO_PREVIOUS_PRODUCT_MESSAGE);
  });
});
