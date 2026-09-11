({
  /** 仕様: Core 第3.3.2節・第3.3.3節。Aura 上書きは New か Edit。View はレコードページ。関連リスト新規の defaultFieldValues と、見積／受注からの戻り先を LWC へ渡す。 */
  syncMode: function (component) {
    component.set(
      "v.formMode",
      component.get("v.recordId") ? "edit" : "new"
    );
    var defaults = "";
    var returnTo = "";
    var returnRecordId = "";
    var pageRef = component.get("v.pageReference");
    var state = pageRef && pageRef.state ? pageRef.state : null;
    var fromState =
      state && state.defaultFieldValues ? state.defaultFieldValues : null;
    if (fromState && typeof fromState === "string") {
      defaults = fromState;
    } else {
      var search =
        window.location && window.location.search
          ? window.location.search
          : "";
      var match = search.match(/[?&]defaultFieldValues=([^&]*)/);
      if (match) {
        try {
          defaults = decodeURIComponent(match[1].replace(/\+/g, " "));
        } catch (ex) {
          defaults = match[1];
        }
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
        var returnToMatch = locSearch.match(/[?&]c__returnTo=([^&]*)/);
        if (returnToMatch) {
          try {
            returnTo = decodeURIComponent(returnToMatch[1].replace(/\+/g, " "));
          } catch (ex2) {
            returnTo = returnToMatch[1];
          }
        }
      }
      if (!returnRecordId) {
        var returnIdMatch = locSearch.match(/[?&]c__returnRecordId=([^&]*)/);
        if (returnIdMatch) {
          try {
            returnRecordId = decodeURIComponent(
              returnIdMatch[1].replace(/\+/g, " ")
            );
          } catch (ex3) {
            returnRecordId = returnIdMatch[1];
          }
        }
      }
    }
    component.set("v.defaultFieldValues", defaults);
    component.set("v.returnTo", returnTo || "");
    component.set("v.returnRecordId", returnRecordId || "");
  }
});
