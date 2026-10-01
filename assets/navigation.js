(() => {
  const sections = [...document.querySelectorAll('details[name="lesson-sections"]')];
  const current = document.querySelector(".lesson-tree a.is-current")?.closest("details");
  sections.forEach((section) => {
    section.open = section === current;
  });

  const desktopButton = document.querySelector(".sidebar-toggle");
  if (desktopButton) {
    const updateDesktopButton = () => {
      const collapsed = document.documentElement.dataset.sidebar === "collapsed";
      const label = collapsed ? "Arată navigarea" : "Ascunde navigarea";
      desktopButton.setAttribute("aria-expanded", String(!collapsed));
      desktopButton.setAttribute("aria-label", label);
      desktopButton.title = label;
    };

    updateDesktopButton();
    desktopButton.addEventListener("click", () => {
      const collapsed = document.documentElement.dataset.sidebar !== "collapsed";
      if (collapsed) document.documentElement.dataset.sidebar = "collapsed";
      else delete document.documentElement.dataset.sidebar;
      try {
        localStorage.setItem("sidebar", collapsed ? "collapsed" : "expanded");
      } catch {}
      updateDesktopButton();
    });
  }

  const button = document.querySelector(".nav-toggle");
  const sidebar = document.querySelector(".sidebar");
  const scrim = document.querySelector(".nav-scrim");
  if (!button || !sidebar || !scrim) return;

  const close = () => {
    document.body.classList.remove("nav-open");
    button.setAttribute("aria-expanded", "false");
    scrim.hidden = true;
  };

  button.addEventListener("click", () => {
    const open = !document.body.classList.contains("nav-open");
    document.body.classList.toggle("nav-open", open);
    button.setAttribute("aria-expanded", String(open));
    scrim.hidden = !open;
  });
  scrim.addEventListener("click", close);
  sidebar.addEventListener("click", (event) => {
    if (event.target.closest("a")) close();
  });
  addEventListener("keydown", (event) => {
    if (event.key === "Escape") close();
  });
})();
