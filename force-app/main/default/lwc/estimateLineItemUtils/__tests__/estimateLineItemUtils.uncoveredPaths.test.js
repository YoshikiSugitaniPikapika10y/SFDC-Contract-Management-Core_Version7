import {
  BILLING_TYPE_ONE_TIME,
  BILLING_TYPE_RECURRING,
  MONTHLY_BILLING_CYCLE,
  PRODUCT_TYPE_NEW,
  PRODUCT_TYPE_ORIGINAL,
  PRODUCT_TYPE_REMAKE,
  PRODUCT_TYPE_RENEW,
  addDaysToIsoDate,
  addMonthsMinusOneDay,
  addYearsMinusOneDay,
  buildDisplayUnit,
  buildUnitPriceSuffix,
  canDuplicateProductLine,
  formatAmountYen,
  formatCurrencyNumber,
  historyTypeDisplayLabel,
  isBlankProductLine,
  isHeaderDatesReady,
  isSplitMonthlyInvoiceSetting,
  isValidIsoDate,
  normalizeDateInput,
  parseCurrencyInput,
  productTypeDisplayLabel,
  resolveDisplayUnit,
  resolveInvoiceSettingBillingCategory,
  resolveProductTypeBadge,
  sameDate,
  validateAmountEntryUnitPrices,
  validateBillingPeriod,
  validateBillingTypeRequired,
  validateCancelEffectiveDate,
  validateCancelProducts,
  validateHeaderDates,
  validateInvoiceSettingForBillingType,
  validateLineDateOrder,
  validateLineWithinHeader,
  validateNewEffectiveDate,
  validateNewHeaderMonthlyPeriod,
  validateRenewEffectiveDate,
  INVOICE_SETTING_SPLIT_MONTHLY,
  INVOICE_SETTING_PREPAID_START
} from "c/estimateLineItemUtils";

describe("estimateLineItemUtils uncovered labels/dates (Core 0.1 / 日付)", () => {
  it("historyTypeDisplayLabel uses 不採用 not 破棄 (Core 0.1)", () => {
    expect(historyTypeDisplayLabel("Archive")).toBe("不採用");
    expect(historyTypeDisplayLabel("New")).toBe("新規");
    expect(historyTypeDisplayLabel("Change")).toBe("追加変更");
    expect(historyTypeDisplayLabel("Unknown")).toBe("Unknown");
    expect(historyTypeDisplayLabel("")).toBe("");
  });

  it("product type badge labels for Original/Remake/New/Renew", () => {
    expect(productTypeDisplayLabel(PRODUCT_TYPE_ORIGINAL)).toBe("変更前");
    expect(productTypeDisplayLabel(PRODUCT_TYPE_REMAKE)).toBe("変更後");
    expect(productTypeDisplayLabel(PRODUCT_TYPE_NEW)).toBe("追加");
    expect(productTypeDisplayLabel(PRODUCT_TYPE_RENEW)).toBe("更新");
    expect(productTypeDisplayLabel(null, "手ラベル")).toBe("手ラベル");
    const badge = resolveProductTypeBadge(PRODUCT_TYPE_ORIGINAL, null);
    expect(badge.typeBadgeLabel).toBe("変更前");
    expect(badge.typeBadgeClass).toContain("est-type-badge_original");
  });

  it("normalizeDateInput / isValidIsoDate / sameDate", () => {
    expect(normalizeDateInput(null)).toBe("");
    expect(normalizeDateInput("2026-01-15")).toBe("2026-01-15");
    expect(normalizeDateInput(" 2026-01-15 ")).toBe("2026-01-15");
    expect(isValidIsoDate("2026-01-15")).toBe(true);
    expect(isValidIsoDate("bad")).toBe(false);
    expect(isValidIsoDate("")).toBe(false);
    expect(sameDate(new Date(2026, 0, 15), new Date(2026, 0, 15))).toBe(true);
    expect(sameDate(new Date(2026, 0, 15), new Date(2026, 0, 16))).toBe(false);
  });

  it("cycle end helpers: 1/31 start 12 cycles ends 翌年1/27 (日付仕様)", () => {
    expect(addYearsMinusOneDay("2025-01-31", 1)).toBe("2026-01-27");
    expect(addMonthsMinusOneDay("2025-01-31", 1)).toBe("2025-02-27");
    expect(addDaysToIsoDate("2025-01-31", 1)).toBe("2025-02-01");
  });

  it("display unit strips ・月 suffix for recurring; unit price suffix", () => {
    expect(buildDisplayUnit("式")).toBe("式");
    expect(buildDisplayUnit("")).toBe("");
    expect(
      resolveDisplayUnit("式・月", null, BILLING_TYPE_RECURRING, MONTHLY_BILLING_CYCLE)
    ).toBe("式");
    expect(
      resolveDisplayUnit("式/月", null, BILLING_TYPE_RECURRING, MONTHLY_BILLING_CYCLE)
    ).toBe("式");
    expect(resolveDisplayUnit(null, "マスタ単位", BILLING_TYPE_RECURRING, "月")).toBe(
      "マスタ単位"
    );
    expect(resolveDisplayUnit("", null, BILLING_TYPE_ONE_TIME, null)).toBe("");
    expect(buildUnitPriceSuffix(BILLING_TYPE_RECURRING)).toBe("/月");
    expect(buildUnitPriceSuffix(BILLING_TYPE_ONE_TIME)).toBe("");
  });

  it("invoice setting validation by billing type (Core 請求設定)", () => {
    expect(isSplitMonthlyInvoiceSetting(INVOICE_SETTING_SPLIT_MONTHLY)).toBe(
      true
    );
    expect(
      validateInvoiceSettingForBillingType(
        BILLING_TYPE_ONE_TIME,
        INVOICE_SETTING_SPLIT_MONTHLY
      )
    ).toBe("一回課金では月次分割は選択できません。");
    expect(
      validateInvoiceSettingForBillingType(
        BILLING_TYPE_RECURRING,
        "不正な請求設定"
      )
    ).toBe("継続課金に対応した請求設定を選択してください。");
    expect(
      validateInvoiceSettingForBillingType("", INVOICE_SETTING_PREPAID_START)
    ).toBe("請求設定が不正です。");
    expect(
      validateInvoiceSettingForBillingType(BILLING_TYPE_ONE_TIME, "")
    ).toBe(null);
    expect(resolveInvoiceSettingBillingCategory(BILLING_TYPE_ONE_TIME)).toBe(
      "OneTime"
    );
    expect(resolveInvoiceSettingBillingCategory(BILLING_TYPE_RECURRING)).toBe(
      "Recurring"
    );
    expect(resolveInvoiceSettingBillingCategory("")).toBe(null);
  });

  it("formatCurrencyNumber / formatAmountYen / parseCurrencyInput", () => {
    expect(formatCurrencyNumber(1234.5)).toBe("1,234.5");
    expect(formatCurrencyNumber(null)).toBe("");
    expect(formatAmountYen(1000)).toBe("1,000");
    expect(formatAmountYen(null)).toBe("");
    expect(parseCurrencyInput("1,234")).toBe(1234);
    expect(parseCurrencyInput("")).toBe(null);
    expect(Number.isNaN(parseCurrencyInput("abc"))).toBe(true);
  });

  it("amount-entry unit price validation (Core 金額入力)", () => {
    expect(validateAmountEntryUnitPrices([])).toBe(null);
    expect(
      validateAmountEntryUnitPrices([
        {
          productId: "01t",
          amountEntryMode: true,
          unitPrice: Number.NaN,
          recordType: PRODUCT_TYPE_NEW
        }
      ])
    ).toMatch(/金額から単価を計算できません/);
    expect(
      validateAmountEntryUnitPrices([
        {
          productId: "01t",
          amountEntryMode: false,
          unitPrice: Number.NaN,
          recordType: PRODUCT_TYPE_NEW
        }
      ])
    ).toMatch(/単価が不正です/);
    expect(
      validateAmountEntryUnitPrices([
        { productId: "01t", amountEntryMode: false, unitPrice: 10 }
      ])
    ).toBe(null);
  });

  it("billing type / period / header / line date gates", () => {
    expect(validateBillingTypeRequired({})).toBe("課金種別を指定してください。");
    expect(validateBillingTypeRequired({ billingType: "不明" })).toMatch(
      /継続課金または一回課金/
    );
    expect(
      validateBillingPeriod({
        billingType: BILLING_TYPE_RECURRING,
        startDate: "",
        endDate: ""
      })
    ).toBe("開始日と終了日を入力してください。");
    expect(
      validateBillingPeriod({
        billingType: BILLING_TYPE_RECURRING,
        startDate: "2025-01-31",
        endDate: "2025-02-28"
      })
    ).toMatch(/月次分割/);
    expect(validateHeaderDates("2025-02-01", "2025-01-01")).toMatch(
      /期間開始日は継続課金の期間終了日以前/
    );
    expect(isHeaderDatesReady("2025-01-01", "2025-01-31")).toBe(true);
    expect(isHeaderDatesReady("", "2025-01-31")).toBe(false);
    expect(
      validateLineDateOrder({ startDate: "2025-02-01", endDate: "2025-01-01" })
    ).toMatch(/開始日は終了日以前/);
    expect(
      validateLineWithinHeader(
        {
          billingType: BILLING_TYPE_RECURRING,
          startDate: "2024-12-01",
          endDate: "2025-01-31"
        },
        "2025-01-01",
        "2025-12-31"
      )
    ).toMatch(/期間開始日以降/);
    expect(
      validateLineWithinHeader(
        {
          billingType: BILLING_TYPE_RECURRING,
          startDate: "2025-01-01",
          endDate: "2026-01-01"
        },
        "2025-01-01",
        "2025-12-31"
      )
    ).toMatch(/期間終了日以前/);
  });

  it("New/Renew/Cancel effective dates and Cancel has no products (Core 4.3)", () => {
    expect(validateNewEffectiveDate("2025-01-01", "2025-01-02")).toMatch(
      /有効日は期間開始日と一致/
    );
    expect(
      validateRenewEffectiveDate("2025-02-01", "2025-02-01", "2025-01-30")
    ).toMatch(/期間終了日の翌日/);
    expect(
      validateCancelEffectiveDate("2025-02-01", "2025-02-02", "2025-01-31")
    ).toMatch(/有効日は解約日と一致/);
    expect(
      validateCancelEffectiveDate("2025-02-02", "2025-02-02", "2025-01-31")
    ).toMatch(/解約日は前回の版の期間終了日の翌日/);
    expect(
      validateCancelProducts([{ productId: "01t", quantity: 1 }])
    ).toBe("解約では商品明細を入力できません。");
    expect(validateCancelProducts([])).toBe(null);
  });

  it("canDuplicateProductLine for New/Change continuation only", () => {
    expect(
      canDuplicateProductLine(
        { recordType: PRODUCT_TYPE_NEW, isReadonly: false },
        { wizardType: "New" }
      )
    ).toBe(true);
    expect(
      canDuplicateProductLine(
        { recordType: PRODUCT_TYPE_ORIGINAL },
        { wizardType: "New" }
      )
    ).toBe(false);
    expect(
      canDuplicateProductLine(
        { recordType: PRODUCT_TYPE_NEW, sourceContractProductId: null },
        { wizardType: "Change" }
      )
    ).toBe(true);
    expect(
      canDuplicateProductLine(
        { recordType: PRODUCT_TYPE_NEW },
        { orderedCustomFieldsOnly: true, wizardType: "New" }
      )
    ).toBe(false);
  });

  it("blank line and new header monthly period", () => {
    expect(isBlankProductLine({})).toBe(true);
    expect(isBlankProductLine({ productId: "01t" })).toBe(false);
    expect(validateNewHeaderMonthlyPeriod("2025-01-31", "2025-02-28")).toMatch(
      /月次/
    );
    expect(validateNewHeaderMonthlyPeriod("2025-01-01", "2025-01-31")).toBe(
      null
    );
  });
});
