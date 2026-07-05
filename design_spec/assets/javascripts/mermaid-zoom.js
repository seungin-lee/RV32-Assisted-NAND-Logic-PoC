(function () {
  var mermaidLoad = null;
  var mermaidReady = false;
  var renderId = 0;

  function loadMermaid() {
    if (window.mermaid) {
      return Promise.resolve(window.mermaid);
    }

    if (mermaidLoad) {
      return mermaidLoad;
    }

    mermaidLoad = new Promise(function (resolve, reject) {
      var script = document.createElement("script");

      script.src = "https://unpkg.com/mermaid@11/dist/mermaid.min.js";
      script.onload = function () {
        resolve(window.mermaid);
      };
      script.onerror = function () {
        reject(new Error("failed to load mermaid"));
      };

      document.head.appendChild(script);
    });

    return mermaidLoad;
  }

  function initMermaid(mermaid) {
    if (!mermaidReady) {
      mermaid.initialize({
        startOnLoad: false,
        theme: "default",
        securityLevel: "loose",
        sequence: {
          actorFontSize: "16px",
          messageFontSize: "16px",
          noteFontSize: "16px"
        }
      });
      mermaidReady = true;
    }

    return mermaid;
  }

  function getSource(block) {
    var code = block.querySelector("code");

    return code ? code.textContent : block.textContent;
  }

  function fallbackCodeBlock(source, message) {
    var wrap = document.createElement("div");
    var note = document.createElement("p");
    var pre = document.createElement("pre");

    wrap.className = "mermaid-rendered mermaid-render-error";
    note.textContent = message || "Mermaid render failed.";
    pre.className = "mermaid-zoom-fallback";
    pre.textContent = source;

    wrap.appendChild(note);
    wrap.appendChild(pre);

    return wrap;
  }

  function renderSource(target, source, zoomed) {
    return loadMermaid()
      .then(initMermaid)
      .then(function (mermaid) {
        var id = "mermaid_" + renderId++;

        return mermaid.render(id, source);
      })
      .then(function (result) {
        target.innerHTML = result.svg;
        if (zoomed) {
          target.classList.add("mermaid-zoom-content");
        }
        if (result.bindFunctions) {
          result.bindFunctions(target);
        }
      });
  }

  function renderBlock(block) {
    var source = getSource(block);
    var wrapper = document.createElement("div");

    wrapper.className = "mermaid-rendered";
    wrapper.__mermaidSource = source;
    wrapper.textContent = "Rendering diagram...";
    block.replaceWith(wrapper);

    renderSource(wrapper, source, false).catch(function () {
      wrapper.replaceWith(fallbackCodeBlock(source));
    });
  }

  function renderAll() {
    Array.prototype.forEach.call(
      document.querySelectorAll("pre.mermaid-source"),
      renderBlock
    );
  }

  function closeOverlay(overlay) {
    if (overlay && overlay.parentNode) {
      overlay.parentNode.removeChild(overlay);
    }
  }

  function openOverlay(source) {
    var overlay = document.createElement("div");
    var dialog = document.createElement("div");
    var toolbar = document.createElement("div");
    var stage = document.createElement("div");
    var zoomOut = document.createElement("button");
    var zoomIn = document.createElement("button");
    var fit = document.createElement("button");
    var reset = document.createElement("button");
    var close = document.createElement("button");
    var content = document.createElement("div");
    var diagramSource = source.__mermaidSource;
    var scale = 1;

    if (!diagramSource) {
      return;
    }

    overlay.className = "mermaid-zoom-overlay";
    overlay.setAttribute("role", "presentation");

    dialog.className = "mermaid-zoom-dialog";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    dialog.setAttribute("aria-label", "Expanded Mermaid diagram");

    toolbar.className = "mermaid-zoom-toolbar";
    stage.className = "mermaid-zoom-stage";

    function configureButton(button, label, ariaLabel) {
      button.className = "mermaid-zoom-button";
      button.type = "button";
      button.textContent = label;
      button.setAttribute("aria-label", ariaLabel);
    }

    configureButton(zoomOut, "-", "Zoom out");
    configureButton(zoomIn, "+", "Zoom in");
    configureButton(fit, "Fit", "Fit diagram to view");
    configureButton(reset, "100%", "Reset zoom");
    configureButton(close, "x", "Close expanded diagram");
    close.classList.add("mermaid-zoom-close");

    content.className = "mermaid-zoom-content";
    content.textContent = "Rendering diagram...";

    function setScale(nextScale) {
      scale = Math.min(4, Math.max(0.25, nextScale));
      content.style.transform = "scale(" + scale + ")";
    }

    function fitToView() {
      var svg = content.querySelector("svg");
      var rect;
      var nextScale;

      if (!svg) {
        setScale(1);
        return;
      }

      rect = svg.getBoundingClientRect();
      nextScale = Math.min(
        (stage.clientWidth - 32) / Math.max(rect.width / scale, 1),
        (stage.clientHeight - 32) / Math.max(rect.height / scale, 1),
        1.5
      );

      setScale(nextScale);
      stage.scrollLeft = 0;
      stage.scrollTop = 0;
    }

    zoomOut.addEventListener("click", function () {
      setScale(scale / 1.25);
    });

    zoomIn.addEventListener("click", function () {
      setScale(scale * 1.25);
    });

    fit.addEventListener("click", fitToView);

    reset.addEventListener("click", function () {
      setScale(1);
    });

    close.addEventListener("click", function () {
      closeOverlay(overlay);
    });

    overlay.addEventListener("click", function (event) {
      if (event.target === overlay) {
        closeOverlay(overlay);
      }
    });

    document.addEventListener("keydown", function onKeydown(event) {
      if (event.key === "Escape") {
        closeOverlay(overlay);
        document.removeEventListener("keydown", onKeydown);
      }
    });

    toolbar.appendChild(zoomOut);
    toolbar.appendChild(zoomIn);
    toolbar.appendChild(fit);
    toolbar.appendChild(reset);
    toolbar.appendChild(close);
    stage.appendChild(content);
    dialog.appendChild(toolbar);
    dialog.appendChild(stage);
    overlay.appendChild(dialog);
    document.body.appendChild(overlay);
    close.focus();

    renderSource(content, diagramSource, true)
      .then(function () {
        requestAnimationFrame(fitToView);
      })
      .catch(function () {
        content.replaceWith(fallbackCodeBlock(diagramSource));
      });
  }

  document.addEventListener("click", function (event) {
    var source = event.target.closest
      ? event.target.closest(".mermaid-rendered")
      : null;

    if (
      !source ||
      source.classList.contains("mermaid-render-error") ||
      source.closest(".mermaid-zoom-overlay")
    ) {
      return;
    }

    event.preventDefault();
    openOverlay(source);
  });

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", renderAll);
  } else {
    renderAll();
  }

  if (window.document$ && window.document$.subscribe) {
    window.document$.subscribe(renderAll);
  }
})();
