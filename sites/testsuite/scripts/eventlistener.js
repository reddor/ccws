
handler.addEventListener("connect", e => {
    e.client.addEventListener("data", e=> {
        let ev = new Event("customEvent");
        ev.client = e.client;
        ev.data = e.data;
        handler.dispatchEvent(ev);
    });
});

handler.addEventListener("customEvent", e => {
    e.client.send(e.data);
    e.client.disconnect();
});

let g = new GlobalEventListener('Test'); g.addEventListener("ping", e => { g.globalDispatch("pong", "EventListener Test")});
