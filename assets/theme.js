(() => {
  const themes = ["light", "dark"];
  const root = document.documentElement;
  const button = document.querySelector(".theme-toggle");
  const themeColor = document.querySelector('meta[name="theme-color"]');

  const apply = (theme, save) => {
    if (!themes.includes(theme)) return;
    const dark = theme === "dark";
    root.dataset.theme = theme;
    button?.setAttribute("aria-pressed", String(dark));
    button?.setAttribute(
      "aria-label",
      dark ? "Activează tema luminoasă" : "Activează tema întunecată",
    );
    if (themeColor) themeColor.content = dark ? "#0a1a2b" : "#f7f5f0";
    if (save) try {
      localStorage.setItem("theme", theme);
    } catch {}
  };

  button?.addEventListener("click", () => {
    apply(root.dataset.theme === "dark" ? "light" : "dark", true);
  });
  apply(themes.includes(root.dataset.theme) ? root.dataset.theme : "light", false);
})();
