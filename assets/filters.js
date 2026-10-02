(() => {
  const browser = document.querySelector(".tag-browser");
  if (!browser) return;

  const filters = [...browser.querySelectorAll(".tag-filter")];
  const results = [...browser.querySelectorAll(".tag-result")];

  const apply = () => {
    const selected = filters.filter((filter) => filter.checked).map((filter) => (
      filter.id.startsWith("author-")
        ? ["author", filter.id.slice("author-".length)]
        : ["tag", filter.id]
    ));
    for (const result of results) {
      result.hidden = selected.some(([kind, value]) => (
        !result.querySelector(`[data-${kind}="${CSS.escape(value)}"]`)
      ));
    }
  };

  const selectHash = () => {
    const target = document.getElementById(decodeURIComponent(location.hash.slice(1)));
    if (target?.classList.contains("tag-filter")) target.checked = true;
    apply();
  };

  browser.addEventListener("change", (event) => {
    if (!event.target.classList.contains("tag-filter")) return;
    history.replaceState(null, "", `${location.pathname}${location.search}`);
    apply();
  });
  addEventListener("hashchange", selectHash);
  selectHash();
})();
