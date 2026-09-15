({
  /** 仕様: Core 第3.3.2節・第3.3.3節。関連リスト新規の defaultFieldValues と、見積／受注からの戻り先を LWC へ渡す。 */
  syncMode: function (component) {
    component.set(
      "v.formMode",
      component.get("v.recordId") ? "edit" : "new"
    );
    var defaults = this.readDefaultFieldValues(component);
    var returnTo = "";
    var returnRecordId = "";
    var pageRef = component.get("v.pageReference");
    var state = pageRef && pageRef.state ? pageRef.state : null;
    if (!component.get("v.recordId")) {
      var accountId = this.resolveParentAccountId(component, defaults);
      if (accountId && defaults.indexOf("Account__c=") === -1) {
        defaults = defaults
          ? defaults + ",Account__c=" + accountId
          : "Account__c=" + accountId;
      }
    }
    if (state) {
      if (state.c__returnTo) {
        returnTo = state.c__returnTo;
      }
      if (state.c__returnRecordId) {
        returnRecordId = state.c__returnRecordId;
      }
    }
    if (!returnTo || !returnRecordId) {
      var locSearch =
        window.location && window.location.search
          ? window.location.search
          : "";
      if (!returnTo) {
        returnTo = this.decodeQueryParam(locSearch, "c__returnTo");
      }
      if (!returnRecordId) {
        returnRecordId = this.decodeQueryParam(locSearch, "c__returnRecordId");
      }
    }
    component.set("v.defaultFieldValues", defaults);
    component.set("v.returnTo", returnTo || "");
    component.set("v.returnRecordId", returnRecordId || "");
  },

  decodeQueryParam: function (search, name) {
    if (!search) {
      return "";
    }
    var match = String(search).match(new RegExp("[?&]" + name + "=([^&]*)"));
    if (!match) {
      return "";
    }
    try {
      return decodeURIComponent(match[1].replace(/\+/g, " "));
    } catch (ex) {
      return match[1];
    }
  },

  readDefaultFieldValues: function (component) {
    var pageRef = component.get("v.pageReference");
    var state = pageRef && pageRef.state ? pageRef.state : null;
    var fromState =
      state && state.defaultFieldValues ? state.defaultFieldValues : null;
    if (fromState && typeof fromState === "object") {
      if (fromState.Account__c) {
        return "Account__c=" + fromState.Account__c;
      }
      return "";
    }
    if (fromState && typeof fromState === "string") {
      return fromState;
    }
    return this.decodeQueryParam(
      window.location && window.location.search ? window.location.search : "",
      "defaultFieldValues"
    );
  },

  accountIdFromAccountUrl: function (url) {
    if (!url) {
      return "";
    }
    var text = String(url);
    try {
      text = decodeURIComponent(text.replace(/\+/g, " "));
    } catch (ex) {
      text = String(url);
    }
    var match = text.match(
      /\/(?:lightning\/r\/)?Account\/([a-zA-Z0-9]{15,18})(?:\/|$|\?|&)/
    );
    return match ? match[1] : "";
  },

  accountIdFromInContextOfRef: function (raw) {
    if (!raw) {
      return "";
    }
    var decoded = raw;
    if (typeof raw === "string") {
      var encoded = raw;
      try {
        encoded = decodeURIComponent(raw.replace(/\+/g, " "));
      } catch (ex) {
        encoded = raw;
      }
      if (encoded.indexOf("1.") === 0) {
        encoded = encoded.substring(2);
      }
      try {
        var normalized = encoded.replace(/-/g, "+").replace(/_/g, "/");
        while (normalized.length % 4 !== 0) {
          normalized += "=";
        }
        decoded = JSON.parse(window.atob(normalized));
      } catch (ex2) {
        return "";
      }
    }
    var attributes = decoded && decoded.attributes ? decoded.attributes : null;
    if (!attributes || !attributes.recordId) {
      return "";
    }
    if (attributes.objectApiName === "Account") {
      return attributes.recordId;
    }
    if (
      !attributes.objectApiName &&
      String(attributes.recordId).indexOf("001") === 0
    ) {
      return attributes.recordId;
    }
    return "";
  },

  /** 仕様: Core 第3.3.2節。クリック元の取引先を New の初期値にする。 */
  resolveParentAccountId: function (component, defaults) {
    if (defaults && defaults.indexOf("Account__c=") !== -1) {
      var fromDefaults = defaults.match(/Account__c=([^,]*)/);
      if (fromDefaults && fromDefaults[1]) {
        return fromDefaults[1];
      }
    }
    var pageRef = component.get("v.pageReference");
    var state = pageRef && pageRef.state ? pageRef.state : {};
    var search =
      window.location && window.location.search ? window.location.search : "";
    var href =
      window.location && window.location.href ? window.location.href : "";
    var fromRef = this.accountIdFromInContextOfRef(
      (state && state.inContextOfRef) ||
        this.decodeQueryParam(search, "inContextOfRef")
    );
    if (fromRef) {
      return fromRef;
    }
    var fromBackground = this.accountIdFromAccountUrl(
      (state && state.backgroundContext) ||
        this.decodeQueryParam(search, "backgroundContext")
    );
    if (fromBackground) {
      return fromBackground;
    }
    return this.accountIdFromAccountUrl(href);
  }
});
