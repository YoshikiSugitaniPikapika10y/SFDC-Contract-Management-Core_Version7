export const VALIDATION_SOURCE = {
  WIZARD: "wizard",
  VALIDATION_RULE: "validation_rule",
  SAVE: "save",
  CONFIRM: "confirm"
};

export const VALIDATION_ALERT_TITLES = {
  /* 入力チェックは本文だけで足りる（見出しは出さない） */
  [VALIDATION_SOURCE.WIZARD]: "",
  [VALIDATION_SOURCE.VALIDATION_RULE]: "",
  [VALIDATION_SOURCE.SAVE]: "",
  [VALIDATION_SOURCE.CONFIRM]: "確認"
};

export const VALIDATION_ALERT_VARIANT = {
  ERROR: "error",
  CONFIRM: "confirm"
};

const VALIDATION_RULE_PATTERNS = [
  /FIELD_CUSTOM_VALIDATION_EXCEPTION/i,
  /入力規則/u,
  /Validation Formula/i,
  /validation rule/i,
  /エラートリガー/u,
  /レコードを保存できません/u
];

export function buildWizardValidationAlert(message) {
  return buildValidationAlert(message, VALIDATION_SOURCE.WIZARD);
}

export function buildConfirmValidationAlert(message) {
  const alert = buildValidationAlert(message, VALIDATION_SOURCE.CONFIRM);
  alert.variant = VALIDATION_ALERT_VARIANT.CONFIRM;
  alert.showActions = true;
  return alert;
}

export function buildValidationAlert(
  message,
  source = VALIDATION_SOURCE.WIZARD
) {
  const messages = normalizeMessages(message);
  return toAlertViewModel(source, messages);
}

export function resolveSaveErrorAlert(error) {
  const messages = extractErrorMessages(error).map(cleanErrorMessage);
  const combined = messages.join("\n");
  const source = isValidationRuleMessage(combined)
    ? VALIDATION_SOURCE.VALIDATION_RULE
    : VALIDATION_SOURCE.WIZARD;
  return toAlertViewModel(source, messages);
}

export function isValidationRuleMessage(text) {
  if (!text) {
    return false;
  }
  return VALIDATION_RULE_PATTERNS.some((pattern) => pattern.test(text));
}

function toAlertViewModel(source, messages) {
  const safeMessages =
    messages && messages.length ? messages : ["入力内容を確認してください。"];
  return {
    source,
    variant: VALIDATION_ALERT_VARIANT.ERROR,
    showActions: false,
    title: VALIDATION_ALERT_TITLES[source] || VALIDATION_ALERT_TITLES.save,
    messages: safeMessages.map((text, index) => ({
      key: `validation-msg-${index}`,
      text
    }))
  };
}

function normalizeMessages(message) {
  if (Array.isArray(message)) {
    return message.map((item) => String(item).trim()).filter(Boolean);
  }
  if (message == null || message === "") {
    return [];
  }
  return String(message)
    .split(/\r?\n/u)
    .map((item) => item.trim())
    .filter(Boolean);
}

function extractErrorMessages(error) {
  const messages = [];

  if (!error) {
    return ["保存中にエラーが発生しました。"];
  }

  const body = error.body;
  if (Array.isArray(body)) {
    body.forEach((entry) => {
      if (entry && entry.message) {
        messages.push(entry.message);
      }
    });
  } else if (body) {
    if (Array.isArray(body.pageErrors)) {
      body.pageErrors.forEach((entry) => {
        if (entry && entry.message) {
          messages.push(entry.message);
        }
      });
    }

    if (body.fieldErrors) {
      Object.values(body.fieldErrors).forEach((fieldEntries) => {
        (fieldEntries || []).forEach((entry) => {
          if (entry && entry.message) {
            messages.push(entry.message);
          }
        });
      });
    }

    if (body.output && Array.isArray(body.output.errors)) {
      body.output.errors.forEach((entry) => {
        if (entry && entry.message) {
          messages.push(entry.message);
        }
      });
    }

    if (body.message) {
      messages.push(body.message);
    }
  }

  if (!messages.length && error.message) {
    messages.push(error.message);
  }

  if (!messages.length) {
    messages.push("保存中にエラーが発生しました。");
  }

  return messages;
}

function cleanErrorMessage(message) {
  if (!message) {
    return "";
  }

  return String(message)
    .replace(/^FIELD_CUSTOM_VALIDATION_EXCEPTION,\s*/iu, "")
    .replace(/^AuraHandledException:\s*/iu, "")
    .replace(/^Script-thrown exception\s*/iu, "")
    .trim();
}
