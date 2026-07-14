(function () {
  var mermaidLoad = null;
  var mermaidReady = false;
  var renderId = 0;
  var highlightId = 0;

  var EDGE_HOVER_MARGIN_PX = 8;
  var BOX_HOVER_MARGIN_PX = 5;
  var NODE_HOVER_MARGIN_PX = 4;

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
        flowchart: {
          defaultRenderer: "elk",
          nodeSpacing: 90,
          rankSpacing: 110,
          diagramPadding: 24,
          curve: "basis",
          htmlLabels: true,
          wrappingWidth: 180
        },
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

  function toArray(list) {
    return Array.prototype.slice.call(list || []);
  }

  function configureButton(button, label, ariaLabel) {
    button.className = "mermaid-zoom-button";
    button.type = "button";
    button.textContent = label;
    button.setAttribute("aria-label", ariaLabel);
  }

  function setToggleButton(button, enabled) {
    button.setAttribute("aria-pressed", enabled ? "true" : "false");
    button.classList.toggle("mermaid-zoom-button-active", enabled);
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

  function closestMatch(element, selector, stopAt) {
    var current = element;

    while (current && current !== stopAt) {
      if (current.matches && current.matches(selector)) {
        return current;
      }
      current = current.parentNode;
    }

    return null;
  }

  function getEdgePath(edge) {
    if (!edge) {
      return null;
    }

    if (edge.matches && edge.matches("path")) {
      return edge;
    }

    return edge.querySelector ? edge.querySelector("path") : null;
  }

  function getElementKey(element) {
    if (!element) {
      return "";
    }

    if (!element.__mermaidHighlightId) {
      highlightId++;
      element.__mermaidHighlightId = "mhi-" + highlightId;
    }

    return element.__mermaidHighlightId;
  }

  function getBoxCenter(element, svg) {
    var rect;
    var point;
    var matrix;
    var box;

    if (svg && element.getBoundingClientRect && svg.createSVGPoint) {
      rect = element.getBoundingClientRect();
      matrix = svg.getScreenCTM();
      if (matrix && rect.width > 0 && rect.height > 0) {
        point = svg.createSVGPoint();
        point.x = rect.left + rect.width / 2;
        point.y = rect.top + rect.height / 2;
        return point.matrixTransform(matrix.inverse());
      }
    }

    try {
      box = element.getBBox();
      return {
        x: box.x + box.width / 2,
        y: box.y + box.height / 2
      };
    } catch (error) {
      return null;
    }
  }

  function isUsableEdgeLabel(label) {
    var text = label.textContent ? label.textContent.trim() : "";
    var rect = label.getBoundingClientRect
      ? label.getBoundingClientRect()
      : null;

    return !!text && !!rect && rect.width > 0 && rect.height > 0;
  }

  function dedupeLabels(labels) {
    var seen = {};
    var result = [];

    labels.forEach(function (label) {
      var rect;
      var key;

      if (!isUsableEdgeLabel(label)) {
        return;
      }

      rect = label.getBoundingClientRect();
      key = [
        label.textContent.trim(),
        Math.round(rect.left),
        Math.round(rect.top),
        Math.round(rect.width),
        Math.round(rect.height)
      ].join("|");

      if (seen[key]) {
        return;
      }

      seen[key] = true;
      result.push(label);
    });

    return result;
  }

  function getPathEndpoints(path) {
    var length;

    if (!path || !path.getTotalLength || !path.getPointAtLength) {
      return null;
    }

    try {
      length = path.getTotalLength();
      return {
        start: path.getPointAtLength(0),
        end: path.getPointAtLength(length)
      };
    } catch (error) {
      return null;
    }
  }

  function getPathDistanceToPoint(path, point) {
    var length;
    var best = null;
    var sampleCount = 24;
    var index;
    var pathPoint;
    var dx;
    var dy;
    var distance;

    if (!path || !point || !path.getTotalLength || !path.getPointAtLength) {
      return null;
    }

    try {
      length = path.getTotalLength();
      for (index = 0; index <= sampleCount; index++) {
        pathPoint = path.getPointAtLength((length * index) / sampleCount);
        dx = pathPoint.x - point.x;
        dy = pathPoint.y - point.y;
        distance = dx * dx + dy * dy;
        if (best === null || distance < best) {
          best = distance;
        }
      }
      return best;
    } catch (error) {
      return null;
    }
  }

  function elementPointToClient(element, x, y) {
    var svg = element.ownerSVGElement || element;
    var matrix = element.getScreenCTM ? element.getScreenCTM() : null;
    var point;

    if (!svg || !svg.createSVGPoint || !matrix) {
      return null;
    }

    point = svg.createSVGPoint();
    point.x = x;
    point.y = y;

    return point.matrixTransform(matrix);
  }

  function getPathDistanceToEvent(path, event) {
    var length;
    var best = null;
    var sampleCount;
    var index;
    var pathPoint;
    var clientPoint;
    var dx;
    var dy;
    var distance;

    if (!path || !path.getTotalLength || !path.getPointAtLength) {
      return null;
    }

    try {
      length = path.getTotalLength();
      sampleCount = Math.max(24, Math.min(96, Math.ceil(length / 18)));

      for (index = 0; index <= sampleCount; index++) {
        pathPoint = path.getPointAtLength((length * index) / sampleCount);
        clientPoint = elementPointToClient(path, pathPoint.x, pathPoint.y);
        if (!clientPoint) {
          return null;
        }

        dx = clientPoint.x - event.clientX;
        dy = clientPoint.y - event.clientY;
        distance = dx * dx + dy * dy;
        if (best === null || distance < best) {
          best = distance;
        }
      }

      return best;
    } catch (error) {
      return null;
    }
  }

  function getLineDistanceToEvent(line, event) {
    var x1;
    var y1;
    var x2;
    var y2;
    var start;
    var end;
    var dx;
    var dy;
    var lengthSquared;
    var ratio;
    var nearestX;
    var nearestY;
    var diffX;
    var diffY;

    if (!line || !line.getAttribute) {
      return null;
    }

    x1 = parseFloat(line.getAttribute("x1") || "0");
    y1 = parseFloat(line.getAttribute("y1") || "0");
    x2 = parseFloat(line.getAttribute("x2") || "0");
    y2 = parseFloat(line.getAttribute("y2") || "0");
    start = elementPointToClient(line, x1, y1);
    end = elementPointToClient(line, x2, y2);

    if (!start || !end) {
      return null;
    }

    dx = end.x - start.x;
    dy = end.y - start.y;
    lengthSquared = dx * dx + dy * dy;

    if (!lengthSquared) {
      diffX = event.clientX - start.x;
      diffY = event.clientY - start.y;
      return diffX * diffX + diffY * diffY;
    }

    ratio =
      ((event.clientX - start.x) * dx + (event.clientY - start.y) * dy) /
      lengthSquared;
    ratio = Math.max(0, Math.min(1, ratio));
    nearestX = start.x + ratio * dx;
    nearestY = start.y + ratio * dy;
    diffX = event.clientX - nearestX;
    diffY = event.clientY - nearestY;

    return diffX * diffX + diffY * diffY;
  }

  function getRectDistanceToEvent(rect, event) {
    var dx = 0;
    var dy = 0;

    if (event.clientX < rect.left) {
      dx = rect.left - event.clientX;
    } else if (event.clientX > rect.right) {
      dx = event.clientX - rect.right;
    }

    if (event.clientY < rect.top) {
      dy = rect.top - event.clientY;
    } else if (event.clientY > rect.bottom) {
      dy = event.clientY - rect.bottom;
    }

    return dx * dx + dy * dy;
  }

  function paddedContains(box, point, padding) {
    return (
      point.x >= box.x - padding &&
      point.x <= box.x + box.width + padding &&
      point.y >= box.y - padding &&
      point.y <= box.y + box.height + padding
    );
  }

  function rectContainsEvent(rect, event, padding) {
    return (
      event.clientX >= rect.left - padding &&
      event.clientX <= rect.right + padding &&
      event.clientY >= rect.top - padding &&
      event.clientY <= rect.bottom + padding
    );
  }

  function getDiagramParts(svg) {
    var nodes = toArray(svg.querySelectorAll("g.node, .node"));
    var edges = toArray(svg.querySelectorAll("g.edgePath, .edgePath"));
    var labels = dedupeLabels(
      toArray(svg.querySelectorAll("g.edgeLabel, .edgeLabel"))
    );
    var pairs = [];
    var usedEdges = [];

    if (!edges.length) {
      edges = toArray(
        svg.querySelectorAll("path.flowchart-link, path.transition")
      );
    }

    edges.forEach(function (edge) {
      pairs.push({
        edge: edge,
        label: null
      });
    });

    labels.forEach(function (label) {
      var center = getBoxCenter(label, svg);
      var bestPair = null;
      var bestDistance = null;

      pairs.forEach(function (pair) {
        var distance;

        if (usedEdges.indexOf(pair.edge) !== -1) {
          return;
        }

        distance = getPathDistanceToPoint(getEdgePath(pair.edge), center);
        if (distance === null) {
          return;
        }

        if (bestDistance === null || distance < bestDistance) {
          bestPair = pair;
          bestDistance = distance;
        }
      });

      if (bestPair) {
        bestPair.label = label;
        usedEdges.push(bestPair.edge);
      }
    });

    return {
      labels: labels,
      nodes: nodes,
      pairs: pairs,
      svg: svg
    };
  }

  function findNearestPairForLabel(parts, label) {
    var center = getBoxCenter(label, parts.svg);
    var nearest = null;
    var nearestDistance = null;

    parts.pairs.forEach(function (pair) {
      var distance = getPathDistanceToPoint(getEdgePath(pair.edge), center);

      if (distance === null) {
        return;
      }

      if (nearestDistance === null || distance < nearestDistance) {
        nearest = {
          edge: pair.edge,
          label: label
        };
        nearestDistance = distance;
      }
    });

    return nearest;
  }

  function findLabelAtEvent(parts, event) {
    var candidates = [];

    parts.labels.forEach(function (label) {
      var rect;
      var dx;
      var dy;

      if (!label.getBoundingClientRect) {
        return;
      }

      rect = label.getBoundingClientRect();
      if (
        !rect.width ||
        !rect.height ||
        !rectContainsEvent(rect, event, BOX_HOVER_MARGIN_PX)
      ) {
        return;
      }

      dx = rect.left + rect.width / 2 - event.clientX;
      dy = rect.top + rect.height / 2 - event.clientY;
      candidates.push({
        distance: dx * dx + dy * dy,
        label: label
      });
    });

    candidates.sort(function (a, b) {
      return a.distance - b.distance;
    });

    return candidates.length ? candidates[0].label : null;
  }

  function findPairAtEvent(parts, event) {
    var edge = null;
    var label;
    var bestDistance = null;

    label = findLabelAtEvent(parts, event);

    if (label) {
      return (
        parts.pairs.find(function (pair) {
          return pair.label === label;
        }) || findNearestPairForLabel(parts, label)
      );
    }

    parts.pairs.forEach(function (pair) {
      var distance = getPathDistanceToEvent(getEdgePath(pair.edge), event);

      if (
        distance === null ||
        distance > EDGE_HOVER_MARGIN_PX * EDGE_HOVER_MARGIN_PX
      ) {
        return;
      }

      if (bestDistance === null || distance < bestDistance) {
        edge = pair;
        bestDistance = distance;
      }
    });

    if (edge) {
      return edge;
    }

    return null;
  }

  function findNodeAtEvent(parts, event) {
    var candidates = [];

    parts.nodes.forEach(function (node) {
      var rect;
      var area;
      var distance;

      if (!node.getBoundingClientRect) {
        return;
      }

      rect = node.getBoundingClientRect();
      if (
        !rect.width ||
        !rect.height ||
        !rectContainsEvent(rect, event, NODE_HOVER_MARGIN_PX)
      ) {
        return;
      }

      area = rect.width * rect.height;
      distance = getRectDistanceToEvent(rect, event);
      candidates.push({
        area: area,
        distance: distance,
        node: node
      });
    });

    candidates.sort(function (a, b) {
      if (a.distance !== b.distance) {
        return a.distance - b.distance;
      }

      return a.area - b.area;
    });

    return candidates.length ? candidates[0].node : null;
  }

  function findConnectedNodes(pair, nodes) {
    var path = getEdgePath(pair.edge);
    var endpoints = getPathEndpoints(path);
    var connected = [];

    if (!endpoints) {
      return connected;
    }

    nodes.forEach(function (node) {
      var box;

      try {
        box = node.getBBox();
      } catch (error) {
        return;
      }

      if (
        paddedContains(box, endpoints.start, 20) ||
        paddedContains(box, endpoints.end, 20)
      ) {
        connected.push(node);
      }
    });

    return connected;
  }

  function clearClasses(parts) {
    parts.nodes.concat(parts.labels).forEach(function (element) {
      element.classList.remove(
        "mermaid-dimmed",
        "mermaid-selected",
        "mermaid-connected"
      );
    });

    parts.pairs.forEach(function (pair) {
      pair.edge.classList.remove(
        "mermaid-dimmed",
        "mermaid-selected",
        "mermaid-connected"
      );
    });
  }

  function clearElementClasses(elements) {
    elements.forEach(function (element) {
      element.classList.remove(
        "mermaid-dimmed",
        "mermaid-selected",
        "mermaid-connected"
      );
    });
  }

  function isDecorativeElement(element) {
    var className = element.getAttribute
      ? element.getAttribute("class") || ""
      : "";

    if (closestMatch(element, "defs, marker", null)) {
      return true;
    }

    return (
      /\barrowMarkerPath\b/.test(className) ||
      /\blabelBkg\b/.test(className) ||
      /\broot\b/.test(className) ||
      /\bclusters\b/.test(className) ||
      /\bedgePaths\b/.test(className) ||
      /\bedgeLabels\b/.test(className) ||
      /\bnodes\b/.test(className)
    );
  }

  function normalizeGenericCandidate(element, svg) {
    var label;
    var node;
    var edge;

    if (!element || element === svg || isDecorativeElement(element)) {
      return null;
    }

    label = closestMatch(element, "g.edgeLabel, .edgeLabel", svg);
    if (label && isUsableEdgeLabel(label)) {
      return label;
    }

    node = closestMatch(element, "g.node, .node", svg);
    if (node && !isDecorativeElement(node)) {
      return node;
    }

    edge = closestMatch(
      element,
      "g.edgePath, .edgePath, path.flowchart-link, path.transition",
      svg
    );
    if (edge && !isDecorativeElement(edge)) {
      return edge;
    }

    if (
      element.matches &&
      element.matches(
        [
          "circle.state-start",
          "line.actor-line",
          "rect.actor",
          "text.actor",
          "line.messageLine0",
          "line.messageLine1",
          "line.messageLine",
          "text.messageText",
          "rect.note",
          "text.noteText",
          "text.loopText",
          "rect.loopLine",
          "line.loopLine",
          "path.loopLine"
        ].join(", ")
      )
    ) {
      return element;
    }

    return null;
  }

  function getGenericCandidates(svg) {
    var selector = [
      "g.node",
      ".node",
      "g.edgeLabel",
      ".edgeLabel",
      "g.edgePath",
      ".edgePath",
      "path.flowchart-link",
      "path.transition",
      "circle.state-start",
      "line.actor-line",
      "rect.actor",
      "text.actor",
      "line.messageLine0",
      "line.messageLine1",
      "line.messageLine",
      "text.messageText",
      "rect.note",
      "text.noteText",
      "text.loopText",
      "rect.loopLine",
      "line.loopLine",
      "path.loopLine"
    ].join(", ");
    var seen = {};
    var candidates = [];

    toArray(svg.querySelectorAll(selector)).forEach(function (element) {
      var candidate = normalizeGenericCandidate(element, svg);
      var key;

      if (!candidate) {
        return;
      }

      key = getElementKey(candidate);
      if (seen[key]) {
        return;
      }

      seen[key] = true;
      candidates.push(candidate);
    });

    return candidates;
  }

  function getHighlightElements(svg) {
    var parts = getDiagramParts(svg);
    var seen = {};
    var elements = [];

    function add(element) {
      var key;

      if (!element) {
        return;
      }

      key = getElementKey(element);
      if (seen[key]) {
        return;
      }

      seen[key] = true;
      elements.push(element);
    }

    parts.nodes.forEach(add);
    parts.labels.forEach(add);
    parts.pairs.forEach(function (pair) {
      add(pair.edge);
      add(pair.label);
    });
    getGenericCandidates(svg).forEach(add);

    return elements;
  }

  function dimAll(parts) {
    parts.nodes.concat(parts.labels).forEach(function (element) {
      element.classList.add("mermaid-dimmed");
    });

    parts.pairs.forEach(function (pair) {
      pair.edge.classList.add("mermaid-dimmed");
    });
  }

  function markActive(element, className) {
    if (!element) {
      return;
    }

    element.classList.remove("mermaid-dimmed");
    element.classList.add(className);
  }

  function scoreGenericCandidate(element, event) {
    var tagName = element.tagName ? element.tagName.toLowerCase() : "";
    var distance = null;
    var margin = BOX_HOVER_MARGIN_PX;
    var rect;
    var area = 0;
    var priority = 3;

    if (tagName === "path") {
      distance = getPathDistanceToEvent(element, event);
      margin = EDGE_HOVER_MARGIN_PX;
      priority = 1;
    } else if (tagName === "line") {
      distance = getLineDistanceToEvent(element, event);
      margin = EDGE_HOVER_MARGIN_PX;
      priority = 1;
    } else if (element.matches && element.matches("g.edgePath, .edgePath")) {
      distance = getPathDistanceToEvent(getEdgePath(element), event);
      margin = EDGE_HOVER_MARGIN_PX;
      priority = 1;
    } else {
      if (!element.getBoundingClientRect) {
        return null;
      }

      rect = element.getBoundingClientRect();
      if (!rect.width || !rect.height) {
        return null;
      }

      distance = getRectDistanceToEvent(rect, event);
      area = rect.width * rect.height;
      priority = tagName === "text" ? 0 : 2;
    }

    if (distance === null || distance > margin * margin) {
      return null;
    }

    return {
      area: area,
      distance: distance,
      element: element,
      priority: priority
    };
  }

  function findGenericAtEvent(svg, event) {
    var scored = [];

    getGenericCandidates(svg).forEach(function (element) {
      var score = scoreGenericCandidate(element, event);

      if (score) {
        scored.push(score);
      }
    });

    scored.sort(function (a, b) {
      if (a.distance !== b.distance) {
        return a.distance - b.distance;
      }

      if (a.priority !== b.priority) {
        return a.priority - b.priority;
      }

      return a.area - b.area;
    });

    return scored.length ? scored[0].element : null;
  }

  function findNearestRectElement(svg, target, selector, maxDistance) {
    var targetRect = target.getBoundingClientRect
      ? target.getBoundingClientRect()
      : null;
    var targetX;
    var targetY;
    var best = null;
    var bestDistance = null;

    if (!targetRect || !targetRect.width || !targetRect.height) {
      return null;
    }

    targetX = targetRect.left + targetRect.width / 2;
    targetY = targetRect.top + targetRect.height / 2;

    toArray(svg.querySelectorAll(selector)).forEach(function (element) {
      var rect;
      var centerX;
      var centerY;
      var dx;
      var dy;
      var distance;

      if (element === target || !element.getBoundingClientRect) {
        return;
      }

      rect = element.getBoundingClientRect();
      if (!rect.width && !rect.height) {
        return;
      }

      centerX = rect.left + rect.width / 2;
      centerY = rect.top + rect.height / 2;
      dx = centerX - targetX;
      dy = centerY - targetY;
      distance = dx * dx + dy * dy;

      if (distance > maxDistance * maxDistance) {
        return;
      }

      if (bestDistance === null || distance < bestDistance) {
        best = element;
        bestDistance = distance;
      }
    });

    return best;
  }

  function findGenericCompanions(svg, target) {
    var companions = [];
    var nearest;

    if (!target.matches) {
      return companions;
    }

    if (target.matches("text.messageText")) {
      nearest = findNearestRectElement(
        svg,
        target,
        "line.messageLine0, line.messageLine1, line.messageLine",
        34
      );
      if (nearest) {
        companions.push(nearest);
      }
    } else if (
      target.matches("line.messageLine0, line.messageLine1, line.messageLine")
    ) {
      nearest = findNearestRectElement(svg, target, "text.messageText", 34);
      if (nearest) {
        companions.push(nearest);
      }
    } else if (target.matches("text.actor")) {
      nearest = findNearestRectElement(svg, target, "rect.actor", 28);
      if (nearest) {
        companions.push(nearest);
      }
    } else if (target.matches("rect.actor")) {
      nearest = findNearestRectElement(svg, target, "text.actor", 28);
      if (nearest) {
        companions.push(nearest);
      }
    }

    return companions;
  }

  function selectGeneric(svg, target) {
    var candidates = getGenericCandidates(svg);

    clearElementClasses(getHighlightElements(svg));
    candidates.forEach(function (element) {
      element.classList.add("mermaid-dimmed");
    });

    markActive(target, "mermaid-selected");
    findGenericCompanions(svg, target).forEach(function (companion) {
      markActive(companion, "mermaid-connected");
    });
  }

  function selectPair(svg, pair) {
    var parts = getDiagramParts(svg);
    var connectedNodes = findConnectedNodes(pair, parts.nodes);

    clearElementClasses(getHighlightElements(svg));
    dimAll(parts);
    markActive(pair.edge, "mermaid-selected");
    markActive(pair.label, "mermaid-selected");

    connectedNodes.forEach(function (node) {
      markActive(node, "mermaid-connected");
    });
  }

  function selectNode(svg, node) {
    var parts = getDiagramParts(svg);
    var nodeBox;

    try {
      nodeBox = node.getBBox();
    } catch (error) {
      return;
    }

    clearElementClasses(getHighlightElements(svg));
    dimAll(parts);
    markActive(node, "mermaid-selected");

    parts.pairs.forEach(function (pair) {
      var path = getEdgePath(pair.edge);
      var endpoints = getPathEndpoints(path);
      var connectedNodes;

      if (
        !endpoints ||
        (!paddedContains(nodeBox, endpoints.start, 20) &&
          !paddedContains(nodeBox, endpoints.end, 20))
      ) {
        return;
      }

      markActive(pair.edge, "mermaid-connected");
      markActive(pair.label, "mermaid-connected");
      connectedNodes = findConnectedNodes(pair, parts.nodes);
      connectedNodes.forEach(function (connectedNode) {
        markActive(connectedNode, "mermaid-connected");
      });
    });
  }

  function initDiagramInteraction(root, enabledByDefault) {
    var svg = root.querySelector("svg");
    var state = {
      activeKey: "",
      enabled: !!enabledByDefault
    };

    if (!svg || root.__mermaidInteraction) {
      return;
    }

    function clearSelection() {
      clearElementClasses(getHighlightElements(svg));
      state.activeKey = "";
    }

    function setEnabled(enabled) {
      state.enabled = !!enabled;
      root.classList.toggle("mermaid-highlight-enabled", state.enabled);

      if (!state.enabled) {
        clearSelection();
      }
    }

    root.addEventListener("mousemove", function (event) {
      var parts;
      var pair;
      var node;
      var generic;
      var nextKey;

      if (!state.enabled) {
        return;
      }

      parts = getDiagramParts(svg);
      node = findNodeAtEvent(parts, event);
      if (node && root.contains(node)) {
        nextKey = "node:" + getElementKey(node);
        if (nextKey !== state.activeKey) {
          state.activeKey = nextKey;
          selectNode(svg, node);
        }
        return;
      }

      pair = findPairAtEvent(parts, event);
      if (pair) {
        nextKey =
          "pair:" +
          getElementKey(pair.edge) +
          ":" +
          getElementKey(pair.label);
        if (nextKey !== state.activeKey) {
          state.activeKey = nextKey;
          selectPair(svg, pair);
        }
        return;
      }

      generic = findGenericAtEvent(svg, event);
      if (generic && root.contains(generic)) {
        nextKey = "generic:" + getElementKey(generic);
        if (nextKey !== state.activeKey) {
          state.activeKey = nextKey;
          selectGeneric(svg, generic);
        }
        return;
      }

      if (state.activeKey) {
        clearSelection();
      }
    });

    root.addEventListener("mouseleave", function () {
      if (state.enabled) {
        clearSelection();
      }
    });

    root.__mermaidInteraction = {
      clear: clearSelection,
      setEnabled: setEnabled
    };

    setEnabled(state.enabled);
  }

  function renderSource(target, source, zoomed, enabledByDefault) {
    return loadMermaid()
      .then(initMermaid)
      .then(function (mermaid) {
        return mermaid.render("mermaid_" + renderId++, source);
      })
      .then(function (result) {
        target.innerHTML = result.svg;
        if (zoomed) {
          target.classList.add("mermaid-zoom-content");
        }
        if (result.bindFunctions) {
          result.bindFunctions(target);
        }
        initDiagramInteraction(target, enabledByDefault);
      });
  }

  function renderBlock(block) {
    var source = getSource(block);
    var wrapper = document.createElement("div");
    var toolbar = document.createElement("div");
    var expand = document.createElement("button");
    var highlight = document.createElement("button");
    var diagram = document.createElement("div");
    var highlightEnabled = false;

    wrapper.className = "mermaid-rendered";
    toolbar.className = "mermaid-inline-toolbar";
    diagram.className = "mermaid-diagram-body";
    diagram.textContent = "Rendering diagram...";
    wrapper.__mermaidSource = source;

    configureButton(expand, "Expand", "Open expanded diagram");
    configureButton(highlight, "Highlight", "Enable diagram highlight view");
    setToggleButton(highlight, false);

    expand.addEventListener("click", function () {
      openOverlay(wrapper);
    });

    highlight.addEventListener("click", function () {
      highlightEnabled = !highlightEnabled;
      setToggleButton(highlight, highlightEnabled);
      if (diagram.__mermaidInteraction) {
        diagram.__mermaidInteraction.setEnabled(highlightEnabled);
      }
    });

    toolbar.appendChild(expand);
    toolbar.appendChild(highlight);
    wrapper.appendChild(toolbar);
    wrapper.appendChild(diagram);
    block.replaceWith(wrapper);

    renderSource(diagram, source, false, false).catch(function () {
      wrapper.replaceWith(fallbackCodeBlock(source));
    });
  }

  function renderAll() {
    toArray(document.querySelectorAll("pre.mermaid-source")).forEach(renderBlock);
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
    var highlight = document.createElement("button");
    var close = document.createElement("button");
    var content = document.createElement("div");
    var diagramSource = source.__mermaidSource;
    var scale = 1;
    var highlightEnabled = true;

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
    content.className = "mermaid-zoom-content";
    content.textContent = "Rendering diagram...";

    configureButton(zoomOut, "-", "Zoom out");
    configureButton(zoomIn, "+", "Zoom in");
    configureButton(fit, "Fit", "Fit diagram to view");
    configureButton(reset, "100%", "Reset zoom");
    configureButton(highlight, "Highlight", "Toggle diagram highlight view");
    configureButton(close, "x", "Close expanded diagram");
    setToggleButton(highlight, highlightEnabled);
    close.classList.add("mermaid-zoom-close");

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

    highlight.addEventListener("click", function () {
      highlightEnabled = !highlightEnabled;
      setToggleButton(highlight, highlightEnabled);
      if (content.__mermaidInteraction) {
        content.__mermaidInteraction.setEnabled(highlightEnabled);
      }
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
    toolbar.appendChild(highlight);
    toolbar.appendChild(close);
    stage.appendChild(content);
    dialog.appendChild(toolbar);
    dialog.appendChild(stage);
    overlay.appendChild(dialog);
    document.body.appendChild(overlay);
    close.focus();

    renderSource(content, diagramSource, true, highlightEnabled)
      .then(function () {
        if (content.__mermaidInteraction) {
          content.__mermaidInteraction.setEnabled(highlightEnabled);
        }
        requestAnimationFrame(fitToView);
      })
      .catch(function () {
        content.replaceWith(fallbackCodeBlock(diagramSource));
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", renderAll);
  } else {
    renderAll();
  }

  if (window.document$ && window.document$.subscribe) {
    window.document$.subscribe(renderAll);
  }
})();
