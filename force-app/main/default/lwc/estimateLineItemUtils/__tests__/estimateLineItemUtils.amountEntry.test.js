import {
  resolveLineAmount,
  deriveUnitPriceFromAmount,
  calculateMonthlyBillingTotal,
  resolveAmountEntryRoundingDiff,
  resolveInvoicePreviewRoundingDiff,
  lineageHasChangeBillingEvent,
  restoreAmountEntryFromSavedAmount,
  resolveChangePairAmountsFromSource,
  parseUnitPriceInput,
  parseQuantityInput,
  parseAmountYenInput,
  roundUnitPrice,
  roundQuantity,
  roundAmountYen,
  BILLING_TYPE_RECURRING,
  BILLING_TYPE_ONE_TIME,
  PRODUCT_TYPE_REMAKE,
  PRODUCT_TYPE_ORIGINAL,
  PRODUCT_TYPE_NEW
} from "c/estimateLineItemUtils";

describe("resolveChangePairAmountsFromSource", () => {
  it("keeps positive charge as Original negative / Remake positive", () => {
    expect(resolveChangePairAmountsFromSource(120000)).toEqual({
      originalAmount: -120000,
      remakeAmount: 120000
    });
  });

  it("keeps discount (negative amount) signs without Math.abs", () => {
    expect(resolveChangePairAmountsFromSource(-120000)).toEqual({
      originalAmount: 120000,
      remakeAmount: -120000
    });
  });

  it("does not force amount-entry restore for matching discount remake", () => {
    const pair = resolveChangePairAmountsFromSource(-120000);
    const remakeRow = {
      billingType: BILLING_TYPE_RECURRING,
      quantity: 1,
      unitPrice: -10000,
      startDate: "2026-04-01",
      endDate: "2027-03-31",
      recordType: PRODUCT_TYPE_REMAKE,
      typeLabel: "Remake",
      amount: pair.remakeAmount
    };
    const restored = restoreAmountEntryFromSavedAmount(remakeRow);
    expect(restored.amountEntryMode).toBeFalsy();
    expect(resolveLineAmount(restored)).toBe(-120000);
  });
});

describe("resolveLineAmount amount entry mode", () => {
  const recurringRow = {
    billingType: BILLING_TYPE_RECURRING,
    quantity: 1300,
    unitPrice: 742.85,
    startDate: "2026-05-01",
    endDate: "2027-02-28",
    recordType: PRODUCT_TYPE_REMAKE,
    typeLabel: "Remake"
  };

  it("uses manualAmount instead of recalculated unitPrice × qty × cycles", () => {
    const manualAmount = 9657000;
    const row = {
      ...recurringRow,
      amountEntryMode: true,
      manualAmount
    };

    expect(deriveUnitPriceFromAmount(row, manualAmount)).toBe(742.85);
    expect(1300 * 742.85 * 10).toBe(9657050);
    expect(resolveLineAmount(row)).toBe(9657000);
  });

  it("keeps calculated amount when not in amount entry mode", () => {
    expect(resolveLineAmount(recurringRow)).toBe(9657050);
  });
});

describe("restoreAmountEntryFromSavedAmount", () => {
  const recurringRow = {
    billingType: BILLING_TYPE_RECURRING,
    quantity: 1300,
    unitPrice: 742.85,
    startDate: "2026-05-01",
    endDate: "2027-02-28",
    recordType: PRODUCT_TYPE_REMAKE,
    typeLabel: "Remake"
  };

  it("restores amount entry mode when saved Amount differs from qty×price×cycles", () => {
    const restored = restoreAmountEntryFromSavedAmount({
      ...recurringRow,
      amount: 9657000
    });
    expect(restored.amountEntryMode).toBe(true);
    expect(restored.manualAmount).toBe(9657000);
    expect(resolveLineAmount(restored)).toBe(9657000);
  });

  it("keeps unit-price mode when saved Amount matches calculated", () => {
    const restored = restoreAmountEntryFromSavedAmount({
      ...recurringRow,
      amount: 9657050
    });
    expect(restored.amountEntryMode).toBeFalsy();
    expect(resolveLineAmount(restored)).toBe(9657050);
  });

  it("restores negative Original amount entry mode", () => {
    const restored = restoreAmountEntryFromSavedAmount({
      ...recurringRow,
      recordType: PRODUCT_TYPE_ORIGINAL,
      typeLabel: "Original",
      amount: -9657000
    });
    expect(restored.amountEntryMode).toBe(true);
    expect(restored.manualAmount).toBe(-9657000);
    expect(resolveLineAmount(restored)).toBe(-9657000);
  });

  it("does not override an existing amount entry mode", () => {
    const restored = restoreAmountEntryFromSavedAmount({
      ...recurringRow,
      amount: 1,
      amountEntryMode: true,
      manualAmount: 9657000
    });
    expect(restored.manualAmount).toBe(9657000);
  });
});

describe("resolveAmountEntryRoundingDiff", () => {
  const recurringRow = {
    billingType: BILLING_TYPE_RECURRING,
    quantity: 1300,
    unitPrice: 742.85,
    startDate: "2026-05-01",
    endDate: "2027-02-28",
    recordType: PRODUCT_TYPE_REMAKE,
    typeLabel: "Remake"
  };

  it("returns billing total and delta when amount entry rounds unit price", () => {
    const diff = resolveAmountEntryRoundingDiff({
      ...recurringRow,
      amountEntryMode: true,
      manualAmount: 9657000
    });
    expect(diff).toEqual({
      manualAmount: 9657000,
      billingTotal: 9657050,
      delta: 50
    });
  });

  it("returns null when estimate matches monthly billing regeneration", () => {
    expect(
      resolveAmountEntryRoundingDiff({
        ...recurringRow,
        amountEntryMode: true,
        manualAmount: 9657050
      })
    ).toBeNull();
    // 単価入力でも月次再生成と同額なら警告なし
    expect(resolveAmountEntryRoundingDiff(recurringRow)).toBeNull();
  });

  it("flags unit-price mode when bulk yen rounding differs from monthly regen", () => {
    // 見積一括: round(33.33×12)=400／請求月次: 33×12=396
    const row = {
      billingType: BILLING_TYPE_RECURRING,
      quantity: 1,
      unitPrice: 33.33,
      startDate: "2026-04-01",
      endDate: "2027-03-31",
      recordType: PRODUCT_TYPE_REMAKE,
      typeLabel: "Remake"
    };
    expect(resolveLineAmount(row)).toBe(400);
    expect(calculateMonthlyBillingTotal(row)).toBe(396);
    expect(resolveAmountEntryRoundingDiff(row)).toEqual({
      manualAmount: 400,
      billingTotal: 396,
      delta: -4
    });
  });

  it("flags amount-entry when manual equals bulk but monthly regen differs", () => {
    const row = {
      billingType: BILLING_TYPE_RECURRING,
      quantity: 1,
      unitPrice: 33.33,
      startDate: "2026-04-01",
      endDate: "2027-03-31",
      recordType: PRODUCT_TYPE_REMAKE,
      typeLabel: "Remake",
      amountEntryMode: true,
      manualAmount: 400
    };
    expect(resolveAmountEntryRoundingDiff(row)).toEqual({
      manualAmount: 400,
      billingTotal: 396,
      delta: -4
    });
  });
});

describe("unit price and amount scale", () => {
  it("rounds unit price to 2 decimal places", () => {
    expect(roundUnitPrice(742.854)).toBe(742.85);
    expect(roundUnitPrice(742.855)).toBe(742.86);
    expect(parseUnitPriceInput("1,234.567")).toBe(1234.57);
    // IEEE754 だと 1.005*100 が 100.4999… になり Math.round だと 1.00 になる
    expect(roundUnitPrice(1.005)).toBe(1.01);
    expect(parseUnitPriceInput("1.005")).toBe(1.01);
  });

  it("rounds quantity to 2 decimal places", () => {
    expect(roundQuantity(1.234)).toBe(1.23);
    expect(roundQuantity(1.235)).toBe(1.24);
    expect(parseQuantityInput("0.5")).toBe(0.5);
    expect(parseQuantityInput("1,234.567")).toBe(1234.57);
  });

  it("calculates line amount with fractional quantity", () => {
    expect(
      resolveLineAmount({
        billingType: BILLING_TYPE_ONE_TIME,
        quantity: 1.5,
        unitPrice: 1000
      })
    ).toBe(1500);
  });

  it("avoids IEEE754 drift on common qty × unitPrice (15 × 33.3 → 500)", () => {
    expect(
      resolveLineAmount({
        billingType: BILLING_TYPE_ONE_TIME,
        quantity: 15,
        unitPrice: 33.3
      })
    ).toBe(500);
    // 見積一括: round(15×33.3×12)=round(5994)=5994（月次 round(499.5)×12=6000 とは別式）
    expect(
      resolveLineAmount({
        billingType: BILLING_TYPE_RECURRING,
        quantity: 15,
        unitPrice: 33.3,
        startDate: "2026-04-01",
        endDate: "2027-03-31"
      })
    ).toBe(5994);
  });

  it("rounds amount to integer yen", () => {
    expect(roundAmountYen(100.4)).toBe(100);
    expect(roundAmountYen(100.5)).toBe(101);
    expect(roundAmountYen(-100.5)).toBe(-101);
    expect(parseAmountYenInput("9,657,000.49")).toBe(9657000);
    expect(parseAmountYenInput("9,657,000.50")).toBe(9657001);
  });

  it("negates Original display amount while keeping unsigned calc for billing total", () => {
    const originalRow = {
      billingType: BILLING_TYPE_RECURRING,
      quantity: 1,
      unitPrice: 10000,
      startDate: "2026-04-01",
      endDate: "2027-03-31",
      recordType: PRODUCT_TYPE_ORIGINAL,
      typeLabel: "Original"
    };
    expect(resolveLineAmount(originalRow)).toBe(-120000);
    expect(resolveAmountEntryRoundingDiff(originalRow)).toBeNull();
  });

  it("documents bulk vs monthly rounding gap used by billing regeneration", () => {
    // 見積: round(33.33×12)=400。請求月次: round(33.33)=33 ×12=396（画面で警告）
    expect(roundAmountYen(33.33 * 12)).toBe(400);
    expect(roundAmountYen(33.33) * 12).toBe(396);
  });
});

describe("resolveInvoicePreviewRoundingDiff", () => {
  const sourceId = "cp-source-1";
  const originalRow = {
    billingType: BILLING_TYPE_RECURRING,
    quantity: 1,
    unitPrice: 33.33,
    startDate: "2026-04-01",
    endDate: "2027-03-31",
    recordType: PRODUCT_TYPE_ORIGINAL,
    typeLabel: "Original",
    sourceContractProductId: sourceId,
    productId: "prod-1",
    invoiceType: "一括前払"
  };
  const remakeRow = {
    billingType: BILLING_TYPE_RECURRING,
    quantity: 1,
    unitPrice: 33.33,
    startDate: "2026-04-01",
    endDate: "2027-03-31",
    recordType: PRODUCT_TYPE_REMAKE,
    typeLabel: "Remake",
    sourceContractProductId: sourceId,
    productId: "prod-1",
    invoiceType: "一括前払"
  };
  const newGapRow = {
    billingType: BILLING_TYPE_RECURRING,
    quantity: 1,
    unitPrice: 33.33,
    startDate: "2026-04-01",
    endDate: "2027-03-31",
    recordType: PRODUCT_TYPE_NEW,
    typeLabel: "New",
    productId: "prod-new"
  };

  it("hides Change 据え置き Remake/Original gaps that do not hit invoice preview", () => {
    const products = [originalRow, remakeRow, newGapRow];
    expect(lineageHasChangeBillingEvent(originalRow, [remakeRow])).toBe(false);
    expect(
      resolveInvoicePreviewRoundingDiff(remakeRow, products, { isChange: true })
    ).toBeNull();
    expect(
      resolveInvoicePreviewRoundingDiff(originalRow, products, {
        isChange: true
      })
    ).toBeNull();
  });

  it("shows Change New line gaps that will appear on invoice preview", () => {
    const products = [originalRow, remakeRow, newGapRow];
    expect(
      resolveInvoicePreviewRoundingDiff(newGapRow, products, { isChange: true })
    ).toEqual({
      manualAmount: 400,
      billingTotal: 396,
      delta: -4
    });
  });

  it("shows Change Remake gaps when lineage has a billing event", () => {
    // 内容差は invoiceType で作り、単価ギャップ（33.33）は残す
    const gapRemake = {
      ...remakeRow,
      invoiceType: "月次分割"
    };
    const productsWithGap = [originalRow, gapRemake];
    expect(lineageHasChangeBillingEvent(originalRow, [gapRemake])).toBe(true);
    expect(
      resolveInvoicePreviewRoundingDiff(gapRemake, productsWithGap, {
        isChange: true
      })
    ).toEqual({
      manualAmount: 400,
      billingTotal: 396,
      delta: -4
    });
  });

  it("keeps non-Change behavior (any line gap is alerted)", () => {
    expect(
      resolveInvoicePreviewRoundingDiff(remakeRow, [remakeRow], {
        isChange: false
      })
    ).toEqual({
      manualAmount: 400,
      billingTotal: 396,
      delta: -4
    });
  });
});
