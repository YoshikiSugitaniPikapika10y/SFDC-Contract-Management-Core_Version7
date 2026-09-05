({
  /** 仕様: Core 第3.3.2節。Aura 上書きは New か Edit。View はレコードページ。関連リスト新規の defaultFieldValues を LWC へ渡す。 */
  syncMode: function (component) {
    component.set(
      "v.formMode",
      component.get("v.recordId") ? "edit" : "new"
    );
    var defaults = "";
    var pageRef = component.get("v.pageReference");
    var fromState =
      pageRef && pageRef.state ? pageRef.state.defaultFieldValues : null;
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
    component.set("v.defaultFieldValues", defaults);
  }
});
