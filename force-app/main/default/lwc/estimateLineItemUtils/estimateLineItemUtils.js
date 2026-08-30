/**
 * 見積作成 LWC 共通ユーティリティ。
 * 明細バリデーション・期間／請求形態ルールは Apex（EstimateCreateController /
 * ChangeBillingEventUtil）と定義を揃えること。
 */

export const BILLING_TYPE_RECURRING = "継続課金";

export const MONTHLY_BILLING_CYCLE = "月";

export const BILLING_TYPE_ONE_TIME = "一回課金";

export const INVOICE_BILLING_CATEGORY_RECURRING = "Recurring";

export const INVOICE_BILLING_CATEGORY_ONE_TIME = "OneTime";

export const INVOICE_SETTING_PREPAID_START = "一括前払";
export const INVOICE_SETTING_POSTPAID_NEXT_DAY = "一括後払";
export const INVOICE_SETTING_SPLIT_MONTHLY = "月次分割";

// 仕様: Core 第4.5.2節、ContractMetadataService.REVENUE_BASIS_*
export const REVENUE_BASIS_OVER_TIME = "月次計上";
export const REVENUE_BASIS_POINT_IN_TIME = "一括計上";
export const REVENUE_BASIS_BLANK_MESSAGE = "売上計上基準を選択してください。";
export const REVENUE_BASIS_INVALID_MESSAGE =
  "売上計上基準は月次計上または一括計上です。";

/** 仕様: Core 第11.9節。数量・単価の丸め API 値。 */
export const QUANTITY_UNIT_PRICE_ROUNDING_SCALE2_HALF_UP = "Scale2HalfUp";
/** 仕様: Core 第11.9節。税抜金額の丸め API 値。 */
export const AMOUNT_ROUNDING_SCALE0_HALF_UP = "Scale0HalfUp";

/**
 * 見積ウィザード等で OrgDefault から渡す丸め方式。
 * 未設定のまま丸めると NaN（既定へ落とさない）。
 */
let quantityUnitPriceRoundingMode = null;
let amountRoundingMode = null;

/**
 * 仕様: Core 第4.6節、第11.9節。
 * getDocumentDefaults 等の OrgDefault を画面計算へ載せる。
 */
export function setAmountCalculationRoundingModes(modes) {
  quantityUnitPriceRoundingMode =
    modes && modes.quantityUnitPriceRoundingMode != null
      ? modes.quantityUnitPriceRoundingMode
      : null;
  amountRoundingMode =
    modes && modes.amountRoundingMode != null ? modes.amountRoundingMode : null;
}

/** @returns {{ scale: number } | null} */
function resolveQuantityUnitPriceRounding(mode) {
  if (mode === QUANTITY_UNIT_PRICE_ROUNDING_SCALE2_HALF_UP) {
    return { scale: 2 };
  }
  return null;
}

/** @returns {{ scale: number } | null} */
function resolveAmountRounding(mode) {
  if (mode === AMOUNT_ROUNDING_SCALE0_HALF_UP) {
    return { scale: 0 };
  }
  return null;
}

const RECURRING_INVOICE_SETTING_LABELS = [
  INVOICE_SETTING_PREPAID_START,
  INVOICE_SETTING_POSTPAID_NEXT_DAY,
  INVOICE_SETTING_SPLIT_MONTHLY
];

const ONE_TIME_INVOICE_SETTING_LABELS = [
  INVOICE_SETTING_PREPAID_START,
  INVOICE_SETTING_POSTPAID_NEXT_DAY
];

export function getAllowedInvoiceSettingLabels(billingType) {
  if (billingType === BILLING_TYPE_RECURRING) {
    return RECURRING_INVOICE_SETTING_LABELS;
  }
  if (billingType === BILLING_TYPE_ONE_TIME) {
    return ONE_TIME_INVOICE_SETTING_LABELS;
  }
  return [];
}

export function isAllowedInvoiceSettingForBillingType(
  billingType,
  invoiceType
) {
  const normalizedInvoiceType = normalizeInvoiceSettingLabel(invoiceType);
  if (!normalizedInvoiceType) {
    return false;
  }
  return getAllowedInvoiceSettingLabels(billingType).includes(
    normalizedInvoiceType
  );
}

export const PRODUCT_TYPE_RENEW = "Renew";

export const PRODUCT_TYPE_ORIGINAL = "Original";

export const PRODUCT_TYPE_REMAKE = "Remake";

export const LEGACY_PRODUCT_TYPE_DERIVATIVE = "derivative";

export const PRODUCT_TYPE_NEW = "New";

export function normalizeProductRecordType(recordType) {
  if (!recordType) {
    return PRODUCT_TYPE_NEW;
  }
  const value = String(recordType).trim();
  if (value.toLowerCase() === LEGACY_PRODUCT_TYPE_DERIVATIVE) {
    return PRODUCT_TYPE_REMAKE;
  }
  if (value === PRODUCT_TYPE_ORIGINAL) {
    return PRODUCT_TYPE_ORIGINAL;
  }
  if (value === PRODUCT_TYPE_REMAKE) {
    return PRODUCT_TYPE_REMAKE;
  }
  if (value === PRODUCT_TYPE_RENEW) {
    return PRODUCT_TYPE_RENEW;
  }
  if (value === PRODUCT_TYPE_NEW) {
    return PRODUCT_TYPE_NEW;
  }
  return value;
}

export function isChangeOriginalLine(line) {
  if (!line) {
    return false;
  }
  // Original は recordType のみで判定する（Remake+isReadonly のフォールバックは廃止）。
  return normalizeProductRecordType(line.recordType) === PRODUCT_TYPE_ORIGINAL;
}

export function isChangeRemakeLine(line) {
  if (!line || !line.sourceContractProductId) {
    return false;
  }
  if (isChangeOriginalLine(line)) {
    return false;
  }
  return normalizeProductRecordType(line.recordType) === PRODUCT_TYPE_REMAKE;
}

/** Renew で引き継いだ継続課金行（手追加の Type=New は含まない） */
export function isRenewProductLine(line) {
  if (!line) {
    return false;
  }
  return normalizeProductRecordType(line.recordType) === PRODUCT_TYPE_RENEW;
}

/** 仕様: Core 第4.5.2節、第4.4.1節。Remake／Original は課金形態を変えない。 */
export function isBillingTypeLockedLine(line) {
  if (!line) {
    return false;
  }
  const recordType = normalizeProductRecordType(line.recordType);
  return (
    recordType === PRODUCT_TYPE_REMAKE ||
    recordType === PRODUCT_TYPE_ORIGINAL
  );
}

export function historyTypeDisplayLabel(historyType) {
  const labels = {
    New: "新規",
    Change: "追加変更",
    Renew: "更新",
    Cancel: "解約",
    Estimate: "見積",
    Ordered: "受注済み",
    Archive: "不採用"
  };
  return labels[historyType] || historyType || "";
}

export function productTypeDisplayLabel(recordType, typeLabel) {
  const normalized = normalizeProductRecordType(recordType || typeLabel);
  const displayByType = {
    [PRODUCT_TYPE_ORIGINAL]: "変更前",
    [PRODUCT_TYPE_REMAKE]: "変更後",
    [PRODUCT_TYPE_RENEW]: "更新",
    [PRODUCT_TYPE_NEW]: "追加"
  };
  return displayByType[normalized] || typeLabel || "追加";
}

export function resolveProductTypeBadge(recordType, typeLabel) {
  const normalized = normalizeProductRecordType(recordType);
  const label = productTypeDisplayLabel(normalized, typeLabel);
  const badgeClassByType = {
    [PRODUCT_TYPE_ORIGINAL]: "est-type-badge_original",
    [PRODUCT_TYPE_REMAKE]: "est-type-badge_remake",
    [PRODUCT_TYPE_NEW]: "est-type-badge_new",
    [PRODUCT_TYPE_RENEW]: "est-type-badge_renew"
  };
  return {
    showTypeBadge: true,
    typeBadgeLabel: label,
    typeBadgeClass: `est-type-badge ${badgeClassByType[normalized] || "est-type-badge_new"}`
  };
}

export function parseLocalDate(isoDate) {
  if (!isoDate) {
    return null;
  }

  const parts = isoDate.split("-");

  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
}

function daysInMonth(year, monthIndex) {
  return new Date(year, monthIndex + 1, 0).getDate();
}

function isCalendarMonthStart(date) {
  return date.getDate() === 1;
}

function isCalendarMonthEnd(date) {
  return date.getDate() === daysInMonth(date.getFullYear(), date.getMonth());
}

/**
 * Keep day-of-month with clamp for short months.
 * Billing-period math relies on this non-sticky behavior.
 */
function addMonthsToDate(date, months) {
  const targetDay = date.getDate();

  const result = new Date(date.getFullYear(), date.getMonth(), 1);

  result.setMonth(result.getMonth() + months);

  const lastDayOfMonth = daysInMonth(result.getFullYear(), result.getMonth());

  result.setDate(Math.min(targetDay, lastDayOfMonth));

  return result;
}

function addYearsToDate(date, years) {
  const targetDay = date.getDate();

  const targetMonth = date.getMonth();

  const result = new Date(date.getFullYear() + years, targetMonth, 1);

  const lastDayOfMonth = daysInMonth(result.getFullYear(), targetMonth);

  result.setDate(Math.min(targetDay, lastDayOfMonth));

  return result;
}

/**
 * If the source date is calendar month-end / month-start,
 * force the result to the same boundary in the target month.
 * Used by wizard ±y/±m shortcuts so chained nudges stay sticky.
 */
function applyStickyMonthBoundary(sourceDate, resultDate) {
  if (isCalendarMonthEnd(sourceDate)) {
    resultDate.setDate(
      daysInMonth(resultDate.getFullYear(), resultDate.getMonth())
    );
  } else if (isCalendarMonthStart(sourceDate)) {
    resultDate.setDate(1);
  }

  return resultDate;
}

export function formatLocalDate(date) {
  const year = date.getFullYear();

  const month = String(date.getMonth() + 1).padStart(2, "0");

  const day = String(date.getDate()).padStart(2, "0");

  return `${year}-${month}-${day}`;
}

export function addDaysToIsoDate(isoDate, days) {
  const date = parseLocalDate(isoDate);

  if (!date) {
    return "";
  }

  return formatLocalDate(addDays(date, days));
}

// 仕様: 日付仕様 第1.3節
export function addYearsToIsoDate(isoDate, years) {
  const date = parseLocalDate(isoDate);

  if (!date || years == null) {
    return "";
  }

  return formatLocalDate(
    applyStickyMonthBoundary(date, addYearsToDate(date, years))
  );
}

// 仕様: 日付仕様 第1.3節
export function addMonthsToIsoDate(isoDate, months) {
  const date = parseLocalDate(isoDate);

  if (!date || months == null) {
    return "";
  }

  return formatLocalDate(
    applyStickyMonthBoundary(date, addMonthsToDate(date, months))
  );
}

/**
 * 仕様: 日付仕様 第1.2節、第2.5節。
 * 開始日から cycles 回分の月次期間を積んだ終了日。
 */
export function endDateForMonthlyCycles(isoStartDate, cycles) {
  const start = parseLocalDate(isoStartDate);
  const n = Number(cycles);

  if (!start || !Number.isFinite(n) || n < 1) {
    return "";
  }

  let periodStart = new Date(start);
  let periodEnd;

  for (let i = 0; i < n; i++) {
    periodEnd = endOfMonthlyPeriod(periodStart);
    periodStart = addDays(periodEnd, 1);
  }

  return formatLocalDate(periodEnd);
}

/** @deprecated 暦の +N年-1日ではない。endDateForMonthlyCycles(start, years*12) と同義。 */
export function addYearsMinusOneDay(isoStartDate, years) {
  const n = Number(years);
  if (!Number.isFinite(n)) {
    return "";
  }
  return endDateForMonthlyCycles(isoStartDate, n * 12);
}

export function addOneYearMinusOneDay(isoStartDate) {
  return endDateForMonthlyCycles(isoStartDate, 12);
}

/** @deprecated 暦の +N月-1日ではない。endDateForMonthlyCycles(start, months) と同義。 */
export function addMonthsMinusOneDay(isoStartDate, months) {
  return endDateForMonthlyCycles(isoStartDate, months);
}

export function normalizeDateInput(value) {
  if (!value) {
    return "";
  }

  const trimmed = String(value).trim();

  if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    return trimmed;
  }

  const date = parseLocalDate(trimmed);

  if (!date) {
    return trimmed;
  }

  return formatLocalDate(date);
}

export function isValidIsoDate(value) {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }

  const date = parseLocalDate(value);

  return !!date && formatLocalDate(date) === value;
}

export function sameDate(left, right) {
  return (
    left.getFullYear() === right.getFullYear() &&
    left.getMonth() === right.getMonth() &&
    left.getDate() === right.getDate()
  );
}

export function addDays(date, days) {
  const result = new Date(date);

  result.setDate(result.getDate() + days);

  return result;
}

// 仕様: 日付仕様 第1.1節、第1.2節
export function endOfMonthlyPeriod(periodStart) {
  const end = addMonthsToDate(new Date(periodStart), 1);

  end.setDate(end.getDate() - 1);

  return end;
}

/** マスタ単位をそのまま表示する（継続課金でも「・月」は付与しない）。 */
export function buildDisplayUnit(unitName) {
  return unitName || "";
}

export function resolveDisplayUnit(unit, unitName, billingType, billingCycle) {
  if (unitName) {
    return unitName;
  }

  if (!unit) {
    return "";
  }

  if (billingType === BILLING_TYPE_RECURRING && billingCycle) {
    const suffix = `・${billingCycle}`;

    if (unit.endsWith(suffix)) {
      return unit.slice(0, -suffix.length);
    }

    const legacySuffix = `/${billingCycle}`;

    if (unit.endsWith(legacySuffix)) {
      return unit.slice(0, -legacySuffix.length);
    }
  }

  return unit;
}

export function buildUnitPriceSuffix(billingType) {
  if (billingType === BILLING_TYPE_RECURRING) {
    return `/${MONTHLY_BILLING_CYCLE}`;
  }

  return "";
}

/** Identity for now; kept as the single normalization entry point for invoice labels. */
export function normalizeInvoiceSettingLabel(invoiceSettingLabel) {
  return invoiceSettingLabel;
}

export function isSplitMonthlyInvoiceSetting(invoiceSettingLabel) {
  return (
    normalizeInvoiceSettingLabel(invoiceSettingLabel) ===
    INVOICE_SETTING_SPLIT_MONTHLY
  );
}

export function validateInvoiceSettingForBillingType(billingType, invoiceType) {
  const normalizedInvoiceType = normalizeInvoiceSettingLabel(invoiceType);
  if (!normalizedInvoiceType) {
    return null;
  }

  if (
    billingType === BILLING_TYPE_ONE_TIME &&
    isSplitMonthlyInvoiceSetting(normalizedInvoiceType)
  ) {
    return "一回課金では月次分割は選択できません。";
  }

  if (
    isAllowedInvoiceSettingForBillingType(billingType, normalizedInvoiceType)
  ) {
    return null;
  }

  if (billingType === BILLING_TYPE_ONE_TIME) {
    return "一回課金では月次分割は選択できません。";
  }
  if (billingType === BILLING_TYPE_RECURRING) {
    return "継続課金に対応した請求設定を選択してください。";
  }
  return "請求設定が不正です。";
}

export function resolveInvoiceSettingBillingCategory(billingType) {
  if (billingType === BILLING_TYPE_ONE_TIME) {
    return INVOICE_BILLING_CATEGORY_ONE_TIME;
  }

  if (billingType === BILLING_TYPE_RECURRING) {
    return INVOICE_BILLING_CATEGORY_RECURRING;
  }

  return null;
}

export function filterInvoiceSettingOptions(options, billingType) {
  const allowedLabels = getAllowedInvoiceSettingLabels(billingType);
  if (!allowedLabels.length) {
    return [];
  }

  return allowedLabels.map((label, index) => {
    const matched = (options || []).find((option) => option.label === label);
    return {
      label,
      billingCategory: resolveInvoiceSettingBillingCategory(billingType),
      sortOrder: matched?.sortOrder ?? (index + 1) * 10
    };
  });
}

// 仕様: Core 第1.1.10節
export function resolveInvoiceTypeForBillingType(
  invoiceType,

  billingType,

  allOptions,

  fallbackLabel,

  options = {}
) {
  const category = resolveInvoiceSettingBillingCategory(billingType);

  if (!category) {
    return "";
  }

  const normalizedInvoiceType = normalizeInvoiceSettingLabel(invoiceType);

  const filteredOptions = filterInvoiceSettingOptions(allOptions, billingType);

  if (
    normalizedInvoiceType &&
    filteredOptions.some((option) => option.label === normalizedInvoiceType)
  ) {
    return normalizedInvoiceType;
  }

  // 不正な既存値は黙って置換しない（呼び出し側でエラーにする）。
  if (normalizedInvoiceType) {
    return normalizedInvoiceType;
  }

  // Change の Original／Remake 等は空を組織既定で埋めない（BUG-094）。
  if (options.fillBlankWithDefault === false) {
    return "";
  }

  // 空のときだけ、課金種別に合うデフォルトを埋める（New 等の初期値）。
  const optionsLoaded = Array.isArray(allOptions) && allOptions.length > 0;
  if (optionsLoaded) {
    const normalizedFallback = normalizeInvoiceSettingLabel(fallbackLabel);
    if (
      isAllowedInvoiceSettingForBillingType(billingType, normalizedFallback)
    ) {
      return normalizedFallback;
    }
  }

  return "";
}

// 仕様: 日付仕様 第1.2節
export function countBillingCycles(startDate, endDate) {
  if (!startDate || !endDate) {
    return null;
  }

  return countMonthlyCycles(startDate, endDate);
}

/**
 * 終了日以下で完了する最後の月次期間終了日（切り捨て寄せ）。
 * 1期間も完了しなければ ""。
 */
export function floorMonthlyEndDate(startDate, endDate) {
  if (!startDate || !endDate) {
    return "";
  }

  const start = parseLocalDate(startDate);
  const end = parseLocalDate(endDate);

  if (!start || !end || end < start) {
    return "";
  }

  let lastCompleteEnd = null;
  let periodStart = new Date(start);

  while (true) {
    const periodEnd = endOfMonthlyPeriod(periodStart);

    if (periodEnd > end) {
      break;
    }

    lastCompleteEnd = periodEnd;

    if (sameDate(periodEnd, end)) {
      return formatLocalDate(end);
    }

    periodStart = addDays(periodEnd, 1);
  }

  return lastCompleteEnd ? formatLocalDate(lastCompleteEnd) : "";
}

/**
 * 境界に乗っていればそのまま、乗っていなければ短い側へ寄せる。
 * （以前の resolveMonthlyEndDate の伸ばし寄せは廃止）
 */
export function alignMonthlyEndDate(startDate, endDate) {
  if (!startDate || !endDate) {
    return endDate || "";
  }

  if (countMonthlyCycles(startDate, endDate) >= 1) {
    return endDate;
  }

  return floorMonthlyEndDate(startDate, endDate) || endDate;
}

/** @deprecated alignMonthlyEndDate と同義（伸ばし寄せはしない）。 */
export function resolveMonthlyEndDate(startDate, endDate) {
  return alignMonthlyEndDate(startDate, endDate);
}

/**
 * アンカー開始日基準で、現在終了のサイクル数 ± delta の終了日。
 * 未整列なら一度切り捨ててから加減する。最小 1 サイクル。
 */
export function adjustMonthlyEndByCycles(startDate, endDate, deltaCycles) {
  if (!startDate) {
    return endDate || "";
  }

  const delta = Number(deltaCycles);
  if (!Number.isFinite(delta) || delta === 0) {
    return endDate || "";
  }

  let cycles = countMonthlyCycles(startDate, endDate);
  if (cycles < 1) {
    if (endDate) {
      const floored = floorMonthlyEndDate(startDate, endDate);
      cycles = floored ? countMonthlyCycles(startDate, floored) : 0;
    } else {
      cycles = 0;
    }
  }

  const next = cycles + delta;
  return endDateForMonthlyCycles(startDate, Math.max(1, next));
}

function countMonthlyCycles(startDate, endDate) {
  const start = parseLocalDate(startDate);

  const end = parseLocalDate(endDate);

  if (!start || !end || end < start) {
    return -1;
  }

  let cycles = 0;

  let periodStart = new Date(start);

  while (true) {
    const periodEnd = endOfMonthlyPeriod(periodStart);

    if (periodEnd > end) {
      return -1;
    }

    cycles++;

    if (sameDate(periodEnd, end)) {
      return cycles;
    }

    periodStart = addDays(periodEnd, 1);
  }
}

export function calculateLineAmount(row) {
  const qty = Number(row.quantity) || 0;
  const price = Number(row.unitPrice) || 0;

  if (
    row.billingType === BILLING_TYPE_RECURRING &&
    row.startDate &&
    row.endDate
  ) {
    const cycles = countBillingCycles(row.startDate, row.endDate);

    if (cycles == null || cycles < 1) {
      return null;
    }

    // 浮動小数の qty*price*cycles は 15×33.3→499.4999… になり得るため整数スケールで計算する。
    return yenFromQuantityUnitPrice(qty, price, cycles);
  }

  return yenFromQuantityUnitPrice(qty, price, 1);
}

/**
 * 行の確定金額。金額入力モードでは manualAmount（UI 入力値）を優先し、
 * それ以外は calculateLineAmount + Original 符号反転。
 */
export function resolveLineAmount(row) {
  if (row && row.amountEntryMode === true && row.manualAmount != null) {
    const manual = roundAmountYen(row.manualAmount);
    return Number.isFinite(manual) ? manual : Number.NaN;
  }

  let amount = calculateLineAmount(row);
  if (amount == null) {
    return null;
  }
  if (isChangeOriginalLine(row)) {
    amount = -amount;
  }
  return amount;
}

/**
 * 請求商品生成と同式の見込み合計（符号なし）。
 * 継続: roundYen(qty×unitPrice) × 月数／一回: roundYen(qty×unitPrice)。
 * 見積の一括丸め roundYen(qty×unitPrice×月数) とは小数単価でずれ得る。
 */
export function calculateMonthlyBillingTotal(row) {
  if (!row) {
    return null;
  }
  const qty = Number(row.quantity) || 0;
  const price = Number(row.unitPrice) || 0;
  if (!Number.isFinite(qty) || !Number.isFinite(price)) {
    return null;
  }
  const monthly = yenFromQuantityUnitPrice(qty, price, 1);
  if (!Number.isFinite(monthly)) {
    return null;
  }
  if (row.billingType === BILLING_TYPE_RECURRING) {
    if (!row.startDate || !row.endDate) {
      return null;
    }
    const cycles = countBillingCycles(row.startDate, row.endDate);
    if (cycles == null || cycles < 1) {
      return null;
    }
    return monthly * cycles;
  }
  return monthly;
}

/**
 * 見積確定金額と、請求再生成見込み（月ごと round(qty×unitPrice) の合計）の差分。
 * 金額入力モードに限らず、単価入力の小数単価による一括丸めギャップも検知する。
 * 一致していれば null。ずれれば { manualAmount(=見積側), billingTotal, delta }。
 *
 * 画面アラート用は resolveInvoicePreviewRoundingDiff を使うこと
 * （Change 据え置き系統など、請求プレビューに載らない行は除外する）。
 */
export function resolveAmountEntryRoundingDiff(row) {
  if (!row) {
    return null;
  }
  const estimateAmount = resolveLineAmount(row);
  if (estimateAmount == null || !Number.isFinite(Number(estimateAmount))) {
    return null;
  }
  const estimate = Number(estimateAmount);

  let billingTotal = calculateMonthlyBillingTotal(row);
  if (billingTotal == null || !Number.isFinite(Number(billingTotal))) {
    return null;
  }
  billingTotal = Number(billingTotal);
  if (isChangeOriginalLine(row)) {
    billingTotal = -billingTotal;
  }
  const delta = billingTotal - estimate;
  if (delta === 0) {
    return null;
  }
  return { manualAmount: estimate, billingTotal, delta };
}

/**
 * Change の Original/Remake 系統に課金イベントがあるか（Apex ChangeBillingEventUtil と同定義）。
 */
export function lineageHasChangeBillingEvent(original, remakes) {
  if (!original || !Array.isArray(remakes) || remakes.length === 0) {
    return false;
  }
  const datedRemakes = remakes
    .filter((line) => line && line.startDate)
    .slice()
    .sort((left, right) =>
      (left.startDate || "").localeCompare(right.startDate || "")
    );
  if (!datedRemakes.length) {
    return false;
  }
  const first = datedRemakes[0];
  if (
    original.startDate &&
    first.startDate &&
    first.startDate > original.startDate
  ) {
    return true;
  }
  for (const remake of datedRemakes) {
    if (doesChangeBillingContentDiffer(remake, original)) {
      return true;
    }
    if (
      remake.endDate &&
      original.endDate &&
      remake.endDate > original.endDate
    ) {
      return true;
    }
  }
  return false;
}

function resolveChangeLineagePair(row, products) {
  if (!row || !row.sourceContractProductId || !Array.isArray(products)) {
    return null;
  }
  if (!isChangeOriginalLine(row) && !isChangeRemakeLine(row)) {
    return null;
  }
  const sourceId = row.sourceContractProductId;
  const original = products.find(
    (line) =>
      isChangeOriginalLine(line) && line.sourceContractProductId === sourceId
  );
  const remakes = products.filter(
    (line) =>
      isChangeRemakeLine(line) && line.sourceContractProductId === sourceId
  );
  return { original, remakes };
}

function lineageHasChangeBillingEventForRow(row, products) {
  const pair = resolveChangeLineagePair(row, products);
  if (!pair || !isChangeRemakeLine(row)) {
    return false;
  }
  return lineageHasChangeBillingEvent(pair.original, pair.remakes);
}

/**
 * Change の据え置き Original/Remake（課金イベントなし）か。
 * products が無いときは判定できないため false（非表示にしない）。
 */
export function isUnchangedChangeLineageRow(row, products) {
  const pair = resolveChangeLineagePair(row, products);
  if (!pair) {
    return false;
  }
  return !lineageHasChangeBillingEvent(pair.original, pair.remakes);
}

/**
 * 請求プレビューに端数ずれが載り得る明細だけ差分を返す（ウィザード端数アラート用）。
 * - New/Renew: 行ギャップがあれば返す（従来どおり）
 * - Change: New（追加行）と課金イベントあり Remake のみ。Original／据え置き Remake は null
 */
export function resolveInvoicePreviewRoundingDiff(row, products, options = {}) {
  const diff = resolveAmountEntryRoundingDiff(row);
  if (diff == null) {
    return null;
  }
  if (options.isChange !== true) {
    return diff;
  }
  if (isChangeOriginalLine(row)) {
    return null;
  }
  if (isChangeRemakeLine(row)) {
    return lineageHasChangeBillingEventForRow(row, products) ? diff : null;
  }
  return diff;
}

/**
 * Change 起動時: 前回見積商品 Amount（符号付き）から Original／Remake 初期金額を作る。
 * Original = -(前回Amount)、Remake = 前回Amount。
 * 値引き（負 Amount）でも Math.abs せず符号を保持する。
 */
export function resolveChangePairAmountsFromSource(sourceAmount) {
  if (
    sourceAmount === null ||
    sourceAmount === undefined ||
    sourceAmount === ""
  ) {
    return { originalAmount: null, remakeAmount: null };
  }
  const signed = roundAmountYen(sourceAmount);
  if (!Number.isFinite(signed)) {
    return { originalAmount: Number.NaN, remakeAmount: Number.NaN };
  }
  return {
    originalAmount: -signed,
    remakeAmount: signed
  };
}

/**
 * 編集・コピー読込時用。見積商品に保存された Amount が見積画面の金額正本なので、
 * 数量×単価（×月数）と一致しない場合は金額入力モードとして復元する。
 * すでに金額入力モードなら何もしない。
 */
export function restoreAmountEntryFromSavedAmount(row) {
  if (!row || row.amountEntryMode === true) {
    return row;
  }
  if (row.amount == null || row.amount === "") {
    return row;
  }
  const saved = roundAmountYen(row.amount);
  if (!Number.isFinite(saved)) {
    return row;
  }

  let billingTotal = calculateLineAmount(row);
  if (billingTotal == null || !Number.isFinite(Number(billingTotal))) {
    // 期間不正などで再計算できない場合も、保存額を表示できるよう金額入力へ寄せる
    return {
      ...row,
      amountEntryMode: true,
      manualAmount: saved
    };
  }
  billingTotal = Number(billingTotal);
  if (isChangeOriginalLine(row)) {
    billingTotal = -billingTotal;
  }
  if (saved === roundAmountYen(billingTotal)) {
    return row;
  }
  return {
    ...row,
    amountEntryMode: true,
    manualAmount: saved
  };
}

/** Format a number for currency-like display (thousands separators). */
export function formatCurrencyNumber(value) {
  if (value === null || value === undefined || value === "") {
    return "";
  }
  const n =
    typeof value === "number" ? value : Number(String(value).replace(/,/g, ""));
  if (!Number.isFinite(n)) {
    return "";
  }
  return n.toLocaleString("ja-JP", {
    maximumFractionDigits: 2
  });
}

/** 金額（円）表示。整数のみ。 */
export function formatAmountYen(value) {
  if (value === null || value === undefined || value === "") {
    return "";
  }
  const n =
    typeof value === "number" ? value : Number(String(value).replace(/,/g, ""));
  if (!Number.isFinite(n)) {
    return "";
  }
  return n.toLocaleString("ja-JP", {
    maximumFractionDigits: 0
  });
}

/**
 * Parse a currency-like input (allows commas) into a finite number.
 * Blank/null returns null (missing) so callers can distinguish it from an
 * explicit 0. Unparseable non-blank input returns NaN so it can be flagged
 * as invalid.
 */
export function parseCurrencyInput(raw) {
  if (raw === null || raw === undefined) {
    return null;
  }
  const cleaned = String(raw).replace(/,/g, "").trim();
  if (cleaned === "") {
    return null;
  }
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : Number.NaN;
}

/**
 * Apex Decimal.setScale(scale, RoundingMode.HALF_UP) 相当。
 * 0.5 タイはゼロから遠ざける。value は number または十進文字列。
 * Math.round(n*10^scale) は 1.005 や乗算結果で桁落ちするため使わない。
 */
function roundHalfUp(value, scale = 0) {
  if (typeof scale !== "number" || !Number.isInteger(scale) || scale < 0) {
    return Number.NaN;
  }
  const normalized = normalizeSignedPlainDecimal(value);
  if (normalized == null) {
    return Number.NaN;
  }
  const { sign, plain } = normalized;
  const dot = plain.indexOf(".");
  let intDigits = dot === -1 ? plain : plain.slice(0, dot);
  let fracDigits = dot === -1 ? "" : plain.slice(dot + 1);
  intDigits = intDigits.replace(/^0+(?=\d)/, "") || "0";

  if (fracDigits.length <= scale) {
    const frac = fracDigits.padEnd(scale, "0");
    return sign * Number(scale === 0 ? intDigits : `${intDigits}.${frac}`);
  }

  const shouldBump = fracDigits.charAt(scale) >= "5";
  let scaled = intDigits + fracDigits.slice(0, scale);
  if (shouldBump) {
    scaled = incrementDigitString(scaled);
  }
  if (scale === 0) {
    return sign * Number(scaled);
  }
  if (scaled.length <= scale) {
    return sign * Number(`0.${scaled.padStart(scale, "0")}`);
  }
  const splitAt = scaled.length - scale;
  return sign * Number(`${scaled.slice(0, splitAt)}.${scaled.slice(splitAt)}`);
}

/** number / 十進文字列 → { sign, plain }。不正値は null。 */
function normalizeSignedPlainDecimal(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  if (typeof value === "string") {
    let str = value.replace(/,/g, "").trim();
    if (str === "") {
      return null;
    }
    let sign = 1;
    if (str.startsWith("-")) {
      sign = -1;
      str = str.slice(1);
    } else if (str.startsWith("+")) {
      str = str.slice(1);
    }
    if (!/^\d+(\.\d+)?$/.test(str)) {
      return null;
    }
    return { sign, plain: str };
  }
  const n = Number(value);
  if (!Number.isFinite(n)) {
    return null;
  }
  if (n === 0) {
    return { sign: 1, plain: "0" };
  }
  return {
    sign: n < 0 ? -1 : 1,
    plain: toPlainDecimalString(Math.abs(n))
  };
}

/** 絶対値 number を指数表記なしの十進文字列にする。 */
function toPlainDecimalString(absNumber) {
  let s = String(absNumber);
  if (!/[eE]/.test(s)) {
    return s;
  }
  const match = s.match(/^(\d+)(?:\.(\d+))?e([+-]?\d+)$/i);
  if (!match) {
    return s;
  }
  const intPart = match[1];
  const fracPart = match[2] || "";
  const exp = Number(match[3]);
  const digits = intPart + fracPart;
  if (exp >= 0) {
    const zeros = exp - fracPart.length;
    if (zeros >= 0) {
      return digits + "0".repeat(zeros);
    }
    const splitAt = digits.length + zeros;
    return `${digits.slice(0, splitAt)}.${digits.slice(splitAt)}`;
  }
  const zeros = -exp - 1;
  return `0.${"0".repeat(zeros)}${digits}`;
}

function incrementDigitString(digits) {
  const chars = digits.split("");
  for (let i = chars.length - 1; i >= 0; i -= 1) {
    if (chars[i] !== "9") {
      chars[i] = String(Number(chars[i]) + 1);
      return chars.join("");
    }
    chars[i] = "0";
  }
  return `1${chars.join("")}`;
}

/** 小数 scale 桁 HALF_UP 後の整数（value × 10^scale）。 */
function toScaledInt(value, scale) {
  const rounded = roundHalfUp(value, scale);
  if (!Number.isFinite(rounded)) {
    return Number.NaN;
  }
  if (rounded === 0) {
    return 0;
  }
  const sign = rounded < 0 ? -1 : 1;
  const plain = toPlainDecimalString(Math.abs(rounded));
  const dot = plain.indexOf(".");
  const intDigits =
    (dot === -1 ? plain : plain.slice(0, dot)).replace(/^0+(?=\d)/, "") || "0";
  const frac = (
    (dot === -1 ? "" : plain.slice(dot + 1)) + "0".repeat(scale)
  ).slice(0, scale);
  return sign * Number(intDigits + frac);
}

/** 整数同士の除算を HALF_UP で商（整数）にする。 */
function divideIntHalfUp(numerator, denominator) {
  if (numerator === 0) {
    return 0;
  }
  const sign = numerator < 0 ? -1 : 1;
  const abs = Math.abs(numerator);
  const quotient = Math.floor(abs / denominator);
  const remainder = abs % denominator;
  if (remainder * 2 >= denominator) {
    return sign * (quotient + 1);
  }
  return sign * quotient;
}

/**
 * 数量×単価×回数を整数円。数量・単価・税抜は第11.9節の OrgDefault。
 */
function yenFromQuantityUnitPrice(quantity, unitPrice, cycles = 1) {
  const qtyResolved = resolveQuantityUnitPriceRounding(
    quantityUnitPriceRoundingMode
  );
  const amountResolved = resolveAmountRounding(amountRoundingMode);
  if (!qtyResolved || !amountResolved) {
    return Number.NaN;
  }
  const q = toScaledInt(quantity, qtyResolved.scale);
  const p = toScaledInt(unitPrice, qtyResolved.scale);
  const c = Number(cycles);
  if (!Number.isFinite(q) || !Number.isFinite(p) || !Number.isFinite(c)) {
    return Number.NaN;
  }
  const denom = 10 ** (qtyResolved.scale * 2);
  return divideIntHalfUp(q * p * c, denom);
}

/** 単価: OrgDefault の数量・単価丸め。null/NaN はそのまま。未設定は NaN。 */
export function roundUnitPrice(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const resolved = resolveQuantityUnitPriceRounding(
    quantityUnitPriceRoundingMode
  );
  if (!resolved) {
    return Number.NaN;
  }
  return roundHalfUp(value, resolved.scale);
}

/** 数量: OrgDefault の数量・単価丸め。null/NaN はそのまま。未設定は NaN。 */
export function roundQuantity(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const resolved = resolveQuantityUnitPriceRounding(
    quantityUnitPriceRoundingMode
  );
  if (!resolved) {
    return Number.NaN;
  }
  return roundHalfUp(value, resolved.scale);
}

/** 金額: OrgDefault の税抜丸め。null/NaN はそのまま。未設定は NaN。 */
export function roundAmountYen(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const resolved = resolveAmountRounding(amountRoundingMode);
  if (!resolved) {
    return Number.NaN;
  }
  return roundHalfUp(value, resolved.scale);
}

/** 単価入力のパース（OrgDefault の数量・単価丸め）。文字列桁を優先して丸める。 */
export function parseUnitPriceInput(raw) {
  if (raw === null || raw === undefined) {
    return null;
  }
  const cleaned = String(raw).replace(/,/g, "").trim();
  if (cleaned === "") {
    return null;
  }
  const resolved = resolveQuantityUnitPriceRounding(
    quantityUnitPriceRoundingMode
  );
  if (!resolved) {
    return Number.NaN;
  }
  const rounded = roundHalfUp(cleaned, resolved.scale);
  return Number.isFinite(rounded) ? rounded : Number.NaN;
}

/** 数量入力のパース（OrgDefault の数量・単価丸め）。文字列桁を優先して丸める。 */
export function parseQuantityInput(raw) {
  if (raw === null || raw === undefined) {
    return null;
  }
  const cleaned = String(raw).replace(/,/g, "").trim();
  if (cleaned === "") {
    return null;
  }
  const resolved = resolveQuantityUnitPriceRounding(
    quantityUnitPriceRoundingMode
  );
  if (!resolved) {
    return Number.NaN;
  }
  const rounded = roundHalfUp(cleaned, resolved.scale);
  return Number.isFinite(rounded) ? rounded : Number.NaN;
}

/** 金額入力のパース（OrgDefault の税抜丸め）。文字列桁を優先して丸める。 */
export function parseAmountYenInput(raw) {
  if (raw === null || raw === undefined) {
    return null;
  }
  const cleaned = String(raw).replace(/,/g, "").trim();
  if (cleaned === "") {
    return null;
  }
  const resolved = resolveAmountRounding(amountRoundingMode);
  if (!resolved) {
    return Number.NaN;
  }
  const rounded = roundHalfUp(cleaned, resolved.scale);
  return Number.isFinite(rounded) ? rounded : Number.NaN;
}

const AMOUNT_FORMULA_ERROR = "数式が不正です（四則と括弧のみ）";
const AMOUNT_FORMULA_DIVZERO = "0で割れません";
const AMOUNT_FORMULA_EMPTY = "数式を入力してください";
const AMOUNT_FORMULA_NEED_INT = "整数円に調整してください";
const AMOUNT_FORMULA_RANGE = "計算結果を金額にできません";
const AMOUNT_ABS_MAX = 1e13;

/**
 * 金額欄の四則式を評価する（eval 禁止）。
 * expression は先頭 `=` を含まない本体。空白・カンマは無視。
 * @returns {{ ok: true, value: number } | { ok: false, message: string }}
 */
export function evaluateAmountFormula(expression) {
  if (expression === null || expression === undefined) {
    return { ok: false, message: AMOUNT_FORMULA_EMPTY };
  }
  const src = String(expression).trim();
  if (src === "") {
    return { ok: false, message: AMOUNT_FORMULA_EMPTY };
  }
  // 許可文字以外は拒否（コード実行・未知演算子を防ぐ）
  if (!/^[0-9+\-*/().,\s]+$/.test(src)) {
    return { ok: false, message: AMOUNT_FORMULA_ERROR };
  }

  let i = 0;
  const peek = () => src[i];
  const skipWs = () => {
    while (i < src.length && /\s/.test(src[i])) {
      i += 1;
    }
  };
  const fail = (message) => {
    throw new Error(message || AMOUNT_FORMULA_ERROR);
  };

  const parseNumber = () => {
    skipWs();
    const start = i;
    let sawDigit = false;
    let sawDot = false;
    while (i < src.length) {
      const ch = src[i];
      if (ch === ",") {
        i += 1;
        continue;
      }
      if (ch >= "0" && ch <= "9") {
        sawDigit = true;
        i += 1;
        continue;
      }
      if (ch === "." && !sawDot) {
        sawDot = true;
        i += 1;
        continue;
      }
      break;
    }
    if (!sawDigit) {
      fail(AMOUNT_FORMULA_ERROR);
    }
    const token = src.slice(start, i).replace(/,/g, "");
    if (token === "." || token.endsWith(".")) {
      fail(AMOUNT_FORMULA_ERROR);
    }
    const n = Number(token);
    if (!Number.isFinite(n)) {
      fail(AMOUNT_FORMULA_ERROR);
    }
    return n;
  };

  const parseFactor = () => {
    skipWs();
    const ch = peek();
    if (ch === "+" || ch === "-") {
      i += 1;
      const v = parseFactor();
      return ch === "-" ? -v : v;
    }
    if (ch === "(") {
      i += 1;
      // eslint-disable-next-line no-use-before-define
      const v = parseExpr();
      skipWs();
      if (peek() !== ")") {
        fail(AMOUNT_FORMULA_ERROR);
      }
      i += 1;
      return v;
    }
    return parseNumber();
  };

  const parseTerm = () => {
    let v = parseFactor();
    for (;;) {
      skipWs();
      const op = peek();
      if (op !== "*" && op !== "/") {
        break;
      }
      i += 1;
      const rhs = parseFactor();
      if (op === "*") {
        v *= rhs;
      } else {
        if (rhs === 0) {
          fail(AMOUNT_FORMULA_DIVZERO);
        }
        v /= rhs;
      }
    }
    return v;
  };

  const parseExpr = () => {
    let v = parseTerm();
    for (;;) {
      skipWs();
      const op = peek();
      if (op !== "+" && op !== "-") {
        break;
      }
      i += 1;
      const rhs = parseTerm();
      v = op === "+" ? v + rhs : v - rhs;
    }
    return v;
  };

  try {
    const value = parseExpr();
    skipWs();
    if (i !== src.length) {
      return { ok: false, message: AMOUNT_FORMULA_ERROR };
    }
    if (!Number.isFinite(value)) {
      return { ok: false, message: AMOUNT_FORMULA_RANGE };
    }
    if (Math.abs(value) > AMOUNT_ABS_MAX) {
      return { ok: false, message: AMOUNT_FORMULA_RANGE };
    }
    return { ok: true, value };
  } catch (e) {
    return {
      ok: false,
      message: e && e.message ? e.message : AMOUNT_FORMULA_ERROR
    };
  }
}

/** 小数第2位までの金額下書き表示（式の非整数結果用）。 */
export function formatAmountDraft(value) {
  if (value === null || value === undefined || value === "") {
    return "";
  }
  const n =
    typeof value === "number" ? value : Number(String(value).replace(/,/g, ""));
  if (!Number.isFinite(n)) {
    return "";
  }
  const rounded = roundHalfUp(n, 2);
  if (!Number.isFinite(rounded)) {
    return "";
  }
  return rounded.toLocaleString("ja-JP", {
    minimumFractionDigits: Number.isInteger(rounded) ? 0 : 2,
    maximumFractionDigits: 2
  });
}

/**
 * 金額ポップアップの入力を解決する。
 * - 先頭 `=` → 四則式。整数なら commit、非整数なら draft（小数第2位・手動で整数化）
 * - それ以外 → 既定は整数円四捨五入で commit
 * - options.requireInteger=true（式で非整数を出したあと）のときは四捨五入せず、
 *   整数円以外は draft のままブロックする
 * @returns {{ ok: true, kind: 'commit'|'draft', value: number, display: string, message?: string }
 *   | { ok: false, message: string }}
 */
export function resolveAmountInputDraft(raw, options = {}) {
  const requireInteger = options && options.requireInteger === true;
  if (raw === null || raw === undefined) {
    return { ok: false, message: "金額を入力してください" };
  }
  const text = String(raw).trim();
  if (text === "") {
    return { ok: false, message: "金額を入力してください" };
  }
  if (text.startsWith("=")) {
    const expr = text.slice(1).trim();
    const evaluated = evaluateAmountFormula(expr);
    if (!evaluated.ok) {
      return evaluated;
    }
    const qtyResolved = resolveQuantityUnitPriceRounding(
      quantityUnitPriceRoundingMode
    );
    const amountResolved = resolveAmountRounding(amountRoundingMode);
    if (!qtyResolved || !amountResolved) {
      return { ok: false, message: AMOUNT_FORMULA_RANGE };
    }
    const asMoney2 = roundHalfUp(evaluated.value, qtyResolved.scale);
    if (!Number.isFinite(asMoney2)) {
      return { ok: false, message: AMOUNT_FORMULA_RANGE };
    }
    const asYen = roundHalfUp(asMoney2, amountResolved.scale);
    if (asMoney2 === asYen) {
      return {
        ok: true,
        kind: "commit",
        value: asYen,
        display: formatAmountYen(asYen)
      };
    }
    return {
      ok: true,
      kind: "draft",
      value: asMoney2,
      display: formatAmountDraft(asMoney2),
      message: AMOUNT_FORMULA_NEED_INT
    };
  }
  if (requireInteger) {
    const cleaned = text.replace(/,/g, "").trim();
    if (cleaned === "" || !/^[+-]?\d+(\.\d+)?$/.test(cleaned)) {
      return { ok: false, message: AMOUNT_FORMULA_ERROR };
    }
    const qtyResolved = resolveQuantityUnitPriceRounding(
      quantityUnitPriceRoundingMode
    );
    const amountResolved = resolveAmountRounding(amountRoundingMode);
    if (!qtyResolved || !amountResolved) {
      return { ok: false, message: AMOUNT_FORMULA_RANGE };
    }
    const asMoney2 = roundHalfUp(cleaned, qtyResolved.scale);
    if (!Number.isFinite(asMoney2)) {
      return { ok: false, message: AMOUNT_FORMULA_RANGE };
    }
    const asYen = roundHalfUp(asMoney2, amountResolved.scale);
    if (asMoney2 !== asYen) {
      return {
        ok: true,
        kind: "draft",
        value: asMoney2,
        display: formatAmountDraft(asMoney2),
        message: AMOUNT_FORMULA_NEED_INT
      };
    }
    return {
      ok: true,
      kind: "commit",
      value: asYen,
      display: formatAmountYen(asYen)
    };
  }
  const yen = parseAmountYenInput(text);
  if (yen === null) {
    return { ok: false, message: "金額を入力してください" };
  }
  if (!Number.isFinite(yen)) {
    return { ok: false, message: AMOUNT_FORMULA_ERROR };
  }
  return {
    ok: true,
    kind: "commit",
    value: yen,
    display: formatAmountYen(yen)
  };
}

/**
 * 単価など小数 scale 桁の入力。先頭 `=` なら四則式、否则は数値。
 * 結果は常に scale 桁 HALF_UP で commit（金額円の「非整数は手修正」ルールは使わない）。
 * @returns {{ ok: true, value: number, display: string } | { ok: false, message: string }}
 */
export function resolveScaledNumericInput(raw, scale = 2) {
  if (typeof scale !== "number" || !Number.isInteger(scale) || scale < 0) {
    return { ok: false, message: AMOUNT_FORMULA_ERROR };
  }
  if (raw === null || raw === undefined) {
    return { ok: false, message: "数値を入力してください" };
  }
  const text = String(raw).trim();
  if (text === "") {
    return { ok: false, message: "数値を入力してください" };
  }
  let numeric;
  if (text.startsWith("=")) {
    const evaluated = evaluateAmountFormula(text.slice(1).trim());
    if (!evaluated.ok) {
      return evaluated;
    }
    numeric = evaluated.value;
  } else {
    if (!/^[0-9+\-.,\s]+$/.test(text)) {
      return { ok: false, message: AMOUNT_FORMULA_ERROR };
    }
    const cleaned = text.replace(/,/g, "").trim();
    numeric = Number(cleaned);
    if (!Number.isFinite(numeric)) {
      return { ok: false, message: AMOUNT_FORMULA_ERROR };
    }
  }
  if (!Number.isFinite(numeric) || Math.abs(numeric) > AMOUNT_ABS_MAX) {
    return { ok: false, message: AMOUNT_FORMULA_RANGE };
  }
  const rounded = roundHalfUp(numeric, scale);
  if (!Number.isFinite(rounded)) {
    return { ok: false, message: AMOUNT_FORMULA_RANGE };
  }
  return {
    ok: true,
    value: rounded,
    display: rounded.toLocaleString("ja-JP", {
      minimumFractionDigits: 0,
      maximumFractionDigits: scale
    })
  };
}

/**
 * Divisor for amount ↔ unitPrice: quantity, or quantity × cycles for recurring.
 * Returns null when cycles cannot be resolved.
 */
export function resolveAmountDivisor(row) {
  const qty = Number(row && row.quantity) || 0;
  if (qty <= 0) {
    return null;
  }
  if (row.billingType === BILLING_TYPE_RECURRING) {
    if (!row.startDate || !row.endDate) {
      return null;
    }
    const cycles = countBillingCycles(row.startDate, row.endDate);
    if (cycles == null || cycles < 1) {
      return null;
    }
    return qty * cycles;
  }
  return qty;
}

/**
 * Derive unitPrice from an entered line amount (UI sign).
 * Change Original rows display a negated amount; reverse that for the price.
 */
export function deriveUnitPriceFromAmount(row, enteredAmount) {
  const divisor = resolveAmountDivisor(row);
  if (divisor == null || divisor === 0) {
    return Number.NaN;
  }
  let unsigned = Number(enteredAmount) || 0;
  if (isChangeOriginalLine(row)) {
    unsigned = -unsigned;
  }
  return roundUnitPrice(unsigned / divisor);
}

/**
 * Amount-entry mode: unitPrice must be a finite number derived from amount.
 */
export function validateAmountEntryUnitPrices(products) {
  if (!products || products.length === 0) {
    return null;
  }
  for (let i = 0; i < products.length; i++) {
    const line = products[i];
    if (!line || !line.productId || line.isReadonly === true) {
      continue;
    }
    const price = Number(line.unitPrice);
    if (line.amountEntryMode === true && !Number.isFinite(price)) {
      const label = productTypeDisplayLabel(line.recordType, line.typeLabel);
      return `商品明細（${label}）: 金額から単価を計算できません（数量またはサイクル数が0です）。`;
    }
    if (Number.isNaN(price)) {
      const label = productTypeDisplayLabel(line.recordType, line.typeLabel);
      return `商品明細（${label}）: 単価が不正です（NaN）。`;
    }
  }
  return null;
}

export function validateBillingTypeRequired(row) {
  if (!row || !row.billingType) {
    return "課金種別を指定してください。";
  }
  if (
    row.billingType !== BILLING_TYPE_RECURRING &&
    row.billingType !== BILLING_TYPE_ONE_TIME
  ) {
    return "課金種別は継続課金または一回課金を指定してください。";
  }
  return null;
}

export function validateBillingPeriod(row) {
  if (row.billingType !== BILLING_TYPE_RECURRING) {
    return null;
  }

  if (!row.startDate || !row.endDate) {
    return "開始日と終了日を入力してください。";
  }

  // 終了日を正規化して通さない（ヘッダー期間と同じ厳密判定）。
  const cycles = countBillingCycles(row.startDate, row.endDate);

  if (cycles == null || cycles < 1) {
    return "開始日・終了日は明細開始日起点の月次分割である必要があります（カレンダー月分割は使えません）。";
  }

  return null;
}

export function isActiveLine(row) {
  return !!(row.productId && Number(row.quantity) > 0);
}

export function validateHeaderDates(startDate, endDate) {
  if (!startDate || !endDate) {
    return null;
  }

  if (startDate > endDate) {
    return "継続課金の期間開始日は継続課金の期間終了日以前の日付を入力してください。";
  }

  return null;
}

export function isHeaderDatesReady(startDate, endDate) {
  return !!(startDate && endDate && !validateHeaderDates(startDate, endDate));
}

export function validateLineDateOrder(row) {
  if (!row.startDate || !row.endDate) {
    return null;
  }

  if (row.startDate > row.endDate) {
    return "開始日は終了日以前の日付を入力してください。";
  }

  return null;
}

export function validateLineWithinHeader(row, headerStart, headerEnd) {
  if (!row.startDate || !row.endDate || !headerStart || !headerEnd) {
    return null;
  }

  // 一回課金は継続課金の契約期間と非連動
  if (!isRecurringLine(row)) {
    return null;
  }

  if (row.startDate < headerStart) {
    return "開始日は期間開始日以降の日付を入力してください。";
  }

  if (row.endDate > headerEnd) {
    return "終了日は期間終了日以前の日付を入力してください。";
  }

  return null;
}

export function isRecurringLine(row) {
  if (row.billingType === BILLING_TYPE_RECURRING) {
    return true;
  }

  if (row.billingType === BILLING_TYPE_ONE_TIME) {
    return false;
  }

  if (!row.invoiceType) {
    return false;
  }

  const normalizedInvoiceType = normalizeInvoiceSettingLabel(row.invoiceType);
  return (
    normalizedInvoiceType === INVOICE_SETTING_PREPAID_START ||
    normalizedInvoiceType === INVOICE_SETTING_POSTPAID_NEXT_DAY ||
    normalizedInvoiceType === INVOICE_SETTING_SPLIT_MONTHLY
  );
}

export function validateNewHeaderMonthlyPeriod(headerStart, headerEnd) {
  if (!headerStart || !headerEnd) {
    return null;
  }

  const cycles = countBillingCycles(headerStart, headerEnd);

  if (cycles == null || cycles < 1) {
    return "期間開始日と期間終了日はヘッダー期間開始日起点の月次分割である必要があります（カレンダー月分割は使えません）。";
  }

  return null;
}

export function validateNewRecurringEndpointCoverage(
  products,
  headerStart,
  headerEnd
) {
  const recurringLines = (products || []).filter(
    (line) => isActiveLine(line) && isRecurringLine(line)
  );

  if (!recurringLines.length) {
    return null;
  }

  const hasStartMatch = recurringLines.some(
    (line) => line.startDate === headerStart
  );

  const hasEndMatch = recurringLines.some((line) => line.endDate === headerEnd);

  if (!hasStartMatch) {
    return "期間開始日と一致する開始日の継続課金明細が1件以上必要です。";
  }

  if (!hasEndMatch) {
    return "期間終了日と一致する終了日の継続課金明細が1件以上必要です。";
  }

  return null;
}

export function validateChangeRecurringEndEndpointCoverage(
  products,
  headerEnd
) {
  const recurringLines = (products || []).filter(
    (line) =>
      !isChangeOriginalLine(line) && isActiveLine(line) && isRecurringLine(line)
  );

  if (!recurringLines.length) {
    return null;
  }

  const hasEndMatch = recurringLines.some((line) => line.endDate === headerEnd);

  if (!hasEndMatch) {
    return "期間終了日と一致する終了日の継続課金明細が1件以上必要です。";
  }

  return null;
}

export function validateNewProductPeriodOverlap(products) {
  const activeLines = (products || []).filter(
    (line) => isActiveLine(line) && !isChangeOriginalLine(line)
  );

  for (let i = 0; i < activeLines.length; i++) {
    const left = activeLines[i];

    if (!left.startDate || !left.endDate) {
      continue;
    }

    for (let j = i + 1; j < activeLines.length; j++) {
      const right = activeLines[j];

      if (left.productId !== right.productId) {
        continue;
      }

      if (!right.startDate || !right.endDate) {
        continue;
      }

      if (left.startDate <= right.endDate && left.endDate >= right.startDate) {
        // 仕様: Core 第4.5.1節。一回×一回は許可。継続どうしと継続×一回だけ不可。
        if (isRecurringLine(left) || isRecurringLine(right)) {
          return "同一商品の契約期間が重複しています。商品ごとに期間が重ならないよう入力してください。";
        }
      }
    }
  }

  return null;
}

export function isBlankProductLine(row) {
  return !row.productId && (row.quantity == null || Number(row.quantity) <= 0);
}

/** 仕様: Core 第4.3.9節 */
export const QUANTITY_MIN = 0.01;

export const QUANTITY_MIN_MESSAGE =
  "数量は0.01以上を入力してください。課金を止める場合は、数量はそのままで単価を0にしてください。";

function validateQuantityMin(row) {
  const quantity = row == null ? null : Number(row.quantity);
  if (
    row == null ||
    row.quantity == null ||
    !Number.isFinite(quantity) ||
    quantity < QUANTITY_MIN
  ) {
    return QUANTITY_MIN_MESSAGE;
  }
  return null;
}

export function validateNewEffectiveDate(periodStartDate, effectiveDate) {
  if (!effectiveDate) {
    return null;
  }

  if (periodStartDate && effectiveDate !== periodStartDate) {
    return "有効日は期間開始日と一致している必要があります。";
  }

  return null;
}

export function validateRenewEffectiveDate(
  periodStartDate,
  effectiveDate,
  previousTermEndDate
) {
  if (previousTermEndDate && periodStartDate) {
    const expectedStart = addDaysToIsoDate(previousTermEndDate, 1);
    if (periodStartDate !== expectedStart) {
      return "期間開始日は前回の版の期間終了日の翌日である必要があります。";
    }
  }

  return validateNewEffectiveDate(periodStartDate, effectiveDate);
}

export function validateCancelEffectiveDate(
  cancelDate,
  effectiveDate,
  previousTermEndDate
) {
  if (previousTermEndDate && cancelDate) {
    const expectedCancelDate = addDaysToIsoDate(previousTermEndDate, 1);
    if (cancelDate !== expectedCancelDate) {
      return "解約日は前回の版の期間終了日の翌日である必要があります。";
    }
  }

  if (effectiveDate && cancelDate && effectiveDate !== cancelDate) {
    return "有効日は解約日と一致している必要があります。";
  }

  return null;
}

/** 仕様: Core 第0.1節、第4.3節 */
export function validateCancelProducts(products) {
  const activeLines = (products || []).filter(isActiveLine);
  if (activeLines.length > 0) {
    return "解約では商品明細を入力できません。";
  }
  return null;
}

function decimalsEqual(left, right) {
  if (left == null && right == null) {
    return true;
  }
  if (left == null || right == null) {
    return false;
  }
  return Number(left) === Number(right);
}

export function isChangeContinuationLine(line) {
  if (!line || isChangeOriginalLine(line) || isChangeRemakeLine(line)) {
    return false;
  }
  const recordType = normalizeProductRecordType(line.recordType);
  if (recordType === PRODUCT_TYPE_NEW && !line.sourceContractProductId) {
    return true;
  }
  if (recordType === PRODUCT_TYPE_REMAKE && !line.sourceContractProductId) {
    return true;
  }
  return false;
}

/** Type=New の編集可能行のみ。コピー結果は常に Type=New（§4.0.4）。 */
export function canDuplicateProductLine(line, options = {}) {
  const { orderedCustomFieldsOnly = false, wizardType = "" } = options;

  if (orderedCustomFieldsOnly || !line || line.isReadonly === true) {
    return false;
  }
  if (normalizeProductRecordType(line.recordType) !== PRODUCT_TYPE_NEW) {
    return false;
  }
  if (wizardType === "New" || wizardType === "Renew") {
    return true;
  }
  if (wizardType === "Change") {
    return isChangeContinuationLine(line);
  }
  return false;
}

/**
 * Change の「新しい商品」(New) が、Original/Remake 系統と同じ Product2 を持つ行を返す。
 * キーは productId（Product2 Id）。追加購入は許可しつつ、延長・変更の誤入力を警告するための検出。
 */
export function findChangeNewLinesWithSameProductAsRemake(products) {
  const lines = Array.isArray(products) ? products : [];
  const lineageProductIds = new Set();
  for (const line of lines) {
    if (!line || !line.productId) {
      continue;
    }
    if (isChangeOriginalLine(line) || isChangeRemakeLine(line)) {
      lineageProductIds.add(String(line.productId));
    }
  }
  if (lineageProductIds.size === 0) {
    return [];
  }

  const matched = [];
  const seenProductIds = new Set();
  for (const line of lines) {
    if (!line || !line.productId) {
      continue;
    }
    if (!isChangeContinuationLine(line)) {
      continue;
    }
    if (normalizeProductRecordType(line.recordType) !== PRODUCT_TYPE_NEW) {
      continue;
    }
    const productId = String(line.productId);
    if (!lineageProductIds.has(productId) || seenProductIds.has(productId)) {
      continue;
    }
    seenProductIds.add(productId);
    matched.push(line);
  }
  return matched;
}

/**
 * 同 Product2 の New がある場合の確認メッセージ。該当なしなら null。
 */
export function buildChangeSameProductNewConfirmMessage(products) {
  const matched = findChangeNewLinesWithSameProductAsRemake(products);
  if (!matched.length) {
    return null;
  }
  const names = matched
    .map((line) => String(line.productName || "").trim())
    .filter((name) => name.length > 0);
  const lines = ["既存契約と同じ商品が新規明細に含まれています。"];
  if (names.length > 0) {
    lines.push(`対象商品: ${names.join("、")}`);
  }
  lines.push(
    "条件変更や期間延長は既存明細を編集してください。追加購入の場合はそのまま続行できます。"
  );
  return lines.join("\n");
}

function isReconstitutionSegment(line) {
  return !!(
    line &&
    line.productId &&
    line.startDate &&
    line.endDate &&
    Number(line.quantity) > 0
  );
}

/**
 * Remake のみで Original 期間カバーを判定する。
 * 「新しい商品」は新規追加専用であり、穴埋めには使わない。
 */
function buildRemakeReconstitutionSegments(derivatives) {
  const segments = [];
  for (const derivative of derivatives || []) {
    if (isReconstitutionSegment(derivative)) {
      segments.push(derivative);
    }
  }
  segments.sort((left, right) => left.startDate.localeCompare(right.startDate));
  return segments;
}

/** 仕様: Core 第0.1節、第1.3節、第4.3.13節 */
export function validateChangeReconstitutionCoverage(original, derivatives) {
  const coverageError =
    "変更後は変更前の期間を重複や隙間なく埋める必要があります。";

  if (!original || !derivatives || !derivatives.length) {
    return "変更後の商品明細を1行以上入力してください。";
  }

  const segments = buildRemakeReconstitutionSegments(derivatives);
  if (!segments.length) {
    return "変更後の商品明細を1行以上入力してください。";
  }

  // Remake 先頭は Original 開始日と一致必須（遅延開始・前倒し開始ともに不可）。
  if (
    original.startDate &&
    segments[0].startDate &&
    segments[0].startDate !== original.startDate
  ) {
    if (segments[0].startDate < original.startDate) {
      return "変更後の開始日は変更前の開始日より前にできません。";
    }
    return coverageError;
  }

  for (let index = 0; index < segments.length - 1; index += 1) {
    const expectedNextStart = addDaysToIsoDate(segments[index].endDate, 1);
    // 隣接必須（終了日の翌日 = 次の開始日）。重複・隙間の両方を弾く。
    if (segments[index + 1].startDate !== expectedNextStart) {
      return coverageError;
    }
  }

  const lastSegment = segments[segments.length - 1];
  // Original終了日までカバーすること。終了日の延長（lastEnd > originalEnd）は許容。
  if (
    original.endDate &&
    (!lastSegment.endDate || lastSegment.endDate < original.endDate)
  ) {
    return coverageError;
  }

  return null;
}

/**
 * 仕様: Core 第0.1節、第1.3節、第1.6.2節、第1.6.3節、第4.4節、第7.8.5節。
 * 期中切替（内容差分の開始が Original 開始より後）では、
 * 切替日前は Original 同条件の Remake、切替日以降の Remake が必要。
 * 全期間1本の洗替（差分開始＝Original開始）は対象外。
 */
export const CHANGE_MID_TERM_REMAKE_SPLIT_MESSAGE =
  "期中切替では、切替日前は変更前と同条件の変更後と、切替日以降の変更後に分けてください。";

export function validateChangeMidTermRemakeSplit(original, derivatives) {
  if (!original || !derivatives || !derivatives.length) {
    return null;
  }
  if (original.billingType === BILLING_TYPE_ONE_TIME) {
    return null;
  }
  const remakes = (derivatives || [])
    .filter((line) => isChangeRemakeLine(line) && line.startDate)
    .slice()
    .sort((left, right) =>
      (left.startDate || "").localeCompare(right.startDate || "")
    );
  if (!remakes.length || !original.startDate) {
    return null;
  }
  let firstDiffering = null;
  for (const remake of remakes) {
    if (doesChangeBillingContentDiffer(remake, original)) {
      firstDiffering = remake;
      break;
    }
  }
  if (!firstDiffering || !firstDiffering.startDate) {
    return null;
  }
  if (firstDiffering.startDate <= original.startDate) {
    return null;
  }
  const dayBefore = addDaysToIsoDate(firstDiffering.startDate, -1);
  if (!dayBefore) {
    return CHANGE_MID_TERM_REMAKE_SPLIT_MESSAGE;
  }
  const pre = remakes.find((line) => line && line.endDate === dayBefore);
  if (!pre || doesChangeBillingContentDiffer(pre, original)) {
    return CHANGE_MID_TERM_REMAKE_SPLIT_MESSAGE;
  }
  if (firstDiffering.startDate !== addDaysToIsoDate(pre.endDate, 1)) {
    return CHANGE_MID_TERM_REMAKE_SPLIT_MESSAGE;
  }
  return null;
}

/**
 * Change保存時は Step3 明細を加工せず 1:1 で返す。
 * （以前は Remake を有効日以降へ再構成し、数量0化や New へのマージをしていた）
 */
export function normalizeChangeProductsForSave(products) {
  if (!products || !products.length) {
    return products || [];
  }

  return products
    .filter((line) => line && line.productId)
    .map((line) => {
      const recordType = normalizeProductRecordType(line.recordType);
      return {
        ...line,
        recordType,
        typeLabel: line.typeLabel || recordType
      };
    });
}

/**
 * Change の課金イベント用の内容差（Apex ChangeBillingEventUtil.doesBillingContentDiffer と同定義）。
 * 仕様: Core 第4.4.1節 — 請求設定の差は継続課金イベントではない。
 */
function doesChangeBillingContentDiffer(line, original) {
  if (!line || !original) {
    return false;
  }
  if (line.productId !== original.productId) {
    return true;
  }
  if (!decimalsEqual(line.quantity, original.quantity)) {
    return true;
  }
  if (!decimalsEqual(line.unitPrice, original.unitPrice)) {
    return true;
  }
  return false;
}

/**
 * Changeで課金イベントが発生する日付一覧（有効日閾値の候補）。
 * Remakeの内容差分開始日・途中開始、終了日延長の開始日（Original終了翌日）、
 * Continuation開始日。
 * 差分がなければ空配列（contractStart へのフォールバックはしない）。
 */
export function collectChangeBillingEventDates(products) {
  return collectChangeBillingEventEntries(products).map((entry) => entry.date);
}

/**
 * Change の課金イベント（日付＋一回課金由来か＋元明細開始日）。
 * 仕様: Core 第4.4節、日付仕様 第2.3節。サイクル境界は元明細開始日起点。
 */
export function collectChangeBillingEventEntries(products) {
  const entries = [];
  const originalsBySourceId = new Map();
  const remakesBySourceId = new Map();

  for (const line of products || []) {
    if (isChangeOriginalLine(line) && line.sourceContractProductId) {
      originalsBySourceId.set(line.sourceContractProductId, line);
      continue;
    }
    if (isChangeRemakeLine(line) && line.sourceContractProductId) {
      const sourceId = line.sourceContractProductId;
      if (!remakesBySourceId.has(sourceId)) {
        remakesBySourceId.set(sourceId, []);
      }
      remakesBySourceId.get(sourceId).push(line);
      continue;
    }
    if (
      isChangeContinuationLine(line) &&
      line.productId &&
      line.startDate &&
      Number(line.quantity) > 0
    ) {
      entries.push({
        date: line.startDate,
        isOneTimeOnly: line.billingType === BILLING_TYPE_ONE_TIME,
        sourceStartDate: line.startDate
      });
    }
  }

  for (const [sourceId, original] of originalsBySourceId.entries()) {
    const remakes = (remakesBySourceId.get(sourceId) || [])
      .filter((line) => line && line.startDate)
      .slice()
      .sort((left, right) =>
        (left.startDate || "").localeCompare(right.startDate || "")
      );
    if (!remakes.length) {
      continue;
    }

    const first = remakes[0];
    const pairIsOneTimeOnly =
      original.billingType === BILLING_TYPE_ONE_TIME ||
      first.billingType === BILLING_TYPE_ONE_TIME;
    if (
      original.startDate &&
      first.startDate &&
      first.startDate > original.startDate
    ) {
      // Original/Remake 系統の途中開始。一回課金系統は切替日計算から除外。
      entries.push({
        date: first.startDate,
        isOneTimeOnly: pairIsOneTimeOnly,
        sourceStartDate: original.startDate
      });
    }

    for (const remake of remakes) {
      const remakeIsOneTimeOnly =
        original.billingType === BILLING_TYPE_ONE_TIME ||
        remake.billingType === BILLING_TYPE_ONE_TIME;
      if (doesChangeBillingContentDiffer(remake, original)) {
        entries.push({
          date: remake.startDate,
          isOneTimeOnly: remakeIsOneTimeOnly,
          sourceStartDate: original.startDate
        });
      }
      // 終了日延長のみ（内容同一）も課金イベント。延長開始日 = Original終了翌日。
      if (
        original.endDate &&
        remake.endDate &&
        remake.endDate > original.endDate
      ) {
        const extensionStart = addDaysToIsoDate(original.endDate, 1);
        if (extensionStart) {
          entries.push({
            date: extensionStart,
            isOneTimeOnly: remakeIsOneTimeOnly,
            sourceStartDate: original.startDate
          });
        }
      }
    }
  }

  return entries;
}

/**
 * 仕様: Core 第4.4節、日付仕様 第2.2節。
 * 継続課金由来の課金イベントがあるときだけ、有効日を請求期間開始日に縛る。
 * イベント0件や一回課金 New 追加のみは切替日必須にしない。
 */
export function requiresChangeEffectiveDateOnBillingPeriodStart(products) {
  const entries = collectChangeBillingEventEntries(products);
  if (!entries.length) {
    return false;
  }
  return entries.some((entry) => entry && entry.isOneTimeOnly !== true);
}

/**
 * 仕様: Core 第4.3.5節、第4.4節。Change の課金イベントがすべて一回課金 New 追加のみか。
 */
export function isChangeOneTimeAddOnly(products) {
  const entries = collectChangeBillingEventEntries(products);
  if (!entries.length) {
    return false;
  }
  return entries.every((entry) => entry && entry.isOneTimeOnly === true);
}

export function hasChangeBillingEventWithinPreviousTerm(
  products,
  previousTermStartDate,
  previousTermEndDate
) {
  if (!previousTermStartDate || !previousTermEndDate) {
    return false;
  }
  return collectChangeBillingEventDates(products).some(
    (eventDate) =>
      eventDate &&
      eventDate >= previousTermStartDate &&
      eventDate <= previousTermEndDate
  );
}

export const CHANGE_REQUIRES_BILLING_EVENT_MESSAGE =
  "前回の版の期間内に課金変更（追加・変更後・相殺）がないため、追加変更ではなく更新で作成してください。";

/** 仕様: Core 第4.5.2節※7、第4.4.2節#8。BE `CHANGE_CUSTOM_FIELDS_ONLY_MESSAGE` と同文。 */
export const CHANGE_CUSTOM_FIELDS_ONLY_MESSAGE =
  "カスタム項目だけを変えた追加変更は成立しません。数量・単価などと同時に変更してください。";

export function validateChangeHasBillingEventInPreviousTerm(
  products,
  previousTermStartDate,
  previousTermEndDate
) {
  if (!previousTermStartDate || !previousTermEndDate) {
    return null;
  }
  // 仕様: Core 第4.4節。BE と同じく一回課金 New 追加のみだけ免除（イベント0件は Renew 誘導へ）。
  if (isChangeOneTimeAddOnly(products)) {
    return null;
  }
  if (
    hasChangeBillingEventWithinPreviousTerm(
      products,
      previousTermStartDate,
      previousTermEndDate
    )
  ) {
    return null;
  }
  return CHANGE_REQUIRES_BILLING_EVENT_MESSAGE;
}

/**
 * 仕様: Core 第4.5.2節※7、第4.4.2節#8。
 * BE `assertChangeIsNotCustomFieldOnly` と同型。画面保存前に同文で止める。
 */
export function validateChangeIsNotCustomFieldOnly(products, sourceProducts) {
  if (isChangeOneTimeAddOnly(products)) {
    return null;
  }
  if (collectChangeBillingEventEntries(products).length) {
    return null;
  }
  if (!hasRemakeCustomFieldDiffFromSource(products, sourceProducts)) {
    return null;
  }
  return CHANGE_CUSTOM_FIELDS_ONLY_MESSAGE;
}

function customFieldValuesEqual(left, right) {
  if (left == null && right == null) {
    return true;
  }
  if (left == null || right == null) {
    return false;
  }
  if (typeof left === "boolean" || typeof right === "boolean") {
    return Boolean(left) === Boolean(right);
  }
  return String(left) === String(right);
}

function hasRemakeCustomFieldDiffFromSource(products, sourceProducts) {
  const sourceById = buildSourceProductMap(sourceProducts);
  if (!sourceById.size) {
    return false;
  }
  for (const line of products || []) {
    if (!isChangeRemakeLine(line) || !line.sourceContractProductId) {
      continue;
    }
    const source = sourceById.get(line.sourceContractProductId);
    if (!source) {
      continue;
    }
    const previousFields = source.customFields || {};
    const remakeFields = line.customFields || {};
    const apiNames = new Set([
      ...Object.keys(previousFields),
      ...Object.keys(remakeFields)
    ]);
    for (const apiName of apiNames) {
      if (
        !customFieldValuesEqual(
          previousFields[apiName],
          remakeFields[apiName]
        )
      ) {
        return true;
      }
    }
  }
  return false;
}

/**
 * Change の継続課金切替日の基準日（最古）。
 * 一回課金 New 追加・一回課金系統のイベントは含めない。
 * 継続イベントがなければ null（切替日不要）。
 */
export function getEarliestChangeBillingThresholdDate(products) {
  const dates = collectChangeBillingEventEntries(products)
    .filter((entry) => entry && entry.date && entry.isOneTimeOnly !== true)
    .map((entry) => entry.date);
  if (!dates.length) {
    return null;
  }
  dates.sort();
  return dates[0];
}

/** 仕様: Core 第4.4節、日付仕様 第2.3節。BE `CHANGE_EFFECTIVE_DATE_BILLING_PERIOD_START_MESSAGE` と同文。 */
export const CHANGE_EFFECTIVE_DATE_BILLING_PERIOD_START_MESSAGE =
  "切替日および課金イベント日は元明細開始日起点の請求期間開始日である必要があります（日割りはできません）。";

export function validateChangeEffectiveDate(
  effectiveDate,
  previousTermStartDate,
  previousTermEndDate,
  contractStartDate,
  products
) {
  // 継続課金イベントが無い（一回課金の追加・変更のみ）なら切替日は検証しない
  if (!requiresChangeEffectiveDateOnBillingPeriodStart(products)) {
    return null;
  }
  if (!effectiveDate) {
    return "切替日を入力してください。";
  }
  if (
    previousTermStartDate &&
    effectiveDate &&
    effectiveDate < previousTermStartDate
  ) {
    return "切替日は前回の版の契約開始日から契約終了日の間で入力してください。";
  }
  if (
    previousTermEndDate &&
    effectiveDate &&
    effectiveDate > previousTermEndDate
  ) {
    return "切替日が前回の版の契約終了日を超えているため、追加変更ではなく更新で作成してください。";
  }
  const sourceCycleError = validateChangeBillingEventsOnSourceCycle(products);
  if (sourceCycleError) {
    return sourceCycleError;
  }
  if (products && effectiveDate) {
    const expected = getEarliestChangeBillingThresholdDate(
      products,
      contractStartDate
    );
    if (expected && effectiveDate !== expected) {
      return `切替日は課金内容が変更された最も古い日付（${expected}）と一致している必要があります。`;
    }
  }
  return null;
}

/**
 * 仕様: Core 第4.4節、日付仕様 第2.3節。
 * 継続課金の課金イベント日は元明細開始日起点のサイクル境界に置く。ヘッダー開始日は使わない。
 */
export function validateChangeBillingEventsOnSourceCycle(products) {
  if (!requiresChangeEffectiveDateOnBillingPeriodStart(products)) {
    return null;
  }
  for (const entry of collectChangeBillingEventEntries(products)) {
    if (!entry || entry.isOneTimeOnly === true) {
      continue;
    }
    if (!entry.date || !entry.sourceStartDate) {
      continue;
    }
    if (!isMonthlyPeriodStartDate(entry.sourceStartDate, entry.date)) {
      return CHANGE_EFFECTIVE_DATE_BILLING_PERIOD_START_MESSAGE;
    }
  }
  return null;
}

export function validateChangePeriodDates(
  contractStartDate,
  contractEndDate,
  previousTermStartDate,
  previousTermEndDate
) {
  if (
    previousTermStartDate &&
    contractStartDate &&
    contractStartDate !== previousTermStartDate
  ) {
    return "期間開始日は前回の版の期間開始日と一致している必要があります。";
  }
  if (
    previousTermEndDate &&
    contractEndDate &&
    contractEndDate < previousTermEndDate
  ) {
    return "期間終了日は前回の版の期間終了日以降の日付を入力してください。";
  }
  if (contractStartDate && contractEndDate) {
    const headerPeriodError = validateNewHeaderMonthlyPeriod(
      contractStartDate,
      contractEndDate
    );
    if (headerPeriodError) {
      return headerPeriodError;
    }
  }
  return null;
}

export function validateChangeProductPeriodOverlap(products) {
  const activeLines = (products || []).filter(
    (line) => isActiveLine(line) && !isChangeOriginalLine(line)
  );

  for (let i = 0; i < activeLines.length; i++) {
    const left = activeLines[i];
    if (!left.startDate || !left.endDate) {
      continue;
    }
    for (let j = i + 1; j < activeLines.length; j++) {
      const right = activeLines[j];
      if (left.productId !== right.productId) {
        continue;
      }
      if (!right.startDate || !right.endDate) {
        continue;
      }
      if (left.startDate <= right.endDate && left.endDate >= right.startDate) {
        // 仕様: Core 第4.5.1節。一回×一回は許可。継続どうしと継続×一回だけ不可。
        if (isRecurringLine(left) || isRecurringLine(right)) {
          return "同一商品の契約期間が重複しています。商品ごとに期間が重ならないよう入力してください。";
        }
      }
    }
  }
  return null;
}

function validateChangeEditableLine(row, headerStart, headerEnd) {
  if (isBlankProductLine(row)) {
    return null;
  }

  // 仕様: Core 第4.3.9節
  const quantityError = validateQuantityMin(row);
  if (quantityError) {
    return quantityError;
  }

  if (
    !isChangeOriginalLine(row) &&
    (row.unitPrice === null || row.unitPrice === undefined)
  ) {
    return "単価を入力してください。";
  }

  if (!row.startDate || !row.endDate) {
    return "開始日と終了日を入力してください。";
  }

  const orderError = validateLineDateOrder(row);
  if (orderError) {
    return orderError;
  }

  const rangeError = validateLineWithinHeader(row, headerStart, headerEnd);
  if (rangeError) {
    return rangeError;
  }

  const billingTypeError = validateBillingTypeRequired(row);
  if (billingTypeError) {
    return billingTypeError;
  }

  if (!row.invoiceType) {
    return "請求設定を選択してください。";
  }

  const invoiceSettingError = validateInvoiceSettingForBillingType(
    row.billingType,
    row.invoiceType
  );
  if (invoiceSettingError) {
    return invoiceSettingError;
  }

  // 仕様: Core 第1.1.10節、第4.5.2節。保存時の必須はAccounting ON/OFFで変えない。
  const revenueError = validateRevenueRecognitionBasisRequired(row);
  if (revenueError) {
    return revenueError;
  }

  return validateBillingPeriod(row);
}

function validateOriginalMatchesSource(line, source, label) {
  const message = `商品明細（${label}）: 変更前の行は前回の版の見積商品と一致している必要があります。`;
  if (!source) {
    return message;
  }
  if (line.productId !== source.productId) {
    return message;
  }
  if (!decimalsEqual(line.quantity, source.quantity)) {
    return message;
  }
  if (!decimalsEqual(line.unitPrice, source.unitPrice)) {
    return message;
  }
  // 仕様: Core 第4.4.1節、第4.5.2節。Original の課金形態の正は前回見積商品。
  if ((line.billingType || "") !== (source.billingType || "")) {
    return message;
  }
  const lineInvoice = normalizeInvoiceSettingLabel(line.invoiceType) || "";
  const sourceInvoice = normalizeInvoiceSettingLabel(source.invoiceType) || "";
  if (lineInvoice !== sourceInvoice) {
    return message;
  }
  if ((line.startDate || "") !== (source.startDate || "")) {
    return message;
  }
  if ((line.endDate || "") !== (source.endDate || "")) {
    return message;
  }
  // 仕様: Core 第4.4節、第4.4.3節。Original と元明細は売上計上基準も一致必須。
  const lineRevenue = line.revenueRecognitionBasis || "";
  const sourceRevenue = source.revenueRecognitionBasis || "";
  if (lineRevenue !== sourceRevenue) {
    return message;
  }
  // 仕様: Core 第4.4節、第4.5.2節。Original 税抜は -(前回 Amount)。
  const expectedOriginalAmount =
    source.amount == null || source.amount === undefined
      ? null
      : -Number(source.amount);
  if (!decimalsEqual(line.amount, expectedOriginalAmount)) {
    return message;
  }
  return null;
}

function buildSourceProductMap(sourceProducts) {
  const sourceById = new Map();
  (sourceProducts || []).forEach((source) => {
    const sourceId = source && (source.contractProductId || source.id);
    if (!sourceId) {
      return;
    }
    sourceById.set(sourceId, {
      contractProductId: sourceId,
      productId: source.productId,
      quantity: source.quantity,
      unitPrice: source.unitPrice,
      amount: source.amount,
      startDate: source.startDate || "",
      endDate: source.endDate || "",
      invoiceType: source.invoiceType || "",
      billingType: source.billingType || "",
      revenueRecognitionBasis: source.revenueRecognitionBasis || ""
    });
  });
  return sourceById;
}

// 仕様: Core 第4.3.5節、第4.3.9節
export function validateChangeProducts(
  products,
  contractStartDate,
  contractEndDate,
  _effectiveDate,
  sourceProducts,
  previousTermStartDate,
  previousTermEndDate
) {
  const lines = products || [];
  const originalBySourceId = new Map();
  const remakesBySourceId = new Map();
  const overlapCandidates = [];
  const sourceById = buildSourceProductMap(sourceProducts);
  const hasSourceCatalog = sourceById.size > 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const label = productTypeDisplayLabel(line.recordType, line.typeLabel);

    if (!isBlankProductLine(line)) {
      const quantityError = validateQuantityMin(line);
      if (quantityError) {
        return `商品明細（${label}）: ${quantityError}`;
      }
    }

    if (isChangeOriginalLine(line)) {
      if (!line.sourceContractProductId) {
        return `商品明細（${label}）: 変更前の行に元の見積商品が指定されていません。`;
      }
      if (originalBySourceId.has(line.sourceContractProductId)) {
        return "変更前の行が重複しています。";
      }
      if (hasSourceCatalog) {
        const source = sourceById.get(line.sourceContractProductId);
        if (!source) {
          return "変更前の行は前回の版の見積商品と一致している必要があります。";
        }
        const matchError = validateOriginalMatchesSource(line, source, label);
        if (matchError) {
          return matchError;
        }
      }
      originalBySourceId.set(line.sourceContractProductId, line);
      continue;
    }

    if (isChangeRemakeLine(line)) {
      if (!line.sourceContractProductId) {
        return `商品明細（${label}）: 変更後の行に元の見積商品が指定されていません。`;
      }
      if (hasSourceCatalog) {
        const remakeSource = sourceById.get(line.sourceContractProductId);
        if (!remakeSource) {
          return `商品明細（${label}）: 変更後の行の元見積商品が見つかりません。`;
        }
        if (line.productId && line.productId !== remakeSource.productId) {
          return `商品明細（${label}）: 変更後の行の商品は変更前（前回の版）と同じ商品にしてください。`;
        }
        // 仕様: Core 第4.4.1節、第4.5.2節。Remake の課金形態の正は前回見積商品。
        if ((line.billingType || "") !== (remakeSource.billingType || "")) {
          return `商品明細（${label}）: 変更後の行の課金形態は前回の版と同じにしてください。`;
        }
        // 仕様: Core 第4.5.2節、第4.4.3節
        const lineInvoice =
          normalizeInvoiceSettingLabel(line.invoiceType) || "";
        const sourceInvoice =
          normalizeInvoiceSettingLabel(remakeSource.invoiceType) || "";
        if (lineInvoice !== sourceInvoice) {
          return `商品明細（${label}）: 変更後の行の請求設定は前回の版と同じにしてください。`;
        }
        const lineRevenue = line.revenueRecognitionBasis || "";
        const sourceRevenue = remakeSource.revenueRecognitionBasis || "";
        if (lineRevenue !== sourceRevenue) {
          return `商品明細（${label}）: 変更後の行の売上計上基準は前回の版と同じにしてください。`;
        }
      }
      if (!remakesBySourceId.has(line.sourceContractProductId)) {
        remakesBySourceId.set(line.sourceContractProductId, []);
      }
      remakesBySourceId.get(line.sourceContractProductId).push(line);
      if (line.productId) {
        const lineError = validateChangeEditableLine(
          line,
          contractStartDate,
          contractEndDate
        );
        if (lineError) {
          return `商品明細（${label}）: ${lineError}`;
        }
      }
      if (isActiveLine(line)) {
        overlapCandidates.push(line);
      }
      continue;
    }

    if (isChangeContinuationLine(line)) {
      if (isActiveLine(line)) {
        const lineError = validateChangeEditableLine(
          line,
          contractStartDate,
          contractEndDate
        );
        if (lineError) {
          return `商品明細（${label}）: ${lineError}`;
        }
        overlapCandidates.push(line);
      }
      continue;
    }

    if (isActiveLine(line)) {
      const lineError = validateChangeEditableLine(
        line,
        contractStartDate,
        contractEndDate
      );
      if (lineError) {
        return `商品明細（${label}）: ${lineError}`;
      }
      overlapCandidates.push(line);
    }
  }

  if (hasSourceCatalog) {
    for (const sourceId of sourceById.keys()) {
      if (!originalBySourceId.has(sourceId)) {
        return "前回の版の継続課金商品すべてに変更前の行が必要です。";
      }
      const derivatives = remakesBySourceId.get(sourceId) || [];
      if (!derivatives.length) {
        return "前回の版の継続課金商品すべてに変更後の行を1件以上入力してください。";
      }
      const reconError = validateChangeReconstitutionCoverage(
        originalBySourceId.get(sourceId),
        derivatives
      );
      if (reconError) {
        return reconError;
      }
      const midTermError = validateChangeMidTermRemakeSplit(
        originalBySourceId.get(sourceId),
        derivatives
      );
      if (midTermError) {
        return midTermError;
      }
    }
  } else {
    if (!originalBySourceId.size) {
      return "商品明細を1行以上入力してください。";
    }
    for (const [sourceId, original] of originalBySourceId.entries()) {
      const derivatives = remakesBySourceId.get(sourceId) || [];
      if (!derivatives.length) {
        return "前回の版の継続課金商品すべてに変更後の行を1件以上入力してください。";
      }
      const reconError = validateChangeReconstitutionCoverage(
        original,
        derivatives
      );
      if (reconError) {
        return reconError;
      }
      const midTermError = validateChangeMidTermRemakeSplit(
        original,
        derivatives
      );
      if (midTermError) {
        return midTermError;
      }
    }
  }

  const customOnlyError = validateChangeIsNotCustomFieldOnly(
    lines,
    sourceProducts
  );
  if (customOnlyError) {
    return customOnlyError;
  }

  const renewForceError = validateChangeHasBillingEventInPreviousTerm(
    lines,
    previousTermStartDate,
    previousTermEndDate
  );
  if (renewForceError) {
    return renewForceError;
  }

  const overlapError = validateChangeProductPeriodOverlap(overlapCandidates);
  if (overlapError) {
    return overlapError;
  }

  const endpointError = validateChangeRecurringEndEndpointCoverage(
    lines,
    contractEndDate
  );
  if (endpointError) {
    return endpointError;
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (isBlankProductLine(line)) {
      continue;
    }
    const label = productTypeDisplayLabel(line.recordType, line.typeLabel);
    if (line.amount == null && line.productId) {
      const qty = Number(line.quantity);
      if (Number.isNaN(qty) || qty !== 0) {
        return `商品明細（${label}）: 金額を計算できません。期間を確認してください。`;
      }
    }
  }

  return null;
}

/** 仕様: Core 第0.1節、第4.5節 */
export function validateRenewProducts(
  products,
  periodStart,
  periodEnd,
  previousTermEnd
) {
  const activeLines = (products || []).filter(isActiveLine);

  if (!activeLines.length) {
    return "商品明細を1行以上入力してください。";
  }

  const hasRecurring = activeLines.some((line) => isRecurringLine(line));
  if (!hasRecurring) {
    return "更新では継続課金商品を1行以上指定してください。一回課金のみの更新はできません。";
  }

  if (previousTermEnd && periodStart) {
    const expectedStart = addDaysToIsoDate(previousTermEnd, 1);
    if (periodStart !== expectedStart) {
      return "期間開始日は前回の版の期間終了日の翌日である必要があります。";
    }
  }

  return validateNewProducts(products, periodStart, periodEnd, true);
}

// 仕様: Core 第4.3.5節、第4.3.9節
export function validateNewLineItem(row, headerStart, headerEnd) {
  if (isBlankProductLine(row)) {
    return null;
  }

  if (!row.startDate || !row.endDate) {
    return "開始日と終了日を入力してください。";
  }

  // 仕様: Core 第4.3.9節
  const quantityError = validateQuantityMin(row);
  if (quantityError) {
    return quantityError;
  }

  if (row.unitPrice === null || row.unitPrice === undefined) {
    return "単価を入力してください。";
  }

  const orderError = validateLineDateOrder(row);

  if (orderError) {
    return orderError;
  }

  const rangeError = validateLineWithinHeader(row, headerStart, headerEnd);

  if (rangeError) {
    return rangeError;
  }

  const billingTypeError = validateBillingTypeRequired(row);
  if (billingTypeError) {
    return billingTypeError;
  }

  if (isActiveLine(row) && !row.invoiceType) {
    return "請求設定を選択してください。";
  }

  const invoiceSettingError = validateInvoiceSettingForBillingType(
    row.billingType,
    row.invoiceType
  );
  if (invoiceSettingError) {
    return invoiceSettingError;
  }

  // 仕様: Core 第1.1.10節、第4.3.8節、第4.5.2節。ON列編集・OFFマスタ初期値のどちらの空も画面で止める。
  const revenueError = validateRevenueRecognitionBasisRequired(row);
  if (revenueError) {
    return revenueError;
  }

  return validateBillingPeriod(row);
}

/** 仕様: Core 第1.1.10節、第4.5.2節。保存時の必須はAccounting ON/OFFで変えない。 */
export function validateRevenueRecognitionBasisRequired(row) {
  if (!isActiveLine(row)) {
    return null;
  }
  const value = row.revenueRecognitionBasis;
  if (value == null || String(value).trim() === "") {
    return REVENUE_BASIS_BLANK_MESSAGE;
  }
  if (
    value !== REVENUE_BASIS_OVER_TIME &&
    value !== REVENUE_BASIS_POINT_IN_TIME
  ) {
    return REVENUE_BASIS_INVALID_MESSAGE;
  }
  return null;
}

export const SPOT_CHANGE_ONE_TIME_ONLY_MESSAGE =
  "都度契約の Change は一回課金だけです。";
export const SPOT_CHANGE_NO_PREVIOUS_PRODUCT_MESSAGE =
  "都度契約の Change は過去の見積商品を引き継ぎません。";

/**
 * 仕様: Core 第5.1節、第3.4.2節、第1.1.10節、第1.1.8節。
 * Spot Change は一回課金 Type=New のみ。継続・Original・Remake・過去明細継承は画面で止める。
 * 共通明細規則は validateNewProducts。
 */
export function validateSpotChangeProducts(products) {
  for (const line of products || []) {
    if (!line || !line.productId) {
      continue;
    }
    if (isChangeOriginalLine(line) || isChangeRemakeLine(line)) {
      return SPOT_CHANGE_ONE_TIME_ONLY_MESSAGE;
    }
    if (line.billingType === BILLING_TYPE_RECURRING) {
      return SPOT_CHANGE_ONE_TIME_ONLY_MESSAGE;
    }
    if (line.sourceContractProductId) {
      return SPOT_CHANGE_NO_PREVIOUS_PRODUCT_MESSAGE;
    }
    const recordType = normalizeProductRecordType(line.recordType);
    if (recordType && recordType !== PRODUCT_TYPE_NEW) {
      return SPOT_CHANGE_ONE_TIME_ONLY_MESSAGE;
    }
  }
  return validateNewProducts(products, "", "");
}

// 仕様: Core 第4.3.9節
export function validateNewProducts(
  products,
  headerStart,
  headerEnd,
  includeProductOverlap = true
) {
  for (let i = 0; i < (products || []).length; i++) {
    const line = products[i];
    if (isBlankProductLine(line)) {
      continue;
    }
    const quantityError = validateQuantityMin(line);
    if (quantityError) {
      const label = productTypeDisplayLabel(line.recordType, line.typeLabel);
      return `商品明細（${label}）: ${quantityError}`;
    }
  }

  const activeLines = (products || []).filter(isActiveLine);

  if (!activeLines.length) {
    return "商品明細を1行以上入力してください。";
  }

  const hasRecurring = activeLines.some((line) => isRecurringLine(line));

  if (hasRecurring) {
    const headerPeriodError = validateNewHeaderMonthlyPeriod(
      headerStart,

      headerEnd
    );

    if (headerPeriodError) {
      return headerPeriodError;
    }

    const endpointError = validateNewRecurringEndpointCoverage(
      products,

      headerStart,

      headerEnd
    );

    if (endpointError) {
      return endpointError;
    }
  }

  if (includeProductOverlap) {
    const overlapError = validateNewProductPeriodOverlap(products);

    if (overlapError) {
      return overlapError;
    }
  }

  for (let i = 0; i < products.length; i++) {
    const line = products[i];

    if (isBlankProductLine(line)) {
      continue;
    }

    const label = productTypeDisplayLabel(line.recordType, line.typeLabel);

    const lineError = validateNewLineItem(line, headerStart, headerEnd);

    if (lineError) {
      return `商品明細（${label}）: ${lineError}`;
    }

    if (line.amount == null && line.productId) {
      const qty = Number(line.quantity);

      if (Number.isNaN(qty) || qty !== 0) {
        return `商品明細（${label}）: 金額を計算できません。期間を確認してください。`;
      }
    }
  }

  return null;
}

export function endOfMonthlyPeriodIsoDate(isoDate) {
  const date = parseLocalDate(isoDate);
  if (!date) {
    return null;
  }
  const periodEnd = addMonthsToDate(date, 1);
  periodEnd.setDate(periodEnd.getDate() - 1);
  return formatLocalDate(periodEnd);
}

export function isMonthlyPeriodStartDate(anchorStartIsoDate, candidateIsoDate) {
  if (!anchorStartIsoDate || !candidateIsoDate) {
    return false;
  }
  if (candidateIsoDate < anchorStartIsoDate) {
    return false;
  }

  let periodStart = anchorStartIsoDate;
  while (periodStart <= candidateIsoDate) {
    if (periodStart === candidateIsoDate) {
      return true;
    }
    periodStart = addDaysToIsoDate(endOfMonthlyPeriodIsoDate(periodStart), 1);
  }
  return false;
}

/**
 * ウィザード表示用の請求基準日（保存時 Apex InvoiceAnchorDateUtil と同定義）。
 * Change の据え置き Original/Remake（課金イベントなし）は表示しない。
 * options.products を渡したときだけ据え置き判定する。
 */
export function resolveInvoiceAnchorFields(
  row,
  historyType,
  effectiveDateIso,
  options = {}
) {
  const hidden = {
    anchorDate: "",
    billingCycleCount: null,
    displayValue: "",
    showInvoiceAnchor: false
  };
  const invoiceType = normalizeInvoiceSettingLabel(
    row && row.invoiceType ? row.invoiceType : ""
  );
  const startDate = row && row.startDate ? row.startDate : "";
  const endDate = row && row.endDate ? row.endDate : "";

  if (!invoiceType || !startDate) {
    return hidden;
  }

  if (
    historyType === "Change" &&
    isUnchangedChangeLineageRow(row, options.products)
  ) {
    return hidden;
  }

  if (invoiceType === INVOICE_SETTING_POSTPAID_NEXT_DAY) {
    if (!endDate) {
      return hidden;
    }
    const anchorDate = addDaysToIsoDate(endDate, 1);
    return {
      anchorDate,
      billingCycleCount: null,
      displayValue: anchorDate,
      showInvoiceAnchor: true
    };
  }

  if (invoiceType === INVOICE_SETTING_SPLIT_MONTHLY) {
    if (!endDate) {
      return hidden;
    }
    const cycles = countBillingCycles(startDate, endDate);
    if (cycles == null || cycles < 1) {
      return hidden;
    }
    return {
      anchorDate: startDate,
      billingCycleCount: cycles,
      displayValue: `${startDate}〜${endDate}（${cycles}回）`,
      showInvoiceAnchor: true
    };
  }

  let anchorDate = startDate;
  const productType = normalizeProductRecordType(
    row && row.recordType ? row.recordType : row && row.typeLabel
  );
  if (
    historyType === "Change" &&
    invoiceType === INVOICE_SETTING_PREPAID_START &&
    productType !== PRODUCT_TYPE_NEW &&
    effectiveDateIso
  ) {
    anchorDate = effectiveDateIso;
  }

  return {
    anchorDate,
    billingCycleCount: null,
    displayValue: anchorDate,
    showInvoiceAnchor: true
  };
}

export const INVOICE_ANCHOR_DISPLAY_TITLE =
  "請求書の請求日ではありません。受注後、請求先の請求日ルールで請求日が決まります。";
