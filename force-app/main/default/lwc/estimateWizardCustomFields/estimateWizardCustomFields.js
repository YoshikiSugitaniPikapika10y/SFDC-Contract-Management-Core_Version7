import { isValidIsoDate } from "c/estimateLineItemUtils";

export function hasCustomFieldValues(customFields = {}) {
  return Object.keys(customFields).some((key) => {
    const value = customFields[key];
    return value !== null && value !== undefined && value !== "";
  });
}

export function isMissingRequiredCustomValue(value) {
  if (value === null || value === undefined) {
    return true;
  }
  if (typeof value === "boolean") {
    return false;
  }
  return String(value).trim() === "";
}

function isBlankCustomValue(value) {
  return isMissingRequiredCustomValue(value);
}

function isIntegerCustomValue(value) {
  if (typeof value === "number") {
    return Number.isInteger(value);
  }
  const text = String(value).trim();
  return /^-?\d+$/.test(text);
}

function isDecimalCustomValue(value) {
  if (typeof value === "number") {
    return Number.isFinite(value);
  }
  const text = String(value).trim();
  if (!/^-?\d+(\.\d+)?$/.test(text)) {
    return false;
  }
  return Number.isFinite(Number(text));
}

/**
 * Returns a short type-error message for a non-blank value, or null if OK.
 */
export function getCustomFieldTypeError(fieldType, value) {
  if (isBlankCustomValue(value)) {
    return null;
  }

  const type = fieldType || "";

  if (type === "DATE") {
    const text = String(value).trim();
    if (!isValidIsoDate(text)) {
      return "YYYY-MM-DD 形式で入力してください";
    }
    return null;
  }

  if (type === "INTEGER" || type === "LONG") {
    if (!isIntegerCustomValue(value)) {
      return "整数で入力してください";
    }
    return null;
  }

  if (type === "DOUBLE" || type === "CURRENCY" || type === "PERCENT") {
    if (!isDecimalCustomValue(value)) {
      return "数値で入力してください";
    }
    return null;
  }

  if (type === "BOOLEAN") {
    if (typeof value === "boolean") {
      return null;
    }
    const text = String(value).trim().toLowerCase();
    if (text === "true" || text === "false" || text === "1" || text === "0") {
      return null;
    }
    return "真偽値で入力してください";
  }

  if (type === "REFERENCE") {
    const text = String(value).trim();
    if (!/^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(text)) {
      return "有効なレコードを選択してください";
    }
  }

  return null;
}

function splitCommaValues(raw) {
  if (raw === null || raw === undefined || raw === "") {
    return [];
  }
  return String(raw)
    .split(",")
    .map((part) => part.trim())
    .filter((part) => part !== "");
}

function splitActualTokens(actual) {
  if (actual === null || actual === undefined || actual === "") {
    return [];
  }
  return String(actual)
    .split(";")
    .map((part) => part.trim())
    .filter((part) => part !== "");
}

/**
 * ContractProduct visibility against Product2 context.
 * No visibilityFieldApiName => always visible.
 */
export function isCustomFieldVisible(definition, productVisibilityContext) {
  if (!definition) {
    return false;
  }
  const fieldApi = (definition.visibilityFieldApiName || "").trim();
  if (!fieldApi) {
    return true;
  }
  if (!productVisibilityContext) {
    return false;
  }

  const actual = Object.prototype.hasOwnProperty.call(
    productVisibilityContext,
    fieldApi
  )
    ? productVisibilityContext[fieldApi]
    : null;
  const operator = (definition.visibilityOperator || "IN").trim().toUpperCase();
  const expected = splitCommaValues(definition.visibilityValues);
  const blank =
    actual === null || actual === undefined || String(actual).trim() === "";

  if (operator === "IS_BLANK") {
    return blank;
  }
  if (operator === "IS_NOT_BLANK") {
    return !blank;
  }

  const actualTokens = splitActualTokens(actual);
  const expectedSet = new Set(expected);

  if (operator === "IN" || operator === "EQUALS") {
    if (actualTokens.length === 0 || expectedSet.size === 0) {
      return false;
    }
    return actualTokens.some((token) => expectedSet.has(token));
  }

  if (operator === "NOT_IN" || operator === "NOT_EQUALS") {
    if (expectedSet.size === 0) {
      return true;
    }
    if (actualTokens.length === 0) {
      return true;
    }
    return !actualTokens.some((token) => expectedSet.has(token));
  }

  return false;
}

/**
 * Wizard Type (New/Change/Renew/Cancel) display flags.
 * Flags must be explicitly true to show; missing/false hides the field.
 */
export function isCustomFieldVisibleForWizardType(definition, wizardType) {
  if (!definition) {
    return false;
  }
  const type = (wizardType || "").trim();
  if (!type) {
    return true;
  }
  if (type === "New") {
    return definition.showOnNew === true;
  }
  if (type === "Change") {
    return definition.showOnChange === true;
  }
  if (type === "Renew") {
    return definition.showOnRenew === true;
  }
  if (type === "Cancel") {
    return definition.showOnCancel === true;
  }
  return true;
}

/**
 * Type-only filter (ignores Product2 visibility).
 * Use for global toggles / counts before a product context exists.
 */
export function filterCustomFieldDefinitionsForWizardType(
  definitions,
  wizardType
) {
  if (!definitions || definitions.length === 0) {
    return [];
  }
  return definitions.filter((field) =>
    isCustomFieldVisibleForWizardType(field, wizardType)
  );
}

export function filterVisibleCustomFieldDefinitions(
  definitions,
  productVisibilityContext,
  wizardType
) {
  if (!definitions || definitions.length === 0) {
    return [];
  }
  return definitions.filter(
    (field) =>
      isCustomFieldVisibleForWizardType(field, wizardType) &&
      isCustomFieldVisible(field, productVisibilityContext)
  );
}

export function pruneInvisibleCustomFields(
  customFields,
  definitions,
  productVisibilityContext,
  wizardType
) {
  const visibleApis = new Set(
    filterVisibleCustomFieldDefinitions(
      definitions,
      productVisibilityContext,
      wizardType
    ).map((field) => field.apiName)
  );
  const next = {};
  const source = customFields || {};
  Object.keys(source).forEach((apiName) => {
    if (visibleApis.has(apiName)) {
      next[apiName] = source[apiName];
    }
  });
  return next;
}

/**
 * Coerce CMDT DefaultValue__c into a wizard custom-field value.
 * Returns undefined when blank / unusable.
 */
export function coerceCustomFieldDefault(fieldType, rawDefault) {
  if (rawDefault === null || rawDefault === undefined) {
    return undefined;
  }
  const trimmed = String(rawDefault).trim();
  if (trimmed === "") {
    return undefined;
  }

  const type = fieldType || "";
  if (type === "BOOLEAN") {
    const lower = trimmed.toLowerCase();
    if (lower === "true" || lower === "1") {
      return true;
    }
    if (lower === "false" || lower === "0") {
      return false;
    }
    return undefined;
  }

  return trimmed;
}

/**
 * Resolve literal or dynamic default for one field definition.
 * defaultSource blank => defaultValue is literal (static).
 * Opportunity => look up defaultValue field API in opportunityDefaultContext.
 * Account => look up Account.<field> in opportunityDefaultContext.
 * Product2 => look up defaultValue field API in productVisibilityContext.
 */
export function resolveCustomFieldDefault(
  field,
  productVisibilityContext,
  opportunityDefaultContext
) {
  if (!field) {
    return undefined;
  }
  const source = (field.defaultSource || "").trim();
  if (!source) {
    return coerceCustomFieldDefault(field.fieldType, field.defaultValue);
  }

  if (source === "Today") {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, "0");
    const day = String(now.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }

  const path = (field.defaultValue || "").trim();
  if (!path) {
    return undefined;
  }

  if (source === "Opportunity") {
    if (!opportunityDefaultContext) {
      return undefined;
    }
    if (
      !Object.prototype.hasOwnProperty.call(opportunityDefaultContext, path)
    ) {
      return undefined;
    }
    return coerceCustomFieldDefault(
      field.fieldType,
      opportunityDefaultContext[path]
    );
  }

  if (source === "Account") {
    if (!opportunityDefaultContext) {
      return undefined;
    }
    const contextKey = path.startsWith("Account.") ? path : `Account.${path}`;
    if (
      !Object.prototype.hasOwnProperty.call(
        opportunityDefaultContext,
        contextKey
      )
    ) {
      return undefined;
    }
    return coerceCustomFieldDefault(
      field.fieldType,
      opportunityDefaultContext[contextKey]
    );
  }

  if (source === "Product2") {
    if (!productVisibilityContext) {
      return undefined;
    }
    if (!Object.prototype.hasOwnProperty.call(productVisibilityContext, path)) {
      return undefined;
    }
    return coerceCustomFieldDefault(
      field.fieldType,
      productVisibilityContext[path]
    );
  }

  return undefined;
}

/**
 * Fill missing keys (not present on the map) with resolved defaults.
 * Does not overwrite keys the user cleared to ''.
 * Re-show after prune removes the key, so defaults apply again.
 */
export function applyDefaultCustomFields(
  customFields,
  definitions,
  productVisibilityContext,
  wizardType,
  opportunityDefaultContext
) {
  const visibleDefinitions = filterVisibleCustomFieldDefinitions(
    definitions,
    productVisibilityContext,
    wizardType
  );
  const next = { ...(customFields || {}) };
  if (!visibleDefinitions.length) {
    return next;
  }

  visibleDefinitions.forEach((field) => {
    if (!field || !field.apiName) {
      return;
    }
    if (Object.prototype.hasOwnProperty.call(next, field.apiName)) {
      return;
    }
    const coerced = resolveCustomFieldDefault(
      field,
      productVisibilityContext,
      opportunityDefaultContext
    );
    if (coerced !== undefined) {
      next[field.apiName] = coerced;
    }
  });
  return next;
}

/**
 * Drop invisible values, then apply defaults for newly visible missing keys.
 */
export function syncCustomFieldsForVisibility(
  customFields,
  definitions,
  productVisibilityContext,
  wizardType,
  opportunityDefaultContext
) {
  return applyDefaultCustomFields(
    pruneInvisibleCustomFields(
      customFields,
      definitions,
      productVisibilityContext,
      wizardType
    ),
    definitions,
    productVisibilityContext,
    wizardType,
    opportunityDefaultContext
  );
}

/**
 * Validates required + type for a custom-field value map.
 * @returns {string|null} error message or null
 */
export function validateCustomFieldMaps(
  definitions,
  values,
  scopeLabel,
  productVisibilityContext,
  wizardType
) {
  const visibleDefinitions = filterVisibleCustomFieldDefinitions(
    definitions,
    productVisibilityContext,
    wizardType
  );
  if (!visibleDefinitions || visibleDefinitions.length === 0) {
    return null;
  }
  const map = values || {};
  const missing = [];
  const typeErrors = [];

  for (const field of visibleDefinitions) {
    const label = field.label || field.apiName;
    const raw = map[field.apiName];

    if (field.required === true && isMissingRequiredCustomValue(raw)) {
      missing.push(label);
      continue;
    }

    const typeError = getCustomFieldTypeError(field.fieldType, raw);
    if (typeError) {
      typeErrors.push(`${label}（${typeError}）`);
    }
  }

  if (missing.length > 0) {
    return `${scopeLabel}の必須カスタム項目を入力してください: ${missing.join("、")}`;
  }
  if (typeErrors.length > 0) {
    return `${scopeLabel}のカスタム項目の形式が不正です: ${typeErrors.join("、")}`;
  }
  return null;
}

/** カスタム項目マップの浅い等価比較（値はプリミティブ想定）。 */
export function shallowEqualFieldMaps(a, b) {
  const left = a || {};
  const right = b || {};
  const leftKeys = Object.keys(left);
  if (leftKeys.length !== Object.keys(right).length) {
    return false;
  }
  return leftKeys.every((key) => left[key] === right[key]);
}

/** 仕様: Core 第0.1節、第5.2節、第7.2節、第7.5節 */
export function buildCustomFieldInputs(
  definitions,
  customFields = {},
  keyPrefix,
  isReadonly = false,
  productVisibilityContext,
  wizardType
) {
  const visibleDefinitions = filterVisibleCustomFieldDefinitions(
    definitions,
    productVisibilityContext,
    wizardType
  );
  if (!visibleDefinitions.length) {
    return [];
  }

  return visibleDefinitions.map((field) => {
    const rawValue = customFields[field.apiName];
    const isPicklist = field.fieldType === "PICKLIST";
    const value =
      rawValue === null || rawValue === undefined
        ? ""
        : isPicklist
          ? String(rawValue)
          : rawValue;
    const isCheckbox = field.fieldType === "BOOLEAN";
    const isNumber = [
      "DOUBLE",
      "CURRENCY",
      "PERCENT",
      "INTEGER",
      "LONG"
    ].includes(field.fieldType);
    const isDate = field.fieldType === "DATE";
    const isReference = field.fieldType === "REFERENCE";
    const isTextarea =
      field.fieldType === "TEXTAREA" || field.fieldType === "LONGTEXTAREA";
    const picklistOptions = (field.picklistOptions || []).map((option) => ({
      label: option.label,
      value: option.value,
      key: `${keyPrefix}-${field.apiName}-${option.value}`,
      selected: option.value === value
    }));
    const picklistLabel = isPicklist
      ? picklistOptions.find((option) => option.value === value)?.label
      : null;

    return {
      apiName: field.apiName,
      label: field.label,
      required: field.required === true,
      fieldType: field.fieldType,
      helpText: field.helpText || "",
      hasHelpText: !!(field.helpText && String(field.helpText).trim()),
      key: `${keyPrefix}-${field.apiName}`,
      value,
      displayValue: isCheckbox
        ? value === true || value === "true"
          ? "する"
          : "しない"
        : String(
            (isPicklist && picklistLabel != null && picklistLabel !== ""
              ? picklistLabel
              : value) || ""
          ),
      isCheckbox,
      isPicklist,
      isNumber,
      isDate,
      isReference,
      referenceObjectApiName: field.referenceObjectApiName || "",
      isTextarea,
      isText:
        !isCheckbox &&
        !isPicklist &&
        !isNumber &&
        !isDate &&
        !isReference &&
        !isTextarea,
      isReadonly,
      checked: value === true || value === "true",
      picklistOptions
    };
  });
}
