// Signalling for online rooms (scripts/net.gd). Before two browsers can play peer to peer they
// swap WebRTC offers, answers and network candidates through a channel named after the room.
// On a page that provides window.AetherSignal (the shop's game page: a Supabase Realtime
// channel shared with Aether Drift; rooms are named "pw-CODE" so the games never meet) that is
// used; otherwise a BroadcastChannel, which only reaches other tabs of the same
// browser (enough for local tests). Godot polls the queue every frame (Net._process). Outgoing
// messages are batched five times a second, so a burst of network candidates stays well inside
// Supabase's per-client message limit.
//
// URL parameters, read from the game's own address or the page around it:
//   room=CODE   an invite link: open the multiplayer screen with this code filled in
//   pwnet=...   automated tests (see scripts/nettest.gd), only from the game's own address; they
//               use the local channel unless the list contains "sig"
(function () {
  function outer() {
    try { if (window.parent !== window && window.parent.location.href) return window.parent; } catch (e) {}
    return null;
  }
  function param(name, own) {
    const sources = own ? [window] : [window, outer()];
    for (const w of sources) {
      if (!w) continue;
      try {
        const v = new URLSearchParams(w.location.search).get(name);
        if (v) return v;
      } catch (e) {}
    }
    return "";
  }

  const net = {
    queue: [],
    out: [],
    timer: 0,
    ch: null,
    kind: "",
    open(room) {
      this.close();
      const deliver = (m) => {
        try { for (const one of JSON.parse(m)) this.queue.push(one); } catch (e) {}
      };
      const page = outer();
      const signal = page && page.AetherSignal;
      const test = param("pwnet", true);
      if (signal && (!test || /(^|,)sig(,|$)/.test(test))) {
        this.ch = signal.open("pw-" + room, deliver);
        this.kind = "online";
      } else {
        const bc = new BroadcastChannel("planar-room:" + room);
        bc.onmessage = (e) => deliver(e.data);
        this.ch = { send: (m) => bc.postMessage(m), close: () => bc.close(), ready: () => true };
        this.kind = "local";
      }
      this.timer = setInterval(() => this.flush(), 200);
    },
    send(text) { this.out.push(text); },
    flush() {
      if (!this.ch || !this.out.length || !this.ch.ready()) return;
      this.ch.send(JSON.stringify(this.out));
      this.out = [];
    },
    ready() { return !!(this.ch && this.ch.ready()); },
    poll() { const q = this.queue; this.queue = []; return JSON.stringify(q); },
    close() {
      clearInterval(this.timer);
      if (this.ch) this.ch.close();
      this.ch = null;
      this.queue = [];
      this.out = [];
    },
    roomFromUrl() { return param("room", false).toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8); },
    testArgs() { return param("pwnet", true); },
    copy(text) {
      const w = outer() || window;
      if (w.navigator.clipboard) w.navigator.clipboard.writeText(text).catch(() => w.prompt("Copy the room code:", text));
      else w.prompt("Copy the room code:", text);
    },
  };
  window.PlanarNet = net;
})();
