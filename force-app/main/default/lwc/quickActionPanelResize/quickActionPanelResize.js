/* 画面の約 95%。標準 flex 中央（ブラウザ実測や zoom に依存しない） */
const LARGE_WIDTH = "95vw";
const LARGE_HEIGHT = "95vh";
const CONFIRM_WIDTH = "32rem";
const CONFIRM_MAX_HEIGHT = "70vh";
const STYLE_ID = "c-quick-action-panel-resize-style";

/** Quick Action host tags that should get the enlarged wizard panel. */
const LARGE_ACTION_HOST_SELECTORS = [
  "c-estimate-create-record-action",
  "c-estimate-edit-record-action",
  "c-estimate-copy-record-action",
  "c-order-create-record-action",
  "c-order-invoice-preview-record-action"
];

/** Compact confirmation dialogs (archive / revert). */
const CONFIRM_ACTION_HOST_SELECTORS = [
  "c-estimate-archive-record-action",
  "c-estimate-action-hub-record-action",
  "c-order-revert-record-action"
];

const RETRY_DELAYS_MS = [0, 50, 100, 250, 500, 1000, 2000];

function joinHasSelectors(selectors, templateFn) {
  return selectors.map(templateFn).join(",\n");
}

function buildCss() {
  const largeHas = LARGE_ACTION_HOST_SELECTORS.join(", ");
  const largeContainerHas = joinHasSelectors(
    LARGE_ACTION_HOST_SELECTORS,
    (sel) => `.slds-modal__container:has(${sel})`
  );
  const largeModalHas = joinHasSelectors(
    LARGE_ACTION_HOST_SELECTORS,
    (sel) => `.slds-modal:has(${sel})`
  );
  const largePanelHas = joinHasSelectors(
    LARGE_ACTION_HOST_SELECTORS,
    (sel) =>
      `runtime_platform_actions-quick-action-panel:has(${sel}), .uiPanel:has(${sel})`
  );

  const confirmHas = CONFIRM_ACTION_HOST_SELECTORS.join(", ");
  const confirmContainerHas = joinHasSelectors(
    CONFIRM_ACTION_HOST_SELECTORS,
    (sel) => `.slds-modal__container:has(${sel})`
  );
  const confirmModalHas = joinHasSelectors(
    CONFIRM_ACTION_HOST_SELECTORS,
    (sel) => `.slds-modal:has(${sel})`
  );
  const confirmPanelHas = joinHasSelectors(
    CONFIRM_ACTION_HOST_SELECTORS,
    (sel) =>
      `runtime_platform_actions-quick-action-panel:has(${sel}), .uiPanel:has(${sel})`
  );

  return `
${largeModalHas},
${confirmModalHas} {
    display: flex !important;
    align-items: center !important;
    justify-content: center !important;
    width: 100% !important;
    height: 100% !important;
    top: 0 !important;
    left: 0 !important;
    right: 0 !important;
    bottom: 0 !important;
    transform: none !important;
    padding: 2.5vh 2.5vw !important;
    box-sizing: border-box !important;
}

${largeContainerHas},
${largePanelHas} {
    width: ${LARGE_WIDTH} !important;
    max-width: min(${LARGE_WIDTH}, 100%) !important;
    min-width: 0 !important;
    height: ${LARGE_HEIGHT} !important;
    max-height: min(${LARGE_HEIGHT}, 100%) !important;
    min-height: 0 !important;
    position: relative !important;
    top: auto !important;
    left: auto !important;
    right: auto !important;
    bottom: auto !important;
    margin: 0 auto !important;
    transform: none !important;
    overflow: hidden !important;
    box-sizing: border-box !important;
}

${confirmContainerHas},
${confirmPanelHas} {
    width: min(100% - 2rem, ${CONFIRM_WIDTH}) !important;
    max-width: min(100% - 2rem, ${CONFIRM_WIDTH}) !important;
    min-width: 0 !important;
    height: auto !important;
    max-height: ${CONFIRM_MAX_HEIGHT} !important;
    min-height: 0 !important;
    position: relative !important;
    top: auto !important;
    left: auto !important;
    right: auto !important;
    bottom: auto !important;
    margin: 0 auto !important;
    transform: none !important;
    box-sizing: border-box !important;
}

${largeContainerHas} .slds-modal__content,
${largeContainerHas} .modal-body,
${largePanelHas} {
    height: 100% !important;
    max-height: 100% !important;
    overflow: hidden !important;
    box-sizing: border-box !important;
}

${confirmContainerHas} .slds-modal__content,
${confirmContainerHas} .modal-body,
${confirmPanelHas} {
    height: auto !important;
    max-height: ${CONFIRM_MAX_HEIGHT} !important;
    overflow: auto !important;
}

${largeHas} {
    display: block !important;
    width: 100% !important;
    height: 100% !important;
    max-width: 100% !important;
    max-height: 100% !important;
    overflow: hidden !important;
    box-sizing: border-box !important;
}

${confirmHas} {
    display: block !important;
    width: 100% !important;
    height: auto !important;
}
`;
}

function ensureGlobalStyle() {
  if (typeof document === "undefined") {
    return;
  }

  // eslint-disable-next-line @lwc/lwc/no-document-query
  let styleEl = document.getElementById(STYLE_ID);
  if (!styleEl) {
    styleEl = document.createElement("style");
    styleEl.id = STYLE_ID;
    (document.head || document.documentElement).appendChild(styleEl);
  }
  styleEl.textContent = buildCss();
}

function isModalContainer(element) {
  if (!element || element.nodeType !== Node.ELEMENT_NODE) {
    return false;
  }

  const classList = element.classList;
  const tagName = element.tagName ? element.tagName.toLowerCase() : "";

  return (
    classList.contains("slds-modal__container") ||
    classList.contains("uiPanel") ||
    classList.contains("panel") ||
    classList.contains("slds-modal") ||
    tagName === "runtime_platform_actions-quick-action-panel" ||
    tagName === "section"
  );
}

function findModalContainer(host) {
  let node = host;
  let found = null;

  for (let depth = 0; depth < 50 && node; depth++) {
    if (
      node.classList &&
      (node.classList.contains("slds-modal__container") ||
        node.classList.contains("uiPanel"))
    ) {
      return node;
    }
    if (
      node.tagName &&
      node.tagName.toLowerCase() ===
        "runtime_platform_actions-quick-action-panel"
    ) {
      found = found || node;
    }
    if (isModalContainer(node) && !found) {
      found = node;
    }
    node = node.parentNode || node.host;
  }

  try {
    // eslint-disable-next-line @lwc/lwc/no-document-query
    const containers = document.querySelectorAll(".slds-modal__container");
    for (let i = 0; i < containers.length; i++) {
      if (containers[i].contains(host)) {
        return containers[i];
      }
    }
  } catch {
    // LWS may block document queries; CSS injection is the fallback.
  }

  return found;
}

function applyInlineLayout(container, size) {
  if (!container || !container.style) {
    return;
  }

  const target =
    container.classList && container.classList.contains("slds-modal")
      ? container.querySelector(".slds-modal__container") || container
      : container;

  const isConfirm = size === "confirm";
  const width = isConfirm ? `min(100% - 2rem, ${CONFIRM_WIDTH})` : LARGE_WIDTH;
  const height = isConfirm ? "auto" : LARGE_HEIGHT;
  const maxHeight = isConfirm ? CONFIRM_MAX_HEIGHT : LARGE_HEIGHT;
  const minHeight = isConfirm ? "0" : "0";

  target.style.setProperty("width", width, "important");
  target.style.setProperty(
    "max-width",
    isConfirm ? width : `min(${LARGE_WIDTH}, 100%)`,
    "important"
  );
  target.style.setProperty("min-width", "0", "important");
  target.style.setProperty("height", height, "important");
  target.style.setProperty(
    "max-height",
    isConfirm ? maxHeight : `min(${LARGE_HEIGHT}, 100%)`,
    "important"
  );
  target.style.setProperty("min-height", minHeight, "important");
  target.style.setProperty("position", "relative", "important");
  target.style.setProperty("top", "auto", "important");
  target.style.setProperty("left", "auto", "important");
  target.style.setProperty("right", "auto", "important");
  target.style.setProperty("bottom", "auto", "important");
  target.style.setProperty("margin", "0 auto", "important");
  target.style.setProperty("transform", "none", "important");
  target.style.setProperty(
    "overflow",
    isConfirm ? "auto" : "hidden",
    "important"
  );
  target.style.setProperty("box-sizing", "border-box", "important");

  const modal =
    (target.closest && target.closest(".slds-modal")) ||
    (target.classList && target.classList.contains("slds-modal")
      ? target
      : null);
  if (modal && modal.style) {
    modal.style.setProperty("display", "flex", "important");
    modal.style.setProperty("align-items", "center", "important");
    modal.style.setProperty("justify-content", "center", "important");
    modal.style.setProperty("width", "100%", "important");
    modal.style.setProperty("height", "100%", "important");
    modal.style.setProperty("top", "0", "important");
    modal.style.setProperty("left", "0", "important");
    modal.style.setProperty("right", "0", "important");
    modal.style.setProperty("bottom", "0", "important");
    modal.style.setProperty("transform", "none", "important");
    modal.style.setProperty("padding", "2.5vh 2.5vw", "important");
    modal.style.setProperty("box-sizing", "border-box", "important");
  }

  /* quick-action-panel 単体のときも、親を flex 中央に寄せる */
  const panelParent = target.parentElement;
  if (
    (!modal || !modal.style) &&
    panelParent &&
    panelParent.style &&
    target !== panelParent
  ) {
    panelParent.style.setProperty("display", "flex", "important");
    panelParent.style.setProperty("align-items", "center", "important");
    panelParent.style.setProperty("justify-content", "center", "important");
    panelParent.style.setProperty("box-sizing", "border-box", "important");
  }

  const modalContent =
    (target.querySelector && target.querySelector(".slds-modal__content")) ||
    (target.closest && target.closest(".slds-modal__content"));
  if (modalContent && modalContent.style) {
    modalContent.style.setProperty(
      "height",
      isConfirm ? "auto" : "100%",
      "important"
    );
    modalContent.style.setProperty(
      "max-height",
      isConfirm ? maxHeight : "100%",
      "important"
    );
    modalContent.style.setProperty(
      "overflow",
      isConfirm ? "auto" : "hidden",
      "important"
    );
    modalContent.style.setProperty("box-sizing", "border-box", "important");
  }
}

function applyOnce(host, size) {
  ensureGlobalStyle();
  const container = findModalContainer(host);
  if (container) {
    applyInlineLayout(container, size);
  }
}

/**
 * Resize the Salesforce Quick Action modal.
 * @param {LightningElement} component
 * @param {'large'|'confirm'} [size='large'] large ≈ 95vw×95vh wizard; confirm = compact dialog
 */
export function resizeQuickActionPanel(component, size = "large") {
  if (typeof window === "undefined" || !component?.template?.host) {
    return;
  }

  const host = component.template.host;
  const panelSize = size === "confirm" ? "confirm" : "large";
  const run = () => applyOnce(host, panelSize);

  ensureGlobalStyle();

  if (typeof requestAnimationFrame === "function") {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(run);
  }

  RETRY_DELAYS_MS.forEach((delay) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(run, delay);
  });

  try {
    if (typeof MutationObserver === "function" && document.body) {
      const observer = new MutationObserver(run);
      observer.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["class", "style"]
      });
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => observer.disconnect(), 2500);
    }
  } catch {
    // Ignore observer failures under restricted DOM access.
  }
}
