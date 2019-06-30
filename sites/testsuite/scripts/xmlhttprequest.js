handler.onRequest = function(client) {
	try {
		var r = new XMLHttpRequest();
	        let x = client.parameter.split("/");
		// lets not be a generic proxy
		if ((x[1] != "/dummy.txt") || x.length != 2) {
			client.disconnect();
			return;
		}
	        r.open("GET", client.parameter);
	        r.onreadystatechange = function(e) {
			if(r.readyState == 4) {
				client.send(r.responseText);
				client.disconnect();
			}
		};
	        r.onerror = function(e) {
			client.send("FAIL: XMLHttpRequest fired error " + e);
			client.disconnect();
		}
	        r.send();
	} catch(e) {
		client.send("FAIL: " + r.statusText);
		client.disconnect();
	}
}

let g = new GlobalEventListener('Test', 'XMLRequest'); g.addEventListener("ping", e => { g.globalDispatch("pong", "XMLHttpRequest Test")});
