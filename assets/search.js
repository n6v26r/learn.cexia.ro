(() => {
  const sidebarSearch = document.querySelector(".sidebar-search");
  const sidebarInput = sidebarSearch?.querySelector("[data-search-input]");
  const quickSearch = sidebarSearch?.querySelector(".quick-search");
  const quickStatus = quickSearch?.querySelector(".search-status");
  const quickResults = quickSearch?.querySelector(".quick-search-results");
  const pageSearch = document.querySelector(".search-page-form");
  const pageInput = pageSearch?.querySelector("[data-search-input]");
  const pageStatus = document.querySelector(".search-page-status");
  const pageResults = document.querySelector(".search-page-results");
  let corpusPromise;

  const normalize = (value) => value
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLocaleLowerCase("ro")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();

  const words = (value) => [...new Set(normalize(value).split(" ").filter(Boolean))];

  const distance = (left, right) => {
    let older = null;
    let previous = Array.from({ length: right.length + 1 }, (_, index) => index);

    for (let i = 1; i <= left.length; i += 1) {
      const current = [i];
      for (let j = 1; j <= right.length; j += 1) {
        const cost = left[i - 1] === right[j - 1] ? 0 : 1;
        current[j] = Math.min(
          current[j - 1] + 1,
          previous[j] + 1,
          previous[j - 1] + cost,
        );
        if (
          older
          && i > 1
          && j > 1
          && left[i - 1] === right[j - 2]
          && left[i - 2] === right[j - 1]
        ) current[j] = Math.min(current[j], older[j - 2] + 1);
      }
      older = previous;
      previous = current;
    }
    return previous[right.length];
  };

  const wordScore = (term, candidates) => {
    let best = 0;
    const tolerance = term.length >= 8 ? 2 : term.length >= 4 ? 1 : 0;
    for (const candidate of candidates) {
      if (candidate === term) return 40;
      if (candidate.startsWith(term)) best = Math.max(best, 30);
      else if (term.length >= 3 && candidate.includes(term)) best = Math.max(best, 20);
      else if (tolerance && Math.abs(candidate.length - term.length) <= tolerance) {
        const edits = distance(term, candidate);
        if (edits <= tolerance) best = Math.max(best, 14 - edits * 3);
      }
    }
    return best;
  };

  const wordMap = (value) => {
    let text = "";
    const offsets = [];
    for (let start = 0; start < value.length;) {
      const character = String.fromCodePoint(value.codePointAt(start));
      const end = start + character.length;
      const normalized = character
        .normalize("NFD")
        .replace(/\p{M}/gu, "")
        .toLocaleLowerCase("ro")
        .replace(/[^\p{L}\p{N}]/gu, " ");
      for (const part of normalized) {
        text += part;
        offsets.push({ start, end });
      }
      start = end;
    }
    return { text, offsets };
  };

  const highlight = (element, text, query) => {
    const terms = words(query);
    const ranges = [];
    for (const match of text.matchAll(/[\p{L}\p{N}_]+/gu)) {
      const mapped = wordMap(match[0]);
      for (const term of terms) {
        const index = mapped.text.indexOf(term);
        if (index >= 0) {
          ranges.push({
            start: match.index + mapped.offsets[index].start,
            end: match.index + mapped.offsets[index + term.length - 1].end,
          });
        } else if (wordScore(term, [mapped.text])) {
          ranges.push({ start: match.index, end: match.index + match[0].length });
        }
      }
    }

    const merged = ranges
      .sort((left, right) => left.start - right.start)
      .reduce((result, range) => {
        const previous = result.at(-1);
        if (previous && range.start <= previous.end) previous.end = Math.max(previous.end, range.end);
        else result.push(range);
        return result;
      }, []);

    let offset = 0;
    for (const range of merged) {
      element.append(document.createTextNode(text.slice(offset, range.start)));
      const mark = document.createElement("mark");
      mark.className = "search-match";
      mark.textContent = text.slice(range.start, range.end);
      element.append(mark);
      offset = range.end;
    }
    element.append(document.createTextNode(text.slice(offset)));
  };

  const documentBlocks = (entry) => {
    const content = entry.querySelector(".search-document-content");
    const scope = content.content || content;
    let nodes = [...scope.querySelectorAll(
      ".nb-markdown :is(h2, h3, h4, p, li, th, td, script[type='math/tex']), .nb-code > pre:first-child",
    )];
    if (!nodes.length) nodes = [...scope.querySelectorAll("h2, h3, h4, p, li, th, td, pre, script[type='math/tex']")];

    const seen = new Set();
    return nodes
      .map((node) => node.textContent.replace(/\s+/g, " ").trim())
      .filter((text) => text && !seen.has(text) && seen.add(text))
      .map((text) => ({ text, normalized: normalize(text), words: words(text) }));
  };

  const readCorpus = (scope) => [...scope.querySelectorAll(".search-document")].map((entry) => {
    const link = entry.querySelector(".search-document-link");
    const blocks = documentBlocks(entry);
    const title = link.textContent.trim();
    const text = blocks.map((block) => block.text).join(" ");
    return {
      title,
      url: link.getAttribute("href"),
      titleNormalized: normalize(title),
      titleWords: words(title),
      textNormalized: normalize(text),
      textWords: words(text),
      blocks,
    };
  });

  const loadCorpus = () => {
    if (corpusPromise) return corpusPromise;
    corpusPromise = (async () => {
      let corpus = document.querySelector(".search-corpus");
      if (!corpus) {
        const response = await fetch(sidebarSearch.action);
        if (!response.ok) throw new Error(`search index: ${response.status}`);
        const page = new DOMParser().parseFromString(await response.text(), "text/html");
        corpus = page.querySelector(".search-corpus");
      }
      if (!corpus) throw new Error("search index missing");
      return readCorpus(corpus);
    })();
    return corpusPromise;
  };

  const scoreBlock = (block, terms, phrase) => {
    let score = block.normalized.includes(phrase) ? 30 : 0;
    for (const term of terms) score += wordScore(term, block.words);
    return score;
  };

  const excerpt = (document, terms, phrase) => {
    const block = document.blocks.reduce((best, candidate) => (
      scoreBlock(candidate, terms, phrase) > scoreBlock(best, terms, phrase) ? candidate : best
    ), document.blocks[0] || { text: "", normalized: "", words: [] });
    if (!block.text) return "";

    const matches = [...block.text.matchAll(/[\p{L}\p{N}_]+/gu)];
    let offset = 0;
    let matchScore = 0;
    for (const match of matches) {
      for (const term of terms) {
        const score = wordScore(term, [normalize(match[0])]);
        if (score > matchScore) {
          matchScore = score;
          offset = match.index;
        }
      }
    }

    let start = Math.max(0, offset - 55);
    if (start) start = block.text.indexOf(" ", start) + 1 || start;
    let end = Math.min(block.text.length, start + 190);
    if (end < block.text.length) {
      const boundary = block.text.lastIndexOf(" ", end);
      if (boundary > start) end = boundary;
    }
    return `${start ? "…" : ""}${block.text.slice(start, end).trim()}${end < block.text.length ? "…" : ""}`;
  };

  const search = (documents, query) => {
    const phrase = normalize(query);
    const terms = [...new Set(phrase.split(" ").filter(Boolean))];
    if (phrase.length < 2 || !terms.length) return [];

    return documents.flatMap((document) => {
      let score = document.titleNormalized.includes(phrase) ? 180 : 0;
      if (document.textNormalized.includes(phrase)) score += 45;

      for (const term of terms) {
        const title = wordScore(term, document.titleWords) * 4;
        const content = wordScore(term, document.textWords);
        const termScore = Math.max(title, content);
        if (!termScore) return [];
        score += termScore;
      }

      return [{ document, score, excerpt: excerpt(document, terms, phrase) }];
    }).sort((left, right) => (
      right.score - left.score || left.document.title.localeCompare(right.document.title, "ro")
    ));
  };

  const resultItem = ({ document: lesson, excerpt: text }, query, showHighlights) => {
    const item = document.createElement("li");
    item.className = "search-result";
    const link = document.createElement("a");
    link.href = lesson.url;
    link.setAttribute("role", "option");

    const title = document.createElement("strong");
    title.className = "search-result-title";
    if (showHighlights) highlight(title, lesson.title, query);
    else title.textContent = lesson.title;
    const path = document.createElement("span");
    path.className = "search-result-path";
    path.textContent = lesson.url;
    link.append(title, path);

    if (text) {
      const snippet = document.createElement("p");
      snippet.className = "search-result-excerpt";
      if (showHighlights) highlight(snippet, text, query);
      else snippet.textContent = text;
      link.append(snippet);
    }
    item.append(link);
    return item;
  };

  const setQueryUrl = (query) => {
    const url = new URL(location.href);
    if (query) url.searchParams.set("q", query);
    else url.searchParams.delete("q");
    history.replaceState(null, "", url);
  };

  const searchPageUrl = (query) => {
    const url = new URL(sidebarSearch.action);
    url.searchParams.set("q", query);
    return url;
  };

  const showQuickResults = async () => {
    const query = sidebarInput.value.trim();
    if (query.length < 2) {
      quickSearch.hidden = true;
      sidebarInput.setAttribute("aria-expanded", "false");
      return;
    }

    quickSearch.hidden = false;
    sidebarInput.setAttribute("aria-expanded", "true");
    quickStatus.textContent = "Se caută…";
    quickResults.replaceChildren();
    try {
      const results = search(await loadCorpus(), query);
      quickStatus.textContent = results.length
        ? `${results.length} ${results.length === 1 ? "rezultat" : "rezultate"}`
        : "Niciun rezultat";
      quickResults.append(...results.slice(0, 6).map((result) => resultItem(result, query, false)));
      if (results.length) {
        const more = document.createElement("li");
        more.className = "search-result quick-search-more";
        const link = document.createElement("a");
        link.href = searchPageUrl(query);
        link.textContent = "Vezi toate rezultatele";
        more.append(link);
        quickResults.append(more);
      }
    } catch {
      quickStatus.textContent = "Căutarea nu a putut fi încărcată.";
    }
  };

  const showPageResults = async () => {
    if (!pageInput) return;
    const query = pageInput.value.trim();
    sidebarInput.value = query;
    pageResults.replaceChildren();
    if (query.length < 2) {
      pageStatus.textContent = "Introdu cel puțin două caractere.";
      return;
    }

    pageStatus.textContent = "Se caută…";
    try {
      const results = search(await loadCorpus(), query);
      pageStatus.textContent = results.length
        ? `${results.length} ${results.length === 1 ? "rezultat" : "rezultate"}`
        : "Niciun rezultat";
      pageResults.append(...results.map((result) => resultItem(result, query, true)));
    } catch {
      pageStatus.textContent = "Căutarea nu a putut fi încărcată.";
    }
  };

  if (sidebarSearch) {
    let timer;
    sidebarInput.addEventListener("input", () => {
      clearTimeout(timer);
      timer = setTimeout(showQuickResults, 80);
    });
    sidebarInput.addEventListener("focus", showQuickResults);
    sidebarInput.addEventListener("keydown", (event) => {
      if (event.key === "ArrowDown") {
        const first = quickResults.querySelector("a");
        if (first) {
          event.preventDefault();
          first.focus();
        }
      }
      if (event.key === "Escape") {
        quickSearch.hidden = true;
        sidebarInput.setAttribute("aria-expanded", "false");
      }
    });
    sidebarSearch.addEventListener("submit", (event) => {
      if (sidebarInput.value.trim().length < 2) event.preventDefault();
    });
    quickResults.addEventListener("keydown", (event) => {
      if (!['ArrowDown', 'ArrowUp', 'Escape'].includes(event.key)) return;
      event.preventDefault();
      if (event.key === "Escape") {
        quickSearch.hidden = true;
        sidebarInput.focus();
        return;
      }
      const links = [...quickResults.querySelectorAll("a")];
      const index = links.indexOf(document.activeElement);
      const next = event.key === "ArrowDown" ? index + 1 : index - 1;
      (links[next] || (next < 0 ? sidebarInput : links[0]))?.focus();
    });
    document.addEventListener("pointerdown", (event) => {
      if (!sidebarSearch.contains(event.target)) {
        quickSearch.hidden = true;
        sidebarInput.setAttribute("aria-expanded", "false");
      }
    });
  }

  if (pageSearch) {
    const initialQuery = new URLSearchParams(location.search).get("q") || "";
    pageInput.value = initialQuery;
    sidebarInput.value = initialQuery;
    let timer;
    pageInput.addEventListener("input", () => {
      clearTimeout(timer);
      sidebarInput.value = pageInput.value;
      setQueryUrl(pageInput.value.trim());
      timer = setTimeout(showPageResults, 80);
    });
    pageSearch.addEventListener("submit", (event) => {
      event.preventDefault();
      setQueryUrl(pageInput.value.trim());
      showPageResults();
    });
    showPageResults();
  }

})();
