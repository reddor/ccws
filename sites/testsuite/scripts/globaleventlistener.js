/* crash when a GlobalEventListener is declared locally within the request
   processevents-callback is not removed from thread in some cases, causing
   the method to be run with a freed class. 
   Easily reproducible with siege.*/
var g = new GlobalEventListener("Test", "GlobalEventListenerTest"); 

handler.onRequest = function(client) {
	try {
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