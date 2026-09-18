// Records every HTTP request the page makes, from inside the page.
//
// Why not devtools: the question is "how many requests, to whom, how fast, and
// which of them failed" for two different builds, compared. Reading that off a
// devtools screenshot is what produced the original report; this produces the
// same view as data. It also captures what devtools cannot label reliably - a
// fetch rejected by a failed CORS preflight has no status anywhere in the HAR,
// but the rejection itself is observable here as a TypeError.
//
// Both transports are wrapped because KDF WASM and the Dart app do not
// necessarily agree on one: package:http on web uses XMLHttpRequest, while
// wasm-bindgen uses fetch.
(function () {
  if (window.__BENCH) return;

  var t0 = performance.now();
  var events = [];
  var MAX = 20000;

  function now() { return (performance.now() - t0) / 1000; }

  function host(url) {
    try { return new URL(url, location.href).host; } catch (e) { return "?"; }
  }

  // The JSON-RPC method is the only thing that distinguishes a gap-scan probe
  // from a block poll, so it is worth digging out of the body.
  function describe(body) {
    if (typeof body !== "string") return null;
    if (body.length > 200000) return null;
    var parsed;
    try { parsed = JSON.parse(body); } catch (e) { return null; }
    var calls = Array.isArray(parsed) ? parsed : [parsed];
    var methods = [], addresses = [];
    for (var i = 0; i < calls.length; i++) {
      var call = calls[i];
      if (!call || typeof call !== "object") continue;
      if (call.method) methods.push(String(call.method));
      var params = call.params;
      if (Array.isArray(params)) {
        for (var j = 0; j < params.length; j++) {
          var p = params[j];
          if (typeof p === "string" && p.length === 42 && p.slice(0, 2) === "0x") {
            addresses.push(p.toLowerCase());
          } else if (p && typeof p === "object") {
            ["to", "from", "address"].forEach(function (k) {
              if (typeof p[k] === "string" && p[k].length === 42) {
                addresses.push(p[k].toLowerCase());
              }
            });
          }
        }
      }
      if (params && typeof params === "object" && !Array.isArray(params)) {
        // KDF's own RPC shape - useful for spotting the SDK's polling loops.
        if (params.coin) addresses.push("coin:" + params.coin);
      }
    }
    return { methods: methods, addresses: addresses, batch: calls.length };
  }

  function push(event) {
    if (events.length < MAX) events.push(event);
  }

  // wasm-bindgen does not hand fetch a string. Depending on how the transport
  // was built the body arrives as a typed array, an ArrayBuffer, or inside a
  // Request object - and a body we cannot read is a request we cannot attribute
  // to an RPC method or an address, which is most of what is being measured.
  function bodyText(body) {
    if (body == null) return null;
    if (typeof body === "string") return body;
    try {
      if (body instanceof ArrayBuffer) return new TextDecoder().decode(body);
      if (ArrayBuffer.isView(body)) {
        return new TextDecoder().decode(
          new Uint8Array(body.buffer, body.byteOffset, body.byteLength)
        );
      }
      if (body instanceof URLSearchParams) return body.toString();
    } catch (e) { /* fall through */ }
    return null;
  }

  function applyDetail(record, text) {
    var detail = describe(text);
    if (detail) {
      record.rpc = detail.methods;
      record.addrs = detail.addresses;
      record.batch = detail.batch;
    }
  }

  var realFetch = window.fetch;
  window.fetch = function (input, init) {
    var url = (typeof input === "string") ? input : (input && input.url) || String(input);
    var method = (init && init.method) || (input && input.method) || "GET";
    var body = init && init.body;
    var detail = describe(bodyText(body));
    var started = now();
    var record = {
      t: started, transport: "fetch", url: url, host: host(url),
      method: method, rpc: detail ? detail.methods : [],
      addrs: detail ? detail.addresses : [], batch: detail ? detail.batch : 1,
    };
    // A Request object hides its body behind an async reader, so fill the
    // detail in once it resolves. The record object is already in the array by
    // then, so mutating it is enough.
    if (!detail && input && typeof input !== "string" && typeof input.clone === "function") {
      try {
        input.clone().text().then(function (text) { applyDetail(record, text); },
                                  function () {});
      } catch (e) { /* not readable */ }
    }
    return realFetch.apply(this, arguments).then(function (response) {
      record.status = response.status;
      record.ok = response.ok;
      record.dt = now() - started;
      push(record);
      return response;
    }, function (error) {
      // No status exists here. A 429 on the CORS preflight and a dead socket
      // are the same object: a TypeError with an opaque message.
      record.status = 0;
      record.ok = false;
      record.failed = true;
      record.error = String(error && error.message || error).slice(0, 200);
      record.dt = now() - started;
      push(record);
      throw error;
    });
  };

  var RealXHR = window.XMLHttpRequest;
  function WrappedXHR() {
    var xhr = new RealXHR();
    var record = { transport: "xhr", rpc: [], addrs: [], batch: 1 };
    var realOpen = xhr.open;
    var realSend = xhr.send;
    xhr.open = function (method, url) {
      record.method = method;
      record.url = url;
      record.host = host(url);
      return realOpen.apply(xhr, arguments);
    };
    xhr.send = function (body) {
      record.t = now();
      applyDetail(record, bodyText(body));
      xhr.addEventListener("loadend", function () {
        record.status = xhr.status;
        record.ok = xhr.status >= 200 && xhr.status < 300;
        record.failed = xhr.status === 0;
        record.dt = now() - record.t;
        push(record);
      });
      return realSend.apply(xhr, arguments);
    };
    return xhr;
  }
  WrappedXHR.prototype = RealXHR.prototype;
  ["UNSENT", "OPENED", "HEADERS_RECEIVED", "LOADING", "DONE"].forEach(function (k, i) {
    WrappedXHR[k] = i;
  });
  window.XMLHttpRequest = WrappedXHR;

  window.__BENCH = {
    t0: t0,
    events: events,
    mark: function (label) { push({ t: now(), transport: "mark", url: label, host: "-", method: "MARK" }); },
    reset: function () { events.length = 0; t0 = performance.now(); },

    // A 1-second sliding window stepped every 50ms, per host. Peak rate is the
    // number in the report, so it has to be computed the same way for both arms.
    summary: function (opts) {
      opts = opts || {};
      var since = opts.since || 0;
      var rows = events.filter(function (e) { return e.transport !== "mark" && e.t >= since; });
      var byHost = {};
      rows.forEach(function (e) { (byHost[e.host] = byHost[e.host] || []).push(e); });

      function forHost(list) {
        var starts = list.map(function (e) { return e.t; }).sort(function (a, b) { return a - b; });
        var peak = 0, peakAt = 0;
        for (var t = starts[0]; t <= starts[starts.length - 1] + 0.05; t += 0.05) {
          var n = 0;
          for (var i = 0; i < starts.length; i++) if (starts[i] >= t && starts[i] < t + 1) n++;
          if (n > peak) { peak = n; peakAt = t; }
        }
        var statuses = {}, methods = {}, addrs = {};
        list.forEach(function (e) {
          var key = e.failed ? "FAILED(no status)" : String(e.status);
          statuses[key] = (statuses[key] || 0) + 1;
          (e.rpc || []).forEach(function (m) { methods[m] = (methods[m] || 0) + 1; });
          (e.addrs || []).forEach(function (a) { addrs[a] = 1; });
        });
        var span = starts[starts.length - 1] - starts[0];
        return {
          requests: list.length,
          first_at_s: +starts[0].toFixed(3),
          last_at_s: +starts[starts.length - 1].toFixed(3),
          span_s: +span.toFixed(3),
          peak_req_per_s: peak,
          peak_at_s: +peakAt.toFixed(2),
          in_first_second: starts.filter(function (s) { return s < starts[0] + 1; }).length,
          mean_req_per_s: span > 0 ? +(list.length / span).toFixed(2) : null,
          statuses: statuses,
          http_429: statuses["429"] || 0,
          failed_no_status: statuses["FAILED(no status)"] || 0,
          rpc_methods: methods,
          distinct_addresses: Object.keys(addrs).filter(function (a) { return a.slice(0, 2) === "0x"; }).length,
          addresses: Object.keys(addrs).filter(function (a) { return a.slice(0, 2) === "0x"; }).sort(),
        };
      }

      var out = { total_requests: rows.length, elapsed_s: +now().toFixed(2), per_host: {} };
      Object.keys(byHost).forEach(function (h) { out.per_host[h] = forHost(byHost[h]); });
      return out;
    },

    dump: function () { return JSON.stringify({ events: events }); },
  };

  console.log("[bench] recorder installed");
})();
