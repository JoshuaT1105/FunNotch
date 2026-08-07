/*
  Everything on this page that moves.

  Each demo is a real notch: shut by default, open on hover, focus or tap, and
  opened once on its own when it first scrolls into view so nobody has to guess
  that it does anything. The breakout panel is actually playable.
*/

(function () {
  "use strict";

  var calm = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // --- Header hairline ---------------------------------------------------
  var header = document.getElementById("site-header");
  if (header) {
    var onScroll = function () {
      header.classList.toggle("scrolled", window.scrollY > 8);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
  }

  // --- Download counter --------------------------------------------------
  //
  // The number is on the page for everyone, not hidden until it is flattering.
  //
  //   GITHUB_REPO  "owner/repo". Counts real completed downloads of every
  //                release asset, straight from GitHub's public API. Needs no
  //                backend and cannot be inflated by reloading this page, so it
  //                wins where both are set.
  //
  //   COUNTER_API  URL of a counter endpoint that answers `{ "total": N }` to
  //                GET and increments on POST. Counts button clicks, which is a
  //                looser thing to measure.
  var GITHUB_REPO = "JoshuaT1105/FunNotch";
  var COUNTER_API = "";

  (function () {
    var out = document.querySelector("[data-dl-total]");
    if (!out || (!GITHUB_REPO && !COUNTER_API)) return;

    var shown = null;
    out.classList.add("pending");

    // Zero is a real answer and gets shown as one. Only a failed or nonsense
    // response leaves the em-dash, so "we don't know" and "nobody yet" stay
    // visibly different.
    function render(total) {
      if (typeof total !== "number" || !isFinite(total) || total < 0) return;
      shown = Math.floor(total);
      out.textContent = shown.toLocaleString();
      out.classList.remove("pending");
    }

    // Every asset of every release added together, so old versions still count
    // and adding a second asset later does not reset the number.
    function fromGitHub() {
      return fetch("https://api.github.com/repos/" + GITHUB_REPO + "/releases", {
        headers: { Accept: "application/vnd.github+json" }
      })
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (releases) {
          if (!Array.isArray(releases)) return;
          var total = 0;
          releases.forEach(function (release) {
            (release.assets || []).forEach(function (asset) {
              total += asset.download_count || 0;
            });
          });
          render(total);
        });
    }

    function fromAPI(method) {
      return fetch(COUNTER_API, {
        method: method,
        // The total is public and the endpoint takes no credentials, so there
        // is nothing here that wants a cookie attached to it.
        credentials: "omit",
        cache: "no-store",
        keepalive: method === "POST"
      })
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (data) { if (data) render(data.total); });
    }

    // A counter is decoration. Anything that goes wrong with it leaves the
    // element hidden and is otherwise none of the visitor's business.
    function quietly(work) {
      try {
        var result = work();
        if (result && result.catch) result.catch(function () {});
      } catch (error) { /* ignored on purpose */ }
    }

    quietly(GITHUB_REPO ? fromGitHub : function () { return fromAPI("GET"); });

    // Counting the click rather than the byte: a static host can't tell us
    // when a file finished transferring. The link keeps its default behaviour
    // regardless, so a dead counter never costs anyone their download.
    if (COUNTER_API && !GITHUB_REPO) {
      Array.prototype.forEach.call(
        document.querySelectorAll("[data-download]"),
        function (link) {
          link.addEventListener("click", function () {
            // Move the number now and let the response correct it, so the
            // click visibly did something even on a slow connection.
            if (shown !== null) render(shown + 1);
            quietly(function () { return fromAPI("POST"); });
          });
        }
      );
    }
  })();

  // --- Opening and closing a panel --------------------------------------
  var screens = document.querySelectorAll("[data-demo]");

  Array.prototype.forEach.call(screens, function (screen) {
    var notch = screen.querySelector(".notch");
    if (!notch) return;

    var hint = screen.parentElement.querySelector(".stage-hint");
    var open = function () {
      notch.classList.add("open");
      screen.classList.add("is-open");
      if (hint) hint.style.opacity = "0";

    };
    var close = function () {
      notch.classList.remove("open");
      screen.classList.remove("is-open");
      if (hint) hint.style.opacity = "";
    };

    notch.addEventListener("mouseenter", open);
    screen.addEventListener("mouseleave", close);
    notch.addEventListener("focus", open);
    notch.addEventListener("blur", close);
    notch.addEventListener("click", function () {
      if (notch.classList.contains("open")) close();
      else open();
    });
    notch.addEventListener("keydown", function (event) {
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
      if (notch.classList.contains("open")) close();
      else open();
    });

    screen.__open = open;
    screen.__close = close;
  });

  // Show each one once, the first time it is scrolled past.
  if ("IntersectionObserver" in window && !calm) {
    var seen = new WeakSet();
    var peek = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting || seen.has(entry.target)) return;
          seen.add(entry.target);
          var screen = entry.target;
          window.setTimeout(function () {
            if (screen.matches(":hover")) return;
            screen.__open();
            window.setTimeout(function () {
              if (!screen.matches(":hover")) screen.__close();
            }, 3200);
          }, 350);
        });
      },
      { threshold: 0.5 }
    );
    Array.prototype.forEach.call(screens, function (s) {
      if (!s.hasAttribute("data-drop")) peek.observe(s);
    });
  }

  // --- The music panel's progress bar creeps forward ---------------------
  var progress = document.querySelector("[data-progress]");
  var elapsed = document.querySelector("[data-elapsed]");
  var remaining = document.querySelector("[data-remaining]");

  function clock(t) {
    var m = Math.floor(t / 60);
    var s = Math.floor(t % 60);
    return m + ":" + (s < 10 ? "0" : "") + s;
  }
  if (progress && !calm) {
    var seconds = 9;
    var total = 274;
    window.setInterval(function () {
      seconds = (seconds + 1) % total;
      progress.style.width = ((seconds / total) * 100).toFixed(2) + "%";
      if (elapsed) elapsed.textContent = clock(seconds);
      // The app shows time remaining on the right, not the track length.
      if (remaining) remaining.textContent = clock(total - seconds);
    }, 1000);
    progress.style.width = ((seconds / total) * 100).toFixed(2) + "%";
  }

  // --- Widget panel cycles through the three layout choices -------------
  //
  // All three happen inside the panel, which is what the app does: it widens
  // to hold whatever is on show rather than putting anything on the wallpaper.
  var widgetScreen = document.querySelector("[data-widgets]");
  if (widgetScreen) {
    var modes = [
      { label: "Only the media", widgets: false, media: true, width: 236 },
      { label: "Media and widgets", widgets: true, media: true, width: 352 },
      { label: "Only widgets", widgets: true, media: false, width: 316 }
    ];
    var wNotch = widgetScreen.querySelector(".notch");
    var wgts = wNotch.querySelectorAll(".notch-closed .wgt");
    var media = wNotch.querySelectorAll(".notch-closed .art, .notch-closed .bars");
    var label = widgetScreen.querySelector(".mode-label");
    var index = 1;

    var applyMode = function () {
      var mode = modes[index];
      Array.prototype.forEach.call(wgts, function (el) {
        el.classList.toggle("gone", !mode.widgets);
      });
      Array.prototype.forEach.call(media, function (el) {
        el.classList.toggle("gone", !mode.media);
      });
      wNotch.style.width = mode.width + "px";
      label.textContent = mode.label;
    };

    applyMode();
    if (!calm) {
      window.setInterval(function () {
        index = (index + 1) % modes.length;
        applyMode();
      }, 2800);
    }
    widgetScreen.addEventListener("click", function () {
      index = (index + 1) % modes.length;
      applyMode();
    });
  }

  // --- The shelf plays out the sequence the app really has ---------------
  //
  // Three states, and the order matters:
  //   1. a file is picked up anywhere on screen — MouseTracker notices the drag
  //   2. `dragDetectorTargeting` turns the panel into a drop zone
  //   3. the drag crosses into it, `draggingEntered` fires, and the shelf opens
  //      the whole way while the file is still held
  // The panel opens *before* you let go, and that is the whole point of the
  // feature — so that is where this stops. Showing the item land afterwards
  // added nothing and put tiles outside the panel's outline.
  var shelf = document.querySelector("[data-drop]");
  if (shelf && !calm) {
    var shelfNotch = shelf.querySelector(".notch");
    var timers = [];

    function reset() {
      timers.forEach(clearTimeout);
      timers = [];
      shelf.classList.remove("dragging");
      shelfNotch.classList.remove("dropping", "open");
      shelf.classList.remove("is-open");
    }

    function at(ms, fn) { timers.push(setTimeout(fn, ms)); }

    function play() {
      reset();
      // 1. Picked up on the desktop. The carry animation runs 2.5s.
      shelf.classList.add("dragging");
      // 2. The panel notices and becomes a drop zone.
      at(320, function () { shelfNotch.classList.add("dropping"); });
      // 3. The drag reaches it: open the whole way, on the Shelf tab, empty and
      //    waiting — the file is still in the air at this point.
      at(1450, function () {
        shelfNotch.classList.remove("dropping");
        shelfNotch.classList.add("open");
        shelf.classList.add("is-open");
      });
      // Held open long enough to read, then it can run again.
      at(5200, reset);
    }

    shelf.__play = play;
    shelf.addEventListener("mouseenter", play);
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        if (entries[0].isIntersecting) play();
      }, { threshold: 0.55 }).observe(shelf);
    }
  }

  // --- Breakout ----------------------------------------------------------
  var gameScreen = document.querySelector("[data-game]");
  if (gameScreen) startBreakout(gameScreen);

  function startBreakout(screen) {
    var canvas = screen.querySelector(".board");
    var ctx = canvas.getContext("2d");

    var elLevel = screen.querySelector("[data-level]");
    var elLives = screen.querySelector("[data-lives]");
    var elScore = screen.querySelector("[data-score]");
    var elBest = screen.querySelector("[data-best]");

    // The canvas is sized from its own box every time that box changes. Fixing
    // the backing store to a constant while CSS displayed it at another width
    // squashed everything horizontally — which is why the paddle was an
    // invisible sliver.
    //
    // Resizing must not restart the run. The panel is 328px shut and ~475px
    // open, so every single hover changes the box — and the old code rebuilt
    // the board on any change, which meant the game reset itself the instant
    // you moved the pointer in to play it. Now the board is rescaled in place.
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var W = 0, H = 0;

    // Returns true only when there is no run to carry over, i.e. start one.
    function measure() {
      var r = canvas.getBoundingClientRect();
      if (r.width < 20 || r.height < 20) return false;
      if (Math.abs(r.width - W) < 1 && Math.abs(r.height - H) < 1) return false;
      var prevW = W, prevH = H;
      W = r.width; H = r.height;
      canvas.width = Math.round(W * dpr);
      canvas.height = Math.round(H * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      if (!prevW) return true;
      rescale(prevW, prevH);
      return false;
    }

    // Carries a run across a resize: everything keeps its relative place.
    function rescale(prevW, prevH) {
      var kx = W / prevW, ky = H / prevH;
      paddleX *= kx; targetX *= kx;
      balls.forEach(function (b) { b.x *= kx; b.y *= ky; });
      drops.forEach(function (d) { d.x *= kx; d.y *= ky; });
      sparks = [];
      layout();
    }

    var COLS = 14;
    var GAP = 3;
    var BRICK_H = 11;
    var TOP = 4;
    var R = 4;
    var PADDLE_H = 7;
    var MAX_BALLS = 16;
    // Every brick drops something, so with a board full of balls the drops can
    // arrive faster than they fall. A ceiling keeps it chaotic, not opaque.
    var MAX_DROPS = 18;
    function paddleY() { return H - 11; }

    // Wide paddle and slow ball. No extra lives — three is what you get.
    var KINDS = [
      { key: "wide", tint: "#4fd8e8", glyph: "\u2194" },
      { key: "multi", tint: "#ffd60a", glyph: "\u00d72" },
      { key: "slow", tint: "#63e6be", glyph: "\u25f7" }
    ];

    var bricks = [], balls = [], drops = [], sparks = [];
    var paddleX = 0, targetX = 0;
    var level = 1, score = 0, lives = 3, best = 0, wide = 0, slow = 0;
    var running = false, over = 0;

    function paddleW() { return Math.max(34, W * (wide > 0 ? 0.24 : 0.15)); }
    function speed() { return Math.min(240 + 22 * (level - 1), 430) * (slow > 0 ? 0.66 : 1); }

    // Brick geometry is derived from row and column, so it can be recomputed at
    // any width without disturbing which bricks are still standing.
    function layout() {
      var bw = (W - GAP * (COLS + 1)) / COLS;
      bricks.forEach(function (b) {
        b.x = GAP + b.col * (bw + GAP);
        b.y = TOP + b.row * (BRICK_H + GAP);
        b.w = bw;
      });
    }

    function build() {
      var rows = Math.min(3 + level, 6);
      bricks = [];
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < COLS; c++) {
          bricks.push({ x: 0, y: 0, w: 0, h: BRICK_H, row: r, col: c });
        }
      }
      layout();
      serve();
    }

    function serve() {
      var a = (-90 + (Math.random() * 40 - 20)) * (Math.PI / 180);
      balls = [{ x: paddleX, y: paddleY() - R - 3, vx: Math.cos(a) * speed(), vy: Math.sin(a) * speed() }];
    }

    function paint() {
      if (elLevel) elLevel.textContent = "L" + level;
      if (elScore) elScore.textContent = score;
      if (elBest) elBest.textContent = best;
      if (elLives) elLives.textContent = new Array(Math.max(lives, 0) + 1).join("\u2665");
    }

    function reset() {
      level = 1; score = 0; lives = 3; wide = 0; slow = 0;
      drops = []; sparks = []; over = 0;
      paddleX = W / 2; targetX = W / 2;
      best = Number(window.localStorage.getItem("fn-best") || 0);
      build();
      paint();
    }

    // Who is driving the paddle. Taken from real pointer events rather than the
    // :hover pseudo-class, which a pen, a touch screen or an assistive pointer
    // may never set — and which would leave the paddle on autopilot while
    // somebody was plainly trying to play.
    var pointerIn = false;

    screen.addEventListener("mousemove", function (event) {
      var box = canvas.getBoundingClientRect();
      if (!box.width) return;
      pointerIn = true;
      targetX = ((event.clientX - box.left) / box.width) * W;
    });
    screen.addEventListener("mouseenter", function () { pointerIn = true; });
    screen.addEventListener("mouseleave", function () { pointerIn = false; });

    function spark(x, y, tint, n) {
      for (var i = 0; i < n; i++) {
        sparks.push({
          x: x, y: y,
          vx: (Math.random() - 0.5) * 130,
          vy: Math.random() * -95 - 10,
          life: 0.22 + Math.random() * 0.28,
          tint: tint
        });
      }
    }

    function collect(kind) {
      if (kind.key === "wide") { wide = 11; return; }
      if (kind.key === "slow") { slow = 9; return; }
      // Doubles the whole board: every ball in play gets a twin, so two in a
      // row takes you 1 -> 2 -> 4.
      var twins = [];
      balls.forEach(function (b) {
        if (balls.length + twins.length >= MAX_BALLS) return;
        var a = Math.atan2(b.vy, b.vx) + Math.PI / 8;
        twins.push({ x: b.x, y: b.y, vx: Math.cos(a) * speed(), vy: Math.sin(a) * speed() });
      });
      balls = balls.concat(twins);
    }

    function step(dt) {
      // A run that ends restarts a beat later, so the board does not silently
      // blink back to level one under your pointer.
      if (over > 0) {
        over -= dt;
        if (over <= 0) reset();
        return;
      }

      wide = Math.max(wide - dt, 0);
      slow = Math.max(slow - dt, 0);

      if (!pointerIn) {
        var lead = balls[0] || { x: W / 2 };
        targetX = paddleX + (lead.x - paddleX) * Math.min(dt * 7, 1);
      }
      var half = paddleW() / 2;
      paddleX += (targetX - paddleX) * Math.min(dt * 15, 1);
      paddleX = Math.max(half, Math.min(W - half, paddleX));

      var sp = speed();
      var steps = Math.max(1, Math.ceil(sp * dt / R));
      var sub = dt / steps;
      var pTop = paddleY() - PADDLE_H / 2;

      for (var n = 0; n < steps; n++) {
        for (var i = balls.length - 1; i >= 0; i--) {
          var b = balls[i];
          var mag = Math.sqrt(b.vx * b.vx + b.vy * b.vy) || 1;
          var dy = b.vy / mag;
          if (Math.abs(dy) < 0.32) dy = dy < 0 ? -0.32 : 0.32;
          var dx = b.vx / mag;
          var norm = Math.sqrt(dx * dx + dy * dy);
          b.vx = dx / norm * sp; b.vy = dy / norm * sp;

          b.x += b.vx * sub; b.y += b.vy * sub;

          if (b.x < R) { b.x = R; b.vx = Math.abs(b.vx); }
          if (b.x > W - R) { b.x = W - R; b.vx = -Math.abs(b.vx); }
          if (b.y < R) { b.y = R; b.vy = Math.abs(b.vy); }

          if (b.vy > 0 && b.y + R >= pTop && b.y < pTop + PADDLE_H + 6) {
            var off = (b.x - paddleX) / half;
            if (Math.abs(off) <= 1.2) {
              var a = -Math.PI / 2 + Math.max(-1, Math.min(1, off)) * (Math.PI / 3);
              b.vx = Math.cos(a) * sp; b.vy = Math.sin(a) * sp;
              b.y = pTop - R;
            }
          }

          for (var k = 0; k < bricks.length; k++) {
            var br = bricks[k];
            if (b.x + R < br.x || b.x - R > br.x + br.w) continue;
            if (b.y + R < br.y || b.y - R > br.y + br.h) continue;
            var ox = Math.min(b.x + R - br.x, br.x + br.w - (b.x - R));
            var oy = Math.min(b.y + R - br.y, br.y + br.h - (b.y - R));
            if (ox < oy) b.vx = b.x < br.x + br.w / 2 ? -Math.abs(b.vx) : Math.abs(b.vx);
            else b.vy = b.y < br.y + br.h / 2 ? -Math.abs(b.vy) : Math.abs(b.vy);

            // Every brick drops something.
            if (drops.length < MAX_DROPS) {
              drops.push({
                x: br.x + br.w / 2, y: br.y + br.h / 2,
                kind: KINDS[(Math.random() * KINDS.length) | 0]
              });
            }
            spark(br.x + br.w / 2, br.y + br.h / 2, "hsl(" + (208 - br.row * 30) + ",62%,60%)", 6);
            bricks.splice(k, 1);
            score += 10;
            if (score > best) { best = score; window.localStorage.setItem("fn-best", best); }
            paint();
            break;
          }

          if (b.y - R > H) balls.splice(i, 1);
        }
        if (!balls.length) break;
      }

      if (!balls.length) {
        lives--;
        paint();
        if (lives <= 0) { over = 1.1; return; }
        serve();
      }
      if (!bricks.length) { level++; drops = []; paint(); build(); }

      for (var d = drops.length - 1; d >= 0; d--) {
        drops[d].y += 118 * dt;
        if (drops[d].y > pTop - 5 && drops[d].y < H - 2 &&
            Math.abs(drops[d].x - paddleX) <= half + 7) {
          spark(drops[d].x, drops[d].y, drops[d].kind.tint, 8);
          collect(drops[d].kind);
          drops.splice(d, 1);
        } else if (drops[d].y > H + 12) {
          drops.splice(d, 1);
        }
      }

      for (var q = sparks.length - 1; q >= 0; q--) {
        var s2 = sparks[q];
        s2.life -= dt;
        if (s2.life <= 0) { sparks.splice(q, 1); continue; }
        s2.vy += 300 * dt;
        s2.x += s2.vx * dt; s2.y += s2.vy * dt;
      }
    }

    function roundRect(x, y, w, h, r) {
      ctx.beginPath();
      ctx.moveTo(x + r, y);
      ctx.arcTo(x + w, y, x + w, y + h, r);
      ctx.arcTo(x + w, y + h, x, y + h, r);
      ctx.arcTo(x, y + h, x, y, r);
      ctx.arcTo(x, y, x + w, y, r);
      ctx.closePath();
    }

    function draw() {
      ctx.clearRect(0, 0, W, H);

      bricks.forEach(function (br) {
        ctx.fillStyle = "hsl(" + (208 - br.row * 30) + ", 62%, 60%)";
        roundRect(br.x, br.y, br.w, br.h, 2.5);
        ctx.fill();
      });

      sparks.forEach(function (s2) {
        ctx.globalAlpha = Math.min(s2.life * 3, 1);
        ctx.fillStyle = s2.tint;
        ctx.fillRect(s2.x - 1.2, s2.y - 1.2, 2.4, 2.4);
      });
      ctx.globalAlpha = 1;

      ctx.font = "700 8px -apple-system, system-ui, sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      drops.forEach(function (d) {
        ctx.fillStyle = d.kind.tint;
        roundRect(d.x - 8, d.y - 6, 16, 12, 3);
        ctx.fill();
        ctx.fillStyle = "#000";
        ctx.fillText(d.kind.glyph, d.x, d.y + 0.5);
      });

      // The name of whatever is currently running, centred in the empty middle
      // of the board — the app does this, and it is the only feedback that a
      // collected drop actually did something.
      var activeName = wide > 0 ? "Wide paddle" : slow > 0 ? "Slow ball" : null;
      if (activeName) {
        ctx.globalAlpha = Math.min(Math.max(wide, slow), 1);
        ctx.fillStyle = "#fff";
        ctx.font = "700 11px -apple-system, system-ui, sans-serif";
        ctx.fillText(activeName, W / 2, H * 0.62);
        ctx.globalAlpha = 1;
      }

      // A flat blue bar, matching the app. It used to carry a glow and a white
      // highlight strip, added back when the paddle was invisible — but the
      // paddle was invisible because it was being clipped, not because it was
      // too dim, so the decoration only made it look unlike the real game.
      var half = paddleW() / 2;
      var py = paddleY() - PADDLE_H / 2;
      ctx.fillStyle = "#0a84ff";
      roundRect(paddleX - half, py, half * 2, PADDLE_H, PADDLE_H / 2);
      ctx.fill();

      ctx.fillStyle = "#fff";
      balls.forEach(function (b) {
        ctx.beginPath();
        ctx.arc(b.x, b.y, R, 0, Math.PI * 2);
        ctx.fill();
      });

      if (over > 0) {
        ctx.fillStyle = "rgba(0,0,0,0.55)";
        ctx.fillRect(0, 0, W, H);
        ctx.fillStyle = "#fff";
        ctx.font = "620 15px -apple-system, system-ui, sans-serif";
        ctx.fillText("Game over", W / 2, H / 2);
      }
    }

    var onScreen = false;
    var last = 0;

    function frame(now) {
      if (!last) last = now;
      var dt = Math.min((now - last) / 1000, 1 / 30);
      last = now;
      if (measure()) reset();
      // Only simulate while the panel is actually open. Behind a shut notch the
      // board is clipped away, and running it there meant your run was always
      // several seconds further along than the one you last saw — exactly like
      // the app, which pauses the game when you close the notch.
      running = onScreen && !calm && screen.classList.contains("is-open");
      if (running && W) step(dt);
      if (onScreen && W) draw();
      requestAnimationFrame(frame);
    }

    if (measure()) reset();
    requestAnimationFrame(frame);

    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        onScreen = entries[0].isIntersecting;
      }, { threshold: 0.2 }).observe(screen);
    } else {
      onScreen = true;
    }
  }
})();
