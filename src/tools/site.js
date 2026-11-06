// The search and the keys of cesia doc --site. Every page reads without it; it asks for no file but those of the site, and
// loads the index of the search at the first search only.
(function () {
  "use strict";
  var root = document.documentElement, base = document.body.getAttribute("data-root") || "";
  var header = document.querySelector("header"), input = document.querySelector("input.search");
  root.classList.add("js");
  try {
    var saved = localStorage.getItem("cesia-theme");
    if (saved === "dark" || saved === "light") root.setAttribute("data-theme", saved);
  } catch (e) {}

  var theme = document.createElement("button");
  theme.className = "theme"; theme.type = "button"; theme.textContent = "◐";
  theme.setAttribute("aria-label", "Switch between dark and light");
  header.appendChild(theme);
  theme.addEventListener("click", function () {
    var chosen = root.getAttribute("data-theme");
    var dark = chosen ? chosen === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
    root.setAttribute("data-theme", dark ? "light" : "dark");
    try { localStorage.setItem("cesia-theme", dark ? "light" : "dark"); } catch (e) {}
  });

  var list = document.createElement("ul"), index = null, shown = [], picked = -1;
  list.className = "results"; list.id = "results"; list.hidden = true; list.setAttribute("role", "listbox");
  header.appendChild(list);
  input.setAttribute("role", "combobox"); input.setAttribute("aria-controls", "results");
  input.setAttribute("aria-expanded", "false"); input.setAttribute("aria-autocomplete", "list");

  function load() {
    if (index || document.getElementById("search-index")) return;
    var s = document.createElement("script");
    s.id = "search-index"; s.src = base + "search.js";
    s.onload = function () { index = window.cesiaSearch || []; find(); };
    document.body.appendChild(s);
  }
  // The exact name first, then its last part, a start, a part of the name, and last the words of what it says.
  function rank(e, q) {
    var t = e[2].toLowerCase(), last = t.slice(t.lastIndexOf(".") + 1);
    if (t === q) return 0;
    if (last === q) return 1;
    if (t.indexOf(q) === 0 || last.indexOf(q) === 0) return 2;
    if (t.indexOf(q) >= 0) return 3;
    if (e[3].toLowerCase().indexOf(q) >= 0) return 4;
    return e[4].toLowerCase().indexOf(q) >= 0 ? 5 : -1;
  }
  function find() {
    var q = input.value.trim().toLowerCase(), found = [];
    if (index && q) {
      for (var i = 0; i < index.length; i++) {
        var r = rank(index[i], q);
        if (r >= 0) found.push([r, index[i][2].length, i]);
      }
      found.sort(function (a, b) { return a[0] - b[0] || a[1] - b[1] || a[2] - b[2]; });
    }
    shown = found.slice(0, 20).map(function (f) { return index[f[2]]; });
    picked = shown.length ? 0 : -1;
    draw();
  }
  function part(tag, cls, text) {
    var e = document.createElement(tag);
    e.className = cls; e.textContent = text;
    return e;
  }
  function draw() {
    list.textContent = "";
    shown.forEach(function (e, k) {
      var li = document.createElement("li");
      li.id = "result-" + k; li.setAttribute("role", "option"); li.setAttribute("aria-selected", String(k === picked));
      li.appendChild(part("span", "title", e[2])); li.appendChild(part("span", "kind", e[0]));
      li.appendChild(part("span", "about", e[3]));
      li.addEventListener("mousedown", function (ev) { ev.preventDefault(); go(e); });
      list.appendChild(li);
    });
    list.hidden = shown.length === 0;
    input.setAttribute("aria-expanded", String(shown.length > 0));
    if (picked >= 0) {
      input.setAttribute("aria-activedescendant", "result-" + picked);
      document.getElementById("result-" + picked).scrollIntoView({ block: "nearest" });
    } else input.removeAttribute("aria-activedescendant");
  }
  function go(e) { location.href = base + e[1]; }
  input.addEventListener("focus", function () { load(); find(); });
  input.addEventListener("input", find);
  input.addEventListener("blur", function () { list.hidden = true; input.setAttribute("aria-expanded", "false"); });
  input.addEventListener("keydown", function (ev) {
    var n = shown.length;
    if (ev.key === "ArrowDown" && n) picked = (picked + 1) % n;
    else if (ev.key === "ArrowUp" && n) picked = (picked + n - 1) % n;
    else if (ev.key === "Enter" && picked >= 0) go(shown[picked]);
    else if (ev.key === "Escape") { input.value = ""; input.blur(); return; }
    else return;
    ev.preventDefault();
    draw();
  });

  var keys = document.createElement("dl");
  keys.className = "keys"; keys.hidden = true; keys.setAttribute("aria-label", "Keys");
  [["/ s", "search"], ["n", "the next page"], ["p", "the previous page"], ["u", "the page above"], ["t", "the home page"],
   ["?", "these keys"]].forEach(function (k) {
    keys.appendChild(part("dt", "", k[0])); keys.appendChild(part("dd", "", k[1]));
  });
  document.body.appendChild(keys);
  document.addEventListener("keydown", function (ev) {
    var t = ev.target, rel = { n: "next", p: "prev", u: "up" }[ev.key];
    if (ev.ctrlKey || ev.metaKey || ev.altKey || t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable) return;
    if (ev.key === "/" || ev.key === "s") { input.focus(); ev.preventDefault(); }
    else if (rel) { var a = document.querySelector("a[rel=" + rel + "]"); if (a) location.href = a.href; }
    else if (ev.key === "t") location.href = base + "index.html";
    else if (ev.key === "?") keys.hidden = !keys.hidden;
    else if (ev.key === "Escape") keys.hidden = true;
  });
})();
