handler.onRequest = function(client) {
	try {
        var g = new GlobalEventListener("Test", "GlboalEventListenerTest"); 
        let list = [];
        client.mimeType = "text/plain";
        g.addEventListener("pong", e => list.push(e.data));
        g.globalDispatch("ping", "test");
        system.setTimeout(() => {
            client.send(list.length == 0 ? "FAIL: no responses" : list.join("\n"));
            client.disconnect();
        }, 100);
    } catch(e) {
		client.send("FAIL: " + e.message);
		client.disconnect();
	}
}